"""Local synthetic Git fixtures; never read player data or call a remote."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('repository_inventory', ROOT / 'tools/repository_inventory.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


def make_glb(document):
    raw = json.dumps(document).encode()
    raw += b' ' * (-len(raw) % 4)
    return struct.pack('<4sII', b'glTF', 2, 20 + len(raw)) + struct.pack('<II', len(raw), 0x4E4F534A) + raw


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / 'repo'
        self.repo.mkdir()
        self.env = {**os.environ, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull,
                    'GIT_AUTHOR_NAME': 'Synthetic', 'GIT_COMMITTER_NAME': 'Synthetic',
                    'GIT_AUTHOR_EMAIL': 'synthetic@example.invalid', 'GIT_COMMITTER_EMAIL': 'synthetic@example.invalid'}
        self.command('init', '-q')
        (self.repo / 'code.py').write_text('def safe():\n    return 3\n')
        (self.repo / 'data.json').write_text('{"enabled":true}\n')
        (self.repo / 'binary.dat').write_bytes(b'\0\xff\x01')
        self.command('add', '--all')
        self.command('commit', '-qm', 'Synthetic fixture')
        self.sha = self.command('rev-parse', 'HEAD').decode().strip()

    def command(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], env=self.env, stderr=subprocess.PIPE)

    def test_complete_deterministic_inventory_and_hashes(self):
        value = m.inventory(self.repo)
        self.assertEqual(value, m.inventory(self.repo))
        self.assertEqual(value['source_commit'], self.sha)
        self.assertEqual(value['coverage']['tracked_entries'], 3)
        self.assertTrue(value['coverage']['all_tracked_blobs_read'])
        self.assertFalse(value['coverage']['semantic_review'])
        self.assertFalse(value['coverage']['runtime_validation'])
        code = next(x for x in value['files'] if x['path'] == 'code.py')
        self.assertEqual(code['python_syntax'], 'valid')
        self.assertEqual(code['symbols'], ['safe'])
        self.assertEqual(code['sha256'], hashlib.sha256((self.repo / 'code.py').read_bytes()).hexdigest())

    def test_dirty_and_untracked_data_are_not_read(self):
        before = m.inventory(self.repo)
        (self.repo / 'private-untracked.txt').write_text('SYNTHETIC_NOT_FOR_OUTPUT')
        (self.repo / 'code.py').write_text('SYNTHETIC_WORKTREE_NOT_FOR_OUTPUT')
        self.assertEqual(before, m.inventory(self.repo))
        self.assertNotIn('SYNTHETIC_', json.dumps(m.inventory(self.repo)))

    def test_symlink_target_is_never_followed(self):
        secret = Path(self.temp.name) / 'synthetic-external.txt'
        secret.write_text('SYNTHETIC_EXTERNAL_DATA_MUST_NOT_APPEAR')
        os.symlink(secret, self.repo / 'link')
        self.command('add', 'link')
        self.command('commit', '-qm', 'Synthetic symlink')
        value = m.inventory(self.repo)
        link = next(x for x in value['files'] if x['path'] == 'link')
        self.assertEqual(link['kind'], 'symlink-not-followed')
        self.assertEqual(link['sha256'], hashlib.sha256(str(secret).encode()).hexdigest())
        self.assertNotIn('SYNTHETIC_EXTERNAL_DATA', json.dumps(value))

    def test_revision_injection_rejected_before_git(self):
        for ref in ('--all', 'HEAD;echo', '../private', 'main..other', 'HEAD^{tree}', ''):
            with self.subTest(ref=ref), patch.object(m, 'git') as call:
                with self.assertRaises(m.InventoryError):
                    m.inventory(self.repo, ref)
                call.assert_not_called()

    def test_missing_commit_fails_without_fetch(self):
        with self.assertRaises(m.InventoryError):
            m.inventory(self.repo, '0' * 40)
        self.assertFalse((self.repo / '.git/FETCH_HEAD').exists())

    def test_size_limit_does_not_return_a_partial_success(self):
        with patch.object(m, 'MAX_TOTAL_BYTES', 1), self.assertRaises(m.InventoryError):
            m.inventory(self.repo)

    def test_gitlink_is_reported_not_expanded(self):
        self.command('update-index', '--add', '--cacheinfo', '160000', self.sha, 'dependency')
        self.command('commit', '-qm', 'Synthetic gitlink')
        value = m.inventory(self.repo)
        self.assertFalse(value['coverage']['all_tracked_blobs_read'])
        self.assertEqual(value['kinds']['gitlink-not-expanded'], 1)
        self.assertFalse((self.repo / 'dependency').exists())

    def test_git_transport_is_disabled_and_errors_are_redacted(self):
        fake = subprocess.CompletedProcess([], 1, b'PRIVATE_STDOUT', b'PRIVATE_STDERR')
        with patch.object(m.subprocess, 'run', return_value=fake) as call:
            with self.assertRaises(m.InventoryError) as exc:
                m.git(self.repo, 'rev-parse', 'HEAD')
            self.assertNotIn('PRIVATE', str(exc.exception))
            args, kwargs = call.call_args
            self.assertIn('protocol.allow=never', args[0])
            self.assertEqual(kwargs['env']['GIT_NO_LAZY_FETCH'], '1')
            self.assertEqual(kwargs['env']['GIT_CONFIG_GLOBAL'], os.devnull)
            self.assertNotIn('shell', kwargs)

    def test_truncated_blob_batch_fails(self):
        original = m.git
        def truncated(repo, *args, **kwargs):
            result = original(repo, *args, **kwargs)
            return result[:-1] if args[0] == 'cat-file' else result
        with patch.object(m, 'git', side_effect=truncated), self.assertRaises(m.InventoryError):
            m.inventory(self.repo)

    def test_cli_success_and_error(self):
        command = ['python3', str(ROOT / 'tools/repository_inventory.py'), '--repo', str(self.repo)]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['source_commit'], self.sha)
        result = subprocess.run(command + ['--revision', 'missing'], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')


class BlobTests(unittest.TestCase):
    def test_valid_container_and_external_uri_count(self):
        value = m.inspect_glb(make_glb({'asset': {'version': '2.0'}, 'meshes': [{}], 'nodes': [{}, {}],
                                      'buffers': [{'uri': 'texture.bin'}, {'uri': 'data:application/octet-stream,AA'}]}))
        self.assertEqual(value, {'structure': 'valid', 'chunks': 1, 'meshes': 1, 'nodes': 2, 'external_uris': 1})

    def test_invalid_glb_not_marked_valid(self):
        good = make_glb({'asset': {'version': '2.0'}})
        for data in (b'', b'not a model', good[:-1], good + b'bad', make_glb([]),
                     good[:4] + struct.pack('<I', 1) + good[8:]):
            with self.subTest(data=data[:12]):
                self.assertEqual(m.inspect_glb(data)['structure'], 'invalid')

    def test_python_and_json_invalid_syntax(self):
        self.assertEqual(m.inspect_blob('bad.py', b'def broken(')['python_syntax'], 'invalid')
        for raw in (b'{', b'{"value":NaN}'):
            self.assertEqual(m.inspect_blob('bad.json', raw)['json_syntax'], 'invalid')

    def test_unicode_binary_and_empty_files(self):
        self.assertEqual(m.inspect_blob('text.md', 'niñez\n'.encode())['lines'], 1)
        self.assertEqual(m.inspect_blob('blob', b'\0')['kind'], 'binary')
        self.assertEqual(m.inspect_blob('empty', b'')['bytes'], 0)

    def test_lfs_is_not_downloaded(self):
        raw = b'version https://git-lfs.github.com/spec/v1\noid sha256:0000\nsize 3\n'
        self.assertEqual(m.inspect_blob('model.glb', raw)['kind'], 'lfs-pointer-not-downloaded')

    def test_godot_symbols_references_and_png_dimensions(self):
        value = m.inspect_blob('test.gd', b'class_name Example\nstatic func run():\n var t = preload("res://a.tscn")\n')
        self.assertEqual(value['symbols'], ['Example', 'run'])
        self.assertEqual(value['references'], ['res://a.tscn'])
        png = b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', 4, 5)
        self.assertEqual(m.inspect_blob('image.png', png)['image_size'], [4, 5])


if __name__ == '__main__':
    unittest.main()
