#!/usr/bin/env python3
"""Offline contract/geometry tests for the ten-player-support batch. Stdlib only."""
from __future__ import annotations
import copy
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parent))
import validate as base

ROOT=Path(__file__).resolve().parents[2]
CATALOG=ROOT/'art/blender/orbita_pack/player_batch/catalog.json'
MANIFEST=ROOT/'game/assets/models/orbita_pack/player_batch/manifest.json'
EXPECTED={'argi_worklight','lagin_sampler','babes_shield','oreka_gravity_tool','izpi_binoculars',
          'arnasa_eva_pack','uhina_arc_emitter','ezpal_coil_dispenser','kimu_survey_ship','balea_rescue_ship'}
need=base.need


def validate_catalog(document):
    need(isinstance(document,dict),'Catalogue must be an object')
    need(document.get('schema')=='espaciokoop-player-batch-contract' and document.get('version')==1,'Contract version')
    rows=document.get('assets')
    need(isinstance(rows,list) and len(rows)==10,'Exactly ten catalogue entries required')
    need(all(isinstance(r,dict) for r in rows),'Entry must be an object')
    need({r.get('name') for r in rows}==EXPECTED,'Stable IDs differ or repeat')
    need({k:sum(r.get('category')==k for r in rows) for k in ('tools','weapons','ships')}=={'tools':6,'weapons':2,'ships':2},'Required 6+2+2 distribution')
    for r in rows:
        need(re.fullmatch('[a-z][a-z0-9_]*',r['name']) is not None,'Unsafe ID')
        required=r.get('required_sockets')
        need(isinstance(required,list) and required and len(required)==len(set(required)),'Invalid socket contract')
        need(all(isinstance(n,str) and re.fullmatch('socket_[a-z0-9_]+',n) for n in required),'Unsafe socket')
        need(isinstance(r.get('animated_nodes'),list) and r['animated_nodes'],'Articulation contract required')
        need(all(isinstance(n,str) and n.isidentifier() for n in r['animated_nodes']),'Bad articulated node')
        kind=r.get('attachment_kind')
        need(kind in ('hand','back','none'),'Unknown attachment kind')
        need((r.get('attachment_socket') in required) if kind!='none' else r.get('attachment_socket')=='','Invalid attachment socket')
        need((r['category']=='ships')==(kind=='none'),'Ships are not hand equipment')
    return rows


def negative_tests(document):
    base.self_test()
    cases=[]
    d=copy.deepcopy(document); d['assets']=d['assets'][:-1]; cases.append(d)
    d=copy.deepcopy(document); d['assets'][1]=copy.deepcopy(d['assets'][0]); cases.append(d)
    d=copy.deepcopy(document); d['assets'][0]['category']='weapons'; cases.append(d)
    d=copy.deepcopy(document); d['assets'][0]['attachment_socket']='socket_missing'; cases.append(d)
    d=copy.deepcopy(document); d['assets'][0]['required_sockets']=['socket_bad','socket_bad']; cases.append(d)
    d=copy.deepcopy(document); d['assets'][0]['name']='../escape'; cases.append(d)
    d=copy.deepcopy(document); d['assets'][0]['animated_nodes']=[]; cases.append(d)
    d=copy.deepcopy(document); d['assets'][0]['attachment_kind']='none'; d['assets'][0]['attachment_socket']=''; cases.append(d)
    for d in cases:
        try:
            validate_catalog(d)
        except (ValueError,KeyError,TypeError):
            continue
        raise AssertionError('Malformed equipment contract accepted')
    print('ORBITA_PLAYER_NEGATIVE_PASS cases=18')


