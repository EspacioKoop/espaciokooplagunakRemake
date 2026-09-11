"""Synthetic runner tests; do not substitute these for real Godot/ENet runs."""
from pathlib import Path
import tempfile
import unittest
from run_gm_live import environment, validate_output

class RunnerTests(unittest.TestCase):
    valid = "GM_LIVE_RESULT checks=7 failures=0\n"
    def test_accepts_one_result(self):
        self.assertTrue(validate_output(0, self.valid))
    def test_nonzero(self):
        self.assertFalse(validate_output(1, self.valid))
    def test_diagnostics(self):
        for prefix in ("ERROR: failure\n", " SCRIPT ERROR: failure\n",
                       "\x1b[31mERROR:\x1b[0m failure\n", "GM_LIVE_FAIL invalid\n",
                       "Unicode parsing error"):
            with self.subTest(prefix=prefix):
                self.assertFalse(validate_output(0, prefix + self.valid))
    def test_missing_and_empty_checks(self):
        for value in ("", "engine started", self.valid.replace("checks=7", "checks=0")):
            self.assertFalse(validate_output(0, value))
    def test_failed_checks(self):
        self.assertFalse(validate_output(0, self.valid.replace("failures=0", "failures=1")))
    def test_duplicate_and_malformed(self):
        for extra in (self.valid, "GM_LIVE_RESULT checks=4 failures=1\n", "GM_LIVE_RESULT invalid\n"):
            self.assertFalse(validate_output(0, self.valid + extra))
    def test_every_suite_is_exact(self):
        values = {"legacy": "GM_HOT_CONSOLE_TESTS 29 checks; 0 failures",
                  "models": "RUNTIME_ASSET_RESULT checks=4 failures=0",
                  "ui": "GM_LIVE_UI_RESULT checks=5 failures=0",
                  "host": "GM_NETWORK_RESULT case=host checks=6 failures=0",
                  "client": "GM_NETWORK_RESULT case=client checks=7 failures=0"}
        for suite, output in values.items():
            self.assertTrue(validate_output(0, output + "\n", suite))
            self.assertFalse(validate_output(0, output.replace("failures=0", "failures=1").replace("0 failures", "1 failures") + "\n", suite))
            self.assertFalse(validate_output(0, (output + "\n") * 2, suite))
    def test_private_directories_are_isolated(self):
        import os
        before = dict(os.environ)
        with tempfile.TemporaryDirectory() as temp:
            env = environment(Path(temp))
            for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
                self.assertTrue(Path(env[key]).is_relative_to(temp))
                self.assertTrue(Path(env[key]).is_dir())
        self.assertEqual(dict(os.environ), before)

if __name__ == "__main__": unittest.main(verbosity=2)
