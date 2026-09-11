"""Photograph delivered GLB geometry without rewriting its file or any .blend. MIT."""
from __future__ import annotations
import json
import struct
import tempfile
from pathlib import Path
import bpy
from mathutils import Vector


def import_for_photo(model: Path) -> None:
    """Blender 4.5's importer iterates None for legacy empty scene node lists.

    Express only those empty lists as []; keep BIN bytes, geometry, transforms,
    materials and scene membership unchanged in a disposable import copy.
    """
    raw=model.read_bytes()
    size,kind=struct.unpack_from('<II',raw,12)
    if kind!=0x4e4f534a:raise ValueError('Missing GLB JSON chunk')
    data=json.loads(raw[20:20+size])
    empty=[s for s in data.get('scenes',[]) if s.get('nodes') is None]
    if not empty:
        bpy.ops.import_scene.gltf(filepath=str(model))
        return
    for scene in empty:scene['nodes']=[]
    encoded=json.dumps(data,separators=(',',':')).encode('utf-8')
    encoded+=b' '*((-len(encoded))%4)
    body=struct.pack('<II',len(encoded),kind)+encoded+raw[20+size:]
    compatible=struct.pack('<III',0x46546c67,2,12+len(body))+body
    print('PHOTO_EMPTY_SCENE_COMPAT',len(empty),'geometry/BIN unchanged',flush=True)
    with tempfile.TemporaryDirectory(prefix='photo-compat-') as folder:
        target=Path(folder)/'view.glb';target.write_bytes(compatible)
        bpy.ops.import_scene.gltf(filepath=str(target))
    if model.read_bytes()!=raw:raise AssertionError('Photo import changed original GLB')


def photograph(model: Path, target: Path, group: str | None = None) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import_for_photo(model)
    scene=bpy.context.scene
    if not any(o.type=='MESH' for o in scene.objects):
        populated=[s for s in bpy.data.scenes if any(o.type=='MESH' for o in s.objects)]
        if len(populated)!=1:raise ValueError('No unambiguous populated scene for photo')
        scene=populated[0]
        bpy.context.window.scene=scene
    scene.frame_set(1)
    if group:
        root=bpy.data.objects.get(group)
        if root is None:raise ValueError('Imported GLB lost submodel '+group)
        keep={root,*root.children_recursive}
        for obj in scene.objects:
            if obj.type=='MESH' and obj not in keep:obj.hide_render=True
    bpy.context.view_layer.update()
    meshes=[o for o in scene.objects if o.type=='MESH' and not o.hide_render]
    if not meshes:raise ValueError('No photographable geometry')
    points=[o.matrix_world@Vector(v) for o in meshes for v in o.bound_box]
    low=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    centre=(low+high)/2
    radius=max((high-low).length/2,.2)
    data=bpy.data.cameras.new('CatalogueCamera')
    camera=bpy.data.objects.new('CatalogueCamera',data)
    scene.collection.objects.link(camera)
    camera.location=centre+Vector((1.25,-1.8,1.25)).normalized()*radius*5
    camera.rotation_euler=(centre-camera.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO';data.clip_end=max(3000,radius*20);data.clip_start=.001
    bpy.context.view_layer.update()
    inv=camera.matrix_world.inverted();projected=[inv@p for p in points]
    data.ortho_scale=max(max(p[i] for p in projected)-min(p[i] for p in projected) for i in (0,1))*1.17
    scene.camera=camera
    scene.world=bpy.data.worlds.new('CatalogueWorld');scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.12,.17,.23,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.55
    for name,direction,power in [('Key',(2,-3,4),1400),('Fill',(-3,-1,2),950),('Rim',(0,3,3),1200)]:
        light_data=bpy.data.lights.new('Catalogue'+name,'AREA')
        light_data.energy=power*radius*radius
        light_data.shape='DISK';light_data.size=radius*3
        light=bpy.data.objects.new(light_data.name,light_data);scene.collection.objects.link(light)
        light.location=centre+Vector(direction)*radius
        light.rotation_euler=(centre-light.location).to_track_quat('-Z','Y').to_euler()
    scene.render.engine='CYCLES';scene.cycles.device='CPU'
    scene.cycles.samples=16;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=4
    scene.render.resolution_x=640;scene.render.resolution_y=640;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
    target.parent.mkdir(parents=True,exist_ok=True);scene.render.filepath=str(target)
    bpy.ops.render.render(write_still=True)
    if not target.is_file():raise RuntimeError('Blender did not write the photograph')
