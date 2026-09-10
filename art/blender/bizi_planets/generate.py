"""Bizi: two original, compact HABITABLE planets. MIT.
One editable .blend per planet contains coherent orbit and surface roots.
All positions are planet-local metres. No external models, private data or textures.
Run with bpy 4.5.3 or Blender. Sources are protected unless --force is explicit.
"""
from __future__ import annotations
import argparse
import json
import math
import random
import sys
from pathlib import Path
import bpy
from mathutils import Vector
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(HERE.parent/'itsasargi_pack'))
import build as art

PLANETS=[('ametz','Ametz · mundo habitable de bosques',120.0,421),('uharte','Uharte · mundo habitable de islas',100.0,987)]
POI_TYPES=['landing','village','observatory','grove','ruins','quarry','greenhouse','relay','wreck','sanctuary','camp','arena','reservoir','arch']
TITLES={
'ametz':['Puerto del Claro','Aldea de las Raíces','Observatorio del Viento','Árbol de los Ecos','Ruinas del Círculo','Cantera de Ámbar','Jardín de Semillas','Torre del Horizonte','Sonda Silenciosa','Santuario del Musgo','Campamento del Sur','Patio de los Guardianes','Depósito del Rocío','Arco de Piedra'],
'uharte':['Puerto de las Mareas','Aldea del Coral','Observatorio de las Islas','Bosque de Palmeras','Ruinas de Sal','Cantera Turquesa','Huerto de la Laguna','Antena del Faro','Náufrago Celeste','Santuario de las Conchas','Campamento del Viajero','Anfiteatro de Basalto','Aljibe del Oasis','Puente de los Dos Vientos']}
ROLES={'landing':['arrival','return','ship_parking'],'village':['dialogue','trade'],'observatory':['survey','mission_clue'],'grove':['biomass','exploration'],'ruins':['archaeology','mission_clue'],'quarry':['minerals','gathering'],'greenhouse':['botany','gathering'],'relay':['repair','communications'],'wreck':['salvage','mission_clue'],'sanctuary':['lore','exploration'],'camp':['rest','mission_start'],'arena':['encounter','cover'],'reservoir':['water','repair'],'arch':['landmark','traversal']}
CURRENT='ametz'
RADIUS=120
CENTRES=[]


def centres():
    result=[]
    golden=math.pi*(3-math.sqrt(5))
    for i in range(14):
        z=1-2*(i+.5)/14
        angle=i*golden
        result.append(Vector((math.sqrt(1-z*z)*math.cos(angle),math.sqrt(1-z*z)*math.sin(angle),z)))
    return result


def terrain_height(n):
    x,y,z=n
    if CURRENT=='ametz':
        value=1.1+2.0*math.sin(3*x+1.2*y)+1.4*math.sin(4*z-2*y)+.55*math.sin(12*x+3*z)
    else:
        value=-1.4+2.2*math.sin(3*x+2*z)*math.cos(3*y-z)+.5*math.sin(10*y+6*x)
    # Flatten broad, connected arrival/POI areas. The same function makes both LODs.
    for i,c in enumerate(CENTRES):
        distance=(n-c).length*RADIUS
        core=15 if i==0 else 10
        outer=core+12
        if distance<outer:
            t=max(0,min(1,(distance-core)/(outer-core)))
            t=t*t*(3-2*t)
            value=value*t+3.4*(1-t)
    return value


def add_palette():
    art.palette()
    colors={
      'soil':((.27,.15,.07) if CURRENT=='ametz' else (.50,.36,.19)),
      'grass':((.15,.34,.13) if CURRENT=='ametz' else (.28,.46,.19)),
      'grass_light':((.27,.47,.18) if CURRENT=='ametz' else (.39,.55,.21)),
      'rock':((.35,.39,.32) if CURRENT=='ametz' else (.21,.29,.31)),
      'sand':(.68,.55,.32),'wood':(.25,.11,.045),
      'leaves':((.10,.29,.12) if CURRENT=='ametz' else (.13,.39,.23)),
      'leaves_light':(.34,.49,.15),'water':(.025,.34,.43),
      'cloth':((.56,.21,.08) if CURRENT=='ametz' else (.26,.50,.63))}
    for name,col in colors.items():
        art.MAT[name]=art.material('B_'+CURRENT+'_'+name,col,.05 if name!='water' else .5,.8 if name!='water' else .22)


