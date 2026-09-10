"""Aterpe: original habitable worlds, not decorative astronomical spheres.
MIT. Closed cube-sphere terrain, matched chunk borders, radial POI frames.
The .blend is the editable source of truth; existing edits are never overwritten
without --force. The Lantegi authoring helpers are a source-code dependency only.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import math
import random
import sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location('lantegi_primitives', ROOT / 'art/blender/lantegi_pack/build.py')
K = importlib.util.module_from_spec(spec)
spec.loader.exec_module(K)

PLANETS = [
    {'slug': 'kare', 'title': 'Kare · praderas calizas', 'radius': 120.0, 'seed': 7843,
     'biome': 'Praderas habitables, caliza, cultivos y astronomía', 'longitude_offset': 0.0},
    {'slug': 'suharri', 'title': 'Suharri · estepa basáltica', 'radius': 150.0, 'seed': 19631,
     'biome': 'Estepa habitable de basalto, líquenes y colonias geotérmicas', 'longitude_offset': 29.0},
]
# Latitude/longitude in degrees; +Y is forward in Blender, +Z is north.
SITES = [(60, 0), (35, 55), (20, 115), (-15, 160), (-45, -150), (-10, -100),
         (35, -60), (-55, -20), (0, 0), (0, 70), (-35, 65), (55, 155),
         (80, -95), (-80, 85), (15, -155), (-15, -35)]
CATALOG = {
    'kare': [
        ('puerto', 'Espigón Celeste', 'port', 'landing'),
        ('observatorio', 'Observatorio de las Mareas', 'observatory', 'science'),
        ('huertos', 'Huertos de las Terrazas', 'farm', 'resource'),
        ('cantera', 'Cantera Blanca', 'quarry', 'resource'),
        ('archivo', 'Archivo Solar', 'archive', 'mission'),
        ('arcos', 'Puente de los Dos Arcos', 'bridge', 'landmark'),
        ('refugio', 'Refugio de Caminantes', 'camp', 'settlement'),
        ('antena', 'Antena Boreal', 'relay', 'science'),
        ('invernadero', 'Invernadero Circular', 'greenhouse', 'resource'),
        ('molinos', 'Plaza de los Molinos', 'village', 'settlement'),
        ('jardin', 'Jardín Mineral', 'crystals', 'resource'),
        ('acueducto', 'Acueducto del Cielo', 'reservoir', 'landmark'),
        ('mirador', 'Mirador del Anillo', 'tower', 'landmark'),
        ('pista', 'Pista de la Última Luz', 'port_small', 'landing'),
        ('columnas', 'Ruinas de las Columnas', 'ruins', 'encounter'),
        ('estacion', 'Estación del Horizonte', 'lab', 'mission'),
    ],
    'suharri': [
        ('puerto', 'Puerto de Carbón', 'port', 'landing'),
        ('central', 'Central de las Chimeneas', 'geothermal', 'mission'),
        ('fundicion', 'Fundición Silenciosa', 'foundry', 'encounter'),
        ('liquenes', 'Jardín de Líquenes', 'fungal', 'resource'),
        ('antenas', 'Campo de Antenas', 'relay', 'science'),
        ('filon', 'Filón de los Cristales', 'quarry', 'resource'),
        ('anfiteatro', 'Anfiteatro de Basalto', 'arena', 'encounter'),
        ('deposito', 'Depósito Presurizado', 'reservoir', 'resource'),
        ('taller', 'Taller de los Colonos', 'lab', 'settlement'),
        ('pasarela', 'Pasarela de la Caldera', 'bridge', 'landmark'),
        ('observatorio', 'Observatorio de Ceniza', 'observatory', 'science'),
        ('memoria', 'Monumento de la Memoria', 'ruins', 'mission'),
        ('campamento', 'Campamento de los Mineros', 'village', 'settlement'),
        ('faro', 'Faro Meridional', 'tower', 'landmark'),
        ('hangar', 'Hangar del Horizonte', 'port_small', 'landing'),
        ('archivo', 'Archivo de la Expedición', 'archive', 'mission'),
    ],
}


def direction(lat, lon):
    a, b = math.radians(lat), math.radians(lon)
    return np.array([math.cos(a) * math.sin(b), math.cos(a) * math.cos(b), math.sin(a)])


def base_height(n, world):
    x, y, z = n[:, 0], n[:, 1], n[:, 2]
    if world['slug'] == 'kare':
        return 2.6 * np.sin(4*x + 2*y) + 1.8 * np.sin(3*z - 2*x) + 1.2 * np.cos(5*y + 2*z)
    field = np.sin(3*x - 2*y) + .55 * np.sin(4*z + y)
    return 3.2 * np.tanh(1.3 * field) + 2.2 * np.sin(4*y - z) + 1.0 * np.cos(6*x + z)


def prepare(world):
    world = dict(world)
    sites = []
    for i, (lat, lon) in enumerate(SITES):
        lon += world['longitude_offset']
        if world['slug'] == 'suharri':
            lat = -lat
        n = direction(lat, lon)
        ident, title, kind, role = CATALOG[world['slug']][i]
        level = float(base_height(n.reshape(1, 3), world)[0]) + .12
        sites.append({'index': i, 'slug': ident, 'title': title, 'kind': kind, 'role': role,
                      'latitude': lat, 'longitude': ((lon + 180) % 360) - 180,
                      'direction': n.tolist(), 'level': level})
    world['sites'] = sites
    vectors = np.array([s['direction'] for s in sites])
    distances = np.arccos(np.clip(vectors @ vectors.T, -1, 1)) * world['radius']
    np.fill_diagonal(distances, np.inf)
    if distances.min() < 37:
        raise ValueError('POI flattening regions overlap')
    return world


def height(n, world):
    n = np.asarray(n, dtype=float)
    n = n / np.linalg.norm(n, axis=1)[:, None]
    result = base_height(n, world)
    radius = world['radius']
    for site in world['sites']:
        dot = np.clip(n @ np.array(site['direction']), -1, 1)
        distance = np.arccos(dot) * radius
        t = np.clip((distance - 11.5) / 6.5, 0, 1)
        weight = 1 - t*t*(3 - 2*t)
        # Flat tangent landing/POI plane, with a smooth transition to spherical terrain.
        plane = (radius + site['level']) / np.maximum(dot, .1) - radius
        result = result * (1 - weight) + plane * weight
    return result


def positions(n, world):
    n = np.asarray(n, dtype=float)
    n = n / np.linalg.norm(n, axis=1)[:, None]
    return n * (world['radius'] + height(n, world))[:, None]


def surface_normals(n, world):
    eps = 0.00005
    grad = np.zeros_like(n)
    for axis in range(3):
        off = np.zeros(3); off[axis] = eps
        grad[:, axis] = (height(n + off, world) - height(n - off, world)) / (2 * eps)
    grad -= n * np.sum(grad * n, axis=1)[:, None]
    normal = n - grad / (world['radius'] + height(n, world))[:, None]
    return normal / np.linalg.norm(normal, axis=1)[:, None]


def mesh_object(name, vertices, faces, parent, materials, indices=None):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    for mat in materials:
        mesh.materials.append(K.M[mat])
    if indices is not None:
        for polygon, index in zip(mesh.polygons, indices):
            polygon.material_index = int(index)
    return ob


def cube_face(face, u, v):
    return [(1,u,v), (-1,u,v), (u,1,v), (u,-1,v), (u,v,1), (u,v,-1)][face]


def terrain(root, world):
    terrain_root = K.empty('Terrain', root)
    terrain_root['layer'] = 'terrain'
    nside = 16
    for face in range(6):
        for cy in range(4):
            for cx in range(4):
                u0, v0 = -1 + cx * .5, -1 + cy * .5
                directions = np.array([cube_face(face, u0 + .5*x/nside, v0 + .5*y/nside)
                                       for y in range(nside+1) for x in range(nside+1)], dtype=float)
                directions /= np.linalg.norm(directions, axis=1)[:, None]
                verts = positions(directions, world)
                faces = []
                for y in range(nside):
                    for x in range(nside):
                        a = y*(nside+1)+x; b = a+1; c = a+nside+1; d = c+1
                        for tri in ((a,b,d),(a,d,c)):
                            p = verts[list(tri)]
                            if np.dot(np.cross(p[1]-p[0], p[2]-p[0]), p.mean(axis=0)) < 0:
                                tri = tuple(reversed(tri))
                            faces.append(tri)
                centres = np.array([directions[list(tri)].mean(axis=0) for tri in faces])
                heights = height(centres, world)
                climate = centres[:,2]*.6 + np.sin(centres[:,0]*8 + centres[:,1]*3)*.3
                palette = np.where(heights > 3.4, 2, np.where(climate > .3, 1, np.where(heights < -2.4, 3, 0)))
                group = K.empty(f'chunk_{face}_{cx}_{cy}', terrain_root)
                group['terrain_chunk'] = True
                group['solid'] = True
                group['face'] = face
                group['grid'] = [cx,cy]
                group['centre_direction'] = directions.mean(axis=0).tolist()
                ob = mesh_object(group.name+'_terrain', verts.tolist(), faces, group,
                                 ['ground0','ground1','ground2','ground3'], palette)
                for p in ob.data.polygons:
                    p.use_smooth = True
                ob.data.normals_split_custom_set_from_vertices(surface_normals(directions, world).tolist())
    return terrain_root


def frame(name, parent, direction_value, position):
    ob = K.empty(name, parent, position)
    ob.rotation_euler = Vector(direction_value).to_track_quat('Z','Y').to_euler()
    return ob


def rock(parent, pos, size, mat='stone', seed=0):
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1)
    ob = bpy.context.object
    for v in ob.data.vertices:
        v.co *= rng.uniform(.82,1.18)
    ob.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return K.finish(ob, 'Carved_rock', pos, mat, parent)


def plant(parent, pos, size, warm=False):
    group = K.empty('Plant', parent, pos)
    K.cylinder('Trunk', (0,0,size*.48), size*.065, size*.96, 'bark', group, sides=8, bevel=0)
    if warm:
        K.taper('Umbrella_crown', (0,0,size), size*.64, size*.12, size*.19, 'leaf2', group, sides=10)
        K.ring('Crown_rim', (0,0,size*.92), size*.51, size*.033, 'leaf', group)
        for x in (-.4,.4):
            K.beam('Fungal_arm', (0,0,size*.51), (x*size,0,size*.8), size*.065, 'bark', group)
    else:
        for x,y,z,s in [(-.3,0,.84,.39),(.28,.12,.9,.4),(0,-.15,1.15,.47)]:
            K.beam('Branch', (0,0,size*.43), (x*size,y*size,z*size), size*.065, 'bark', group)
            rock(group,(x*size,y*size,z*size),(size*s,size*s*.9,size*s*.72),'leaf' if x<.1 else 'leaf2',int(size*100+x*10))
    return group


def stairs(parent, pos=(0,-5,0), width=3, count=5, depth=.6, step=.22, mat='stone'):
    x,y,z = pos
    for i in range(count):
        K.box('Stair', (x,y+i*depth,z+(i+1)*step/2), (width,depth+.02,(i+1)*step), mat,parent,.02)


def bollard(parent, x, y, height_value=1.2):
    K.cylinder('Beacon_base',(x,y,.08),.3,.16,'dark',parent,sides=12)
    K.cylinder('Beacon_mast',(x,y,height_value/2),.095,height_value,'steel',parent,sides=12)
    K.cylinder('Beacon_light',(x,y,height_value),.14,.3,'amber',parent,sides=12)


def cargo(parent, pos, size=1.0):
    x,y,z=pos
    K.box('Cargo_crate',(x,y,z+.6*size),(1.1*size,1.1*size,1.2*size),'teal',parent,.08)
    for xx in (-.4,.4):
        K.box('Crate_band',(x+xx*size,y,z+.6*size),(.1*size,1.14*size,1.24*size),'steel',parent,.018)
    K.box('Crate_lock',(x,y-.57*size,z+.7*size),(.24*size,.04*size,.2*size),'orange',parent,.02)


def shelter(parent, pos=(0,1,0), width=4.2, length=3.8):
    x,y,z=pos
    # Open-front shelter, not an inaccessible solid placeholder house.
    K.box('Shelter_floor',(x,y,z+.12),(width,length,.24),'stone',parent,.025)
    for xx in (-width/2+.1,width/2-.1):
        for yy in (-length/2+.1,length/2-.1):
            K.cylinder('Shelter_column',(x+xx,y+yy,z+1.7),.13,3.2,'steel',parent,sides=12)
    K.box('Rear_panel',(x,y+length/2,z+1.35),(width,.15,2.55),'white',parent,.04)
    K.box('Roof',(x,y,z+3.36),(width+.4,length+.4,.22),'teal',parent,.065)
    K.box('Roof_stripe',(x,y,z+3.49),(.3,length+.39,.04),'orange',parent,.01)


def arch(parent, x, y, radius=3.1):
    for xx in (-radius,radius):
        K.box('Arch_pier',(x+xx,y,1.8),(.85,1.3,3.6),'stone',parent,.07)
    for i in range(9):
        a=(i+.5)*math.pi/9
        ob=K.box('Arch_voussoir',(x+radius*math.cos(a),y,3.5+radius*math.sin(a)),
                 (radius*.37,1.3,.78),'stone',parent,.04)
        ob.rotation_euler.y=math.pi/2-a
    K.box('Arch_keystone',(x,y,3.5+radius+.15),(.9,1.5,1),'white',parent,.06)


def dish(parent, pos=(0,1,4), radius=2.2):
    group=K.empty('Telescope_dish',parent,pos)
    group.rotation_euler.x=math.radians(33)
    verts=[(0,0,0)]
    for ring in range(1,9):
        rr=radius*ring/8
        for i in range(32):
            a=i*math.tau/32
            verts.append((rr*math.cos(a),rr*math.sin(a),.22*(rr*rr)))
    faces=[]
    for i in range(32): faces.append((0,1+i,1+(i+1)%32))
    for ring in range(7):
        a=1+ring*32;b=a+32
        for i in range(32): faces.append((a+i,b+i,b+(i+1)%32,a+(i+1)%32))
    ob=mesh_object('Reflector_bowl',verts,faces,group,['white'])
    solid=ob.modifiers.new('Reflector_thickness','SOLIDIFY');solid.thickness=.07
    K.ring('Dish_rim',(0,0,.22*radius*radius),radius,.06,'steel',group)
    for i in range(3):
        a=i*math.tau/3
        K.beam('Receiver_strut',(radius*math.cos(a),radius*math.sin(a),.22*radius*radius),
               (0,0,radius*.8),.045,'steel',group)
    K.cylinder('Receiver',(0,0,radius*.8),.17,.28,'cyan',group,sides=16)


def windmill(parent, pos, scale=1):
    x,y,z=pos
    K.taper('Wind_tower',(x,y,z+3.3*scale),.3*scale,.17*scale,6.6*scale,'white',parent,sides=12)
    hub=K.empty('Wind_rotor',parent,(x,y-.25*scale,z+6.1*scale))
    K.cylinder('Wind_hub',(0,0,0),.23*scale,.48*scale,'teal',hub,(0,1,0),16)
    for i in range(3):
        a=i*math.tau/3
        K.beam('Wind_blade',(.28*scale*math.sin(a),0,.28*scale*math.cos(a)),
               (2.15*scale*math.sin(a),0,2.15*scale*math.cos(a)),.2*scale,'shell',hub,True)


def poi_geometry(root, site, world):
    d=np.array(site['direction']); radius=world['radius']
    poi=frame('poi_'+site['slug'],root,d,(d*(radius+site['level'])).tolist())
    poi['poi_id']='aterpe/'+world['slug']+'/'+site['slug']
    poi['title']=site['title'];poi['kind']=site['kind'];poi['role']=site['role'];poi['solid']=True
    warm=world['slug']=='suharri'
    kind=site['kind']
    # Exterior arrival ring. Centres stay distinct; navigation paths terminate here.
    K.ring('Wayfinding_ring',(0,0,.05),9.4,.055,'trail',poi)
    for x in (-2,2): bollard(poi,x,-8.0,.85)
    if kind in ('port','port_small'):
        size=6 if kind=='port' else 4.7
        K.cylinder('Landing_deck',(0,0,.16),size,.32,'dark',poi,sides=48,bevel=.025)
        K.ring('Landing_circle',(0,0,.34),size-.4,.09,'orange',poi)
        K.box('Landing_alignment',(0,0,.345),(.19,size*1.1,.02),'white',poi,.003)
        for a in (0,120,240):
            a=math.radians(a)
            bollard(poi,(size+.3)*math.cos(a),(size+.3)*math.sin(a),.65)
        for x in (-1.3,1.3): cargo(poi,(x,6.6,0),.75)
        K.box('Service_console',(6.8,1,.6),(1,.8,1.2),'shell',poi,.08)
        K.screen(poi,(6.8,1,1.23),.65,.48)
        K.socket('landing_'+site['slug'],poi,(0,0,.36))
    elif kind=='observatory':
        K.cylinder('Observatory_plinth',(0,1,.4),4,.8,'stone',poi,sides=32,bevel=.06)
        stairs(poi,(0,-4,0),3,4,.6,.2)
        K.taper('Telescope_pedestal',(0,1,2.0),1.35,.5,2.8,'teal',poi,sides=16)
        dish(poi,(0,1,3.7),2.8)
        cargo(poi,(-4.9,2,0),.8)
        K.box('Terminal',(4.4,0,.65),(.9,.7,1.3),'shell',poi,.07)
        K.screen(poi,(4.4,0,1.32),.6,.45)
    elif kind in ('farm','greenhouse'):
        for y in (-2.6,0,2.6):
            for x in (-3,1.9):
                K.box('Raised_bed',(x,y,.28),(3.7,1.55,.55),'stone',poi,.05)
                K.box('Cultivation_soil',(x,y,.57),(3.4,1.3,.04),'bark',poi,.01)
                for j in range(5):
                    plant(poi,(x-1.3+j*.64,y,.6),.72,warm)
        if kind=='greenhouse':
            for x in (-5.4,5.4):
                for y in (-3.7,0,3.7):
                    K.cylinder('Pergola_column',(x,y,2.15),.12,4.3,'white',poi,sides=12)
            for y in (-3.7,0,3.7):
                K.beam('Pergola_span',(-5.4,y,4.3),(5.4,y,4.3),.17,'teal',poi,True)
            for x in (-4,-2,0,2,4):
                K.box('Sunshade',(x,0,4.4),(1.6,7.7,.06),'glass',poi,.02)
        else:
            windmill(poi,(5.2,3,0),.72)
            K.cylinder('Water_butt',(4.8,-2,.9),.7,1.8,'teal',poi,sides=20)
    elif kind=='quarry':
        for i in range(7):
            a=i*math.tau/7
            rock(poi,(4.7*math.cos(a),2+3.2*math.sin(a),1.4),(1.7,1.3,2.5),'stone',i+world['seed'])
        for x in (-.75,.75): K.beam('Mine_rail',(x,-5.5,.12),(x,3.5,.12),.1,'steel',poi,True)
        for y in np.arange(-5.5,3.6,.7): K.box('Rail_tie',(0,float(y),.05),(2.15,.16,.1),'bark',poi,.01)
        cargo(poi,(0,1,.13),1.1)
        K.beam('Crane_mast',(-4,-1,0),(-4,-1,5.8),.3,'orange',poi,True)
        K.beam('Crane_jib',(-4,-1,5.8),(1,-1,5.8),.24,'orange',poi,True)
        K.beam('Crane_cable',(1,-1,5.8),(1,-1,2.6),.035,'steel',poi)
        K.ring('Crane_hook',(1,-1,2.5),.2,.045,'steel',poi,(1,0,0))
    elif kind in ('archive','ruins'):
        for x in (-3.7,3.7):
            for y in (-1.8,1.5,4.8):
                h=4.4 if kind=='archive' else 2.4+(y+2)*.31
                K.cylinder('Column_base',(x,y,.2),.64,.4,'stone',poi,sides=12)
                K.cylinder('Archive_column',(x,y,h/2),.42,h,'stone',poi,sides=12)
                K.box('Column_cap',(x,y,h),(.95,.95,.3),'white',poi,.04)
            if kind=='archive': K.box('Archive_lintel',(x,1.5,4.72),(1,8.5,.32),'stone',poi,.04)
        K.cylinder('Memory_plinth',(0,2,.6),1.6,1.2,'teal',poi,sides=12)
        K.ring('Memory_orbit',(0,2,2.4),1.4,.16,'steel',poi,(0,1,0))
        rock(poi,(0,2,2.4),(.65,.65,1.1),'cyan',world['seed'])
        for i in range(4): rock(poi,(-5+i*3,5.8,.4),(.8,.6,.7),'stone',i)
    elif kind=='bridge':
        arch(poi,0,2,3)
        arch(poi,0,-2,3)
        K.box('Raised_crossing',(0,0,.55),(3,8.7,.5),'stone',poi,.05)
        stairs(poi,(0,-6.8,0),3,4,.6,.2)
        stairs(poi,(0,6.8,0),3,4,-.6,.2)
        for x in (-1.58,1.58):
            K.beam('Crossing_rail',(x,-4,1.75),(x,4,1.75),.12,'steel',poi)
            for y in (-3.8,-1.9,0,1.9,3.8): K.beam('Rail_post',(x,y,.7),(x,y,1.75),.11,'steel',poi)
    elif kind=='camp':
        shelter(poi,(0,2.5,0),5.2,4.1)
        for x in (-3.5,3.5): K.box('Bench',(x,-2,.5),(1.1,2.5,1),'bark',poi,.08)
        K.cylinder('Fire_basin',(0,-2,.17),.9,.34,'stone',poi,sides=16)
        for i in range(5):
            a=i*math.tau/5
            K.beam('Camp_log',(.6*math.cos(a),-2+.6*math.sin(a),.3),(0,-2,.48),.15,'bark',poi)
        cargo(poi,(-4,3,0),.9)
    elif kind=='relay':
        for x,y,h in [(-3,1,7.0),(3,2.7,5.4),(0,-2,3.7)]:
            for xx in (-.55,.55):
                K.beam('Relay_leg',(x+xx,y,.1),(x,y,h),.13,'steel',poi)
            for z in (1.7,3.3,4.8):
                if z<h: K.beam('Antenna_bar',(x-1.4,y,z),(x+1.4,y,z),.065,'copper',poi)
            K.cylinder('Relay_light',(x,y,h+.15),.19,.35,'cyan',poi,sides=12)
        shelter(poi,(0,5.8,0),3.8,2.0)
        cargo(poi,(0,5.8,.25),.6)
    elif kind=='village':
        for x,y in [(-4,2.8),(3.8,3),(0,-2.5)]:
            shelter(poi,(x,y,0),3.2,2.6)
            cargo(poi,(x+1,y,0),.45)
        windmill(poi,(-5,-3,0),.7)
        windmill(poi,(5,-2,0),.8)
    elif kind in ('crystals','fungal'):
        for i in range(11):
            a=i*2.399963;rr=1.3+math.sqrt(i)*1.25
            x,y=rr*math.cos(a),rr*math.sin(a)
            if kind=='fungal': plant(poi,(x,y,0),2+(i%4)*.7,True)
            else:
                K.taper('Mineral_prism',(x,y,1.2+(i%3)*.4),.7,.08,2.4+(i%3)*.8,
                        'mineral' if i%2 else 'stone',poi,sides=6)
        K.cylinder('Sample_table',(0,-5.4,.63),.85,1.26,'teal',poi,sides=12)
    elif kind=='reservoir':
        for x in (-3,3):
            K.cylinder('Storage_tank',(x,2,2.0),1.8,4,'teal',poi,sides=32,bevel=.06)
            for z in (.45,3.3): K.ring('Tank_hoop',(x,2,z),1.83,.11,'steel',poi)
            K.taper('Tank_roof',(x,2,4.25),1.85,.7,.5,'shell',poi)
            K.hose('Transfer_pipe',[(x,1.2,.45),(x,-2,.45),(0,-2,.45)],.16,'copper',poi)
        K.box('Pump_station',(0,-2,.65),(1.8,1.2,1.3),'orange',poi,.09)
        for y in (0,2.6,5.2):
            for x in (-.8,.8): K.cylinder('Service_support',(x,y,2.0),.12,4,'steel',poi,sides=12)
        K.box('Service_walkway',(0,2.6,4.05),(1.9,6.4,.18),'dark',poi,.02)
    elif kind=='tower':
        K.cylinder('Tower_base',(0,1,.23),3.3,.46,'stone',poi,sides=16)
        K.taper('Lookout_tower',(0,1,3.4),1.6,.95,6.3,'white',poi,sides=8)
        K.cylinder('Lookout_deck',(0,1,6.6),2.6,.32,'teal',poi,sides=20)
        for i in range(10):
            a=i*math.tau/10
            K.cylinder('Deck_rail',(2.35*math.cos(a),1+2.35*math.sin(a),7.2),.055,1,'steel',poi,sides=8)
        K.ring('Circular_rail',(0,1,7.7),2.35,.07,'steel',poi)
        K.cylinder('Lighthouse_lens',(0,1,7.3),.5,1,'amber',poi,sides=20)
        K.taper('Lighthouse_cap',(0,1,8.1),1.1,.15,.65,'teal',poi,sides=12)
        for i in range(15):
            a=i*.33
            box=K.box('Spiral_stair',(2*math.cos(a),1+2*math.sin(a),.2+i*.35),(1.35,.85,.22),'stone',poi,.035)
            box.rotation_euler.z=a
    elif kind in ('lab','foundry'):
        shelter(poi,(0,2.2,0),7.5,5.3)
        for x in (-2.5,2.5):
            K.box('Workbench',(x,2,.85),(2.1,1.3,1.7),'shell',poi,.08)
            K.screen(poi,(x,2,1.73),1.4,.7)
        for x in (-5,5):
            cargo(poi,(x,-1,0),1.0)
        if kind=='foundry':
            for x in (-2.2,2.2):
                K.cylinder('Furnace_flue',(x,4.2,4.6),.48,3.7,'dark',poi,sides=16)
                K.ring('Flue_rim',(x,4.2,6.5),.48,.09,'copper',poi)
        else:
            K.box('Solar_frame',(0,2.2,3.8),(6.6,4.6,.2),'steel',poi,.04)
            for x in (-2.2,0,2.2):
                for y in (1.15,3.25): K.box('Solar_cell',(x,y,3.92),(2.03,1.91,.04),'glass',poi,.018)
    elif kind=='geothermal':
        for x,y,h in [(-3,2,5.6),(3,2,4.4),(0,4.5,7.0)]:
            K.taper('Geothermal_stack',(x,y,h/2),.95,.5,h,'stone',poi,sides=10)
            K.cylinder('Collector',(x,y,h*.5),1.1,.9,'teal',poi,sides=16)
            K.ring('Collector_band',(x,y,h*.5),1.12,.08,'orange',poi)
            K.hose('Collector_pipe',[(x,y,h*.5),(x,y-1.5,h*.5),(x,y-1.5,.45),(0,-1,.45)],.15,'copper',poi)
        K.cylinder('Turbine',(0,-1,1.0),1.1,2,'dark',poi,sides=24)
        K.ring('Turbine_cap',(0,-1,2.0),1.15,.13,'steel',poi)
        for x in (-4,4): cargo(poi,(x,-3,0),.8)
    elif kind=='arena':
        for ring in range(3):
            radius=4.6+ring*.9
            for i in range(12):
                a=math.radians(15+i*27)
                ob=K.box('Amphitheatre_seat',(radius*math.cos(a),radius*math.sin(a),.2+ring*.35),
                         (1.9,.85,.4+ring*.7),'stone',poi,.055)
                ob.rotation_euler.z=a+math.pi/2
        K.ring('Arena_boundary',(0,0,.055),3.7,.065,'trail',poi)
        for x in (-6,6): rock(poi,(x,2,2),(1.2,1.2,3),'stone',int(abs(x)))
    else:
        raise ValueError('Unimplemented POI kind: '+kind)
    # Explicit stable consumer anchors, not fake implemented game mechanics.
    for role,pos in [('arrival',(0,-10.0,1.2)),('departure',(0,-9.5,.15)),
                     ('resource',(-6,-5,.3)),('quest',(3,-6,.3)),('encounter',(6,-4,.5))]:
        marker=K.empty(role+'_'+site['slug'],poi,pos)
        marker['anchor_role']=role
        marker['stable_id']='aterpe/'+world['slug']+'/'+site['slug']+'/'+role
    # Small visible mineral sample at the resource anchor.
    for i in range(3):
        K.taper('Resource_sample',(-6+i*.35,-5,.45+i*.13),.24,.055,.9+i*.26,'mineral',poi,sides=6)
    return poi


def path_graph(root, world):
    vectors=np.array([s['direction'] for s in world['sites']])
    distance=np.arccos(np.clip(vectors@vectors.T,-1,1))
    edges=set()
    for i in range(len(vectors)):
        for j in np.argsort(distance[i])[1:3]: edges.add(tuple(sorted((i,int(j)))))
    # Add a deterministic spanning tree so every POI belongs to the walking network.
    reached={0}
    while len(reached)<len(vectors):
        _,i,j=min((distance[i,j],i,j) for i in reached for j in range(len(vectors)) if j not in reached)
        edges.add(tuple(sorted((i,j))));reached.add(j)
    group=K.empty('Footpath_network',root)
    group['layer']='trails'
    for i,j in sorted(edges):
        a,b=vectors[i],vectors[j];theta=float(distance[i,j]);axis=np.cross(a,b);axis/=np.linalg.norm(axis)
        arc=theta*world['radius'];steps=max(4,int(arc/2))
        start=min(.42,11/arc)
        dirs=[]
        for t in np.linspace(start,1-start,steps):
            n=(math.sin((1-t)*theta)*a+math.sin(t*theta)*b)/math.sin(theta)
            side=np.cross(axis,n);side/=np.linalg.norm(side)
            # axis is cross-track; offset equally on each side of the geodesic.
            for sign in (-1,1):
                v=n+axis*(sign*.75/world['radius']);v/=np.linalg.norm(v);dirs.append(v)
        n=np.array(dirs);verts=positions(n,world)+n*.055
        faces=[]
        for k in range(steps-1):
            tri=(2*k,2*k+1,2*k+3,2*k+2)
            pts=verts[list(tri)]
            if np.dot(np.cross(pts[1]-pts[0],pts[2]-pts[0]),pts.mean(axis=0))<0:tri=tuple(reversed(tri))
            faces.append(tri)
        mesh_object(f'trail_{i}_{j}',verts.tolist(),faces,group,['trail'])
    root['path_edges_json']=json.dumps(sorted(edges))


def scatter(root, world):
    rng=random.Random(world['seed'])
    group=K.empty('Scenery',root);group['layer']='scenery'
    sites=np.array([s['direction'] for s in world['sites']])
    made=0
    while made<125:
        n=np.array([rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-1,1)])
        if np.linalg.norm(n)<.2:continue
        n/=np.linalg.norm(n)
        if np.arccos(np.clip(sites@n,-1,1)).min()*world['radius']<20:continue
        pos=positions(n.reshape(1,3),world)[0]
        placement=frame('scenery_%03d'%made,group,n,pos.tolist())
        if world['slug']=='kare' and made%4!=0:
            plant(placement,(0,0,-.07),rng.uniform(2.2,4.1),False)
        elif world['slug']=='suharri' and made%3==0:
            plant(placement,(0,0,-.08),rng.uniform(1.8,3.4),True)
        else:
            scale=rng.uniform(.7,1.8)
            rock(placement,(0,0,.48*scale),(scale,scale*.7,scale*1.1),'stone',made)
        made+=1


def palette(world):
    warm=world['slug']=='suharri'
    values={
        'ground0':(.19,.31,.13) if not warm else (.23,.24,.13),
        'ground1':(.32,.42,.17) if not warm else (.38,.34,.16),
        'ground2':(.68,.69,.53) if not warm else (.19,.23,.27),
        'ground3':(.26,.35,.17) if not warm else (.11,.14,.17),
        'stone':(.64,.67,.53) if not warm else (.12,.17,.21),
        'trail':(.51,.41,.24) if not warm else (.53,.35,.18),
        'leaf':(.12,.33,.13) if not warm else (.38,.43,.16),
        'leaf2':(.34,.49,.16) if not warm else (.19,.39,.34),
        'bark':(.23,.15,.085) if not warm else (.22,.24,.19),
        'mineral':(.57,.37,.16) if not warm else (.27,.5,.65),
    }
    for name,color in values.items():K.M[name]=K.material('AT_'+name,color,.05,.86)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--missing-only',action='store_true');mode.add_argument('--force',action='store_true')
    parser.add_argument('--only',choices=[p['slug'] for p in PLANETS])
    argv=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    args=parser.parse_args(argv)
    chosen=[p for p in PLANETS if not args.only or p['slug']==args.only]
    if not args.missing_only and not args.force:
        if any((HERE/(p['slug']+'.blend')).exists() for p in chosen):raise SystemExit('Refusing to replace edited Aterpe sources')
    for initial in chosen:
        world=prepare(initial);target=HERE/(world['slug']+'.blend')
        if args.missing_only and target.exists():
            print('PRESERVED',world['slug'],flush=True);continue
        root=K.reset(world['slug'],world['title']);palette(world)
        root['asset_id']='aterpe/'+world['slug'];root['habitable']=True
        root['radius_metres']=world['radius'];root['biome']=world['biome']
        root['units']='metres';root['planet_spec_json']=json.dumps(world,ensure_ascii=False)
        root['coordinate_contract']='+Y up / -Z prime meridian in Godot; centre at origin'
        terrain(root,world)
        for site in world['sites']:poi_geometry(root,site,world)
        path_graph(root,world);scatter(root,world)
        bpy.context.scene.frame_set(1)
        bpy.context.view_layer.update()
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(target),compress=True)
        print('ATERPE_SOURCE_SAVED',world['slug'],len(root.children_recursive),flush=True)
    print('ATERPE_BUILD_PASS',flush=True)


if __name__=='__main__':main()
