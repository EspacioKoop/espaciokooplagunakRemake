"""Reproducible visual catalogue of real Git-versioned 3D assets. MIT.

Reads pack manifests and GLB/PNG blobs, never executes a pack's Python or .blend.
Only --render-missing imports Blender, to photograph GLBs lacking individual art.
The catalogue is derived documentation, NOT a second gameplay/metadata authority.
"""
from __future__ import annotations
import argparse
import hashlib
import html
import io
import json
import os
import re
import struct
import subprocess
import sys
from pathlib import Path, PurePosixPath
from urllib.parse import quote
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
REPO = 'EspacioKoop/espaciokooplagunakRemake'
WEB = 'https://github.com/' + REPO
RAW = 'https://raw.githubusercontent.com/' + REPO
CATEGORIES = {'tools':'Herramientas', 'weapons':'Armas ficticias', 'ships':'Naves',
    'avatars':'Avatares y tripulación', 'enemies':'Enemigos y drones',
    'planets':'Planetas y lunas', 'environments':'Entornos e interiores',
    'props':'Utilería e infraestructura', 'other':'Otros recursos'}
ALIASES = {'habitable_planets':'planets','worlds':'planets','characters':'avatars',
    'crew':'avatars','robots':'avatars','infrastructure':'props','modules':'props',
    'equipment':'tools','interiors':'environments','environment':'environments',
    'structures':'props','drones':'enemies'}
BASE = {'ships':'itsaso transport sentinel', 'planets':'planet asteroid',
    'avatars':'crew', 'environments':'bridge_room engineering_room quarters_room cargo_room mess_room medbay_room hallway',
    'props':'anomaly beacon station chair console crate reactor'}


def need(ok, message):
    if not ok:
        raise ValueError(message)


def path(value: str, prefixes=()) -> str:
    need(isinstance(value,str) and value and '\\' not in value and '\x00' not in value, 'Invalid path')
    value = 'game/' + value[6:] if value.startswith('res://') else value
    parts = PurePosixPath(value)
    need(bool(parts.parts) and not parts.is_absolute() and '..' not in parts.parts and ':' not in value and '%' not in value, 'Unsafe path: '+value)
    need(not prefixes or any(value.startswith(p) for p in prefixes), 'Out-of-scope path: '+value)
    return parts.as_posix()


def slug(value):
    need(isinstance(value,str) and re.fullmatch(r'[a-zA-Z0-9_/-]+',value) is not None, 'Invalid asset ID')
    need(not any(x in ('','..','.') for x in value.split('/')), 'Invalid ID components')
    return value.replace('/','--')


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def git(*args):
    return subprocess.check_output(['git',*args],cwd=ROOT,stderr=subprocess.PIPE,timeout=60)


def resolve(ref):
    need(re.fullmatch(r'(origin/[A-Za-z0-9_./-]+|[a-f0-9]{40})',ref) is not None and '..' not in ref, 'Unsafe ref')
    try:
        return git('rev-parse','--verify',ref+'^{commit}').decode().strip()
    except subprocess.CalledProcessError:
        return None


def exists(revision, name):
    if not revision:
        return False
    try:
        git('cat-file','-e',revision+':'+path(name))
        return True
    except subprocess.CalledProcessError:
        return False


def blob(revision, name):
    need(re.fullmatch('[a-f0-9]{40}',revision) is not None, 'Unpinned blob read')
    name = path(name)
    size = int(git('cat-file','-s',revision+':'+name))
    need(0 < size <= 128*1024*1024, 'Empty or oversized blob')
    return git('show',revision+':'+name)


def url(revision, name, raw=False):
    return (RAW if raw else WEB+'/blob')+'/'+revision+'/'+quote(path(name),safe='/')


