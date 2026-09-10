"""Original Orbita library. Blender/bpy 4.5.3, Python 3.11; no downloaded art.

Run from repository root: python art/blender/orbita_pack/build.py
Blender CLI: blender -b --python art/blender/orbita_pack/build.py
Existing .blend files are never replaced unless --force is explicit.
Use export.py after manual edits; do NOT regenerate an edited source.
Coordinates in helpers are Godot metres: X right, Y up, -Z forward.
"""
from __future__ import annotations
import argparse
import math
import random
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / 'art/blender/orbita_pack'
SPECS = [
    ('karramarro_tug', 'Karramarro · remolcador orbital', 'ships', 'Nave industrial con horquillas de remolque y dos motores.', 'metres'),
    ('erlea_miner', 'Erlea · nave minera', 'ships', 'Nave minera de cuatro depósitos y cabezal de extracción ficticio.', 'metres'),
    ('pulse_turret', 'Begi · torreta de pulso', 'equipment', 'Equipo ficticio de doble emisor con pivote de orientación.', 'metres'),
    ('containment_projector', 'Lotura · proyector de contención', 'equipment', 'Equipo ficticio de campo, cámara central y tres antenas.', 'metres'),
    ('technician_robot', 'Torlo · técnico mecánico', 'avatars', 'Tripulante robótico con articulaciones rígidas y anclajes de equipo.', 'metres'),
    ('medic_robot', 'Osasun · asistente sanitario', 'avatars', 'Robot de tripulación compacto con pantalla y brazos articulados.', 'metres'),
    ('lapa_drone', 'Lapa · dron parásito', 'enemies', 'Dron de seis patas, caparazón y sensor orientable.', 'metres'),
    ('aingira_probe', 'Aingira · sonda hostil', 'enemies', 'Sonda segmentada con aletas y articulación de la cola.', 'metres'),
    ('harri_moon', 'Harri · luna de cráteres', 'worlds', 'Mundo estilizado con relieve de cráteres modelado y color en materiales.', 'display_units'),
    ('eraztun_giant', 'Eraztun · gigante anillado', 'worlds', 'Planeta bandeado con anillos de geometría de doble cara.', 'display_units'),
    ('docking_collar', 'Kaia · collar de atraque', 'infrastructure', 'Módulo abierto con anclajes frontal y posterior.', 'metres'),
    ('solar_array', 'Eguzki · módulo solar', 'infrastructure', 'Bus orbital de dos alas, paneles separados y antena.', 'metres'),
]
M: dict[str, bpy.types.Material] = {}


def point(v):
    x, y, z = v
    return Vector((x, -z, y))


def material(name, rgb, metal=0.0, rough=.42, glow=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*rgb, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    p.inputs['Emission Color'].default_value = (*rgb, 1)
    p.inputs['Emission Strength'].default_value = glow
    return mat


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.context.scene.render.fps = 24
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 97
    M.clear()
    for name, rgb, metal, rough, glow in [
        ('ceramic', (.72, .79, .77), .22, .38, 0),
        ('graphite', (.033, .055, .074), .6, .4, 0),
        ('alloy', (.24, .32, .34), .82, .31, 0),
        ('amber', (.92, .36, .055), .35, .38, 0),
        ('teal', (.035, .37, .36), .42, .36, 0),
        ('glass', (.017, .11, .15), .65, .19, 0),
        ('cyan', (.06, .8, .94), .12, .25, 2.2),
        ('red', (.9, .055, .10), .2, .34, 1.3),
        ('plum', (.24, .08, .17), .55, .39, 0),
        ('gold', (.55, .34, .09), .76, .38, 0),
        ('solar', (.03, .08, .25), .5, .27, 0),
    ]:
        M[name] = material('Orbita_' + name, rgb, metal, rough, glow)


def node(name, parent=None, at=(0, 0, 0)):
    ob = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    ob.location = point(at)
    ob.empty_display_size = .12
    return ob


def socket(parent, name, at):
    ob = node('socket_' + name, parent, at)
    ob['orbita_socket'] = name
    ob['forward'] = '-Z in Godot'
    return ob


def finish(ob, name, parent, at, mat):
    ob.name = name
    ob.parent = parent
    ob.location = point(at)
    ob.data.materials.append(M[mat] if isinstance(mat, str) else mat)
    return ob


def box(parent, name, at, size, mat='ceramic', bevel=.035):
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob = bpy.context.object
    ob.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = ob.modifiers.new('Machined_edges', 'BEVEL')
        mod.width = min(bevel, min(size) * .22)
        mod.segments = 2
    return finish(ob, name, parent, at, mat)


def sphere(parent, name, at, size, mat='ceramic', detail=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=detail, radius=1)
    ob = bpy.context.object
    ob.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(ob, name, parent, at, mat)


def rod(parent, name, a, b, radius, mat='alloy', top=None, vertices=16):
    delta = point(b) - point(a)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
        radius2=radius if top is None else top, depth=delta.length)
    ob = bpy.context.object
    ob.rotation_mode = 'QUATERNION'
    ob.rotation_quaternion = delta.to_track_quat('Z', 'Y')
    return finish(ob, name, parent, tuple((x+y)/2 for x, y in zip(a, b)), mat)


