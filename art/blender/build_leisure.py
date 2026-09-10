"""Author the social spaces in Blender and export their named roots as one GLB.

Run with Blender 4.5.3 or its bpy Python module. Geometry is original; the
sculptures are deliberately stylized studies, never presented as scans.
"""
from pathlib import Path
import hashlib
import json
import math
import random
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
random.seed(9021)
bpy.ops.wm.read_factory_settings(use_empty=True)
def vector(p): return Vector((p[0], -p[2], p[1]))
def material(name, color, metal=0, emission=0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    shader=m.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Metallic'].default_value=metal
    shader.inputs['Roughness'].default_value=.68
    if emission:
        shader.inputs['Emission Color'].default_value=(*color,1)
        shader.inputs['Emission Strength'].default_value=emission
    return m
STONE=material('Sculpture · warm limestone',(.72,.67,.52))
MARBLE=material('Gallery · pale stone',(.52,.57,.55))
DARK=material('Deep blue enamel',(.027,.075,.11),.25)
WOOD=material('Oiled chestnut',(.28,.12,.056))
GOLD=material('Brushed brass',(.64,.39,.12),.55)
TEAL=material('Sea glass',(.04,.45,.39),.25)
LIGHT=material('Warm light',(.95,.68,.3),0,2)
SAND=material('Sand',(.69,.52,.29))
WATER=material('Water',(.025,.25,.33),.25)
RED=material('Booth red',(.56,.06,.045))
GLASS=material('Smoked blue glazing',(.09,.25,.32),.4)
LEAF=material('Wind grass',(.2,.3,.11))
PAPER=material('Book paper',(.8,.76,.6))
roots=[]
def empty(name, parent=None, at=(0,0,0)):
    ob=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(ob)
    ob.parent=parent;ob.location=vector(at);return ob
def zone(name):
    ob=empty(name);roots.append(ob);return ob
def finish(ob,name,parent,mat):
    ob.name=name;ob.parent=parent;ob.data.materials.append(mat);return ob
def box(parent,name,p,size,mat=DARK,bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=vector(p));ob=bpy.context.object
    ob.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=ob.modifiers.new('Rounded edges','BEVEL');mod.width=bevel;mod.segments=2
    return finish(ob,name,parent,mat)
def oval(parent,name,p,size,mat=STONE):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,location=vector(p));ob=bpy.context.object
    ob.scale=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for poly in ob.data.polygons:poly.use_smooth=True
    return finish(ob,name,parent,mat)
def rod(parent,name,a,b,r,mat=STONE,r2=None):
    av,bv=vector(a),vector(b);delta=bv-av
    bpy.ops.mesh.primitive_cone_add(vertices=12,radius1=r,radius2=r if r2 is None else r2,depth=delta.length,location=(av+bv)/2)
    ob=bpy.context.object;ob.rotation_mode='QUATERNION';ob.rotation_quaternion=delta.to_track_quat('Z','Y')
    return finish(ob,name,parent,mat)
def combine(parent,name):
    meshes=[o for o in parent.children if o.type=='MESH' and not o.name.startswith('Decor_')]
    if not meshes:return
    bpy.ops.object.select_all(action='DESELECT')
    for ob in meshes:ob.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.convert(target='MESH');bpy.ops.object.join()
    ob=bpy.context.object;ob.name=name;return ob
def room(parent,width,depth,height=5,walls=True):
    box(parent,'Floor',(0,-.15,0),(width,.3,depth),MARBLE)
    if walls:
        for x in [-width/2,width/2]:box(parent,'Side wall',(x,height/2,0),(.3,height,depth),DARK)
        box(parent,'Back wall',(0,height/2,-depth/2),(width,height,.3),DARK)
        for x in [-width/4-1,width/4+1]:box(parent,'Entrance wall',(x,height/2,depth/2),(width/2-2,height,.3),DARK)
        for z in range(int(-depth/2)+2,int(depth/2),6):
            box(parent,'Ceiling beam',(0,height-.2,z),(width,.35,.4),GOLD)
            box(parent,'Linear light',(0,height-.43,z),(width-2,.05,.09),LIGHT)
    for x in [-width/2+.5,width/2-.5]:box(parent,'Border',(x,.015,0),(.12,.035,depth-1),GOLD)
