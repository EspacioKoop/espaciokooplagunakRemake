"""Original Lantegi models. MIT, no imported art or external textures.
Run with Python + bpy==4.5.3 or blender -b --python ... -- [arguments].
Existing edited .blend files are preserved unless --force is explicitly given.
Blender coordinates: +Z up, +Y forward; glTF/Godot: +Y up, -Z forward.
"""
from __future__ import annotations
import argparse
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SPECS = [
    ('torque_wrench', 'Giltza · llave dinamométrica', 'tools', 'Mordaza articulada y ajuste de par', 'grip'),
    ('sample_drill', 'Zunda · taladro de muestras', 'tools', 'Corona de muestreo, cartucho y empuñadura auxiliar', 'grip'),
    ('hull_patcher', 'Jostura · aplicador de parches', 'tools', 'Cabezal de sellado y cartucho de polímero ficticio', 'grip'),
    ('foam_extinguisher', 'Apar · extintor de espuma', 'tools', 'Depósito, manguera y palanca de servicio', 'floor'),
    ('power_bridge', 'Zubi · batería puente', 'tools', 'Batería portátil con pinzas y conectores', 'floor'),
    ('folding_floodlight', 'Argi · foco plegable', 'tools', 'Trípode, cabezal basculante y asa', 'floor'),
    ('pulse_disc', 'Uhin · proyector de discos', 'weapons', 'Arma de ciencia ficción con rotor emisor', 'grip'),
    ('ion_carbine', 'Trumoi · carabina iónica', 'weapons', 'Arma de ciencia ficción con celda y disipador móvil', 'grip'),
    ('enara_courier', 'Enara · nave mensajera', 'ships', 'Mensajera de ala barrida, dos motores y tren articulado', 'centre'),
    ('dortoka_freighter', 'Dortoka · transporte logístico', 'ships', 'Transporte logístico con rampa y módulos de carga laterales', 'centre'),
]
M = {}


def material(name, color, metal=0.0, rough=0.45, emission=0.0):
    mat = bpy.data.materials.new('LT_' + name)
    mat.use_nodes = True
    node = mat.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value = (*color, 1)
    node.inputs['Metallic'].default_value = metal
    node.inputs['Roughness'].default_value = rough
    if emission:
        node.inputs['Emission Color'].default_value = (*color, 1)
        node.inputs['Emission Strength'].default_value = emission
    mat.diffuse_color = (*color, 1)
    return mat


def reset(ident, title):
    global M
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = {
        'shell': material('ceramic', (.59, .72, .72), .48, .33),
        'white': material('porcelain', (.83, .87, .82), .26, .39),
        'teal': material('deep_teal', (.025, .21, .24), .62, .3),
        'dark': material('graphite', (.025, .041, .055), .65, .34),
        'rubber': material('rubber', (.022, .028, .031), .0, .77),
        'steel': material('machined_titanium', (.39, .49, .55), .86, .25),
        'copper': material('copper', (.55, .22, .065), .75, .3),
        'orange': material('rescue_orange', (.98, .24, .035), .32, .4),
        'red': material('safety_red', (.52, .035, .022), .34, .36),
        'glass': material('opaque_optical_glass', (.018, .055, .085), .62, .16),
        'cyan': material('cyan_emitter', (.06, .8, .87), .22, .24, 2),
        'amber': material('amber_emitter', (1., .32, .045), .1, .28, 1.3),
        'violet': material('ion_emitter', (.38, .16, .9), .2, .27, 2.0),
    }
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = 61
    scene.name = 'mechanical_cycle'
    root = empty(ident)
    root['asset_id'] = 'lantegi/' + ident
    root['title'] = title
    root['license'] = 'MIT'
    root['version'] = 1
    root['units'] = 'metres'
    return root


def empty(name, parent=None, pos=(0, 0, 0)):
    ob = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    ob.location = pos
    ob.empty_display_type = 'PLAIN_AXES'
    ob.empty_display_size = .06
    return ob


def socket(name, parent, pos=(0, 0, 0)):
    ob = empty('socket_' + name, parent, pos)
    ob['purpose'] = name
    return ob


