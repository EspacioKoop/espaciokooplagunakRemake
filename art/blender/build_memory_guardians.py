"""Original navigational automata for the Itsaso memory gallery. Blender 4.5.3.

Run in Blender background mode, or with the bpy module. No reference meshes,
textures or code are imported. Object names preserve editable gaze pivots.
"""
from pathlib import Path
import math
import runpy
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, metallic=0.0, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = .36
    shader.inputs["Emission Color"].default_value = (*color, 1)
    shader.inputs["Emission Strength"].default_value = emission
    return mat


BRASS = material("Memory | brushed copper", (.56, .28, .07), .7)
BLUE = material("Memory | midnight ceramic", (.027, .08, .12), .3)
IVORY = material("Memory | enamel", (.65, .77, .73), .15)
GLOW = material("Memory | amber lens", (.98, .46, .065), .1, 2.0)


def point(xyz):
    x, y, z = xyz
    return Vector((x, -z, y))


def node(name, parent=None, at=(0, 0, 0)):
    ob = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    ob.location = point(at)
    return ob


def finish(ob, name, parent, mat):
    ob.name = name
    ob.parent = parent
    ob.data.materials.append(mat)
    return ob


def box(parent, name, at, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=point(at))
    ob = bpy.context.object
    ob.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel = ob.modifiers.new("Edge radius", "BEVEL")
    bevel.width = .035
    bevel.segments = 2
    return finish(ob, name, parent, mat)


def rod(parent, name, a, b, radius, mat, top=None):
    start, end = point(a), point(b)
    delta = end - start
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=radius,
        radius2=radius if top is None else top, depth=delta.length,
        location=(start + end) * .5)
    ob = bpy.context.object
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = delta.to_track_quat("Z", "Y")
    return finish(ob, name, parent, mat)


def ring(parent, name, at, radius, mat):
    # Ring plane faces Godot +Z; the pivot remains separate in the GLB.
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=.055,
        major_segments=24, minor_segments=8, location=point(at), rotation=(math.pi / 2, 0, 0))
    return finish(bpy.context.object, name, parent, mat)


def crystal(parent, name, at, scale, mat):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1, location=point(at))
    ob = bpy.context.object
    ob.scale = (scale[0], scale[2], scale[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(ob, name, parent, mat)


def automaton(name, keeper=False):
    root = node(name)
    height = 2.0 if keeper else 1.25
    box(root, "Foot | ceramic", (0, .11, 0), (1.0, .22, .85), BLUE)
    box(root, "Foot | copper rim", (0, .25, 0), (.87, .07, .72), BRASS)
    rod(root, "Spindle", (0, .29, 0), (0, height + .05, 0), .21, BLUE, .14)
    for sign in [-1, 1]:
        rod(root, "Arch | upright", (sign * .34, .29, 0), (sign * .34, height, 0), .085, IVORY)
        rod(root, "Arch | shoulder", (sign * .34, height, 0), (0, height + .28, 0), .085, BRASS)
        box(root, "Memory slat", (sign * .28, .7, .17), (.11, .49, .1), BRASS)
    pivot = node("Gaze", root, (0, height + .48, 0))
    ring(pivot, "Gimbal", (0, 0, 0), .38 if keeper else .3, BRASS)
    crystal(pivot, "Lens", (0, 0, .08), (.17, .23, .15), GLOW)
    rod(pivot, "Pointer", (0, -.23, 0), (0, -.23, .46), .04, IVORY, .01)
    if keeper:
        for sign in [-1, 1]:
            rod(root, "Aerial", (sign * .37, 2.05, 0), (sign * .47, 3.12, 0), .025, BRASS)
            crystal(root, "Aerial lamp", (sign * .47, 3.12, 0), (.07, .07, .07), GLOW)
    return root


automaton("memory_keeper", True)
automaton("memory_sentinel")
prism = node("memory_prism")
box(prism, "Plinth", (0, .12, 0), (.7, .24, .7), BLUE)
rod(prism, "Record spindle", (0, .24, 0), (0, 1.25, 0), .13, BRASS)
ring(prism, "Record frame", (0, 1.43, 0), .27, IVORY)
crystal(prism, "Record core", (0, 1.43, 0), (.15, .28, .15), GLOW)
box(prism, "Record plate", (0, .7, .16), (.38, .22, .06), IVORY)

# Preserve the authored object hierarchy in the editable, compressed Blender source.
source = ROOT / "art/blender/memory_guardians.blend"
bpy.ops.wm.save_as_mainfile(filepath=str(source), compress=True)
runpy.run_path(str(ROOT / "art/blender/export_memory_guardians.py"), run_name="__main__")