def glb(raw):
    need(len(raw)>=28, 'Truncated GLB')
    magic,version,length = struct.unpack_from('<III',raw)
    need((magic,version,length)==(0x46546c67,2,len(raw)), 'Invalid GLB header')
    size,kind = struct.unpack_from('<II',raw,12)
    need(kind==0x4e4f534a and size%4==0 and 20+size<=len(raw), 'Invalid GLB JSON chunk')
    data=json.loads(raw[20:20+size])
    need(data.get('asset',{}).get('version')=='2.0', 'Wrong glTF version')
    for entry in data.get('buffers',[])+data.get('images',[]):
        need(not entry.get('uri') or entry['uri'].startswith('data:'), 'External GLB dependency')
    need(data.get('meshes'), 'GLB has no meshes')
    return data


def png_info(raw):
    with Image.open(io.BytesIO(raw)) as image:
        need(image.format in ('PNG','JPEG','WEBP'), 'Unsupported photograph format')
        size=image.size
        need(64<=size[0]<=8192 and 64<=size[1]<=8192, 'Invalid photograph dimensions')
        image.verify()
    return list(size)


def selected_nodes(data, group):
    nodes=data.get('nodes',[])
    roots=[i for i,n in enumerate(nodes) if n.get('name')==group]
    need(len(roots)==1, 'Submodel root not unique: '+str(group))
    todo=roots[:];seen=set()
    while todo:
        i=todo.pop()
        need(isinstance(i,int) and 0<=i<len(nodes), 'Invalid child index')
        need(i not in seen, 'Repeated node/cycle in subtree')
        seen.add(i);todo.extend(nodes[i].get('children',[]))
    return seen


def stats(data, group=None):
    nodes=data.get('nodes',[])
    selected=selected_nodes(data,group) if group else set(range(len(nodes)))
    meshes={nodes[i]['mesh'] for i in selected if 'mesh' in nodes[i]}
    need(meshes, 'Submodel has no geometry')
    triangles=0;materials=set()
    for index in meshes:
        for primitive in data['meshes'][index]['primitives']:
            need(primitive.get('mode',4)==4, 'Non-triangle primitive')
            count=data['accessors'][primitive['indices']]['count'] if 'indices' in primitive else data['accessors'][primitive['attributes']['POSITION']]['count']
            need(count>0 and count%3==0, 'Invalid triangle count')
            triangles+=count//3
            if 'material' in primitive: materials.add(primitive['material'])
    sockets=[nodes[i]['name'] for i in sorted(selected) if nodes[i].get('name','').lower().startswith('socket_')]
    animations=[a.get('name','unnamed') for a in data.get('animations',[]) if any(c.get('target',{}).get('node') in selected for c in a.get('channels',[]))]
    return {'triangles':triangles, 'triangle_scope':'selected_submodel' if group else 'unique_referenced_meshes',
        'materials':[data['materials'][i].get('name','material_'+str(i)) for i in sorted(materials)],
        'sockets':sockets, 'animations_gltf':animations, 'has_skin':any('skin' in nodes[i] for i in selected)}


def records(spec, document):
    mode=spec.get('adapter','assets')
    if mode=='groups':
        return [({'id':spec['id']+'/'+name,'title':spec.get('titles',{}).get(name,name.replace('_',' ').capitalize()),
            'runtime':spec['runtime'],'source':spec['source'],'group':name,
            'category':spec.get('category','environments')}, '/submodels/'+str(i) if document.get('submodels')==spec['groups'] else None)
            for i,name in enumerate(spec['groups'])]
    entries=document.get('assets') if mode=='assets' else document.get('models')
    need(isinstance(entries,list) and entries, 'Manifest does not contain asset records: '+spec['id'])
    result=[]
    for i,original in enumerate(entries):
        entry=dict(original)
        ident=entry.get('id',entry.get('name'))
        need(isinstance(ident,str), 'Missing ID')
        if mode=='base' and ident not in spec['models']:continue
        if '/' not in ident:ident=spec.get('namespace',spec['id'])+'/'+ident
        entry['source_id']=entry.get('id',entry.get('name'))
        entry['id']=ident
        runtime=entry.get('runtime',entry.get('glb',entry.get('file')))
        need(isinstance(runtime,str), 'Missing runtime: '+ident)
        if '/' not in runtime:runtime=str(PurePosixPath(spec['manifest']).parent/runtime)
        entry['runtime']=path(runtime,('game/assets/models/',))
        entry['source']=entry.get('source',spec.get('source'))
        entry['title']=spec.get('titles',{}).get(ident.split('/')[-1],entry.get('title',ident.split('/')[-1].replace('_',' ').capitalize()))
        result.append((entry,'/'+('models' if mode=='base' else 'assets')+'/'+str(i)))
    if 'expected_count' in spec:need(len(result)==spec['expected_count'], 'Unexpected model count: '+spec['id'])
    return result