def finish(ob, name, pos, mat, parent, bevel=0, smooth=False):
    ob.name = name
    ob.parent = parent
    ob.location = pos
    ob.data.materials.append(M[mat])
    if smooth:
        for face in ob.data.polygons:
            face.use_smooth = len(face.vertices) == 4
    if bevel:
        mod = ob.modifiers.new('Manufactured_edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = 'ANGLE'
        mod = ob.modifiers.new('Weighted_normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
    return ob


def box(name, pos, size, mat, parent, bevel=.007, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob = bpy.context.object
    ob.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish(ob, name, pos, mat, parent, min(bevel, min(size) * .25))
    if rot:
        ob.rotation_euler = rot
    return ob


def cylinder(name, pos, radius, depth, mat, parent, axis=(0, 0, 1), sides=32, bevel=.003):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=depth)
    ob = finish(bpy.context.object, name, pos, mat, parent, min(bevel, radius * .2, depth * .2), True)
    ob.rotation_euler = Vector(axis).to_track_quat('Z', 'Y').to_euler()
    return ob


def taper(name, pos, r1, r2, depth, mat, parent, axis=(0, 0, 1), sides=32):
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r1, radius2=r2, depth=depth)
    ob = finish(bpy.context.object, name, pos, mat, parent, .002, True)
    ob.rotation_euler = Vector(axis).to_track_quat('Z', 'Y').to_euler()
    return ob


def ring(name, pos, radius, thickness, mat, parent, axis=(0, 0, 1)):
    bpy.ops.mesh.primitive_torus_add(major_segments=36, minor_segments=8,
                                   major_radius=radius, minor_radius=thickness)
    ob = finish(bpy.context.object, name, pos, mat, parent, smooth=True)
    ob.rotation_euler = Vector(axis).to_track_quat('Z', 'Y').to_euler()
    for face in ob.data.polygons:
        face.use_smooth = True
    return ob


def beam(name, a, b, width, mat, parent, square=False):
    a, b = Vector(a), Vector(b)
    delta = b - a
    if square:
        ob = box(name, (a + b) * .5, (width, width, delta.length), mat, parent, width * .15)
        ob.rotation_euler = delta.to_track_quat('Z', 'Y').to_euler()
        return ob
    return cylinder(name, (a + b) * .5, width * .5, delta.length, mat, parent, delta, 16)


def polygon(name, points, z, depth, mat, parent, bevel=.01):
    n = len(points)
    vertices = [(x, y, z + h) for h in (-depth * .5, depth * .5) for x, y in points]
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    return finish(ob, name, (0, 0, 0), mat, parent, bevel)


def loft(name, sections, mat, parent, bevel=.025):
    # Hand-authored octagonal cross-sections along forward +Y; no zero-area tips.
    profile = [(-.65, -1), (.65, -1), (1, -.55), (1, .55),
               (.65, 1), (-.65, 1), (-1, .55), (-1, -.55)]
    verts = [(x * w, y, zz + z * h) for y, w, h, zz in sections for x, z in profile]
    faces = [tuple(reversed(range(8))), tuple(range(len(verts) - 8, len(verts)))]
    for j in range(len(sections) - 1):
        for k in range(8):
            faces.append((j * 8 + k, j * 8 + (k + 1) % 8,
                          (j + 1) * 8 + (k + 1) % 8, (j + 1) * 8 + k))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    return finish(ob, name, (0, 0, 0), mat, parent, bevel)


def hose(name, points, radius, mat, parent):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 8
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    curve.use_fill_caps = True
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for bp, co in zip(spline.bezier_points, points):
        bp.co = co
        bp.handle_left_type = 'AUTO'
        bp.handle_right_type = 'AUTO'
    ob = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(ob)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.object, name, (0, 0, 0), mat, parent, smooth=True)


def animate(ob, prop, poses):
    for frame, value in poses:
        setattr(ob, prop, value)
        ob.keyframe_insert(data_path=prop, frame=frame, group='Mechanical')
    if ob.animation_data and ob.animation_data.action:
        ob.animation_data.action.name = ob.name + '_cycle'
    bpy.context.scene.frame_set(1)


def grip(parent, y=0, z=0, length=.19):
    box('Grip_core', (0, y, z), (.076, .083, length), 'dark', parent, .015,
        (math.radians(-12), 0, 0))
    for i in range(6):
        box('Grip_rib', (0, y - .004, z - length * .38 + i * length * .145),
            (.083, .086, .012), 'rubber', parent, .003)
    box('Grip_end', (0, y, z - length * .55), (.083, .095, .028), 'teal', parent)


def screen(parent, pos, width=.08, length=.1):
    x, y, z = pos
    box('Screen_rim', (x, y, z), (width + .019, length + .019, .018), 'dark', parent)
    box('Screen_glass', (x, y, z + .011), (width, length, .004), 'glass', parent, .002)
    for i, ratio in enumerate((.73, .46, .62)):
        box('Screen_bar', (x - width * (1 - ratio) * .4, y - length * .28 + i * length * .25, z + .014),
            (width * ratio * .8, .004, .0015), 'cyan', parent, .0003)


