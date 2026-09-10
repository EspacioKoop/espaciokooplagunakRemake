#!/usr/bin/env python3
"""Offline checks for exported Orbita GLB/source/catalogue integrity. Stdlib only."""
from __future__ import annotations
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
IDS={'karramarro_tug','erlea_miner','pulse_turret','containment_projector','technician_robot',
     'medic_robot','lapa_drone','aingira_probe','harri_moon','eraztun_giant','docking_collar','solar_array'}
ANIMATED=IDS-{'karramarro_tug','harri_moon','eraztun_giant','docking_collar'}
COMP={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}


def need(ok,message):
    if not ok: raise ValueError(message)


def finite_json(text):
    def invalid(value): raise ValueError('Non-finite JSON: '+value)
    return json.loads(text,parse_constant=invalid)


def parse_glb(data):
    need(len(data)>=28,'Truncated GLB')
    magic,version,total=struct.unpack_from('<III',data)
    need(magic==0x46546C67 and version==2 and total==len(data),'Invalid GLB header/length')
    offset=12; chunks=[]
    while offset<len(data):
        need(offset+8<=len(data),'Truncated chunk header')
        size,kind=struct.unpack_from('<II',data,offset); offset+=8
        need(size%4==0 and offset+size<=len(data),'Invalid chunk bounds')
        chunks.append((kind,data[offset:offset+size])); offset+=size
    need(len(chunks)==2 and chunks[0][0]==0x4E4F534A and chunks[1][0]==0x004E4942,'Expected JSON + embedded BIN')
    doc=finite_json(chunks[0][1]); binary=chunks[1][1]
    need(doc.get('asset',{}).get('version')=='2.0','Wrong glTF version')
    buffers=doc.get('buffers',[])
    need(len(buffers)==1 and 'uri' not in buffers[0],'External buffer forbidden')
    need(0<buffers[0]['byteLength']<=len(binary),'Invalid buffer size')
    need(not doc.get('images') and not doc.get('textures'),'Pack must not depend on textures')
    need(not doc.get('cameras') and not doc.get('skins'),'Unexpected camera/skin')
    need('KHR_draco_mesh_compression' not in doc.get('extensionsRequired',[]),'Unsupported compression')
    return doc,binary


def accessor(doc,binary,index):
    need(type(index) is int and 0<=index<len(doc['accessors']),'Bad accessor reference')
    a=doc['accessors'][index]
    need('sparse' not in a and a.get('componentType') in COMP and a.get('type') in WIDTH,'Unsupported accessor')
    vi=a.get('bufferView'); need(type(vi) is int and 0<=vi<len(doc['bufferViews']),'Bad bufferView')
    view=doc['bufferViews'][vi]; need(view.get('buffer',0)==0,'Bad buffer reference')
    fmt,size=COMP[a['componentType']]; width=WIDTH[a['type']]
    count=a['count']; need(type(count) is int and 0<count<=2000000,'Bad accessor count')
    stride=view.get('byteStride',size*width)
    start=view.get('byteOffset',0)+a.get('byteOffset',0)
    end=start+(count-1)*stride+size*width
    need(stride>=size*width and start>=0 and end<=len(binary),'Accessor exceeds BIN')
    need(end<=view.get('byteOffset',0)+view['byteLength'],'Accessor exceeds view')
    values=[struct.unpack_from('<'+fmt*width,binary,start+i*stride) for i in range(count)]
    need(all(math.isfinite(v) for row in values for v in row),'Non-finite accessor')
    return values


def inspect_mesh(doc,binary):
    count=0
    for mesh in doc.get('meshes',[]):
        for p in mesh['primitives']:
            need(p.get('mode',4)==4,'Non-triangle primitive')
            vertices=accessor(doc,binary,p['attributes']['POSITION'])
            need(len(vertices[0])==3,'Invalid position dimensions')
            need('NORMAL' in p['attributes'],'Missing normals')
            normals=accessor(doc,binary,p['attributes']['NORMAL'])
            need(len(normals)==len(vertices),'Normal count mismatch')
            need(all(abs(sum(v*v for v in n)-1)<.02 for n in normals),'Non-unit normal')
            indices=[row[0] for row in accessor(doc,binary,p['indices'])] if 'indices' in p else list(range(len(vertices)))
            need(len(indices)%3==0,'Incomplete triangle')
            need(all(type(i) is int and 0<=i<len(vertices) for i in indices),'Invalid triangle index')
            need(0<=p.get('material',-1)<len(doc.get('materials',[])),'Missing material')
            for offset in range(0,len(indices),3):
                a,b,c=(vertices[indices[offset+j]] for j in range(3))
                u=[b[i]-a[i] for i in range(3)]; v=[c[i]-a[i] for i in range(3)]
                cross=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
                need(sum(x*x for x in cross)>1e-20,'Degenerate triangle')
            count+=len(indices)//3
    need(0<count<150000,'Empty or oversized model')
    for anim in doc.get('animations',[]):
        need(anim.get('channels') and anim.get('samplers'),'Empty animation')
        for sampler in anim['samplers']:
            times=[v[0] for v in accessor(doc,binary,sampler['input'])]
            need(all(a<b for a,b in zip(times,times[1:])),'Unordered animation time')
            accessor(doc,binary,sampler['output'])
    return count


