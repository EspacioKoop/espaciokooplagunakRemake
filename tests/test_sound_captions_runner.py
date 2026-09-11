import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import run_sound_captions as runner

GOOD = "SOUND_CAPTIONS_RESULT checks=12 failures=0\nSOUND_CAPTIONS_OK\n"


class RunnerTests(unittest.TestCase):
    def test_positive(self):
        self.assertEqual(runner.validate_output(0, GOOD), 12)

    def test_exit_failure(self):
        with self.assertRaises(ValueError): runner.validate_output(1, GOOD)

    def test_error_diagnostics(self):
        for prefix in ("ERROR:", " SCRIPT ERROR:", "\x1b[31mERROR:\x1b[0m", "\tFATAL ERROR:", "SOUND_CAPTIONS_FAIL:"):
            with self.subTest(prefix=prefix), self.assertRaises(ValueError):
                runner.validate_output(0, prefix + " injected\n" + GOOD)

    def test_missing_and_malformed_summaries(self):
        for text in ("", "SOUND_CAPTIONS_OK\n", GOOD.replace("checks=12", "checks=0"), GOOD.replace("failures=0", "failures=1"), GOOD + GOOD, GOOD.replace("failures=0", "failures=0 suffix"), GOOD.replace("SOUND_CAPTIONS_OK", "SOUND_CAPTIONS_OK suffix")):
            with self.subTest(text=text), self.assertRaises(ValueError): runner.validate_output(0, text)

    def test_crlf_and_ansi(self):
        self.assertEqual(runner.validate_output(0, "\x1b[32m" + GOOD.replace("\n", "\r\n") + "\x1b[0m"), 12)

    def test_real_subprocess(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.run_checked([sys.executable, "-c", f"print({GOOD!r})"], os.environ.copy()), 12)

    def test_timeout(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            runner.run_checked([sys.executable, "-c", "import time; time.sleep(2)"], os.environ.copy(), timeout=0.05)

    def test_environment_isolation(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {"LAGUNAK_PRIVATE": "private", "SOUND_CAPTION_CAPTURE_DIR": "old"}):
            env = runner.isolated_environment(Path(temp))
            self.assertNotIn("LAGUNAK_PRIVATE", env)
            self.assertNotIn("SOUND_CAPTION_CAPTURE_DIR", env)
            for key in ("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                self.assertTrue(Path(env[key]).is_relative_to(temp))
                self.assertTrue(Path(env[key]).is_dir())

    def test_oversize_log(self):
        with patch.object(runner, "MAX_LOG_BYTES", 8), self.assertRaises(ValueError):
            runner.run_checked([sys.executable, "-c", "print('x'*50)"], os.environ.copy())

    def test_stale_capture_not_accepted(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, "run_checked", return_value=1), patch.dict(os.environ, {"DISPLAY": ":123"}):
            target = Path(temp)
            for name in runner.IMAGES: (target / name).write_bytes(b"old evidence")
            with self.assertRaises(SystemExit): runner.main(["--graphical", "--output", temp])
            self.assertEqual((target / runner.IMAGES[0]).read_bytes(), b"old evidence")
            self.assertFalse((target / "report.json").exists())


if __name__ == "__main__": unittest.main()