def bolt(parent, pos, axis=(0, 0, 1), size=.007):
    cylinder('Fastener', pos, size, size * .65, 'steel', parent, axis, 6, size * .08)


def vents(parent, pos, count=5, spacing=.028, length=.09, axis='y'):
    x, y, z = pos
    for i in range(count):
        if axis == 'y':
            box('Vent_louvre', (x, y + i * spacing, z), (length, .008, .006), 'dark', parent, .001)
        else:
            box('Vent_louvre', (x + i * spacing, y, z), (.008, length, .006), 'dark', parent, .001)


def torque_wrench(r):
    grip(r, z=-.01, length=.23)
    box('Torque_body', (0, .055, .145), (.105, .18, .15), 'shell', r, .016)
    screen(r, (0, .05, .223), .068, .104)
    beam('Spine', (0, .09, .17), (0, .3, .17), .056, 'steel', r, True)
    polygon('Fixed_jaw', [(-.08, .27), (-.065, .4), (.065, .4), (.09, .36),
                         (.045, .355), (.04, .31), (-.032, .31), (-.045, .265)], .17, .064, 'steel', r, .006)
    moving = empty('Jaw_slide', r, (.036, .276, .17))
    box('Moving_jaw', (0, 0, 0), (.045, .088, .07), 'teal', moving)
    for i in range(5):
        box('Jaw_teeth', (-.026, -.025 + i * .012, 0), (.012, .005, .06), 'steel', moving, .001)
    animate(moving, 'location', [(1, (.036, .276, .17)), (31, (.088, .276, .17)), (61, (.036, .276, .17))])
    cylinder('Adjustment_wheel', (.066, .215, .17), .038, .034, 'copper', r, (1, 0, 0), 24)
    for i in range(8):
        a = i * math.tau / 8
        bolt(r, (.085, .215 + .027 * math.cos(a), .17 + .027 * math.sin(a)), (1, 0, 0), .004)
    ring('Lanyard', (0, -.02, -.162), .022, .005, 'steel', r, (1, 0, 0))
    socket('grip', r)
    socket('tool_tip', r, (0, .36, .17))
    socket('holster', r, (-.055, .02, .13))


def sample_drill(r):
    grip(r, z=-.005)
    loft('Drill_shell', [(-.16, .07, .08, .155), (-.08, .105, .10, .155),
                         (.16, .085, .085, .155), (.24, .06, .065, .155)], 'teal', r, .008)
    box('Battery', (0, -.028, -.14), (.14, .145, .09), 'orange', r, .018)
    for x in (-.105, .105):
        box('Side_armour', (x, .045, .155), (.017, .22, .09), 'shell', r)
        for y in (-.025, .095):
            bolt(r, (x * 1.09, y, .155), (1, 0, 0))
    vents(r, (0, -.115, .247), 5, .022, .095)
    cylinder('Chuck', (0, .23, .155), .074, .11, 'dark', r, (0, 1, 0))
    spindle = empty('Sample_spindle', r, (0, .295, .155))
    cylinder('Bit_shaft', (0, .11, 0), .033, .22, 'steel', spindle, (0, 1, 0), 24)
    for y in (.035, .085, .135, .185):
        ring('Cutting_flute', (0, y, 0), .042, .011, 'copper', spindle, (0, 1, 0))
    ring('Sample_crown', (0, .235, 0), .048, .011, 'steel', spindle, (0, 1, 0))
    for i in range(8):
        a = i * math.tau / 8
        box('Crown_tooth', (.049 * math.cos(a), .245, .049 * math.sin(a)),
            (.018, .026, .018), 'steel', spindle, .002)
    animate(spindle, 'rotation_euler', [(1, (0, 0, 0)), (16, (0, math.pi / 2, 0)),
                                       (31, (0, math.pi, 0)), (46, (0, math.pi * 1.5, 0)), (61, (0, math.tau, 0))])
    beam('Auxiliary_mount', (.05, .14, .1), (.16, .14, .075), .035, 'steel', r)
    cylinder('Auxiliary_grip', (.175, .14, -.005), .032, .15, 'rubber', r)
    socket('grip', r)
    socket('support_hand', r, (.175, .14, -.005))
    socket('tool_tip', r, (0, .556, .155))
    socket('sample', spindle, (0, .25, 0))


