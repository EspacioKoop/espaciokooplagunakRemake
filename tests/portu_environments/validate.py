"""Offline validation of Portu deliverables; standard-library only. MIT."""
from __future__ import annotations
import copy
import hashlib
import json
import math
import struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FORMATS={5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
IDS={'quarantine_clinic','hydroponic_garden','residential_lounge','memory_archive','communications_hub','cargo_lift_dock','reactor_service','repair_drydock'}


def require(value,message):
    if not value:raise ValueError(message)


def unpack(raw):
    require(len(raw)>28,'truncated file')
    require(struct.unpack_from('<III',raw)==(0x46546c67,2,len(raw)),'invalid GLB header')
    offset=12;chunks=[]
    while offset<len(raw):
        require(offset+8<=len(raw),'truncated chunk header')
        length,kind=struct.unpack_from('<II',raw,offset);offset+=8
        require(length%4==0 and offset+length<=len(raw),'invalid chunk boundary')
        chunks.append((kind,raw[offset:offset+length]));offset+=length
    require(len(chunks)==2 and chunks[0][0]==0x4e4f534a and chunks[1][0]==0x004e4942,'missing GLB chunks')
    return json.loads(chunks[0][1]),chunks[1][1]


def values(doc,binary,index):
    a=doc['accessors'][index];view=doc['bufferViews'][a['bufferView']]
    require('sparse' not in a,'unexpected sparse accessor')
    require(a['componentType'] in FORMATS and a['type'] in WIDTH,'unsupported accessor')
    code,width=FORMATS[a['componentType']];n=WIDTH[a['type']]
    require(isinstance(a['count'],int) and 0<a['count']<2_000_000,'accessor count')
    stride=view.get('byteStride',n*width);start=view.get('byteOffset',0)+a.get('byteOffset',0)
    end=start+(a['count']-1)*stride+n*width
    require(view.get('buffer',0)==0 and stride>=n*width and start>=view.get('byteOffset',0) and end<=view.get('byteOffset',0)+view['byteLength'] and end<=len(binary),'accessor overflow')
    result=[struct.unpack_from('<'+code*n,binary,start+i*stride) for i in range(a['count'])]
    require(all(math.isfinite(x) for row in result for x in row),'non-finite geometry')
    return result


def inspect(doc,binary):
    require(doc.get('asset',{}).get('version')=='2.0','glTF version')
    require(len(doc.get('buffers',[]))==1 and not doc['buffers'][0].get('uri'),'external buffer')
    require(not doc.get('images') and not doc.get('textures'),'external art dependency')
    nodes=doc.get('nodes',[]);require(nodes,'empty scene')
    names=[n.get('name','') for n in nodes]
    sockets=[n for n in names if n.startswith('socket_')]
    require(len(sockets)==len(set(sockets)),'duplicate sockets')
    require('door_left' in names and 'door_right' in names,'missing articulated door leaves')
    for node in nodes:
        for key in ('translation','rotation','scale','matrix'):
            require(all(math.isfinite(x) for x in node.get(key,[])),'non-finite transform')
        require(all(0<=i<len(nodes) for i in node.get('children',[])),'invalid child index')
    for material in doc.get('materials',[]):
        p=material.get('pbrMetallicRoughness',{})
        require(0<=p.get('metallicFactor',1)<=1 and 0<=p.get('roughnessFactor',1)<=1,'invalid PBR factor')
    tris=0
    for mesh in doc.get('meshes',[]):
        for p in mesh['primitives']:
            require(p.get('mode',4)==4,'not triangle geometry')
            positions=values(doc,binary,p['attributes']['POSITION']);normals=values(doc,binary,p['attributes']['NORMAL'])
            require(len(positions)==len(normals),'normal count')
            require(all(.85<sum(x*x for x in n)<1.15 for n in normals),'invalid normal length')
            indices=[x[0] for x in values(doc,binary,p['indices'])]
            require(len(indices)%3==0 and all(0<=i<len(positions) for i in indices),'invalid triangle indices')
            for k in range(0,len(indices),3):
                a,b,c=[positions[indices[k+j]] for j in range(3)]
                u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)]
                cross=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
                require(sum(x*x for x in cross)>1e-22,'degenerate triangle')
            require(0<=p['material']<len(doc['materials']),'invalid material reference')
            tris+=len(indices)//3
    require(1000<tris<180000,'environment triangle budget')
    return tris,sockets


def main():
    path=ROOT/'game/assets/models/portu_environments/manifest.json'
    doc=json.loads(path.read_text());require(doc['schema_version']==1 and doc['pack']=='portu','manifest schema')
    require({e['id'].split('/')[-1] for e in doc['assets']}==IDS and len(doc['assets'])==8,'exact eight environments')
    report=[];first=None
    for e in doc['assets']:
        for key in ('source','runtime','scene','preview'):
            p=(ROOT/e[key]).resolve();require(p.is_relative_to(ROOT) and p.is_file(),'missing/escaping '+key)
        raw=(ROOT/e['runtime']).read_bytes();g,b=unpack(raw);first=first or (raw,g,b)
        tris,sockets=inspect(g,b)
        require(tris==e['triangles'] and len(raw)==e['bytes'],'geometry metadata')
        require(set(sockets)=={s['name'] for s in e['sockets']},'socket metadata')
        require(hashlib.sha256(raw).hexdigest()==e['sha256'],'runtime SHA-256')
        require(hashlib.sha256((ROOT/e['source']).read_bytes()).hexdigest()==e['source_sha256'],'source SHA-256')
        require(e['units']=='metres' and e['license']=='MIT','authoring contract')
        for s in e['sockets']:
            require(len(s['position'])==3 and all(math.isfinite(x) for x in s['position']),'socket coordinates')
        require(all('socket_'+name in sockets for name in ['arrival','return','connect_front','connect_back','door_use','objective',*['route_'+str(i) for i in range(5)]]),'required destination anchors')
        report.append({'id':e['id'],'triangles':tris,'bytes':len(raw),'sockets':len(sockets)})
    negatives=0
    def rejects(fn):
        nonlocal negatives
        try:fn()
        except (ValueError,KeyError,IndexError,struct.error):negatives+=1;return
        raise AssertionError('Corrupt input accepted')
    raw,g,b=first
    rejects(lambda:unpack(raw[:13]));rejects(lambda:unpack(b'BAD!'+raw[4:]));rejects(lambda:unpack(raw[:-4]))
    bad=copy.deepcopy(g);bad['buffers'][0]['uri']='external.bin';rejects(lambda:inspect(bad,b))
    bad=copy.deepcopy(g);bad['nodes']+=[{'name':'socket_same'},{'name':'socket_same'}];rejects(lambda:inspect(bad,b))
    bad=copy.deepcopy(g);bad['nodes'][0]['translation']=[float('nan'),0,0];rejects(lambda:inspect(bad,b))
    bad=copy.deepcopy(g);bad['accessors'][0]['count']=5_000_000;rejects(lambda:inspect(bad,b))
    bad=copy.deepcopy(g);bad['images']=[{'uri':'forbidden.png'}];rejects(lambda:inspect(bad,b))
    out=ROOT/'build/portu';out.mkdir(parents=True,exist_ok=True)
    (out/'validation.json').write_text(json.dumps({'environments':report,'negative_cases':negatives},indent=2)+'\n')
    print('PORTU_VALIDATION_PASS environments=8 negative_cases='+str(negatives)+' triangles='+str(sum(r['triangles'] for r in report)))

if __name__=='__main__':main()
