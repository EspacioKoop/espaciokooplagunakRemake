"""Tests of process/error handling; these do not pretend to run Godot."""
import contextlib
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from run_assistance_training import main, run_suite, validate_output


class OutputTests(unittest.TestCase):
    def test_success(self):
        validate_output("Godot Engine\nTRAINING 123 checks; 0 failures\n", "TRAINING", 100)

    def test_rejects_bad_or_missing_evidence(self):
        for text in ("", "TRAINING 99 checks; 0 failures\n", "TRAINING 100 checks; 1 failures\n",
                     "TRAINING 100 checks; 0 failures\n" * 2,
                     "SCRIPT ERROR: failed\nTRAINING 100 checks; 0 failures\n",
                     "  ERROR: failed\nTRAINING 100 checks; 0 failures\n",
                     "OTHER 100 checks; 0 failures\n", "TRAINING x checks; 0 failures\n"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                validate_output(text, "TRAINING", 100)

    def test_warning_is_not_error(self):
        validate_output("WARNING: driver note\nTRAINING 100 checks; 0 failures\n", "TRAINING", 100)


class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.output = Path(self.folder.name)

    def invoke(self, result, graphical=False, capture=False):
        def execute(*args, **kwargs):
            if capture:
                Path(kwargs["env"]["TRAINING_SCREENSHOT"]).write_bytes(b"test fixture" * 150)
            return result
        with patch("run_assistance_training.subprocess.run", side_effect=execute) as launch:
            with contextlib.redirect_stdout(io.StringIO()):
                run_suite(Path("/fake/godot"), "test_assistance_training.gd",
                          "ASSISTANCE_TRAINING_TESTS", 100, graphical, self.output)
            return launch.call_args

    def test_isolated_command_and_profile(self):
        result = subprocess.CompletedProcess([], 0, "ASSISTANCE_TRAINING_TESTS 100 checks; 0 failures\n")
        with patch.dict(os.environ, {"LAGUNAK_PASSWORD": "discard", "TRAINING_SCREENSHOT": "discard"}):
            call = self.invoke(result)
        self.assertIn("--headless", call.args[0])
        self.assertEqual(call.args[0][-2:], ["--", "--test"])
        self.assertEqual(call.kwargs["timeout"], 120)
        self.assertNotIn("LAGUNAK_PASSWORD", call.kwargs["env"])
        self.assertNotIn("TRAINING_SCREENSHOT", call.kwargs["env"])
        self.assertNotEqual(call.kwargs["env"]["HOME"], os.environ.get("HOME"))
        self.assertFalse(Path(call.kwargs["env"]["HOME"]).exists(), "temporary profile removed")
        self.assertTrue((self.output / "test_assistance_training.log").is_file())

    def test_nonzero_exit_rejected(self):
        with self.assertRaises(RuntimeError):
            self.invoke(subprocess.CompletedProcess([], 1, "ASSISTANCE_TRAINING_TESTS 100 checks; 0 failures\n"))

    def test_exit_zero_with_error_rejected(self):
        with self.assertRaises(ValueError):
            self.invoke(subprocess.CompletedProcess([], 0, "SCRIPT ERROR: broken\n"))

    def test_timeout_preserves_output(self):
        error = subprocess.TimeoutExpired(["godot"], 120, output=b"partial\n")
        with patch("run_assistance_training.subprocess.run", side_effect=error), self.assertRaises(RuntimeError):
            run_suite(Path("/fake/godot"), "test_assistance_training.gd", "ASSISTANCE_TRAINING_TESTS", 100, False, self.output)
        self.assertEqual((self.output / "test_assistance_training.log").read_text(), "partial\n")

    def test_graphical_run_requires_screenshot(self):
        with self.assertRaises(RuntimeError):
            self.invoke(subprocess.CompletedProcess([], 0, "ASSISTANCE_TRAINING_TESTS 100 checks; 0 failures\n"), graphical=True)

    def test_stale_screenshot_is_not_evidence(self):
        (self.output / "assistance-training.png").write_bytes(b"stale fixture" * 150)
        with self.assertRaises(RuntimeError):
            self.invoke(subprocess.CompletedProcess([], 0, "ASSISTANCE_TRAINING_TESTS 100 checks; 0 failures\n"), graphical=True)

    def test_graphical_command(self):
        call = self.invoke(subprocess.CompletedProcess([], 0, "ASSISTANCE_TRAINING_TESTS 101 checks; 0 failures\n"), graphical=True, capture=True)
        self.assertNotIn("--headless", call.args[0])
        self.assertEqual(call.kwargs["env"]["TRAINING_SCREENSHOT"], str(self.output / "assistance-training.png"))

    def test_missing_binary(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(main(["--godot", str(self.output / "missing-godot")]), 2)


if __name__ == "__main__":
    unittest.main()
