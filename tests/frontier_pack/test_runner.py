"""Synthetic process and evidence regressions; not a substitute for real Godot."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
import run_godot as runner

RESULT = {'checks': 293, 'failures': [], 'assets': 24, 'passed': True}
def output(value=RESULT):
    return 'FRONTIER_GODOT_RESULT ' + json.dumps(value) + '\n'


class RunnerTests(unittest.TestCase):
    def test_valid_result_and_ansi(self):
        self.assertEqual(runner.decode_result(output()), RESULT)
        self.assertEqual(runner.decode_result('\x1b[32m' + output().strip() + '\x1b[0m\r\n'), RESULT)

    def test_inconsistent_result(self):
        for key, bad in [('checks', 0), ('checks', True), ('checks', 2.5), ('checks', '293'),
                         ('assets', 23), ('assets', True), ('failures', ['failed']),
                         ('failures', None), ('failures', {}), ('passed', False), ('passed', 1)]:
            with self.subTest(key=key, bad=bad), self.assertRaises(RuntimeError):
                runner.decode_result(output(dict(RESULT, **{key: bad})))

    def test_missing_duplicate_and_malformed_results(self):
        cases = ['', output() * 2, output() + 'FRONTIER_GODOT_RESULT broken',
                 'FRONTIER_GODOT_RESULT {', output([]), output(dict(RESULT, extra=True)),
                 'FRONTIER_GODOT_RESULT {"checks":1,"checks":293,"assets":24,"passed":true,"failures":[]}']
        for text in cases:
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                runner.decode_result(text)

    def execute_python(self, code, timeout=5):
        with contextlib.redirect_stdout(io.StringIO()):
            return runner.execute([sys.executable, '-c', code], os.environ.copy(), timeout)

    def test_real_synthetic_subprocess_positive(self):
        self.assertEqual(self.execute_python('print("fixture")'), 'fixture\n')

    def test_first_indented_and_ansi_errors_override_zero_exit(self):
        for prefix in ['ERROR:', '  ERROR:', 'SCRIPT ERROR:', 'USER ERROR:', 'FATAL:',
                       'FATAL ERROR:', '\x1b[31mERROR:\x1b[0m', 'FRONTIER_TEST_FAIL:']:
            with self.subTest(prefix=prefix), self.assertRaises(RuntimeError):
                self.execute_python('print(' + repr(prefix + ' fixture\n' + output()) + ')')

    def test_nonzero_process(self):
        with self.assertRaises(RuntimeError):
            self.execute_python('raise SystemExit(2)')

    def test_timeout(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            self.execute_python('import time; time.sleep(10)', 0.05)

    def test_log_limit(self):
        with patch.object(runner, 'MAX_LOG_BYTES', 16), self.assertRaises(RuntimeError):
            self.execute_python('print("x" * 100)')

    def fixture(self, root):
        for directory in ['game/assets/models/frontier_pack', 'game/asset_lab/frontier_pack', 'tests/frontier_pack', 'docs/images/frontier_pack']:
            (root / directory).mkdir(parents=True)
        (root / 'tests/frontier_pack/test_import.gd').write_text('fixture')
        target = root / 'docs/images/frontier_pack/godot_lab.png'
        Image.new('RGB', (1280, 800)).save(target, compress_level=0)
        return target

    def run_fixture(self, root, capture, bad_restart=False):
        calls = []
        def execute(command, env, timeout):
            calls.append(command)
            if len(calls) == 2:
                return output(dict(RESULT, failures=['bad'])) if bad_restart else output()
            if len(calls) == 3 and capture:
                target = Path(next(str(arg).split('=', 1)[1] for arg in command if str(arg).startswith('--frontier-capture=')))
                self.assertFalse(target.exists())
                Image.new('RGB', (1280, 800), (10, 20, 30)).save(target, compress_level=0)
            return 'Godot fixture\n'
        with patch.object(runner, 'ROOT', root), patch.object(runner, 'execute', side_effect=execute), patch.dict(os.environ, {'DISPLAY': ':77'}), contextlib.redirect_stdout(io.StringIO()):
            runner.main(['--godot', sys.executable, '--capture'])
        return calls

    def test_old_image_cannot_satisfy_new_capture(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = self.fixture(root)
            before = target.read_bytes()
            with self.assertRaises(RuntimeError):
                self.run_fixture(root, False)
            self.assertEqual(target.read_bytes(), before)
            self.assertFalse((root / 'game/assets/models/frontier_pack/godot_validation.json').exists())

    def test_new_capture_and_report_published(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = self.fixture(root)
            before = target.read_bytes()
            self.assertEqual(len(self.run_fixture(root, True)), 3)
            self.assertNotEqual(target.read_bytes(), before)
            result = json.loads((root / 'game/assets/models/frontier_pack/godot_validation.json').read_text())
            self.assertTrue(result['capture'])
            self.assertEqual(result['capture_sha256'], runner.validate_capture(target))

    def test_inconsistent_suite_never_launches_capture(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = self.fixture(root)
            before = target.read_bytes()
            with self.assertRaises(RuntimeError):
                self.run_fixture(root, True, bad_restart=True)
            self.assertEqual(target.read_bytes(), before)

    def test_invalid_png(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'bad.png'
            path.write_bytes(b'not a PNG' * 2000)
            with self.assertRaises((RuntimeError, OSError)):
                runner.validate_capture(path)

    def test_wrong_dimensions(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'bad.png'
            Image.new('RGB', (800, 800)).save(path, compress_level=0)
            with self.assertRaises(RuntimeError):
                runner.validate_capture(path)

    def test_isolated_profile(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {'LAGUNAK_PASSWORD': 'synthetic', 'TOKEN': 'synthetic'}):
            env = runner.isolated_environment(Path(folder))
            self.assertNotIn('TOKEN', env)
            self.assertNotIn('LAGUNAK_PASSWORD', env)
            for key in ['HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']:
                self.assertTrue(Path(env[key]).is_relative_to(folder))


if __name__ == '__main__':
    unittest.main()
