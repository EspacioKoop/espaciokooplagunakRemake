"""Binary validation of Itsasargi and optional Bizi assets. Python standard library. MIT."""
from __future__ import annotations
import copy
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FORMAT={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT2':4,'MAT3':9,'MAT4':16}


def require(condition,message):
    if not condition:raise ValueError(message)


def unpack(raw):
    require(len(raw)>=28,'truncated GLB')
    magic,version,length=struct.unpack_from('<III',raw)
    require((magic,version,length)==(0x46546C67,2,len(raw)),'header/length')
    offset=12;chunks=[]
    while offset<len(raw):
        require(offset+8<=len(raw),'chunk header')
        size,kind=struct.unpack_from('<II',raw,offset);offset+=8
        require(size%4==0 and offset+size<=len(raw),'chunk boundary')
        chunks.append((kind,raw[offset:offset+size]));offset+=size
    require(len(chunks)==2 and chunks[0][0]==0x4E4F534A and chunks[1][0]==0x004E4942,'GLB chunks')
    return json.loads(chunks[0][1]),chunks[1][1]


def accessor(doc,binary,index):
    require(isinstance(index,int) and 0<=index<len(doc.get('accessors',[])),'accessor index')
    a=doc['accessors'][index]
    require('sparse' not in a,'unexpected sparse accessor')
    require(a.get('componentType') in FORMAT and a.get('type') in WIDTH,'accessor format')
    count=a.get('count',0);require(isinstance(count,int) and 0<count<5_000_000,'accessor count')
    v=doc['bufferViews'][a['bufferView']]
    code,width=FORMAT[a['componentType']];n=WIDTH[a['type']];size=width*n
    stride=v.get('byteStride',size)
    start=v.get('byteOffset',0)+a.get('byteOffset',0)
    require(stride>=size and stride%width==0,'stride')
    end=start+(count-1)*stride+size
    require(v.get('buffer',0)==0 and start>=v.get('byteOffset',0) and end<=v.get('byteOffset',0)+v['byteLength'] and end<=len(binary),'accessor bounds')
    result=[struct.unpack_from('<'+code*n,binary,start+i*stride) for i in range(count)]
    require(all(math.isfinite(v) for row in result for v in row),'nonfinite accessor')
    return result


def validate_doc(doc,binary):
    require(doc.get('asset',{}).get('version')=='2.0','glTF version')
    require(len(doc.get('buffers',[]))==1,'buffer count')
    require(not doc['buffers'][0].get('uri'),'external buffer')
    require(doc['buffers'][0]['byteLength']<=len(binary),'buffer size')
    require(not doc.get('images') and not doc.get('textures'),'unexpected texture dependency')
    nodes=doc.get('nodes',[]);require(nodes,'nodes missing')
    names=[n.get('name','') for n in nodes if n.get('name','').startswith('socket_')]
    require(len(names)==len(set(names)),'duplicate sockets')
    for n in nodes:
        for k in ('translation','rotation','scale','matrix'):
            require(all(math.isfinite(v) for v in n.get(k,[])),'nonfinite node transform')
        require(all(isinstance(i,int) and 0<=i<len(nodes) for i in n.get('children',[])),'child index')
    for m in doc.get('materials',[]):
        p=m.get('pbrMetallicRoughness',{})
        require(all(math.isfinite(v) and 0<=v<=1 for v in p.get('baseColorFactor',[1,1,1,1])),'base color')
        require(0<=p.get('metallicFactor',1)<=1 and 0<=p.get('roughnessFactor',1)<=1,'PBR ranges')
    triangles=0
    for mesh in doc.get('meshes',[]):
        for p in mesh['primitives']:
            require(p.get('mode',4)==4,'triangle primitive required')
            attrs=p['attributes'];require('POSITION' in attrs and 'NORMAL' in attrs,'positions/normals')
            positions=accessor(doc,binary,attrs['POSITION']);normals=accessor(doc,binary,attrs['NORMAL'])
            require(len(positions)==len(normals),'normal count')
            require(all(.85<sum(v*v for v in n)<1.15 for n in normals),'normal length')
            indices=[i[0] for i in accessor(doc,binary,p['indices'])]
            require(len(indices)%3==0,'triangle index count')
            require(all(isinstance(i,int) and 0<=i<len(positions) for i in indices),'index outside vertices')
            for start in range(0,len(indices),3):
                a,b,c=[positions[indices[start+j]] for j in range(3)]
                u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)]
                cross=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
                require(sum(x*x for x in cross)>1e-22,'degenerate triangle')
            require(0<=p['material']<len(doc['materials']),'material index')
            triangles+=len(indices)//3
    require(triangles>0,'empty geometry')
    for a in doc.get('animations',[]):
        for c in a['channels']:
            require(0<=c['target']['node']<len(nodes),'animation target')
            s=a['samplers'][c['sampler']]
            times=accessor(doc,binary,s['input']);values=accessor(doc,binary,s['output'])
            require(all(times[i][0]<times[i+1][0] for i in range(len(times)-1)),'animation time order')
            require(len(values)==len(times)*(3 if s.get('interpolation')=='CUBICSPLINE' else 1),'animation samples')
    return triangles,names


