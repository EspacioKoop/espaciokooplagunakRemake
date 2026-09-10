"""Dependency-free validation of the Frontier GLBs; no network or user data.
Usage: python tests/frontier_pack/validate_pack.py [--root REPO]
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import re
import struct
from pathlib import Path

COMPONENTS={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
WIDTHS={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT2':4,'MAT3':9,'MAT4':16}
EXPECTED={'ships':4,'weapons':4,'avatars':3,'enemies':3,'worlds':5,'props':5}
RIGGED={'crew_navigator','crew_engineer','crew_synthetic','enemy_warden','enemy_crawler'}
CLIPS={**{x:{'Idle','Walk','Wave'} for x in RIGGED if x!='enemy_crawler'},
       'enemy_crawler':{'Scuttle'},'enemy_watcher':{'Hover'},'orbain_turret':{'Scan'},'cargo_crate':{'Open'}}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_glb(path):
    raw=path.read_bytes()
    require(len(raw)>=28,'Truncated GLB')
    magic,version,total=struct.unpack_from('<4sII',raw)
    require(magic==b'glTF' and version==2 and total==len(raw),'GLB header mismatch')
    cursor=12
    chunks=[]
    while cursor<len(raw):
        require(cursor+8<=len(raw),'Truncated chunk header')
        size,kind=struct.unpack_from('<II',raw,cursor)
        cursor+=8
        require(size%4==0 and cursor+size<=len(raw),'Invalid chunk bounds or alignment')
        chunks.append((kind,raw[cursor:cursor+size]))
        cursor+=size
    require(chunks and chunks[0][0]==0x4e4f534a,'First chunk must be JSON')
    doc=json.loads(chunks[0][1])
    binary=b''.join(data for kind,data in chunks if kind==0x004e4942)
    require(doc.get('asset',{}).get('version')=='2.0','Unsupported glTF version')
    require(len(doc.get('buffers',[]))==1,'Expected one embedded buffer')
    require('uri' not in doc['buffers'][0],'External buffer is forbidden')
    require(doc['buffers'][0]['byteLength']<=len(binary),'Buffer exceeds binary chunk')
    require(all('uri' not in image for image in doc.get('images',[])),'External image is forbidden')
    return doc,binary,raw


def accessor(doc,binary,index):
    accessors=doc.get('accessors',[])
    require(isinstance(index,int) and 0<=index<len(accessors),'Accessor reference out of bounds')
    item=accessors[index]
    require('sparse' not in item,'Sparse accessor not supported by this pack contract')
    require(item.get('componentType') in COMPONENTS and item.get('type') in WIDTHS,'Invalid accessor type')
    vi=item.get('bufferView',-1)
    require(isinstance(vi,int) and 0<=vi<len(doc.get('bufferViews',[])),'Missing buffer view')
    view=doc['bufferViews'][vi]
    require(view.get('buffer',0)==0,'Invalid buffer reference')
    fmt,size=COMPONENTS[item['componentType']]
    width=WIDTHS[item['type']]
    packed=size*width
    stride=view.get('byteStride',packed)
    offset=view.get('byteOffset',0)+item.get('byteOffset',0)
    count=item.get('count',0)
    require(isinstance(count,int) and count>0,'Empty accessor')
    require(stride>=packed and offset>=0,'Invalid accessor stride or offset')
    last=offset+(count-1)*stride+packed
    require(last<=len(binary) and last<=view.get('byteOffset',0)+view['byteLength'],'Accessor exceeds buffer view')
    rows=[struct.unpack_from('<'+fmt*width,binary,offset+i*stride) for i in range(count)]
    require(all(math.isfinite(v) for row in rows for v in row),'Non-finite accessor values')
    if item.get('normalized') and item['componentType']!=5126:
        maximum={5120:127,5121:255,5122:32767,5123:65535,5125:4294967295}[item['componentType']]
        rows=[tuple(max(-1,v/maximum) for v in row) for row in rows]
    return rows


def validate_asset(path,entry):
    doc,binary,raw=load_glb(path)
    require(hashlib.sha256(raw).hexdigest()==entry['sha256'],'GLB SHA-256 mismatch')
    nodes=doc.get('nodes',[])
    require(nodes and doc.get('scenes'),'Missing scene')
    for node in nodes:
        require(all(isinstance(c,int) and 0<=c<len(nodes) for c in node.get('children',[])),'Invalid child node')
        require(all(math.isfinite(x) for key in ['translation','rotation','scale','matrix'] for x in node.get(key,[])),'Non-finite node transform')
        require(all(x>0 for x in node.get('scale',[1,1,1])),'Zero or negative scale is forbidden')
        require('camera' not in node,'Studio camera leaked into model')
    # Detect cycles rather than hanging while traversing a malformed resource.
    visiting=set()
    visited=set()
    def visit(index):
        require(index not in visiting,'Cyclic scene graph')
        if index in visited:
            return
        visiting.add(index)
        for child in nodes[index].get('children',[]):
            visit(child)
        visiting.remove(index)
        visited.add(index)
    for i in range(len(nodes)):
        visit(i)
    names={n.get('name') for n in nodes}
    require(set(entry['sockets'])<=names,'Missing attachment socket')
    triangles=0
    vertices=0
    skinned_primitives=0
    for mesh in doc.get('meshes',[]):
        for p in mesh['primitives']:
            require(p.get('mode',4)==4,'Only triangles are allowed')
            attrs=p['attributes']
            positions=accessor(doc,binary,attrs['POSITION'])
            normals=accessor(doc,binary,attrs['NORMAL'])
            require(len(normals)==len(positions),'Normal count mismatch')
            require(all(.90<sum(x*x for x in normal)<1.10 for normal in normals),'Invalid normals')
            indices=[r[0] for r in accessor(doc,binary,p['indices'])]
            require(len(indices)%3==0 and all(0<=x<len(positions) for x in indices),'Invalid triangle indices')
            require(all(len(set(indices[k:k+3]))==3 for k in range(0,len(indices),3)),'Degenerate triangle indices')
            require(0<=p.get('material',-1)<len(doc.get('materials',[])),'Missing PBR material')
            triangles+=len(indices)//3
            vertices+=len(positions)
            if 'JOINTS_0' in attrs:
                joints=accessor(doc,binary,attrs['JOINTS_0'])
                weights=accessor(doc,binary,attrs['WEIGHTS_0'])
                require(len(joints)==len(weights)==len(positions),'Skin vertex count mismatch')
                require(all(abs(sum(row)-1)<.005 and min(row)>=0 for row in weights),'Skin weights are not normalized')
                skin_sizes=[len(s['joints']) for s in doc.get('skins',[])]
                require(skin_sizes and all(0<=j<max(skin_sizes) for row in joints for j in row),'Joint index exceeds skin')
                skinned_primitives+=1
    require(100<=triangles<=100000,'Unexpected triangle budget')
    require(triangles==entry['triangles'],'Triangle manifest mismatch')
    for skin in doc.get('skins',[]):
        require(all(0<=j<len(nodes) for j in skin['joints']),'Invalid skin node')
        inverse=accessor(doc,binary,skin['inverseBindMatrices'])
        require(len(inverse)==len(skin['joints']),'Inverse bind count mismatch')
    if entry['id'] in RIGGED:
        require(doc.get('skins') and skinned_primitives>0,'Expected skeletal skin')
        require(entry['joints']>=(9 if entry['id']=='enemy_crawler' else 18),'Missing rig bones')
    animation_names=set()
    channels=0
    for animation in doc.get('animations',[]):
        animation_names.add(animation.get('name','').rsplit('|',1)[-1])
        require(animation.get('channels'),'Empty animation')
        for channel in animation['channels']:
            sampler=animation['samplers'][channel['sampler']]
            times=[r[0] for r in accessor(doc,binary,sampler['input'])]
            require(len(times)>=2 and all(a<b for a,b in zip(times,times[1:])),'Invalid animation time sequence')
            require(times[0]>=0 and times[-1]>times[0],'Invalid animation duration')
            values=accessor(doc,binary,sampler['output'])
            factor=3 if sampler.get('interpolation')=='CUBICSPLINE' else 1
            require(len(values)==len(times)*factor,'Animation value count mismatch')
            require(0<=channel['target']['node']<len(nodes),'Animation targets missing node')
            require(channel['target']['path'] in ['translation','rotation','scale'],'Unexpected animation path')
            channels+=1
    require(CLIPS.get(entry['id'],set())<=animation_names,'Missing required animation clips: '+repr(animation_names))
    return {'id':entry['id'],'triangles':triangles,'exported_vertices':vertices,
            'animation_channels':channels,'skinned_primitives':skinned_primitives,'status':'passed'}


def validate(root):
    directory=root/'game/assets/models/frontier_pack'
    manifest=json.loads((directory/'manifest.json').read_text())
    require(manifest.get('format')=='lagunak-frontier-library' and manifest.get('version')==1,'Manifest format mismatch')
    entries=manifest['assets']
    require(len(entries)==manifest['asset_count']==24,'Expected 24 assets')
    require(len({e['id'] for e in entries})==24,'Duplicate asset IDs')
    require({key:sum(e['category']==key for e in entries) for key in EXPECTED}==EXPECTED,'Category inventory mismatch')
    results=[]
    for entry in entries:
        require(re.fullmatch('[a-z][a-z0-9_]{1,63}',entry['id']) is not None,'Invalid asset ID')
        expected_source='art/blender/frontier_pack/sources/'+entry['id']+'.blend'
        require(entry['source']==expected_source,'Unexpected source path')
        require(entry['glb']=='res://assets/models/frontier_pack/'+entry['id']+'.glb','Unexpected resource path')
        source=root/expected_source
        require(source.is_file() and source.stat().st_size>1000,'Missing Blender source')
        require(hashlib.sha256(source.read_bytes()).hexdigest()==entry['source_sha256'],'Blender source hash mismatch')
        require(entry['license']=='MIT' and entry['forward']=='-Z' and entry['up']=='+Y','Asset contract mismatch')
        require(all(math.isfinite(x) and x>.001 for x in entry['dimensions_m']),'Invalid dimensions')
        try:
            results.append(validate_asset(directory/(entry['id']+'.glb'),entry))
        except (ValueError,KeyError,IndexError,struct.error) as error:
            raise ValueError(entry['id']+': '+str(error)) from error
    report={'format':'lagunak-frontier-validation','version':1,'passed':True,'assets_checked':len(results),
        'triangles_total':sum(x['triangles'] for x in results),'assets':results,
        'scope':'GLB structure, buffer bounds, geometry, normals, materials, source hashes, skins, sockets, animation tracks. Not gameplay QA.'}
    (directory/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2])
    args=parser.parse_args()
    validate(args.root.resolve())