def ring(parent, name, at, radius, tube, mat='alloy', face='front'):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=tube,
        major_segments=48, minor_segments=8)
    ob = bpy.context.object
    if face == 'front':
        ob.rotation_euler.x = math.pi / 2
    return finish(ob, name, parent, at, mat)


def cycle(ob, axis='Y', angle=.2, phase=0.0):
    # Mechanical object animation, not a deforming humanoid skeleton.
    index = {'X': 0, 'Y': 2, 'Z': 1}[axis]
    sign = -1 if axis == 'Z' else 1
    ob.rotation_mode = 'XYZ'
    original = ob.rotation_euler.copy()
    for frame, value in [(1, 0), (25, 1), (49, 0), (73, -1), (97, 0)]:
        ob.rotation_euler = original
        ob.rotation_euler[index] += sign * (angle * value + phase)
        ob.keyframe_insert(data_path='rotation_euler', frame=frame)
    ob.rotation_euler = original
    ob['motion'] = 'mechanical_cycle'


def thruster(root, x, y, z, radius=.5):
    rod(root, 'Engine_shroud', (x,y,z-.7), (x,y,z+.6), radius, 'graphite', radius*.8)
    ring(root, 'Engine_lip', (x,y,z+.65), radius*.8, radius*.1, 'alloy')
    rod(root, 'Engine_emitter', (x,y,z+.60), (x,y,z+.64), radius*.59, 'cyan')
    for a in range(0, 360, 90):
        t=math.radians(a)
        box(root,'Engine_fin',(x+math.cos(t)*radius,y+math.sin(t)*radius,z),(.12,.12,1.1),'alloy')
    socket(root, 'exhaust_' + str(x).replace('-', 'm').replace('.', '_'), (x,y,z+.8))


def karramarro(root):
    box(root,'Keel',(0,0,.8),(2.8,1.1,7.2),'graphite',.18)
    box(root,'Upper_hull',(0,.64,1.4),(3.4,.55,4.9),'ceramic',.22)
    box(root,'Cabin',(0,1.12,.2),(2.4,1.05,2.65),'amber',.22)
    box(root,'Forward_glass',(0,1.2,-1.17),(1.86,.53,.07),'glass')
    for s in (-1,1):
        box(root,'Cabin_side_glass',(s*1.205,1.2,.12),(.07,.5,1.45),'glass')
        box(root,'Fork',(s*2.0,-.12,-1.9),(.8,.85,6.6),'ceramic',.16)
        box(root,'Fork_insert',(s*2.0,.34,-2.15),(.57,.1,4.7),'amber')
        box(root,'Tow_tip',(s*2,-.12,-5.3),(.95,1.05,.65),'graphite',.12)
        for i in range(7):
            box(root,'Hazard_dash',(s*2,.41,-3.9+i*.54),(.61,.065,.17),'graphite',.012)
        for i in range(3):
            box(root,'Service_vent',(s*1.08,.97,2.1+i*.48),(.43,.13,.24),'graphite')
        thruster(root,s*2.18,.05,2.9,.72)
        rod(root,'Tow_brace',(s*1.1,-.1,1),(s*2,-.1,-1),.16,'alloy')
        socket(root,'tow_left' if s < 0 else 'tow_right',(s*2,-.12,-5.7))
    box(root,'Hatch',(0,.95,2.2),(1.0,.2,1.3),'teal')
    rod(root,'Antenna',(0,1.7,.6),(0,2.5,.6),.035,'alloy')
    sphere(root,'Signal',(0,2.53,.6),(.12,.12,.12),'cyan')
    socket(root,'cockpit',(0,1.2,-.4)); socket(root,'cargo',(0,-.5,-2.5))