def negative_tests(raw):
    doc,binary=unpack(raw);count=0
    def rejected(fn):
        nonlocal count
        try:fn()
        except (ValueError,KeyError,IndexError,struct.error):count+=1;return
        raise AssertionError('Corrupt input was accepted')
    rejected(lambda:unpack(raw[:17]))
    rejected(lambda:unpack(b'BAD!'+raw[4:]))
    rejected(lambda:unpack(raw[:-4]))
    broken=copy.deepcopy(doc);broken['buffers'][0]['uri']='https://example.invalid/forbidden.bin'
    rejected(lambda:validate_doc(broken,binary))
    broken=copy.deepcopy(doc);broken['nodes'].append({'name':'socket_invalid','translation':[float('nan'),0,0]})
    rejected(lambda:validate_doc(broken,binary))
    broken=copy.deepcopy(doc);broken['nodes'] += [{'name':'socket_duplicate'},{'name':'socket_duplicate'}]
    rejected(lambda:validate_doc(broken,binary))
    broken=copy.deepcopy(doc);broken['accessors'][0]['count']=9_000_000
    rejected(lambda:accessor(broken,binary,0))
    broken=copy.deepcopy(doc);broken['materials'][0]['pbrMetallicRoughness']['roughnessFactor']=2
    rejected(lambda:validate_doc(broken,binary))
    broken=copy.deepcopy(doc);broken['images']=[{'uri':'private.png'}]
    rejected(lambda:validate_doc(broken,binary))
    return count


def validate_pack(path):
    pack=json.loads(path.read_text());assets=pack['assets'];ids=set();results=[]
    for e in assets:
        require(e['id'] not in ids,'duplicate asset id');ids.add(e['id'])
        for key in ('source','runtime','preview'):
            p=(ROOT/e[key]).resolve();require(p.is_relative_to(ROOT),'path escape');require(p.is_file(),'missing '+e[key])
        source=ROOT/e['source'];runtime=ROOT/e['runtime'];raw=runtime.read_bytes()
        require(hashlib.sha256(source.read_bytes()).hexdigest()==e['source_sha256'],'source hash')
        require(hashlib.sha256(raw).hexdigest()==e['sha256'],'GLB hash')
        require(len(raw)==e['bytes'],'GLB bytes')
        doc,binary=unpack(raw);triangles,sockets=validate_doc(doc,binary)
        require(triangles==e['triangles'],'triangle metadata')
        require(set(sockets)=={s['name'] for s in e['sockets']},'socket metadata')
        require(e['animations']==[a.get('name','') for a in doc.get('animations',[])],'animation metadata')
        require(all(math.isfinite(x) and x>0 for x in e['dimensions']),'dimensions')
        budget=50000 if e['category']=='ships' else 400000 if e['category']=='habitable_planets' else 35000
        require(triangles<=budget,'triangle budget')
        results.append({'id':e['id'],'triangles':triangles,'bytes':len(raw),'sockets':len(sockets)})
    if pack['pack']=='itsasargi':
        require(len(assets)==10,'10 models required')
        require({k:sum(e['category']==k for e in assets) for k in ('tools','weapons','ships')}=={'tools':6,'weapons':2,'ships':2},'category counts')
        require(all(e['animations'] for e in assets),'all mechanisms must export')
    if pack['pack']=='bizi':
        require(len(assets)==4 and len(pack['planets'])==2,'planet pairs')
        for planet in pack['planets']:
            require(planet['habitable'] is True and 60<=planet['radius_m']<=160,'compact habitable planet')
            require(len(planet['pois'])==14 and len(planet['resources'])==28,'POI/resource counts')
            require(len({p['id'] for p in planet['pois']})==14,'unique POI ids')
            pair=[e for e in assets if e['id'].startswith('bizi/'+planet['id']+'/')]
            require(len(pair)==2 and pair[0]['source']==pair[1]['source'],'common source')
            require(pair[0]['triangles']<pair[1]['triangles'],'orbit lower detail')
            require(all(e['radius_m']==planet['radius_m'] and e['habitable'] is True for e in pair),'coherent radius')
            for p in planet['pois']:
                require(abs(math.sqrt(sum(x*x for x in p['position']))-planet['radius_m'])<20,'POI on sphere')
                require(all(link in {q['id'] for q in planet['pois']} for link in p['links']),'POI link')
    return results


def main():
    results=validate_pack(ROOT/'game/assets/models/itsasargi_pack/manifest.json')
    planet=ROOT/'game/assets/models/bizi_planets/manifest.json'
    if planet.is_file():results+=validate_pack(planet)
    first=ROOT/'game/assets/models/itsasargi_pack/arc_welder.glb'
    negatives=negative_tests(first.read_bytes())
    out=ROOT/'build/itsasargi';out.mkdir(parents=True,exist_ok=True)
    report={'assets':results,'negative_tests':negatives,'total_triangles':sum(r['triangles'] for r in results),'total_bytes':sum(r['bytes'] for r in results)}
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('ASSET_VALIDATION_PASS',len(results),'assets',negatives,'negative tests',report['total_triangles'],'triangles')

if __name__=='__main__':main()