def planet_mesh(name, subdivisions, parent, detailed):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions,radius=1)
    sphere=bpy.context.object
    directions=[v.co.normalized() for v in sphere.data.vertices]
    vertices=[tuple(n*(RADIUS+terrain_height(n))) for n in directions]
    faces=[tuple(p.vertices) for p in sphere.data.polygons]
    bpy.data.objects.remove(sphere,do_unlink=True)
    groups={i:[] for i in range(8)} if detailed else {0:[]}
    for f in faces:
        center=sum((directions[i] for i in f),Vector())/3
        group=(int(center.x>=0)*4+int(center.y>=0)*2+int(center.z>=0)) if detailed else 0
        groups[group].append(f)
    for group,group_faces in groups.items():
        used=sorted({i for f in group_faces for i in f});mapping={old:new for new,old in enumerate(used)}
        mesh=bpy.data.meshes.new(name+'_'+str(group))
        mesh.from_pydata([vertices[i] for i in used],[],[tuple(mapping[i] for i in f) for f in group_faces]);mesh.update()
        ob=bpy.data.objects.new(name+'_'+str(group),mesh);bpy.context.scene.collection.objects.link(ob);ob.parent=parent
        ob['keep_separate']=True;ob['surface_collision']=True
        mats=['grass','grass_light','rock','sand','soil']
        for mat in mats:mesh.materials.append(art.MAT[mat])
        for p in mesh.polygons:
            point=p.center if p.center.length else sum((mesh.vertices[v].co for v in p.vertices),Vector())/3
            n=point.normalized();h=terrain_height(n)
            noise=math.sin(n.x*43+n.y*37+n.z*23)
            if h<-0.4:p.material_index=3
            elif h>3.8:p.material_index=2
            elif noise>.52:p.material_index=1
            elif noise<-.91:p.material_index=4
            else:p.material_index=0
            p.use_smooth=False
    # Water is visual only; terrain remains a closed, continuous solid sphere.
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4 if detailed else 3,radius=RADIUS-1.35)
    water=bpy.context.object;art.finish(water,'water_visual','water',parent)
    water['keep_separate']=True;water['no_collision']=True


def radial_pivot(name,normal,height=None,parent=None):
    n=Vector(normal).normalized()
    ob=art.pivot(name,tuple(n*(RADIUS+(terrain_height(n) if height is None else height))),parent)
    ob.rotation_euler=n.to_track_quat('Z','Y').to_euler()
    return ob


def tree(parent,pos=(0,0,0),size=1,palm=False):
    x,y,z=pos
    art.cylinder('Trunk',(x,y,z+size*2.0),size*.32,size*4,'wood',parent,vertices=7,r2=size*.19)
    if palm:
        for i in range(6):
            a=i*math.pi/3
            p=[(x,y),(x+math.cos(a-.2)*size*1.7,y+math.sin(a-.2)*size*1.7),(x+math.cos(a)*size*3.2,y+math.sin(a)*size*3.2),(x+math.cos(a+.2)*size*1.7,y+math.sin(a+.2)*size*1.7)]
            art.plate('Palm_frond',p,z+size*4,size*.07,'leaves' if i%2 else 'leaves_light',parent)
    else:
        for i in range(3):
            art.cylinder('Conifer_crown',(x,y,z+size*(2.1+i*.9)),size*(1.7-i*.35),size*2.0,'leaves' if i%2 else 'leaves_light',parent,vertices=8,r2=size*.08)


