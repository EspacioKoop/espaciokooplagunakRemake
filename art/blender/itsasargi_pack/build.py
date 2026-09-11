"""Original Itsasargi hard-surface models; MIT, no downloaded geometry.
Python + bpy 4.5.3, or blender -b --python this_file -- --missing-only.
Each saved .blend is the editable source of truth. Existing sources are protected.
Blender: X right, Y forward, Z up. Export: X right, Y up, -Z forward. Metres.
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
    ('arc_welder', 'Lotu · soldador de arco', 'tools', 'Colimador retráctil y batería extraíble visual; reparación ficticia.'),
    ('eva_winch', 'Amarra · cabrestante EVA', 'tools', 'Tambor, guía y mosquetón para cable de seguridad; sin simulación de cuerda.'),
    ('rescue_beacon', 'Argi · baliza de emergencia', 'tools', 'Trípode, reflector rotatorio y antena de señalización.'),
    ('specimen_case', 'Hazi · maletín de especímenes', 'tools', 'Tapa articulada, seis cápsulas y cierres; transporte científico.'),
    ('oxygen_rebreather', 'Arnasa · respirador portátil', 'tools', 'Dos depósitos, regulador, máscara y tubo; accesorio de ciencia ficción.'),
    ('field_transceiver', 'Irrati · transceptor de campo', 'tools', 'Antena desplegable, dial, pantalla y altavoz para comunicaciones.'),
    ('prism_sidearm', 'Prisma · pistola fotónica', 'weapons', 'Arma visual ficticia con prisma, corredera y boca para efectos.'),
    ('gravity_lance', 'Indar · lanza gravitatoria', 'weapons', 'Arma visual ficticia de dos manos con emisores abiertos y anillos.'),
    ('marra_interceptor', 'Marra · interceptor de ala manta', 'ships', 'Silueta ancha, alas articuladas, cabina y dos propulsores.'),
    ('hodei_surveyor', 'Hodei · corbeta de exploración', 'ships', 'Casco catamarán, observatorio giratorio y bahía científica exterior.'),
]
MAT = {}
ROOT_OBJECT = None


def material(name, color, metal=0.0, rough=0.45, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Emission Color'].default_value = (*color, 1)
    bsdf.inputs['Emission Strength'].default_value = emission
    return mat


def palette():
    global MAT
    MAT = {
        'shell': material('I_ceramic_ivory', (0.65, 0.72, 0.71), .35, .32),
        'navy': material('I_deep_petrol', (.028, .11, .15), .65, .33),
        'metal': material('I_titanium', (.23, .29, .32), .85, .28),
        'rubber': material('I_graphite_grip', (.019, .025, .033), .0, .72),
        'orange': material('I_safety_amber', (.95, .28, .035), .3, .34),
        'cyan': material('I_cyan_emitter', (.04, .70, .9), .2, .25, 2),
        'amber': material('I_amber_indicator', (1, .40, .035), .15, .3, 1.6),
        'glass': material('I_opaque_blue_glass', (.025, .16, .25), .72, .13),
        'violet': material('I_prism_emitter', (.43, .12, .95), .2, .25, 1.8),
    }


def finish(ob, name, mat, parent=None, bevel=0):
    ob.name = name
    ob.parent = parent if parent is not None else ROOT_OBJECT
    ob.data.materials.clear()
    ob.data.materials.append(MAT[mat])
    if bevel:
        mod = ob.modifiers.new('Editable_edge_bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        mod.affect = 'EDGES'
    return ob


def box(name, pos, size, mat='shell', parent=None, bevel=.008, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    ob = bpy.context.object
    ob.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rot is not None:
        ob.rotation_euler = rot
    return finish(ob, name, mat, parent, min(bevel, min(size)*.22))


def cylinder(name, pos, radius, depth, mat='metal', parent=None, axis=(0,0,1), vertices=16, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=pos)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=r2, depth=depth, location=pos)
    ob = bpy.context.object
    ob.rotation_euler = Vector(axis).to_track_quat('Z','Y').to_euler()
    return finish(ob, name, mat, parent, min(radius*.06, depth*.08))


def ring(name, pos, radius, tube, mat='metal', parent=None, axis=(0,0,1)):
    bpy.ops.mesh.primitive_torus_add(major_segments=24, minor_segments=8, location=pos, major_radius=radius, minor_radius=tube)
    ob=bpy.context.object
    ob.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler()
    return finish(ob,name,mat,parent)


def beam(name, a, b, radius, mat='metal', parent=None):
    a,b=Vector(a),Vector(b)
    return cylinder(name,(a+b)/2,radius,(b-a).length,mat,parent,b-a)


def pivot(name, pos=(0,0,0), parent=None):
    ob=bpy.data.objects.new(name,None)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent=parent if parent is not None else ROOT_OBJECT
    ob.location=pos
    ob.empty_display_type='PLAIN_AXES'
    ob.empty_display_size=.06
    return ob


def socket(name, pos, parent=None, rotation=(0,0,0)):
    ob=pivot('socket_'+name,pos,parent)
    ob.rotation_euler=rotation
    ob['purpose']=name
    ob['forward_axis_godot']='-Z'
    return ob


def cycle(ob, axis, amount, move=False):
    prop='location' if move else 'rotation_euler'
    original=getattr(ob,prop)[axis]
    for frame,weight in ((1,0),(31,1),(61,1),(91,0)):
        getattr(ob,prop)[axis]=original+amount*weight
        ob.keyframe_insert(data_path=prop,frame=frame)
    getattr(ob,prop)[axis]=original
    ob['articulation']='mechanical_cycle'


def hose(name, points, radius=.014, mat='rubber', parent=None):
    for i in range(len(points)-1):
        beam(name+'_'+str(i),points[i],points[i+1],radius,mat,parent)
    for i,p in enumerate(points[1:-1]):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,radius=radius,location=p)
        finish(bpy.context.object,name+'_joint_'+str(i),mat,parent)


def plate(name, polygon, z, depth, mat='shell', parent=None):
    n=len(polygon)
    verts=[(x,y,z-depth/2) for x,y in polygon]+[(x,y,z+depth/2) for x,y in polygon]
    faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces); mesh.update()
    ob=bpy.data.objects.new(name,mesh); bpy.context.scene.collection.objects.link(ob)
    return finish(ob,name,mat,parent,min(depth*.12,.04))


def hull(name, sections, mat='shell', parent=None):
    # Octagonal cross sections (y, half-width, bottom, top), no zero-area tips.
    verts=[]
    for y,w,lo,hi in sections:
        d=(hi-lo)*.23
        verts.extend([(-w*.7,y,lo), (w*.7,y,lo), (w,y,lo+d), (w,y,hi-d),
                      (w*.7,y,hi),(-w*.7,y,hi),(-w,y,hi-d),(-w,y,lo+d)])
    faces=[tuple(reversed(range(8)))]
    for j in range(len(sections)-1):
        for k in range(8):
            a=j*8+k;b=j*8+(k+1)%8
            faces.append((a,b,b+8,a+8))
    faces.append(tuple(range((len(sections)-1)*8,len(sections)*8)))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    ob=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(ob)
    return finish(ob,name,mat,parent,.025)


def grip(parent=None, pos=(0,-.12,-.12), length=.20):
    box('Grip_frame',pos,(.085,.11,length),'navy',parent,.014)
    for i in range(6):
        box('Grip_rib_'+str(i),(pos[0],pos[1]-.006,pos[2]-length*.39+i*length*.15),(.093,.108,.011),'rubber',parent,.004)
    socket('grip_primary',pos,parent)


def vents(prefix, pos, count=6, step=.045, parent=None, size=(.012,.12,.012)):
    for i in range(count):
        box(prefix+str(i),(pos[0]+(i-(count-1)/2)*step,pos[1],pos[2]),size,'rubber',parent,.002)


def welder():
    grip()
    box('Power_body',(0,.02,.075),(.19,.30,.16),'navy',bevel=.025)
    box('Ceramic_guard',(0,.07,.155),(.20,.25,.035),'shell')
    box('Battery',(0,-.15,.05),(.145,.095,.145),'orange',bevel=.018)
    for x in (-.10,.10):
        box('Thermal_cheek',(x,.045,.06),(.026,.19,.10),'shell')
    cylinder('Emitter_collar',(0,.20,.075),.065,.09,'metal',axis=(0,1,0))
    moving=pivot('arc_collet',(0,.24,.075))
    cylinder('Ceramic_nozzle',(0,.035,0),.043,.10,'shell',moving,(0,1,0),r2=.026)
    for x in (-.025,.025):
        beam('Tungsten_prong',(x,.07,0),(x,.13,0),.009,'metal',moving)
    ring('Arc_ring',(0,.083,0),.030,.006,'cyan',moving,(0,1,0))
    socket('effect_arc',(0,.145,0),moving)
    cycle(moving,1,.025,True)
    vents('Heat_slot_', (0,.10,.18),5,.031,size=(.013,.08,.008))
    socket('battery',(0,-.205,.05))


def winch():
    box('Mount',(0,0,0),(.32,.13,.33),'navy',bevel=.026)
    for x in (-.14,.14):
        box('Cage',(x,.07,0),(.04,.20,.32),'shell')
    drum=pivot('winch_drum',(0,.095,0))
    cylinder('Spool',(0,0,0),.113,.23,'rubber',drum,(1,0,0),24)
    for x in (-.12,.12):
        cylinder('Spool_flange',(x,0,0),.141,.018,'orange',drum,(1,0,0),24)
    for x in range(12):
        ring('Wound_tether_'+str(x),(-.099+x*.018,0,0),.116,.007,'metal',drum,(1,0,0))
    cycle(drum,0,math.pi)
    beam('Handle_top',(-.13,0,.21),(.13,0,.21),.022,'rubber')
    for x in (-.13,.13):beam('Handle_leg',(x,0,.12),(x,0,.21),.018)
    beam('Tether_out',(0,.21,0),(0,.31,-.09),.008,'orange')
    ring('Carabiner',(0,.33,-.13),.047,.011,'metal',axis=(1,0,0))
    cylinder('Lock_sleeve',(0,.374,-.13),.016,.046,'orange')
    socket('grip_primary',(0,0,.21))
    socket('tether_exit',(0,.21,0))
    socket('mount',(0,-.075,0),rotation=(0,0,math.pi))


def beacon():
    cylinder('Core',(0,0,.35),.083,.42,'navy',vertices=12)
    for i in range(3):
        ang=i*2*math.pi/3
        leg=pivot('leg_'+str(i),(0,0,.23));leg.rotation_euler.z=ang
        beam('Strut',(0,.06,0),(0,.32,-.20),.021,'metal',leg)
        box('Foot',(0,.32,-.215),(.09,.09,.03),'rubber',leg)
        cycle(leg,0,-.20)
    cylinder('Beacon_base',(0,0,.59),.14,.065,'orange')
    rotating=pivot('beacon_reflector',(0,0,.655))
    cylinder('Beacon_lens',(0,0,0),.109,.09,'amber',rotating,vertices=24)
    box('Reflector',(0,-.025,0),(.17,.023,.12),'shell',rotating)
    cycle(rotating,2,math.pi*1.5)
    cylinder('Cap',(0,0,.728),.143,.03,'navy')
    beam('Antenna',(.05,0,.75),(.05,0,.98),.008)
    for z in (.78,.84,.90):cylinder('Antenna_ring',(.05,0,z),.014,.018,'orange')
    socket('signal',(0,0,.70));socket('grip_primary',(0,0,.36));socket('ground',(0,0,0))


def case():
    box('Case_shell',(0,0,.11),(.50,.32,.20),'navy',bevel=.026)
    box('Case_rim',(0,0,.21),(.52,.34,.045),'metal')
    box('Foam_bed',(0,0,.235),(.46,.28,.036),'rubber')
    for i in range(6):
        x=(i%3-1)*.145;y=(-.065 if i<3 else .065)
        cylinder('Sample_sleeve_'+str(i),(x,y,.268),.046,.052,'shell')
        cylinder('Sample_lid_'+str(i),(x,y,.305),.044,.025,'cyan')
        socket('sample_'+str(i),(x,y,.34))
    lid=pivot('case_lid',(0,-.17,.24))
    box('Lid_shell',(0,.17,.035),(.52,.34,.06),'shell',lid,.018)
    box('Lid_inlay',(0,.17,.069),(.40,.25,.018),'navy',lid)
    box('Safety_mark_a',(0,.17,.084),(.12,.035,.008),'orange',lid)
    box('Safety_mark_b',(0,.17,.085),(.035,.12,.008),'orange',lid)
    cycle(lid,0,math.radians(105))
    for x in (-.19,.19):
        box('Latch',(x,.175,.18),(.053,.025,.08),'orange')
        cylinder('Hinge',(x,-.176,.24),.024,.065,'metal',axis=(1,0,0))
    for x in (-.085,.085):box('Handle_post',(x,.22,.12),(.022,.11,.03),'metal')
    box('Carry_handle',(0,.266,.12),(.19,.035,.035),'rubber')
    socket('grip_primary',(0,.266,.12));socket('ground',(0,0,0))


def rebreather():
    box('Backplate',(0,0,.18),(.29,.075,.40),'navy',bevel=.023)
    for x in (-.105,.105):
        cylinder('Oxygen_tank',(x,.10,.20),.078,.35,'shell',vertices=20)
        for z in (.07,.31):
            ring('Tank_band',(x,.10,z),.081,.012,'orange')
        cylinder('Valve',(x,.1,.408),.028,.075,'metal')
        box('Valve_handle',(x,.1,.456),(.072,.018,.016),'orange')
    box('Regulator',(0,.10,.21),(.072,.12,.14),'metal')
    cylinder('Gauge',(0,.175,.25),.034,.018,'cyan',axis=(0,1,0))
    hose('Breathing_hose',[(.06,.1,.43),(.22,.15,.47),(.28,.29,.38),(.23,.40,.18),(.08,.43,.11)],.019)
    mask=pivot('breathing_mask',(0,.39,.14))
    hull('Mask',[(0,.10,-.055,.065),(.07,.065,-.04,.05)],'rubber',mask)
    cylinder('Mask_filter',(0,.092,0),.053,.052,'shell',mask,(0,1,0))
    ring('Filter_trim',(0,.12,0),.049,.006,'cyan',mask,(0,1,0))
    cycle(mask,2,.14)
    socket('mask',(0,0,0),mask)
    socket('back_mount',(0,-.043,.19),rotation=(0,0,math.pi))
    socket('grip_primary',(0,.04,.42))


def radio():
    box('Radio_chassis',(0,0,.12),(.16,.095,.28),'navy',bevel=.018)
    box('Front_panel',(0,.052,.13),(.137,.023,.22),'shell')
    box('Readout',(0,.069,.198),(.108,.012,.060),'glass')
    for i in range(5):
        box('Signal_bar_'+str(i),(-.038+i*.019,.077,.188+i*.004),(.009,.005,.012+i*.008),'cyan')
    for z in range(5):box('Speaker_slot_'+str(z),(0,.067,.074+z*.012),(.098,.009,.005),'rubber')
    cylinder('Tuning_dial',(.042,0,.285),.023,.047,'orange',vertices=12)
    ant=pivot('radio_antenna',(-.055,0,.272))
    cylinder('Aerial',(0,0,.13),.010,.26,'rubber',ant)
    cylinder('Aerial_tip',(0,0,.26),.014,.025,'orange',ant)
    cycle(ant,1,-.48)
    socket('signal',(0,0,.275),ant)
    box('Push_to_talk',(-.087,0,.15),(.025,.05,.07),'orange')
    box('Belt_clip',(0,-.061,.16),(.055,.014,.15),'metal')
    socket('grip_primary',(0,0,.12));socket('belt',(0,-.07,.16))


def pistol():
    grip(pos=(0,-.12,-.095),length=.22)
    plate('Trigger_guard',[(-.06,-.13),(.06,-.13),(.065,.055),(-.065,.055)],-.062,.024,'metal')
    box('Receiver',(0,.015,.075),(.13,.31,.115),'navy',bevel=.016)
    for x in (-.074,.074):box('Side_plate',(x,.006,.089),(.022,.25,.075),'shell')
    slide=pivot('prism_shroud',(0,.07,.125))
    box('Shroud',(0,0,0),(.15,.26,.047),'shell',slide)
    cycle(slide,1,-.055,True)
    cylinder('Prism_chamber',(0,.11,.072),.042,.19,'violet',axis=(0,1,0),vertices=6)
    for y in (.055,.13,.205):ring('Prism_cage',(0,y,.072),.048,.009,'metal',axis=(0,1,0))
    cylinder('Muzzle',(0,.229,.072),.052,.035,'navy',axis=(0,1,0),vertices=6)
    box('Rear_sight',(0,-.089,.167),(.06,.018,.026),'orange')
    box('Front_sight',(0,.20,.16),(.012,.02,.025),'cyan')
    socket('muzzle',(0,.255,.072));socket('holster',(.092,-.12,-.05))
    socket('cell',(0,-.12,-.228))


def lance():
    grip(pos=(0,-.28,-.14),length=.22)
    box('Stock',(0,-.48,.015),(.16,.27,.15),'navy',bevel=.020)
    box('Shoulder_pad',(0,-.63,.015),(.18,.036,.17),'rubber')
    box('Reactor',(0,-.20,.07),(.20,.38,.19),'shell',bevel=.022)
    box('Energy_cell',(0,-.12,-.075),(.11,.18,.10),'orange')
    beam('Central_spine',(0,-.05,.075),(0,.59,.075),.035,'metal')
    for i,y in enumerate((.06,.22,.38)):
        rotor=pivot('gravity_ring_'+str(i),(0,y,.075))
        ring('Coil',(0,0,0),.112,.018,'navy',rotor,(0,1,0))
        for angle in (0,math.pi/2,math.pi,math.pi*1.5):
            x=.112*math.cos(angle);z=.112*math.sin(angle)
            box('Coil_cap',(x,0,z),(.047,.08,.039),'violet',rotor)
        cycle(rotor,1,(-1 if i%2 else 1)*math.pi/2)
    for x in (-.145,.145):
        plate('Emitter_fork',[(x-.022,-.01),(x+.022,-.01),(x+.026,.57),(x,.66),(x-.026,.57)],.075,.042,'metal')
        box('Fork_light',(x,.51,.1),(.023,.19,.017),'cyan')
    box('Foregrip',(0,.05,-.11),(.075,.17,.085),'rubber')
    socket('grip_support',(0,.05,-.11));socket('muzzle',(0,.67,.075));socket('stock',(0,-.65,.015))


def thruster(name, pos, radius, length, parent=None):
    cylinder(name+'_body',pos,radius,length,'navy',parent,(0,1,0),20,r2=radius*.76)
    x,y,z=pos
    ring(name+'_rim',(x,y-length/2,z),radius*.86,radius*.13,'metal',parent,(0,1,0))
    cylinder(name+'_emission',(x,y-length/2-.012,z),radius*.68,.025,'cyan',parent,(0,1,0),20)
    socket(name+'_exhaust',(x,y-length/2-.045,z),parent,(0,0,math.pi))


def marra():
    hull('Central_hull',[(-4.5,.65,-.5,.42),(-2,1.1,-.50,.68),(1.5,.86,-.36,.62),(4.6,.25,-.15,.25),(5.3,.09,-.08,.08)])
    hull('Canopy',[(0,.65,.50,.80),(1.1,.52,.57,1.18),(2.3,.22,.44,.65)],'glass')
    box('Canopy_spine',(0,1.25,.94),(.10,1.7,.09),'navy',bevel=.015)
    for side in (-1,1):
        wing=plate('Manta_wing',[(side*.5,1.6),(side*2.1,.3),(side*5.6,-3.4),(side*3.3,-4.1),(side*.8,-2.8)],0,.26,'navy')
        plate('Wing_armour',[(side*1.2,.6),(side*1.95,0),(side*4.6,-3.0),(side*3.05,-3.25),(side*1.15,-2.1)],.20,.13,'shell')
        plate('Wing_mark',[(side*2.1,-.8),(side*2.4,-1.1),(side*3.55,-2.75),(side*3.14,-2.65)],.29,.035,'orange')
        fin=pivot('wingtip_'+('left' if side<0 else 'right'),(side*4,-3,.12))
        plate('Tip_fin',[(0,0),(side*1.65,-.25),(side*1.3,-1.0),(0,-.8)],0,.16,'metal',fin)
        cycle(fin,1,side*.35)
        thruster('engine_'+('left' if side<0 else 'right'),(side*1.55,-3.6,-.12),.50,2.0)
        cylinder('Forward_emitter',(side*1.25,.5,-.1),.115,1.4,'metal',axis=(0,1,0))
        socket('hardpoint_'+('left' if side<0 else 'right'),(side*1.25,1.3,-.1))
        for j in range(4):box('Cooling_vane',(side*.86,-2.5+j*.3,.62),(.34,.10,.04),'rubber')
        box('Navigation_light',(side*5.1,-3.4,.18),(.16,.30,.08),'cyan' if side>0 else 'amber')
    socket('cockpit',(0,1.2,.9));socket('dock',(0,-4.6,-.03),rotation=(0,0,math.pi))
    socket('centre_of_mass',(0,-.6,0))


def hodei():
    hull('Central_lab',[(-5,1.3,-.55,.65),(-2,1.55,-.7,1.25),(2,1.15,-.55,1.1),(4.8,.60,-.20,.55)],'navy')
    hull('Observatory_bridge',[(1.1,1.02,.95,1.15),(2.2,.85,1.0,1.65),(3.6,.42,.70,1.02)],'glass')
    for side in (-1,1):
        pod=pivot('outrigger_'+('left' if side<0 else 'right'),(side*3.1,0,-.1))
        hull('Survey_pontoon',[(-5.9,.55,-.55,.40),(-4,.85,-.6,.72),(2.6,.72,-.4,.65),(5.8,.24,-.1,.18)],'shell',pod)
        for y in (-2.7,1.1):
            box('Bridge_spar',(side*1.7,y,-.12),(2.8,.62,.43),'metal')
            box('Spar_stripe',(side*1.7,y,.13),(2.6,.16,.06),'orange')
        thruster('survey_engine_'+('left' if side<0 else 'right'),(0,-5.5,0),.59,1.4,pod)
        for y in (-2,0,2):
            box('Experiment_bay',(0,y,.72),(.84,1.12,.24),'navy',pod,.06)
            box('Bay_cover',(0,y,.87),(.66,.97,.055),'shell',pod)
        socket('payload_'+('left' if side<0 else 'right'),(0,0,-.64),pod)
        box('Forward_sensor',(0,4.3,.35),(.26,.30,.14),'cyan',pod)
    obs=pivot('observatory_turntable',(0,-1.4,1.30))
    cylinder('Turntable',(0,0,0),.71,.22,'metal',obs,vertices=24)
    for x in (-.40,.40):box('Sensor_yoke',(x,0,.45),(.12,.17,.85),'shell',obs)
    cylinder('Telescope',(0,.15,.8),.34,1.2,'navy',obs,(0,1,0),20)
    ring('Lens_rim',(0,.76,.8),.36,.065,'shell',obs,(0,1,0))
    cylinder('Sensor_lens',(0,.79,.8),.29,.035,'cyan',obs,(0,1,0),24)
    cycle(obs,2,math.pi*.66)
    socket('sensor',(0,.84,.8),obs)
    for i in range(5):box('Lab_roof_panel',(0,-3.8+i*.4,.86),(1.5,.28,.12),'shell',bevel=.02)
    box('Dorsal_fin',(0,-4.5,1.1),(.16,.70,1.20),'orange',bevel=.035)
    socket('cockpit',(0,2.2,1.34));socket('dock',(0,-5.15,0),rotation=(0,0,math.pi))
    socket('centre_of_mass',(0,-.3,0))


BUILDERS=[welder,winch,beacon,case,rebreather,radio,pistol,lance,marra,hodei]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group()
    group.add_argument('--missing-only',action='store_true')
    group.add_argument('--force',action='store_true')
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    args=parser.parse_args(argv)
    targets=[HERE/(s[0]+'.blend') for s in SPECS]
    if not args.missing_only and not args.force and any(p.exists() for p in targets):
        raise SystemExit('Refusing to overwrite editable .blend sources; use --missing-only or explicit --force.')
    global ROOT_OBJECT
    for spec,builder,path in zip(SPECS,BUILDERS,targets):
        if path.exists() and args.missing_only:
            print('PRESERVED',path.name,flush=True);continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        palette()
        ROOT_OBJECT=None
        ROOT_OBJECT=pivot(spec[0])
        ROOT_OBJECT['asset_id']='itsasargi/'+spec[0]
        ROOT_OBJECT['license']='MIT'
        ROOT_OBJECT['version']=1
        ROOT_OBJECT['units']='metres'
        ROOT_OBJECT['description']=spec[3]
        builder()
        scene=bpy.context.scene
        scene.name='mechanical_cycle';scene.frame_start=1;scene.frame_end=91;scene.render.fps=30
        scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
        scene.frame_set(1)
        bpy.ops.object.select_all(action='DESELECT')
        ROOT_OBJECT.select_set(True);bpy.context.view_layer.objects.active=ROOT_OBJECT
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
        print('CREATED',path.name,flush=True)

if __name__=='__main__':
    main()
