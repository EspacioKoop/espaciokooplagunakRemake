"""Photograph a delivered GLB (or named submodel), without saving any .blend. MIT."""
from __future__ import annotations
from pathlib import Path
import bpy
from mathutils import Vector


def photograph(model: Path, target: Path, group: str | None = None) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(model))
    scene=bpy.context.scene
    scene.frame_set(1)
    if group:
        root=bpy.data.objects.get(group)
        if root is None:
            raise ValueError('Imported GLB lost submodel '+group)
        keep={root,*root.children_recursive}
        for obj in scene.objects:
            if obj.type=='MESH' and obj not in keep:
                obj.hide_render=True
    bpy.context.view_layer.update()
    meshes=[o for o in scene.objects if o.type=='MESH' and not o.hide_render]
    if not meshes:
        raise ValueError('No photographable geometry')
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
    data.type='ORTHO'
    data.clip_end=max(3000,radius*20)
    data.clip_start=.001
    bpy.context.view_layer.update()
    inv=camera.matrix_world.inverted()
    projected=[inv@p for p in points]
    data.ortho_scale=max(max(p[i] for p in projected)-min(p[i] for p in projected) for i in (0,1))*1.17
    scene.camera=camera
    scene.world=bpy.data.worlds.new('CatalogueWorld')
    scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.12,.17,.23,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.55
    for name,direction,power in [('Key',(2,-3,4),1400),('Fill',(-3,-1,2),950),('Rim',(0,3,3),1200)]:
        light_data=bpy.data.lights.new('Catalogue'+name,'AREA')
        light_data.energy=power*radius*radius
        light_data.shape='DISK';light_data.size=radius*3
        light=bpy.data.objects.new(light_data.name,light_data)
        scene.collection.objects.link(light)
        light.location=centre+Vector(direction)*radius
        light.rotation_euler=(centre-light.location).to_track_quat('-Z','Y').to_euler()
    scene.render.engine='CYCLES';scene.cycles.device='CPU'
    scene.cycles.samples=16;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=4
    scene.render.resolution_x=640;scene.render.resolution_y=640;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
    target.parent.mkdir(parents=True,exist_ok=True)
    scene.render.filepath=str(target)
    bpy.ops.render.render(write_still=True)
    if not target.is_file():raise RuntimeError('Blender did not write the photograph')
