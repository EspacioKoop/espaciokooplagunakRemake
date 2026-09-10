"""Derive all three representations from each edited Aterpe .blend.
Never save the source here. Orbital/approach simplification is in memory only.
The surface collision geometry is never replaced by a far LOD.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Matrix, Vector
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODELS = ROOT / 'game/assets/models/aterpe_pack'
IMAGES = ROOT / 'docs/images/aterpe_pack'
_spec = importlib.util.spec_from_file_location('lantegi_export_helpers', ROOT / 'art/blender/lantegi_pack/export.py')
E = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(E)
C = Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
PLANETS = ('kare','suharri')


def join_world(parts, parent, name):
    if not parts:
        return None
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts: ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts)>1: bpy.ops.object.join()
    ob=parts[0]
    world=ob.matrix_world.copy()
    ob.parent=parent
    ob.matrix_world=world
    ob.name=name
    return ob


def simplify(root, mode):
    terrain=bpy.data.objects.get('Terrain')
    if terrain is None:raise ValueError('Missing Terrain collection')
    if mode!='surface':
        meshes=[o for o in terrain.children_recursive if o.type=='MESH']
        joined=join_world(meshes,terrain,'Terrain_'+mode)
        for ob in list(terrain.children_recursive):
            if ob.type=='EMPTY' and ob!=joined:bpy.data.objects.remove(ob,do_unlink=True)
    scenery=bpy.data.objects.get('Scenery')
    if scenery is not None:
        joined=join_world([o for o in scenery.children_recursive if o.type=='MESH'],scenery,'Scenery_'+mode)
        for ob in list(scenery.children_recursive):
            if ob.type=='EMPTY' and ob!=joined:bpy.data.objects.remove(ob,do_unlink=True)
    if mode=='surface':return
    terrain_ratio=.26 if mode=='approach' else .075
    prop_ratio=.68 if mode=='approach' else .28
    for ob in list(root.children_recursive):
        if ob.type!='MESH':continue
        ratio=terrain_ratio if ob.parent==terrain else prop_ratio
        if len(ob.data.polygons)<80:continue
        bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
        mod=ob.modifiers.new('Representation_simplification','DECIMATE')
        mod.ratio=ratio;mod.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=mod.name)


def world_frame(ob):
    matrix=C@ob.matrix_world@C.inverted()
    q=matrix.to_quaternion()
    return {'position':list(matrix.translation),'rotation_xyzw':[q.x,q.y,q.z,q.w]}


def metadata(root, source):
    world=json.loads(root['planet_spec_json'])
    entries=[]
    for site in world['sites']:
        ob=bpy.data.objects.get('poi_'+site['slug'])
        if ob is None:raise ValueError('Missing editable POI: '+site['slug'])
        entry={k:site[k] for k in ('slug','title','kind','role','latitude','longitude')}
        entry['id']='aterpe/'+world['slug']+'/'+site['slug']
        entry['node_name']=ob.name
        entry['frame']=world_frame(ob)
        entry['anchors']={}
        for role in ('arrival','departure','resource','quest','encounter'):
            name=role+'_'+site['slug'];anchor=bpy.data.objects.get(name)
            if anchor is None:raise ValueError('Missing anchor '+name)
            entry['anchors'][role]={'node_name':name,**world_frame(anchor)}
        if site['role']=='landing':
            anchor=bpy.data.objects.get('socket_landing_'+site['slug'])
            if anchor is None:raise ValueError('Missing landing deck anchor')
            entry['anchors']['landing']={'node_name':anchor.name,**world_frame(anchor)}
        entries.append(entry)
    return {'id':'aterpe/'+world['slug'],'slug':world['slug'],'title':world['title'],
            'version':1,'habitable':True,'habitat':'breathable fictional gameplay world',
            'radius_metres':world['radius'],'biome':world['biome'],
            'axes':'+Y north/up; -Z longitude zero; +X east','origin':'planet centre',
            'units':'metres','source':str(source.relative_to(ROOT)),
            'source_sha256':E.sha(source),'license':'MIT','pois':entries,
            'terrain_chunks':96,'paths':json.loads(root['path_edges_json']),
            'representations':{},'status':'exported',
            'surface_scene':'game/assets/models/aterpe_pack/'+world['slug']+'_surface.tscn',
            'limits':'Inspection/exploration scene. No atmosphere simulation, orbit physics, combat, harvesting, quests, saves or multiplayer rules.'}


def write_scene(slug):
    text='''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://asset_lab/aterpe_pack/planet_surface.gd" id="1"]
[ext_resource type="PackedScene" path="res://assets/models/aterpe_pack/SLUG_surface.glb" id="2"]

[node name="SLUG" type="Node3D"]
script = ExtResource("1")
planet_slug = "SLUG"

[node name="Visual" parent="." instance=ExtResource("2")]
'''.replace('SLUG',slug)
    (MODELS/(slug+'_surface.tscn')).write_text(text)


def render_site(slug, target, site_slug, destination):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(target))
    poi=bpy.data.objects.get('poi_'+site_slug)
    if poi is None:raise ValueError('Lost POI during GLB round trip')
    bpy.context.view_layer.update()
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=24
    scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=4
    scene.render.resolution_x=960;scene.render.resolution_y=640;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    world=bpy.data.worlds.new('Surface_preview');world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.24,.36,.48,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.65;scene.world=world
    data=bpy.data.cameras.new('Surface_camera');camera=bpy.data.objects.new(data.name,data)
    scene.collection.objects.link(camera);scene.camera=camera
    camera.location=poi.matrix_world@Vector((12,-18,10))
    target_point=poi.matrix_world@Vector((0,1,2.4))
    camera.rotation_euler=(target_point-camera.location).to_track_quat('-Z','Y').to_euler()
    data.lens=37;data.clip_start=.04;data.clip_end=1000
    sun_data=bpy.data.lights.new('Surface_sun','SUN');sun_data.energy=2.3;sun_data.angle=.12
    sun=bpy.data.objects.new(sun_data.name,sun_data);scene.collection.objects.link(sun)
    direction=(poi.matrix_world.to_3x3()@Vector((-.5,.7,-1))).normalized()
    sun.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(destination);bpy.ops.render.render(write_still=True)


def overview(entries):
    from PIL import Image,ImageDraw,ImageFont
    canvas=Image.new('RGB',(1600,1260),'#0c1b28');draw=ImageDraw.Draw(canvas)
    path='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    try:large=ImageFont.truetype(path,34);small=ImageFont.truetype(path,19);label=ImageFont.truetype(path,24)
    except OSError:large=small=label=ImageFont.load_default()
    draw.text((35,20),'ATERPE / PLANETAS HABITABLES',font=large,fill='#eff3e5')
    draw.text((37,67),'Dos esferas completas / 16 POI por mundo / representaciones de una misma fuente Blender',font=small,fill='#9eb9bb')
    for i,e in enumerate(entries):
        x=35+i*785
        image=Image.open(IMAGES/(e['slug']+'_orbit.png')).convert('RGBA')
        image.thumbnail((725,620),Image.Resampling.LANCZOS);canvas.paste(image,(x+20,110),image)
        draw.text((x+15,717),e['title'],font=label,fill='#eff3e5')
        draw.text((x+15,753),f"HABITABLE / radio {e['radius_metres']:.0f} m / 16 lugares modelados",font=small,fill='#9eb9bb')
        site=Image.open(IMAGES/(e['slug']+'_surface.png')).convert('RGB')
        site.thumbnail((740,430),Image.Resampling.LANCZOS);canvas.paste(site,(x,800))
    draw.text((37,1232),'Renders de los GLB entregados. Teletransporte/recorrido en laboratorio; vuelo seamless y reglas de campaña pendientes.',font=small,fill='#9eb9bb')
    canvas.save(IMAGES/'overview.png')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--render',action='store_true')
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:];args=parser.parse_args(argv)
    MODELS.mkdir(parents=True,exist_ok=True);IMAGES.mkdir(parents=True,exist_ok=True)
    entries=[]
    for slug in PLANETS:
        source=HERE/(slug+'.blend');before=E.sha(source);entry=None
        for mode in ('surface','approach','orbit'):
            bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
            root=bpy.data.objects.get(slug)
            if root is None or root.get('asset_id')!='aterpe/'+slug or not root.get('habitable'):
                raise ValueError('Not the expected habitable source')
            bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
            if entry is None:entry=metadata(root,source)
            E.optimise(root);simplify(root,mode)
            root['representation']=mode
            target=MODELS/(slug+'_'+mode+'.glb')
            doc=E.export_one(root,target)
            triangles=sum(doc['accessors'][p['indices']]['count']//3 for m in doc['meshes'] for p in m['primitives'])
            entry['representations'][mode]={'path':str(target.relative_to(ROOT)),
                'sha256':E.sha(target),'bytes':target.stat().st_size,'triangles':triangles,
                'mesh_count':len(doc['meshes']),'source_sha256':before,
                'collision':mode=='surface','coordinate_scale':1.0}
            if E.sha(source)!=before:raise ValueError('Exporter modified editable source')
            print('ATERPE_EXPORTED',slug,mode,triangles,flush=True)
            if args.render and mode=='orbit':E.render_glb(slug,target,IMAGES/(slug+'_orbit.png'),(1.3,1.5,1.0))
        write_scene(slug)
        if args.render:
            render_site(slug,MODELS/(slug+'_surface.glb'),'observatorio',IMAGES/(slug+'_surface.png'))
            render_site(slug,MODELS/(slug+'_surface.glb'),'puerto',IMAGES/(slug+'_landing.png'))
        entries.append(entry)
    manifest={'schema':'espaciokoop-habitable-planets','schema_version':1,'pack':'aterpe',
              'blender_version':bpy.app.version_string,'planets':entries,
              'lod_policy':{'orbit_to_approach_radius_multiple':2.2,'approach_to_orbit_radius_multiple':2.45,
                            'surface_entry':'explicit teleport, not seamless flight',
                            'collision':'full surface retained while walking; never the far mesh'}}
    (MODELS/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if args.render:overview(entries)
    print('ATERPE_EXPORT_PASS',flush=True)


if __name__=='__main__':main()
