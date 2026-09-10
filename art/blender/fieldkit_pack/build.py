"""Fieldkit: ten original editable assets. Blender/bpy 4.5.3, Python 3.11.

Six player tools, two fictional energy weapons, two ships. No downloaded art.
Coordinates in helpers: Godot metres, X right, Y up, -Z forward.
Existing artist sources are preserved; --force is an explicit destructive reset.
Export edited sources with export.py, not this construction recipe.
"""
from __future__ import annotations
import argparse
import math
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / 'art/blender/fieldkit_pack'
SPECS = [
    ('giltza_hack_tool', 'Giltza · interfaz de hackeo', 'tools', 'Brazalete abierto con consola abatible, contactos y microproyector.', 'wrist'),
    ('kako_tether', 'Kako · gancho magnético', 'tools', 'Herramienta de mano con carrete y garra magnética articulada.', 'grip'),
    ('argi_scanner', 'Argi · escáner de campo', 'tools', 'Escáner de mano con pantalla, aro sensor y antenas plegables.', 'grip'),
    ('jostun_repair', 'Jostun · reparador', 'tools', 'Herramienta de reparación ficticia con pinzas y cartucho de servicio.', 'grip'),
    ('ebaki_cutter', 'Ebaki · cortador de campo', 'tools', 'Cortador industrial ficticio de anillo, resguardo y dos empuñaduras.', 'grip'),
    ('soros_medkit', 'Soros · botiquín de campaña', 'tools', 'Maletín médico de asa central, tapa abatible y módulos extraíbles.', 'handle'),
    ('tximista_carbine', 'Tximista · carabina de pulsos', 'weapons', 'Carabina ficticia con cámara de energía, culata y visor.', 'grip'),
    ('txinparta_sidearm', 'Txinparta · pistola iónica', 'weapons', 'Arma corta ficticia con bobina visible y corredera mecánica.', 'grip'),
    ('enara_shuttle', 'Enara · lanzadera de expedición', 'ships', 'Lanzadera compacta con alas cortas, tren y rampa posterior articulada.', 'centre'),
    ('hontz_corvette', 'Hontz · corbeta de patrulla', 'ships', 'Corbeta de doble góndola con puente elevado y antena orientable.', 'centre'),
]
M = {}


def point(v):
    x, y, z = v
    return Vector((x, -z, y))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = 'field_cycle'
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 49
    M.clear()
    palette = [
        ('chalk', (.68,.76,.73), .18,.4,0),
        ('graphite', (.025,.043,.06), .5,.42,0),
        ('alloy', (.27,.34,.38), .8,.28,0),
        ('amber', (.94,.32,.045), .25,.4,0),
        ('blue', (.035,.13,.29), .4,.35,0),
        ('glass', (.018,.15,.20), .65,.18,0),
        ('cyan', (.06,.75,.91), .1,.23,1.7),
        ('green', (.20,.78,.42), .1,.3,1.0),
        ('brass', (.59,.32,.085), .75,.32,0),
        ('plum', (.27,.055,.14), .4,.4,0),
    ]
    for name, rgb, metallic, roughness, glow in palette:
        mat = bpy.data.materials.new('Fieldkit_' + name)
        mat.diffuse_color = (*rgb,1)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        for key, value in [('Base Color',(*rgb,1)),('Metallic',metallic),('Roughness',roughness),('Emission Color',(*rgb,1)),('Emission Strength',glow)]:
            bsdf.inputs[key].default_value = value
        M[name] = mat


def node(name, parent=None, at=(0,0,0)):
    ob = bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    ob.location = point(at)
    ob.empty_display_size = .05
    return ob


def socket(parent, name, at):
    name = 'socket_' + name
    if name in bpy.data.objects:
        raise ValueError('Duplicate socket: ' + name)
    ob = node(name,parent,at)
    ob['fieldkit_socket'] = True
    ob['forward_axis'] = '-Z in Godot'
    return ob


def finish(ob,name,parent,at,mat):
    ob.name = name
    ob.parent = parent
    ob.location = point(at)
    ob.data.materials.append(M[mat])
    return ob


