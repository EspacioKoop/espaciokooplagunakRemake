"""Unit and real subprocess tests for the runner, not substitutes for Godot tests."""
from __future__ import annotations

import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import run_loadout_comparison as runner

MARKER = "LOADOUT_COMPARISON_TESTS"
SUMMARY = f"{MARKER} 123 checks; 0 failures\n"


class OutputChecks(unittest.TestCase):
    def test_complete_summary(self):
        runner.check_output(0, "Godot banner\n" + SUMMARY, MARKER)

    def test_nonzero_exit(self):
        with self.assertRaises(runner.VerificationError):
            runner.check_output(1, SUMMARY, MARKER)

    def test_engine_errors_even_with_zero_exit(self):
        for prefix in ["ERROR:", "SCRIPT ERROR:", "  ERROR:", "\x1b[31mERROR:\x1b[0m"]:
            with self.subTest(prefix=prefix), self.assertRaises(runner.VerificationError):
                runner.check_output(0, prefix + " problem\n" + SUMMARY, MARKER)

    def test_missing_summary(self):
        with self.assertRaises(runner.VerificationError):
            runner.check_output(0, "Godot banner\n", MARKER)

    def test_zero_checks(self):
        with self.assertRaises(runner.VerificationError):
            runner.check_output(0, f"{MARKER} 0 checks; 0 failures\n", MARKER)

    def test_reported_failure(self):
        with self.assertRaises(runner.VerificationError):
            runner.check_output(0, f"{MARKER} 10 checks; 1 failures\n", MARKER)

    def test_duplicate_summaries(self):
        with self.assertRaises(runner.VerificationError):
            runner.check_output(0, SUMMARY + SUMMARY, MARKER)

    def test_other_suite_summary_cannot_pass(self):
        with self.assertRaises(runner.VerificationError):
            runner.check_output(0, "LOADOUT_EDITOR_TESTS 20 checks; 0 failures\n", MARKER)

    def test_truncated_summary(self):
        with self.assertRaises(runner.VerificationError):
            runner.check_output(0, f"{MARKER} 123 checks;", MARKER)

    def test_colored_crlf_summary(self):
        runner.check_output(0, "\x1b[32m" + SUMMARY.rstrip() + "\x1b[0m\r\n", MARKER)

    def test_import_needs_no_suite_summary_but_must_be_clean(self):
        runner.check_output(0, "Import complete\n", None)
        with self.assertRaises(runner.VerificationError):
            runner.check_output(0, "SCRIPT ERROR: Parse error\n", None)


class EnvironmentChecks(unittest.TestCase):
    def test_isolation_preserves_display_and_does_not_mutate_original(self):
        original = {"HOME": "/not-the-test-home", "DISPLAY": ":77", "PATH": os.defpath}
        before = original.copy()
        with tempfile.TemporaryDirectory() as folder:
            env = runner.isolated_environment(Path(folder), original)
            self.assertEqual(original, before)
            self.assertEqual(env["DISPLAY"], ":77")
            self.assertEqual(env["PATH"], os.defpath)
            for name in ["HOME", "USERPROFILE", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"]:
                self.assertTrue(Path(env[name]).is_dir())
                self.assertTrue(Path(env[name]).is_relative_to(Path(folder)))

    def test_resolves_explicit_executable(self):
        self.assertEqual(runner.resolve_godot(sys.executable), str(Path(sys.executable).resolve()))

    def test_missing_engine_is_controlled(self):
        with mock.patch.object(runner.shutil, "which", return_value=None):
            with self.assertRaises(runner.VerificationError):
                runner.resolve_godot("nonexistent-lagunak-engine-12345")


class SubprocessChecks(unittest.TestCase):
    def run_python(self, source, marker=MARKER, timeout=10):
        with contextlib.redirect_stdout(io.StringIO()):
            runner.run_step([sys.executable, "-c", source], os.environ, marker, timeout)

    def test_real_subprocess_output(self):
        self.run_python(f"print({SUMMARY!r}, end='')")

    def test_real_subprocess_error_is_detected(self):
        with self.assertRaises(runner.VerificationError):
            self.run_python(f"print('ERROR: synthetic runner fixture'); print({SUMMARY!r})")

    def test_real_subprocess_nonzero_exit(self):
        with self.assertRaises(runner.VerificationError):
            self.run_python(f"import sys; print({SUMMARY!r}); sys.exit(7)")

    def test_real_subprocess_timeout(self):
        with self.assertRaises(runner.VerificationError):
            self.run_python("import time; time.sleep(10)", timeout=0.1)

    def test_unavailable_executable(self):
        with self.assertRaises(runner.VerificationError):
            runner.run_step(["/does-not-exist/lagunak-godot"], os.environ, MARKER)

    def test_log_size_limit(self):
        with mock.patch.object(runner, "MAX_LOG_BYTES", 64):
            with self.assertRaises(runner.VerificationError):
                self.run_python("print('x' * 1000)")


class OrchestrationChecks(unittest.TestCase):
    def test_runs_import_and_both_real_suite_commands(self):
        calls = []
        def record(command, env, marker, timeout=120):
            calls.append((list(command), dict(env), marker))
            self.assertTrue(Path(env["HOME"]).is_dir())
        with mock.patch.object(runner, "resolve_godot", return_value="/engine/godot"):
            with mock.patch.object(runner, "run_step", side_effect=record):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(runner.main([]), 0)
        self.assertEqual(len(calls), 3)
        self.assertIn("--editor", calls[0][0])
        self.assertIsNone(calls[0][2])
        for index, (script, marker) in enumerate(runner.SUITES, start=1):
            self.assertIn(str(runner.ROOT / "tests" / script), calls[index][0])
            self.assertEqual(calls[index][2], marker)
            self.assertEqual(calls[index][0][-2:], ["--", "--test"])
            self.assertNotIn("--headless", calls[index][0])
            self.assertEqual(calls[index][1]["HOME"], calls[0][1]["HOME"])
        self.assertFalse(Path(calls[0][1]["HOME"]).exists())

    def test_headless_flag_is_explicit(self):
        with mock.patch.object(runner, "resolve_godot", return_value="/engine/godot"):
            with mock.patch.object(runner, "run_step") as step:
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(runner.main(["--headless"]), 0)
        for call in step.call_args_list:
            self.assertIn("--headless", call.args[0])

    def test_import_failure_stops_before_suites(self):
        with mock.patch.object(runner, "resolve_godot", return_value="/engine/godot"):
            with mock.patch.object(runner, "run_step", side_effect=runner.VerificationError("import failed")) as step:
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(runner.main([]), 1)
        self.assertEqual(step.call_count, 1)

    def test_missing_engine_returns_failure(self):
        with mock.patch.object(runner, "resolve_godot", side_effect=runner.VerificationError("missing")):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(runner.main([]), 1)


if __name__ == "__main__":
    unittest.main()
