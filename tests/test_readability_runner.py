"""Synthetic runner regressions; real Godot UI/persistence still run separately."""
import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import run_readability as runner

OK = "READABILITY_RESULT checks=7 failures=0\nREADABILITY_OK\n"


class OutputTests(unittest.TestCase):
    def test_valid_and_colored_crlf(self):
        for text in (OK, "Godot\n" + OK, "\x1b[32m" + OK.replace("\n", "\x1b[0m\r\n")):
            runner.validate_output(0, text)

    def test_error_first_line_indented_and_ansi(self):
        for diagnostic in ("ERROR:", "  ERROR:", "SCRIPT ERROR:", "USER ERROR:", "FATAL:",
                           "FATAL ERROR:", "\x1b[31mERROR:\x1b[0m", "READABILITY_FAIL:"):
            for text in (diagnostic + " fixture\n" + OK, OK + diagnostic + " fixture\n"):
                with self.subTest(text=text), self.assertRaises(ValueError):
                    runner.validate_output(0, text)

    def test_missing_empty_failed_partial_and_duplicate_summaries(self):
        for text in ("", "READABILITY_OK\n", OK.replace("checks=7", "checks=0"),
                     OK.replace("failures=0", "failures=1"), OK.replace("checks=7", "checks=oops"),
                     OK + OK, OK + "READABILITY_RESULT checks=", OK + "READABILITY_OK\n",
                     OK.replace("READABILITY_OK", "READABILITY_OK_suffix"),
                     OK.replace("READABILITY_RESULT", "prefix READABILITY_RESULT")):
            with self.subTest(text=text), self.assertRaises(ValueError):
                runner.validate_output(0, text)

    def test_nonzero_exit(self):
        for code in (-11, 1, 127):
            with self.assertRaises(ValueError):
                runner.validate_output(code, OK)

    def test_warning_is_allowed(self):
        runner.validate_output(0, "WARNING: fixture\n" + OK)


class ProcessTests(unittest.TestCase):
    def invoke(self, results, args=(), capture=False):
        calls = []
        def execute(command, **kwargs):
            calls.append((command, dict(kwargs["env"])))
            if capture and "READABILITY_CAPTURE_PATH" in kwargs["env"]:
                Path(kwargs["env"]["READABILITY_CAPTURE_PATH"]).write_bytes(b"\x89PNG\r\n\x1a\n" + b"fixture" * 200)
            text, code = results[len(calls) - 1]
            kwargs["stdout"].write(text.encode())
            return subprocess.CompletedProcess(command, code)
        with patch.object(runner.subprocess, "run", side_effect=execute), patch.dict(os.environ, {"DISPLAY": ":77"}), contextlib.redirect_stdout(io.StringIO()):
            runner.main(["--godot", sys.executable, *args])
        return calls

    def test_two_processes_share_only_temporary_profile(self):
        with patch.dict(os.environ, {"READABILITY_CAPTURE_PATH": "private", "LAGUNAK_PASSWORD": "private"}):
            calls = self.invoke([(OK, 0), (OK, 0)])
        self.assertEqual(len(calls), 2)
        self.assertIn("--verify-persisted", calls[1][0])
        self.assertEqual(calls[0][1], calls[1][1])
        for key in ("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            self.assertNotEqual(calls[0][1][key], os.environ.get(key))
            self.assertFalse(Path(calls[0][1][key]).exists())
        self.assertNotIn("LAGUNAK_PASSWORD", calls[0][1])
        self.assertNotIn("READABILITY_CAPTURE_PATH", calls[0][1])

    def test_restart_is_validated_too(self):
        with self.assertRaises(SystemExit):
            self.invoke([(OK, 0), ("\x1b[31mERROR:\x1b[0m bad\n" + OK, 0)])

    def test_timeout_fails(self):
        with patch.object(runner.subprocess, "run", side_effect=subprocess.TimeoutExpired("fixture", 90)), self.assertRaises(SystemExit):
            runner.main(["--godot", sys.executable])

    def test_old_capture_cannot_satisfy_new_run(self):
        with tempfile.TemporaryDirectory() as folder:
            old = Path(folder) / "old.png"
            old.write_bytes(b"old fixture" * 200)
            with self.assertRaises(SystemExit):
                self.invoke([(OK, 0), (OK, 0)], ("--graphical", "--screenshot", str(old)))
            self.assertEqual(old.read_bytes(), b"old fixture" * 200)

    def test_new_capture_is_published_after_both_passes(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "new.png"
            calls = self.invoke([(OK, 0), (OK, 0)], ("--graphical", "--screenshot", str(target)), capture=True)
            self.assertTrue(target.read_bytes().startswith(b"\x89PNG"))
            self.assertNotEqual(calls[0][1]["READABILITY_CAPTURE_PATH"], str(target))
            self.assertNotIn("READABILITY_CAPTURE_PATH", calls[1][1])

    def test_failed_restart_does_not_publish_capture(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "new.png"
            with self.assertRaises(SystemExit):
                self.invoke([(OK, 0), (OK, 1)], ("--graphical", "--screenshot", str(target)), capture=True)
            self.assertFalse(target.exists())

    def test_real_synthetic_subprocess_regression(self):
        with tempfile.TemporaryDirectory() as folder:
            engine = Path(folder) / "fake-engine"
            engine.write_text("#!" + sys.executable + "\nprint(" + repr("\x1b[31mERROR:\x1b[0m fixture\n" + OK) + ")\n")
            engine.chmod(0o700)
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
                runner.main(["--godot", str(engine)])


if __name__ == "__main__":
    unittest.main()
