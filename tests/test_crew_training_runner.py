"""Synthetic subprocess/PNG checks; these do not replace the Godot exercise."""
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
from run_crew_training import validate_output, validate_capture, isolated_environment, execute, run, main

GOOD = 'CREW_TRAINING_RESULT {"checks":250,"failures":0,"courses":9,"first_mission":true,"ui":true}\n'


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)

    def test_good(self):
        self.assertEqual(validate_output(GOOD)["courses"], 9)

    def test_ansi_good(self):
        self.assertEqual(validate_output('\x1b[32m' + GOOD.rstrip() + '\x1b[0m\n')["courses"], 9)

    def test_all_error_placements(self):
        for line in ('ERROR: bad', '  ERROR: bad', 'SCRIPT ERROR: bad', '\x1b[31mERROR:\x1b[0m bad', 'Unicode parsing error'):
            with self.subTest(line=line), self.assertRaises(ValueError):
                validate_output(line + '\n' + GOOD)

    def test_missing_ambiguous_or_broken_summary(self):
        for text in ('', GOOD * 2, 'prefix ' + GOOD, 'CREW_TRAINING_RESULT {\n', 'CREW_TRAINING_RESULT []\n'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                validate_output(text)

    def test_typed_evidence(self):
        good = json.loads(GOOD.split(' ', 1)[1])
        for field, values in {'checks': [0, 149, True, '250', 250.0], 'failures': [1, False, '0'], 'courses': [8, '9', 9.0], 'first_mission': [False, 1], 'ui': [False, 1]}.items():
            for value in values:
                with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                    validate_output('CREW_TRAINING_RESULT ' + json.dumps({**good, field: value}))

    def test_profile_isolation(self):
        original = dict(os.environ)
        with patch.dict(os.environ, {'LAGUNAK_TOKEN': 'synthetic', 'CREW_TRAINING_SCREENSHOT': 'old'}):
            env = isolated_environment(self.folder / 'profiles')
        self.assertNotIn('LAGUNAK_TOKEN', env)
        self.assertNotIn('CREW_TRAINING_SCREENSHOT', env)
        for key in ('HOME', 'USERPROFILE', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'APPDATA', 'LOCALAPPDATA'):
            self.assertTrue(Path(env[key]).is_relative_to(self.folder))
            self.assertTrue(Path(env[key]).is_dir())
        self.assertEqual(dict(os.environ), original)

    def test_timeout_keeps_log(self):
        log = self.folder / 'failed.log'
        with patch('run_crew_training.subprocess.run', side_effect=subprocess.TimeoutExpired([], 180, output=b'partial')), self.assertRaises(RuntimeError):
            execute(['synthetic'], {}, log)
        self.assertEqual(log.read_text(), 'partial')

    def test_exit_code_rejected(self):
        with patch('run_crew_training.subprocess.run', return_value=subprocess.CompletedProcess([], 1, GOOD)), contextlib.redirect_stdout(io.StringIO()), self.assertRaises(RuntimeError):
            execute(['synthetic'], {}, self.folder / 'failed.log')

    def test_warning_allowed(self):
        self.assertEqual(validate_output('WARNING: display note\n' + GOOD)['failures'], 0)

    def test_capture_decode(self):
        path = self.folder / 'new.png'
        Image.new('RGB', (940, 860)).save(path)
        self.assertEqual(len(validate_capture(path)), 64)

    def test_capture_wrong_dimensions_or_format(self):
        for kind, size in [('PNG', (941, 860)), ('JPEG', (940, 860))]:
            path = self.folder / 'bad.png'
            Image.new('RGB', size).save(path, format=kind)
            with self.assertRaises(ValueError):
                validate_capture(path)

    def test_capture_missing_or_corrupt(self):
        path = self.folder / 'missing.png'
        with self.assertRaises(ValueError): validate_capture(path)
        path.write_bytes(b'not a png' * 1000)
        with self.assertRaises((OSError, ValueError)): validate_capture(path)

    def synthetic_run(self, capture=False, graphical=False, errors=False):
        records = []
        def invoke(command, **kwargs):
            records.append((list(command), dict(kwargs['env'])))
            if '--editor' in command:
                return subprocess.CompletedProcess(command, 0, 'Godot import\n')
            if capture:
                Image.new('RGB', (940, 860)).save(kwargs['env']['CREW_TRAINING_SCREENSHOT'])
            return subprocess.CompletedProcess(command, 0, ('ERROR: failure\n' if errors else '') + GOOD)
        with patch('run_crew_training.subprocess.run', side_effect=invoke), contextlib.redirect_stdout(io.StringIO()):
            result = run(Path(sys.executable), self.folder, graphical)
        return result, records

    def test_headless_run(self):
        result, records = self.synthetic_run()
        self.assertFalse(result['graphical'])
        self.assertIn('--editor', records[0][0])
        self.assertIn('--headless', records[1][0])
        self.assertEqual(records[1][0][-2:], ['--', '--test'])
        self.assertNotIn('CREW_TRAINING_SCREENSHOT', records[1][1])
        self.assertFalse(Path(records[1][1]['HOME']).exists())

    def test_graphical_fresh_evidence(self):
        result, records = self.synthetic_run(capture=True, graphical=True)
        self.assertTrue(result['graphical'])
        self.assertEqual(len(result['capture_sha256']), 64)
        self.assertNotIn('--headless', records[1][0])
        self.assertIn('1600x900', records[1][0])
        self.assertNotIn('CREW_TRAINING_SCREENSHOT', records[0][1])
        self.assertEqual(json.loads((self.folder / 'result.json').read_text()), result)
        self.assertFalse(Path(records[1][1]['CREW_TRAINING_SCREENSHOT']).exists())

    def test_stale_capture_cannot_pass(self):
        old = self.folder / 'school.png'
        Image.new('RGB', (940, 860)).save(old)
        original = old.read_bytes()
        (self.folder / 'result.json').write_text('{"old":"success"}')
        with self.assertRaises(ValueError):
            self.synthetic_run(graphical=True)
        self.assertEqual(old.read_bytes(), original)
        self.assertFalse((self.folder / 'result.json').exists())

    def test_error_does_not_publish_capture(self):
        with self.assertRaises(ValueError): self.synthetic_run(capture=True, graphical=True, errors=True)
        self.assertFalse((self.folder / 'school.png').exists())
        self.assertFalse((self.folder / 'result.json').exists())

    def test_missing_binary(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(['--godot', str(self.folder / 'absent')]), 2)


if __name__ == '__main__':
    unittest.main()
