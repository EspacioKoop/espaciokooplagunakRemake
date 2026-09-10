"""Offline validation of delivered Blender/GLB planet assets. Standard library only."""
from __future__ import annotations
from collections import Counter
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import unittest

ROOT=Path(__file__).resolve().parents[2]
ASSETS=ROOT/'game/assets/models/bizigai_pack'
TYPES={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
WIDTHS={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}


def require(condition,message):
    if not condition: raise ValueError(message)


def read_glb(data):
    require(len(data)>=28,'Truncated GLB')
    magic,version,total=struct.unpack_from('<4sII',data)
    require(magic==b'glTF' and version==2 and total==len(data),'GLB header')
    offset=12; chunks=[]
    while offset<len(data):
        require(offset+8<=len(data),'Chunk header')
        length,kind=struct.unpack_from('<II',data,offset); offset+=8
        require(length%4==0 and offset+length<=len(data),'Chunk bounds/alignment')
        chunks.append((kind,data[offset:offset+length])); offset+=length
    require(len(chunks)==2 and chunks[0][0]==0x4e4f534a and chunks[1][0]==0x004e4942,'GLB chunks')
    doc=json.loads(chunks[0][1]); binary=chunks[1][1]
    require(doc['asset']['version']=='2.0','glTF version')
    require(len(doc.get('buffers',[]))==1 and 'uri' not in doc['buffers'][0],'External buffer')
    require(doc['buffers'][0]['byteLength']<=len(binary),'Buffer length')
    require(not doc.get('images') and not doc.get('textures'),'Unexpected textures')
    return doc,binary


def accessor(doc,binary,index):
    require(isinstance(index,int) and 0<=index<len(doc['accessors']),'Accessor index')
    a=doc['accessors'][index]
    require('sparse' not in a,'Unsupported sparse accessor')
    require(a['componentType'] in TYPES and a['type'] in WIDTHS,'Accessor type')
    require(isinstance(a['count'],int) and a['count']>0,'Accessor count')
    vi=a.get('bufferView',-1)
    require(0<=vi<len(doc.get('bufferViews',[])),'BufferView index')
    view=doc['bufferViews'][vi]
    fmt,unit=TYPES[a['componentType']]; width=WIDTHS[a['type']]; size=unit*width
    stride=view.get('byteStride',size); start=view.get('byteOffset',0)+a.get('byteOffset',0)
    require(stride>=size and stride%unit==0,'Accessor stride')
    require(start>=0 and start%unit==0,'Accessor offset')
    end=start+(a['count']-1)*stride+size
    require(end<=view.get('byteOffset',0)+view['byteLength'] and end<=len(binary),'Accessor bounds')
    result=[struct.unpack_from('<'+fmt*width,binary,start+i*stride) for i in range(a['count'])]
    if fmt=='f': require(all(math.isfinite(x) for row in result for x in row),'Non-finite accessor')
    return result


def geometry(doc,binary,check_closed=False):
    cache={}
    def values(i):
        if i not in cache: cache[i]=accessor(doc,binary,i)
        return cache[i]
    total=0; edges=Counter(); terrain_faces=0; smallest=1e20
    terrain_meshes={n['mesh'] for n in doc.get('nodes',[]) if n.get('name','').startswith('terrain_') and 'mesh' in n}
    for mi,mesh in enumerate(doc.get('meshes',[])):
        for prim in mesh['primitives']:
            require(prim.get('mode',4)==4,'Non-triangle primitive')
            p=values(prim['attributes']['POSITION'])
            require(all(len(v)==3 for v in p),'Position width')
            idx=[x[0] for x in values(prim['indices'])] if 'indices' in prim else list(range(len(p)))
            require(len(idx)%3==0 and all(isinstance(i,int) and 0<=i<len(p) for i in idx),'Triangle indices')
            if 'NORMAL' in prim['attributes']:
                normals=values(prim['attributes']['NORMAL'])
                require(len(normals)==len(p),'Normal count')
                require(all(.8<sum(x*x for x in n)<1.2 for n in normals),'Invalid normals')
            for k in range(0,len(idx),3):
                a,b,c=(p[idx[k+j]] for j in range(3))
                u=[b[j]-a[j] for j in range(3)]; v=[c[j]-a[j] for j in range(3)]
                cross=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
                area2=sum(x*x for x in cross)
                require(area2>1e-13,'Degenerate triangle')
                smallest=min(smallest,area2)
                if check_closed and mi in terrain_meshes:
                    # Weld material/normal splits and the shared boundaries of the six tiles.
                    verts=[tuple(round(x,3) for x in q) for q in (a,b,c)]
                    for j in range(3): edges[tuple(sorted((verts[j],verts[(j+1)%3])))]+=1
                    require(sum(cross[j]*a[j] for j in range(3))>0,'Inverted terrain triangle')
                    terrain_faces+=1
            total+=len(idx)//3
    if check_closed:
        require(len(terrain_meshes)==6,'Expected six closed-globe terrain tiles')
        require(edges and all(n==2 for n in edges.values()),'Open or non-manifold globe seam')
    return total,terrain_faces,smallest


def validate_manifest(manifest):
    require(manifest.get('schema')=='bizigai-planets' and manifest.get('version')==1,'Manifest schema')
    require(len(manifest.get('worlds',[]))==2,'Expected two worlds')
    all_ids=set(); summary=[]
    for world in manifest['worlds']:
        require(world['habitable'] is True and world['breathable_atmosphere'] is True,'Habitability contract')
        require(100<=world['radius_m']<=300,'Compact world radius')
        require(world['origin']==[0,0,0] and world['units']=='metres','Coordinate contract')
        source=ROOT/world['source']
        require(source.is_file() and source.stat().st_size>100000,'Missing editable source')
        require(hashlib.sha256(source.read_bytes()).hexdigest()==world['source_sha256'],'Source hash mismatch')
        require(len(world['pois'])==16,'POI count')
        for poi in world['pois']:
            require(poi['id'] not in all_ids,'Duplicate POI ID'); all_ids.add(poi['id'])
            require(len(poi['arrival_m'])==3 and all(math.isfinite(x) for x in poi['arrival_m']),'Arrival position')
        tris=[]
        for tier in ['orbital','approach','surface']:
            entry=world['representations'][tier]; path=ROOT/entry['path']; data=path.read_bytes()
            require(len(data)==entry['bytes'] and hashlib.sha256(data).hexdigest()==entry['sha256'],'GLB hash/size mismatch')
            doc,binary=read_glb(data)
            count,terrain_count,area=geometry(doc,binary,True)
            require(count==entry['triangles'],'Triangle manifest mismatch')
            require(terrain_count==12*entry['terrain_grid_per_face']**2,'Terrain grid budget')
            require(count<350000,'Excessive geometry budget')
            nodes={n.get('name'):n for n in doc.get('nodes',[])}
            require(len(nodes)==len(doc.get('nodes',[])),'Duplicate node names')
            for poi in world['pois']:
                require(poi['arrival_node'] in nodes and poi['focus_node'] in nodes,'Missing arrival/focus anchor')
                pos=nodes[poi['arrival_node']].get('translation',[0,0,0])
                require(max(abs(a-b) for a,b in zip(pos,poi['arrival_m']))<.002,'Anchor coordinate mismatch')
            collision_names=[name for name in nodes if name and name.endswith('-col')]
            require(len(collision_names)>=22 if tier=='surface' else not collision_names,'Collision representation contract')
            tris.append(count)
            summary.append({'world':world['id'],'tier':tier,'triangles':count,'terrain_triangles':terrain_count,'bytes':len(data),'minimum_area_squared':area})
        require(tris[0]<tris[1]<tris[2],'LOD triangle ordering')
    return summary


class NegativeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec=importlib.util.spec_from_file_location('bizigai_spec',ROOT/'art/blender/bizigai_pack/spec.py')
        cls.spec=importlib.util.module_from_spec(spec); spec.loader.exec_module(cls.spec)
        cls.data=(ASSETS/'lurga_orbital.glb').read_bytes()
        cls.doc,cls.binary=read_glb(cls.data)

    def test_truncated(self):
        with self.assertRaises(ValueError): read_glb(self.data[:20])
    def test_magic(self):
        with self.assertRaises(ValueError): read_glb(b'BAD!'+self.data[4:])
    def test_length(self):
        with self.assertRaises(ValueError): read_glb(self.data[:-4])
    def test_offset(self):
        d=copy.deepcopy(self.doc); d['accessors'][0]['byteOffset']=len(self.binary)+4
        with self.assertRaises(ValueError): accessor(d,self.binary,0)
    def test_count(self):
        d=copy.deepcopy(self.doc); d['accessors'][0]['count']=-1
        with self.assertRaises(ValueError): accessor(d,self.binary,0)
    def test_stride(self):
        d=copy.deepcopy(self.doc); d['bufferViews'][d['accessors'][0]['bufferView']]['byteStride']=1
        with self.assertRaises(ValueError): accessor(d,self.binary,0)
    def test_zero_direction(self):
        with self.assertRaises(ValueError): self.spec.surface_radius('lurga',(0,0,0))
    def test_nan_direction(self):
        with self.assertRaises(ValueError): self.spec.normalize((float('nan'),1,0))
    def test_world(self):
        with self.assertRaises((ValueError,KeyError)): self.spec.surface_radius('unknown',(1,0,0))
    def test_poi_index(self):
        for i in [-1,16,900]:
            with self.assertRaises(ValueError): self.spec.poi_direction(i)
    def test_axes(self):
        for p in [(1,2,3),(0,1,0),(0,-1,0)]:
            self.assertEqual(p,self.spec.blender_to_godot(self.spec.godot_to_blender(p)))
    def test_compact_complete_sphere(self):
        for world in ['lurga','elur']:
            for i in range(181):
                angle=i*math.pi/90
                r=self.spec.surface_radius(world,(math.sin(angle),math.cos(angle),0))
                self.assertTrue(180<r<270)


def main():
    manifest=json.loads((ASSETS/'manifest.json').read_text(encoding='utf-8'))
    summary=validate_manifest(manifest)
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(NegativeTests))
    if not result.wasSuccessful(): raise SystemExit(1)
    out=ROOT/'build/bizigai'; out.mkdir(parents=True,exist_ok=True)
    (out/'geometry-validation.json').write_text(json.dumps({'assets':summary,'negative_tests':result.testsRun},indent=2)+'\n')
    print('BIZIGAI_GEOMETRY_PASS worlds=2 glb=6 pois=32 negative_tests=%d'%result.testsRun)

if __name__=='__main__': main()