def erlea(root):
    sphere(root,'Faceted_core',(0,0,0),(1.8,1.05,3.1),'amber',2)
    box(root,'Spine',(0,.8,.4),(1.25,.75,3.6),'graphite',.2)
    sphere(root,'Canopy',(0,1.05,-1.4),(.83,.58,1.1),'glass',2)
    for s in (-1,1):
        for z in (-.4,1.65):
            x=s*2.15
            rod(root,'Cargo_tank',(x,-.25,z-.72),(x,-.25,z+.72),.74,'ceramic',vertices=12)
            ring(root,'Tank_band',(x,-.25,z-.5),.73,.08,'graphite')
            ring(root,'Tank_band',(x,-.25,z+.5),.73,.08,'graphite')
            box(root,'Tank_support',(s*1.35,-.25,z),(1.1,.22,.35),'alloy')
        rod(root,'Tool_boom',(s*1.45,-.4,-.8),(s*2.3,-.45,-3.3),.2,'alloy')
        sphere(root,'Boom_joint',(s*2.3,-.45,-3.3),(.32,.32,.32),'graphite')
        rod(root,'Tool_nozzle',(s*2.3,-.45,-3.3),(s*1.25,-.45,-4.4),.31,'amber',.2)
        socket(root,'mining_left' if s<0 else 'mining_right',(s*1.25,-.45,-4.4))
        thruster(root,s*.94,.1,2.95,.55)
        for i in range(5):
            box(root,'Radiator',(s*.7,1.42,.1+i*.39),(.47,.07,.2),'alloy')
    sensor=node('Sensor_gimbal',root,(0,1.65,.7))
    ring(sensor,'Sensor_frame',(0,0,0),.36,.06,'gold')
    sphere(sensor,'Sensor_lens',(0,0,-.04),(.22,.22,.1),'cyan')
    cycle(sensor,'Y',.4)
    socket(root,'cargo',(0,-1,1.2)); socket(root,'cockpit',(0,1,-1.5))


def turret(root):
    rod(root,'Base',(0,.08,0),(0,.3,0),.67,'graphite',vertices=24)
    ring(root,'Mount_rim',(0,.29,0),.59,.055,'amber','up')
    pivot=node('Yaw',root,(0,.46,0))
    box(pivot,'Cradle',(0,.1,0),(1.02,.43,.76),'ceramic',.12)
    for s in (-1,1):
        box(pivot,'Side_cheek',(s*.55,.18,-.14),(.2,.51,.8),'teal')
        rod(pivot,'Barrel',(s*.28,.22,-.1),(s*.28,.22,-1.24),.145,'graphite',.12)
        for z in (-.55,-.8,-1.05):
            ring(pivot,'Barrel_band',(s*.28,.22,z),.15,.025,'alloy')
        ring(pivot,'Emitter_guard',(s*.28,.22,-1.26),.16,.035,'ceramic')
        rod(pivot,'Emitter',(s*.28,.22,-1.26),(s*.28,.22,-1.29),.085,'cyan')
        socket(pivot,'muzzle_left' if s<0 else 'muzzle_right',(s*.28,.22,-1.34))
    box(pivot,'Target_window',(0,.42,-.4),(.24,.13,.06),'cyan')
    cycle(pivot,'Y',.24); socket(root,'mount',(0,0,0))


def projector(root):
    box(root,'Base',(0,.11,0),(.85,.22,.9),'graphite',.1)
    box(root,'Power_pack',(0,.38,.05),(.63,.42,.58),'ceramic',.1)
    rod(root,'Spindle',(0,.45,0),(0,.93,0),.18,'alloy')
    head=node('Field_gimbal',root,(0,1.13,0))
    sphere(head,'Chamber',(0,0,0),(.25,.25,.25),'cyan',3)
    ring(head,'Equator',(0,0,0),.35,.045,'gold','up')
    for i in range(3):
        a=i*math.tau/3
        x,z=math.cos(a),math.sin(a)
        rod(head,'Prong',(x*.28,-.3,z*.28),(x*.48,.29,z*.48),.075,'graphite')
        sphere(head,'Electrode',(x*.48,.29,z*.48),(.1,.1,.1),'teal')
        rod(root,'Conduit',(x*.22,.45,z*.22),(x*.26,.84,z*.26),.045,'amber')
    cycle(head,'Y',.55); socket(head,'field_origin',(0,0,0)); socket(root,'mount',(0,0,0))