def face(parent,x,y,z,beard=False,headdress=False):
    oval(parent,'Head',(x,y,z),(.29,.38,.28))
    box(parent,'Nose',(x,y-.03,z+.27),(.09,.17,.12),STONE,.025)
    for sign in [-1,1]:
        oval(parent,'Ear',(x+sign*.28,y-.015,z),(.06,.11,.055))
        oval(parent,'Eye recess',(x+sign*.1,y+.055,z+.257),(.055,.027,.018),DARK)
        rod(parent,'Brow',(x+sign*.055,y+.12,z+.24),(x+sign*.16,y+.105,z+.24),.025)
    if beard:
        for dx in [-.18,-.09,0,.09,.18]:oval(parent,'Beard',(x+dx,y-.3,z+.13),(.085,.2,.15))
    if headdress:
        for sign in [-1,1]:box(parent,'Nemes',(x+sign*.32,y-.06,z-.06),(.16,.75,.36),STONE,.07)
    else:
        for i in range(11):
            a=i*math.tau/11;oval(parent,'Hair',(x+math.cos(a)*.25,y+.21,z+math.sin(a)*.22),(.105,.15,.11))
def person(parent,variant='standing',scale=1):
    figure=empty('Figure',parent)
    bust=variant in ['bust','bearded','pharaoh','princess']
    if not bust:
        for sign in [-1,1]:
            rod(figure,'Leg',(sign*.21,.16,0),(sign*.2,1.2,.025 if sign==1 else -.15),.15,r2=.22)
            oval(figure,'Foot',(sign*.21,.12,.14),(.16,.12,.29))
    else:box(figure,'Bust support',(0,.4,0),(.45,.8,.4),STONE,.05)
    hip=1.15 if not bust else .85
    oval(figure,'Pelvis',(0,hip,0),(.43,.34,.26))
    oval(figure,'Torso',(.035,hip+.5,-.015),(.48,.61,.28))
    rod(figure,'Neck',(.02,hip+.88,0),(.02,hip+1.12,0),.14)
    face(figure,.02,hip+1.42,.01,variant in ['bearded','hercules','poseidon','laocoon'],variant in ['pharaoh','princess'])
    if not bust:
        if variant in ['venus','draped','seated']:
            for i in range(11):
                a=i*math.tau/11
                rod(figure,'Drapery',(math.cos(a)*.4,hip+.08,math.sin(a)*.23),(math.cos(a)*.44,.08,math.sin(a)*.27),.085)
        if variant!='venus':
            for sign in [-1,1]:
                elbow=(sign*.69,hip+.52,0)
                hand=(sign*.91,hip+.27,.22)
                if variant in ['poseidon','laocoon']:elbow=(sign*.85,hip+.98,0);hand=(sign*1.28,hip+1.02,.1)
                rod(figure,'Upper arm',(sign*.42,hip+.8,0),elbow,.125)
                rod(figure,'Forearm',elbow,hand,.095);oval(figure,'Hand',hand,(.1,.12,.09))
        if variant in ['spear','poseidon']:
            rod(figure,'Spear',(.99,0,.2),(.99,3.35,.2),.032,GOLD)
            if variant=='poseidon':
                for dx in [-.18,0,.18]:rod(figure,'Trident',(.99+dx,3.0,.2),(.99+dx,3.48,.2),.035,GOLD)
        if variant=='hercules':rod(figure,'Club',(.65,.1,-.1),(.85,1.25,-.1),.13,r2=.22)
        if variant=='laocoon':
            previous=None
            for i in range(30):
                a=i*.65;p=(math.cos(a)*.62,.15+i*.065,math.sin(a)*.42)
                if previous:rod(figure,'Serpent',previous,p,.055)
                previous=p
    combine(figure,'Carved form')
    figure.scale=(scale,scale,scale)
    return figure