def hull_patcher(r):
    grip(r, length=.2)
    box('Patcher_chassis', (0, .04, .145), (.13, .24, .13), 'shell', r, .022)
    cylinder('Polymer_reservoir', (0, -.15, .145), .084, .2, 'orange', r, (0, 1, 0))
    for y in (-.23, -.08):
        ring('Reservoir_clamp', (0, y, .145), .087, .009, 'dark', r, (0, 1, 0))
    cylinder('Cartridge_cap', (0, -.259, .145), .065, .025, 'steel', r, (0, 1, 0))
    head = empty('Seal_head', r, (0, .205, .145))
    box('Seal_head_mount', (0, 0, 0), (.16, .13, .075), 'dark', head)
    box('Seal_plate', (0, .086, 0), (.24, .047, .15), 'teal', head, .012)
    box('Seal_pad', (0, .114, 0), (.208, .018, .119), 'rubber', head, .009)
    for x in (-.115, .115):
        cylinder('Pressure_roller', (x, .111, 0), .018, .13, 'steel', head)
    animate(head, 'location', [(1, (0, .205, .145)), (31, (0, .255, .145)), (61, (0, .205, .145))])
    hose('Feed_hose', [(.076, -.17, .145), (.12, -.035, .095), (.12, .1, .135), (.062, .178, .145)], .012, 'rubber', r)
    screen(r, (0, .01, .217), .083, .13)
    for x in (-.045, .045):
        box('Status_strip', (x, .12, .217), (.013, .05, .005), 'amber', r, .001)
    socket('grip', r)
    socket('application', head, (0, .128, 0))
    socket('cartridge', r, (0, -.26, .145))


def foam_extinguisher(r):
    cylinder('Tank', (0, 0, .29), .12, .42, 'red', r, sides=40, bevel=.008)
    taper('Tank_shoulder', (0, 0, .525), .12, .064, .09, 'red', r)
    cylinder('Tank_foot', (0, 0, .065), .13, .1, 'rubber', r, bevel=.006)
    cylinder('Valve', (0, 0, .591), .031, .068, 'steel', r)
    for z in (.16, .405):
        ring('Tank_band', (0, 0, z), .122, .008, 'shell', r)
    # Raised safety emblem, geometry not a texture or medical marking.
    box('Safety_panel', (0, .121, .287), (.116, .01, .115), 'white', r)
    for z in (.26, .287, .314):
        box('Safety_mark', (0, .128, z), (.065, .005, .01), 'red', r, .001)
    beam('Handle_left', (-.052, -.035, .565), (-.052, -.1, .65), .023, 'dark', r, True)
    beam('Handle_right', (.052, -.035, .565), (.052, -.1, .65), .023, 'dark', r, True)
    beam('Handle_crossbar', (-.055, -.1, .65), (.055, -.1, .65), .028, 'rubber', r, True)
    lever = empty('Valve_lever', r, (0, -.006, .619))
    box('Lever', (0, -.065, .005), (.035, .145, .014), 'orange', lever)
    animate(lever, 'rotation_euler', [(1, (0, 0, 0)), (31, (.22, 0, 0)), (61, (0, 0, 0))])
    cylinder('Gauge_rim', (0, .045, .615), .032, .02, 'steel', r, (0, 1, 0))
    cylinder('Gauge_face', (0, .057, .615), .027, .004, 'glass', r, (0, 1, 0))
    beam('Gauge_needle', (0, .061, .6), (.018, .061, .63), .004, 'amber', r)
    hose('Extinguisher_hose', [(.032, 0, .59), (.18, -.09, .61), (.2, -.04, .3), (.18, .14, .29)], .017, 'rubber', r)
    taper('Foam_nozzle', (.18, .235, .29), .022, .052, .19, 'dark', r, (0, 1, 0))
    ring('Nozzle_lip', (.18, .333, .29), .05, .007, 'orange', r, (0, 1, 0))
    socket('grip', r, (0, -.1, .65))
    socket('nozzle', r, (.18, .34, .29))
    socket('wall_mount', r, (0, -.128, .32))


