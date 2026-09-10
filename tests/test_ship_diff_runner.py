"""Negative tests for orchestration; they do not replace running Godot."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("ship_diff_runner", Path(__file__).with_name("run_ship_configuration_diff.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)
OK = "Godot test runtime\nSHIP_CONFIGURATION_DIFF_TESTS 22 checks; 0 failures\n"


class ResultTests(unittest.TestCase):
    def test_complete_success(self):
        self.assertEqual(runner.validate_result(subprocess.CompletedProcess([], 0, OK)), OK)

    def test_rejects_incomplete_or_bad_summary(self):
        for text in ("", "other tests passed", "SHIP_CONFIGURATION_DIFF_TESTS 0 checks; 0 failures\n",
                     "SHIP_CONFIGURATION_DIFF_TESTS 22 checks; 1 failures\n", OK + OK,
                     "prefix SHIP_CONFIGURATION_DIFF_TESTS 22 checks; 0 failures\n"):
            with self.subTest(text=text), self.assertRaises(runner.VerificationError):
                runner.validate_result(subprocess.CompletedProcess([], 0, text))

    def test_rejects_errors_even_after_success_marker(self):
        for text in ("ERROR: failure", "SCRIPT ERROR: invalid call", "  USER ERROR: failure"):
            with self.subTest(text=text), self.assertRaises(runner.VerificationError):
                runner.validate_result(subprocess.CompletedProcess([], 0, OK + text))

    def test_rejects_crash_and_failure_status(self):
        for code in (-11, 1, 127):
            with self.subTest(code=code), self.assertRaises(runner.VerificationError):
                runner.validate_result(subprocess.CompletedProcess([], code, OK))

    def test_output_limit(self):
        with self.assertRaises(runner.VerificationError):
            runner.validate_result(subprocess.CompletedProcess([], 0, OK + "x" * runner.MAX_OUTPUT))


class ExecutionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "game").mkdir()
        (self.root / "tests").mkdir()
        (self.root / "game" / "project.godot").touch()
        (self.root / "tests" / "test_ship_configuration_diff.gd").touch()
        self.godot = self.root / "fake godot"
        self.godot.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        self.godot.chmod(0o700)

    def test_command_and_private_data_are_isolated(self):
        original = dict(os.environ)
        captured = {}
        def execute(command, **kwargs):
            captured.update(kwargs)
            captured["command"] = command
            for variable in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
                self.assertTrue(Path(kwargs["env"][variable]).is_dir())
                self.assertNotEqual(kwargs["env"][variable], original.get(variable))
            return subprocess.CompletedProcess(command, 0, OK)
        with patch.object(runner.subprocess, "run", side_effect=execute):
            self.assertEqual(runner.run_suite(self.godot, root=self.root, headless=True, timeout=30), OK)
        self.assertEqual(captured["command"][0], str(self.godot))
        self.assertIn("--headless", captured["command"])
        self.assertEqual(captured["command"][-2:], ["--", "--test"])
        self.assertEqual(captured["timeout"], 30)
        self.assertFalse(captured.get("shell", False))
        self.assertFalse(Path(captured["env"]["HOME"]).exists())
        self.assertEqual(dict(os.environ), original)

    def test_graphical_mode_keeps_display(self):
        with patch.dict(os.environ, {"DISPLAY": ":42"}):
            with patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, OK)) as run:
                runner.run_suite(self.godot, root=self.root)
            self.assertNotIn("--headless", run.call_args.args[0])
            self.assertEqual(run.call_args.kwargs["env"]["DISPLAY"], ":42")

    def test_missing_executable(self):
        with self.assertRaises(runner.VerificationError):
            runner.run_suite(self.root / "missing", root=self.root)

    def test_non_executable_file(self):
        self.godot.chmod(0o600)
        with self.assertRaises(runner.VerificationError):
            runner.run_suite(self.godot, root=self.root)

    def test_missing_project(self):
        (self.root / "game" / "project.godot").unlink()
        with self.assertRaises(runner.VerificationError):
            runner.run_suite(self.godot, root=self.root)

    def test_missing_suite(self):
        (self.root / "tests" / "test_ship_configuration_diff.gd").unlink()
        with self.assertRaises(runner.VerificationError):
            runner.run_suite(self.godot, root=self.root)

    def test_timeout_cleans_up(self):
        captured = {}
        def timeout(command, **kwargs):
            captured.update(kwargs)
            raise subprocess.TimeoutExpired(command, kwargs["timeout"])
        with patch.object(runner.subprocess, "run", side_effect=timeout), self.assertRaises(runner.VerificationError):
            runner.run_suite(self.godot, root=self.root)
        self.assertFalse(Path(captured["env"]["HOME"]).exists())

    def test_os_error_is_controlled(self):
        with patch.object(runner.subprocess, "run", side_effect=OSError("test")), self.assertRaises(runner.VerificationError):
            runner.run_suite(self.godot, root=self.root)

    def test_rejects_invalid_timeouts_before_execution(self):
        with patch.object(runner.subprocess, "run") as run:
            for timeout in (0, 301, float("nan"), float("inf")):
                with self.subTest(timeout=timeout), self.assertRaises(runner.VerificationError):
                    runner.run_suite(self.godot, root=self.root, timeout=timeout)
            run.assert_not_called()

    def test_main_reports_failure(self):
        with patch.object(runner, "run_suite", side_effect=runner.VerificationError("test")), patch("sys.stderr"), self.assertRaises(SystemExit) as exit_result:
            raise SystemExit(runner.main(["--headless"]))
        self.assertEqual(exit_result.exception.code, 1)

    def test_main_success(self):
        with patch.object(runner, "run_suite", return_value=OK), patch("sys.stdout"):
            self.assertEqual(runner.main(["--headless"]), 0)


if __name__ == "__main__":
    unittest.main()