def rock(parent,pos=(0,0,0),scale=(1,1,1),name='Boulder',mat='rock'):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=pos)
    ob=bpy.context.object;ob.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return art.finish(ob,name,mat,parent)


def hut(parent,pos=(0,0,0),size=1):
    x,y,z=pos
    art.box('Habitat_foundation',(x,y,z+.22),(4.3*size,3.8*size,.44),'rock',parent,.10)
    art.box('Habitat_wall',(x,y,z+1.6*size),(4*size,3.5*size,2.8*size),'wood' if CURRENT=='ametz' else 'shell',parent,.10)
    art.box('Habitat_door',(x,y+1.77*size,z+1.1*size),(1.05*size,.055,2.1*size),'navy',parent)
    for sx in (-1.25,1.25):
        art.box('Habitat_window',(x+sx*size,y+1.79*size,z+1.8*size),(.65*size,.05,.7*size),'cyan',parent)
    art.cylinder('Habitat_roof',(x,y,z+3.4*size),3.35*size,1.4*size,'cloth',parent,vertices=4,r2=.08)
    art.cylinder('Chimney',(x-1.15*size,y-.8*size,z+3.7*size),.22*size,1.6*size,'metal',parent,vertices=8)


def landing(parent):
    art.cylinder('Landing_pad',(0,0,.22),9.0,.44,'navy',parent,vertices=32)
    art.ring('Landing_outline',(0,0,.47),8.25,.16,'orange',parent)
    for x in (-2.2,2.2):art.box('Landing_H_post',(x,0,.46),(.55,5,.03),'shell',parent)
    art.box('Landing_H_bridge',(0,0,.46),(4.5,.55,.03),'shell',parent)
    for i in range(8):
        a=i*math.pi/4
        art.cylinder('Pad_light',(math.cos(a)*8.2,math.sin(a)*8.2,.68),.18,.35,'cyan',parent,vertices=8)
    hut(parent,(11,1,0),.62)
    art.box('Arrival_ramp',(0,-10,.14),(4,5,.28),'metal',parent)
    art.socket('landing',(0,-11,1.85),parent)
    art.socket('return',(0,-9,.65),parent)
    art.socket('ship_parking',(0,0,.52),parent)


def village(parent):
    for x,y,s in [(-5,1,.88),(4,3,1),(0,-4,.65)]:hut(parent,(x,y,0),s)
    art.cylinder('Village_well',(0,1,.55),1.3,1.1,'rock',parent,vertices=12)
    art.cylinder('Well_water',(0,1,1.11),1.1,.015,'water',parent)
    for x in (-1.25,1.25):art.beam('Well_post',(x,1,1.0),(x,1,3.5),.13,'wood',parent)
    art.beam('Well_crossbar',(-1.4,1,3.5),(1.4,1,3.5),.16,'wood',parent)


def observatory(parent):
    art.cylinder('Tower_base',(0,0,1.8),2.4,3.6,'rock',parent,vertices=12)
    art.cylinder('Observation_deck',(0,0,3.8),3.4,.35,'wood',parent,vertices=16)
    for i in range(12):
        a=i*math.pi/6
        art.beam('Deck_railing_post',(math.cos(a)*3.1,math.sin(a)*3.1,4),(math.cos(a)*3.1,math.sin(a)*3.1,5),.075,'metal',parent)
    art.ring('Deck_railing',(0,0,5),3.1,.06,'metal',parent)
    art.cylinder('Telescope_mount',(0,0,4.6),.40,1.4,'metal',parent)
    art.cylinder('Telescope',(0,.5,5.5),.6,3.3,'shell',parent,(0,1,.18),20)
    art.cylinder('Telescope_lens',(0,2.15,5.8),.51,.04,'cyan',parent,(0,1,.18),20)
    for i in range(16):
        art.box('Exterior_steps',(3.8,-4+i*.42,.12+i*.24),(1.8,.50,.24),'wood',parent)


