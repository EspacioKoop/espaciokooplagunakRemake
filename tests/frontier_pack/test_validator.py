"""Negative regression tests for the binary/library validation contract."""
from __future__ import annotations
import copy
import hashlib
import json
import struct
import tempfile
import unittest
from pathlib import Path
import validate_pack as validator

ROOT=Path(__file__).resolve().parents[2]
MODELS=ROOT/'game/assets/models/frontier_pack'


class ValidatorRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.entry=json.loads((MODELS/'manifest.json').read_text())['assets'][0]
        cls.path=MODELS/(cls.entry['id']+'.glb')
        cls.document,cls.binary,cls.raw=validator.load_glb(cls.path)

    def temporary_glb(self,raw):
        folder=tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        path=Path(folder.name)/'asset.glb'
        path.write_bytes(raw)
        return path

    def test_valid_asset(self):
        self.assertEqual(validator.validate_asset(self.path,self.entry)['status'],'passed')

    def test_truncated_header(self):
        with self.assertRaises(ValueError):
            validator.load_glb(self.temporary_glb(b'glTF'))

    def test_wrong_magic(self):
        with self.assertRaises(ValueError):
            validator.load_glb(self.temporary_glb(b'FAIL'+self.raw[4:]))

    def test_wrong_total_size(self):
        damaged=bytearray(self.raw)
        struct.pack_into('<I',damaged,8,len(damaged)+12)
        with self.assertRaises(ValueError):
            validator.load_glb(self.temporary_glb(damaged))

    def test_chunk_exceeds_file(self):
        damaged=bytearray(self.raw)
        struct.pack_into('<I',damaged,12,len(damaged)*2)
        with self.assertRaises(ValueError):
            validator.load_glb(self.temporary_glb(damaged))

    def test_corrupt_hash(self):
        entry=dict(self.entry,sha256='0'*64)
        with self.assertRaisesRegex(ValueError,'SHA-256'):
            validator.validate_asset(self.path,entry)

    def test_missing_socket(self):
        entry=dict(self.entry,sockets=self.entry['sockets']+['Socket_NotPresent'])
        with self.assertRaisesRegex(ValueError,'socket'):
            validator.validate_asset(self.path,entry)

    def test_triangle_manifest_mismatch(self):
        entry=dict(self.entry,triangles=self.entry['triangles']+1)
        with self.assertRaisesRegex(ValueError,'Triangle manifest'):
            validator.validate_asset(self.path,entry)

    def test_accessor_out_of_range(self):
        for index in [-1,len(self.document['accessors'])]:
            with self.subTest(index=index),self.assertRaises(ValueError):
                validator.accessor(self.document,self.binary,index)

    def test_accessor_buffer_overflow(self):
        document=copy.deepcopy(self.document)
        document['accessors'][0]['count']=10**9
        with self.assertRaises(ValueError):
            validator.accessor(document,self.binary,0)

    def test_accessor_invalid_stride(self):
        document=copy.deepcopy(self.document)
        view=document['accessors'][0]['bufferView']
        document['bufferViews'][view]['byteStride']=1
        with self.assertRaises(ValueError):
            validator.accessor(document,self.binary,0)

    def test_reject_nonfinite_vertex(self):
        document=copy.deepcopy(self.document)
        index=next(i for i,a in enumerate(document['accessors']) if a['componentType']==5126)
        item=document['accessors'][index]
        view=document['bufferViews'][item['bufferView']]
        offset=view.get('byteOffset',0)+item.get('byteOffset',0)
        binary=bytearray(self.binary)
        struct.pack_into('<f',binary,offset,float('nan'))
        with self.assertRaisesRegex(ValueError,'Non-finite'):
            validator.accessor(document,binary,index)

    def test_reject_source_path_traversal(self):
        manifest=json.loads((MODELS/'manifest.json').read_text())
        manifest['assets'][0]['source']='../../private-file.blend'
        with tempfile.TemporaryDirectory() as folder:
            target=Path(folder)/'game/assets/models/frontier_pack'
            target.mkdir(parents=True)
            (target/'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError,'Unexpected source path'):
                validator.validate(Path(folder))

    def test_reject_duplicate_ids(self):
        manifest=json.loads((MODELS/'manifest.json').read_text())
        manifest['assets'][1]['id']=manifest['assets'][0]['id']
        with tempfile.TemporaryDirectory() as folder:
            target=Path(folder)/'game/assets/models/frontier_pack'
            target.mkdir(parents=True)
            (target/'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError,'Duplicate'):
                validator.validate(Path(folder))


if __name__=='__main__':
    unittest.main(verbosity=2)
