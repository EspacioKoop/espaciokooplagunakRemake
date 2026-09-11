"""Offline regression tests for the documentary asset library. MIT."""
import importlib.util
import io
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('catalogue',ROOT/'tools/asset_library/catalogue.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)


def doc():
    return {'asset':{'version':'2.0'},'buffers':[{'byteLength':12}],
        'nodes':[{'name':'group','children':[1,2]},{'name':'part','mesh':0},{'name':'socket_grip'}],
        'meshes':[{'primitives':[{'attributes':{'POSITION':0},'indices':1,'material':0}]}],
        'accessors':[{'count':3},{'count':3}], 'materials':[{'name':'Ceramic'}],
        'animations':[{'name':'mechanical_cycle','channels':[{'target':{'node':1}}]}]}


def binary(data=None):
    raw=json.dumps(data or doc()).encode();raw+=b' '*((-len(raw))%4)
    body=struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',12,0x004e4942)+bytes(12)
    return struct.pack('<III',0x46546c67,2,len(body)+12)+body


def photograph():
    output=io.BytesIO();Image.new('RGB',(64,64),(30,80,130)).save(output,'PNG');return output.getvalue()


class CatalogueTests(unittest.TestCase):
    def test_resource_path(self):
        self.assertEqual(c.path('res://assets/models/a.glb'),'game/assets/models/a.glb')

    def test_unsafe_paths_rejected(self):
        for value in ('../secret','/etc/passwd','art/../../secret','x\\y','x\0y','https://example.org/a','x%2fsecret','.'):
            with self.subTest(value=value), self.assertRaises(ValueError):c.path(value)

    def test_path_scope(self):
        with self.assertRaises(ValueError):c.path('docs/a.blend',('art/blender/',))

    def test_unsafe_ids(self):
        for value in ('a/../b','a//b','/a','a?b','á','a b'):
            with self.subTest(value=value),self.assertRaises(ValueError):c.slug(value)

    def test_slug(self):
        self.assertEqual(c.slug('bizi/ametz/surface'),'bizi--ametz--surface')

    def test_ref_is_not_a_shell_argument(self):
        for value in ('--help','HEAD','origin/../a','https://x','$(touch /tmp/x)'):
            with self.subTest(value=value),self.assertRaises(ValueError):c.resolve(value)

    def test_blob_must_be_commit_pinned(self):
        with self.assertRaises(ValueError):c.blob('main','docs/a.md')

    def test_glb_header(self):
        self.assertEqual(c.glb(binary())['asset']['version'],'2.0')

    def test_corrupt_glb(self):
        for raw in (b'',binary()[:24],b'BAD!'+binary()[4:],binary()[:-4]):
            with self.subTest(length=len(raw)),self.assertRaises(ValueError):c.glb(raw)

    def test_external_dependency(self):
        data=doc();data['buffers'][0]['uri']='private.bin'
        with self.assertRaises(ValueError):c.glb(binary(data))

    def test_empty_geometry(self):
        data=doc();data['meshes']=[]
        with self.assertRaises(ValueError):c.glb(binary(data))

    def test_actual_photo(self):
        self.assertEqual(c.png_info(photograph()),[64,64])

    def test_non_image_is_not_a_photo(self):
        with self.assertRaises(Exception):c.png_info(b'<svg>not a model</svg>')

    def test_tiny_image_rejected(self):
        output=io.BytesIO();Image.new('RGB',(1,1)).save(output,'PNG')
        with self.assertRaises(ValueError):c.png_info(output.getvalue())

    def test_group_stats(self):
        result=c.stats(doc(),'group')
        self.assertEqual(result['triangles'],1)
        self.assertEqual(result['materials'],['Ceramic'])
        self.assertEqual(result['sockets'],['socket_grip'])
        self.assertEqual(result['animations_gltf'],['mechanical_cycle'])

    def test_missing_group_rejected(self):
        with self.assertRaises(ValueError):c.stats(doc(),'unknown')

    def test_duplicate_group_rejected(self):
        data=doc();data['nodes'].append({'name':'group'})
        with self.assertRaises(ValueError):c.selected_nodes(data,'group')

    def test_child_cycle_rejected(self):
        data=doc();data['nodes'][1]['children']=[0]
        with self.assertRaises(ValueError):c.selected_nodes(data,'group')

    def test_out_of_bounds_child_rejected(self):
        data=doc();data['nodes'][0]['children']=[900]
        with self.assertRaises(ValueError):c.selected_nodes(data,'group')

    def test_triangles_not_lines(self):
        data=doc();data['meshes'][0]['primitives'][0]['mode']=1
        with self.assertRaises(ValueError):c.stats(data)

    def test_base_adapter(self):
        spec={'id':'base','adapter':'base','models':['crate'],'expected_count':1,
            'manifest':'game/assets/models/manifest.json','source':'art/blender/base.blend'}
        result=c.records(spec,{'models':[{'name':'crate','file':'crate.glb'}]})
        self.assertEqual(result[0][0]['id'],'base/crate')
        self.assertEqual(result[0][0]['source_id'],'crate')
        self.assertEqual(result[0][1],'/models/0')

    def test_frontier_adapter_preserves_original_id(self):
        spec={'id':'frontier','manifest':'game/assets/models/frontier_pack/manifest.json'}
        data={'assets':[{'id':'ship','source':'art/blender/a.blend','glb':'res://assets/models/frontier_pack/ship.glb'}]}
        entry,pointer=c.records(spec,data)[0]
        self.assertEqual(entry['id'],'frontier/ship')
        self.assertEqual(entry['source_id'],'ship')
        self.assertEqual(entry['runtime'],'game/assets/models/frontier_pack/ship.glb')

    def test_named_submodel_adapter(self):
        spec={'id':'memory','adapter':'groups','groups':['keeper'],'runtime':'game/assets/models/m.glb','source':'art/blender/m.blend'}
        entry,pointer=c.records(spec,{'submodels':['keeper']})[0]
        self.assertEqual(entry['group'],'keeper');self.assertEqual(pointer,'/submodels/0')

    def test_adapter_does_not_invent_manifest_pointer(self):
        spec={'id':'leisure','adapter':'groups','groups':['beach'],'runtime':'game/assets/models/l.glb','source':'art/blender/l.blend'}
        self.assertIsNone(c.records(spec,{'models':[]})[0][1])

    def test_missing_manifest_entries(self):
        with self.assertRaises(ValueError):c.records({'id':'test'}, {'assets':[]})

    def test_wrong_pack_count(self):
        spec={'id':'x','expected_count':2,'manifest':'game/assets/models/m.json'}
        with self.assertRaises(ValueError):c.records(spec,{'assets':[{'id':'x/a','runtime':'game/assets/models/a.glb'}]})

    def test_habitable_category(self):
        self.assertEqual(c.category({'id':'bizi/a','category':'habitable_planets'}),'planets')

    def test_html_escaped(self):
        value=c.text('<img onerror="bad">|\n')
        self.assertNotIn('<img',value);self.assertNotIn('|',value)

    def test_sources_have_individual_packs(self):
        data=json.loads((ROOT/'tools/asset_library/sources.json').read_text())
        ids=[p['id'] for p in data['packs']]
        self.assertEqual(len(ids),len(set(ids)))
        self.assertIn('itsasargi',ids);self.assertIn('fieldkit',ids);self.assertIn('bizi',ids)

    def test_existing_photo_is_pinned(self):
        entry={'id':'tools/a','preview':'docs/images/tools/a.png'}
        with patch.object(c,'exists',return_value=True),patch.object(c,'blob',return_value=photograph()):
            preview=c.photo(entry,{},'a'*40,binary(),False)
        self.assertIn('/'+'a'*40+'/',preview['url'])

    def test_absent_photo_fails_closed(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(c,'ROOT',Path(folder)),patch.object(c,'exists',return_value=False):
            with self.assertRaisesRegex(ValueError,'individual photo'):c.photo({'id':'p/a'},{},'a'*40,binary(),False)

    def test_overview_is_not_individual_photo(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(c,'ROOT',Path(folder)),patch.object(c,'exists',return_value=True):
            with self.assertRaisesRegex(ValueError,'individual photo'):
                c.photo({'id':'p/a','preview':'docs/images/p/overview.png'},{},'a'*40,binary(),False)

if __name__=='__main__':unittest.main()