def robot(root, medic=False):
    color='teal' if medic else 'amber'
    for s in (-1,1):
        box(root,'Foot',(s*.21,.10,-.10),(.31,.2,.5),'graphite',.08)
        rod(root,'Shin',(s*.21,.24,0),(s*.21,.61,0),.105,'alloy')
        box(root,'Shin_cover',(s*.21,.43,-.075),(.22,.31,.16),'ceramic')
        sphere(root,'Knee',(s*.21,.66,0),(.135,.135,.135),'graphite')
        rod(root,'Thigh',(s*.21,.69,0),(s*.18,.99,0),.135,color)
    box(root,'Pelvis',(0,1,0),(.53,.24,.32),'graphite',.08)
    if medic:
        sphere(root,'Torso',(0,1.29,0),(.40,.35,.26),'ceramic',3)
    else:
        box(root,'Torso',(0,1.29,0),(.75,.56,.45),color,.1)
    box(root,'Breast_panel',(0,1.34,-.245),(.45,.31,.07),'graphite')
    box(root,'Status_bar',(0,1.4,-.29),(.3,.05,.025),'cyan')
    for i in range(3):
        box(root,'Status_key',(-.1+i*.1,1.29,-.29),(.05,.05,.025),'teal' if medic else 'amber')
    head=node('Head_yaw',root,(0,1.76,0))
    sphere(head,'Head_shell',(0,0,0),(.28,.25,.24),'ceramic' if medic else color,3)
    box(head,'Visor',(0,.015,-.205),(.4,.14,.09),'graphite',.03)
    for s in (-1,1):
        sphere(head,'Optic',(s*.105,.02,-.259),(.053,.045,.022),'cyan')
        arm=node('Arm_left' if s<0 else 'Arm_right',root,(s*.48,1.43,0))
        sphere(arm,'Shoulder',(0,0,0),(.14,.14,.14),'alloy')
        rod(arm,'Upper_arm',(0,-.08,0),(s*.02,-.31,0),.09,'ceramic')
        sphere(arm,'Elbow',(s*.02,-.36,0),(.105,.105,.105),'graphite')
        box(arm,'Forearm',(s*.02,-.53,-.03),(.18,.28,.2),color)
        box(arm,'Palm',(s*.02,-.72,-.03),(.16,.12,.12),'graphite')
        for f in (-1,1):
            rod(arm,'Gripper',(s*.02+f*.065,-.75,-.03),(s*.02+f*.065,-.86,-.10),.025,'alloy',vertices=8)
        socket(arm,'hand_left' if s<0 else 'hand_right',(s*.02,-.84,-.08))
        cycle(arm,'X',s*.12)
    box(root,'Backpack',(0,1.29,.30),(.43,.40,.25),'ceramic')
    rod(root,'Back_spool',(-.27,1.27,.33),(.27,1.27,.33),.09,'teal')
    socket(root,'back',(0,1.30,.46)); socket(head,'view',(0,.04,-.31))
    cycle(head,'Y',.25)


def lapa(root):
    sphere(root,'Body',(0,.49,0),(.59,.27,.72),'graphite',2)
    sphere(root,'Carapace',(0,.66,.08),(.57,.25,.59),'plum',2)
    for s in (-1,1):
        for i in range(3):
            z=-.48+i*.47
            a=(s*.44,.5,z); b=(s*.93,.31,z-.10); c=(s*1.06,.045,z-.35)
            sphere(root,'Hip',a,(.12,.12,.12),'alloy')
            rod(root,'Leg_upper',a,b,.09,'plum',.065)
            sphere(root,'Leg_knee',b,(.085,.085,.085),'graphite')
            rod(root,'Leg_lower',b,c,.06,'alloy',.015)
            box(root,'Claw',(c[0],.04,c[2]-.05),(.12,.07,.21),'graphite')
        box(root,'Threat_strip',(s*.23,.76,-.11),(.13,.045,.54),'red')
    eye=node('Sensor_yaw',root,(0,.53,-.64))
    ring(eye,'Eye_frame',(0,0,0),.19,.045,'alloy')
    sphere(eye,'Eye',(0,0,-.04),(.135,.135,.075),'red',2)
    cycle(eye,'Y',.42); socket(eye,'sensor',(0,0,-.15)); socket(root,'attach',(0,.29,0))