def animal(parent,kind='lion'):
    figure=empty('Figure',parent)
    oval(figure,'Body',(0,.95,0),(.46,.54,.95))
    for x in [-.35,.35]:
        for z in [-.52,.5]:rod(figure,'Leg',(x,.12,z),(x,.92,z),.13);oval(figure,'Paw',(x,.09,z+.1),(.18,.09,.25))
    oval(figure,'Neck',(0,1.4,.62),(.35,.55,.31))
    oval(figure,'Head',(0,1.8,.85),(.32,.32,.39))
    oval(figure,'Muzzle',(0,1.69,1.13),(.22,.15,.19))
    for x in [-.17,.17]:oval(figure,'Ear',(x,2.03,.75),(.1,.16,.075));oval(figure,'Eye',(x,1.88,1.14),(.035,.04,.025),DARK)
    if kind=='lion':
        for i in range(14):
            a=i*math.tau/14;oval(figure,'Mane',(math.cos(a)*.35,1.7+math.sin(a)*.4,.62),(.15,.19,.18))
    if kind=='horse':
        oval(figure,'Long head',(0,1.75,1.0),(.25,.37,.48))
        for z in [-.2,0,.2,.4]:oval(figure,'Mane',(0,1.72,z),(.07,.2,.22))
    rod(figure,'Tail',(0,1.2,-.82),(.4,.45,-1.25),.08)
    combine(figure,'Carved animal');return figure

EXHIBITS=[
 ('venus-de-milo','Afrodita de Melos','venus'),('farao-amasis','Amasis II','pharaoh'),('leon-al-lat','León de Al-Lāt','lion'),
 ('caballo-marco-aurelio','Caballo de Marco Aurelio','horse'),('david-cabeza','Cabeza del David','bust'),('doriforo','Doríforo','spear'),
 ('herakles-farnese','Heracles Farnesio','hercules'),('homero','Homero','bearded'),('jabali','Jabalí sentado','boar'),
 ('julio-cesar','Julio César','bust'),('kore-chiton','Koré con quitón','draped'),('laocoonte','Laocoonte','laocoon'),
 ('loba-capitolina','Loba capitolina','wolf'),('marco-aurelio','Marco Aurelio','bearded'),('penelope','Penélope','seated'),
 ('poseidon-artemision','Poseidón de Artemisión','poseidon'),('prinsesse-amarna','Princesa de Amarna','princess'),('venus-capitolina','Venus capitolina','draped')]
