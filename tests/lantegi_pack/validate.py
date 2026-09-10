"""Offline Lantegi GLB validation, also reusable by Aterpe. No Blender required."""
from __future__ import annotations
import copy
import hashlib
import json
import math
import struct
import unittest
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[2]
DTYPES = {5120: '<i1', 5121: '<u1', 5122: '<i2', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT2': 4, 'MAT3': 9, 'MAT4': 16}


def require(value, message):
    if not value:
        raise ValueError(message)


def decode(data):
    require(len(data) >= 20, 'Truncated GLB')
    require(struct.unpack_from('<III', data) == (0x46546C67, 2, len(data)), 'GLB header')
    chunks, at = [], 12
    while at < len(data):
        require(at + 8 <= len(data), 'Truncated chunk header')
        size, kind = struct.unpack_from('<II', data, at)
        at += 8
        require(size % 4 == 0 and at + size <= len(data), 'Invalid chunk bounds')
        chunks.append((kind, data[at:at + size]))
        at += size
    require(len(chunks) == 2 and chunks[0][0] == 0x4E4F534A and chunks[1][0] == 0x004E4942, 'GLB chunks')
    doc = json.loads(chunks[0][1])
    binary = chunks[1][1]
    require(doc.get('asset', {}).get('version') == '2.0', 'glTF version')
    require(len(doc.get('buffers', [])) == 1, 'Expected one embedded buffer')
    require('uri' not in doc['buffers'][0], 'External buffer')
    size = doc['buffers'][0]['byteLength']
    require(0 <= len(binary) - size <= 3, 'BIN length')
    require(not doc.get('images') and not doc.get('textures'), 'Unexpected textures')
    return doc, binary[:size]


def accessor(doc, binary, index):
    require(isinstance(index, int) and 0 <= index < len(doc.get('accessors', [])), 'Accessor index')
    a = doc['accessors'][index]
    require('sparse' not in a and 'bufferView' in a, 'Unsupported accessor encoding')
    vi = a['bufferView']
    require(0 <= vi < len(doc['bufferViews']), 'Buffer view index')
    view = doc['bufferViews'][vi]
    require(view.get('buffer', 0) == 0, 'Buffer index')
    start, size = view.get('byteOffset', 0), view['byteLength']
    require(start >= 0 and size >= 0 and start + size <= len(binary), 'Buffer view bounds')
    require(a['componentType'] in DTYPES and a['type'] in WIDTHS, 'Accessor type')
    dtype, width = np.dtype(DTYPES[a['componentType']]), WIDTHS[a['type']]
    stride = view.get('byteStride', width * dtype.itemsize)
    count, offset = a['count'], a.get('byteOffset', 0)
    require(isinstance(count, int) and count > 0 and offset >= 0, 'Accessor count/offset')
    require(stride >= width * dtype.itemsize and stride % dtype.itemsize == 0, 'Accessor stride')
    require(offset + (count - 1) * stride + width * dtype.itemsize <= size, 'Accessor bounds')
    array = np.ndarray((count, width), dtype=dtype, buffer=binary,
                       offset=start + offset, strides=(stride, dtype.itemsize)).copy()
    require(np.isfinite(array).all(), 'Non-finite accessor')
    return array


def validate_blob(data):
    doc, binary = decode(data)
    for i in range(len(doc.get('accessors', []))):
        accessor(doc, binary, i)
    triangles = 0
    for mesh in doc.get('meshes', []):
        for p in mesh['primitives']:
            require(p.get('mode', 4) == 4, 'Non-triangle primitive')
            pos = accessor(doc, binary, p['attributes']['POSITION'])
            require(pos.shape[1] == 3, 'Position width')
            indices = accessor(doc, binary, p['indices']).ravel()
            require(np.issubdtype(indices.dtype, np.integer), 'Index type')
            require(len(indices) % 3 == 0 and len(indices) > 0, 'Index cardinality')
            require(indices.min() >= 0 and indices.max() < len(pos), 'Index outside positions')
            t = pos[indices.astype(int)].reshape((-1, 3, 3)).astype(float)
            cross = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
            require((np.einsum('ij,ij->i', cross, cross) > 1e-24).all(), 'Degenerate triangle')
            normal = accessor(doc, binary, p['attributes']['NORMAL'])
            require(normal.shape == pos.shape, 'Normal shape')
            lengths = np.linalg.norm(normal, axis=1)
            require(((lengths > .9) & (lengths < 1.1)).all(), 'Invalid normals')
            require(0 <= p['material'] < len(doc.get('materials', [])), 'Material index')
            triangles += len(indices) // 3
    require(triangles > 0, 'Empty geometry')
    nodes = doc.get('nodes', [])
    parents = {}
    for i, node in enumerate(nodes):
        for child in node.get('children', []):
            require(0 <= child < len(nodes) and child not in parents, 'Invalid hierarchy')
            parents[child] = i
        for key in ('translation', 'rotation', 'scale', 'matrix'):
            require(all(math.isfinite(v) for v in node.get(key, [])), 'Non-finite transform')
    for i in range(len(nodes)):
        seen, current = set(), i
        while current in parents:
            require(current not in seen, 'Hierarchy cycle')
            seen.add(current)
            current = parents[current]
    for anim in doc.get('animations', []):
        for sampler in anim['samplers']:
            times = accessor(doc, binary, sampler['input']).ravel()
            require(len(times) > 1 and (np.diff(times) > 0).all(), 'Animation times')
            values = accessor(doc, binary, sampler['output'])
            factor = 3 if sampler.get('interpolation') == 'CUBICSPLINE' else 1
            require(len(values) == len(times) * factor, 'Animation value count')
        for channel in anim['channels']:
            require(0 <= channel['target']['node'] < len(nodes), 'Animation node')
            require(0 <= channel['sampler'] < len(anim['samplers']), 'Animation sampler')
    return doc, triangles


def encode(doc, binary):
    text = json.dumps(doc, separators=(',', ':')).encode()
    text += b' ' * (-len(text) % 4)
    binary += b'\0' * (-len(binary) % 4)
    return (struct.pack('<III', 0x46546C67, 2, 28 + len(text) + len(binary))
            + struct.pack('<II', len(text), 0x4E4F534A) + text
            + struct.pack('<II', len(binary), 0x004E4942) + binary)


def fixture():
    binary = struct.pack('<18f3H', 0, 0, 0, 1, 0, 0, 0, 1, 0,
                         0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 2)
    doc = {'asset': {'version': '2.0'}, 'buffers': [{'byteLength': len(binary)}],
           'bufferViews': [{'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
                           {'buffer': 0, 'byteOffset': 36, 'byteLength': 36},
                           {'buffer': 0, 'byteOffset': 72, 'byteLength': 6}],
           'accessors': [{'bufferView': 0, 'componentType': 5126, 'type': 'VEC3', 'count': 3},
                         {'bufferView': 1, 'componentType': 5126, 'type': 'VEC3', 'count': 3},
                         {'bufferView': 2, 'componentType': 5123, 'type': 'SCALAR', 'count': 3}],
           'meshes': [{'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1}, 'indices': 2, 'material': 0}]}],
           'materials': [{}], 'nodes': [{'mesh': 0}], 'scenes': [{'nodes': [0]}], 'scene': 0}
    return doc, binary


class NegativeTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(validate_blob(encode(*fixture()))[1], 1)

    def test_truncated(self):
        with self.assertRaises(ValueError): validate_blob(encode(*fixture())[:-1])

    def test_magic(self):
        with self.assertRaises(ValueError): validate_blob(b'nope' + encode(*fixture())[4:])

    def test_external(self):
        d, b = fixture(); d['buffers'][0]['uri'] = 'forbidden.bin'
        with self.assertRaises(ValueError): validate_blob(encode(d, b))

    def test_bounds(self):
        d, b = fixture(); d['accessors'][0]['count'] = 30000
        with self.assertRaises(ValueError): validate_blob(encode(d, b))

    def test_nan(self):
        d, b = fixture(); b = struct.pack('<f', float('nan')) + b[4:]
        with self.assertRaises(ValueError): validate_blob(encode(d, b))

    def test_index(self):
        d, b = fixture(); b = b[:-2] + struct.pack('<H', 300)
        with self.assertRaises(ValueError): validate_blob(encode(d, b))

    def test_degenerate(self):
        d, b = fixture(); b = b[:-2] + struct.pack('<H', 0)
        with self.assertRaises(ValueError): validate_blob(encode(d, b))

    def test_cycle(self):
        d, b = fixture(); d['nodes'][0]['children'] = [0]
        with self.assertRaises(ValueError): validate_blob(encode(d, b))

    def test_stride(self):
        d, b = fixture(); d['bufferViews'][0]['byteStride'] = 1
        with self.assertRaises(ValueError): validate_blob(encode(d, b))

    def test_material(self):
        d, b = fixture(); d['meshes'][0]['primitives'][0]['material'] = 5
        with self.assertRaises(ValueError): validate_blob(encode(d, b))


def main():
    manifest = json.loads((ROOT / 'game/assets/models/lantegi_pack/manifest.json').read_text())
    entries = manifest['assets']
    require(len(entries) == 10, 'Expected ten Lantegi models')
    require([sum(e['category'] == k for e in entries) for k in ['tools', 'weapons', 'ships']] == [6, 2, 2], 'Category count')
    require(len({e['id'] for e in entries}) == 10, 'Duplicate ID')
    total, anchors = 0, 0
    for e in entries:
        for path_key, hash_key in [('source', 'source_sha256'), ('runtime', 'runtime_sha256')]:
            path = ROOT / e[path_key]
            require(path.is_file(), 'Missing ' + str(path))
            require(hashlib.sha256(path.read_bytes()).hexdigest() == e[hash_key], 'Stale hash ' + str(path))
        data = (ROOT / e['runtime']).read_bytes()
        doc, tris = validate_blob(data)
        require(tris == e['triangles'] and tris < 60000, 'Triangle budget/count')
        require(len(data) == e['bytes'] and len(data) < 12000000, 'Byte budget/count')
        actual = [n['name'] for n in doc['nodes'] if n.get('name', '').startswith('socket_')]
        require(set(actual) == {s['name'] for s in e['sockets']} and len(actual) == len(set(actual)), 'Sockets')
        require(len(actual) >= 3, 'Missing anchors')
        require(e['animations'] and e['animations'] == [a['name'] for a in doc.get('animations', [])], 'Missing animation')
        require(any(n.get('extras', {}).get('asset_id') == e['id'] for n in doc['nodes']), 'Asset root metadata')
        require(all(math.isfinite(x) and x > 0 for x in e['dimensions']), 'Dimensions')
        require((ROOT / e['preview']).is_file(), 'Missing preview')
        total += tris
        anchors += len(actual)
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(NegativeTests))
    require(result.wasSuccessful(), 'Negative fixtures failed')
    proof = {'models': len(entries), 'triangles': total, 'sockets': anchors, 'validator_tests': result.testsRun}
    output = ROOT / 'build/lantegi'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'validation.json').write_text(json.dumps(proof, indent=2) + '\n')
    print('LANTEGI_VALIDATE_PASS', proof)


if __name__ == '__main__':
    main()
