"""Export saved .blend files without rewriting sources. MIT.
Previews are made from reimported GLBs, not from higher-detail source scenes.
Shared helpers are used by the additive Bizi collection in this same delivery.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build import HERE, ROOT, SPECS


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def optimise(root):
    groups={}
    for ob in list(root.children_recursive):
        if ob.type!='MESH':continue
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True);bpy.context.view_layer.objects.active=ob
        for mod in list(ob.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        bm=bmesh.new();bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bmesh.ops.triangulate(bm,faces=list(bm.faces))
        # Small bevel artefacts must never become degenerate exported triangles.
        small=[f for f in bm.faces if f.calc_area()<1e-12]
        if small:bmesh.ops.delete(bm,geom=small,context='FACES')
        bm.to_mesh(ob.data);bm.free();ob.data.update()
        if not ob.animation_data and not ob.children and not ob.get('keep_separate',False):
            groups.setdefault(ob.parent,[]).append(ob)
    for parent,parts in groups.items():
        if len(parts)<2:continue
        bpy.ops.object.select_all(action='DESELECT')
        for ob in parts:ob.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        bpy.ops.object.join();parts[0].name=parent.name+'_mesh'


def glb_json(path):
    raw=Path(path).read_bytes()
    if len(raw)<20:raise ValueError('Truncated GLB')
    magic,version,length=struct.unpack_from('<III',raw)
    if (magic,version,length)!=(0x46546C67,2,len(raw)):raise ValueError('Invalid GLB header')
    size,kind=struct.unpack_from('<II',raw,12)
    if kind!=0x4E4F534A:raise ValueError('No JSON chunk')
    return json.loads(raw[20:20+size])


def bounds(root):
    bpy.context.view_layer.update()
    points=[o.matrix_world@Vector(v) for o in [root,*root.children_recursive] if o.type=='MESH' for v in o.bound_box]
    if not points:raise ValueError('No geometry')
    return Vector(tuple(min(p[i] for p in points) for i in range(3))),Vector(tuple(max(p[i] for p in points) for i in range(3)))


def export_model(source, root_name, target, asset_id):
    before=sha(source)
    bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
    root=bpy.data.objects.get(root_name)
    if root is None:raise ValueError('Missing source root '+root_name)
    bpy.context.scene.frame_set(1)
    bpy.context.scene.name='mechanical_cycle'
    optimise(root)
    low,high=bounds(root)
    objects=[root,*root.children_recursive]
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    bpy.context.view_layer.objects.active=root
    target.parent.mkdir(parents=True,exist_ok=True)
    options=dict(filepath=str(target),export_format='GLB',use_selection=True,
        export_yup=True,export_extras=True,export_animations=any(o.animation_data for o in objects),
        export_animation_mode='SCENE',export_frame_range=True,export_anim_scene_split_object=False,
        export_cameras=False,export_lights=False,export_apply=False,
        export_copyright='Original Espaciokoop Lagunak geometry - MIT')
    props=set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    if not {'export_animation_mode','export_yup','use_selection'}.issubset(props):raise RuntimeError('Unsupported Blender exporter')
    bpy.ops.export_scene.gltf(**{k:v for k,v in options.items() if k in props})
    if before!=sha(source):raise AssertionError('Exporter changed editable source')
    doc=glb_json(target)
    def to_godot(v):return [round(v.x,6),round(v.z,6),round(-v.y,6)]
    lo=[low.x,low.z,-high.y];hi=[high.x,high.z,-low.y]
    sockets=[]
    for ob in objects:
        if ob.name.startswith('socket_'):
            bpy.context.view_layer.update()
            sockets.append({'name':ob.name,'position':to_godot(ob.matrix_world.translation),'forward_axis':'-Z','lookup':'find_child(name, true, false)'})
    if len({s['name'] for s in sockets})!=len(sockets):raise ValueError('Duplicate socket names')
    triangles=sum(doc['accessors'][p['indices']]['count']//3 for m in doc.get('meshes',[]) for p in m['primitives'])
    return {'id':asset_id,'version':1,'source':str(source.relative_to(ROOT)),
        'runtime':str(target.relative_to(ROOT)),'source_sha256':before,'sha256':sha(target),
        'bytes':target.stat().st_size,'triangles':triangles,'mesh_nodes':sum(o.type=='MESH' for o in objects),
        'aabb':{'min':[round(v,6) for v in lo],'max':[round(v,6) for v in hi]},
        'dimensions':[round(hi[i]-lo[i],6) for i in range(3)],
        'materials':[m.get('name','') for m in doc.get('materials',[])],
        'sockets':sorted(sockets,key=lambda s:s['name']),
        'animations':[a.get('name','') for a in doc.get('animations',[])],
        'units':'metres','axes':'+X right / +Y up / -Z forward','license':'MIT',
        'status':'exported','authoring_blender':bpy.app.version_string}


def render_exported(target, root_name, image, resolution=480):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(target))
    root=bpy.data.objects.get(root_name)
    if root is None:raise ValueError('GLB lost named root '+root_name)
    bpy.context.scene.frame_set(1)
    low,high=bounds(root);centre=(low+high)/2
    radius=max((high-low).length/2,.2)
    scene=bpy.context.scene;scene.render.engine='CYCLES'
    scene.cycles.device='CPU';scene.cycles.samples=16;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=4
    scene.render.resolution_x=resolution;scene.render.resolution_y=resolution
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
    scene.world=bpy.data.worlds.new('Preview_world');scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.19,.25,.30,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
    cam_data=bpy.data.cameras.new('Preview_camera');cam=bpy.data.objects.new('Preview_camera',cam_data)
    scene.collection.objects.link(cam);cam.location=centre+Vector((1.35,1.8,1.05)).normalized()*radius*5
    cam.rotation_euler=(centre-cam.location).to_track_quat('-Z','Y').to_euler()
    cam_data.type='ORTHO';cam_data.clip_end=max(2000,radius*20)
    bpy.context.view_layer.update();inv=cam.matrix_world.inverted()
    projected=[inv@(o.matrix_world@Vector(v)) for o in [root,*root.children_recursive] if o.type=='MESH' for v in o.bound_box]
    span=max(max(p[i] for p in projected)-min(p[i] for p in projected) for i in (0,1))
    cam_data.ortho_scale=span*1.17;scene.camera=cam
    for name,direction,power,color in [('Key',(2,3,4),1100,(.83,.92,1)),('Fill',(-3,1,1),650,(.48,.76,1)),('Rim',(1,-3,3),1300,(1,.64,.38))]:
        data=bpy.data.lights.new(name,'AREA');data.energy=power*radius*radius;data.shape='DISK';data.size=radius*3
        data.color=color;light=bpy.data.objects.new(name,data);scene.collection.objects.link(light)
        light.location=centre+Vector(direction)*radius
        light.rotation_euler=(centre-light.location).to_track_quat('-Z','Y').to_euler()
    image.parent.mkdir(parents=True,exist_ok=True);scene.render.filepath=str(image)
    bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--render',action='store_true')
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    args=parser.parse_args(argv);entries=[]
    for ident,title,category,description in SPECS:
        target=ROOT/'game/assets/models/itsasargi_pack'/f'{ident}.glb'
        entry=export_model(HERE/f'{ident}.blend',ident,target,'itsasargi/'+ident)
        entry.update(title=title,category=category,description=description)
        entry['preview']='docs/images/itsasargi_pack/'+ident+'.png'
        if args.render:render_exported(target,ident,ROOT/entry['preview'])
        entries.append(entry);print('EXPORTED',entry['id'],entry['triangles'],flush=True)
    result={'schema':'espaciokoop-asset-pack','schema_version':1,'pack':'itsasargi','version':1,
        'library_issue':52,'source_of_truth':'saved .blend files','assets':entries,
        'limits':'Art resources only. No inventory, weapon rules, ship selection, humanoid rig, collisions or networking.'}
    (ROOT/'game/assets/models/itsasargi_pack/manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
