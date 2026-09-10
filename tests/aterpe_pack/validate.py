"""Offline tests for all delivered Aterpe GLBs and topological sphere closure."""
from __future__ import annotations
import hashlib
import importlib.util
import json
from collections import Counter
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('lantegi_validation', ROOT / 'tests/lantegi_pack/validate.py')
V = importlib.util.module_from_spec(spec);spec.loader.exec_module(V)
require = V.require


def matrix(node):
    if 'matrix' in node:
        return np.array(node['matrix'],dtype=float).reshape((4,4),order='F')
    x,y,z,w = node.get('rotation',[0,0,0,1])
    result=np.eye(4)
    result[:3,:3]=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                            [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                            [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]) @ np.diag(node.get('scale',[1,1,1]))
    result[:3,3]=node.get('translation',[0,0,0])
    return result


def transforms(doc):
    parents={c:i for i,n in enumerate(doc['nodes']) for c in n.get('children',[])}
    cache={}
    def world(i):
        if i not in cache:cache[i]=(world(parents[i]) if i in parents else np.eye(4))@matrix(doc['nodes'][i])
        return cache[i]
    for i in range(len(doc['nodes'])):world(i)
    return cache,parents


def terrain_topology(doc,binary):
    matrices,parents=transforms(doc);lookup={};vertices=[];triangles=[];chunks=0
    for i,node in enumerate(doc['nodes']):
        if node.get('extras',{}).get('terrain_chunk'):chunks+=1
        if 'mesh' not in node:continue
        current=i;terrain=False
        while True:
            if doc['nodes'][current].get('name')=='Terrain':terrain=True;break
            if current not in parents:break
            current=parents[current]
        if not terrain:continue
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            points=V.accessor(doc,binary,primitive['attributes']['POSITION']).astype(float)
            points=(matrices[i]@np.column_stack((points,np.ones(len(points)))).T).T[:,:3]
            ids=[]
            for point in points:
                key=tuple(np.round(point,4))
                if key not in lookup:lookup[key]=len(vertices);vertices.append(point)
                ids.append(lookup[key])
            indices=V.accessor(doc,binary,primitive['indices']).ravel()
            triangles.extend(np.array(ids)[indices].reshape((-1,3)).tolist())
    require(chunks==96,'Expected 96 independently addressable terrain chunks')
    require(len(triangles)>40000,'Incomplete terrain')
    vertices=np.array(vertices);faces=np.array(triangles)
    edges=Counter(tuple(sorted((int(a),int(b)))) for f in faces for a,b in zip(f,np.roll(f,-1)))
    require(all(n==2 for n in edges.values()),'Open or non-manifold sphere seam')
    require(len(vertices)-len(edges)+len(faces)==2,'Terrain is not topological sphere')
    xyz=vertices[faces]
    normals=np.cross(xyz[:,1]-xyz[:,0],xyz[:,2]-xyz[:,0])
    require((np.einsum('ij,ij->i',normals,xyz.mean(axis=1))>0).all(),'Inward terrain faces')
    return {'vertices':len(vertices),'edges':len(edges),'triangles':len(faces),'chunks':chunks,'euler_characteristic':2}


def main():
    catalogue=json.loads((ROOT/'game/assets/models/aterpe_pack/manifest.json').read_text())
    require(catalogue.get('schema_version')==1 and len(catalogue['planets'])==2,'Planet catalogue')
    results=[]
    for entry in catalogue['planets']:
        require(entry['habitable'] is True and entry['radius_metres'] in (120,150),'Habitable compact planet')
        source=ROOT/entry['source']
        require(hashlib.sha256(source.read_bytes()).hexdigest()==entry['source_sha256'],'Source hash')
        require(len(entry['pois'])==16 and len({p['id'] for p in entry['pois']})==16,'Sixteen unique POI')
        require(sum('landing' in p['anchors'] for p in entry['pois'])==2,'Two landing decks per planet')
        visited={0};edges=entry['paths']
        while True:
            new=visited|{b for a,b in edges if a in visited}|{a for a,b in edges if b in visited}
            if new==visited:break
            visited=new
        require(len(visited)==16,'Disconnected POI walking graph')
        counts={};topology=None
        for lod in ('surface','approach','orbit'):
            e=entry['representations'][lod];blob=(ROOT/e['path']).read_bytes()
            require(hashlib.sha256(blob).hexdigest()==e['sha256'],'GLB hash')
            require(e['source_sha256']==entry['source_sha256'] and e['coordinate_scale']==1,'LOD source/scale divergence')
            doc,tris=V.validate_blob(blob);_,binary=V.decode(blob)
            require(tris==e['triangles'] and len(blob)==e['bytes'],'GLB metrics')
            require(len(blob)<40000000 and tris<500000,'Planet budget')
            counts[lod]=tris
            world,_=transforms(doc)
            named={n.get('name'):i for i,n in enumerate(doc['nodes'])}
            for p in entry['pois']:
                require(p['node_name'] in named,'Missing POI '+p['node_name'])
                actual=world[named[p['node_name']]][:3,3]
                require(np.allclose(actual,p['frame']['position'],atol=0.001),'POI changed between representations')
                for role,a in p['anchors'].items():
                    require(a['node_name'] in named,'Missing '+role+' anchor')
                    actual=world[named[a['node_name']]][:3,3]
                    require(np.allclose(actual,a['position'],atol=.001),'Anchor frame mismatch')
                    require(np.linalg.norm(actual)>entry['radius_metres']-12,'Buried anchor')
            if lod=='surface':topology=terrain_topology(doc,binary)
        require(counts['orbit']<counts['approach']<counts['surface'],'LODs must genuinely simplify')
        require((ROOT/entry['surface_scene']).is_file(),'Missing instantiable surface scene')
        for suffix in ('orbit','surface','landing'):
            require((ROOT/'docs/images/aterpe_pack'/f"{entry['slug']}_{suffix}.png").is_file(),'Missing actual preview')
        results.append({'planet':entry['slug'],'topology':topology,'triangles':counts,'pois':16})
    out=ROOT/'build/aterpe';out.mkdir(parents=True,exist_ok=True)
    (out/'validation.json').write_text(json.dumps(results,indent=2)+'\n')
    print('ATERPE_VALIDATE_PASS',json.dumps(results))


if __name__=='__main__':main()