def power_bridge(r):
    box('Battery_case', (0, 0, .18), (.47, .28, .31), 'teal', r, .038)
    for x in (-.24, .24):
        box('Shock_guard', (x, 0, .18), (.06, .31, .36), 'rubber', r, .026)
        box('Side_plate', (x * 1.04, 0, .18), (.026, .24, .24), 'shell', r, .014)
        for y in (-.085, .085):
            for z in (.1, .26):
                bolt(r, (x * 1.12, y, z), (1, 0, 0), .009)
    for x in (-.14, .14):
        beam('Handle_upright', (x, 0, .33), (x, 0, .45), .034, 'steel', r, True)
    beam('Carry_handle', (-.15, 0, .45), (.15, 0, .45), .045, 'rubber', r, True)
    screen(r, (0, .071, .341), .13, .075)
    for i in range(4):
        box('Charge_bar', (-.065 + i * .043, .144, .23), (.027, .006, .022), 'cyan', r, .002)
    for sign, color in ((-1, 'orange'), (1, 'cyan')):
        x = sign * .12
        cylinder('Output_socket', (x, .151, .12), .035, .038, 'steel', r, (0, 1, 0))
        cylinder('Output_insulator', (x, .174, .12), .022, .012, color, r, (0, 1, 0))
        hose('Power_lead', [(x, -.08, .34), (sign * .25, -.2, .35),
                            (sign * .29, -.23, .12), (sign * .1, -.21, .13)], .009, 'rubber', r)
        clamp = empty('Clamp_' + ('left' if sign < 0 else 'right'), r, (sign * .075, -.195, .22))
        box('Clamp_grip', (0, 0, 0), (.032, .047, .15), color, clamp)
        box('Clamp_contact', (0, 0, .091), (.025, .035, .045), 'copper', clamp)
        animate(clamp, 'rotation_euler', [(1, (0, 0, 0)), (31, (0, sign * .18, 0)), (61, (0, 0, 0))])
    socket('grip', r, (0, 0, .45))
    socket('output_left', r, (-.12, .184, .12))
    socket('output_right', r, (.12, .184, .12))
    socket('mount', r, (0, 0, .02))


def folding_floodlight(r):
    cylinder('Tripod_hub', (0, 0, .18), .066, .12, 'dark', r)
    for i in range(3):
        a = i * math.tau / 3
        foot = (.28 * math.cos(a), .28 * math.sin(a), .027)
        beam('Tripod_leg', (.033 * math.cos(a), .033 * math.sin(a), .21), foot, .03, 'steel', r, True)
        box('Foot_pad', foot, (.077, .065, .028), 'rubber', r, .009, (0, 0, a))
    cylinder('Mast', (0, 0, .39), .024, .43, 'steel', r)
    cylinder('Mast_collar', (0, 0, .41), .034, .048, 'orange', r)
    for x in (-.153, .153):
        beam('Yoke', (0, 0, .6), (x, 0, .63), .032, 'dark', r, True)
        beam('Yoke_upright', (x, 0, .63), (x, 0, .78), .032, 'dark', r, True)
        cylinder('Tilt_knob', (x * 1.1, 0, .78), .032, .033, 'orange', r, (1, 0, 0), 16)
    head = empty('Light_head', r, (0, 0, .78))
    box('Head_shell', (0, -.005, 0), (.283, .101, .183), 'teal', head, .022)
    box('Reflector', (0, .052, 0), (.256, .017, .157), 'steel', head, .01)
    for x in (-.084, 0, .084):
        for z in (-.042, .042):
            box('LED_lens', (x, .065, z), (.066, .012, .056), 'white', head, .008)
            box('LED_emitter', (x, .073, z), (.046, .005, .034), 'cyan', head, .004)
    for x in (-.08, -.04, 0, .04, .08):
        box('Cooling_fin', (x, -.066, 0), (.009, .031, .12), 'dark', head, .002)
    beam('Carry_handle', (-.11, -.045, .122), (.11, -.045, .122), .026, 'rubber', head, True)
    for x in (-.11, .11):
        beam('Handle_leg', (x, -.045, .07), (x, -.045, .122), .018, 'steel', head, True)
    animate(head, 'rotation_euler', [(1, (0, 0, 0)), (31, (-1.1, 0, 0)), (61, (0, 0, 0))])
    box('Power_pack', (0, -.076, .23), (.11, .087, .12), 'orange', r)
    socket('grip', head, (0, -.045, .122))
    socket('light', head, (0, .079, 0))
    socket('floor', r)


def pulse_disc(r):
    grip(r)
    box('Emitter_body', (0, .085, .145), (.132, .24, .1), 'dark', r, .02)
    box('Upper_armour', (0, .045, .206), (.14, .15, .039), 'shell', r)
    cylinder('Emitter_spine', (0, .185, .155), .051, .14, 'steel', r, (0, 1, 0))
    rotor = empty('Pulse_rotor', r, (0, .265, .155))
    ring('Emitter_ring', (0, 0, 0), .096, .017, 'dark', rotor, (0, 1, 0))
    ring('Emitter_channel', (0, .017, 0), .094, .006, 'cyan', rotor, (0, 1, 0))
    cylinder('Emitter_core', (0, .012, 0), .032, .052, 'glass', rotor, (0, 1, 0))
    cylinder('Core_lens', (0, .041, 0), .022, .005, 'cyan', rotor, (0, 1, 0))
    for i in range(6):
        a = i * math.tau / 6
        beam('Rotor_spoke', (.032 * math.cos(a), 0, .032 * math.sin(a)),
             (.088 * math.cos(a), 0, .088 * math.sin(a)), .011, 'steel', rotor)
        box('Emitter_segment', (.101 * math.cos(a), 0, .101 * math.sin(a)),
            (.035, .071, .037), 'teal', rotor, .006, (0, -a, 0))
    animate(rotor, 'rotation_euler', [(1, (0, 0, 0)), (31, (0, math.pi, 0)), (61, (0, math.tau, 0))])
    for x in (-.087, .087):
        beam('Protective_rail', (x, -.03, .185), (x, .24, .185), .018, 'orange', r, True)
    box('Power_cell', (0, -.071, .145), (.08, .056, .09), 'teal', r)
    socket('grip', r)
    socket('emitter', r, (0, .312, .155))
    socket('holster', r, (-.076, .05, .16))