def category(entry):
    raw=entry.get('category')
    if raw is None and entry['id'].startswith('base/'):
        name=entry['id'].split('/')[-1]
        raw=next((k for k,v in BASE.items() if name in v.split()),'other')
    raw=ALIASES.get(raw,raw)
    return raw if raw in CATEGORIES else 'other'


def photo(entry, spec, revision, runtime_bytes, render_missing):
    candidates=[entry.get('preview')]
    if spec.get('preview_directory'):
        candidates.append(spec['preview_directory']+'/'+entry['id'].split('/')[-1]+'.png')
    for candidate in candidates:
        if not candidate:continue
        candidate=path(candidate,('docs/images/',))
        if PurePosixPath(candidate).stem in ('overview','catalogue','gallery'):continue
        if exists(revision,candidate):
            raw=blob(revision,candidate)
            return {'path':candidate,'revision':revision,'url':url(revision,candidate,True),
                'kind':'repository_model_render','sha256':digest(raw),'size_px':png_info(raw)}
    target='docs/images/asset_library/'+slug(entry['id'])+'.png'
    proof=ROOT/(target+'.json')
    expected={'runtime_sha256':digest(runtime_bytes),'group':entry.get('group'),'renderer_version':1}
    current=json.loads(proof.read_text()) if proof.is_file() else None
    if current!=expected or not (ROOT/target).is_file():
        need(render_missing, 'Missing/stale individual photo: '+entry['id']+'; run --render-missing')
        from render import photograph
        import tempfile
        with tempfile.TemporaryDirectory(prefix='asset-photo-') as folder:
            model=Path(folder)/'model.glb';model.write_bytes(runtime_bytes)
            photograph(model,ROOT/target,entry.get('group'))
        proof.write_text(json.dumps(expected,sort_keys=True,indent=2)+'\n')
    raw=(ROOT/target).read_bytes()
    return {'path':target,'revision':None,'url':None,'kind':'blender_glb_render',
        'sha256':digest(raw),'size_px':png_info(raw),'runtime_sha256':expected['runtime_sha256'],
        'group':expected['group']}


