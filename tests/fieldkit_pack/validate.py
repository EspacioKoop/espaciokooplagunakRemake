"""Offline, standard-library-only validation for the ten Fieldkit models."""
from __future__ import annotations
import copy
import hashlib
import json
import math
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[2]
IDS=['giltza_hack_tool','kako_tether','argi_scanner','jostun_repair','ebaki_cutter','soros_medkit','tximista_carbine','txinparta_sidearm','enara_shuttle','hontz_corvette']
COMP={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}


def require(condition,message):
    if not condition:
        raise ValueError(message)


def unpack_glb(data):
    require(20<=len(data)<=32*1024*1024,'GLB size')
    require(struct.unpack_from('<III',data)==(0x46546C67,2,len(data)),'GLB header')
    offset=12
    chunks=[]
    while offset<len(data):
        require(offset+8<=len(data),'Truncated chunk')
        size,kind=struct.unpack_from('<II',data,offset)
        offset+=8
        require(size%4==0 and offset+size<=len(data),'Chunk bounds')
        chunks.append((kind,data[offset:offset+size]))
        offset+=size
    require(len(chunks)==2 and chunks[0][0]==0x4E4F534A and chunks[1][0]==0x004E4942,'Expected JSON/BIN chunks')
    return json.loads(chunks[0][1]),chunks[1][1]


def values(doc,binary,index):
    accessors=doc.get('accessors',[])
    require(isinstance(index,int) and 0<=index<len(accessors),'Accessor index')
    a=accessors[index]
    require('sparse' not in a,'Sparse accessor unsupported by contract')
    require(a.get('componentType') in COMP and a.get('type') in WIDTH,'Accessor format')
    count=a.get('count',0)
    require(isinstance(count,int) and 0<count<=2000000,'Accessor count')
    views=doc.get('bufferViews',[])
    vindex=a.get('bufferView',-1)
    require(isinstance(vindex,int) and 0<=vindex<len(views),'Buffer view missing')
    v=views[vindex]
    require(v.get('buffer')==0,'Unknown buffer')
    char,size=COMP[a['componentType']]
    width=WIDTH[a['type']]
    item=size*width
    stride=v.get('byteStride',item)
    require(isinstance(stride,int) and item<=stride<=252 and stride%size==0,'Accessor stride')
    voffset=v.get('byteOffset',0)
    aoffset=a.get('byteOffset',0)
    length=v.get('byteLength',0)
    require(all(isinstance(n,int) and n>=0 for n in (voffset,aoffset,length)),'Negative buffer bounds')
    require(voffset+length<=len(binary) and aoffset+(count-1)*stride+item<=length,'Accessor bounds')
    fmt='<'+char*width
    result=[struct.unpack_from(fmt,binary,voffset+aoffset+i*stride) for i in range(count)]
    require(all(math.isfinite(x) for row in result for x in row),'Nonfinite accessor')
    return result


def validate_doc(doc,binary):
    require(doc.get('asset',{}).get('version')=='2.0','glTF version')
    buffers=doc.get('buffers',[])
    require(len(buffers)==1 and 'uri' not in buffers[0],'External buffer prohibited')
    require(0<=len(binary)-buffers[0].get('byteLength',-10)<=3,'Buffer length mismatch')
    require(not doc.get('images') and not doc.get('textures'),'Pack must not require textures')
    nodes=doc.get('nodes',[])
    require(0<len(nodes)<150,'Node budget')
    names=[n.get('name','') for n in nodes if n.get('name','').startswith('socket_')]
    require(len(names)>=3 and len(set(names))==len(names),'Missing/duplicate sockets')
    require(all(n.isidentifier() for n in names),'Nonportable sockets')
    for node in nodes:
        for key in ('translation','rotation','scale','matrix'):
            require(all(isinstance(x,(int,float)) and math.isfinite(x) for x in node.get(key,[])),'Nonfinite transform')
        require(all(isinstance(c,int) and 0<=c<len(nodes) for c in node.get('children',[])),'Invalid child')
    parent={}
    for i,node in enumerate(nodes):
        for child in node.get('children',[]):
            require(child not in parent,'Multiple parents')
            parent[child]=i
    for i in range(len(nodes)):
        seen=set()
        while i in parent:
            require(i not in seen,'Node cycle')
            seen.add(i)
            i=parent[i]
    mats=doc.get('materials',[])
    require(1<=len(mats)<=12,'Material budget')
    triangle_count=0
    for mesh in doc.get('meshes',[]):
        for p in mesh['primitives']:
            require(p.get('mode',4)==4,'Only triangles supported')
            require(isinstance(p.get('material'),int) and 0<=p['material']<len(mats),'Missing material')
            attrs=p.get('attributes',{})
            require('POSITION' in attrs and 'NORMAL' in attrs,'Missing position/normal')
            pos=values(doc,binary,attrs['POSITION'])
            normals=values(doc,binary,attrs['NORMAL'])
            require(len(pos)==len(normals),'Normal count')
            require(all(.9<sum(x*x for x in n)<1.1 for n in normals),'Normal length')
            for a in attrs.values():
                values(doc,binary,a)
            index=[int(row[0]) for row in values(doc,binary,p['indices'])] if 'indices' in p else list(range(len(pos)))
            require(len(index)%3==0 and all(0<=i<len(pos) for i in index),'Index bounds')
            for i in range(0,len(index),3):
                a,b,c=(pos[index[i+j]] for j in range(3))
                u=[b[j]-a[j] for j in range(3)]
                v=[c[j]-a[j] for j in range(3)]
                cross=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
                require(sum(x*x for x in cross)>1e-22,'Degenerate triangle')
            triangle_count+=len(index)//3
    require(100<=triangle_count<=50000,'Triangle budget')
    clips=doc.get('animations',[])
    require(len(clips)==1 and clips[0].get('name')=='field_cycle','Missing field_cycle')
    require(bool(clips[0].get('channels')),'Empty clip')
    for animation in clips:
        for sampler in animation['samplers']:
            times=[row[0] for row in values(doc,binary,sampler['input'])]
            require(len(times)>1 and times[-1]>times[0] and all(b>a for a,b in zip(times,times[1:])),'Invalid animation timeline')
            output=values(doc,binary,sampler['output'])
            multiplier=3 if sampler.get('interpolation')=='CUBICSPLINE' else 1
            require(len(output)==len(times)*multiplier,'Animation sample count')
        for channel in animation['channels']:
            target=channel['target']
            require(0<=target['node']<len(nodes) and target['path'] in ('translation','rotation','scale'),'Invalid animation target')
            require(0<=channel['sampler']<len(animation['samplers']),'Animation sampler index')
    return triangle_count