def ion_carbine(r):
    grip(r, y=-.11)
    loft('Carbine_receiver', [(-.31, .058, .047, .16), (-.18, .075, .08, .16),
                              (.19, .065, .068, .16), (.29, .039, .041, .16)], 'dark', r, .008)
    polygon('Stock', [(-.064, -.23), (-.06, -.48), (.06, -.48), (.064, -.23)], .123, .16, 'teal', r, .008)
    box('Shoulder_pad', (0, -.485, .123), (.143, .035, .19), 'rubber', r, .014)
    for x in (-.075, .075):
        box('Receiver_panel', (x, -.015, .178), (.015, .25, .07), 'shell', r)
        for y in (-.11, .085):
            bolt(r, (x * 1.1, y, .178), (1, 0, 0), .006)
    cylinder('Ion_conduit', (0, .32, .16), .032, .24, 'steel', r, (0, 1, 0))
    for y in (.24, .29, .34, .39):
        ring('Ion_coil', (0, y, .16), .041, .008, 'violet', r, (0, 1, 0))
    taper('Emitter_shroud', (0, .455, .16), .039, .051, .095, 'teal', r, (0, 1, 0), 16)
    ring('Emitter_rim', (0, .505, .16), .05, .008, 'steel', r, (0, 1, 0))
    cylinder('Emitter_optic', (0, .51, .16), .033, .005, 'violet', r, (0, 1, 0))
    sled = empty('Cooling_sled', r, (0, .02, .235))
    box('Heat_sink', (0, 0, 0), (.09, .2, .034), 'teal', sled)
    vents(sled, (0, -.075, .021), 7, .026, .081)
    animate(sled, 'location', [(1, (0, .02, .235)), (31, (0, -.045, .255)), (61, (0, .02, .235))])
    box('Foregrip', (0, .16, .035), (.07, .085, .14), 'rubber', r, .015)
    box('Ion_cell', (0, -.012, .022), (.078, .117, .14), 'teal', r, .012, (.16, 0, 0))
    for x in (-.041, .041):
        box('Cell_indicator', (x, -.005, .03), (.006, .06, .049), 'cyan', r, .002)
    box('Sight_base', (0, -.19, .257), (.056, .084, .033), 'steel', r)
    box('Sight_frame', (0, -.19, .295), (.067, .029, .057), 'dark', r)
    box('Sight_lens', (0, -.172, .3), (.04, .004, .028), 'glass', r)
    socket('grip', r, (0, -.11, 0))
    socket('support_hand', r, (0, .16, .035))
    socket('emitter', r, (0, .52, .16))
    socket('sight', r, (0, -.19, .3))
    socket('shoulder', r, (0, -.505, .123))


def engine(parent, name, pos, radius, length):
    group = empty(name, parent, pos)
    cylinder('Engine_casing', (0, 0, 0), radius, length, 'dark', group, (0, 1, 0), 32, .024)
    for y in (-length * .36, length * .3):
        ring('Engine_band', (0, y, 0), radius * 1.015, radius * .075, 'steel', group, (0, 1, 0))
    taper('Engine_intake', (0, length * .47, 0), radius, radius * .73, length * .17, 'teal', group, (0, 1, 0))
    cylinder('Intake_dark', (0, length * .565, 0), radius * .63, .025, 'glass', group, (0, 1, 0), 32)
    taper('Engine_nozzle', (0, -length * .55, 0), radius * .85, radius * .64, length * .18, 'steel', group, (0, 1, 0))
    cylinder('Exhaust_core', (0, -length * .65, 0), radius * .52, .026, 'cyan', group, (0, 1, 0))
    ring('Exhaust_ring', (0, -length * .65, 0), radius * .72, radius * .045, 'orange', group, (0, 1, 0))
    for i in range(8):
        a = i * math.tau / 8
        beam('Engine_strake', (radius * math.cos(a), -length * .26, radius * math.sin(a)),
             (radius * math.cos(a), length * .18, radius * math.sin(a)), radius * .05, 'shell', group, True)
    return group