def grove(parent):
    tree(parent,(0,0,0),2.4,CURRENT=='uharte')
    for i in range(8):
        a=i*math.pi/4
        rock(parent,(math.cos(a)*5,math.sin(a)*5,.4),(1.1,.7,.55),'Root_stone')
    for x in (-4,4):art.box('Rest_bench',(x,0,.55),(1.1,3,.25),'wood',parent)


def ruins(parent):
    for i in range(9):
        a=i*math.tau/9
        h=2.2+(i%3)*1.0
        art.cylinder('Ruined_column',(math.cos(a)*5,math.sin(a)*5,h/2),.55,h,'rock',parent,vertices=6)
        art.box('Column_cap',(math.cos(a)*5,math.sin(a)*5,h+.15),(1.4,1.4,.3),'sand',parent)
    art.cylinder('Inscribed_plinth',(0,0,.45),2.3,.9,'rock',parent,vertices=8)
    art.ring('Relic_ring',(0,0,1),1.7,.09,'cyan',parent)


def quarry(parent):
    for i in range(12):
        a=i*2.39996;r=2+(i%3)*1.6
        rock(parent,(math.cos(a)*r,math.sin(a)*r,.7+(i%2)),(1.1,1.5,1.8),'Quarry_rock')
        art.cylinder('Ore_crystal',(math.cos(a)*r+.3,math.sin(a)*r,.9+(i%2)),.28,1.8,'amber' if CURRENT=='ametz' else 'cyan',parent,vertices=5,r2=.025)
    art.box('Sample_cart',(-5,-3,.9),(1.6,2.4,.35),'wood',parent)
    for x in (-5.8,-4.2):
        for y in (-3.8,-2.2):art.cylinder('Cart_wheel',(x,y,.55),.50,.17,'metal',parent,(1,0,0),12)


def greenhouse(parent):
    for x in (-4,0,4):
        art.box('Garden_bed',(x,0,.28),(2.9,7,.55),'wood',parent)
        art.box('Garden_soil',(x,0,.58),(2.55,6.6,.06),'soil',parent)
        for j in range(6):
            y=-2.6+j
            art.cylinder('Plant_stem',(x,y,1.1),.08,1,'leaves',parent,vertices=6)
            rock(parent,(x,y,1.65),(.45,.45,.35),'Crop','leaves_light')
    for x in (-5.9,5.9):art.beam('Canopy_support',(x,0,0),(x,0,4.0),.12,'wood',parent)
    art.box('Shade_canopy',(0,0,4.1),(12,7.8,.12),'cloth',parent)


def relay(parent):
    art.cylinder('Relay_base',(0,0,.7),2.5,1.4,'navy',parent,vertices=12)
    for z in range(7):
        art.box('Tower_segment',(0,0,1.6+z),(.55,.55,1.1),'metal',parent)
        art.beam('Diagonal_guy',(-2,-2,0),(0,0,7),.07,'metal',parent)
    for z in (4.5,6.4,8):art.beam('Aerial_crossbar',(-2.3,0,z),(2.3,0,z),.075,'orange',parent)
    art.ring('Signal_dish',(0,.4,6.5),1.6,.18,'shell',parent,(0,1,0))
    art.cylinder('Dish_core',(0,.45,6.5),.40,.6,'cyan',parent,(0,1,0))
    art.box('Relay_console',(2,-2,.8),(1.2,1,1.6),'shell',parent)


def wreck(parent):
    art.hull('Wrecked_probe',[(-4,1.5,-.3,.7),(-2,1.7,-.1,1.8),(2,.7,0,.9),(3,.12,0,.3)],'shell',parent)
    art.plate('Broken_wing',[(-1,-1),(-6,-3),(-4,2),(-1,1)],.4,.25,'navy',parent)
    for i in range(6):
        art.box('Wreckage',(4+(i%2)*1.6,-3+i,.25),(.8,1.2,.5),'metal',parent,rot=(.1*i,.2*i,.7*i))
    art.cylinder('Wreck_beacon',(0,0,2),.12,1,'amber',parent)


