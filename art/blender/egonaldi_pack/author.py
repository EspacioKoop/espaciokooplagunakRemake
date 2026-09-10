"""Egonaldi: original reusable station destinations. MIT.
python author.py build | python author.py export
Blender/bpy 4.5.3. Helpers are our own Bizigai mesh primitives, not imported art.
Existing editable sources are preserved. Export and preview never save over them.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(HERE.parent/'bizigai_pack'))
from build import Mesh, material, collection, anchor, glb_info, godot_to_blender
import bpy
import bmesh
from mathutils import Vector, Matrix

OUT=ROOT/'game/assets/models/egonaldi_pack'
IMAGES=ROOT/'docs/images/egonaldi_pack'
DESTINATIONS={
 'itun_embassy':('Itun','Embajada y sala de negociación',(.65,.37,.10)),
 'babes_security':('Babes','Control de seguridad y celdas',(.62,.16,.12)),
 'trebe_training':('Trebe','Entrenamiento físico y obstáculos',(.10,.48,.39)),
 'zeru_observatory':('Zeru','Observatorio panorámico',(.12,.32,.64)),
 'ur_recycling':('Ur','Reciclaje y depuración de agua',(.08,.43,.53)),
 'isil_sanctuary':('Isil','Cámara de meditación y jardín mineral',(.44,.25,.58)),
}
SOCKETS={
 'arrival':(0,.98,17), 'return':(0,.05,18.5),
 'connector_south':(0,0,20), 'connector_north':(0,0,-20),
 'npc_left':(-3,.05,6), 'npc_right':(3,.05,6),
 'objective':(-3,.05,-6), 'encounter':(3,.05,-6),
}


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def mats(accent):
 return [material('egonaldi_'+n,c,metal,rough,emission) for n,c,metal,rough,emission in [
  ('deck',(.095,.135,.17),.4,.65,0),('wall',(.36,.43,.46),.25,.5,0),
  ('ceramic',(.70,.77,.76),.05,.5,0),('structure',(.045,.07,.095),.7,.4,0),
  ('accent',accent,.25,.45,0),('lamp',(.20,.74,.78),.1,.4,1.7),
  ('glass',(.055,.19,.25),.65,.18,0),('cushion',(.16,.23,.26),.0,.9,0),
  ('wood',(.34,.22,.13),.0,.8,0),('water',(.04,.38,.43),.5,.15,.15),
  ('stone',(.49,.48,.43),.1,.8,0),('signal',(.86,.58,.14),.2,.5,.4)]]


def finish(mesh,name,materials,coll,bevel=False):
 obj=mesh.object(name,materials,coll)
 if bevel:
  mod=obj.modifiers.new('edge_finish','BEVEL');mod.width=.045;mod.segments=1
  mod.affect='EDGES'
 return obj


def chair(m,x,y,heading=0):
 r=Matrix.Rotation(heading,3,'Z')
 def p(v):return Vector((x,y,0))+r@Vector(v)
 m.box(p((0,0,.58)),(1.15,1.1,.22),7,r)
 m.box(p((0,.48,1.1)),(1.15,.15,.9),7,r)
 for dx in [-.42,.42]:
  for dy in [-.36,.36]:m.box(p((dx,dy,.25)),(.10,.10,.5),3,r)


def console(m,d,x,y):
 m.box((x,y,.65),(2.8,1.7,1.3),1)
 m.box((x,y,1.35),(3,1.8,.22),3)
 m.box((x,y+.4,2.0),(2.7,.2,1.3),3)
 d.box((x,y+.27,2.05),(2.4,.05,.95),6)
 for i in range(5):d.box((x-.9+i*.45,y+.23,1.85+i*.10),(.24,.03,.07),5)


def shell(materials):
 coll=collection('ARCHITECTURE')
 floor=Mesh();floor.box((0,0,-.25),(36,40,.5),0)
 finish(floor,'deck-col',materials,coll)
 side=Mesh()
 for x in [-18,18]:
  side.box((x,0,1),(0.6,40,2),1)
  side.box((x,0,7.1),(.6,40,1.8),1)
  for y in [-16,-8,0,8,16]:
   side.box((x,y,4),(.5,7.5,4.2),6)
   side.box((x,y+4,4),(.9,.35,8),3)
 finish(side,'side_walls-col',materials,coll)
 for y,name in [(-20,'front_wall'),(20,'back_wall')]:
  wall=Mesh()
  for x in [-10.5,10.5]:wall.box((x,y,4),(15,.6,8),1)
  wall.box((0,y,7),(6,.6,2),3)
  for x in [-3.2,3.2]:wall.box((x,y,3),(.45,1,6),4)
  finish(wall,name+'-col',materials,coll,True)
 roof=Mesh()
 for x in [-10.5,10.5]:roof.box((x,0,8.2),(15,40,.4),3)
 roof.box((0,0,8.2),(6,40,.2),6)
 finish(roof,'roof-col',materials,collection('ROOF'))
 ribs=Mesh(); detail=Mesh()
 for y in [-16,-8,0,8,16]:
  for s in [-1,1]:
   ribs.beam((s*16.8,y,0),(s*16.8,y,6),.32,3)
   ribs.beam((s*16.8,y,6),(s*14.8,y,7.8),.32,3)
  ribs.beam((-15,y,7.8),(15,y,7.8),.3,3)
  for x in [-9,9]:detail.box((x,y,7.55),(8,.4,.16),5)
 finish(ribs,'ribs-col',materials,coll)
 for x in range(-16,18,4):detail.box((x,0,.012),(.035,39,.02),3)
 for y in range(-18,20,4):detail.box((0,y,.014),(35,.035,.02),3)
 for x in [-2.2,2.2]:
  detail.box((x,0,.025),(.09,39,.035),4)
  for y in [-16,-8,0,8,16]:detail.box((x,y,.048),(.13,1.1,.035),5)
 for y in [-18,18]:
  for s in [-1,1]:detail.beam((s*1,y-.6,.035),(0,y+.6,.035),.13,5)
 finish(detail,'architecture_detail',materials,coll)


def embassy(m,d):
 for x in [-8,8]:
  m.box((x,0,1.05),(5,16,.35),8)
  for y in [-5,5]:m.box((x,y,.5),(3,1.3,1),3)
  for y in [-6,-2,2,6]:
   chair(m,x-3.2,y,-math.pi/2);chair(m,x+3.2,y,math.pi/2)
   d.box((x,y,1.26),(2.5,1,.05),4)
  m.cylinder((x,13,.7),3,1.4,2,n=24)
  m.cylinder((x,13,2.0),.5,2,3,n=12)
  d.ball((x,13,3.3),(1.9,1.9,1.9),6,20,10)
  d.ring((x,13,3.3),2.2,.10,5,32)
 for x in [-14,14]:
  m.cylinder((x,13,3.5),.10,7,3,n=8)
  m.box((x+.75,13,5.5),(1.4,.08,2.6),4)
 for x in [-8,8]:console(m,d,x,-13)


def security(m,d):
 for s in [-1,1]:
  x=s*11
  for y in [-9,0,9]:
   m.box((x,y,.08),(9,7.8,.16),4)
   for dy in [-4,4]:m.box((x,y+dy,2.6),(9,.3,5.2),1)
   m.box((x+s*4.5,y,2.6),(.3,8,5.2),1)
   # Open doorway on the inward face; bars stop outside its 2.2 m opening.
   for dy in [-3.5,-2.8,-2.1,2.1,2.8,3.5]:
    m.cylinder((x-s*4.5,y+dy,2.4),.07,4.8,3,n=6)
   m.box((x-s*4.5,y,4.8),(.22,8,.28),3)
   m.box((x+s*2,y,.65),(2,3.5,1.3),7)
   m.box((x+s*3,y+2,1.0),(1.2,1.2,2),2)
   d.box((x-s*4.65,y,5.05),(.07,2.2,.3),5)
  console(m,d,s*8,15)
  m.cylinder((s*4.5,-13,1.1),.23,2.2,3,n=10)
  d.ball((s*4.5,-13,2.3),(.4,.4,.3),11,10,6)


def training(m,d):
 for s in [-1,1]:
  x=s*9
  for i in range(5):
   y=-11+i*3
   m.box((x,y,.23+i*.08),(5.5,1.3,.46+i*.16),4)
   d.box((x,y,.48+i*.16),(4.8,.8,.04),7)
  for dx in [-2.5,2.5]:m.beam((x+dx,6,0),(x+dx,6,4),.16,3)
  m.beam((x-2.5,6,4),(x+2.5,6,4),.2,3)
  for k in range(7):m.beam((x-2.5,6+k*.6,4),(x+2.5,6+k*.6,4),.10,3)
  for dx in [-2.5,2.5]:m.beam((x+dx,9.6,0),(x+dx,9.6,4),.16,3)
  for dx in [-2,2]:
   m.cylinder((x+dx,14,1.3),.5,2.6,7,n=12)
   d.ring((x+dx,14,1.4),.54,.10,4,12)
  console(m,d,s*13,-15)


def observatory(m,d):
 for s in [-1,1]:
  x=s*10
  m.cylinder((x,8,.35),5,.7,3,n=32)
  d.ring((x,8,.73),4.5,.10,5,32)
  m.cylinder((x,8,1.7),1.2,2.7,1,n=16)
  m.beam((x-2,8,2),(x-2,8,4),.4,4)
  m.beam((x+2,8,2),(x+2,8,4),.4,4)
  rot=Matrix.Rotation(-.6,3,'X')
  m.cylinder((x,8,4.8),1.3,6,2,n=20,rot=rot)
  d.ball((x,9.7,7.25),(1.15,1.0,.45),6,16,8)
  for y in [-12,-6,0]:console(m,d,s*9,y)
  m.box((s*12,18,4),(7,.4,6),3)
  d.box((s*12,17.75,4),(6.6,.06,5.6),6)
  for i in range(15):
   xx=s*12+2.6*math.sin(i*2.3);zz=4+2.3*math.cos(i*1.9)
   d.ball((xx,17.65,zz),(.06,.05,.06),5,6,4)


def recycling(m,d):
 for s in [-1,1]:
  x=s*11
  for y in [-8,5]:
   m.cylinder((x,y,2.4),3.1,4.8,1,n=24)
   m.cylinder((x,y,4.9),3.2,.22,3,n=24)
   d.cylinder((x,y,5.03),2.65,.035,9,n=32)
   for z in [.5,2.5,4.5]:d.ring((x,y,z),3.15,.13,4,24)
   m.beam((x,y,4.5),(x+s*4,y,4.5),.4,3)
  m.beam((x+s*4,-8,4.5),(x+s*4,13,4.5),.5,4)
  for j in range(4):m.cylinder((s*7+j*s*2,15,1.9),.65,3.8,2,n=12)
  console(m,d,s*8,-15)
  for y in [-3,10]:
   m.box((s*5,y,.7),(1.5,2.5,1.4),3)
   d.box((s*5,y,1.42),(1.3,2.3,.05),5)


def sanctuary(m,d):
 for s in [-1,1]:
  x=s*10
  for y in [-7,8]:
   m.cylinder((x,y,.20),5,.4,10,n=32)
   d.cylinder((x,y,.43),4.6,.04,8,n=32)
   for i in range(5):d.ring((x,y,.48),1+i*.7,.045,2,40)
   for i in range(3):
    a=i*2.4+s
    m.ball((x+1.6*math.cos(a),y+1.6*math.sin(a),1+i*.5),(1.0,.8,1+i*.4),10,10,6)
  for y in [-15,0,15]:
   m.box((s*6,y,.55),(3,1.5,1.1),8)
   d.box((s*6,y,1.14),(2.8,1.4,.08),7)
  m.cylinder((s*14,15,2.6),.18,5.2,3,n=10)
  d.ball((s*14,15,5.3),(.6,.6,.8),5,12,6)
  for y in [-12,0,12]:
   m.beam((s*16,y,0),(s*16,y,5),.18,8)
   for z in [1,2,3,4]:d.box((s*16,y,z),(.07,3.4,.09),4)


BUILDERS=[embassy,security,training,observatory,recycling,sanctuary]


def build(ident,force=False):
 source=HERE/(ident+'.blend')
 if source.exists() and not force:return False
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.context.scene.unit_settings.system='METRIC'
 materials=mats(DESTINATIONS[ident][2]);shell(materials)
 m,d=Mesh(),Mesh()
 BUILDERS[list(DESTINATIONS).index(ident)](m,d)
 coll=collection('INTERIOR')
 finish(m,'furnishings-col',materials,coll,True)
 finish(d,'furnishing_detail',materials,coll)
 coll=collection('CONNECTORS')
 for name,pos in SOCKETS.items():
  a=anchor('socket_'+name,godot_to_blender(pos),Matrix.Identity(3),coll)
  a['purpose']=name
  if name.startswith('connector_'):
   a.rotation_mode='XYZ';a.rotation_euler=(0,0,math.pi if name.endswith('south') else 0)
 scene=bpy.context.scene;scene['asset_id']='egonaldi/'+ident
 scene['license']='MIT';scene['units']='metres'
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
 return True


def preview(ident,path):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(path))
 for obj in bpy.data.objects:
  if obj.type=='MESH' and (obj.name.startswith('roof') or obj.name.startswith('front_wall')):obj.hide_render=True
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24
 scene.cycles.use_denoising=True
 scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.render.resolution_percentage=100
 scene.world=bpy.data.worlds.new('InspectionWorld');scene.world.use_nodes=True
 scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.04,.065,.09,1)
 scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
 for pos,power,size in [((10,-15,30),14000,22),((-18,10,25),10000,18),((0,0,6),1100,12)]:
  light=bpy.data.lights.new('InspectionArea','AREA');light.energy=power;light.shape='DISK';light.size=size
  obj=bpy.data.objects.new('InspectionArea',light);scene.collection.objects.link(obj);obj.location=pos
  obj.rotation_euler=(Vector((0,0,0))-obj.location).to_track_quat('-Z','Y').to_euler()
 cam_data=bpy.data.cameras.new('InspectionCamera');cam=bpy.data.objects.new('InspectionCamera',cam_data)
 scene.collection.objects.link(cam);cam.location=(38,-47,39)
 cam.rotation_euler=(Vector((0,1,1))-cam.location).to_track_quat('-Z','Y').to_euler()
 cam_data.type='ORTHO';cam_data.ortho_scale=60;scene.camera=cam
 scene.view_settings.view_transform='AgX'
 IMAGES.mkdir(parents=True,exist_ok=True);scene.render.filepath=str(IMAGES/(ident+'.png'))
 bpy.ops.render.render(write_still=True)


def prepare_export_meshes():
 """Evaluate editable bevels, then weld coincident cap vertices at 10 micrometres.
 Narrow beveled rods can otherwise contain collapsed triangles. Work is in memory;
 this is geometric cleanup of the delivery, not weaker validation or source loss.
 """
 depsgraph=bpy.context.evaluated_depsgraph_get()
 for obj in list(bpy.context.scene.objects):
  if obj.type!='MESH':continue
  evaluated=obj.evaluated_get(depsgraph)
  data=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=depsgraph)
  data.name=obj.data.name+'_export'
  # Keep Godot's collision suffix at the end of the runtime mesh name.
  if obj.name.endswith('-col'):data.name=obj.name
  obj.modifiers.clear();obj.data=data
  bm=bmesh.new();bm.from_mesh(data)
  before=len(bm.verts)
  bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.00001)
  bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=0.00001)
  bmesh.ops.triangulate(bm,faces=list(bm.faces))
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
  removed=before-len(bm.verts)
  bm.to_mesh(data);bm.free();data.update()
  if removed:print('EGONALDI_WELD',obj.name,'coincident_vertices=',removed)


def export(ident):
 source=HERE/(ident+'.blend');before=sha(source)
 bpy.ops.wm.open_mainfile(filepath=str(source))
 prepare_export_meshes()
 OUT.mkdir(parents=True,exist_ok=True);target=OUT/(ident+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',export_apply=True,
  export_yup=True,export_extras=True,export_animations=False,export_cameras=False,export_lights=False)
 if sha(source)!=before:raise RuntimeError('Exporter modified source')
 info=glb_info(target)
 info.update({'id':'egonaldi/'+ident,'name':DESTINATIONS[ident][0],'description':DESTINATIONS[ident][1],
  'source':str(source.relative_to(ROOT)),'source_sha256':before,'runtime':str(target.relative_to(ROOT)),
  'res_path':'res://assets/models/egonaldi_pack/'+ident+'.glb',
  'units':'metres','floor_size_m':[36,40],'height_m':8.4,'axes':'+Y up; -Z north/forward',
  'arrival_m':list(SOCKETS['arrival']),'sockets':{'socket_'+k:list(v) for k,v in SOCKETS.items()},
  'connector_aperture_m':[5.95,6],'clear_route_m':[[0,.98,17],[0,.98,0],[0,.98,-17]],
  'preview':str((IMAGES/(ident+'.png')).relative_to(ROOT)),
  'export_cleanup':'evaluated modifiers; coincident vertices welded at 0.00001 m; triangulated',
  'limits':['Reusable scenery, not new campaign rules','Open connectors; no door or docking logic','No NPC, economy, policing or resource simulation']})
 preview(ident,target)
 info['preview_sha256']=sha(IMAGES/(ident+'.png'))
 return info


def main():
 parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['build','export']);parser.add_argument('--force',action='store_true')
 args=parser.parse_args()
 if args.mode=='build':
  created=sum(build(k,args.force) for k in DESTINATIONS)
  print('EGONALDI_SOURCES_PASS created=%d preserved=%d'%(created,6-created))
 else:
  data={'schema':'egonaldi-destinations','version':1,'license':'MIT','authoring':'Blender '+bpy.app.version_string,
   'assets':[export(k) for k in DESTINATIONS]}
  (OUT/'manifest.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
  print('EGONALDI_EXPORT_PASS assets=6 sources=6 previews=6')
if __name__=='__main__':main()