def make_asset(spec, revision, main, entry, pointer, render_missing):
    ident=entry['id'];slug(ident)
    source=path(entry.get('source'),('art/blender/',))
    need(source.endswith('.blend'), 'Source is not editable Blender')
    runtime=path(entry['runtime'],('game/assets/models/',))
    source_raw=blob(revision,source);runtime_raw=blob(revision,runtime)
    data=glb(runtime_raw)
    for key,raw in (('source_sha256',source_raw),('sha256',runtime_raw)):
        if entry.get(key):need(entry[key]==digest(raw),'Manifest hash mismatch: '+ident+' '+key)
    measured=stats(data,entry.get('group'))
    if entry.get('triangles') is not None and not entry.get('group'):
        need(measured['triangles']==entry['triangles'],'Manifest triangle mismatch: '+ident)
    photograph=photo(entry,spec,revision,runtime_raw,render_missing)
    in_main=exists(main,runtime) and git('rev-parse',main+':'+runtime)==git('rev-parse',revision+':'+runtime)
    dimensions=entry.get('dimensions',entry.get('dimensions_m'))
    if dimensions is None and entry.get('dimensions_blender_xyz'):
        x,y,z=entry['dimensions_blender_xyz'];dimensions=[x,z,y]
    links={key:url(revision,value) for key,value in [('source',source),('runtime',runtime),('manifest',spec['manifest'])]}
    for key in ('scene','guide','viewer'):
        value=entry.get(key,spec.get(key))
        if value and exists(revision,path(value)):
            links[key]=url(revision,value)
    return {'id':ident,'pack':spec['id'],'source_id':entry.get('source_id',entry.get('name',ident)),
        'title':entry['title'],'version':entry.get('version',1),'category':category(entry),
        'description':entry.get('description',spec.get('description','Recurso de biblioteca; consultar su guía.')),
        'source':source,'runtime':runtime,'resource':'res://'+runtime.removeprefix('game/'),
        'group':entry.get('group'),'revision':revision,
        'manifest':{'path':spec['manifest'],'revision':revision,'record_pointer':pointer,
            'record_is_adapter':spec.get('adapter')=='groups'},
        'preview':photograph,'links':links,'card':'docs/asset_library/models/'+slug(ident)+'.md',
        'availability':{'files_present':True,'in_main_at_snapshot':in_main,
            'catalogue_validation':'files_glb_header_hashes_and_real_photo_checked',
            'godot_validation':'consult_pack_pr_and_evidence','gameplay_integration':'not_inferred'},
        'source_sha256':digest(source_raw),'runtime_sha256':digest(runtime_raw),'runtime_bytes':len(runtime_raw),
        'units':entry.get('units',spec.get('units','not_declared')),
        'axes':entry.get('axes','glTF +Y up, -Z forward'),
        'dimensions_xyz':dimensions,'pivot':entry.get('pivot','consult_source_and_sockets'),
        'license':entry.get('license',spec.get('license','MIT')),
        'collision':entry.get('collision','consult_pack'),'lod':entry.get('lod','consult_pack'),
        'habitable':entry.get('habitable',False),'representation':entry.get('representation'),
        'radius_m':entry.get('radius_m'),'statistics':measured,
        'declared_sockets':entry.get('sockets',[]),'declared_status':entry.get('status'),
        'pull_request':spec.get('pull_request'),'known_limits':spec.get('limits','No atribuye mecánicas nuevas; consultar documentación del pack.')}


def image_link(asset, document):
    preview=asset['preview']
    return preview['url'] or Path(os.path.relpath(ROOT/preview['path'],(ROOT/document).parent)).as_posix()


def text(value):
    return html.escape(str(value),quote=True).replace('|','&#124;').replace('\n',' ')


