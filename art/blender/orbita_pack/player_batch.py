"""Second Orbita batch: ten original, editable player/support assets.

Blender/bpy 4.5.3 + Python 3.11. Reuses the first batch's geometry/export
helpers, never changes its files. Build only creates missing sources unless
--force is explicit; export reads edited .blend files without saving them.
All helper coordinates are Godot metres: +Y up, -Z front.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from mathutils import Vector
import build as H
import export as E

ROOT = H.ROOT
SOURCES = H.HERE / 'player_batch'
MODELS = ROOT / 'game/assets/models/orbita_pack/player_batch'
PREVIEWS = ROOT / 'docs/images/orbita_pack/player_batch'
CATALOG = SOURCES / 'catalog.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prism(root, name, outline, thickness, at=(0, 0, 0), mat='ceramic', bevel=.015):
    """Closed extruded XZ outline; editable polygonal hard-surface part."""
    n = len(outline)
    points = [H.point((x, y, z)) for y in (-thickness / 2, thickness / 2) for x, z in outline]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2*n))]
    faces += [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(points, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    H.finish(ob, name, root, at, mat)
    if bevel:
        mod = ob.modifiers.new('Panel_edge', 'BEVEL')
        mod.width = min(bevel, thickness*.15)
        mod.segments = 2
    return ob


def hull(root, name, sections, mat='ceramic'):
    """Octagonal loft, not a scaled cube. sections: z, half-width, half-height, y."""
    coords = []
    for z, w, h, y in sections:
        for x0, y0 in [(-.65,-1),(.65,-1),(1,-.55),(1,.55),(.65,1),(-.65,1),(-1,.55),(-1,-.55)]:
            coords.append(H.point((x0*w, y+y0*h, z)))
    faces = [tuple(reversed(range(8))), tuple(range(len(coords)-8, len(coords)))]
    for k in range(len(sections)-1):
        for i in range(8):
            j = (i+1) % 8
            faces.append((8*k+i, 8*k+j, 8*(k+1)+j, 8*(k+1)+i))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(coords, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    return H.finish(ob, name, root, (0,0,0), mat)


def slide(ob, delta):
    rest = ob.location.copy()
    movement = H.point(delta)
    for frame, value in [(1,0),(25,1),(49,1),(73,0),(97,0)]:
        ob.location = rest + movement*value
        ob.keyframe_insert(data_path='location', frame=frame)
    ob.location = rest


def hose(root, name, points, radius=.012, mat='graphite'):
    for i, (a,b) in enumerate(zip(points, points[1:])):
        H.rod(root, name+'_section', a, b, radius, mat, vertices=10)
        if i:
            H.sphere(root, name+'_joint', a, (radius,)*3, mat, detail=1)


def handle(root, at=(0,0,0), accent='teal'):
    x,y,z = at
    grip = H.box(root,'Insulated_grip',(x,y-.055,z),(.078,.15,.10),'graphite',.015)
    grip.rotation_euler.x = -.14
    H.box(root,'Grip_heel',(x,y-.14,z+.012),(.09,.045,.12),accent,.009)
    for i in range(4):
        H.box(root,'Grip_rib',(x,y-.11+i*.033,z-.052),(.061,.008,.007),'alloy',.001)
    H.socket(root,'grip',(x,y-.055,z))
    return grip


def panel_lights(root, at, count=3):
    x,y,z = at
    for i in range(count):
        H.box(root,'Status_segment',(x+i*.023,y,z),(.013,.016,.006),'cyan',.001)


def argi(root):
    H.box(root,'Magnetic_foot',(0,.025,0),(.24,.05,.19),'graphite',.012)
    for s in (-1,1):
        H.box(root,'Magnet_rail',(s*.082,.005,0),(.035,.01,.16),'alloy',.003)
        H.rod(root,'Yoke_upright',(s*.13,.05,.025),(s*.13,.24,.025),.014,'amber')
        H.rod(root,'Handle_side',(s*.08,.24,.04),(s*.08,.36,.04),.013,'graphite')
    H.rod(root,'Carry_handle',(-.08,.36,.04),(.08,.36,.04),.016,'graphite')
    head = H.node('Lamp_pitch',root,(0,.235,.025))
    H.box(head,'Lamp_housing',(0,0,0),(.24,.15,.11),'amber',.015)
    H.box(head,'Reflector_frame',(0,0,-.061),(.216,.122,.019),'alloy',.012)
    H.box(head,'Optical_glass',(0,0,-.073),(.193,.105,.012),'glass',.010)
    for x in (-.061,0,.061):
        for y in (-.029,.029):
            H.rod(head,'LED_lens',(x,y,-.078),(x,y,-.087),.021,'cyan',vertices=16)
    for i in range(5):
        H.box(head,'Heat_sink',(0,-.054+i*.027,.064),(.20,.010,.025),'graphite',.002)
    H.cycle(head,'X',.24)
    H.socket(head,'light',(0,0,-.095))
    H.socket(root,'grip',(0,.36,.04))
    H.socket(root,'mount',(0,0,0))
    H.socket(root,'battery',(0,.045,.09))


def lagin(root):
    handle(root, accent='amber')
    H.box(root,'Sampler_body',(0,.063,-.06),(.15,.13,.28),'ceramic',.018)
    H.box(root,'Upper_spine',(0,.141,-.085),(.065,.034,.24),'teal',.008)
    H.rod(root,'Sample_chamber',(0,.069,-.10),(0,.069,-.31),.066,'graphite',vertices=24)
    barrel = H.node('Probe_extension',root,(0,.07,-.28))
    H.rod(barrel,'Probe_sleeve',(0,0,0),(0,0,-.16),.032,'alloy',.024)
    H.ring(barrel,'Contact_lip',(0,0,-.16),.032,.008,'amber')
    H.rod(barrel,'Optical_sample_tip',(0,0,-.162),(0,0,-.177),.016,'cyan')
    slide(barrel,(0,0,-.055))
    H.socket(barrel,'sample_tip',(0,0,-.181))
    vial = H.node('Sample_carousel',root,(.116,.074,-.08))
    for i in range(3):
        a = i*math.tau/3
        x,z = math.cos(a)*.041, math.sin(a)*.041
        H.rod(vial,'Sealed_vial',(x,-.035,z),(x,.061,z),.022,'glass',vertices=12)
        H.rod(vial,'Vial_cap',(x,.060,z),(x,.077,z),.025,'amber',vertices=12)
        H.sphere(vial,'Specimen',(x,.006,z),(.013,.025,.012),'gold',detail=1)
    H.cycle(vial,'Y',.30)
    H.socket(root,'canister',(.116,.09,-.08))
    H.socket(root,'belt',(0,.071,.095))
    panel_lights(root,(-.027,.10,-.205))


def babes(root):
    H.box(root,'Shield_base',(0,.042,0),(.40,.084,.24),'graphite',.020)
    for s in (-1,1):
        H.box(root,'Foot',(s*.17,.02,-.08),(.065,.04,.30),'alloy',.009)
        H.rod(root,'Carry_frame',(s*.09,.09,.07),(s*.09,.40,.07),.015,'amber')
    H.rod(root,'Carry_grip',(-.09,.40,.07),(.09,.40,.07),.016,'graphite')
    H.rod(root,'Field_cell',(0,.075,0),(0,.235,0),.11,'teal',vertices=24)
    H.ring(root,'Cell_collar',(0,.20,0),.111,.015,'alloy',face='top')
    H.sphere(root,'Field_emitter',(0,.285,-.048),(.10,.105,.066),'cyan')
    for s in (-1,1):
        p = H.node('Shield_petal_left' if s<0 else 'Shield_petal_right',root,(s*.115,.215,0))
        outline=[(0,-.08),(s*.105,-.13),(s*.19,-.04),(s*.20,.10),(s*.10,.15),(0,.10)]
        prism(p,'Ceramic_petal',outline,.085,mat='ceramic')
        H.box(p,'Inductor_strip',(s*.10,.052,.035),(.024,.02,.16),'teal',.003)
        H.cycle(p,'Z',s*.25)
    H.socket(root,'grip',(0,.40,.07))
    H.socket(root,'mount',(0,0,0))
    H.socket(root,'field',(0,.285,-.13))
    panel_lights(root,(-.028,.056,-.126))


def oreka(root):
    handle(root, accent='amber')
    H.box(root,'Gravity_controller',(0,.065,-.065),(.145,.135,.25),'teal',.02)
    H.box(root,'Control_top',(0,.143,-.04),(.09,.026,.17),'graphite',.005)
    H.sphere(root,'Suspension_core',(0,.075,-.273),(.045,.045,.045),'cyan')
    H.ring(root,'Core_gimbal',(0,.075,-.245),.091,.012,'alloy')
    for s in (-1,1):
        arm = H.node('Clamp_left' if s<0 else 'Clamp_right',root,(s*.074,.07,-.14))
        outline=[(0,0),(s*.055,-.055),(s*.068,-.19),(s*.022,-.25),(s*-.003,-.225),(s*.025,-.16),(s*.017,-.06)]
        prism(arm,'Gravity_fork',outline,.044,mat='ceramic',bevel=.005)
        H.box(arm,'Fork_inductor',(s*.045,.028,-.13),(.020,.016,.13),'amber',.004)
        H.sphere(arm,'Pole_tip',(s*.01,0,-.23),(.023,.028,.034),'cyan')
        H.cycle(arm,'Y',s*.10)
    H.socket(root,'effect',(0,.075,-.41))
    H.socket(root,'battery',(0,.078,.067))
    H.socket(root,'belt',(-.079,.055,-.015))
    panel_lights(root,(-.027,.16,-.11))


def izpi(root):
    H.box(root,'Optical_bridge',(0,.027,.015),(.19,.068,.10),'teal',.014)
    for s in (-1,1):
        x = s*.081
        H.rod(root,'Optical_tube',(x,.036,.075),(x,.036,-.105),.061,'ceramic',vertices=24)
        H.ring(root,'Eyecup',(x,.036,.094),.043,.012,'graphite')
        H.rod(root,'Rear_lens',(x,.036,.085),(x,.036,.093),.034,'glass',vertices=24)
        objective=H.node('Lens_left' if s<0 else 'Lens_right',root,(x,.036,-.102))
        H.rod(objective,'Focus_sleeve',(0,0,.01),(0,0,-.075),.053,'graphite',vertices=24)
        H.ring(objective,'Focus_ring',(0,0,-.029),.054,.006,'amber')
        H.ring(objective,'Lens_bezel',(0,0,-.078),.057,.007,'alloy')
        H.sphere(objective,'Multispectral_lens',(0,0,-.081),(.049,.049,.015),'glass',detail=3)
        H.rod(objective,'Reticle_sensor',(s*.041,.025,-.082),(s*.041,.025,-.086),.009,'cyan',vertices=12)
        slide(objective,(0,0,-.018))
        H.socket(objective,'optic_left' if s<0 else 'optic_right',(0,0,-.10))
    H.rod(root,'Focus_knob',(-.028,.089,.028),(.028,.089,.028),.025,'graphite')
    H.box(root,'Range_display',(0,.064,-.048),(.067,.022,.038),'glass',.004)
    hose(root,'Hand_strap',[(-.14,.022,.07),(-.15,-.064,.06),(.15,-.064,.06),(.14,.022,.07)],.008)
    H.socket(root,'grip',(0,-.064,.06))
    H.socket(root,'eyes',(0,.036,.11))
    H.socket(root,'belt',(0,-.026,.059))


def arnasa(root):
    H.box(root,'Backplate',(0,.31,.018),(.34,.56,.085),'graphite',.025)
    H.box(root,'Life_support_case',(0,.30,.096),(.29,.40,.12),'ceramic',.022)
    for s in (-1,1):
        x = s*.143
        H.rod(root,'EVA_tank',(x,.16,.18),(x,.46,.18),.077,'teal',vertices=24)
        H.sphere(root,'Tank_dome_top',(x,.46,.18),(.077,.080,.077),'teal')
        H.sphere(root,'Tank_dome_bottom',(x,.16,.18),(.077,.080,.077),'teal')
        for y in (.205,.405):
            H.ring(root,'Tank_restraint',(x,y,.18),.080,.012,'alloy',face='top')
        H.rod(root,'Tank_valve',(x,.54,.18),(x,.575,.18),.025,'amber')
        hose(root,'Shoulder_harness',[(s*.09,.55,-.012),(s*.15,.55,-.10),(s*.18,.35,-.13),(s*.14,.13,-.04)],.019)
    H.box(root,'Filter_module',(0,.19,.233),(.13,.13,.065),'amber',.009)
    fan=H.node('Filter_fan',root,(0,.19,.274))
    H.ring(fan,'Fan_guard',(0,0,0),.046,.007,'alloy')
    for i in range(5):
        a = i*math.tau/5
        H.rod(fan,'Fan_spoke',(0,0,0),(math.cos(a)*.038,math.sin(a)*.038,0),.008,'graphite',vertices=8)
    H.cycle(fan,'Z',.75)
    H.box(root,'Pressure_display',(0,.445,.216),(.095,.068,.025),'glass',.005)
    panel_lights(root,(-.024,.445,.234))
    hose(root,'Breathing_hose',[(.15,.57,.18),(.25,.60,.14),(.28,.46,.02),(.24,.35,-.09)],.018)
    H.sphere(root,'Docked_mask',(.235,.32,-.07),(.065,.075,.042),'graphite')
    H.socket(root,'back',(0,.31,-.031))
    H.socket(root,'hose',(.24,.35,-.12))
    H.socket(root,'supply',(0,.22,.27))
    H.socket(root,'grip',(0,.585,.05))
    H.rod(root,'Grab_handle',(-.07,.585,.05),(.07,.585,.05),.014,'graphite')


def uhina(root):
    handle(root, accent='teal')
    hull(root,'Arc_receiver',[(-.33,.062,.056,.07),(-.17,.099,.085,.07),(.13,.083,.079,.07)],'graphite')
    H.box(root,'Receiver_casing',(0,.13,-.05),(.15,.074,.29),'ceramic',.015)
    H.box(root,'Shoulder_spine',(0,.065,.23),(.065,.058,.25),'alloy',.008)
    H.box(root,'Shoulder_pad',(0,.023,.378),(.11,.16,.055),'graphite',.012)
    H.box(root,'Forward_grip',(0,-.027,-.27),(.064,.135,.08),'graphite',.01)
    for s in (-1,1):
        coil=H.node('Arc_rail_left' if s<0 else 'Arc_rail_right',root,(s*.067,.075,-.30))
        outline=[(0,0),(s*.025,-.08),(s*.045,-.26),(s*.012,-.34),(s*-.013,-.31),(s*.009,-.23),(s*-.012,-.05)]
        prism(coil,'Arc_prong',outline,.047,mat='ceramic',bevel=.006)
        for i in range(5):
            H.box(coil,'Induction_seam',(s*.018,.029,-.045-i*.048),(.031,.012,.014),'cyan',.002)
        H.cycle(coil,'Y',s*.055)
    H.ring(root,'Stabiliser',(0,.075,-.333),.089,.012,'teal')
    H.box(root,'Sight_base',(0,.182,-.015),(.054,.03,.11),'graphite',.005)
    H.box(root,'Sight_window',(0,.214,-.034),(.046,.039,.018),'glass',.003)
    cell=H.node('Power_cell',root,(.079,.07,.037))
    H.box(cell,'Cell',(0,0,0),(.037,.104,.14),'amber',.01)
    slide(cell,(.015,0,0))
    H.socket(root,'muzzle',(0,.075,-.65))
    H.socket(root,'support_grip',(0,-.027,-.27))
    H.socket(root,'stock',(0,.04,.406))
    H.socket(root,'cell',(.111,.07,.037))
    H.socket(root,'sight',(0,.216,-.041))


def ezpal(root):
    handle(root, accent='plum')
    H.box(root,'Disperser_body',(0,.072,-.095),(.158,.15,.255),'plum',.018)
    H.box(root,'Upper_shell',(0,.157,-.095),(.135,.040,.24),'ceramic',.008)
    H.box(root,'Rear_guard',(0,.068,.064),(.17,.14,.038),'graphite',.010)
    head=H.node('Coil_carousel',root,(0,.072,-.217))
    H.rod(head,'Core',(0,0,.01),(0,0,-.16),.076,'graphite',vertices=24)
    for i in range(3):
        a=i*math.tau/3+math.pi/2
        x,y=math.cos(a)*.065,math.sin(a)*.065
        H.rod(head,'Field_channel',(x,y,-.01),(x,y,-.16),.037,'alloy',vertices=16)
        for z in (-.035,-.089,-.143):
            H.ring(head,'Induction_coil',(x,y,z),.036,.006,'gold')
        H.rod(head,'Emitter_face',(x,y,-.166),(x,y,-.174),.025,'cyan',vertices=16)
    H.cycle(head,'Z',.24)
    H.socket(head,'muzzle',(0,0,-.19))
    H.box(root,'Auxiliary_grip',(0,-.044,-.18),(.065,.105,.082),'graphite',.01)
    for s in (-1,1):
        H.box(root,'Side_armour',(s*.087,.085,-.077),(.023,.10,.16),'ceramic',.005)
        for i in range(3):
            H.box(root,'Side_vents',(s*.10,.095,-.12+i*.035),(.009,.055,.013),'graphite',.002)
    panel_lights(root,(-.025,.162,-.22))
    H.socket(root,'support_grip',(0,-.044,-.18))
    H.socket(root,'cell',(0,.072,.09))
    H.socket(root,'sling',(-.11,.11,.015))


def kimu(root):
    hull(root,'Survey_keel',[(-5.2,.24,.23,.1),(-3.0,1.10,.55,.02),(1.45,1.30,.55,.02),(3.5,.70,.36,.12)],'graphite')
    hull(root,'Ceramic_hull',[(-4.3,.31,.28,.24),(-2.0,1.16,.42,.38),(1.8,1.18,.39,.36),(2.7,.70,.27,.30)],'ceramic')
    hull(root,'Cockpit_canopy',[(-3.7,.32,.22,.63),(-2.3,.72,.39,.73),(-1.25,.73,.37,.74),(-.83,.43,.17,.71)],'glass')
    for s in (-1,1):
        wing=[(s*.88,-1.25),(s*3.75,-.13),(s*4.45,2.25),(s*3.10,2.61),(s*1.06,1.34)]
        prism(root,'Swept_sensor_wing',wing,.24,at=(0,.02,0),mat='teal',bevel=.030)
        H.rod(root,'Wing_spar',(s*1.0,-.1,.4),(s*3.3,-.1,1.3),.16,'alloy')
        H.thruster(root,s*2.3,.13,2.60,.52)
        H.box(root,'Radiator_block',(s*.72,.81,1.13),(.52,.12,1.08),'graphite')
        for j in range(5):
            H.box(root,'Radiator_fin',(s*.72,.89,.72+j*.19),(.44,.034,.064),'alloy',.006)
        H.socket(root,'payload_left' if s<0 else 'payload_right',(s*3.40,-.15,.75))
        H.rod(root,'Landing_leg',(s*.84,-.45,-1.0),(s*1.2,-.93,-.88),.07,'alloy')
        H.box(root,'Landing_skid',(s*1.20,-.96,-.6),(.20,.10,1.22),'graphite')
    sensor=H.node('Survey_antenna',root,(0,1.10,.85))
    H.rod(root,'Antenna_mast',(0,.70,.85),(0,1.1,.85),.12,'alloy')
    H.ring(sensor,'Dish_rim',(0,.20,0),.67,.055,'amber')
    for a in range(0,360,60):
        t=math.radians(a)
        H.rod(sensor,'Dish_spoke',(0,.20,-.10),(math.cos(t)*.64,.20+math.sin(t)*.64,0),.026,'alloy',vertices=10)
    H.rod(sensor,'Dish_feed',(0,.20,-.10),(0,.20,-.39),.065,'gold',.028)
    H.sphere(sensor,'Dish_lens',(0,.20,-.4),(.10,.10,.075),'cyan')
    H.cycle(sensor,'Y',.42)
    H.socket(sensor,'survey',(0,.20,-.52))
    H.socket(root,'cockpit',(0,.77,-2.0))
    H.socket(root,'dock',(0,-.45,1.45))
    H.socket(root,'origin',(0,0,0))


def balea(root):
    hull(root,'Rescue_hull',[(-7.4,.55,.57,.10),(-5.1,1.80,.95,.03),(-.5,2.02,1.05,.03),(4.2,1.66,.81,.08),(5.5,1.25,.63,.12)],'ceramic')
    hull(root,'Ventral_keel',[(-5.7,.38,.34,-.72),(-2.5,.86,.49,-.77),(3.2,.73,.33,-.65)],'teal')
    hull(root,'Bridge',[(-6.45,.43,.23,.94),(-4.2,1.07,.37,1.13),(-3.0,.84,.26,1.10)],'graphite')
    hull(root,'Bridge_glass',[(-6.38,.40,.16,1.03),(-4.38,1.02,.26,1.24),(-3.48,.78,.21,1.24)],'glass')
    for s in (-1,1):
        x=s*2.45
        H.box(root,'Pod_sponson',(x,-.03,.53),(1.15,.44,7.15),'graphite',.10)
        for i in range(3):
            z=-2.06+i*2.12
            H.rod(root,'Evacuation_capsule',(x,.09,z-.64),(x,.09,z+.64),.53,'teal',vertices=16)
            H.sphere(root,'Capsule_front',(x,.09,z-.64),(.53,.53,.30),'ceramic')
            H.sphere(root,'Capsule_rear',(x,.09,z+.64),(.53,.53,.30),'ceramic')
            H.ring(root,'Capsule_lock',(x,.09,z-.42),.535,.055,'amber')
            H.box(root,'Capsule_window',(x,.631,z),(.44,.035,.46),'glass',.014)
            H.socket(root,('evac_left_' if s<0 else 'evac_right_')+str(i+1),(x,-.47,z))
        H.thruster(root,s*2.48,.11,4.74,.85)
        H.rod(root,'Engine_pylon',(s*1.21,0,3.34),(s*2.48,0,4.13),.23,'alloy')
        for j in range(5):
            H.box(root,'Dorsal_radiator',(s*.79,1.003,.63+j*.55),(.55,.065,.27),'graphite')
        H.box(root,'Rescue_stripe',(s*1.83,.50,-3.24),(.072,.34,1.05),'amber')
        arm=H.node('Rescue_arm_left' if s<0 else 'Rescue_arm_right',root,(s*1.4,-.60,-4.08))
        H.rod(arm,'Reach_boom',(0,0,0),(s*.65,-.53,-1.50),.11,'alloy')
        H.box(arm,'Soft_capture_clamp',(s*.65,-.57,-1.52),(.40,.18,.45),'amber',.032)
        H.box(arm,'Clamp_pad',(s*.65,-.68,-1.52),(.31,.04,.35),'graphite')
        H.cycle(arm,'Y',s*.10)
        H.socket(arm,'rescue_left' if s<0 else 'rescue_right',(s*.65,-.7,-1.52))
    H.box(root,'Dorsal_hatch',(0,1.14,-1.08),(1.11,.12,1.36),'teal',.04)
    H.ring(root,'Docking_collar',(0,1.24,-1.08),.48,.085,'alloy',face='top')
    H.socket(root,'dock',(0,1.32,-1.08))
    H.socket(root,'cockpit',(0,1.22,-4.60))
    H.socket(root,'cargo',(0,-1.31,-.4))
    H.socket(root,'origin',(0,0,0))


BUILDERS = {
    'argi_worklight':argi, 'lagin_sampler':lagin, 'babes_shield':babes,
    'oreka_gravity_tool':oreka, 'izpi_binoculars':izpi, 'arnasa_eva_pack':arnasa,
    'uhina_arc_emitter':uhina, 'ezpal_coil_dispenser':ezpal,
    'kimu_survey_ship':kimu, 'balea_rescue_ship':balea,
}


def catalogue():
    data = json.loads(CATALOG.read_text(encoding='utf-8'))
    rows = data['assets']
    if len(rows) != 10 or {r['name'] for r in rows} != set(BUILDERS):
        raise ValueError('Player batch catalogue/constructors mismatch')
    if {k:sum(r['category']==k for r in rows) for k in ('tools','weapons','ships')} != {'tools':6,'weapons':2,'ships':2}:
        raise ValueError('Player batch must contain exactly 6 tools, 2 weapons and 2 ships')
    return rows


def build_sources(rows, force=False):
    SOURCES.mkdir(parents=True, exist_ok=True)
    made = 0
    for row in rows:
        path = SOURCES/(row['name']+'.blend')
        if path.exists() and not force:
            continue
        H.reset()
        root = H.node(row['name'])
        root['asset_id'] = 'orbita/'+row['name']
        root['asset_version'] = 1
        root['batch'] = 'player_support_01'
        root['license'] = 'MIT'
        root['provenance'] = 'Original authored geometry; no imported art.'
        root['description'] = row['description']
        root['units'] = 'metres'
        root['front'] = 'Godot -Z'
        BUILDERS[row['name']](root)
        bpy.context.scene.frame_set(1)
        bpy.context.view_layer.update()
        bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
        made += 1
    print(f'ORBITA_PLAYER_SOURCES_PASS created={made} preserved={len(rows)-made}', flush=True)


def overview(rows):
    from PIL import Image, ImageDraw, ImageFont
    width, cell_w, cell_h = 1500, 480, 412
    height = 165 + math.ceil(len(rows)/3)*cell_h
    image = Image.new('RGB',(width,height),'#101c29')
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',22)
        title = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',36)
    except OSError:
        font=title=ImageFont.load_default()
    draw.text((28,23),'ÓRBITA / EQUIPO Y APOYO',font=title,fill='#e4eeed')
    draw.text((30,75),'6 herramientas · 2 armas ficticias · 2 naves / GLB reimportados en Blender',font=font,fill='#88a9b3')
    for i,row in enumerate(rows):
        x,y = 20+(i%3)*493, 120+(i//3)*cell_h
        draw.rounded_rectangle((x,y,x+cell_w,y+394),14,fill='#192b3b')
        preview=Image.open(PREVIEWS/(row['name']+'.png')).convert('RGBA')
        preview.thumbnail((460,322),Image.Resampling.LANCZOS)
        image.paste(preview,(x+(cell_w-preview.width)//2,y+8),preview)
        draw.text((x+17,y+335),row['title'].split(' · ')[0],font=font,fill='#e4eeed')
        draw.text((x+17,y+364),row['name'],font=font,fill='#88a9b3')
    image.save(PREVIEWS/'overview.png')


def export_sources(rows, render=False):
    MODELS.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    entries=[]
    for row in rows:
        ident=row['name']
        source=SOURCES/(ident+'.blend')
        before=digest(source)
        bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
        root=bpy.data.objects.get(ident)
        if root is None or root.get('asset_id') != 'orbita/'+ident:
            raise ValueError('Incorrect source root: '+ident)
        bpy.context.scene.frame_set(1)
        bpy.context.scene.name='mechanical_cycle'
        parts=sum(o.type=='MESH' for o in root.children_recursive)
        E.optimise(root)
        objects=E.descendants(root)
        low,high=E.bounds(objects)
        size=high-low
        bpy.ops.object.select_all(action='DESELECT')
        for ob in objects:
            ob.select_set(True)
        bpy.context.view_layer.objects.active=root
        target=MODELS/(ident+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,
            export_yup=True,export_extras=True,export_animations=True,export_animation_mode='SCENE',
            export_frame_range=True,export_anim_scene_split_object=False,export_cameras=False,
            export_lights=False,export_apply=False,export_copyright='Original Espaciokoop Lagunak art — MIT')
        doc=E.glb_json(target)
        nodes=doc['nodes']
        parents={child:i for i,n in enumerate(nodes) for child in n.get('children',[])}
        def node_path(index):
            path=[nodes[index]['name']]
            while index in parents:
                index=parents[index]
                path.append(nodes[index]['name'])
            return '/'.join(reversed(path))
        sockets=[{'name':n['name'],'path':node_path(i)} for i,n in enumerate(nodes) if n.get('name','').startswith('socket_')]
        names=[s['name'] for s in sockets]
        if len(names)!=len(set(names)) or any(not n.isidentifier() for n in names):
            raise ValueError('Nonportable/duplicate socket: '+ident)
        if not set(row['required_sockets']).issubset(names):
            raise ValueError('Missing contracted socket: '+ident)
        accessors=doc['accessors']
        triangles=sum(accessors[p['indices']]['count']//3 for m in doc['meshes'] for p in m['primitives'])
        animations=[a.get('name','') for a in doc.get('animations',[])]
        if not animations:
            raise ValueError('Missing mechanical animation: '+ident)
        entry=dict(id='orbita/'+ident,name=ident,version=1,batch='player_support_01',title=row['title'],
            category=row['category'],description=row['description'],
            runtime=target.relative_to(ROOT).as_posix(),source=source.relative_to(ROOT).as_posix(),
            resource='res://assets/models/orbita_pack/player_batch/'+ident+'.glb',
            preview='docs/images/orbita_pack/player_batch/'+ident+'.png',
            sha256=digest(target),source_sha256=before,bytes=target.stat().st_size,
            units='metres',axes='Godot +Y up, -Z forward',
            dimensions=[round(size.x,6),round(size.z,6),round(size.y,6)],
            aabb_min=[round(low.x,6),round(low.z,6),round(-high.y,6)],
            aabb_max=[round(high.x,6),round(high.z,6),round(-low.y,6)],
            triangles=triangles,editable_parts=parts,mesh_nodes=sum('mesh' in n for n in nodes),
            materials=[m.get('name','') for m in doc['materials']],sockets=sockets,animations=animations,
            attachment_socket=row['attachment_socket'],attachment_kind=row['attachment_kind'],
            required_sockets=row['required_sockets'],animated_nodes=row['animated_nodes'],
            license='MIT',status='exported_not_gameplay_integrated',rig='rigid_object_hierarchy',
            collision='not_included',lod='not_included',provenance='Original authored geometry; no imported art')
        entries.append(entry)
        if render:
            E.render_exported(ident,target,PREVIEWS/(ident+'.png'))
        if digest(source)!=before:
            raise RuntimeError('Export modified source: '+ident)
        print(f'ORBITA_PLAYER_EXPORTED {ident} triangles={triangles}',flush=True)
    manifest=dict(schema='espaciokoop-asset-pack',version=1,pack='orbita_player_support',issue=52,
        parent_pack='orbita',batch='player_support_01',blender=bpy.app.version_string,assets=entries)
    (MODELS/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if render:
        overview(rows)
    print('ORBITA_PLAYER_EXPORT_PASS assets=10',flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation',choices=('build','export'))
    parser.add_argument('--force',action='store_true',help='Destructively rebuild only this batch, losing manual edits.')
    parser.add_argument('--render',action='store_true',help='Render delivered GLB, not source-only geometry.')
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    args=parser.parse_args(argv)
    rows=catalogue()
    if args.operation=='build':
        build_sources(rows,args.force)
    else:
        if args.force:
            parser.error('--force only applies to source construction')
        export_sources(rows,args.render)


if __name__=='__main__':
    main()