def sanctuary(parent):
    art.cylinder('Sanctuary_dais',(0,0,.3),4.7,.6,'sand',parent,vertices=16)
    for i in range(5):
        a=i*math.tau/5
        art.cylinder('Standing_stone',(math.cos(a)*3,math.sin(a)*3,2.1),.7,4.2,'rock',parent,vertices=5,r2=.4)
    art.ring('Sacred_hoop',(0,0,3),1.4,.25,'cyan',parent,(0,1,0))
    rock(parent,(0,0,1.3),(1.7,1.2,1.3),'Relic_pedestal')


def camp(parent):
    for x in (-4,4):
        art.cylinder('Expedition_tent',(x,1,1.5),2.6,3,'cloth',parent,vertices=4,r2=.07)
        art.box('Tent_door',(x,2.4,.8),(1,.03,1.5),'navy',parent)
    art.ring('Hearth',(0,0,.16),1.2,.16,'rock',parent)
    for i in range(5):rock(parent,(math.cos(i)*.5,math.sin(i)*.5,.25),(.4,.3,.3),'Hearth_coal','amber')
    for y in (-2.5,2.5):art.cylinder('Log_seat',(0,y,.4),.4,3,'wood',parent,(1,0,0),8)


def arena(parent):
    art.cylinder('Encounter_court',(0,0,.12),8,.24,'sand',parent,vertices=24)
    for x,y,h in [(-4,-3,1.1),(4,2,1.3),(0,4,.8),(-5,3,1.6),(4,-4,.9)]:
        art.box('Encounter_cover',(x,y,h/2),(2.7,1.4,h),'rock',parent,.15)
    for x in (-7,7):
        art.cylinder('Gate_column',(x,-4,2.1),.6,4.2,'rock',parent,vertices=6)
    for i in range(4):art.socket('encounter_'+str(i),((-1 if i%2 else 1)*5,(-1 if i<2 else 1)*4,.6),parent)


def reservoir(parent):
    art.cylinder('Water_cistern',(0,0,.85),4,1.7,'rock',parent,vertices=24)
    art.cylinder('Contained_water',(0,0,1.72),3.6,.025,'water',parent,vertices=32)
    art.ring('Cistern_rim',(0,0,1.7),3.85,.20,'sand',parent)
    art.beam('Water_pipe',(3,0,.5),(7,0,.5),.28,'metal',parent)
    art.cylinder('Pump',(7,0,1.2),.7,2.4,'navy',parent)
    art.ring('Pump_wheel',(7,.8,1.7),.6,.07,'orange',parent,(0,1,0))
    art.box('Service_walkway',(0,-4.5,.32),(9,1.4,.64),'wood',parent)


def arch(parent):
    for x in (-4,4):
        rock(parent,(x,0,2.3),(1.7,2.0,2.7),'Arch_pillar')
    for i in range(7):
        a=math.pi*i/6
        rock(parent,(math.cos(a)*4,0,4+math.sin(a)*3),(1.25,1.55,1.20),'Arch_keystone')
    art.box('Traversable_arch_path',(0,0,.1),(6,7,.20),'sand',parent)