def box(parent,name,at,size,mat='chalk',bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob = bpy.context.object
    ob.scale = (size[0],size[2],size[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod = ob.modifiers.new('Machined_edge','BEVEL')
        mod.width = min(bevel,min(size)*.24)
        mod.segments = 2
    return finish(ob,name,parent,at,mat)


def rod(parent,name,a,b,radius,mat='alloy',top=None,vertices=24):
    delta = point(b)-point(a)
    if delta.length < 1e-6:
        raise ValueError('Zero-length rod')
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius,
        radius2=radius if top is None else top,depth=delta.length)
    ob = bpy.context.object
    ob.rotation_mode = 'QUATERNION'
    ob.rotation_quaternion = delta.to_track_quat('Z','Y')
    for poly in ob.data.polygons:
        poly.use_smooth = len(poly.vertices)==4
    return finish(ob,name,parent,tuple((x+y)/2 for x,y in zip(a,b)),mat)


def ring(parent,name,at,radius,tube,mat='alloy',axis='Z'):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius,minor_radius=tube,
        major_segments=32,minor_segments=8)
    ob = bpy.context.object
    if axis=='Z':
        ob.rotation_euler.x = math.pi/2
    elif axis=='X':
        ob.rotation_euler.y = math.pi/2
    for poly in ob.data.polygons:
        poly.use_smooth = True
    return finish(ob,name,parent,at,mat)


def ellipsoid(parent,name,at,scale,mat='chalk',detail=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=detail,radius=1)
    ob = bpy.context.object
    ob.scale = (scale[0],scale[2],scale[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(ob,name,parent,at,mat)


def mesh(parent,name,verts,faces,mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata([point(v) for v in verts],[],faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    ob = bpy.data.objects.new(name,data)
    bpy.context.collection.objects.link(ob)
    return finish(ob,name,parent,(0,0,0),mat)


def hull(parent,name,sections,mat='chalk'):
    # Eight-sided loft, each section is (z, half_width, half_height, centre_y).
    cross = [(-.72,-1),(.72,-1),(1,-.65),(1,.65),(.72,1),(-.72,1),(-1,.65),(-1,-.65)]
    verts = [(x*w,y*h+cy,z) for z,w,h,cy in sections for x,y in cross]
    faces = [tuple(range(7,-1,-1)),tuple(range((len(sections)-1)*8,len(sections)*8))]
    for j in range(len(sections)-1):
        for i in range(8):
            a=j*8+i;b=j*8+(i+1)%8
            faces.append((a,b,b+8,a+8))
    return mesh(parent,name,verts,faces,mat)


def plate(parent,name,outline,y,thickness,mat='chalk'):
    verts = [(x,y+sign*thickness/2,z) for sign in (-1,1) for x,z in outline]
    n=len(outline)
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(parent,name,verts,faces,mat)


def animate(ob,axis='Y',angle=.2):
    index={'X':0,'Y':2,'Z':1}[axis]
    direction=-1 if axis=='Z' else 1
    ob.rotation_mode='XYZ'
    original=ob.rotation_euler.copy()
    for frame,value in [(1,0),(13,1),(25,0),(37,-.2),(49,0)]:
        ob.rotation_euler=original
        ob.rotation_euler[index] += direction*angle*value
        ob.keyframe_insert(data_path='rotation_euler',frame=frame)
    ob.rotation_euler=original


def slide(ob,offset=(0,0,.025)):
    original=ob.location.copy()
    for frame,value in [(1,0),(8,1),(16,0),(49,0)]:
        ob.location=original+point(offset)*value
        ob.keyframe_insert(data_path='location',frame=frame)
    ob.location=original


def grip(root,at=(0,0,0),height=.19,width=.065):
    x,y,z=at
    box(root,'Grip_core',(x,y,z),(width,height,.09),'graphite')
    for i in range(5):
        box(root,'Grip_rib',(x,y-height*.35+i*height*.16,z-.045),(width+.006,.012,.012),'alloy',.003)
    box(root,'Grip_heel',(x,y-height*.53,z),(width+.025,.027,.1),'amber',.008)
    socket(root,'grip',at)


def display(root,at,size=(.105,.065,.008),glow='cyan'):
    x,y,z=at
    box(root,'Display_frame',at,(size[0]+.018,size[1]+.018,size[2]),'graphite',.007)
    box(root,'Display_glass',(x,y,z-size[2]),size,'glass',.003)
    for i in range(3):
        box(root,'Display_trace',(x-size[0]*.15+i*.011,y+size[1]*.23-i*.02,z-size[2]*1.7),(size[0]*(.65-i*.13),.004,.002),glow,.001)


def fasteners(root,at,spread=.045):
    x,y,z=at
    for dx in (-spread,spread):
        rod(root,'Recessed_fastener',(x+dx,y,z),(x+dx,y,z-.006),.006,'alloy',vertices=6)


def hack(root):
    # Open octagonal cuff; the opening remains actual geometry, not a solid box.
    for z in (-.115,.115):
        ring(root,'Wrist_band',(0,0,z),.064,.010,'graphite')
    for x in (-.062,.062):
        box(root,'Cuff_rail',(x,.015,0),(.020,.065,.25),'chalk')
        for z in (-.065,.01,.07):
            box(root,'Service_contact',(x,.052,z),(.020,.008,.025),'brass',.002)
    box(root,'Console_backbone',(0,.071,0),(.16,.038,.25),'blue')
    hinge=node('Console_hinge',root,(-.079,.097,.025))
    box(hinge,'Foldout_console',(.077,0,-.012),(.154,.014,.205),'chalk',.006)
    # Screen faces upward in the closed position.
    box(hinge,'Interface_panel',(.077,.009,-.016),(.126,.003,.154),'glass',.001)
    for z in (-.068,-.034,0,.034):
        box(hinge,'Interface_row',(.066,.012,z),(.082,.002,.004),'cyan',.001)
    for x in (.045,.074,.105):
        box(hinge,'Console_button',(x,.012,.071),(.017,.004,.012),'amber',.002)
    rod(root,'Projector_body',(0,.112,-.099),(0,.112,-.145),.023,'alloy')
    rod(root,'Projector_lens',(0,.112,-.146),(0,.112,-.152),.017,'cyan')
    socket(root,'wrist',(0,0,0)); socket(root,'effect',(0,.112,-.153))
    socket(hinge,'screen',(.077,.014,0))
    animate(hinge,'Z',-.9)


def tether(root):
    grip(root)
    hull(root,'Tether_chassis',[(-.31,.055,.047,.14),(-.20,.085,.068,.14),(.085,.08,.065,.14),(.14,.05,.04,.14)],'amber')
    rod(root,'Spool_axle',(-.13,.16,.04),(.13,.16,.04),.055,'graphite')
    for x in (-.108,.108):
        ring(root,'Cable_flange',(x,.16,.04),.080,.012,'alloy','X')
    for x in (-.07,-.042,-.014,.014,.042,.07):
        ring(root,'Cable_winding',(x,.16,.04),.057,.010,'brass','X')
    rod(root,'Magnetic_guide',(0,.14,-.30),(0,.14,-.43),.037,'graphite',.026)
    for i in range(3):
        a=i*math.tau/3
        pivot=node('Hook_petal_'+str(i),root,(math.cos(a)*.025,.14+math.sin(a)*.025,-.39))
        rod(pivot,'Petal_arm',(0,0,0),(math.cos(a)*.043,math.sin(a)*.043,-.07),.012,'alloy')
        rod(pivot,'Magnetic_tip',(math.cos(a)*.043,math.sin(a)*.043,-.07),(math.cos(a)*.018,math.sin(a)*.018,-.105),.015,'amber')
        animate(pivot,'Y',.18)
    display(root,(0,.165,.145),(.09,.045,.006))
    socket(root,'cable_exit',(0,.14,-.44)); socket(root,'hook',(0,.14,-.50))
    socket(root,'offhand',(0,.10,-.22))


def scanner(root):
    grip(root,height=.16,width=.065)
    box(root,'Scanner_case',(0,.11,-.07),(.18,.14,.24),'blue',.025)
    display(root,(0,.13,.061),(.125,.078,.009))
    for x in (-.075,.075):
        box(root,'Bumper',(x,.11,-.09),(.027,.155,.265),'chalk')
        for z in (-.14,-.10,-.06):
            box(root,'Side_vent',(x*1.17,.14,z),(.012,.049,.015),'graphite',.002)
    gimbal=node('Sensor_gimbal',root,(0,.22,-.14))
    ring(gimbal,'Sensor_guard',(0,0,0),.075,.012,'alloy')
    ellipsoid(gimbal,'Multispectral_lens',(0,0,-.013),(.054,.054,.025),'cyan')
    for x in (-.086,.086):
        rod(gimbal,'Sensor_antenna',(x,0,.015),(x*1.25,.16,.015),.008,'brass')
        ellipsoid(gimbal,'Antenna_tip',(x*1.25,.16,.015),(.012,.017,.012),'chalk')
    animate(gimbal,'Y',.45)
    socket(gimbal,'scan_origin',(0,0,-.048));socket(root,'screen',(0,.13,.075))
    socket(root,'offhand',(0,.1,-.15))


def repair(root):
    grip(root,height=.18)
    box(root,'Repair_body',(0,.13,-.11),(.15,.13,.27),'chalk',.024)
    for x in (-.065,.065):
        rod(root,'Service_canister',(x,.14,-.03),(x,.14,.16),.028,'blue')
        ring(root,'Canister_band',(x,.14,.1),.029,.006,'brass')
    box(root,'Status_plate',(0,.203,-.105),(.09,.018,.16),'amber')
    for z in (-.16,-.12,-.08):
        box(root,'Status_light',(0,.216,z),(.056,.005,.009),'cyan',.002)
    for s in (-1,1):
        jaw=node('Jaw_left' if s<0 else 'Jaw_right',root,(s*.057,.13,-.23))
        rod(jaw,'Jaw_shaft',(0,0,0),(s*.022,0,-.15),.018,'alloy',.011)
        rod(jaw,'Repair_contact',(s*.022,0,-.15),(-s*.026,0,-.19),.016,'brass',.009)
        animate(jaw,'Y',s*.22)
        socket(jaw,'contact_left' if s<0 else 'contact_right',(-s*.026,0,-.19))
    rod(root,'Repair_light',(0,.185,-.246),(0,.185,-.27),.023,'cyan')
    socket(root,'effect',(0,.13,-.424));socket(root,'offhand',(0,.10,-.16))


def cutter(root):
    grip(root,height=.21,width=.072)
    hull(root,'Cutter_power_housing',[(-.27,.065,.05,.14),(-.17,.09,.085,.14),(.11,.08,.07,.14)],'amber')
    box(root,'Heat_guard',(0,.233,-.04),(.18,.024,.28),'graphite')
    for i in range(5):
        box(root,'Heat_fin',(0,.259,-.15+i*.046),(.15,.036,.015),'alloy',.003)
    rod(root,'Ring_arm',(0,.15,-.24),(0,.15,-.38),.03,'alloy')
    disk=node('Cutter_ring',root,(0,.15,-.43))
    ring(disk,'Energy_ring',(0,0,0),.105,.018,'brass','X')
    ring(disk,'Inner_emitter',(0,0,0),.077,.009,'cyan','X')
    rod(disk,'Rotor_axle',(-.034,0,0),(.034,0,0),.030,'graphite')
    for i in range(8):
        a=i*math.tau/8
        rod(disk,'Rotor_spoke',(0,math.sin(a)*.037,math.cos(a)*.037),(0,math.sin(a)*.089,math.cos(a)*.089),.007,'alloy')
    # Separated shield plates cover the rear arc and leave the leading edge visible.
    for a in (-.9,-.45,0,.45,.9):
        box(root,'Ring_resguardo',(0,.15+math.sin(a)*.127,-.43+math.cos(a)*.127),(.09,.044,.036),'chalk',.006)
    for x in (-.13,.13):
        rod(root,'Front_handle_support',(x*.6,.12,-.19),(x,.23,-.19),.016,'alloy')
    rod(root,'Front_handle',(-.13,.23,-.19),(.13,.23,-.19),.023,'graphite')
    animate(disk,'X',math.pi*1.5)
    socket(root,'cut_origin',(0,.15,-.555));socket(root,'offhand',(0,.23,-.19))


def medkit(root):
    # Origin at the carry handle; the case hangs below the player's hand.
    box(root,'Case_body',(0,-.18,0),(.36,.23,.19),'chalk',.025)
    box(root,'Case_midband',(0,-.18,-.101),(.325,.055,.024),'blue')
    for x in (-.172,.172):
        box(root,'Corner_guard',(x,-.18,0),(.038,.247,.205),'graphite')
    for x in (-.08,.08):
        rod(root,'Handle_support',(x,-.062,0),(x,.005,0),.017,'alloy')
    rod(root,'Carry_handle',(-.08,.005,0),(.08,.005,0),.022,'graphite')
    socket(root,'grip',(0,.005,0));socket(root,'belt',(0,-.14,.11))
    lid=node('Medical_lid',root,(0,-.29,.102))
    box(lid,'Hinged_front',(0,.11,-.206),(.318,.19,.019),'chalk')
    # Original green diamond emblem, not a protected red-cross emblem.
    emblem=box(lid,'Medical_diamond',(0,.11,-.22),(.059,.059,.007),'green',.004)
    emblem.rotation_euler.y=math.pi/4
    for x in (-.12,.12):
        box(lid,'Latch',(x,.19,-.214),(.035,.045,.019),'amber')
    for i,x in enumerate((-.105,-.035,.035,.105)):
        rod(root,'Sealed_cartridge',(x,-.26,-.047),(x,-.105,-.047),.025,'blue' if i%2 else 'alloy')
        ring(root,'Cartridge_seal',(x,-.122,-.047),.026,.005,'green','Y')
    display(root,(0,-.10,-.11),(.13,.034,.005),'green')
    animate(lid,'X',-1.05)
    socket(root,'treatment',(0,-.18,-.14));socket(root,'offhand',(0,-.29,0))


def weapon(root,small=False):
    grip(root,height=.2 if small else .23,width=.07)
    y=.165
    if small:
        hull(root,'Ion_frame',[(-.31,.044,.04,y),(-.24,.069,.068,y),(.14,.065,.055,y)],'plum')
        emitter=node('Ion_slide',root,(0,y,-.09))
        box(emitter,'Slide',(0,.027,0),(.122,.077,.33),'chalk')
        rod(emitter,'Ion_coil_core',(0,0,-.12),(0,0,-.255),.028,'cyan')
        for z in (-.14,-.17,-.20,-.23):
            ring(emitter,'Coil_turn',(0,0,z),.037,.008,'brass')
        box(root,'Aim_post',(0,.262,-.205),(.019,.018,.035),'graphite',.003)
        box(root,'Rear_sight',(0,.258,.092),(.070,.020,.026),'graphite',.003)
        socket(emitter,'muzzle',(0,0,-.265))
        socket(root,'aim',(0,.276,.075))
    else:
        hull(root,'Pulse_receiver',[(-.57,.053,.044,y),(-.42,.075,.075,y),(.17,.079,.07,y)],'blue')
        box(root,'Power_magazine',(0,-.015,-.20),(.085,.24,.12),'alloy',.014)
        for z in (-.245,-.20,-.155):
            box(root,'Magazine_status',(0,.01,z),(.09,.014,.012),'cyan',.002)
        hull(root,'Stock',[ (.15,.052,.036,y),(.31,.043,.024,y),(.47,.057,.086,y-.025)],'graphite')
        box(root,'Butt_pad',(0,.13,.478),(.13,.22,.040),'alloy')
        emitter=node('Pulse_emitter',root,(0,y,-.42))
        rod(emitter,'Capacitor',(0,0,.065),(0,0,-.23),.034,'cyan')
        for z in (-.16,-.105,-.05,.005):
            ring(emitter,'Induction_band',(0,0,z),.045,.010,'brass')
        for x in (-.057,.057):
            box(emitter,'Emitter_rail',(x,0,-.075),(.025,.073,.37),'chalk')
        rod(emitter,'Front_shroud',(0,0,-.21),(0,0,-.30),.060,'graphite',.047)
        rod(root,'Optic',(0,.29,.02),(0,.29,-.18),.039,'graphite')
        rod(root,'Optic_lens',(0,.29,-.181),(0,.29,-.19),.030,'glass')
        for i in range(7):
            box(root,'Rail_notch',(0,.255,-.39+i*.066),(.082,.012,.022),'alloy',.003)
        socket(root,'offhand',(0,.102,-.34));socket(root,'aim',(0,.29,.035))
        socket(emitter,'muzzle',(0,0,-.304))
    for x in (-.045,.045):
        rod(root,'Trigger_guard',(x*.7,.09,-.055),(x*.7,-.045,-.11),.008,'alloy')
    rod(root,'Guard_crossbar',(-.032,-.045,-.11),(.032,-.045,-.11),.009,'alloy')
    slide(emitter,(0,0,.035))
    socket(root,'holster',(0,.055,.085));socket(root,'power_cell',(0,-.09,0))


def engine(root,name,at,radius,length):
    x,y,z=at
    rod(root,name+'_body',(x,y,z-length*.5),(x,y,z+length*.5),radius,'graphite',radius*.78,24)
    for dz in (-.31,.15,.50):
        ring(root,name+'_band',(x,y,z+dz*length),radius*(.83 if dz>.4 else .95),radius*.09,'alloy')
    rod(root,name+'_emission',(x,y,z+length*.5),(x,y,z+length*.52),radius*.55,'cyan')
    socket(root,'exhaust_'+name,(x,y,z+length*.53))


def shuttle(root):
    hull(root,'Enara_hull',[(-5.9,.35,.38,.05),(-4.5,1.2,.65,.12),(-2.0,1.7,.95,.12),(2.9,1.7,.95,.12),(4.2,1.17,.68,.12)],'chalk')
    hull(root,'Enara_canopy',[(-4.65,.67,.19,.80),(-3.5,1.12,.48,1.05),(-1.85,.91,.39,1.08)],'glass')
    box(root,'Canopy_spine',(0,1.48,-2.9),(.17,.10,2.1),'blue',.04)
    for s in (-1,1):
        wing=[(s*1.35,-2.5),(s*4.2,.0),(s*4.8,2.6),(s*1.35,1.55)]
        plate(root,'Swept_wing',wing,.02,.21,'blue')
        plate(root,'Wing_inlay',[(s*1.8,-1.7),(s*3.8,.05),(s*4.25,1.7),(s*1.8,1.1)],.145,.025,'chalk')
        engine(root,'left' if s<0 else 'right',(s*2.7,.02,2.0),.67,3.6)
        for i in range(5):
            box(root,'Hull_louvre',(s*1.72,.49,-.7+i*.47),(.075,.27,.20),'graphite')
        box(root,'Safety_stripe',(s*1.33,1.04,.35),(.18,.032,3.1),'amber')
        gear=node('Landing_left' if s<0 else 'Landing_right',root,(s*1.0,-.68,.4))
        rod(gear,'Gear_strut',(0,0,0),(s*.32,-.86,0),.095,'alloy')
        rod(gear,'Hydraulic',(s*.16,-.10,.22),(s*.32,-.75,0),.04,'graphite')
        box(gear,'Landing_foot',(s*.32,-.91,0),(.72,.16,1.25),'graphite',.06)
        animate(gear,'Z',s*.19)
        socket(root,'hardpoint_left' if s<0 else 'hardpoint_right',(s*2.4,-.32,-.65))
    ramp=node('Cargo_ramp',root,(0,-.54,4.2))
    box(ramp,'Ramp_panel',(0,.46,0),(1.76,.92,.14),'blue',.06)
    for x in (-.68,0,.68):
        box(ramp,'Ramp_track',(x,.46,.09),(.05,.85,.045),'alloy')
    animate(ramp,'X',1.0)
    for x in (-.48,.48):
        socket(root,'pilot' if x<0 else 'copilot',(x,.90,-3.25))
    socket(root,'entry',(0,-.55,4.31));socket(root,'cargo',(0,.12,1.2))
    socket(root,'centre',(0,0,0))


def corvette(root):
    hull(root,'Hontz_keel',[(-13,.28,.30,-.2),(-10,1.1,.75,-.1),(-4.8,2.1,1.35,0),(5.5,2.25,1.4,0),(9.8,1.55,1.0,0)],'graphite')
    hull(root,'Dorsal_armour',[(-10.5,.43,.15,.65),(-5.7,1.77,.35,1.15),(4.6,1.83,.41,1.18),(8.4,1.1,.32,1.0)],'chalk')
    hull(root,'Command_bridge',[(-4.9,.8,.22,1.55),(-3.2,1.13,.55,2.0),(-.4,.94,.46,2.02)],'blue')
    hull(root,'Bridge_glazing',[(-4.83,.70,.15,1.77),(-3.3,1.04,.33,2.19),(-1.2,.84,.24,2.16)],'glass')
    for s in (-1,1):
        plate(root,'Nacelle_bridge',[(s*1.8,-3),(s*5,-.7),(s*5.5,6.3),(s*1.9,3.1)],-.05,.48,'alloy')
        nacelle=node('Nacelle_left' if s<0 else 'Nacelle_right',root,(s*4.7,-.12,1.5))
        hull(nacelle,'Outrigger_armour',[(-4.6,.31,.37,0),(-2.9,.87,.78,0),(4.7,.89,.76,0),(6.0,.58,.59,0)],'blue')
        engine(root,'port' if s<0 else 'starboard',(s*4.7,-.12,7.4),.84,2.5)
        for i in range(9):
            box(nacelle,'Radiator_blade',(s*.96,.24,-2.5+i*.62),(.35,.18,.24),'graphite',.03)
        for i in range(5):
            box(root,'Hull_service_panel',(s*2.12,.46,-2.8+i*1.3),(.18,.62,.87),'chalk',.06)
        box(root,'Hull_identification_bar',(s*1.14,1.64,3.1),(.27,.07,4.3),'amber',.025)
        for z in (-7.2,2.2):
            mount=node('Mount_'+('left' if s<0 else 'right')+('_fore' if z<0 else '_aft'),root,(s*1.44,1.23,z))
            rod(mount,'Mount_plate',(0,0,0),(0,.19,0),.37,'alloy',vertices=16)
            socket(mount,'hardpoint_'+('left' if s<0 else 'right')+('_fore' if z<0 else '_aft'),(0,.2,0))
    sensor=node('Survey_dish',root,(0,2.17,2.3))
    rod(sensor,'Sensor_pedestal',(0,0,0),(0,.83,0),.18,'alloy')
    ring(sensor,'Sensor_dish',(0,1.0,0),.72,.11,'chalk')
    for x in (-.36,0,.36):
        rod(sensor,'Dish_lattice',(x,.48,0),(x,1.52,0),.028,'brass')
    ellipsoid(sensor,'Sensor_eye',(0,1.0,-.06),(.27,.27,.16),'cyan')
    animate(sensor,'Y',.65)
    socket(sensor,'scan_origin',(0,1.0,-.24))
    ring(root,'Docking_collar',(0,-.36,9.91),.68,.14,'alloy')
    socket(root,'dock',(0,-.36,10.07));socket(root,'bridge',(0,2,-2.5))
    socket(root,'centre',(0,0,0))


BUILDERS = [hack,tether,scanner,repair,cutter,medkit,lambda r: weapon(r,False),lambda r: weapon(r,True),shuttle,corvette]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group()
    group.add_argument('--missing-only',action='store_true')
    group.add_argument('--force',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    HERE.mkdir(parents=True,exist_ok=True)
    created=preserved=0
    for spec,builder in zip(SPECS,BUILDERS):
        name,title,category,description,pivot=spec
        path=HERE/(name+'.blend')
        if path.exists() and not args.force:
            if args.missing_only:
                preserved+=1
                continue
            raise FileExistsError(str(path)+' exists; use export.py to preserve manual edits')
        reset()
        root=node(name)
        root['asset_id']='fieldkit/'+name
        root['asset_version']=1
        root['category']=category
        root['description']=description
        root['pivot']=pivot
        root['license']='MIT'
        builder(root)
        bpy.context.scene.frame_set(1)
        bpy.context.view_layer.update()
        # Source retains individual parts, modifiers and mechanical pivots.
        bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
        created+=1
    print(f'FIELDKIT_SOURCES_PASS created={created} preserved={preserved}',flush=True)


if __name__=='__main__':
    main()
