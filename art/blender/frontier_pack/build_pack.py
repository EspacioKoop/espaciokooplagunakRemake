"""Original Frontier asset library for Espaciokoop Lagunak. MIT.

Run with Blender 4.5.3: blender -b --python build_pack.py -- --render
Or with the official bpy==4.5.3 module and Python 3.11.
Sources are never silently overwritten: --rebuild is required on subsequent builds.
Authoring coordinates: metres, Z up, +Y forward; GLB: metres, Y up, -Z forward.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import random
import struct
import sys
import uuid
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector
from mathutils import noise

ROOT = Path(__file__).resolve().parents[3]
SOURCES = ROOT / 'art/blender/frontier_pack/sources'
MODELS = ROOT / 'game/assets/models/frontier_pack'
IMAGES = ROOT / 'docs/images/frontier_pack'
TAU = math.tau
PALETTE = {}
OBJECTS = []
ROOT_OBJECT = None

SPECS = [
    ('haizea_scout', 'Haizea / exploradora', 'ships', 'Reconocimiento, doble motor y sensores de proa.'),
    ('basajaun_hauler', 'Basajaun / carguera', 'ships', 'Transporte industrial con seis contenedores externos.'),
    ('izar_science', 'Izar / científica', 'ships', 'Laboratorio de largo alcance con anillos instrumentales.'),
    ('ekaitz_interceptor', 'Ekaitz / interceptora', 'ships', 'Silueta hostil con alas barridas y emisores gemelos.'),
    ('argi_sidearm', 'Argi / pistola de pulso', 'weapons', 'Equipo ficticio compacto con celda extraíble y emisor.'),
    ('tximista_carbine', 'Tximista / carabina', 'weapons', 'Arma ficticia de inducción con culata, visor y bobinas.'),
    ('sugar_lance', 'Sugar / lanza de plasma', 'weapons', 'Equipo ficticio pesado de doble horquilla energética.'),
    ('orbain_turret', 'Orbain / torreta', 'weapons', 'Montaje externo con pivote de giro y dos bocas.'),
    ('crew_navigator', 'Navegante', 'avatars', 'Traje naval ligero, casco y arnés de navegación.'),
    ('crew_engineer', 'Ingeniera de cubierta', 'avatars', 'Traje de mantenimiento, hombreras y mochila técnica.'),
    ('crew_synthetic', 'Tripulante sintético', 'avatars', 'Androide segmentado, ópticas y núcleo torácico.'),
    ('enemy_watcher', 'Vigía / dron', 'enemies', 'Explorador flotante con óptica central y estabilizadores.'),
    ('enemy_crawler', 'Armiarma / caminante', 'enemies', 'Autómata cuadrúpedo con patas articuladas y núcleo.'),
    ('enemy_warden', 'Harri / centinela', 'enemies', 'Guardián bípedo de placas minerales y cristales.'),
    ('world_ocean', 'Urdin / oceánico', 'worlds', 'Globo de océanos, archipiélagos y nubes estilizadas.'),
    ('world_desert', 'Harea / desértico', 'worlds', 'Globo de estratos cálidos y mesetas erosionadas.'),
    ('world_ice', 'Izotz / helado', 'worlds', 'Globo de casquetes, hielo azul y fracturas.'),
    ('world_lava', 'Labe / volcánico', 'worlds', 'Globo de costra oscura y fisuras incandescentes.'),
    ('world_gas', 'Ortzadar / gigante', 'worlds', 'Globo bandeado con sistema de anillos independiente.'),
    ('cargo_crate', 'Caja modular', 'props', 'Contenedor con tapa articulada, cierres y cantoneras.'),
    ('medical_capsule', 'Cápsula de auxilio', 'props', 'Suministro reconocible por paneles blancos y cruz turquesa.'),
    ('navigation_beacon', 'Baliza de navegación', 'props', 'Nodo orbital con paneles y anillo emisor.'),
    ('mineral_cluster', 'Veta de cristales', 'props', 'Recurso mineral con cinco cristales y base rocosa.'),
    ('field_scanner', 'Escáner de campo', 'props', 'Herramienta de exploración con pantalla y sonda.'),
]


def material(name, color, metal=0.0, rough=0.5, emission=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = (*color, 1)
    m.use_backface_culling = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    return m


def reset(asset_id):
    global PALETTE, OBJECTS, ROOT_OBJECT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    OBJECTS = []
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1
    scene.render.fps = 24
    scene.frame_start, scene.frame_end = 1, 49
    PALETTE = {
        'hull': material('Hull_Slate', (0.065, 0.12, 0.17), .55, .32),
        'ivory': material('Ceramic_Ivory', (.67, .74, .72), .2, .4),
        'dark': material('Carbon', (.012, .025, .036), .3, .6),
        'teal': material('Crew_Teal', (.025, .42, .38), .35, .35),
        'orange': material('Utility_Amber', (.95, .29, .055), .25, .4),
        'steel': material('Brushed_Titanium', (.30, .40, .47), .8, .29),
        'gold': material('Hardware_Brass', (.63, .36, .10), .75, .32),
        'red': material('Hostile_Oxide', (.36, .035, .07), .55, .4),
        'violet': material('Mineral_Violet', (.22, .08, .38), .5, .35),
        'glass': material('Opaque_Visor', (.018, .13, .19), .72, .16),
        'glow': material('Emitter_Cyan', (.025, .8, .72), .2, .3, 2.8),
        'hot': material('Emitter_Amber', (1, .16, .025), .2, .35, 2.5),
    }
    ROOT_OBJECT = empty(asset_id, (0, 0, 0), root=False)
    ROOT_OBJECT['asset_id'] = asset_id
    ROOT_OBJECT['license'] = 'MIT'
    ROOT_OBJECT['forward_axis'] = '+Y in Blender / -Z in glTF'
    ROOT_OBJECT['units'] = 'metres; worlds have a normalized 1m radius'


def parent_keep(obj, parent):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world


def register(obj, name, mat=None, bone=None, parent=None, smooth=False):
    obj.name = name
    if mat is not None:
        obj.data.materials.append(PALETTE[mat] if isinstance(mat, str) else mat)
    if obj.type == 'MESH':
        for p in obj.data.polygons:
            p.use_smooth = smooth
    if bone:
        obj['deform_bone'] = bone
    if ROOT_OBJECT is not None and obj != ROOT_OBJECT:
        parent_keep(obj, parent or ROOT_OBJECT)
    OBJECTS.append(obj)
    return obj


def empty(name, loc, root=True, parent=None):
    o = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.empty_display_size = .1
    if root and ROOT_OBJECT:
        parent_keep(o, parent or ROOT_OBJECT)
    OBJECTS.append(o)
    return o


def socket(name, loc, parent=None):
    o = empty(name, loc, parent=parent)
    o['socket'] = True
    o['forward'] = '+Y'
    return o


def bevel(obj, amount, segments=2):
    if not amount:
        return
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new('Machined_edges', 'BEVEL')
    mod.width = amount
    mod.segments = segments
    mod.affect = 'EDGES'
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # Keep large planar faces flat; bevel strips alone supply the highlights.


def box(name, loc, size, mat, bevel_width=.025, rot=None, bone=None, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.scale = size
    if rot:
        o.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bevel(o, min(bevel_width, min(size) * .22))
    return register(o, name, mat, bone, parent)


def sphere(name, loc, size, mat, bone=None, parent=None, segments=24, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=loc)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return register(o, name, mat, bone, parent, smooth=True)


def rod(name, a, b, radius, mat, radius2=None, vertices=12, bone=None, parent=None):
    a, b = Vector(a), Vector(b)
    direction = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
        radius2=radius if radius2 is None else radius2, depth=direction.length,
        location=(a + b) / 2)
    o = bpy.context.object
    o.rotation_euler = direction.to_track_quat('Z', 'Y').to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return register(o, name, mat, bone, parent)


def ring(name, loc, radius, tube, mat, rot=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_torus_add(major_segments=40, minor_segments=8,
        major_radius=radius, minor_radius=tube, location=loc, rotation=rot)
    return register(bpy.context.object, name, mat, parent=parent, smooth=True)


def mesh(name, verts, faces, mat, bone=None, parent=None, edge=.0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    o = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    bevel(o, edge)
    return register(o, name, mat, bone, parent)


def hull(name, sections, mat, edge=.05):
    verts = []
    for y, w, low, high in sections:
        mid, height = (high + low) / 2, high - low
        for x, z in [(-.65*w, high), (.65*w, high), (w, mid+.25*height),
                     (w, mid-.25*height), (.65*w, low), (-.65*w, low),
                     (-w, mid-.25*height), (-w, mid+.25*height)]:
            verts.append((x, y, z))
    faces = [tuple(reversed(range(8)))]
    for s in range(len(sections)-1):
        for j in range(8):
            faces.append((s*8+j, s*8+(j+1)%8, (s+1)*8+(j+1)%8, (s+1)*8+j))
    faces.append(tuple(range((len(sections)-1)*8, len(sections)*8)))
    return mesh(name, verts, faces, mat, edge=edge)


def wing(name, polygon, z, thick, mat):
    n = len(polygon)
    verts = [(x, y, z + dz) for dz in [-thick/2, thick/2] for x, y in polygon]
    faces = [tuple(reversed(range(n))), tuple(range(n, n*2))]
    faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
    return mesh(name, verts, faces, mat, edge=min(.04, thick*.15))


def engine(x, y, z, radius=.6, length=2, hot=False):
    rod('Engine_housing', (x,y,z), (x,y-length,z), radius, 'steel', radius*.78, 20)
    ring('Nozzle_rim', (x,y-length,z), radius*.76, radius*.13, 'dark', (math.pi/2,0,0))
    rod('Thruster_emitter', (x,y-length-.025,z), (x,y-length-.06,z), radius*.59,
        'hot' if hot else 'glow', vertices=20)
    socket('Engine', (x,y-length-.10,z))


def ship(kind):
    if kind == 0:
        hull('Pressure_hull', [(-7,1.35,-.5,.6),(-3,2,-.7,1.1),(3,1.7,-.5,.9),(8,.2,-.1,.3)], 'hull')
        hull('Canopy', [(1.2,.85,.8,1.15),(3.2,.8,.7,1.55),(5.8,.22,.35,.5)], 'glass', .025)
        for s in [-1,1]:
            wing('Swept_sponson', [(s*1.2,1),(s*4.5,-1),(s*4,-5.8),(s*1.3,-4)], .0,.48,'ivory')
            box('Engine_pylon', (s*3.6,-3.8,.05), (.85,4,.75), 'hull', .12)
            engine(s*3.6,-5.0,.05,.59,1.5)
            box('Livery', (s*3.6,-2.9,.46), (.4,2.5,.025), 'teal', .005)
            rod('Sensor_boom',(s*.95,4,.3),(s*.95,6.5,.3),.06,'steel')
            sphere('Navigation_light',(s*4,-1,.35),(.1,.18,.09),'glow')
        box('Dorsal_spine',(0,-2,1.0),(.38,6,.32),'ivory',.07)
        for y in [-5,-4.4,-3.8]:
            box('Heat_vent',(0,y,1.0),(1.1,.22,.08),'dark',.02)
        socket('Cockpit',(0,3,1.3))
        socket('Dock',(0,-.5,-.75))
    elif kind == 1:
        hull('Cargo_keel',[(-11,1.5,-1,1),(5,1.7,-1,1),(10,1,-.6,1.3),(12,.7,-.4,.8)],'hull',.1)
        hull('Bridge',[(7.5,1.25,.85,1.5),(10.5,.9,.85,2),(11.5,.65,.8,1.2)],'ivory')
        box('Bridge_glass',(0,10.82,1.43),(1.28,.15,.45),'glass',.05)
        for s in [-1,1]:
            box('Structural_rail',(s*2.25,-1,0),(.35,17,.5),'steel',.04)
            for i,y in enumerate([-6.7,-1.6,3.5]):
                box('Cargo_module',(s*3,y,.0),(3.1,4.6,2.9),'orange' if i%2 else 'ivory',.16)
                for dy in [-1.8,1.8]:
                    box('Container_frame',(s*3,y+dy,0),(3.23,.24,3.04),'dark',.03)
                for yy in [-1,-.5,0,.5,1]:
                    box('Cargo_rib',(s*4.565,y+yy,0),(.04,.13,2.35),'steel',.005)
                box('Cargo_status',(s*3,y+2.315,.45),(1,.02,.12),'glow',.004)
                socket('Cargo_mount',(s*3,y,1.6))
            engine(s*2.4,-9.5,0,1.15,2.8)
        for y in [-8,-3,2]:
            box('Top_walkway',(0,y,1.2),(1.15,3.5,.16),'gold',.02)
        socket('Dock',(0,0,-1.15))
        socket('Cockpit',(0,10,1.65))
    elif kind == 2:
        hull('Laboratory_hull',[(-9,1.1,-.8,.7),(-5,1.9,-1,1),(4,1.6,-.6,.9),(9,.25,-.1,.4)],'ivory')
        hull('Observation_glazing',[(3,.8,.8,1.2),(5,.68,.6,1.25),(7,.3,.4,.7)],'glass')
        for y,r in [(-3.5,3.9),(-.5,3.0)]:
            ring('Instrument_ring',(0,y,0),r,.17,'steel',(math.pi/2,0,0))
            ring('Ring_trace',(0,y-.07,0),r-.23,.055,'glow',(math.pi/2,0,0))
            for a in range(4):
                angle=a*TAU/4
                x,z=math.cos(angle)*r,math.sin(angle)*r
                rod('Ring_stay',(0,y,0),(x,y,z),.11,'hull')
                box('Instrument_pod',(x,y,z),(.55,.9,.55),'teal',.09)
        for s in [-1,1]:
            box('Radiator_arm',(s*2.5,-6.5,0),(3,.28,.22),'steel')
            box('Radiator_panel',(s*3,-6.5,0),(2.2,3.2,.12),'hull')
            for t in [-.7,0,.7]:
                box('Panel_bus',(s*3+t,-6.5,.08),(.05,3,.035),'gold',.005)
            engine(s*1.0,-8.3,0,.6,1.5)
        socket('Science_array',(0,6,.6))
        socket('Dock',(0,2,-.8))
        socket('Cockpit',(0,5,1.1))
    else:
        hull('Razor_hull',[(-6,1.2,-.45,.5),(-1,1.6,-.7,.8),(5,.5,-.25,.5),(9,.045,0,.12)],'dark')
        hull('Armored_canopy',[(0,.65,.75,.95),(2.5,.5,.7,1.4),(4.5,.15,.45,.55)],'red')
        for s in [-1,1]:
            wing('Swept_blade',[(s*.8,3),(s*6.4,-6),(s*5.3,-7),(s*1.1,-3)],.05,.3,'red')
            wing('Blade_inlay',[(s*2,1),(s*5.7,-5.5),(s*5.15,-5.5),(s*1.6,-.2)],.225,.045,'steel')
            rod('Lance_rail',(s*1.45,-1,.15),(s*1.45,6,.15),.14,'steel')
            rod('Lance_tip',(s*1.45,5.8,.15),(s*1.45,6.25,.15),.11,'hot')
            engine(s*.8,-5.3,0,.65,1.7,True)
            socket('Weapon_mount',(s*1.45,6.3,.15))
        wing('Vertical_fin',[(-.13,-4),(.13,-4),(.13,-6),(-.13,-6)],1.35,2.1,'red')
        socket('Cockpit',(0,2,1.1))
        socket('Dock',(0,-1,-.8))
    socket('Forward',(0,1,0))


def object_clip(obj, name, poses):
    obj.animation_data_create()
    action = bpy.data.actions.new(name)
    obj.animation_data.action = action
    for frame, loc, rot in poses:
        if loc is not None:
            obj.location = loc
            obj.keyframe_insert(data_path='location', frame=frame)
        if rot is not None:
            obj.rotation_euler = rot
            obj.keyframe_insert(data_path='rotation_euler', frame=frame)
    track = obj.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, action)
    strip.name = name
    obj.animation_data.action = None
    return track


def weapon(kind):
    if kind == 3:
        rod('Mount_flange',(0,0,0),(0,0,.17),.62,'dark',vertices=24)
        rod('Bearing',(0,0,.17),(0,0,.43),.43,'steel',vertices=24)
        ring('Bearing_light',(0,0,.34),.44,.025,'glow')
        pivot=empty('Azimuth',(0,0,.43))
        box('Turret_housing',(0,0,.76),(1.05,.9,.63),'hull',.12,parent=pivot)
        for s in [-1,1]:
            rod('Barrel',(s*.3,.15,.82),(s*.3,1.1,.82),.13,'steel',parent=pivot)
            for y in [.3,.48,.66]:
                ring('Coil',(s*.3,y,.82),.15,.035,'gold',(math.pi/2,0,0),pivot)
            rod('Muzzle_core',(s*.3,1.08,.82),(s*.3,1.13,.82),.105,'glow',parent=pivot)
            socket('Muzzle'+('_L' if s<0 else '_R'),(s*.3,1.15,.82),pivot)
        box('Target_optic',(0,.465,.88),(.21,.04,.15),'glass',.02,parent=pivot)
        object_clip(pivot,'Scan',[(1,None,(0,0,-.65)),(25,None,(0,0,.65)),(49,None,(0,0,-.65))])
        socket('Mount',(0,0,0))
        return
    width=[.09,.11,.19][kind]
    length=[.34,.73,.72][kind]
    body_mat=['ivory','hull','orange'][kind]
    box('Receiver',(0,.14,.16),(width*2,length,.17),body_mat,.025)
    box('Lower_frame',(0,.08,.055),(width*1.7,length*.72,.085),'dark',.016)
    box('Grip',(0,-.06,-.065),(.13,.17,.26),'dark',.025,rot=(.2,0,0))
    for z in [-.13,-.08,-.03]:
        box('Grip_rib',(0,.028,z),(.13,.014,.017),'steel',.003)
    box('Trigger_guard',(0,.11,-.04),(.048,.14,.10),'steel',.009)
    box('Energy_cell',(width+.01,.09,.17),(.045,.17,.105),'teal',.012)
    for y in [.025,.075,.125]:
        box('Cell_indicator',(width+.036,y,.17),(.008,.025,.045),'glow',.002)
    muzzle_y = .14 + length/2 + (.11 if kind==0 else .32)
    if kind < 2:
        rod('Induction_barrel',(0,.14,.16),(0,muzzle_y,.16),width*.58,'steel',vertices=16)
        for y in ([.33] if kind==0 else [.5,.56,.62,.68]):
            ring('Induction_band',(0,y,.16),width*.72,.012,'gold',(math.pi/2,0,0))
        rod('Emitter',(0,muzzle_y,.16),(0,muzzle_y+.018,.16),width*.43,'glow',vertices=16)
        box('Sight',(0,.03,.283),(.038,.15,.06),'dark',.01)
        box('Sight_glass',(0,.108,.283),(.024,.008,.038),'glow',.002)
    else:
        for s in [-1,1]:
            box('Plasma_prong',(s*.145,.51,.16),(.07,.5,.11),'steel',.025)
            box('Prong_conductor',(s*.109,.53,.16),(.014,.34,.055),'hot',.002)
        sphere('Plasma_core',(0,.30,.16),(.075,.16,.075),'hot',segments=16,rings=8)
        muzzle_y=.79
    if kind > 0:
        box('Stock_bridge',(0,-.38,.14),(.1,.27,.08),'steel',.015)
        box('Stock',(0,-.55,.075),(.15,.12,.28),'dark',.025)
        box('Shoulder_pad',(0,-.62,.065),(.17,.035,.24),'teal',.008)
        socket('Offhand',(0,.35,.045))
    socket('Grip',(0,0,0))
    socket('Muzzle',(0,muzzle_y+.025,.16))
    socket('Sight_line',(0,.05,.32))


def humanoid_bones():
    bones=[('Root',(0,0,0),(0,0,.2),None),('Hips',(0,0,.87),(0,0,1.03),'Root'),
           ('Spine',(0,0,1.03),(0,0,1.28),'Hips'),('Chest',(0,0,1.28),(0,0,1.48),'Spine'),
           ('Neck',(0,0,1.48),(0,0,1.60),'Chest'),('Head',(0,0,1.60),(0,0,1.91),'Neck')]
    for s,tag in [(-1,'L'),(1,'R')]:
        bones.extend([
            ('UpperArm.'+tag,(s*.30,0,1.43),(s*.40,0,1.11),'Chest'),
            ('LowerArm.'+tag,(s*.40,0,1.11),(s*.43,.015,.87),'UpperArm.'+tag),
            ('Hand.'+tag,(s*.43,.015,.87),(s*.43,.035,.75),'LowerArm.'+tag),
            ('UpperLeg.'+tag,(s*.155,0,.89),(s*.17,0,.51),'Hips'),
            ('LowerLeg.'+tag,(s*.17,0,.51),(s*.17,0,.13),'UpperLeg.'+tag),
            ('Foot.'+tag,(s*.17,0,.13),(s*.17,.19,.06),'LowerLeg.'+tag)])
    return bones


def rig_mesh(bones, clips=True):
    arm_data=bpy.data.armatures.new('Frontier_Rig')
    arm=bpy.data.objects.new('Rig',arm_data)
    bpy.context.scene.collection.objects.link(arm)
    parent_keep(arm,ROOT_OBJECT)
    OBJECTS.append(arm)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    bpy.context.view_layer.objects.active=arm
    bpy.ops.object.mode_set(mode='EDIT')
    for name,head,tail,parent in bones:
        b=arm_data.edit_bones.new(name)
        b.head,b.tail=head,tail
        if parent:
            b.parent=arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.show_in_front=True
    for obj in list(OBJECTS):
        if obj.type=='MESH' and 'deform_bone' in obj:
            group=obj.vertex_groups.new(name=obj['deform_bone'])
            group.add(list(range(len(obj.data.vertices))),1.0,'REPLACE')
            modifier=obj.modifiers.new('Skin','ARMATURE')
            modifier.object=arm
            parent_keep(obj,arm)
    if clips:
        for clip,frames in [('Idle',49),('Walk',25),('Wave',49)]:
            arm.animation_data_create()
            action=bpy.data.actions.new(clip)
            arm.animation_data.action=action
            for frame in range(1,frames+1,3):
                phase=(frame-1)/(frames-1)*TAU
                for pb in arm.pose.bones:
                    pb.rotation_mode='XYZ'
                    pb.rotation_euler=(0,0,0)
                    pb.location=(0,0,0)
                if clip=='Idle':
                    arm.pose.bones['Chest'].rotation_euler.x=.025*math.sin(phase)
                    arm.pose.bones['Head'].rotation_euler.y=.025*math.sin(phase)
                elif clip=='Walk':
                    for tag,sign in [('L',1),('R',-1)]:
                        arm.pose.bones['UpperLeg.'+tag].rotation_euler.x=.44*math.sin(phase)*sign
                        arm.pose.bones['LowerLeg.'+tag].rotation_euler.x=-.52*max(0,math.sin(phase)*sign)
                        arm.pose.bones['UpperArm.'+tag].rotation_euler.x=-.34*math.sin(phase)*sign
                        arm.pose.bones['LowerArm.'+tag].rotation_euler.x=-.16
                else:
                    envelope=math.sin((frame-1)/(frames-1)*math.pi)
                    arm.pose.bones['UpperArm.R'].rotation_euler.z=-1.9*envelope
                    arm.pose.bones['LowerArm.R'].rotation_euler.x=(.65+.32*math.sin(phase*2))*envelope
                    arm.pose.bones['Hand.R'].rotation_euler.z=.3*math.sin(phase*2)*envelope
                for pb in arm.pose.bones:
                    pb.keyframe_insert(data_path='rotation_euler',frame=frame,group=pb.name)
                    pb.keyframe_insert(data_path='location',frame=frame,group=pb.name)
            track=arm.animation_data.nla_tracks.new()
            track.name=clip
            track.strips.new(clip,1,action)
            arm.animation_data.action=None
        for pb in arm.pose.bones:
            pb.rotation_euler=(0,0,0)
            pb.location=(0,0,0)
    return arm


def humanoid(kind):
    armor=['teal','orange','ivory','violet'][kind]
    box('Pelvis',(0,0,.96),(.43,.29,.21),'dark',.055,bone='Hips')
    sphere('Torso_underlay',(0,0,1.24),(.255,.165,.29),'dark',bone='Spine')
    box('Chest_armor',(0,.065,1.32),(.47,.24,.33),armor,.075,bone='Chest')
    box('Abdominal_plate',(0,.13,1.09),(.27,.095,.15),'steel',.035,bone='Spine')
    for x in [-.15,0,.15]:
        box('Belt_module',(x,.165,.96),(.10,.07,.11),'gold',.018,bone='Hips')
    rod('Neck_seal',(0,0,1.45),(0,0,1.60),.105,'dark',bone='Neck')
    if kind==2:
        box('Synthetic_head',(0,0,1.73),(.26,.24,.29),'steel',.065,bone='Head')
        box('Faceplate',(0,.13,1.75),(.21,.045,.16),'dark',.022,bone='Head')
        for x in [-.064,.064]:
            sphere('Optic',(x,.163,1.77),(.033,.02,.023),'glow',bone='Head',segments=16,rings=8)
        box('Jaw',(0,.085,1.615),(.16,.11,.055),'ivory',.018,bone='Head')
    elif kind==3:
        mesh('Mineral_helm',[(-.16,-.1,1.58),(.16,-.1,1.58),(.18,.12,1.73),(-.18,.12,1.73),
             (0,-.08,2.01),(0,.24,1.79)],[(0,1,2,3),(0,4,1),(1,4,2),(2,4,5),(3,5,4),(0,3,4),(2,5,3)],armor,bone='Head',edge=.012)
        box('Optic_slit',(0,.207,1.77),(.23,.03,.04),'hot',.008,bone='Head')
    else:
        sphere('Helmet_shell',(0,0,1.73),(.185,.17,.207),'ivory' if kind==0 else armor,bone='Head')
        sphere('Visor',(0,.121,1.756),(.157,.078,.126),'glass',bone='Head')
        box('Chin_seal',(0,.125,1.615),(.22,.13,.062),'dark',.022,bone='Head')
        for s in [-1,1]:
            sphere('Headset',(s*.173,0,1.736),(.045,.09,.09),'steel',bone='Head',segments=16,rings=8)
        box('Helmet_marker',(0,.023,1.927),(.038,.11,.018),'glow',.004,bone='Head')
    for s,tag in [(-1,'L'),(1,'R')]:
        up,low,hand='UpperArm.'+tag,'LowerArm.'+tag,'Hand.'+tag
        sphere('Shoulder_joint',(s*.285,0,1.43),(.112,.125,.12),'dark',bone=up)
        sphere('Shoulder_plate',(s*.32,0,1.46),(.14 if kind!=3 else .21,.15,.105),armor,bone=up)
        rod('Upper_arm',(s*.315,0,1.39),(s*.393,0,1.13),.081,'dark',.093,bone=up)
        box('Bicep_plate',(s*.36,.061,1.275),(.13,.11,.18),armor,.03,bone=up)
        sphere('Elbow',(s*.40,0,1.11),(.087,.087,.087),'steel',bone=low)
        rod('Forearm',(s*.403,0,1.09),(s*.43,.015,.88),.077,armor,.095,bone=low)
        box('Wrist_seal',(s*.431,.015,.872),(.145,.14,.057),'dark',.018,bone=hand)
        box('Glove',(s*.43,.035,.803),(.14,.17,.13),'dark' if kind<2 else 'steel',.035,bone=hand)
        box('Knuckle_plate',(s*.43,.123,.815),(.113,.025,.055),armor,.008,bone=hand)
        thigh,shin,foot='UpperLeg.'+tag,'LowerLeg.'+tag,'Foot.'+tag
        rod('Thigh',(s*.155,0,.89),(s*.17,0,.54),.115,'dark',.095,bone=thigh)
        box('Thigh_plate',(s*.17,.06,.716),(.18,.16,.24),armor,.04,bone=thigh)
        sphere('Knee',(s*.17,0,.51),(.105,.10,.095),'steel',bone=shin)
        box('Knee_cap',(s*.17,.09,.51),(.16,.095,.13),'ivory' if kind<3 else armor,.035,bone=shin)
        rod('Shin',(s*.17,0,.47),(s*.17,0,.15),.095,'dark',.105,bone=shin)
        box('Shin_plate',(s*.17,.074,.31),(.15,.11,.235),armor,.03,bone=shin)
        box('Boot',(s*.17,.068,.084),(.215,.34,.16),'dark',.045,bone=foot)
        box('Toe_plate',(s*.17,.187,.105),(.18,.10,.095),'steel',.025,bone=foot)
        box('Sole',(s*.17,.072,.022),(.22,.34,.043),'steel',.013,bone=foot)
    if kind==0:
        box('Navigation_patch',(-.11,.192,1.36),(.10,.022,.074),'gold',.008,bone='Chest')
        for z in [1.27,1.32,1.37]:
            box('Suit_status',(.13,.197,z),(.075,.015,.018),'glow',.003,bone='Chest')
        box('Life_support',(0,-.188,1.28),(.30,.16,.33),'hull',.045,bone='Chest')
    elif kind==1:
        box('Tool_pack',(0,-.23,1.26),(.41,.27,.44),'hull',.06,bone='Chest')
        for s in [-1,1]:
            rod('Support_tank',(s*.15,-.33,1.08),(s*.15,-.33,1.43),.078,'steel',bone='Chest')
            box('Utility_pouch',(s*.26,-.01,.96),(.14,.20,.16),'orange',.025,bone='Hips')
        box('Wrist_screen',(-.43,.09,1.025),(.12,.05,.11),'glow',.012,bone='LowerArm.L')
        box('Chest_harness',(0,.199,1.315),(.17,.045,.22),'dark',.022,bone='Chest')
    elif kind==2:
        sphere('Thoracic_core',(0,.205,1.32),(.068,.035,.068),'glow',bone='Chest')
        for z in [1.1,1.2,1.3,1.4]:
            box('Spinal_segment',(0,-.178,z),(.13,.065,.06),'steel',.016,bone='Spine' if z<1.28 else 'Chest')
    else:
        for s in [-1,1]:
            for z,y in [(1.43,-.16),(1.30,-.19),(1.16,-.19)]:
                rod('Crystal_spine',(s*.11,y,z),(s*.17,y-.22,z+.19),.10,'violet',0,6,bone='Chest')
        sphere('Furnace_core',(0,.205,1.32),(.075,.04,.075),'hot',bone='Chest')
    arm=rig_mesh(humanoid_bones())
    for name,pos,bone in [('Hand_L',(-.43,.035,.8),'Hand.L'),('Hand_R',(.43,.035,.8),'Hand.R'),
                           ('Back',(0,-.36,1.3),'Chest'),('Head_top',(0,0,1.98),'Head')]:
        o=socket(name,pos)
        world=o.matrix_world.copy()
        o.parent=arm
        o.parent_type='BONE'
        o.parent_bone=bone
        o.matrix_world=world
    socket('Feet',(0,0,0))


def enemy(kind):
    if kind==2:
        humanoid(3)
        return
    if kind==0:
        pivot=empty('Hover_body',(0,0,0))
        sphere('Armored_orb',(0,0,.85),(.43,.32,.35),'hull',parent=pivot)
        ring('Equatorial_guard',(0,0,.85),.45,.04,'steel',parent=pivot)
        sphere('Main_lens',(0,.30,.88),(.20,.07,.18),'dark',parent=pivot)
        sphere('Optic_core',(0,.355,.88),(.11,.035,.11),'hot',parent=pivot)
        for s in [-1,1]:
            rod('Stabilizer',(s*.30,0,.85),(s*.78,-.05,.78),.055,'steel',parent=pivot)
            box('Side_pod',(s*.70,-.03,.77),(.20,.4,.21),'red',.04,parent=pivot)
            rod('Lift_emitter',(s*.70,-.03,.67),(s*.70,-.03,.61),.075,'glow',parent=pivot)
        rod('Antenna',(0,-.12,1.12),(0,-.16,1.43),.018,'steel',parent=pivot)
        sphere('Antenna_tip',(0,-.16,1.43),(.045,.045,.045),'hot',parent=pivot,segments=12,rings=8)
        socket('Sensor',(0,.4,.88),pivot)
        object_clip(pivot,'Hover',[(1,(0,0,0),(0,0,-.12)),(25,(0,0,.08),(0,0,.12)),(49,(0,0,0),(0,0,-.12))])
        return
    sphere('Crawler_carapace',(0,0,.68),(.53,.65,.26),'red',bone='Body')
    box('Back_armor',(0,-.06,.90),(.57,.68,.14),'hull',.05,bone='Body')
    sphere('Forward_optic',(0,.62,.71),(.16,.045,.10),'hot',bone='Body')
    bones=[('Body',(0,0,.64),(0,0,.92),None)]
    for s in [-1,1]:
        for side_y in [-1,1]:
            tag=('L' if s<0 else 'R')+('F' if side_y>0 else 'B')
            hip=(s*.38,side_y*.34,.66)
            knee=(s*.89,side_y*.57,.53)
            toe=(s*1.05,side_y*.74,.055)
            up,low='Femur_'+tag,'Tibia_'+tag
            bones += [(up,hip,knee,'Body'),(low,knee,toe,up)]
            sphere('Hip_joint',hip,(.13,.13,.13),'steel',bone=up)
            rod('Femur',hip,knee,.105,'hull',.077,bone=up)
            sphere('Knee_joint',knee,(.105,.105,.105),'gold',bone=low)
            rod('Tibia',knee,toe,.085,'dark',.025,bone=low)
            sphere('Foot',toe,(.11,.15,.055),'steel',bone=low)
    arm=rig_mesh(bones,clips=False)
    arm.animation_data_create()
    action=bpy.data.actions.new('Scuttle')
    arm.animation_data.action=action
    for frame in range(1,26,3):
        phase=(frame-1)/24*TAU
        for i,pb in enumerate(arm.pose.bones):
            pb.rotation_mode='XYZ'
            pb.rotation_euler=(.13*math.sin(phase+i*math.pi/2) if pb.name!='Body' else 0,0,0)
            pb.keyframe_insert(data_path='rotation_euler',frame=frame,group=pb.name)
    track=arm.animation_data.nla_tracks.new()
    track.name='Scuttle'
    track.strips.new('Scuttle',1,action)
    arm.animation_data.action=None
    socket('Sensor',(0,.70,.72))


def fractal(v, seed=0):
    p=Vector(v)+Vector((seed*.131,seed*.317,seed*.197))
    return sum(noise.noise(p*(2**i))*2**(-i) for i in range(5))/1.9375


def world(kind):
    m=material('World_Vertex_PBR',(.8,.8,.8),.05,.68)
    nodes=m.node_tree.nodes
    color=nodes.new('ShaderNodeVertexColor')
    color.layer_name='SurfaceColor'
    m.node_tree.links.new(color.outputs['Color'],nodes.get('Principled BSDF').inputs['Base Color'])
    if kind==3:
        m.node_tree.links.new(color.outputs['Color'],nodes.get('Principled BSDF').inputs['Emission Color'])
        nodes.get('Principled BSDF').inputs['Emission Strength'].default_value=.17
    o=sphere('Planet_surface',(0,0,0),(1,1,1),m,segments=96,rings=48)
    attr=o.data.color_attributes.new(name='SurfaceColor',type='FLOAT_COLOR',domain='CORNER')
    for poly in o.data.polygons:
        for li in poly.loop_indices:
            p=o.data.vertices[o.data.loops[li].vertex_index].co.normalized()
            n=fractal(p*2.0,kind+11)
            detail=fractal(p*7.0,3)
            if kind==0:
                if n<-.06:
                    t=max(0,min(1,(n+.5)/.44))
                    c=(.012+.025*t,.06+.16*t,.16+.19*t)
                elif n<.015:
                    c=(.39,.54,.34)
                else:
                    c=(.06+n*.35,.22+n*.42,.115+n*.25)
                if abs(p.z)>.88+detail*.07:
                    c=(.75,.86,.84)
            elif kind==1:
                band=.5+.5*math.sin(p.z*39+n*8)
                c=(.43+.30*band,.19+.18*band,.065+.12*band)
            elif kind==2:
                crack=abs(fractal(p*4,31))
                c=(.055,.25,.38) if crack<.028 else (.45+n*.28,.69+n*.18,.80+n*.12)
            elif kind==3:
                crack=abs(fractal(p*3,17))
                c=(1,.17+.3*detail,.012) if crack<.04 else (.043+n*.026,.048+n*.02,.062+n*.025)
            else:
                band=.5+.5*math.sin(p.z*30+detail*3)
                storm=math.exp(-((p.x-.6)**2+(p.y-.55)**2+(p.z+.2)**2)*42)
                c=(.48+.32*band,.24+.31*band-storm*.12,.13+.29*band)
            attr.data[li].color=(*[max(.0,min(1,x)) for x in c],1)
    if kind==0:
        cloud_verts=[]
        cloud_faces=[]
        for p in o.data.polygons:
            center=p.center.normalized()
            if fractal(center*4,52)>.20 and abs(center.z)<.88:
                indices=[]
                for vi in p.vertices:
                    indices.append(len(cloud_verts))
                    cloud_verts.append(tuple(o.data.vertices[vi].co*1.013))
                cloud_faces.append(tuple(indices))
        if cloud_faces:
            clouds=mesh('Cloud_patches',cloud_verts,cloud_faces,'ivory')
            for p in clouds.data.polygons:
                p.use_smooth=True
    if kind==4:
        bands=[(1.26,1.34,'dark'),(1.37,1.49,'gold'),(1.51,1.66,'ivory'),(1.71,1.82,'steel'),(1.85,1.9,'gold')]
        for inner,outer,mat in bands:
            verts=[]
            for radius in [inner,outer]:
                verts += [(radius*math.cos(i*TAU/128),radius*math.sin(i*TAU/128),0) for i in range(128)]
            faces=[(i,(i+1)%128,(i+1)%128+128,i+128) for i in range(128)]
            ring_mat=PALETTE[mat].copy()
            ring_mat.name='Ring_'+mat
            ring_mat.use_backface_culling=False
            obj=mesh('Orbital_ring',verts,faces,ring_mat)
            obj.rotation_euler=(.22,.12,0)
    socket('Center',(0,0,0))
    socket('North_pole',(0,0,1.03))
    ROOT_OBJECT['normalized_radius_m']=1.0
    ROOT_OBJECT['usage']='Orbital globe, not a walkable terrain or a physical-scale planet.'


def prop(kind):
    if kind==0:
        box('Container',(0,0,.43),(1.18,.92,.84),'hull',.07)
        for s in [-1,1]:
            for y in [-.38,.38]:
                box('Corner_guard',(s*.53,y,.46),(.18,.18,.94),'steel',.025)
            box('Carry_handle',(s*.62,0,.66),(.08,.34,.09),'dark',.015)
        lid=empty('Lid_hinge',(0,-.46,.89))
        box('Lid',(0,0,.90),(1.19,.94,.12),'ivory',.035,parent=lid)
        for x in [-.38,.38]:
            box('Latch',(x,.49,.78),(.14,.065,.16),'gold',.02)
        box('Status_panel',(0,.468,.52),(.35,.023,.18),'dark',.012)
        box('Status_light',(0,.485,.52),(.24,.015,.035),'glow',.003)
        object_clip(lid,'Open',[(1,None,(0,0,0)),(25,None,(math.radians(108),0,0)),(49,None,(0,0,0))])
        socket('Pickup',(0,0,.45))
    elif kind==1:
        rod('Capsule_body',(0,0,.14),(0,0,.82),.30,'ivory',vertices=24)
        for z in [.10,.86]:
            rod('End_cap',(0,0,z-.07),(0,0,z+.07),.32,'teal',vertices=24)
        for x in [-.18,.18]:
            box('Protective_rail',(x,.25,.48),(.045,.055,.63),'steel',.012)
        box('Medical_cross_v',(0,.303,.49),(.065,.023,.25),'glow',.006)
        box('Medical_cross_h',(0,.307,.49),(.21,.023,.065),'glow',.006)
        box('Handle',(0,0,1.0),(.28,.08,.08),'dark',.018)
        socket('Pickup',(0,0,.48))
    elif kind==2:
        rod('Beacon_mast',(0,0,-.7),(0,0,.75),.19,'hull',vertices=16)
        ring('Signal_ring',(0,0,.33),.51,.045,'glow')
        sphere('Transmitter',(0,0,.80),(.23,.23,.27),'ivory')
        for s in [-1,1]:
            box('Panel_spar',(s*.65,0,0),(.95,.06,.07),'steel',.015)
            box('Solar_panel',(s*1,0,0),(1.2,.88,.05),'hull',.015)
            for x in [-.4,-.2,0,.2,.4]:
                box('Solar_cell_bus',(s*1+x,0,.033),(.025,.82,.009),'gold',.002)
        rod('Antenna',(0,0,.96),(0,0,1.43),.019,'steel')
        socket('Signal',(0,0,1.45))
        socket('Mount',(0,0,-.72))
    elif kind==3:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=(0,0,.13))
        o=bpy.context.object
        o.scale=(.65,.53,.25)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        register(o,'Rock_bed','dark')
        rng=random.Random(4105)
        for i,(x,y,z) in enumerate([(-.25,0,.27),(0,.08,.3),(.24,-.02,.24),(.1,-.25,.2),(-.28,-.25,.2)]):
            height=rng.uniform(.48,.93)
            rod('Crystal',(x,y,z),(x+.08,y+.03,z+height),.13,'teal' if i%2 else 'violet',.04,6)
            rod('Crystal_tip',(x+.08,y+.03,z+height),(x+.10,y+.04,z+height+.2),.04,'glow',0,6)
        socket('Pickup',(0,0,.4))
    else:
        box('Scanner_case',(0,0,.08),(.32,.42,.13),'ivory',.04)
        box('Rubber_frame',(0,.025,.155),(.26,.30,.035),'dark',.02)
        box('Display',(0,.025,.178),(.215,.25,.012),'glass',.007)
        for y in [-.03,.015,.06]:
            box('Display_trace',(-.025,y,.187),(.13,.008,.006),'glow',.001)
        for x in [-.095,0,.095]:
            sphere('Button',(x,-.15,.154),(.025,.02,.011),'teal',segments=12,rings=8)
        rod('Probe',(0,.21,.07),(0,.42,.07),.032,'steel')
        sphere('Probe_tip',(0,.43,.07),(.045,.04,.045),'glow',segments=16,rings=8)
        box('Hand_strap',(0,0,-.025),(.18,.13,.055),'dark',.015)
        socket('Grip',(0,0,0))
        socket('Sensor',(0,.46,.07))


def bounds():
    bpy.context.view_layer.update()
    points=[]
    for o in OBJECTS:
        if o.type=='MESH':
            points += [o.matrix_world @ Vector(corner) for corner in o.bound_box]
    if not points:
        raise ValueError('Asset contains no meshes')
    low=Vector([min(p[i] for p in points) for i in range(3)])
    high=Vector([max(p[i] for p in points) for i in range(3)])
    return low,high,points


def studio():
    low,high,points=bounds()
    center=(low+high)/2
    extent=max(high-low)
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.device='CPU'
    scene.cycles.samples=16
    scene.cycles.use_denoising=True
    scene.cycles.max_bounces=4
    scene.render.resolution_x=640
    scene.render.resolution_y=640
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=False
    scene.world=bpy.data.worlds.new('Studio_world')
    scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value=(.025,.039,.055,1)
    bg.inputs[1].default_value=.45
    bpy.ops.object.camera_add(location=center+Vector((4.5,7,4.0)).normalized()*extent*4)
    camera=bpy.context.object
    camera.name='__Studio_Camera'
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO'
    camera.data.clip_end=max(1000,extent*30)
    bpy.context.view_layer.update()
    local=[camera.matrix_world.inverted() @ p for p in points]
    projected=max(max(p[a] for p in local)-min(p[a] for p in local) for a in [0,1])
    camera.data.ortho_scale=projected*1.23
    scene.camera=camera
    for name,direction,energy,color in [
        ('Key',(3,4,6),650,(1,.88,.74)),
        ('Fill',(-4,2,3),380,(.56,.76,1)),
        ('Rim',(1,-4,4),850,(.35,1,.88))]:
        bpy.ops.object.light_add(type='AREA',location=center+Vector(direction).normalized()*extent*2)
        light=bpy.context.object
        light.name='__Studio_'+name
        light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
        light.data.energy=energy*extent**2
        light.data.shape='DISK'
        light.data.size=extent*1.4
        light.data.color=color
    scene.view_settings.view_transform='AgX'
    return low,high


def glb_info(path):
    raw=path.read_bytes()
    magic,version,total=struct.unpack_from('<4sII',raw)
    if magic!=b'glTF' or version!=2 or total!=len(raw):
        raise ValueError('Invalid GLB header: '+str(path))
    length,kind=struct.unpack_from('<II',raw,12)
    if kind!=0x4E4F534A:
        raise ValueError('Missing glTF JSON chunk')
    doc=json.loads(raw[20:20+length])
    triangles=sum(doc['accessors'][p['indices']]['count']//3 for m in doc.get('meshes',[]) for p in m['primitives'])
    return {'triangles':triangles,'mesh_nodes':sum('mesh' in n for n in doc.get('nodes',[])),
        'materials':len(doc.get('materials',[])),'animations':[a['name'] for a in doc.get('animations',[])],
        'skins':len(doc.get('skins',[])),'joints':max([len(s['joints']) for s in doc.get('skins',[])]+[0]),
        'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}


def optimize_export():
    global OBJECTS
    groups={}
    for o in OBJECTS:
        if o.type=='MESH':
            groups.setdefault(o.parent.name if o.parent else '',[]).append(o)
    for parent,objects in groups.items():
        if len(objects)<2:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in objects:
            o.select_set(True)
        active=objects[0]
        bpy.context.view_layer.objects.active=active
        bpy.ops.object.join()
        active.name='Geometry_'+parent
    OBJECTS=[o for o in bpy.context.scene.objects if not o.name.startswith('__Studio_')]


def export_current(path):
    bpy.ops.object.select_all(action='DESELECT')
    for o in OBJECTS:
        o.select_set(True)
    bpy.context.view_layer.objects.active=ROOT_OBJECT
    options=dict(filepath=str(path),export_format='GLB',use_selection=True,
                 export_extras=True,export_yup=True,export_animations=True,
                 export_cameras=False,export_lights=False,export_apply=True,
                 export_animation_mode='NLA_TRACKS',export_force_sampling=True,
                 export_frame_range=False,export_nla_strips=True)
    supported=bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    options={k:v for k,v in options.items() if k in supported}
    bpy.ops.export_scene.gltf(**options)


def freeze_for_preview():
    for o in OBJECTS:
        if o.animation_data:
            for track in o.animation_data.nla_tracks:
                track.mute=True
            o.animation_data.action=None
        if o.type=='ARMATURE':
            o.data.pose_position='REST'
            for p in o.pose.bones:
                p.rotation_euler=(0,0,0)
                p.location=(0,0,0)
        if o.name in ['Azimuth','Lid_hinge']:
            o.rotation_euler=(0,0,0)
        if o.name=='Hover_body':
            o.location=(0,0,0)
            o.rotation_euler=(0,0,0)
    bpy.context.view_layer.update()


def build_one(spec, render, rebuild):
    asset_id,title,category,description=spec
    source=SOURCES/(asset_id+'.blend')
    if source.exists() and not rebuild:
        raise FileExistsError(f'{source}: use export_pack.py to preserve manual edits, or --rebuild to replace sources')
    reset(asset_id)
    index=[s[0] for s in SPECS if s[2]==category].index(asset_id)
    {'ships':ship,'weapons':weapon,'avatars':humanoid,'enemies':enemy,'worlds':world,'props':prop}[category](index)
    # All parts are editable in the source; joining is performed only after saving.
    for arm in [o for o in OBJECTS if o.type=='ARMATURE']:
        arm.data.pose_position='REST'
    low,high=studio()
    collection=bpy.data.collections.new('Asset_'+asset_id)
    bpy.context.scene.collection.children.link(collection)
    for o in OBJECTS:
        for owner in list(o.users_collection):
            owner.objects.unlink(o)
        collection.objects.link(o)
    collection.asset_mark()
    collection.asset_data.description=title+' — '+description
    collection.asset_data.catalog_id=str(uuid.uuid5(uuid.NAMESPACE_URL,'lagunak-frontier/'+category))
    meta={'id':asset_id,'title':title,'category':category,'description':description,
        'license':'MIT','source':str(source.relative_to(ROOT)),
        'glb':'res://assets/models/frontier_pack/'+asset_id+'.glb',
        'forward':'-Z','up':'+Y','units':'metres',
        'dimensions_m':[round(float(high.x-low.x),5),round(float(high.z-low.z),5),round(float(high.y-low.y),5)],
        'sockets':[o.name for o in OBJECTS if o.get('socket')],
        'integration':'Library resource; not automatically registered in campaign, avatar editor, combat or Atlas.'}
    text=bpy.data.texts.new('ASSET_README.json')
    text.write(json.dumps(meta,ensure_ascii=False,indent=2))
    bpy.ops.object.select_all(action='DESELECT')
    ROOT_OBJECT.select_set(True)
    bpy.context.view_layer.objects.active=ROOT_OBJECT
    # Source stores editable parts, studio and all clips. It opens in the rest pose.
    bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
    meta['source_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
    for arm in [o for o in OBJECTS if o.type=='ARMATURE']:
        arm.data.pose_position='POSE'
    optimize_export()
    export_current(MODELS/(asset_id+'.glb'))
    meta.update(glb_info(MODELS/(asset_id+'.glb')))
    if render:
        freeze_for_preview()
        bpy.context.scene.render.filepath=str(IMAGES/(asset_id+'.png'))
        bpy.ops.render.render(write_still=True)
    return meta


def sheets(entries):
    from PIL import Image,ImageDraw,ImageFont
    font_path='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    def font(size):
        try:
            return ImageFont.truetype(font_path,size)
        except OSError:
            return ImageFont.load_default(size=size)
    groups=[('catalogue',entries)]+[(cat,[x for x in entries if x['category']==cat]) for cat in ['ships','weapons','avatars','enemies','worlds','props']]
    for group,items in groups:
        cols=4 if group=='catalogue' else min(3,len(items))
        tile=420 if group=='catalogue' else 600
        header=150
        rows=math.ceil(len(items)/cols)
        canvas=Image.new('RGB',(cols*tile,header+rows*(tile+66)+52),'#0b1620')
        draw=ImageDraw.Draw(canvas)
        draw.text((28,24),'FRONTERA  /  VOLUMEN 01',font=font(32),fill='#e4f0ed')
        draw.text((30,76),'ESPACIOKOOP LAGUNAK  ·  '+group.upper()+'  ·  RENDERS DE ASSETS',font=font(15),fill='#79b9b3')
        draw.line((28,116,canvas.width-28,116),fill='#2dd1b7',width=2)
        for i,e in enumerate(items):
            x=(i%cols)*tile
            y=header+(i//cols)*(tile+66)
            image=Image.open(IMAGES/(e['id']+'.png')).convert('RGB').resize((tile,tile),Image.Resampling.LANCZOS)
            canvas.paste(image,(x,y))
            draw.text((x+18,y+tile+7),e['title'],font=font(18 if group=='catalogue' else 23),fill='#edf5f2')
            draw.text((x+18,y+tile+34),f"{e['triangles']:,} tris  ·  "+(' / '.join(e['animations']) if e['animations'] else 'malla estática'),font=font(12 if group=='catalogue' else 15),fill='#8da9b7')
        draw.text((28,canvas.height-31),'Blender 4.5.3  ·  geometría original MIT  ·  las imágenes no son capturas de la campaña',font=font(13),fill='#8da9b7')
        canvas.save(IMAGES/(group+'.jpg'),quality=92)


def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render',action='store_true')
    parser.add_argument('--rebuild',action='store_true')
    parser.add_argument('--only',choices=[s[0] for s in SPECS])
    options=parser.parse_args(args)
    for p in [SOURCES,MODELS,IMAGES]:
        p.mkdir(parents=True,exist_ok=True)
    entries=[]
    for spec in SPECS:
        if options.only and spec[0]!=options.only:
            continue
        print('BUILDING',spec[0],flush=True)
        entries.append(build_one(spec,options.render,options.rebuild))
    manifest_path=MODELS/'manifest.json'
    if options.only and manifest_path.exists():
        prior=json.loads(manifest_path.read_text())['assets']
        entries=[x for x in prior if x['id']!=options.only]+entries
        entries.sort(key=lambda e:[s[0] for s in SPECS].index(e['id']))
    manifest={'format':'lagunak-frontier-library','version':1,'blender':bpy.app.version_string,
        'license':'MIT','asset_count':len(entries),'source_reference':'EspacioKoop/espaciokooplagunakRemake',
        'coordinate_system':'glTF: Y up, -Z forward; Blender: Z up, +Y forward',
        'scope':'Additional development assets. No gameplay or network registration.',
        'assets':entries}
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    catalog=['# Blender Asset Catalog Definition','VERSION 1','']
    for category in ['ships','weapons','avatars','enemies','worlds','props']:
        catalog.append(f"{uuid.uuid5(uuid.NAMESPACE_URL,'lagunak-frontier/'+category)}:Frontera/{category}:{category}")
    (SOURCES/'blender_assets.cats.txt').write_text('\n'.join(catalog)+'\n')
    if options.render and all((IMAGES/(e['id']+'.png')).exists() for e in entries):
        sheets(entries)
    print('FRONTIER_BUILD_OK',len(entries),sum(e['triangles'] for e in entries),flush=True)


if __name__=='__main__':
    main()
