"""Reexport edited Orbita sources without saving over the .blend files.

python art/blender/orbita_pack/export.py --render
blender -b --python art/blender/orbita_pack/export.py -- --render
Static parts are joined only in memory, by parent. Named articulated pivots and
sockets survive export. Previews reimport the exported GLB in a clean scene.
No textures, external resources or network are used.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
import bmesh
from mathutils import Vector
from build import ROOT,HERE,SPECS

MODELS=ROOT/'game/assets/models/orbita_pack'
IMAGES=ROOT/'docs/images/orbita_pack'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def descendants(root):
    return [root,*root.children_recursive]


def bounds(objects):
    bpy.context.view_layer.update()
    points=[o.matrix_world@Vector(v) for o in objects if o.type=='MESH' for v in o.bound_box]
    if not points: raise ValueError('Empty mesh')
    low=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    return low,high


def optimise(root):
    groups={}
    for ob in list(root.children_recursive):
        if ob.type!='MESH': continue
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True); bpy.context.view_layer.objects.active=ob
        for mod in list(ob.modifiers): bpy.ops.object.modifier_apply(modifier=mod.name)
        bm=bmesh.new(); bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(ob.data); bm.free(); ob.data.update()
        if not ob.animation_data and not ob.children:
            groups.setdefault(ob.parent,[]).append(ob)
    for parent,parts in groups.items():
        if len(parts)<2: continue
        bpy.ops.object.select_all(action='DESELECT')
        for ob in parts: ob.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        bpy.ops.object.join()
        parts[0].name=parent.name+'_mesh'


def glb_json(path):
    data=path.read_bytes()
    magic,version,length=struct.unpack_from('<III',data)
    if (magic,version,length)!=(0x46546C67,2,len(data)): raise ValueError('Invalid GLB header')
    size,kind=struct.unpack_from('<II',data,12)
    if kind!=0x4E4F534A: raise ValueError('Missing JSON chunk')
    return json.loads(data[20:20+size])


def render(root,path):
    low,high=bounds(descendants(root)); centre=(low+high)*.5
    radius=max((high-low).length/2,.5)
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.device='CPU'; scene.cycles.samples=24
    scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED'; scene.render.threads=4
    scene.render.resolution_x=640; scene.render.resolution_y=640
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=True
    scene.world=bpy.data.worlds.new('Preview_world'); scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.2,.26,.34,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.35
    camera_data=bpy.data.cameras.new('Preview_camera')
    camera=bpy.data.objects.new('Preview_camera',camera_data)
    scene.collection.objects.link(camera)
    direction=Vector((1.1,1.7,1.0)).normalized()
    camera.location=centre+direction*radius*5
    camera.rotation_euler=(centre-camera.location).to_track_quat('-Z','Y').to_euler()
    camera_data.type='ORTHO'; camera_data.lens=50
    bpy.context.view_layer.update()
    inv=camera.matrix_world.inverted()
    screen=[inv@(ob.matrix_world@Vector(v)) for ob in descendants(root) if ob.type=='MESH' for v in ob.bound_box]
    span=max(max(p[i] for p in screen)-min(p[i] for p in screen) for i in (0,1))
    camera_data.ortho_scale=span*1.22; scene.camera=camera
    for name,direction,power,tint in [
        ('Key',(2.0,2.5,3.0),900,(.86,.94,1.0)),
        ('Fill',(-2.8,1.0,1.2),580,(.42,.76,1.0)),
        ('Rim',(1.0,-2.0,2.4),1100,(1.0,.61,.32)),
    ]:
        data=bpy.data.lights.new('Preview_'+name,'AREA')
        data.energy=power*radius*radius; data.shape='DISK'; data.size=radius*3
        data.color=tint
        light=bpy.data.objects.new(data.name,data); scene.collection.objects.link(light)
        light.location=centre+Vector(direction)*radius
        light.rotation_euler=(centre-light.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)


def render_exported(ident,target,path):
    # Round-trip validation: render the delivered GLB, never a richer source scene.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(target))
    root=bpy.data.objects.get(ident)
    if root is None: raise ValueError('Root lost during GLB reimport: '+ident)
    bpy.context.scene.frame_set(1)
    render(root,path)


def contact_sheet(entries):
    from PIL import Image,ImageDraw,ImageFont
    page=Image.new('RGB',(1600,1510),'#101c29'); draw=ImageDraw.Draw(page)
    font_path='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    try:
        large=ImageFont.truetype(font_path,42); small=ImageFont.truetype(font_path,18); text=ImageFont.truetype(font_path,21)
    except OSError:
        large=small=text=ImageFont.load_default()
    draw.text((48,28),'ÓRBITA / BIBLIOTECA 3D',font=large,fill='#e4eeed')
    draw.text((50,87),'12 modelos originales · Blender 4.5.3 · renders de los GLB exportados',font=small,fill='#88a9b3')
    categories={'ships':'Naves','equipment':'Equipo','avatars':'Tripulación','enemies':'Enemigos','worlds':'Mundos','infrastructure':'Infraestructura'}
    for i,entry in enumerate(entries):
        x=32+(i%4)*392; y=137+(i//4)*440
        draw.rounded_rectangle((x,y,x+374,y+418),radius=16,fill='#192b3b')
        image=Image.open(IMAGES/(entry['id'].split('/')[-1]+'.png')).convert('RGBA')
        image.thumbnail((358,344),Image.Resampling.LANCZOS)
        page.paste(image,(x+(374-image.width)//2,y+8),image)
        title=entry['title'].split(' · ')[0]
        draw.text((x+18,y+347),title,font=text,fill='#e4eeed')
        draw.text((x+18,y+378),categories[entry['category']]+' / '+str(entry['triangles'])+' tris',font=small,fill='#88a9b3')
    draw.text((50,1475),'Modelos para reutilizar. No implica nuevas mecánicas integradas en la campaña.',font=small,fill='#88a9b3')
    page.save(IMAGES/'overview.png')


def write_guide(entries):
    lines=['# Pack Órbita — biblioteca original de modelos', '',
      'Índice permanente: [issue #52](https://github.com/EspacioKoop/espaciokooplagunakRemake/issues/52). '
      'Biblioteca global: [ASSET_LIBRARY.md](ASSET_LIBRARY.md).', '',
      '![Renders de los GLB reimportados en Blender](images/orbita_pack/overview.png)', '',
      '**Estado:** modelos exportados; consultar PR/CI para la importación verificada. '
      'No se han integrado automáticamente en campaña, combate, IA, avatar, Atlas ni selección de nave. '
      'La galería son renders de los modelos, no capturas del juego final.', '',
      '## Catálogo', '', '| ID | Modelo | GLB | Fuente editable | Triángulos | Animación |',
      '| --- | --- | --- | --- | ---: | --- |']
    for e in entries:
        lines.append(f"| `{e['id']}` | {e['title']} | [GLB](../{e['runtime']}) | [.blend](../{e['source']}) | {e['triangles']} | {', '.join(e['animations']) or 'Estático'} |")
    lines += ['', '## Uso en Godot', '',
      'Los GLB son autocontenidos y no requieren Blender para jugar. Arrastra el GLB a una escena '
      'o instancia su PackedScene. El catálogo verificable está en '
      '`game/assets/models/orbita_pack/manifest.json` (hashes, dimensiones, materiales y anclajes).', '',
      '```gdscript', 'var model = preload("res://assets/models/orbita_pack/karramarro_tug.glb").instantiate()',
      'add_child(model)', 'var tow_socket = model.find_child("socket_tow_left", true, false)', '```', '',
      'Para inspección aislada: abre `game/asset_lab/orbita_pack/viewer.tscn` y pulsa F6, o ejecuta:', '',
      '```sh', '.toolchain/godot --path game res://asset_lab/orbita_pack/viewer.tscn', '```', '',
      'El visor permite elegir modelo, orbitar, acercar, restablecer y reproducir la animación mecánica. '
      'Sólo el visor normaliza visualmente el tamaño; no modifica los GLB.', '',
      '## Contrato de autoría', '',
      '- Coordenadas de ejecución: +X derecha, +Y arriba, -Z frente. Blender usa +Z arriba; '
      'el exportador convierte automáticamente. Una unidad es un metro, excepto los mundos: '
      'son unidades de representación, NO radios astronómicos.',
      '- El origen permanece en el origen de autoría. Robots, torreta, proyector y collar se apoyan '
      'en el plano Y=0; naves/sonda/módulo solar usan un origen de montaje; mundos centrados en (0,0,0). '
      'Consultar AABB y dimensiones reales en el manifiesto.',
      '- Los nodos `socket_*` tienen nombres únicos. `path` en el manifiesto describe la jerarquía glTF, '
      'no una NodePath relativa de Godot. Resolver el nombre con `find_child(..., true, false)` '
      'desde la instancia. Las bocas apuntan al -Z local; adaptar los anclajes industriales a su consumidor.',
      '- `mechanical_cycle` mueve pivotes rígidos. Los robots NO tienen esqueleto humano, '
      'pesos, locomoción, retargeting ni controladores. No sustituyen directamente el `crew.glb` existente.',
      '- Materiales Principled PBR, color/metal/roughness/emisión, sin texturas externas ni nodos de ruido que se pierdan en glTF. '
      'Las fuentes mantienen piezas editables; los GLB agrupan piezas estáticas por pivote para reducir nodos.',
      '- No contienen físicas, colisiones, LOD, daño, IA ni lógica de red. Usar formas simples para '
      'colisión según el consumidor; no crear trimesh dinámico por defecto. Los mundos son vistas lejanas, no superficies caminables.',
      '- Geometría original, licencia MIT del repositorio. Sin arte importado, modelos de terceros, datos personales ni servicios de generación externos.',
      '', '## Editar sin perder trabajo', '',
      'La fuente de verdad editable es cada `.blend`. El constructor procedural se usa sólo para la primera creación. '
      'Por defecto aborta si existen fuentes; `--force` es una operación destructiva explícita. '
      '`--missing-only` conserva todas las fuentes existentes. El exportador NUNCA guarda sobre ellas.', '',
      '```sh', '# Primera creación (Python 3.11 + bpy==4.5.3):',
      'python art/blender/orbita_pack/build.py', '# Tras editar y guardar un .blend:',
      'python art/blender/orbita_pack/export.py --render', '# Equivalente desde Blender:',
      'blender -b --python art/blender/orbita_pack/export.py -- --render',
      '# Verificación estructural:', 'python tests/orbita_pack/validate.py', '```', '',
      'Cada render abre el GLB exportado en una escena limpia. Las pruebas de Godot comprueban '
      'materiales, anclajes, clips y selección de los doce modelos, y guardan una captura real del visor.', '',
      '## Ampliaciones', '',
      'Reserva archivos en #7 y registra altas/revisiones en #52. Conserva IDs publicados; '
      'versiona cambios de escala, origen, materiales o anclajes. No sobrescribas packs de otros agentes. '
      'El generador exporta sólo la lista permitida SPECS; un nuevo modelo requiere alta explícita y pruebas.', '']
    (ROOT/'docs/ORBITA_ASSET_PACK.md').write_text('\n'.join(lines),encoding='utf-8')


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--render',action='store_true')
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    args=parser.parse_args(argv)
    MODELS.mkdir(parents=True,exist_ok=True); IMAGES.mkdir(parents=True,exist_ok=True)
    entries=[]
    for ident,title,category,description,units in SPECS:
        source=HERE/(ident+'.blend')
        before=sha(source)
        bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
        root=bpy.data.objects.get(ident)
        if root is None or root.get('asset_id')!='orbita/'+ident: raise ValueError('Wrong source root: '+ident)
        bpy.context.scene.frame_set(1)
        bpy.context.scene.name='mechanical_cycle'
        parts=sum(o.type=='MESH' for o in root.children_recursive)
        optimise(root)
        objects=descendants(root); low,high=bounds(objects)
        size=high-low
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects: ob.select_set(True)
        bpy.context.view_layer.objects.active=root
        target=MODELS/(ident+'.glb')
        options=dict(filepath=str(target),export_format='GLB',use_selection=True,
          export_yup=True,export_extras=True,export_animations=any(o.animation_data for o in objects),
          export_animation_mode='SCENE',export_frame_range=True,
          export_anim_scene_split_object=False,export_cameras=False,export_lights=False,
          export_apply=False,export_copyright='Original Espaciokoop Lagunak art — MIT')
        allowed=set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
        required={'export_animation_mode','export_yup','export_extras','use_selection'}
        if not required.issubset(allowed): raise RuntimeError('Unsupported glTF exporter')
        bpy.ops.export_scene.gltf(**{k:v for k,v in options.items() if k in allowed})
        doc=glb_json(target)
        accessors=doc.get('accessors',[])
        triangles=sum(accessors[p['indices']]['count']//3 if 'indices' in p else accessors[p['attributes']['POSITION']]['count']//3
            for m in doc.get('meshes',[]) for p in m['primitives'])
        nodes=doc.get('nodes',[])
        parents={child:i for i,n in enumerate(nodes) for child in n.get('children',[])}
        def node_path(index):
            result=[nodes[index].get('name','node')]
            while index in parents:
                index=parents[index]; result.append(nodes[index].get('name','node'))
            return '/'.join(reversed(result))
        sockets=[{'name':n['name'],'path':node_path(i)} for i,n in enumerate(nodes) if n.get('name','').startswith('socket_')]
        names=[s['name'] for s in sockets]
        if len(names)!=len(set(names)) or any(not name.isidentifier() for name in names):
            raise ValueError('Socket names must be unique portable identifiers: '+ident)
        animations=[a.get('name','') for a in doc.get('animations',[])]
        entry=dict(id='orbita/'+ident,version=1,title=title,category=category,description=description,
          runtime=target.relative_to(ROOT).as_posix(),resource='res://assets/models/orbita_pack/'+ident+'.glb',
          source=source.relative_to(ROOT).as_posix(),preview='docs/images/orbita_pack/'+ident+'.png',
          sha256=sha(target),source_sha256=before,bytes=target.stat().st_size,
          units=units,axes='Godot +Y up, -Z forward',dimensions=[round(size.x,5),round(size.z,5),round(size.y,5)],
          aabb_min=[round(low.x,5),round(low.z,5),round(-high.y,5)],
          aabb_max=[round(high.x,5),round(high.z,5),round(-low.y,5)],
          triangles=triangles,editable_parts=parts,mesh_nodes=sum('mesh' in n for n in nodes),
          materials=[m.get('name','') for m in doc.get('materials',[])],sockets=sockets,animations=animations,
          license='MIT',status='exported_not_gameplay_integrated',rig='rigid_object_hierarchy',
          collision='not_included',lod='not_included',provenance='Original authored geometry; no imported art')
        entries.append(entry)
        if args.render: render_exported(ident,target,IMAGES/(ident+'.png'))
        if sha(source)!=before: raise RuntimeError('Editable source was modified by export')
        print('ORBITA_ASSET_EXPORTED '+ident+' triangles='+str(triangles),flush=True)
    manifest=dict(schema='espaciokoop-asset-pack',version=1,pack='orbita',issue=52,
      blender=bpy.app.version_string,geometry_seed=5209,assets=entries)
    (MODELS/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    write_guide(entries)
    if args.render: contact_sheet(entries)
    print('ORBITA_EXPORT_PASS assets='+str(len(entries)),flush=True)

if __name__=='__main__': main()