BUILDERS=[landing,village,observatory,grove,ruins,quarry,greenhouse,relay,wreck,sanctuary,camp,arena,reservoir,arch]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group();group.add_argument('--force',action='store_true');group.add_argument('--missing-only',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    paths=[HERE/(p[0]+'.blend') for p in PLANETS]
    if not args.force and not args.missing_only and any(p.exists() for p in paths):raise SystemExit('Editable sources exist; --missing-only preserves them.')
    global CURRENT,RADIUS,CENTRES
    for (ident,title,radius,seed),path in zip(PLANETS,paths):
        if path.exists() and args.missing_only:print('PRESERVED',path);continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        CURRENT=ident;RADIUS=radius;CENTRES=centres();rng=random.Random(seed);add_palette();art.ROOT_OBJECT=None
        surface=art.pivot(ident+'_surface');art.ROOT_OBJECT=surface
        surface['asset_id']='bizi/'+ident;surface['habitable']=True;surface['radius_m']=radius
        surface['sea_level_m']=radius-1.35;surface['license']='MIT';surface['version']=1
        surface['gravity_model']='radial-local';surface['habitability']='Fictional temperate, breathable world; gameplay scale, not astrophysical simulation.'
        planet_mesh('terrain_chunk',6,surface,True)
        catalogue=[]
        for i,(normal,kind,builder) in enumerate(zip(CENTRES,POI_TYPES,BUILDERS)):
            root=radial_pivot('poi_'+kind,normal,parent=surface)
            root['poi_id']=ident+'/'+kind;root['title']=TITLES[ident][i];root['roles']=json.dumps(ROLES[kind])
            builder(root)
            art.socket('poi_'+kind,(0,-8,1.85),root)
            # Two reusable resource meshes/anchors, not automatically campaign inventory.
            for j in range(2):
                marker=art.pivot('resource_'+kind+'_'+str(j),(7+j*1.3,3,.25),root)
                marker['resource_kind']='mineral' if j==0 else 'botanical'
                if j==0:art.cylinder('Resource_crystal',(0,0,.5),.33,1.0,'amber' if CURRENT=='ametz' else 'cyan',marker,vertices=5,r2=.02)
                else:rock(marker,(0,0,.45),(.5,.5,.45),'Resource_bud','leaves_light')
                art.socket('resource_'+kind+'_'+str(j),(0,0,.65),marker)
            catalogue.append({'id':ident+'/'+kind,'node':root.name,'title':TITLES[ident][i],'roles':ROLES[kind],
                'entry_socket':'socket_poi_'+kind,'source_normal':list(normal),'arrival_clearance_m':1.85})
        # Distant foliage avoids POI clear zones and shallow-water pockets.
        for i in range(210):
            n=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-1,1))).normalized()
            if terrain_height(n)<-.15 or min((n-c).length*radius for c in CENTRES)<19:continue
            patch=radial_pivot('flora_'+str(i),n,parent=surface)
            tree(patch,size=rng.uniform(.55,1.1),palm=CURRENT=='uharte')
        for i in range(70):
            n=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-1,1))).normalized()
            if min((n-c).length*radius for c in CENTRES)<19:continue
            patch=radial_pivot('rock_'+str(i),n,parent=surface)
            s=rng.uniform(.4,1.7);rock(patch,(0,0,s*.4),(s,s*.8,s*.65))
        # Separate orbital model: same centre, terrain function and unscaled metres.
        art.ROOT_OBJECT=None
        orbit=art.pivot(ident+'_orbit');art.ROOT_OBJECT=orbit
        orbit['asset_id']='bizi/'+ident;orbit['habitable']=True;orbit['radius_m']=radius
        planet_mesh('orbit_terrain',4,orbit,False)
        for i,n in enumerate(CENTRES):
            marker=radial_pivot('orbital_landmark_'+POI_TYPES[i],n,parent=orbit)
            if i==0:art.cylinder('Distant_landing_pad',(0,0,.24),9,.48,'navy',marker,vertices=16)
            elif POI_TYPES[i] in ('relay','observatory','arch'):
                art.cylinder('Distant_landmark',(0,0,3),1.2,6,'shell',marker,vertices=6)
            else:art.cylinder('Distant_settlement',(0,0,.9),3,1.8,'wood' if ident=='ametz' else 'shell',marker,vertices=6,r2=1)
        bpy.context.scene['planet_catalogue']=json.dumps({'id':ident,'title':title,'habitable':True,'radius_m':radius,'pois':catalogue},ensure_ascii=False)
        bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
        bpy.context.scene.frame_set(1)
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
        print('CREATED HABITABLE',ident,'radius',radius,'POIs',len(catalogue),flush=True)

if __name__=='__main__':main()
