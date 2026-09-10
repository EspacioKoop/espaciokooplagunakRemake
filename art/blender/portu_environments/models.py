"""PORTU: original reusable station destinations, MIT. Blender/bpy 4.5.3.
Saved .blend sources are authoritative and protected. No imported art or textures.
Modes: build (first authoring), export (saved-source export), all. --missing-only
preserves manual edits. One metre; Blender +Z up, +Y forward; Godot +Y up, -Z forward.
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
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
OUT=ROOT/'game/assets/models/portu_environments'
IMAGES=ROOT/'docs/images/portu_environments'
SPECS=[
 ('quarantine_clinic','Osasun · clínica de cuarentena','medical','Camas, descontaminación, sala de observación y dispensarios.'),
 ('hydroponic_garden','Hosto · invernadero hidropónico','botany','Bancales, iluminación de cultivo, depósitos y pasillos de mantenimiento.'),
 ('residential_lounge','Etxe · salón residencial','residential','Sofás, mesas, literas, cocina y espacio social de tripulación.'),
 ('memory_archive','Oroimen · archivo y museo','archive','Vitrinas, piezas originales, estanterías y consulta documental.'),
 ('communications_hub','Lotura · centro de comunicaciones','communications','Puestos de control, matriz de enlaces y nodos de comunicaciones.'),
 ('cargo_lift_dock','Karga · plataforma de carga','logistics','Plataforma de transferencia, guías, carros y racks; sin ascensor de campaña.'),
 ('reactor_service','Bero · servicio del reactor','engineering','Módulos de energía, refrigeración, cuadros y espacios de inspección.'),
 ('repair_drydock','Kaia · dique de reparación','repair','Bastidor de servicio vacío, grúas, brazos y bancos para reparar futuras naves.'),
]
M={}
CURRENT=None


def empty(name,pos=(0,0,0),parent=None):
    o=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(o)
    o.parent=parent;o.location=pos;o.empty_display_type='PLAIN_AXES';o.empty_display_size=.25
    return o


def mat(name,color,metal=.15,rough=.48,emit=0):
    m=bpy.data.materials.new('Portu_'+name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emit
    return m


def palette():
    global M
    M={
      'wall':mat('ceramic',(.48,.57,.60),.3), 'floor':mat('deck',(.040,.066,.087),.55),
      'dark':mat('graphite',(.018,.033,.046),.3), 'metal':mat('titanium',(.20,.27,.29),.75,.3),
      'accent':mat('safety_amber',(.90,.35,.045)), 'cyan':mat('cyan',(.04,.63,.74),.2,.32,1.0),
      'white':mat('warm_light',(.84,.85,.65),.1,.5,.4), 'blue':mat('blue_glass',(.025,.18,.27),.55,.18),
      'cloth':mat('teal_fabric',(.045,.25,.27),.0,.85), 'wood':mat('wood',(.28,.13,.060),.0,.8),
      'green':mat('leaf',(.12,.32,.10),.0,.9), 'leaf':mat('leaf_tip',(.33,.53,.16),.0,.85),
      'soil':mat('soil',(.12,.075,.042),.0,.95), 'violet':mat('violet',(.43,.16,.72),.3,.3,.5),
    }


def finish(o,name,material,parent,bevel=0):
    o.name=name;o.parent=parent;o.data.materials.append(M[material])
    if bevel:
        mod=o.modifiers.new('Editable_bevel','BEVEL');mod.width=bevel;mod.segments=2
    return o


def box(name,p,s,material='wall',parent=None,bevel=.04):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.dimensions=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,material,parent,min(bevel,min(s)*.12))


def cyl(name,p,r,h,material='metal',parent=None,axis=(0,0,1),n=12,r2=None):
    if r2 is None:bpy.ops.mesh.primitive_cylinder_add(vertices=n,radius=r,depth=h,location=p)
    else:bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r,radius2=r2,depth=h,location=p)
    o=bpy.context.object;o.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler()
    return finish(o,name,material,parent,min(.025,r*.07,h*.07))


def beam(name,a,b,r=.08,material='metal',parent=None):
    a,b=Vector(a),Vector(b);return cyl(name,(a+b)/2,r,(b-a).length,material,parent,b-a)


def ring(name,p,r,t=.05,material='cyan',parent=None,axis=(0,0,1)):
    bpy.ops.mesh.primitive_torus_add(major_segments=24,minor_segments=6,major_radius=r,minor_radius=t,location=p)
    o=bpy.context.object;o.rotation_euler=Vector(axis).to_track_quat('Z','Y').to_euler()
    return finish(o,name,material,parent)


def label(text,p,size=.45,parent=None):
    bpy.ops.object.text_add(location=p);o=bpy.context.object;o.data.body=text;o.data.align_x='CENTER'
    o.data.size=size;o.data.extrude=.004;o.rotation_euler=(math.pi/2,0,0)
    bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.object,'Label_'+text,'white',parent)


def socket(name,p,kind,parent,rotation=(0,0,0)):
    o=empty('socket_'+name,p,parent);o.rotation_euler=rotation;o['role']=kind
    return o


def console(parent,p=(0,0,0),name='Console'):
    x,y,z=p
    box(name+'_base',(x,y,z+.48),(1.6,.9,.96),'dark',parent)
    panel=box(name+'_panel',(x,y+.07,z+1.18),(1.7,.10,.85),'metal',parent)
    box(name+'_display',(x,y-.0,z+1.2),(1.38,.035,.57),'blue',parent)
    for i in range(5):box(name+'_readout',(x-.50+i*.25,y-.03,z+1.09+i*.045),(.14,.025,.03),'cyan',parent,.003)
    box(name+'_keypad',(x,y-.45,z+.91),(1.35,.35,.07),'wall',parent)
    for i in range(5):box(name+'_key',(x-.5+i*.25,y-.5,z+.96),(.10,.12,.015),'accent' if i==4 else 'dark',parent,.003)


def chair(parent,p=(0,0,0)):
    x,y,z=p
    cyl('Chair_stem',(x,y,z+.35),.13,.65,parent=parent)
    box('Chair_seat',(x,y,z+.72),(.8,.8,.18),'cloth',parent)
    box('Chair_back',(x,y-.34,z+1.20),(.82,.16,.90),'cloth',parent)
    for s in (-1,1):box('Chair_arm',(x+s*.49,y,z+1),(.12,.7,.14),'metal',parent)


def crate(parent,p=(0,0,0),s=1):
    x,y,z=p;box('Container',(x,y,z+s*.5),(s*1.5,s,s),'wall',parent)
    for d in (-.55,.55):box('Container_band',(x+s*d,y,z+s*.5),(.09,s*1.015,s*1.015),'metal',parent)
    box('Container_latch',(x,y-s*.51,z+s*.55),(.22,.025,.18),'accent',parent)


def shell(root,title):
    structural=empty('structure',parent=root)
    floor=empty('floor_tiles',parent=root)
    front=empty('front_cutaway',parent=root)
    roof=empty('roof_cutaway',parent=root)
    box('Subdeck',(0,0,-.24),(24.8,36,.4),'metal',floor)
    for x in range(-10,12,4):
        for y in range(-14,18,4):box('Floor_tile',(x,y,-.025),(3.975,3.975,.11),'floor',floor,.012)
    # Central four-metre aisle stays free in every environment.
    for x in (-2.15,2.15):box('Aisle_edge',(x,2,.035),(.08,26,.014),'accent',floor,.002)
    for x in (-12.2,12.2):
        box('Side_wall',(x,0,3),(.35,32,6),'wall',structural)
        for y in range(-14,16,4):
            box('Wall_rib',(x*.985,y,3),(.30,.26,6),'metal',structural)
            box('Lower_panel',(x*.975,y,1.05),(.20,3.45,1.65),'dark',structural)
            box('Window',(x*.978,y,3.4),(.15,2.7,1.8),'blue',structural)
            box('Wall_light',(x*.970,y,4.72),(.12,2.75,.09),'cyan',structural)
    for y,group in ((-16,front),(16,structural)):
        for x in (-7.2,7.2):box('End_wall',(x,y,3),(10.2,.35,6),'wall',group)
        box('Portal_lintel',(0,y,4.9),(4.2,.40,2.2),'dark',group)
        for x in (-2.2,2.2):box('Portal_jamb',(x,y,1.8),(.25,.48,3.6),'metal',group)
    for y in (-8,0,8):
        box('Ceiling_beam',(0,y,5.85),(24,.35,.5),'metal',roof)
        for x in (-6,6):box('Ceiling_light',(x,y,5.60),(5,.55,.12),'white',roof)
    box('Roof',(0,0,6.2),(24.4,32,.28),'wall',roof)
    # A real two-leaf sliding door separates the arrival vestibule.
    for x in (-7.2,7.2):box('Vestibule_wall',(x,-10,2.1),(10.2,.3,4.2),'dark',structural)
    box('Door_header',(0,-10,3.9),(4.6,.5,.7),'metal',structural)
    for side,name in ((-1,'left'),(1,'right')):
        pivot=empty('door_'+name,(side*1.05,-10,0),root)
        pivot['mechanism']='slide_x';pivot['open_offset_x']=side*2.12
        box('Door_leaf',(0,0,1.7),(2.05,.19,3.4),'wall',pivot)
        box('Door_window',(0,-.11,2.20),(1.1,.025,.75),'blue',pivot)
        box('Door_safety',(side*.86,-.12,1.65),(.10,.025,3.15),'accent',pivot)
        box('Door_handle',(side*.67,-.18,1.0),(.11,.12,.55),'metal',pivot)
    console(structural,(7,-12,0),'Arrival_terminal')
    label(title.upper(),(0,-10.30,4.45),.48,structural)
    label('PORTU / 01',(0,-16.24,4.45),.45,front)
    for name,p,kind in [('arrival',(0,-14,1.0),'arrival'),('return',(0,-13,.15),'return'),
                        ('door_use',(0,-12,1.1),'door'),('connect_front',(0,-16,0),'connector'),
                        ('connect_back',(0,16,0),'connector')]:
        socket(name,p,kind,root,(0,0,math.pi) if name=='connect_front' else (0,0,0))
    for i,y in enumerate((-7,-2,4,10,14)):
        socket('route_'+str(i),(0,y,.06),'walk_route',root)
    for i,(x,y) in enumerate(((-3,-4),(3,-4),(-3,6),(3,6))):
        socket('npc_'+str(i),(x,y,.06),'future_npc',root)
        socket('resource_'+str(i),(x*2,y,.8),'future_resource',root)
    socket('objective',(0,12,.06),'future_objective',root)
    return empty('furnishings',parent=root)


def clinic(p):
    for x in (-7,7):
        for y in (-4,5):
            box('Bed_pedestal',(x,y,.48),(1.7,3,.96),'metal',p)
            box('Medical_mattress',(x,y,1.04),(1.9,3.4,.20),'wall',p)
            box('Pillow',(x,y+1.15,1.22),(1.45,.65,.17),'cloth',p)
            for dx in (-1.1,1.1):beam('Bed_rail',(x+dx,y-1,1.1),(x+dx,y+1,1.1),.06,parent=p)
            beam('Monitor_arm',(x+1.45,y+.8,0),(x+1.45,y+.8,2.4),.08,parent=p)
            box('Vital_monitor',(x+1.45,y+.8,2.25),(.70,.20,.62),'blue',p)
            for i in range(5):box('Pulse_display',(x+1.2+i*.11,y+.68,2.1+i*.035),(.065,.025,.06),'cyan',p)
        box('Privacy_divider',(x,.2,1.4),(5.1,.15,2.8),'cloth',p)
    for x in (-9,9):
        box('Sanitation_cabinet',(x,12,1.4),(3,1.6,2.8),'wall',p)
        box('Medical_cross_a',(x,11.17,1.7),(1.1,.04,.25),'cyan',p)
        box('Medical_cross_b',(x,11.14,1.7),(.25,.04,1.1),'cyan',p)
    console(p,(5,11,0),'Nurse_station')


def garden(p):
    for x in (-8,-4,4,8):
        for y in (-3,6):
            box('Grow_tray',(x,y,.68),(2.5,6,.55),'wall',p)
            box('Growing_medium',(x,y,.97),(2.15,5.6,.035),'soil',p)
            for j in range(6):
                for dx in (-.55,.55):
                    yy=y-2.4+j*.95
                    cyl('Plant_stem',(x+dx,yy,1.35),.055,.78,'green',p,n=6)
                    for k in range(2):
                        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=.37,location=(x+dx,yy,1.45+k*.30))
                        o=bpy.context.object;o.scale=(1.3,.7,.5);finish(o,'Plant_leaf','leaf' if k else 'green',p)
            for xx in (x-1.25,x+1.25):beam('Grow_frame',(xx,y,0),(xx,y,3.9),.055,parent=p)
            box('Grow_light',(x,y,3.8),(2.55,5.7,.12),'violet',p)
    for x in (-6,6):
        cyl('Nutrient_tank',(x,13,1.5),1,3,'metal',p,n=20)
        for z in (.5,2.5):ring('Tank_band',(x,13,z),1.03,.055,'cyan',p)
    console(p,(10,12,0),'Garden_control')


def lounge(p):
    for x in (-7,7):
        for y in (-3,6):
            box('Sofa_base',(x,y,.4),(3.6,1.3,.8),'dark',p)
            box('Sofa_cushion',(x,y,.91),(3.5,1.2,.24),'cloth',p)
            box('Sofa_back',(x,y+.60,1.35),(3.7,.25,1.2),'cloth',p)
            for dx in (-1.9,1.9):box('Sofa_arm',(x+dx,y,.95),(.28,1.35,.7),'wall',p)
            cyl('Table_stem',(x,y-2,.45),.12,.9,parent=p)
            box('Table_top',(x,y-2,.95),(2.6,1.3,.12),'wood',p)
            for dx in (-.6,.6):cyl('Mug',(x+dx,y-2,1.1),.09,.22,'wall',p)
    for x in (-8,8):
        box('Sleeping_module',(x,12,1.8),(4.4,3.0,3.6),'dark',p)
        for z in (.6,2.3):
            box('Bunk_frame',(x,11.3,z),(4,.65,.22),'metal',p)
            box('Bunk_linen',(x,12,z+.25),(3.8,2.4,.2),'cloth',p)
    console(p,(5,11,0),'Kitchen_appliance')


def archive(p):
    for x in (-9,9):
        for y in (-4,4,11):
            box('Archive_case',(x,y,1.6),(2.6,3.6,3.2),'dark',p)
            for z in (.7,1.5,2.3):
                box('Archive_shelf',(x,y,z),(2.7,3.7,.09),'metal',p)
                for i in range(6):box('Bound_volume',(x,y-1.3+i*.5,z+.38),(2.1,.30,.62),'wood' if i%2 else 'wall',p)
    for x in (-4.5,4.5):
        for y in (-4,5):
            cyl('Display_plinth',(x,y,.65),1.2,1.3,'wall',p,n=8)
            ring('Display_rim',(x,y,1.34),1.08,.045,'cyan',p)
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=.78,location=(x,y,2.2))
            o=bpy.context.object;o.rotation_euler=(.2,.4,.3);finish(o,'Original_geometric_relic','metal' if y<0 else 'accent',p)
    console(p,(4.5,12,0),'Archive_reader')
    console(p,(-4.5,12,0),'Archive_reader')


def communications(p):
    for x in (-7,7):
        for y in (-5,1,7):
            console(p,(x,y,0),'Operator')
            chair(p,(x,y-1.3,0))
            box('Signal_rack',(x+2,y+.3,1.6),(1.1,1.3,3.2),'dark',p)
            for z in range(7):box('Link_slot',(x+2,y-.37,.5+z*.37),(.75,.04,.13),'cyan' if z%2 else 'blue',p)
    box('Link_wall',(0,14.8,3),(18,.35,4.6),'dark',p)
    for x in (-6,0,6):
        box('Command_screen',(x,14.58,3.2),(5.1,.05,2.8),'blue',p)
        for i in range(6):box('Diagram',(x-1.8+i*.65,14.54,2.6+i*.21),(.35,.03,.5),'cyan',p)


def cargo(p):
    for x in (-7,7):
        for y in (-4,5,12):crate(p,(x,y,0),1.8 if y!=5 else 1.35)
        for y in (-5,6):
            box('Rack_pillar',(x-2.4,y,2.2),(.25,.25,4.4),'metal',p)
            box('Rack_pillar',(x+2.4,y,2.2),(.25,.25,4.4),'metal',p)
        box('Rack_lintel',(x,.5,4.3),(5,11.3,.3),'accent',p)
    # Flush usable transfer deck; consumers may animate it after reserving mechanics.
    box('Cargo_transfer_plate',(0,5,.045),(3.8,8,.025),'metal',p)
    for y in (1,9):box('Lift_warning',(0,y,.067),(3.8,.12,.012),'accent',p,.002)
    for x in (-2.7,2.7):
        box('Lift_guide',(x,5,2.5),(.2,.24,5),'metal',p)
        box('Lift_drive',(x,5,4.5),(.65,.65,.80),'dark',p)
    console(p,(4,12,0),'Transfer_control')


def reactor(p):
    for x in (-7,7):
        for y in (-4,6):
            cyl('Reactor_base',(x,y,.35),2,.7,'dark',p,n=20)
            cyl('Core_vessel',(x,y,2.4),1.3,3.9,'blue',p,n=24)
            cyl('Top_cap',(x,y,4.5),1.7,.45,'metal',p,n=20)
            for z in (1,2,3,4):ring('Containment_coil',(x,y,z),1.40,.13,'cyan',p)
            for a in range(4):
                angle=a*math.pi/2
                beam('Core_pillar',(x+math.cos(angle)*1.6,y+math.sin(angle)*1.6,.6),(x+math.cos(angle)*1.6,y+math.sin(angle)*1.6,4.3),.09,'metal',p)
            beam('Coolant_pipe',(x,y,4.8),(x,13,4.8),.18,'accent',p)
    for x in (-8,8):console(p,(x,12,0),'Service_station')
    for x in (-4.5,4.5):
        box('Isolation_fence',(x,1,1.2),(.10,16,2.4),'metal',p)
        box('Fence_window',(x,1,1.2),(.12,15.5,1.9),'blue',p)


def drydock(p):
    for x in (-6.5,6.5):
        box('Crane_rail',(x,3,.16),(.4,22,.30),'metal',p)
        for y in (-5,5,11):
            box('Maintenance_bench',(x*1.5,y,.85),(3.2,2.1,1.7),'wall',p)
            for j in range(4):box('Tool_drawer',(x*1.5,y-1.08,.35+j*.35),(2.7,.03,.23),'dark',p)
        for y in (-4,9):
            box('Crane_upright',(x,y,2.5),(.35,.40,5),'accent',p)
    for y in (-4,9):
        box('Crane_crossbeam',(0,y,5.0),(13.5,.50,.6),'accent',p)
        box('Hoist_trolley',(0,y,4.6),(1.4,.8,.7),'metal',p)
        beam('Hoist_cable',(0,y,4.3),(0,y,3.3),.055,'dark',p)
        ring('Hoist_eye',(0,y,3.1),.23,.065,'metal',p,(0,1,0))
    for x in (-4,4):
        for y in (-1,6):
            cyl('Hull_support',(x,y,.5),.50,1.0,'metal',p)
            box('Support_pad',(x,y,1.07),(1.4,1.4,.2),'dark',p)
    console(p,(8,12,0),'Drydock_control')


BUILDERS=[clinic,garden,lounge,archive,communications,cargo,reactor,drydock]


def build(missing=False,force=False):
    targets=[HERE/(s[0]+'.blend') for s in SPECS]
    if not force and not missing and any(p.exists() for p in targets):raise SystemExit('Refusing to overwrite editable sources. Use --missing-only; --force is destructive.')
    for spec,builder,path in zip(SPECS,BUILDERS,targets):
        if path.exists() and missing:print('PRESERVED',path.name,flush=True);continue
        bpy.ops.wm.read_factory_settings(use_empty=True);palette()
        root=empty(spec[0]);root['asset_id']='portu/'+spec[0];root['version']=1;root['title']=spec[1]
        root['license']='MIT';root['category']=spec[2];root['description']=spec[3]
        furnish=shell(root,spec[1].split(' · ')[1]);builder(furnish)
        bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
        print('PORTU_SOURCE',spec[0],flush=True)


def clean(mesh):
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bad=[f for f in bm.faces if f.calc_area()<1e-10]
    if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free();mesh.update()


def optimise(root):
    groups={}
    for o in list(root.children_recursive):
        if o.type!='MESH':continue
        bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
        for m in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=m.name)
        clean(o.data);groups.setdefault(o.parent,[]).append(o)
    for parent,parts in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in parts:o.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        if len(parts)>1:bpy.ops.object.join()
        parts[0].name=parent.name+'_mesh';clean(parts[0].data)


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def preview(target,ident):
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(target))
    root=bpy.data.objects.get(ident)
    if root is None:raise ValueError('Exported root missing')
    for name in ('roof_cutaway','front_cutaway'):
        group=bpy.data.objects.get(name)
        if group:
            for o in [group,*group.children_recursive]:o.hide_render=True
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=20;scene.cycles.use_denoising=True
    scene.render.threads_mode='FIXED';scene.render.threads=4
    scene.render.resolution_x=1200;scene.render.resolution_y=800;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('Portu_preview_world');scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.075,.11,.14,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
    camdata=bpy.data.cameras.new('Overview_camera');cam=bpy.data.objects.new('Overview_camera',camdata);scene.collection.objects.link(cam)
    cam.location=(29,-38,33);cam.rotation_euler=(Vector((0,1,1.5))-cam.location).to_track_quat('-Z','Y').to_euler()
    camdata.type='ORTHO';camdata.ortho_scale=43;camdata.clip_end=500;scene.camera=cam
    for name,pos,energy,size in [('Key',(0,-8,24),8500,18),('Fill',(-15,0,15),5000,16),('Back',(8,16,12),6500,12)]:
        ld=bpy.data.lights.new(name,'AREA');ld.energy=energy;ld.shape='DISK';ld.size=size
        l=bpy.data.objects.new(name,ld);scene.collection.objects.link(l);l.location=pos
        l.rotation_euler=(Vector((0,0,1))-l.location).to_track_quat('-Z','Y').to_euler()
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(IMAGES/(ident+'.png'))
    bpy.ops.render.render(write_still=True)


def export(render=False):
    OUT.mkdir(parents=True,exist_ok=True);IMAGES.mkdir(parents=True,exist_ok=True);entries=[]
    for ident,title,category,description in SPECS:
        source=HERE/(ident+'.blend');before=digest(source)
        bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
        root=bpy.data.objects.get(ident)
        if root is None or root.get('asset_id')!='portu/'+ident:raise ValueError('Wrong source root')
        optimise(root);bpy.context.view_layer.update()
        sockets=[]
        for o in root.children_recursive:
            if o.name.startswith('socket_'):
                p=o.matrix_world.translation;sockets.append({'name':o.name,'role':o['role'],'position':[round(p.x,5),round(p.z,5),round(-p.y,5)]})
        bpy.ops.object.select_all(action='DESELECT')
        for o in [root,*root.children_recursive]:o.select_set(True)
        bpy.context.view_layer.objects.active=root
        target=OUT/(ident+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,export_extras=True,export_animations=False,export_cameras=False,export_lights=False)
        if before!=digest(source):raise AssertionError('Export modified source')
        raw=target.read_bytes();size,kind=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+size])
        tris=sum(doc['accessors'][p['indices']]['count']//3 for mesh in doc['meshes'] for p in mesh['primitives'])
        entry={'id':'portu/'+ident,'version':1,'title':title,'category':category,'description':description,
            'source':str(source.relative_to(ROOT)),'runtime':str(target.relative_to(ROOT)),
            'scene':'game/asset_lab/portu_environments/instances/'+ident+'.tscn',
            'preview':'docs/images/portu_environments/'+ident+'.png',
            'source_sha256':before,'sha256':digest(target),'bytes':len(raw),'triangles':tris,
            'units':'metres','axes':'+X right / +Y up / -Z forward','footprint_m':[24.8,36.0],'ceiling_m':6,
            'sockets':sockets,'materials':[m['name'] for m in doc['materials']],
            'door':{'left':'door_left','right':'door_right','travel_m':2.12,'opening_m':4.1},
            'license':'MIT','status':'exported; validation state in PR',
            'limits':'Reusable furnished environment, not campaign missions, NPC AI, economy or medical/engineering simulation.'}
        entries.append(entry)
        if render:preview(target,ident)
        directory=ROOT/'game/asset_lab/portu_environments/instances';directory.mkdir(parents=True,exist_ok=True)
        (directory/(ident+'.tscn')).write_text('[gd_scene load_steps=3 format=3]\n\n[ext_resource type="Script" path="res://asset_lab/portu_environments/environment.gd" id="1"]\n[ext_resource type="PackedScene" path="res://assets/models/portu_environments/'+ident+'.glb" id="2"]\n\n[node name="PortuEnvironment" type="Node3D"]\nscript = ExtResource("1")\n\n[node name="Model" parent="." instance=ExtResource("2")]\n',encoding='utf-8')
        print('PORTU_EXPORTED',ident,tris,flush=True)
    (OUT/'manifest.json').write_text(json.dumps({'schema':'espaciokoop-portu-environments','schema_version':1,'pack':'portu','library_issue':52,'assets':entries},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--mode',choices=['build','export','all'],default='all')
    group=parser.add_mutually_exclusive_group();group.add_argument('--missing-only',action='store_true');group.add_argument('--force',action='store_true')
    parser.add_argument('--render',action='store_true')
    a=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.mode in ('build','all'):build(a.missing_only,a.force)
    if a.mode in ('export','all'):export(a.render)

if __name__=='__main__':main()