def aingira(root):
    sphere(root,'Head',(0,0,-.65),(.42,.31,.58),'plum',2)
    box(root,'Face',(0,.04,-1.14),(.39,.11,.08),'red')
    for s in (-1,1):
        rod(root,'Mandible',(s*.26,-.08,-.85),(s*.37,-.12,-1.35),.07,'alloy',.018)
        fin=box(root,'Head_fin',(s*.49,0,-.52),(.43,.055,.57),'graphite')
        fin.rotation_euler.y=s*.28
    parent=root
    for i in range(5):
        seg=node('Tail_%02d'%i,parent,(0,0,.32 if i==0 else .41))
        r=.29-i*.039
        sphere(seg,'Vertebra',(0,0,0),(r,r*.8,.29),'graphite' if i%2 else 'plum',2)
        ring(seg,'Conductive_band',(0,0,.08),r*.86,.024,'gold')
        sphere(seg,'Spine_light',(0,r*.82,0),(.04,.028,.12),'red',1)
        cycle(seg,'Y',.14 if i else .07)
        parent=seg
    for s in (-1,1):
        rod(parent,'Tail_fin',(0,0,.11),(s*.4,0,.61),.09,'plum',.008)
    socket(root,'sensor',(0,.04,-1.24)); socket(parent,'tail',(0,0,.25))


def moon(root):
    rng=random.Random(5209)
    craters=[]
    for _ in range(20):
        v=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-1,1))).normalized()
        craters.append((v,rng.uniform(.10,.29)))
    palette=[material('Harri_rock_%d'%i,(.20+i*.043,.235+i*.043,.25+i*.046),0,.94) for i in range(6)]
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=5,radius=1)
    ob=bpy.context.object; ob.name='Crater_surface'; ob.parent=root
    heights=[]
    for v in ob.data.vertices:
        d=v.co.normalized()
        h=.018*math.sin(d.x*19)*math.sin(d.y*23)*math.sin(d.z*17)
        for centre,r in craters:
            distance=math.acos(max(-1.0,min(1.0,d.dot(centre))))/r
            if distance<1.4:
                h+=r*(-.26*math.exp(-distance**4*3)+.075*math.exp(-((distance-1.03)/.17)**2))
        v.co=d*(1+h); heights.append(h)
    for m in palette: ob.data.materials.append(m)
    for p in ob.data.polygons:
        h=sum(heights[i] for i in p.vertices)/len(p.vertices)
        p.material_index=max(0,min(5,int((h+.07)*53)))
        p.use_smooth=True
    socket(root,'centre',(0,0,0))


def annulus(parent, name, inner, outer, y, mat):
    verts=[]; faces=[]; steps=160
    for height in (y-.003,y+.003):
        for r in (inner,outer):
            for i in range(steps):
                a=i*math.tau/steps
                verts.append(tuple(point((r*math.cos(a),height,r*math.sin(a)))))
    for i in range(steps):
        j=(i+1)%steps
        faces.extend([(i,j,steps+j,steps+i),(2*steps+i,3*steps+i,3*steps+j,2*steps+j),
                      (i,2*steps+i,2*steps+j,j),(steps+i,steps+j,3*steps+j,3*steps+i)])
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    ob=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(ob)
    ob.parent=parent; ob.data.materials.append(mat)


def giant(root):
    palette=[material('Eraztun_band_%d'%i,c,0,.86) for i,c in enumerate([
        (.30,.15,.10),(.57,.29,.15),(.76,.49,.27),(.88,.66,.43),(.54,.37,.26),(.85,.74,.57)])]
    bpy.ops.mesh.primitive_uv_sphere_add(segments=96,ring_count=48,radius=1)
    ob=bpy.context.object; ob.name='Banded_cloud_deck'; ob.parent=root
    for m in palette: ob.data.materials.append(m)
    for p in ob.data.polygons:
        c=p.center if p.center.length else sum((ob.data.vertices[i].co for i in p.vertices),Vector())/len(p.vertices)
        lat=c.z+.025*math.sin(math.atan2(c.y,c.x)*7+c.z*16)
        p.material_index=int((lat+1)*22)%6; p.use_smooth=True
    rings=node('Ring_plane',root); rings.rotation_euler.x=math.radians(24)
    for i,(a,b) in enumerate([(1.35,1.49),(1.51,1.65),(1.68,1.85),(1.92,2.0),(2.03,2.20),(2.22,2.27)]):
        annulus(rings,'Ring_%02d'%i,a,b,0,palette[(i+2)%6])
    socket(root,'centre',(0,0,0))


