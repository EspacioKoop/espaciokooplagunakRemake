"""Offline geometry contracts and real Godot integration for Egonaldi. MIT."""
from __future__ import annotations
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/egonaldi'
ASSETS=ROOT/'game/assets/models/egonaldi_pack'
spec=importlib.util.spec_from_file_location('glb_validation',ROOT/'tests/bizigai_pack/validate.py')
glb=importlib.util.module_from_spec(spec);spec.loader.exec_module(glb)


def path_under_root(path):
 p=(ROOT/path).resolve()
 glb.require(p.is_relative_to(ROOT.resolve()),'Path escapes repository')
 return p


def validate():
 data=json.loads((ASSETS/'manifest.json').read_text(encoding='utf-8'))
 glb.require(data.get('schema')=='egonaldi-destinations' and data.get('version')==1,'Manifest schema')
 glb.require(len(data.get('assets',[]))==6,'Environment count')
 ids=set();total=0
 for entry in data['assets']:
  glb.require(entry['id'] not in ids,'Duplicate ID');ids.add(entry['id'])
  source=path_under_root(entry['source']);runtime=path_under_root(entry['runtime']);preview=path_under_root(entry['preview'])
  for path,key in [(source,'source_sha256'),(runtime,'sha256'),(preview,'preview_sha256')]:
   glb.require(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==entry[key],'Missing or mismatched delivery file')
  glb.require(source.stat().st_size>5000,'Editable source is empty')
  doc,binary=glb.read_glb(runtime.read_bytes())
  triangles,_,_=glb.geometry(doc,binary)
  glb.require(triangles==entry['triangles'] and 500<triangles<100000,'Geometry budget')
  glb.require(runtime.stat().st_size==entry['bytes'],'GLB bytes')
  nodes={n.get('name'):n for n in doc.get('nodes',[])}
  glb.require(len(nodes)==len(doc.get('nodes',[])),'Duplicate node names')
  glb.require(len(entry['sockets'])==8,'Socket count')
  for name,pos in entry['sockets'].items():
   glb.require(name in nodes,'Missing socket')
   actual=nodes[name].get('translation',[0,0,0])
   glb.require(max(abs(a-b) for a,b in zip(actual,pos))<.002,'Socket coordinate drift')
  glb.require(sum(n.endswith('-col') for n in nodes if n)>=7,'Missing collision meshes')
  from PIL import Image
  with Image.open(preview) as image:
   glb.require(image.size==(1200,900),'Preview dimensions');image.verify()
  total+=triangles
 print('EGONALDI_GEOMETRY_PASS assets=6 sockets=48 triangles=%d'%total)
 return data


class NegativeTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.raw=(ASSETS/'itun_embassy.glb').read_bytes();cls.doc,cls.binary=glb.read_glb(cls.raw)
 def test_truncation(self):
  with self.assertRaises(ValueError):glb.read_glb(self.raw[:-4])
 def test_magic(self):
  with self.assertRaises(ValueError):glb.read_glb(b'FAIL'+self.raw[4:])
 def test_index(self):
  with self.assertRaises(ValueError):glb.accessor(self.doc,self.binary,999999)
 def test_offset(self):
  d=copy.deepcopy(self.doc);d['accessors'][0]['byteOffset']=len(self.binary)+100
  with self.assertRaises(ValueError):glb.accessor(d,self.binary,0)
 def test_stride(self):
  d=copy.deepcopy(self.doc);d['bufferViews'][d['accessors'][0]['bufferView']]['byteStride']=1
  with self.assertRaises(ValueError):glb.accessor(d,self.binary,0)
 def test_path(self):
  with self.assertRaises(ValueError):path_under_root('../../escape')
 def test_external_absolute(self):
  with self.assertRaises(ValueError):path_under_root('/outside_asset_root')


def run(name,command,timeout=300):
 result=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
 (OUT/(name+'.log')).write_text(result.stdout,encoding='utf-8')
 print(result.stdout)
 if result.returncode or re.search(r'SCRIPT ERROR:|^ERROR:|Parse Error:|EGONALDI_TEST_FAIL:',result.stdout,re.MULTILINE):
  raise RuntimeError(name+' failed')
 if name!='import' and 'EGONALDI_GODOT_PASS' not in result.stdout:raise RuntimeError('Missing success marker')


def main():
 OUT.mkdir(parents=True,exist_ok=True)
 data=validate()
 result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(NegativeTests))
 if not result.wasSuccessful():raise SystemExit(1)
 if '--validate-only' in sys.argv:return
 godot=str(ROOT/'.toolchain/godot');game=str(ROOT/'game');script=str(ROOT/'tests/egonaldi_pack/test_lab.gd')
 run('import',[godot,'--headless','--editor','--path',game,'--quit'],420)
 run('headless',[godot,'--headless','--path',game,'--audio-driver','Dummy','--script',script])
 run('graphical',['xvfb-run','-a',godot,'--path',game,'--rendering-method','gl_compatibility','--audio-driver','Dummy','--script',script,'--','--capture'])
 from PIL import Image,ImageStat
 for entry in data['assets']:
  ident=entry['id'].split('/')[1]
  for suffix in ['overview','walk']:
   path=ROOT/'docs/images/egonaldi_pack'/(ident+'_'+suffix+'.png')
   with Image.open(path) as image:
    glb.require(image.size==(1600,900),'Godot capture dimensions')
    glb.require(max(ImageStat.Stat(image.convert('RGB')).stddev)>10,'Blank capture')
 print('EGONALDI_RUNTIME_PASS assets=6 captures=12 renders=6 negative_tests=7')

if __name__=='__main__':main()