def gear(parent, name, pos, size=1.0):
    pivot = empty(name, parent, pos)
    beam('Landing_strut', (0, 0, 0), (0, 0, -.7 * size), .11 * size, 'steel', pivot)
    beam('Landing_brace', (0, .32 * size, .02), (0, 0, -.55 * size), .063 * size, 'dark', pivot)
    box('Landing_skid', (0, .025 * size, -.73 * size), (.34 * size, .75 * size, .1 * size), 'rubber', pivot, .03)
    animate(pivot, 'rotation_euler', [(1, (0, 0, 0)), (31, (-1.2, 0, 0)), (61, (0, 0, 0))])
    socket(name + '_contact', pivot, (0, .025 * size, -.79 * size))


def enara_courier(r):
    loft('Courier_fuselage', [(-3.4, .68, .48, 0), (-2.4, 1.12, .63, 0),
                             (.5, .95, .57, .04), (2.7, .53, .38, .025),
                             (4.25, .085, .075, 0)], 'shell', r, .075)
    loft('Ventral_keel', [(-2.6, .37, .13, -.57), (.8, .33, .12, -.5),
                         (3.25, .1, .065, -.22)], 'dark', r, .025)
    loft('Cockpit_canopy', [(.0, .62, .17, .58), (.5, .68, .36, .64),
                           (1.55, .52, .31, .58), (2.45, .17, .1, .36)], 'glass', r, .035)
    for sign in (-1, 1):
        wing = [(sign * .65, -.1), (sign * 2.7, -2.6), (sign * 3.65, -3.5),
                (sign * 2.75, -3.8), (sign * .58, -2.3)]
        polygon('Swept_wing', wing, -.06, .2, 'teal', r, .047)
        polygon('Wing_armour', [(sign * 1.05, -.7), (sign * 2.8, -2.86),
                                (sign * 2.25, -3.12), (sign * 1.0, -2.11)], .067, .028, 'shell', r, .01)
        polygon('Rescue_stripe', [(sign * 1.51, -1.57), (sign * 1.77, -1.88),
                                  (sign * 1.49, -2.56), (sign * 1.29, -2.39)], .087, .013, 'orange', r, .004)
        group = engine(r, 'Engine_' + ('left' if sign < 0 else 'right'), (sign * 1.37, -2.48, .05), .39, 1.86)
        socket('exhaust_' + ('left' if sign < 0 else 'right'), group, (0, -1.23, 0))
        fin = polygon('Tail_fin', [(sign * .62, -2.31), (sign * .68, -3.55),
                                   (sign * 1.33, -3.23), (sign * .99, -2.17)], 0, .095, 'teal', r, .015)
        fin.rotation_euler[1] = sign * 1.08
        fin.location.z = .67
        beam('Cockpit_frame', (sign * .62, .4, .86), (sign * .2, 2.24, .5), .037, 'steel', r)
        cylinder('Navigation_lamp', (sign * 3.31, -3.21, .025), .053, .035,
                 'red' if sign < 0 else 'cyan', r)
        socket('wing_' + ('left' if sign < 0 else 'right'), r, (sign * 2.4, -2.65, -.17))
    for y in (-2.31, -1.98, -1.65):
        box('Dorsal_louvre', (0, y, .654), (.93, .11, .045), 'dark', r, .009)
    box('Dorsal_rescue_line', (0, -1.02, .632), (.18, .95, .02), 'orange', r)
    gear(r, 'gear_front', (0, 1.31, -.36), .65)
    gear(r, 'gear_left', (-.85, -2, -.43), .85)
    gear(r, 'gear_right', (.85, -2, -.43), .85)
    socket('pilot', r, (0, .73, .45))
    socket('cargo', r, (0, -1, 0))
    socket('docking', r, (0, -3.49, .02))
    socket('sensor', r, (0, 4.27, 0))