def negative_tests(doc,binary):
    cases=[]
    def case(label,edit):
        bad=copy.deepcopy(doc)
        edit(bad)
        cases.append((label,bad,binary))
    case('version',lambda d:d['asset'].update(version='1.0'))
    case('external_buffer',lambda d:d['buffers'][0].update(uri='https://invalid.example/asset.bin'))
    case('external_texture',lambda d:d.update(images=[{'uri':'private.png'}]))
    case('invalid_child',lambda d:d['nodes'][0].update(children=[99999]))
    case('self_cycle',lambda d:d['nodes'][0].update(children=[0]))
    case('missing_animation',lambda d:d.update(animations=[]))
    case('invalid_transform',lambda d:d['nodes'][0].update(translation=[0,float('nan'),0]))
    case('view_bounds',lambda d:d['bufferViews'][0].update(byteOffset=10**9))
    case('accessor_count',lambda d:d['accessors'][0].update(count=10**9))
    case('missing_normals',lambda d:d['meshes'][0]['primitives'][0]['attributes'].pop('NORMAL'))
    case('missing_material',lambda d:d['meshes'][0]['primitives'][0].update(material=999))
    sockets=[i for i,n in enumerate(doc['nodes']) if n.get('name','').startswith('socket_')]
    case('duplicate_socket',lambda d:d['nodes'][sockets[1]].update(name=d['nodes'][sockets[0]]['name']))
    for label,bad,data in cases:
        try:
            validate_doc(bad,data)
        except (ValueError,KeyError,IndexError,struct.error):
            continue
        raise AssertionError('Accepted negative case: '+label)
    for data in (b'bad',b'glTF'+b'\0'*20):
        try:
            unpack_glb(data)
        except (ValueError,struct.error):
            continue
        raise AssertionError('Accepted corrupt container')
    return len(cases)+2


def main():
    path=ROOT/'game/assets/models/fieldkit_pack/manifest.json'
    manifest=json.loads(path.read_text(encoding='utf-8'))
    entries=manifest['assets']
    require([e['id'] for e in entries]==['fieldkit/'+s for s in IDS],'Exact ten asset IDs')
    require([sum(e['category']==c for e in entries) for c in ('tools','weapons','ships')]==[6,2,2],'Expected 6 tools + 2 weapons + 2 ships')
    total=0
    for entry in entries:
        for key,hash_key in (('runtime','sha256'),('source','source_sha256')):
            p=(ROOT/entry[key]).resolve()
            require(p.is_relative_to(ROOT.resolve()),'Escaping repository path')
            require(p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==entry[hash_key],'Hash mismatch: '+str(p))
        doc,binary=unpack_glb((ROOT/entry['runtime']).read_bytes())
        triangles=validate_doc(doc,binary)
        require(triangles==entry['triangles'],'Triangle manifest mismatch')
        sockets=[n.get('name') for n in doc['nodes'] if n.get('name','').startswith('socket_')]
        require(sockets==entry['sockets'] and entry['attachment_socket'] in sockets,'Attachment socket mismatch')
        require(entry['units']=='metres' and entry['license']=='MIT','Units/license')
        require((ROOT/entry['scene']).is_file(),'Missing Godot instance scene')
        require(all(math.isfinite(n) and n>0 for n in entry['dimensions']),'Invalid dimensions')
        if entry.get('preview'):
            png=(ROOT/entry['preview']).read_bytes()
            require(png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II',png,16)==(640,640),'Missing preview')
        total+=triangles
    doc,binary=unpack_glb((ROOT/entries[0]['runtime']).read_bytes())
    negatives=negative_tests(doc,binary)
    report={'assets':10,'tools':6,'weapons':2,'ships':2,'triangles':total,'negative_cases':negatives,
        'glb_bytes':sum(e['bytes'] for e in entries),'sockets':sum(len(e['sockets']) for e in entries)}
    output=ROOT/'build/fieldkit'
    output.mkdir(parents=True,exist_ok=True)
    (output/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('FIELDKIT_VALIDATION_PASS '+json.dumps(report),flush=True)


if __name__=='__main__':
    main()