def card(asset):
    a=asset; s=a['statistics'];image=image_link(a,a['card'])
    title=text(a['title']); links=' · '.join(f'[{k.title()}]({v})' for k,v in a['links'].items())
    status='Archivo presente en main al inventariar' if a['availability']['in_main_at_snapshot'] else 'Publicado en rama de entrega; no atribuido a main'
    dims=' × '.join(str(v) for v in a['dimensions_xyz']) if a['dimensions_xyz'] else 'No declaradas por separado'
    rows=[('ID estable',a['id']),('Colección / categoría',a['pack']+' / '+CATEGORIES[a['category']]),
        ('Versión del recurso',a['version']),('Estado documental',status),('Unidades',a['units']),
        ('Ejes',a['axes']),('Dimensiones X × Y × Z',dims),('Origen / pivote',a['pivot']),
        ('Triángulos del GLB',s['triangles']),('Licencia',a['license']),('Colisión',a['collision']),('LOD',a['lod'])]
    if a['group']:rows.append(('Submodelo dentro del GLB compartido',a['group']))
    if a['habitable']:rows += [('HABITABLE','Sí, por diseño ficticio del mundo'),('Representación',a['representation']),('Radio de referencia (m)',a['radius_m'])]
    out=f'# {title}\n\n[← Biblioteca](../../ASSET_LIBRARY.md) · [Colección](../{a["pack"]}.md) · [JSON para agentes](../../asset_library.json)\n\n'
    out+=f'<img src="{image}" alt="Modelo 3D real: {title}" width="560">\n\n'
    out+=f'{text(a["description"])}\n\n{links}\n\n| Campo | Valor |\n| --- | --- |\n'
    out+=''.join(f'| {key} | {text(value)} |\n' for key,value in rows)
    out+='\n## Reutilización\n\n```text\n'+a['resource']+'\n```\n\n'
    out+='Instanciar el GLB o su escena, sin copiar la geometría. '
    if a['group']:out+='Esta ficha identifica un subgrupo del GLB compartido, no un archivo independiente. '
    out+='Los nombres de anclajes distinguen mayúsculas y minúsculas; resolverlos desde la instancia.\n\n'
    out+='**Materiales:** '+(', '.join('`'+text(x)+'`' for x in s['materials']) or 'No declarados')+'.\n\n'
    out+='**Anclajes:** '+(', '.join('`'+text(x)+'`' for x in s['sockets']) or 'Sin anclajes nombrados en el GLB')+'.\n\n'
    out+='**Clips glTF:** '+(', '.join('`'+text(x)+'`' for x in s['animations_gltf']) or 'Sin clips')+'. Godot puede normalizar nombres al importar; consultar la guía del pack.\n\n'
    out+='## Alcance y trazabilidad\n\n'+text(a['known_limits'])+'\n\n'
    out+='La comprobación de catálogo no sustituye las pruebas de Godot ni demuestra integración de campaña. '
    if a['pull_request']:out+=f'[Pruebas y revisión de la entrega #{a["pull_request"]}]({WEB}/pull/{a["pull_request"]}). '
    out+=f'Revisión de los recursos: `{a["revision"]}`.\n\n'
    out+=f'Foto: `{a["preview"]["kind"]}`, {a["preview"]["size_px"][0]} × {a["preview"]["size_px"][1]} píxeles. '
    out+='Es una imagen del recurso real, no arte conceptual. Los encuadres aislados de submodelos no muestran el resto del conjunto.\n\n'
    out+='Metadatos derivados del manifiesto fijado y los binarios; no editar esta ficha a mano. [Protocolo de alta](../CONTRIBUTING.md).\n'
    return out


def grid(assets, document):
    lines=['| Modelo | Modelo |','| --- | --- |']
    for start in range(0,len(assets),2):
        cells=[]
        for a in assets[start:start+2]:
            target=Path(os.path.relpath(ROOT/a['card'],(ROOT/document).parent)).as_posix()
            cells.append(f'<a href="{target}"><img src="{image_link(a,document)}" alt="{text(a["title"])}" width="300"></a><br>**[{text(a["title"])}]({target})**<br><code>{a["id"]}</code>')
        if len(cells)==1:cells.append('')
        lines.append('| '+' | '.join(cells)+' |')
    return '\n'.join(lines)+'\n'