def self_test():
    # Negative tests must reject malformed envelopes without needing Blender.
    doc={'asset':{'version':'2.0'},'buffers':[{'byteLength':4}]}
    def pack(d):
        j=json.dumps(d).encode(); j+=b' '*((-len(j))%4)
        b=struct.pack('<II',len(j),0x4E4F534A)+j+struct.pack('<II',4,0x004E4942)+b'\0'*4
        return struct.pack('<III',0x46546C67,2,12+len(b))+b
    good=pack(doc); parse_glb(good)
    cases=[b'',good[:12],b'BAD!'+good[4:],good[:-1],good+b'\0',
           pack({'asset':{'version':'1.0'},'buffers':[{'byteLength':4}]}),
           pack({'asset':{'version':'2.0'},'buffers':[{'byteLength':4,'uri':'https://invalid.test/x'}]}),
           pack({'asset':{'version':'2.0'},'buffers':[{'byteLength':400}]}),
           pack({'asset':{'version':'2.0'},'buffers':[{'byteLength':4}],'images':[{'uri':'x.png'}]})]
    for data in cases:
        try: parse_glb(data)
        except (ValueError,KeyError,struct.error): continue
        raise AssertionError('Malformed GLB accepted')
    try: finite_json('{"bad":NaN}')
    except ValueError: pass
    else: raise AssertionError('NaN accepted')
    print('ORBITA_NEGATIVE_PASS cases=10')


def main():
    self_test()
    manifest=finite_json((ROOT/'game/assets/models/orbita_pack/manifest.json').read_text())
    entries=manifest['assets']
    need(manifest['schema']=='espaciokoop-asset-pack' and manifest['version']==1,'Manifest version')
    need(len(entries)==12 and {e['id'].split('/')[-1] for e in entries}==IDS,'Catalogue mismatch')
    total=0; results=[]
    for e in entries:
        ident=e['id'].split('/')[-1]
        need(e['id']=='orbita/'+ident and e['license']=='MIT','ID/license')
        need(e['runtime']=='game/assets/models/orbita_pack/'+ident+'.glb','Unsafe runtime path')
        need(e['source']=='art/blender/orbita_pack/'+ident+'.blend','Unsafe source path')
        for key,digest in [('runtime','sha256'),('source','source_sha256')]:
            p=ROOT/e[key]; need(p.is_file() and p.stat().st_size>1024,'Missing/empty '+key)
            need(hashlib.sha256(p.read_bytes()).hexdigest()==e[digest],'Hash mismatch '+key)
        doc,binary=parse_glb((ROOT/e['runtime']).read_bytes())
        triangles=inspect_mesh(doc,binary); total+=triangles
        need(triangles==e['triangles'],'Triangle manifest mismatch')
        names=[n.get('name','') for n in doc['nodes']]
        actual={n for n in names if n.startswith('socket_')}
        need(actual and actual=={s['name'] for s in e['sockets']},'Socket mismatch')
        need(all(not n.startswith('Preview_') for n in names),'Preview object leaked')
        need(all(math.isfinite(v) and v>0 for v in e['dimensions']),'Invalid dimensions')
        need(bool(doc.get('animations'))==(ident in ANIMATED),'Missing/unexpected animation')
        for n in doc['nodes']:
            for field in ('translation','rotation','scale','matrix'):
                need(all(math.isfinite(v) for v in n.get(field,[])),'Invalid transform')
        preview=ROOT/e['preview']
        need(preview.is_file() and preview.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'),'Missing preview')
        results.append({'id':e['id'],'triangles':triangles,'sockets':len(actual),'animations':e['animations'],'status':'pass'})
    report={'assets':len(entries),'triangles':total,'negative_tests':10,'results':results,'status':'pass'}
    out=ROOT/'build/orbita'; out.mkdir(parents=True,exist_ok=True)
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('ORBITA_VALIDATION_PASS assets=%d triangles=%d negative_tests=10'%(len(entries),total))

if __name__=='__main__': main()