def dortoka_freighter(r):
    loft('Rescue_hull', [(-5.1, 1.6, 1.03, .03), (-4.05, 2.08, 1.37, .1),
                        (1.4, 2.08, 1.35, .1), (3.9, 1.48, .98, .12),
                        (5.05, .55, .53, -.03)], 'white', r, .095)
    loft('Belly_armour', [(-4.75, 1.42, .16, -1.01), (2.7, 1.6, .2, -.99),
                         (4.25, .85, .12, -.71)], 'teal', r, .045)
    loft('Bridge_canopy', [(1.37, 1.31, .14, 1.25), (2.11, 1.24, .41, 1.22),
                          (3.25, .98, .36, 1.08), (3.99, .6, .17, .87)], 'glass', r, .035)
    for sign in (-1, 1):
        s = 'left' if sign < 0 else 'right'
        for y in (-2.8, .1):
            beam('Engine_pylon', (sign * 1.74, y, -.1), (sign * 2.92, y, -.1), .28, 'steel', r, True)
        group = engine(r, 'Rescue_engine_' + s, (sign * 3.05, -1.72, -.07), .71, 4.8)
        socket('exhaust_' + s, group, (0, -3.15, 0))
        loft('Side_pod_' + s, [(-2.9, .42, .49, .31), (-2.4, .48, .55, .31),
                               (.7, .48, .55, .31), (1.25, .28, .33, .31)], 'orange', r, .035).location.x = sign * 2.14
        for y in (-2.2, -.75, .5):
            box('Pod_band', (sign * 2.59, y, .31), (.045, .15, .76), 'dark', r, .017)
            box('Pod_window', (sign * 2.63, y + .36, .43), (.032, .32, .21), 'glass', r, .014)
        polygon('Shoulder_wing', [(sign * 1.5, -3.2), (sign * 4.07, -3.05),
                                  (sign * 3.5, -4.6), (sign * 1.47, -4.39)], .55, .22, 'teal', r, .042)
        box('Upper_rescue_stripe', (sign * 1.28, -1.2, 1.464), (.29, 4.45, .028), 'orange', r)
        for y in (-2.35, -.88, .58):
            box('Roof_module', (sign * .61, y, 1.498), (.58, .88, .15), 'shell', r, .04)
            vents(r, (sign * .61, y - .28, 1.58), 5, .13, .41)
        gear(r, 'gear_rear_' + s, (sign * 1.36, -3.52, -.96), 1.15)
        gear(r, 'gear_front_' + s, (sign * 1.16, 2.13, -.96), 1.15)
        socket('cargo_pod_' + s, r, (sign * 2.13, -.75, .32))
        socket('docking_' + s, r, (sign * 2.67, .8, .3))
    # Rear sill and side rails leave the moving cargo ramp readable from outside.
    for x in (-1.46, 1.46):
        box('Hatch_frame', (x, -5.16, .035), (.15, .18, 1.98), 'dark', r, .035)
    box('Hatch_header', (0, -5.16, 1.02), (3.06, .18, .13), 'dark', r)
    ramp = empty('Cargo_ramp', r, (0, -5.2, -.88))
    box('Ramp_armour', (0, -.015, .86), (2.69, .14, 1.72), 'teal', ramp, .035)
    box('Ramp_tread', (0, -.092, .86), (2.39, .024, 1.46), 'dark', ramp, .015)
    for z in (.3, .54, .78, 1.02, 1.26, 1.5):
        box('Ramp_grip_strip', (0, -.11, z), (2.32, .019, .055), 'steel', ramp, .009)
    for x in (-1.19, 1.19):
        box('Ramp_hazard', (x, -.11, .86), (.072, .026, 1.53), 'orange', ramp)
    animate(ramp, 'rotation_euler', [(1, (0, 0, 0)), (31, (1.64, 0, 0)), (61, (0, 0, 0))])
    socket('ramp_tip', ramp, (0, 0, 1.72))
    socket('cargo', r, (0, -3.6, -.75))
    socket('pilot', r, (-.52, 2.45, .95))
    socket('copilot', r, (.52, 2.45, .95))
    socket('nose_sensor', r, (0, 5.09, 0))


BUILDERS = {name: globals()[name] for name, *_ in SPECS}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--missing-only', action='store_true')
    mode.add_argument('--force', action='store_true')
    parser.add_argument('--only', choices=list(BUILDERS))
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    args = parser.parse_args(argv)
    chosen = [spec for spec in SPECS if not args.only or spec[0] == args.only]
    if not args.missing_only and not args.force:
        existing = [name for name, *_ in chosen if (HERE / (name + '.blend')).exists()]
        if existing:
            raise SystemExit('Refusing to overwrite edited sources: ' + ', '.join(existing))
    for ident, title, category, description, pivot in chosen:
        target = HERE / (ident + '.blend')
        if target.exists() and args.missing_only:
            print('PRESERVED', ident, flush=True)
            continue
        root = reset(ident, title)
        root['category'] = category
        root['pivot'] = pivot
        root['description'] = description
        BUILDERS[ident](root)
        bpy.context.scene.frame_set(1)
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action='DESELECT')
        root.select_set(True)
        bpy.context.view_layer.objects.active = root
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(target), compress=True)
        print('SOURCE_SAVED', ident, len(root.children_recursive), flush=True)
    print('LANTEGI_BUILD_PASS', flush=True)


if __name__ == '__main__':
    main()