def collar(root):
    for z in (-.45,.45):
        ring(root,'Docking_rim',(0,1.55,z),1.25,.16,'ceramic')
        ring(root,'Gasket',(0,1.55,z*1.15),1.10,.06,'graphite')
    for i in range(8):
        a=i*math.tau/8
        x,y=math.cos(a)*1.24,1.55+math.sin(a)*1.24
        rod(root,'Longitudinal_strut',(x,y,-.45),(x,y,.45),.10,'alloy')
        sphere(root,'Dock_indicator',(x,y,-.64),(.085,.085,.045),'cyan')
    for s in (-1,1):
        box(root,'Base_foot',(s*.91,.12,0),(.63,.24,1.2),'graphite')
        box(root,'Clamp_housing',(s*1.37,1.55,0),(.33,.5,.72),'amber')
    socket(root,'port_front',(0,1.55,-.65)); socket(root,'port_back',(0,1.55,.65))
    socket(root,'mount',(0,0,0))


def solar(root):
    box(root,'Bus',(0,0,0),(.83,.85,1.6),'gold',.1)
    box(root,'Bus_face',(0,0,-.85),(.68,.69,.10),'ceramic')
    for s in (-1,1):
        rod(root,'Wing_support',(s*.4,0,0),(s*.95,0,0),.09,'alloy')
        wing=node('Wing_left' if s<0 else 'Wing_right',root,(s*.95,0,0))
        box(wing,'Frame',(s*1.25,0,0),(2.63,.10,2.48),'graphite')
        for x in range(4):
            for z in range(4):
                at=(s*(.29+x*.62),.069,-.9+z*.6)
                box(wing,'Solar_cell',at,(.56,.032,.53),'solar',.008)
                box(wing,'Cell_busbar',(at[0],.088,at[2]),(.015,.006,.51),'alloy',.001)
        cycle(wing,'X',.09)
        socket(wing,'tip',(s*2.58,0,0))
    rod(root,'Aerial_mast',(0,.42,.3),(0,1.08,.3),.04,'alloy')
    ring(root,'Antenna',(0,1.13,.3),.28,.035,'ceramic')
    rod(root,'Antenna_feed',(0,1.13,.3),(0,1.13,-.1),.025,'gold',.01)
    socket(root,'mount',(0,-.45,0)); socket(root,'bus',(0,0,.87))

BUILDERS={
 'karramarro_tug':karramarro,'erlea_miner':erlea,'pulse_turret':turret,
 'containment_projector':projector,'technician_robot':lambda r:robot(r,False),
 'medic_robot':lambda r:robot(r,True),'lapa_drone':lapa,'aingira_probe':aingira,
 'harri_moon':moon,'eraztun_giant':giant,'docking_collar':collar,'solar_array':solar,
}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--force',action='store_true',help='Explicitly replace the procedural sources, losing manual edits.')
    parser.add_argument('--missing-only',action='store_true',help='Only create missing sources; preserve all existing sources.')
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    args=parser.parse_args(argv)
    HERE.mkdir(parents=True,exist_ok=True)
    paths=[HERE/(spec[0]+'.blend') for spec in SPECS]
    if any(p.exists() for p in paths) and not (args.force or args.missing_only):
        raise SystemExit('Existing sources protected. Use export.py for edits; --force is destructive.')
    count=0
    for ident,title,category,description,units in SPECS:
        path=HERE/(ident+'.blend')
        if path.exists() and args.missing_only: continue
        reset(); root=node(ident)
        root['asset_id']='orbita/'+ident; root['asset_version']=1
        root['license']='MIT'; root['provenance']='Original geometry authored for Espaciokoop Lagunak; no imported art.'
        root['units']=units; root['front']='Godot -Z'; root['description']=description
        BUILDERS[ident](root)
        bpy.context.scene.frame_set(1)
        bpy.context.view_layer.update()
        bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
        count+=1
    print('ORBITA_SOURCES_PASS created=%d preserved=%d'%(count,len(SPECS)-count),flush=True)

if __name__=='__main__': main()
