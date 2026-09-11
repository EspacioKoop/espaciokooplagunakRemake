"""Reexport saved Fieldkit .blend files; never regenerate or overwrite sources.

python art/blender/fieldkit_pack/export.py [--render]
Blender CLI: blender -b --python art/blender/fieldkit_pack/export.py -- --render
Renders are optional asset QA evidence, not generated concept art.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
import bmesh
from mathutils import Vector
from build import ROOT,HERE,SPECS

MODELS=ROOT/'game/assets/models/fieldkit_pack'
IMAGES=ROOT/'docs/images/fieldkit_pack'
SCENES=ROOT/'game/asset_lab/fieldkit_pack/instances'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds(root):
    bpy.context.view_layer.update()
    points=[o.matrix_world@Vector(v) for o in root.children_recursive if o.type=='MESH' for v in o.bound_box]
    if not points:
        raise ValueError('No geometry')
    return (Vector(tuple(min(p[i] for p in points) for i in range(3))),
            Vector(tuple(max(p[i] for p in points) for i in range(3))))


def optimise(root):
    groups={}
    for ob in list(root.children_recursive):
        if ob.type!='MESH':
            continue
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active=ob
        for mod in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bm=bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()
        # Custom lofts receive UVs on the export copy; authored UVs are retained.
        if not ob.data.uv_layers:
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.uv.smart_project(island_margin=.025)
            bpy.ops.object.mode_set(mode='OBJECT')
        if not ob.animation_data and not ob.children:
            groups.setdefault(ob.parent,[]).append(ob)
    for parent,parts in groups.items():
        if len(parts)<2:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        for ob in parts:
            ob.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        bpy.ops.object.join()
        parts[0].name=parent.name+'_mesh'


def glb_json(path):
    data=path.read_bytes()
    if len(data)<20 or struct.unpack_from('<III',data)!=(0x46546C67,2,len(data)):
        raise ValueError('Invalid GLB header')
    length,kind=struct.unpack_from('<II',data,12)
    if kind!=0x4E4F534A:
        raise ValueError('GLB JSON missing')
    return json.loads(data[20:20+length])


def preview(ident,target,path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(target))
    root=bpy.data.objects.get(ident)
    if root is None:
        raise ValueError('Root lost in GLB round-trip')
    bpy.context.scene.frame_set(1)
    low,high=bounds(root)
    centre=(low+high)*.5
    radius=max((high-low).length/2,.1)
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.device='CPU'
    scene.cycles.samples=24
    scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED'
    scene.render.threads=4
    scene.render.resolution_x=640
    scene.render.resolution_y=640
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=True
    scene.world=bpy.data.worlds.new('QA_world')
    scene.world.use_nodes=True
    background=scene.world.node_tree.nodes['Background']
    background.inputs[0].default_value=(.2,.26,.34,1)
    background.inputs[1].default_value=.4
    data=bpy.data.cameras.new('QA_camera')
    camera=bpy.data.objects.new('QA_camera',data)
    scene.collection.objects.link(camera)
    camera.location=centre+Vector((1.5,1.75,1.1)).normalized()*radius*5
    camera.rotation_euler=(centre-camera.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO'
    data.clip_start=.001
    data.clip_end=max(radius*20,100)
    scene.camera=camera
    bpy.context.view_layer.update()
    inv=camera.matrix_world.inverted()
    points=[inv@(o.matrix_world@Vector(v)) for o in root.children_recursive if o.type=='MESH' for v in o.bound_box]
    data.ortho_scale=max(max(p[i] for p in points)-min(p[i] for p in points) for i in (0,1))*1.25
    for name,direction,power,tint in [('Key',(2,2.5,3),900,(.86,.94,1)),('Fill',(-2.8,1,1.2),580,(.46,.78,1)),('Rim',(1,-2,2.4),1100,(1,.65,.38))]:
        light_data=bpy.data.lights.new('QA_'+name,'AREA')
        light_data.energy=power*radius*radius
        light_data.size=radius*3
        light_data.color=tint
        light=bpy.data.objects.new(light_data.name,light_data)
        scene.collection.objects.link(light)
        light.location=centre+Vector(direction)*radius
        light.rotation_euler=(centre-light.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)


def write_catalog(entries):
    # The compact discovery index points to the authoritative manifest rather than duplicating hashes.
    index={'schema':'espaciokoop-asset-discovery','version':1,'pack':'fieldkit','issue':52,
        'manifest':'game/assets/models/fieldkit_pack/manifest.json',
        'viewer':'game/asset_lab/fieldkit_pack/viewer.tscn',
        'assets':[{'id':e['id'],'category':e['category'],'title':e['title'],'scene':e['scene']} for e in entries]}
    (ROOT/'docs/fieldkit_assets.json').write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render',action='store_true')
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    args=parser.parse_args(argv)
    for folder in (MODELS,IMAGES,SCENES):
        folder.mkdir(parents=True,exist_ok=True)
    entries=[]
    for ident,title,category,description,pivot in SPECS:
        source=HERE/(ident+'.blend')
        before=sha(source)
        bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
        root=bpy.data.objects.get(ident)
        if root is None or root.get('asset_id')!='fieldkit/'+ident:
            raise ValueError('Wrong source: '+ident)
        bpy.context.scene.frame_set(1)
        bpy.context.scene.name='field_cycle'
        editable_parts=sum(o.type=='MESH' for o in root.children_recursive)
        optimise(root)
        low,high=bounds(root)
        objects=[root,*root.children_recursive]
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects:
            ob.select_set(True)
        bpy.context.view_layer.objects.active=root
        target=MODELS/(ident+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,
            export_yup=True,export_extras=True,export_animations=True,
            export_animation_mode='SCENE',export_frame_range=True,
            export_anim_scene_split_object=False,export_cameras=False,export_lights=False,
            export_apply=False,export_copyright='Original Espaciokoop Lagunak art - MIT')
        doc=glb_json(target)
        accessors=doc.get('accessors',[])
        triangles=sum(accessors[p['indices']]['count']//3 if 'indices' in p else accessors[p['attributes']['POSITION']]['count']//3
            for m in doc.get('meshes',[]) for p in m['primitives'])
        nodes=doc.get('nodes',[])
        sockets=[n['name'] for n in nodes if n.get('name','').startswith('socket_')]
        if len(sockets)!=len(set(sockets)) or any(not n.isidentifier() for n in sockets):
            raise ValueError('Nonportable socket name: '+ident)
        resource='res://assets/models/fieldkit_pack/'+ident+'.glb'
        scene=SCENES/(ident+'.tscn')
        scene.write_text('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="'+resource+'" id="1"]\n\n[node name="'+ident+'" type="Node3D"]\nmetadata/asset_id = "fieldkit/'+ident+'"\n\n[node name="Model" parent="." instance=ExtResource("1")]\n',encoding='utf-8')
        entry={'id':'fieldkit/'+ident,'version':1,'title':title,'category':category,'description':description,
            'source':source.relative_to(ROOT).as_posix(),'runtime':target.relative_to(ROOT).as_posix(),
            'resource':resource,'scene':scene.relative_to(ROOT).as_posix(),
            'sha256':sha(target),'source_sha256':before,'bytes':target.stat().st_size,
            'triangles':triangles,'editable_parts':editable_parts,'mesh_nodes':sum('mesh' in n for n in nodes),
            'materials':[m.get('name','') for m in doc.get('materials',[])],
            'sockets':sockets,'animations':[a.get('name','') for a in doc.get('animations',[])],
            'units':'metres','axes':'Godot +X right, +Y up, -Z forward','pivot':pivot,
            'attachment_socket':'socket_wrist' if pivot=='wrist' else ('socket_centre' if category=='ships' else 'socket_grip'),
            'aabb_min':[round(low.x,6),round(low.z,6),round(-high.y,6)],
            'aabb_max':[round(high.x,6),round(high.z,6),round(-low.y,6)],
            'dimensions':[round(high.x-low.x,6),round(high.z-low.z,6),round(high.y-low.y,6)],
            'license':'MIT','provenance':'Original geometry authored in Blender; no external art',
            'status':'exported_not_gameplay_integrated','collision':'not_included','rig':'rigid_mechanical',
            'preview':'docs/images/fieldkit_pack/'+ident+'.png' if args.render else None}
        if args.render:
            preview(ident,target,IMAGES/(ident+'.png'))
        if sha(source)!=before:
            raise RuntimeError('Exporter modified artist source')
        entries.append(entry)
        print('FIELDKIT_EXPORTED '+ident+' triangles='+str(triangles),flush=True)
    manifest={'schema':'espaciokoop-asset-pack','version':1,'pack':'fieldkit','issue':52,'blender':bpy.app.version_string,'assets':entries}
    (MODELS/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    write_catalog(entries)
    print('FIELDKIT_EXPORT_PASS assets=10',flush=True)


if __name__=='__main__':
    main()