def main():
    document=base.finite_json(CATALOG.read_text(encoding='utf-8'))
    rows=validate_catalog(document)
    negative_tests(document)
    manifest=base.finite_json(MANIFEST.read_text(encoding='utf-8'))
    need(manifest.get('schema')=='espaciokoop-asset-pack' and manifest.get('version')==1,'Manifest schema')
    need(manifest.get('pack')=='orbita_player_support','Wrong pack')
    entries=manifest['assets']
    need(len(entries)==10 and {e['id'] for e in entries}=={'orbita/'+n for n in EXPECTED},'Delivered asset inventory differs')
    recipes={r['name']:r for r in rows}
    results=[]
    for e in entries:
        ident=e['id'].split('/')[-1]
        row=recipes[ident]
        paths={'runtime':f'game/assets/models/orbita_pack/player_batch/{ident}.glb',
               'source':f'art/blender/orbita_pack/player_batch/{ident}.blend',
               'preview':f'docs/images/orbita_pack/player_batch/{ident}.png'}
        for k,value in paths.items():
            need(e.get(k)==value,'Noncanonical '+k+' path: '+ident)
            need((ROOT/value).is_file(),'Missing '+k+': '+ident)
        need(e.get('resource')=='res://'+paths['runtime'][5:],'Godot resource path mismatch')
        need(e.get('category')==row['category'] and e.get('license')=='MIT','Category/license mismatch')
        need(e.get('units')=='metres','Metric scale required')
        need(e.get('attachment_socket')==row['attachment_socket'] and e.get('attachment_kind')==row['attachment_kind'],'Attachment metadata mismatch')
        for key,hash_key in [('runtime','sha256'),('source','source_sha256')]:
            data=(ROOT/e[key]).read_bytes()
            need(len(data)>1024,'Empty asset '+ident)
            need(hashlib.sha256(data).hexdigest()==e[hash_key],'Hash mismatch '+ident+' '+key)
        doc,binary=base.parse_glb((ROOT/e['runtime']).read_bytes())
        triangles=base.inspect_mesh(doc,binary)
        need(triangles==e['triangles'],'Triangle count mismatch '+ident)
        nodes=doc['nodes']
        names=[n.get('name','') for n in nodes]
        need(ident in names,'Root missing '+ident)
        sockets={n for n in names if n.startswith('socket_')}
        need(set(row['required_sockets']).issubset(sockets),'Required socket missing '+ident)
        need(sockets=={s['name'] for s in e['sockets']},'Socket metadata differs '+ident)
        need(all(names.count(n)==1 for n in sockets),'Duplicate socket '+ident)
        need(set(row['animated_nodes']).issubset(names),'Articulated pivot missing '+ident)
        need(not any(n.startswith('Preview_') for n in names),'Preview rig leaked '+ident)
        targets={nodes[c['target']['node']]['name'] for a in doc.get('animations',[]) for c in a['channels']}
        need(set(row['animated_nodes']).issubset(targets),'Animation not targeting its contracted parts '+ident)
        need(len(doc.get('animations',[]))==1,'Expected one mechanical cycle '+ident)
        limit=50 if row['category']=='ships' else 2
        need(len(e['dimensions'])==3 and all(0<d<=limit for d in e['dimensions']),'Invalid metric dimensions '+ident)
        need(e['status']=='exported_not_gameplay_integrated','Do not claim gameplay integration')
        need((ROOT/e['preview']).read_bytes().startswith(b'\x89PNG\r\n\x1a\n'),'Invalid technical preview')
        results.append({'id':e['id'],'category':e['category'],'triangles':triangles,'sockets':len(sockets),'animations':len(doc['animations']),'status':'pass'})
    # The first twelve remain a distinct, independently verifiable manifest.
    original=base.finite_json((ROOT/'game/assets/models/orbita_pack/manifest.json').read_text())
    need(len(original['assets'])==12,'Original batch inventory changed')
    need(not {e['id'] for e in original['assets']} & {e['id'] for e in entries},'Duplicate library ID')
    for e in original['assets']:
        for key,hash_key in [('runtime','sha256'),('source','source_sha256')]:
            need(hashlib.sha256((ROOT/e[key]).read_bytes()).hexdigest()==e[hash_key],'Original batch no longer matches its hashes')
    report={'status':'pass','assets':10,'library_assets':22,'categories':{'tools':6,'weapons':2,'ships':2},
            'triangles':sum(r['triangles'] for r in results),'sockets':sum(r['sockets'] for r in results),
            'animations':sum(r['animations'] for r in results),'negative_tests':18,'results':results}
    out=ROOT/'build/orbita'; out.mkdir(parents=True,exist_ok=True)
    (out/'player-validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('ORBITA_PLAYER_VALIDATION_PASS assets=10 library=22 triangles='+str(report['triangles'])+' negative_tests=18')


if __name__=='__main__':
    main()