def pages(catalogue):
    assets=catalogue['assets'];outputs={}
    for a in assets:outputs[a['card']]=card(a)
    index='# Biblioteca visual de modelos 3D\n\n'
    index+='**Una ficha y una fotografía real por modelo.** [JSON para agentes](asset_library.json) · [Protocolo y formato](asset_library/CONTRIBUTING.md) · [Registro permanente #52]('+WEB+'/issues/52).\n\n'
    index+=f'Este inventario contiene **{len(assets)} fichas con imagen individual**, obtenidas de archivos reales y referencias Git fijas. '
    index+='No cuenta propuestas sin binarios. Un archivo en main no implica una nueva mecánica ni una release.\n\n'
    index+='## Elegir colección\n\n| Colección | Fichas con foto | Disponibilidad de archivos |\n| --- | ---: | --- |\n'
    for pack in catalogue['packs']:
        items=[a for a in assets if a['pack']==pack['id']]
        if not items:continue
        doc='docs/asset_library/'+pack['id']+'.md'
        p='# '+pack['title']+'\n\n[← Índice de biblioteca](../ASSET_LIBRARY.md) · [JSON](../asset_library.json)\n\n'
        p+=f'**{len(items)} fichas**, cada una con imagen real, fuente editable, GLB y datos técnicos. Pulsa el nombre o la imagen para abrir la ficha.\n\n'
        p+=text(pack.get('limits','Los usos futuros no equivalen a mecánicas integradas.'))+'\n\n'
        p+=grid(items,doc)
        outputs[doc]=p
        availability='En main al inventariar' if all(a['availability']['in_main_at_snapshot'] for a in items) else 'Rama de entrega; revisar PR'
        index+=f'| [{text(pack["title"])}](asset_library/{pack["id"]}.md) | {len(items)} | {availability} |\n'
    index+='\n## Buscar por categoría\n\n'
    for key,label in CATEGORIES.items():
        items=[a for a in assets if a['category']==key]
        if not items:continue
        doc='docs/asset_library/categories/'+key+'.md'
        outputs[doc]='# '+label+'\n\n[← Biblioteca](../../ASSET_LIBRARY.md)\n\n'+grid(items,doc)
        index+=f'[{label} · {len(items)}](asset_library/categories/{key}.md)  \n'
    index+='\n## Cómo leer las fichas\n\n'
    index+='Cada ID conserva colección y nombre. La ficha enlaza la fuente `.blend`, el GLB, el manifiesto y la escena o guía disponibles. Incluye escala/ejes, dimensiones declaradas, materiales, anclajes, clips y limitaciones. Los planetas **HABITABLES** distinguen representación orbital y superficie; dos representaciones no se cuentan como dos mundos.\n\n'
    index+='Las fotos existentes se enlazan por revisión inmutable; las que faltaban se renderizan importando el GLB entregado. No se ejecutan constructores ni se sobrescriben fuentes de Blender. Los submodelos de ocio y guardianes mantienen su GLB compartido y se fotografían por separado.\n\n'
    index+='**Disponibilidad, validación e integración son campos distintos.** Este catálogo comprueba archivos, hashes, GLB y fotografías; las pruebas jugables siguen en cada PR. No concede daño, IA, inventario, vuelo o misiones a un modelo por tener una imagen.\n\n'
    index+='## Para agentes\n\n'
    index+='Leer `docs/asset_library.json` (formato `espaciokoop-asset-library`, versión 2). `assets` contiene fichas normalizadas; `packs` identifica colecciones; `manifest` apunta a la autoridad de metadatos; `revision` fija los archivos consumidos. `preview` identifica imagen, origen y dimensiones. Los prefijos documentales de recursos antiguos no renombran APIs.\n\n'
    index+='```sh\npython tools/asset_library/catalogue.py --check\npython -m unittest discover -s tests/asset_library -v\n# Refrescar deliberadamente después de traer las ramas:\npython tools/asset_library/catalogue.py --refresh --render-missing\n```\n\n'
    index+='El comando de refresco actualiza documentación derivada, nunca el estado del juego. [Reglas para añadir modelos y preservar sus fotos](asset_library/CONTRIBUTING.md).\n\n'
    index+='## Pendientes, sin fingir una entrega\n\n'
    if catalogue['pending']:
        for pending in catalogue['pending']:index+=f'- **{text(pending["title"])}:** {text(pending["reason"])}.\n'
    else:index+='Todas las colecciones incluidas en este corte tienen recursos y fotografías. Las colecciones aún no registradas deben incorporarse con su manifiesto y reserva.\n'
    index+='\nInventario referido a `main@'+catalogue['inventory_base_commit']+'`; las revisiones de cada entrega están en [sources.lock.json](asset_library/sources.lock.json). '
    index+='[Índice anterior conservado](asset_library/LEGACY_INDEX.md). No cerrar #52 al integrar esta actualización.\n'
    outputs['docs/ASSET_LIBRARY.md']=index
    outputs['docs/asset_library.json']=json.dumps(catalogue,ensure_ascii=False,indent=2,allow_nan=False)+'\n'
    return outputs


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh',action='store_true');parser.add_argument('--check',action='store_true')
    parser.add_argument('--render-missing',action='store_true')
    args=parser.parse_args()
    need(not (args.check and (args.refresh or args.render_missing)), '--check must not change the inventory')
    specs=json.loads((ROOT/'tools/asset_library/sources.json').read_text())['packs']
    lock_path=ROOT/'docs/asset_library/sources.lock.json'
    need(not args.check or lock_path.is_file(), 'Missing source lock; --check never creates one')
    if args.refresh or not lock_path.exists():
        main_sha=resolve('origin/main');need(main_sha,'Fetch origin/main first')
        sources={}
        for spec in specs:
            candidates=[main_sha]+[resolve(ref) for ref in spec.get('refs',[])]
            selected=next((r for r in candidates if r and exists(r,spec['manifest'])),None)
            if selected is None and spec.get('required',True):raise ValueError('Missing required pack '+spec['id'])
            sources[spec['id']]=selected
        lock={'version':1,'main_revision':main_sha,'sources':sources}
        lock_path.parent.mkdir(parents=True,exist_ok=True)
        lock_path.write_text(json.dumps(lock,sort_keys=True,indent=2)+'\n')
    else:lock=json.loads(lock_path.read_text())
    assets=[];packs=[];pending=[]
    for spec in specs:
        need(not spec.get('required',True) or lock['sources'].get(spec['id']), 'Required pack absent from source lock: '+spec['id'])
        revision=lock['sources'].get(spec['id'])
        if not revision:
            pending.append({'id':spec['id'],'title':spec['title'],'reason':'Manifiesto todavía no publicado en las revisiones consultadas'});continue
        document=json.loads(blob(revision,spec['manifest']))
        entries=records(spec,document)
        converted=[make_asset(spec,revision,lock['main_revision'],e,p,args.render_missing) for e,p in entries]
        assets.extend(converted)
        packs.append({**spec,'revision':revision,'asset_ids':[a['id'] for a in converted]})
        print('CATALOGUE_PACK',spec['id'],len(converted),revision,flush=True)
    need(len({a['id'] for a in assets})==len(assets),'Duplicate IDs across packs')
    need(len({a['card'] for a in assets})==len(assets),'Colliding card paths')
    catalogue={'schema':'espaciokoop-asset-library','version':2,'issue':52,'coordination_issue':7,
        'repository':REPO,'inventory_base_commit':lock['main_revision'],
        'purpose':'Generated documentary snapshot; pack manifests remain authoritative. No gameplay state.',
        'guide':'docs/ASSET_LIBRARY.md','packs':packs,'assets':assets,'pending':pending}
    outputs=pages(catalogue)
    for name,content in outputs.items():
        target=ROOT/name
        if args.check:
            need(target.is_file() and target.read_text()==content,'Stale/missing generated file '+name)
        else:
            target.parent.mkdir(parents=True,exist_ok=True);target.write_text(content,encoding='utf-8')
    summary={'assets':len(assets),'packs':len(packs),'pending':len(pending),
        'individual_photos':len(assets),'new_photos':sum(a['preview']['kind']=='blender_glb_render' for a in assets)}
    out=ROOT/'build/asset_library';out.mkdir(parents=True,exist_ok=True)
    (out/'validation.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('ASSET_LIBRARY_PASS',json.dumps(summary),flush=True)

if __name__=='__main__':main()