museum=zone('museum_hall');room(museum,36,58,6)
catalog=[]
for i,(identifier,title,variant) in enumerate(EXHIBITS):
    x=(i%3-1)*10;z=(i//3)*8-22
    box(museum,'Pedestal',(x,.4,z),(2.25,.8,2.25),MARBLE,.07)
    box(museum,'Brass plinth',(x,.85,z),(2.05,.1,2.05),GOLD,.03)
    holder=empty('exhibit_'+identifier,museum,(x,.9,z))
    figure=animal(holder,variant) if variant in ['lion','horse','boar','wolf'] else person(holder,variant)
    catalog.append({'id':identifier,'title':title,'position':[x,0,z+2.25],'zone':8,'node':'exhibit_'+identifier,
      'text':'Estudio escultórico estilizado inspirado en '+title+'. Modelado nuevo con geometría editable de Blender. Esta interpretación de juego no es un escaneo, un vaciado ni una reconstrucción arqueológica del original.'})
combine(museum,'Gallery architecture')
for i in range(5):
    wall=empty('painting_'+str(i),museum,(-17.7,2.2,-20+i*10))
    box(wall,'Brass frame',(0,0,0),(.16,2.7,4.2),GOLD)
    box(wall,'Dark canvas',(.1,0,0),(.03,2.5,4),DARK)
    for j in range(12):
        z=-1.8+j*.3;height=.3+math.sin(j*.7+i)*.2
        box(wall,'Painted relief',(.14,-.7+height/2,z),(.035,height+.5,.31),[TEAL,MARBLE,GOLD][(j+i)%3])
    combine(wall,'Original geometric painting')
book=empty('book',museum,(5,1.1,24))
box(museum,'Book lectern',(5,.53,24),(1.8,1.06,1.1),WOOD,.06)
box(book,'Book spine',(0,0,0),(.12,.07,1.0),GOLD)
for sign in [-1,1]:
    cover=empty('cover_left' if sign==-1 else 'cover_right',book)
    box(cover,'Book cover',(sign*.4,0,0),(.8,.07,1.05),TEAL)
box(book,'Pages',(0,.05,0),(1.48,.05,.94),PAPER)
page=empty('turning_page',book,(0,.1,0));box(page,'Page',(-.4,0,0),(.8,.013,.94),PAPER)

cantina=zone('cantina');room(cantina,24,24,4.8)
box(cantina,'Bar',(0,1.05,-7),(9,2.1,1.7),WOOD,.15)
box(cantina,'Bar top',(0,2.13,-7),(9.4,.18,2),GOLD,.06)
for i in range(12):rod(cantina,'Bottle',(-4+i*.7,2.25,-7),(-4+i*.7,2.68,-7),.09,TEAL,r2=.05)
for x in [-5,5]:
    for z in [0,6]:
        box(cantina,'Table',(x,1.02,z),(3,.16,2.2),WOOD,.08)
        rod(cantina,'Table leg',(x,0,z),(x,1,z),.18,GOLD)
        for sign in [-1,1]:
            box(cantina,'Bench',(x,.52,z+sign*1.8),(3,.16,.6),TEAL,.06)
            for dx in [-1,1]:rod(cantina,'Bench support',(x+dx,0,z+sign*1.8),(x+dx,.5,z+sign*1.8),.07,GOLD)
combine(cantina,'Cantina architecture')

terrace=zone('terrace');room(terrace,28,24,4,False)
for x in [-14,14]:box(terrace,'Balustrade',(x,.7,0),(.25,1.4,24),GOLD)
box(terrace,'Balustrade',(0,.7,-12),(28,1.4,.25),GOLD)
for x,z in [(-4,-4),(5,3)]:
    rod(terrace,'Table leg',(x,0,z),(x,.92,z),.12,GOLD)
    box(terrace,'Table',(x,1,z),(2.5,.15,2.5),WOOD,.1)
    for sign in [-1,1]:box(terrace,'Seat',(x+sign*2,.5,z),(.9,.18,.9),TEAL,.1)
rod(terrace,'Fishing rod',(10,0,-9),(13,2.8,-13),.045,WOOD)
combine(terrace,'Terrace architecture')

studio=zone('studio');room(studio,24,24,5)
for i in range(9):
    box(studio,'Acoustic panel',(-8+i*2,2.3,-11.7),(1.7,3,.25),[TEAL,WOOD,DARK][i%3],.04)
box(studio,'Stage',(0,.15,-5),(9,.3,7),WOOD)
rod(studio,'Microphone',(0,.3,-3),(0,1.7,-3),.025,GOLD)
oval(studio,'Microphone head',(0,1.72,-3),(.07,.12,.07),DARK)
for x in [-7,7]:box(studio,'Speaker',(x,1,-6),(1.5,2,1.3),DARK,.05)
combine(studio,'Studio architecture')

memories=zone('memories_hall');room(memories,12,64,6)
box(memories,'Black runner',(0,.035,0),(4,.035,62),DARK)
for i in range(12):
    for sign in [-1,1]:
        box(memories,'Memorial',(sign*4.5,1.2,i*5-27),(1.2,2.4,1.1),MARBLE,.08)
        oval(memories,'Memory light',(sign*4.5,2.7,i*5-27),(.2,.2,.2),LIGHT)
        box(memories,'Raven motif',(sign*1.6,.07,i*5-27),(.8,.04,.25),GOLD)
combine(memories,'Memorial architecture')

beach=zone('beach')
box(beach,'Sand',(-4,-.2,0),(32,.4,112),SAND)
box(beach,'Decor_Water',(100,-.19,0),(176,.08,400),WATER)
for i in range(12):
    z=-49+i*9
    oval(beach,'Dune',(-18,.1,z),(6,1.5+random.random()*1.4,7),SAND)
    for j in range(4):
        x=-13-random.random()*4
        rod(beach,'Grass',(x,.6,z+j*.5),(x+.6,1.2,z+j*.5),.04,LEAF,r2=0)
    if i%2==0:
        rod(beach,'Lamp',(-9,0,z),(-9,3.6,z),.065,GOLD)
        oval(beach,'Lamp globe',(-9,3.7,z),(.16,.2,.16),LIGHT)
for z in range(-48,53,4):box(beach,'Walkway',(-4,.025,z),(4,.04,3.5),WOOD)
booth=empty('phone_booth',beach,(-7,0,48))
for x in [-.65,.65]:box(booth,'Booth frame',(x,1.4,0),(.12,2.8,1.4),RED)
box(booth,'Roof',(0,2.85,0),(1.55,.18,1.55),RED,.1)
box(booth,'Glazed rear',(0,1.4,-.65),(1.3,2.6,.08),GLASS)
box(booth,'Telephone',(0,1.45,-.42),(.36,.5,.16),DARK,.04)
combine(booth,'Telephone booth')
statue=empty('beach_lion',beach,(2,.8,-32));animal(statue,'lion')
box(beach,'Lion pedestal',(2,.4,-32),(3,.8,3),MARBLE,.08)
clock=empty('shore_clock',beach,(5,1.6,8))
oval(clock,'Clock face',(0,0,0),(1.3,1.3,.12),PAPER)
for i in range(12):
    a=i*math.tau/12;oval(clock,'Hour mark',(math.sin(a),math.cos(a),.14),(.055,.055,.03),GOLD)
for name,length,width in [('hour_hand',.58,.07),('minute_hand',.85,.045),('second_hand',1,.025)]:
    hand=empty(name,clock);box(hand,'Clock hand',(0,length/2,.18),(width,length,.035),RED if name=='second_hand' else DARK)
for z in [-65,5,75]:
    rod(beach,'Decor_Turbine tower',(75,0,z),(75,45,z),1.2,MARBLE,r2=.4)
    rotor=empty('wind_rotor_'+str(z),beach,(75,45,z))
    oval(rotor,'Turbine hub',(0,0,0),(.9,.9,.9),MARBLE)
    for i in range(3):
        a=i*math.tau/3;rod(rotor,'Blade',(math.sin(a)*2,math.cos(a)*2,0),(math.sin(a)*18,math.cos(a)*18,0),.7,MARBLE,r2=.15)
for i in range(10):box(beach,'Decor_Foam',(12.3,-.09,-50+i*11),(.35,.04,8),PAPER)
# Keep animated roots separate while batching the static room architecture.
combine(beach,'Beach architecture')

for index,root in enumerate(roots):root.location=vector((index%3*200,0,index//3*460))
bpy.context.scene['authoring']='Original Lagunak remake geometry. Stylized sculptures; no imported reference meshes.'
source=ROOT/'art/blender/leisure_assets.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
# Reuse the exporter used after manual editing; it restores authoring positions.
import importlib.util
spec=importlib.util.spec_from_file_location('leisure_export',ROOT/'art/blender/export_leisure.py')
exporter=importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)
exporter.export()
out=ROOT/'game/assets/models/leisure_bundle.glb'
(ROOT/'game/data/museum.json').write_text(json.dumps({'format':'lagunak-museum','version':1,'exhibits':catalog},ensure_ascii=False,indent=2)+'\n')
print('LEISURE_ASSETS_OK',source.stat().st_size,out.stat().st_size,len(catalog),flush=True)
