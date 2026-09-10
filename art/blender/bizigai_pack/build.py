"""Create/editable Blender worlds, export self-contained GLB without overwriting sources.
Usage: python build.py build | python build.py export
Requires bpy 4.5.3; all geometry is original. MIT.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import struct
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
from spec import WORLDS, normalize, dot, poi_direction, surface_radius, godot_to_blender, blender_to_godot
import bpy
from mathutils import Vector, Matrix

RUNTIME = ROOT / "game/assets/models/bizigai_pack"
TIERS = {"surface": 64, "approach": 32, "orbital": 16}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def material(name, color, metallic=0.0, roughness=.75, emission=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    s = m.node_tree.nodes.get("Principled BSDF")
    s.inputs["Base Color"].default_value = (*color, 1)
    s.inputs["Metallic"].default_value = metallic
    s.inputs["Roughness"].default_value = roughness
    if emission:
        s.inputs["Emission Color"].default_value = (*color, 1)
        s.inputs["Emission Strength"].default_value = emission
    return m


def palette(world):
    warm = world == "lurga"
    colors = [
        (.31,.42,.11) if warm else (.22,.40,.32),
        (.52,.30,.16) if warm else (.50,.58,.62),
        (.76,.49,.28) if warm else (.87,.93,.94),
        (.16,.28,.085) if warm else (.10,.26,.23),
        (.82,.75,.58) if warm else (.80,.86,.88),
        (.085,.12,.14), (.055,.32,.40), (.24,.75,.71),
        (.64,.40,.12), (.24,.35,.10) if warm else (.18,.40,.32),
        (.83,.69,.29) if warm else (.56,.42,.69), (.075,.32,.38),
    ]
    names = ["meadow","rock","highland","foliage","ceramic","metal","glass","light","soil","crop","flower","water"]
    return [material("bizigai_"+n, c, .55 if n in {"metal","glass"} else 0,
                     .2 if n in {"glass","water"} else .78,
                     .6 if n == "light" else 0) for n,c in zip(names,colors)]


class Mesh:
    """Small explicit mesh authoring helper; no external assets or geometry services."""
    def __init__(self, origin=None, rotation=None):
        self.vertices=[]; self.faces=[]; self.materials=[]
        self.origin=Vector(origin or (0,0,0))
        self.rotation=rotation or Matrix.Identity(3)

    def part(self, verts, faces, mat):
        base=len(self.vertices)
        self.vertices.extend(tuple(self.origin+self.rotation@Vector(v)) for v in verts)
        self.faces.extend(tuple(base+i for i in f) for f in faces)
        self.materials.extend([mat]*len(faces))

    def box(self, c, s, mat=4, rot=None):
        c=Vector(c); r=rot or Matrix.Identity(3)
        v=[tuple(c+r@Vector((x*s[0]/2,y*s[1]/2,z*s[2]/2)))
           for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        self.part(v, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)

    def cylinder(self,c,r,depth,mat=5,n=12,top=None,rot=None):
        c=Vector(c); rotation=rot or Matrix.Identity(3)
        rt=r if top is None else top
        # A tiny non-zero cap avoids degenerate cone triangles on export.
        rt=max(.001,rt)
        verts=[]
        for z,rad in [(-depth/2,r),(depth/2,rt)]:
            verts += [tuple(c+rotation@Vector((rad*math.cos(2*math.pi*i/n),rad*math.sin(2*math.pi*i/n),z))) for i in range(n)]
        faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
        faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        self.part(verts,faces,mat)

    def ball(self,c,s,mat=3,segments=12,rings=6):
        c=Vector(c); verts=[tuple(c+Vector((0,0,s[2])))]
        for j in range(1,rings):
            a=math.pi*j/rings
            for i in range(segments):
                t=2*math.pi*i/segments
                verts.append(tuple(c+Vector((s[0]*math.sin(a)*math.cos(t),s[1]*math.sin(a)*math.sin(t),s[2]*math.cos(a)))))
        bottom=len(verts); verts.append(tuple(c+Vector((0,0,-s[2]))))
        faces=[(0,1+i,1+(i+1)%segments) for i in range(segments)]
        for j in range(rings-2):
            a=1+j*segments; b=a+segments
            faces += [(a+i,b+i,b+(i+1)%segments,a+(i+1)%segments) for i in range(segments)]
        last=1+(rings-2)*segments
        faces += [(last+i,bottom,last+(i+1)%segments) for i in range(segments)]
        self.part(verts,faces,mat)

    def beam(self,a,b,width,mat=5):
        a,b=Vector(a),Vector(b); delta=b-a
        rot=Vector((0,0,1)).rotation_difference(delta.normalized()).to_matrix()
        self.box((a+b)/2,(width,width,delta.length),mat,rot)

    def ring(self,c,radius,width,mat=7,n=24):
        c=Vector(c)
        for i in range(n):
            a=2*math.pi*i/n; b=2*math.pi*(i+1)/n
            self.beam(c+Vector((radius*math.cos(a),radius*math.sin(a),0)),
                      c+Vector((radius*math.cos(b),radius*math.sin(b),0)),width,mat)

    def object(self,name,mats,collection):
        data=bpy.data.meshes.new(name)
        data.from_pydata(self.vertices,[],self.faces); data.update()
        for m in mats: data.materials.append(m)
        for p,i in zip(data.polygons,self.materials): p.material_index=i
        obj=bpy.data.objects.new(name,data); collection.objects.link(obj)
        return obj


def collection(name):
    c=bpy.data.collections.new(name); bpy.context.scene.collection.children.link(c); return c


def anchor(name,position,rotation,coll):
    obj=bpy.data.objects.new(name,None); coll.objects.link(obj)
    obj.location=position; obj.rotation_mode="QUATERNION"; obj.rotation_quaternion=rotation.to_quaternion()
    obj.empty_display_type="ARROWS"; obj.empty_display_size=1.2
    return obj


def terrain(world,n,mats,coll):
    # Six independent tiles with mathematically identical edge coordinates.
    axes=[(0,1),(0,-1),(1,1),(1,-1),(2,1),(2,-1)]
    for face,(axis,sign) in enumerate(axes):
        mesh=Mesh(); dirs=[]
        for j in range(n+1):
            for i in range(n+1):
                v=[0.,0.,0.]; v[axis]=sign
                other=[k for k in range(3) if k!=axis]
                v[other[0]]=2*i/n-1; v[other[1]]=2*j/n-1
                d=normalize(v); dirs.append(d)
                mesh.vertices.append(godot_to_blender(tuple(x*surface_radius(world,d) for x in d)))
        for j in range(n):
            for i in range(n):
                a=j*(n+1)+i; f=(a,a+1,a+n+2,a+n+1)
                p,q,r=[Vector(mesh.vertices[k]) for k in f[:3]]
                if (q-p).cross(r-p).dot(p)<0: f=tuple(reversed(f))
                mesh.faces.append(f)
                d=dirs[a]; h=surface_radius(world,d)-WORLDS[world]["radius_m"]
                if world=="lurga": color=2 if h>15 else (1 if h>10 else 0)
                else: color=2 if h>16 or abs(d[1])>.88 else (1 if h>10 else 0)
                mesh.materials.append(color)
        obj=mesh.object("terrain_%s_%d-col"%(coll.name.lower(),face),mats,coll)
        for p in obj.data.polygons: p.use_smooth=True
        obj["terrain_face"]=face


def cabin(m,x,y,size=1.0):
    # Real doorway, side/rear walls and roof, not a sealed painted box.
    m.box((x,y,.2),(8*size,6*size,.4),4)
    m.box((x-3.8*size,y,2*size),(.4,6*size,4*size),4)
    m.box((x+3.8*size,y,2*size),(.4,6*size,4*size),4)
    m.box((x,y+2.8*size,2*size),(8*size,.4,4*size),4)
    for side in [-1,1]:
        m.box((x+side*2.65*size,y-2.8*size,2*size),(2.7*size,.4,4*size),4)
        m.box((x+side*2.65*size,y-3.04*size,2.4*size),(1.6*size,.08,1.0*size),6)
    m.box((x,y-2.8*size,3.6*size),(2.7*size,.4,.8*size),4)
    m.box((x,y,4.1*size),(8.7*size,6.7*size,.5*size),5)
    m.box((x,y-3.2*size,3.6*size),(2.2*size,.16,.13),7)


def landmark(kind,world,origin,rot,mats,coll,index):
    m=Mesh(origin,rot); d=Mesh(origin,rot)
    stone=1 if world=="lurga" else 2
    # Arrival beacon is outside every structure at local (0,-13).
    d.ring((0,-13,.08),1.5,.12,7,16)
    for x in [-2.2,2.2]:
        m.cylinder((x,-13,.65),.15,1.3,5,n=6)
        d.ball((x,-13,1.4),(.27,.27,.22),7,8,4)
    if kind=="landing":
        m.cylinder((0,2,.18),8,.36,5,n=24)
        d.ring((0,2,.41),6.7,.22,7)
        for x in [-2.,2.]: d.box((x,2,.42),(.4,4,.03),4)
        d.box((0,2,.42),(4,.4,.03),4)
        cabin(m,12,4,.65)
        for x,y in [(-8,-3),(8,-3),(-8,8),(8,8)]:
            m.cylinder((x,y,1.2),.25,2.4,5,n=8); d.ball((x,y,2.5),(.35,.35,.35),7,8,4)
    elif kind=="greenhouse":
        for x in [-6,6]:
            m.box((x,2,.3),(8,10,.6),4)
            m.ball((x,2,2.7),(4,5,2.9),6,16,8)
            for y in [-1,2,5]:
                d.ring((x,y,2.8),3.0,.1,4,12)
                d.box((x,y,.8),(5,.6,.5),9)
        m.cylinder((0,9,2),1.4,4,4)
    elif kind=="observatory":
        m.cylinder((0,3,2.5),6,5,4,n=20)
        m.ball((0,3,5.4),(6,6,3),6,20,8)
        for x in [-4,4]:
            m.beam((x,3,6),(x,0,10),.65,5)
            m.cylinder((x,0,10),1.3,3,4,n=12,rot=Matrix.Rotation(.6,3,'X'))
            d.ball((x,-.7,11),(.9,.9,.7),7,12,6)
        for x in [-8,8]: m.box((x,-1,.5),(3,7,1),stone)
    elif kind=="ruins":
        for j in range(3):
            for i in range(11):
                a=math.pi*i/10; r=6+j*2
                m.box((r*math.cos(a),3+r*math.sin(a),.6+j*.45),(2.3,2.2,1.2+j*.9),stone)
        for x in [-10,10]:
            m.cylinder((x,0,3.5),.85,7,stone,n=8)
            m.box((x,0,7),(2.3,2.3,.5),stone)
        m.box((0,3,.2),(8,7,.4),stone); d.ring((0,3,.45),2.5,.2,7,12)
    elif kind=="quarry":
        for i in range(12):
            a=2*math.pi*i/12; x=7*math.cos(a); y=4+6*math.sin(a)
            m.ball((x,y,1),(2.5,2,1.6),stone,8,4)
            d.cylinder((x,y,2.5+(i%3)*.4),.7,3+(i%3),7 if i%3==0 else 10,n=5,top=.12)
        m.box((0,3,.3),(6,5,.6),5)
        for x in [-2,2]: m.box((x,3,1),(1.5,2,1.1),4)
    elif kind=="arches":
        for y in [-1,7]:
            for i in range(12):
                a=math.pi*i/12; b=math.pi*(i+1)/12
                m.beam((7*math.cos(a),y,2+7*math.sin(a)),(7*math.cos(b),y,2+7*math.sin(b)),1.5,stone)
            for x in [-7,7]: m.box((x,y,1),(1.8,2,2),stone)
        for x in [-9,9]: m.box((x,3,.3),(2,13,.6),stone)
    elif kind=="workshop":
        cabin(m,-6,4,.9)
        for x in [2,12]: m.beam((x,3,0),(x,3,8),.6,5)
        m.beam((2,3,8),(12,3,8),.8,4)
        m.beam((7,3,8),(7,3,4),.15,5)
        m.box((7,3,2),(4,5,3),4)
        for y in [0,6]: d.box((7,y,2.8),(3.2,.15,.6),7)
        for x in [2,5,8]: m.cylinder((x,9,1.3),.7,2.6,8,n=10)
    elif kind in {"water","thermal"}:
        for x,y,r in [(-5,3,4),(5,5,3.5)]:
            m.cylinder((x,y,.12),r+.6,.24,stone,n=24)
            d.cylinder((x,y,.26),r,.06,11,n=32)
            for i in range(8):
                a=i*math.pi/4
                m.ball((x+(r+.5)*math.cos(a),y+(r+.5)*math.sin(a),.3),(.6,.6,.4),stone,8,4)
        m.cylinder((0,11,2.5),1.4,5,4,n=16)
        for x in [-5,5]: m.beam((x,8,.5),(0,11,.5),.35,5)
        if kind=="thermal":
            for x in [-10,10]:
                m.cylinder((x,5,2),1,4,5,n=10)
                d.ring((x,5,3.8),1.1,.15,7,12)
    elif kind=="wind":
        for x,y in [(-7,3),(7,3),(0,10)]:
            m.cylinder((x,y,4),.3,8,5,n=8)
            for a in [0,math.pi/2,math.pi,math.pi*1.5]:
                m.beam((x,y,2),(x+2*math.cos(a),y+2*math.sin(a),4),.25,4)
                m.box((x+2*math.cos(a),y+2*math.sin(a),5.3),(.35,1.4,4.2),4,Matrix.Rotation(a,3,'Z'))
            d.ring((x,y,7.6),1.2,.13,7,12)
    elif kind=="solar":
        for x in [-8,0,8]:
            for y in [1,8]:
                m.cylinder((x,y,1.2),.25,2.4,5,n=8)
                m.box((x,y,2.5),(6.8,4.7,.24),5,Matrix.Rotation(.24,3,'X'))
                d.box((x,y,2.7),(6.4,4.3,.06),6,Matrix.Rotation(.24,3,'X'))
                for k in [-2,0,2]: d.box((x+k,y,2.82),(.06,4,.05),7)
        m.box((0,14,1.1),(5,2,2.2),4)
    elif kind=="monolith":
        for i in range(9):
            a=i*2*math.pi/9
            x,y=8*math.cos(a),3+8*math.sin(a)
            m.box((x,y,3+(i%3)*.6),(1.6,1.6,6+(i%3)*1.2),stone,Matrix.Rotation(-a,3,'Z'))
            d.box((x,y-.86,3),(.3,.06,3),7)
        m.cylinder((0,3,.7),3,1.4,stone,n=12)
        d.ball((0,3,2),(1.2,1.2,1.2),7,8,4)
    elif kind=="wreck":
        for x in [-6,-2,2,6]:
            m.cylinder((x,4,2.5),2.5,2.8,5,n=10,rot=Matrix.Rotation(math.pi/2,3,'Y'))
            d.ring((x,4,2.5),2.4,.12,8,12)
        m.box((0,4,1),(16,6,1.2),4,Matrix.Rotation(.1,3,'Y'))
        for s in [-1,1]: m.box((s*8,6,1.5),(5,9,.5),4,Matrix.Rotation(s*.4,3,'Z'))
        for x,y in [(-10,-2),(9,0),(5,11)]: m.box((x,y,.7),(3,2,1.2),5,Matrix.Rotation(.4*x,3,'Z'))
    elif kind=="camp":
        for x in [-7,7]:
            for dx in [-3,3]: m.beam((x+dx,4,0),(x+dx,4,4),.12,5)
            m.box((x,4,3.8),(7,6,.18),8,Matrix.Rotation(.16,3,'Y'))
            for y in [2,6]: m.box((x,y,.6),(3,1.5,1.2),4)
        d.ring((0,3,.15),1.7,.22,stone,12)
        for a in [0,1,2]: m.box((0,3,.4),(2,.3,.3),8,Matrix.Rotation(a,3,'Z'))
    elif kind=="farm":
        for j in range(4):
            y=j*3; z=.25+j*.2
            m.box((0,y,z),(18,2.4,.5+j*.4),stone)
            d.box((0,y,z+.3),(17,2,.1),8)
            for x in range(-7,8,2):
                d.ball((x,y,z+.7),(.5,.5,.6),9,6,4)
                d.ball((x,y,z+1.3),(.25,.25,.2),10,6,4)
        m.cylinder((12,5,2),1.4,4,4,n=12)
    elif kind=="relay":
        for x,y in [(-2,0),(2,0),(0,4)]: m.beam((x,y,0),(0,1.5,15),.35,5)
        for z in [3,6,9,12]: m.ring((0,1.5,z),2-z*.07,.17,4,6)
        m.ball((0,1.5,15),(2.5,1,2.5),6,12,6)
        d.ball((0,1.5,18),(.45,.45,.45),7,8,4)
        cabin(m,8,5,.65)
    else:
        raise ValueError("Unknown landmark kind: "+kind)
    m.object("poi_%02d_%s-col"%(index,kind),mats,coll)
    d.object("detail_%02d_%s"%(index,kind),mats,coll)


def vegetation(world,mats,coll):
    rng=random.Random(WORLDS[world]["seed"])
    trees=[Mesh() for _ in range(6)]; shrubs=[Mesh() for _ in range(6)]
    count=0
    for i in range(1200):
        y=rng.uniform(-1,1); a=rng.uniform(-math.pi,math.pi)
        d=(math.sqrt(1-y*y)*math.cos(a),y,math.sqrt(1-y*y)*math.sin(a))
        if any(dot(d,poi_direction(k)) > math.cos(30/WORLDS[world]["radius_m"]) for k in range(16)): continue
        h=surface_radius(world,d)-WORLDS[world]["radius_m"]
        if h>14 or (world=="elur" and abs(y)>.85): continue
        if math.sin(8*d[0]+2*d[2])+math.cos(7*d[1]-d[0]) < -.1: continue
        axis=max(range(3),key=lambda k:abs(d[k])); chunk=axis*2+(1 if d[axis]<0 else 0)
        pos=Vector(godot_to_blender(tuple(x*surface_radius(world,d) for x in d)))
        rot=Vector((0,0,1)).rotation_difference(Vector(godot_to_blender(d))).to_matrix()
        tree=Mesh(pos,rot); height=rng.uniform(3.8,7.5)
        tree.cylinder((0,0,height*.35),.28,height*.7,8,n=6,top=.16)
        if world=="lurga":
            tree.ball((0,0,height), (height*.62,height*.53,height*.27),3,9,5)
            tree.ball((height*.3,0,height*.86),(height*.34,height*.32,height*.2),9,8,4)
        else:
            tree.cylinder((0,0,height*.67),height*.34,height*.8,3,n=7,top=.07)
            tree.cylinder((0,0,height*.90),height*.24,height*.6,9,n=7,top=.04)
        dest=trees[chunk]; base=len(dest.vertices); dest.vertices.extend(tree.vertices)
        dest.faces.extend(tuple(base+x for x in f) for f in tree.faces); dest.materials.extend(tree.materials)
        plant=Mesh(pos,rot)
        for j in range(3):
            x,y2=rng.uniform(-3,3),rng.uniform(-3,3)
            plant.ball((x,y2,.35),(.45,.4,.45),9,6,4)
            plant.ball((x,y2,.8),(.18,.18,.18),10,6,4)
        dest=shrubs[chunk]; base=len(dest.vertices); dest.vertices.extend(plant.vertices)
        dest.faces.extend(tuple(base+x for x in f) for f in plant.faces); dest.materials.extend(plant.materials)
        count+=1
    for i,m in enumerate(trees):
        if m.vertices: m.object("grove_%d"%i,mats,coll)
    for i,m in enumerate(shrubs):
        if m.vertices: m.object("understory_%d"%i,mats,coll)
    return count


def build(world,force=False):
    source=HERE/(world+".blend")
    if source.exists() and not force:
        print("PRESERVED",source.name); return False
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system="METRIC"
    bpy.context.scene.unit_settings.scale_length=1.0
    mats=palette(world)
    for tier,n in TIERS.items(): terrain(world,n,mats,collection(tier.upper()))
    landmarks=collection("LANDMARKS")
    sockets=collection("ANCHORS")
    for i,(ident,title,kind) in enumerate(WORLDS[world]["pois"]):
        direction=poi_direction(i)
        origin=Vector(godot_to_blender(tuple(x*surface_radius(world,direction) for x in direction)))
        rot=Vector((0,0,1)).rotation_difference(Vector(godot_to_blender(direction))).to_matrix()
        landmark(kind,world,origin,rot,mats,landmarks,i)
        obj=anchor("arrival_"+ident,origin+rot@Vector((0,-13,1.1)),rot,sockets)
        obj["poi_id"]="bizigai/"+world+"/"+ident
        obj["title"]=title; obj["kind"]=kind
        anchor("focus_"+ident,origin+rot@Vector((0,3,2)),rot,sockets)
        if kind in {"quarry","farm","water","thermal"}:
            anchor("resource_"+ident,origin+rot@Vector((3,-7,.5)),rot,sockets)
    count=vegetation(world,mats,collection("VEGETATION"))
    scene=bpy.context.scene
    scene["world_id"]="bizigai/"+world; scene["habitable"]=True
    scene["radius_m"]=WORLDS[world]["radius_m"]; scene["tree_count"]=count
    # Only the detailed tier is initially visible in the editable scene.
    for name in ["APPROACH","ORBITAL"]:
        bpy.data.collections[name].hide_viewport=True; bpy.data.collections[name].hide_render=True
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
    print("CREATED",world,"trees",count)
    return True


def glb_info(path):
    data=path.read_bytes()
    magic,version,total=struct.unpack_from("<4sII",data)
    if magic!=b"glTF" or version!=2 or total!=len(data): raise ValueError("Invalid GLB")
    length,kind=struct.unpack_from("<II",data,12)
    if kind!=0x4E4F534A: raise ValueError("Missing JSON")
    doc=json.loads(data[20:20+length])
    triangles=0
    for mesh in doc.get("meshes",[]):
        for prim in mesh["primitives"]:
            acc=doc["accessors"][prim["indices"]] if "indices" in prim else doc["accessors"][prim["attributes"]["POSITION"]]
            triangles+=acc["count"]//3
    return {"triangles":triangles,"bytes":len(data),"meshes":len(doc.get("meshes",[])),"sha256":digest(path)}


def export(world):
    source=HERE/(world+".blend")
    if not source.is_file(): raise FileNotFoundError(source)
    before=digest(source)
    record={k:v for k,v in WORLDS[world].items() if k!="pois"}
    record.update({"id":"bizigai/"+world,"source":str(source.relative_to(ROOT)),"source_sha256":before,
        "axes":"+Y north/up; -Z zero longitude; +X east", "origin":[0,0,0],"units":"metres", "pois":[],"representations":{}})
    for tier in TIERS:
        bpy.ops.wm.open_mainfile(filepath=str(source))
        record["tree_count"]=int(bpy.context.scene["tree_count"])
        for c in bpy.data.collections:
            c.hide_viewport=False; c.hide_render=False
        bpy.ops.object.select_all(action="DESELECT")
        selected=[]
        for coll_name in [tier.upper(),"LANDMARKS","ANCHORS"]+(["VEGETATION"] if tier!="orbital" else []):
            for obj in list(bpy.data.collections[coll_name].objects):
                if tier!="surface" and obj.name.startswith("understory_"): continue
                if tier=="orbital" and obj.name.startswith("detail_"): continue
                obj.hide_set(False); obj.select_set(True); selected.append(obj)
                if tier!="surface" and obj.name.endswith("-col"): obj.name=obj.name[:-4]
        if tier=="surface":
            for ident,title,kind in WORLDS[world]["pois"]:
                a=bpy.data.objects["arrival_"+ident]; f=bpy.data.objects["focus_"+ident]
                record["pois"].append({"id":"bizigai/"+world+"/"+ident,"name":title,"kind":kind,
                    "arrival_node":a.name,"focus_node":f.name,
                    "arrival_m":[round(x,6) for x in blender_to_godot(a.location)],
                    "focus_m":[round(x,6) for x in blender_to_godot(f.location)],
                    "status":"modeled_location_not_gameplay"})
        RUNTIME.mkdir(parents=True,exist_ok=True)
        target=RUNTIME/(world+"_"+tier+".glb")
        bpy.ops.export_scene.gltf(filepath=str(target),export_format="GLB",use_selection=True,
            export_apply=True,export_yup=True,export_extras=True,export_animations=False,
            export_cameras=False,export_lights=False,export_materials="EXPORT")
        info=glb_info(target); info["path"]=str(target.relative_to(ROOT)); info["res_path"]="res://"+str(target.relative_to(ROOT/"game"))
        info["terrain_grid_per_face"]=TIERS[tier]
        info["collision"]="six terrain trimeshes and landmark structure trimeshes" if tier=="surface" else "none"
        record["representations"][tier]=info
        print("EXPORTED",world,tier,info["triangles"],"triangles")
    if digest(source)!=before: raise RuntimeError("Exporter changed editable source")
    return record


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("mode",choices=["build","export"])
    parser.add_argument("--force",action="store_true",help="Explicitly discard and rebuild editable sources")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else None)
    if args.mode=="build":
        created=sum(build(w,args.force) for w in WORLDS)
        print("BIZIGAI_SOURCES_PASS created=%d preserved=%d"%(created,2-created))
    else:
        manifest={"schema":"bizigai-planets","version":1,"license":"MIT","authoring":"Blender "+bpy.app.version_string,
            "provenance":"Original procedural mesh authoring; no imported art or personal data",
            "habitable_is_fictional_design":True,"worlds":[export(w) for w in WORLDS],
            "limits":["Not astronomical scale","No flight or seamless transition","No network, missions, enemies or harvest logic",
                      "Water is shallow visual basin geometry, no swimming","Vegetation has no collision","No planetary orbit or spin"]}
        (RUNTIME/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print("BIZIGAI_EXPORT_PASS worlds=2 glb=6")

if __name__=="__main__": main()
