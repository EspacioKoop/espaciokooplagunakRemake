"""Runner tests; these do not claim to execute or validate Godot gameplay."""
from contextlib import redirect_stderr
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_npc_workbench as runner


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = runner.isolated_environment(self.root)

    def execute(self, code, marker=None, timeout=5):
        return runner.run_checked([sys.executable, "-c", code], self.root, self.env, timeout, marker)

    def test_isolates_all_user_directories_and_drops_credentials(self):
        env = runner.isolated_environment(self.root, {"PATH": "/bin", "HOME": "/private", "TOKEN": "private", "DISPLAY": ":7"})
        self.assertNotIn("TOKEN", env)
        self.assertEqual(env["DISPLAY"], ":7")
        self.assertEqual(env["PATH"], "/bin")
        for key in ("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "TEMP"):
            self.assertTrue(Path(env[key]).is_relative_to(self.root))
            self.assertTrue(Path(env[key]).is_dir())

    def test_requires_positive_complete_marker(self):
        text = self.execute("print('NPC_GENERATOR_PASS checks=12')", "NPC_GENERATOR_PASS")
        self.assertIn("checks=12", text)

    def test_empty_marker_is_not_success(self):
        with self.assertRaises(runner.VerificationError):
            self.execute("print('engine started')", "NPC_GENERATOR_PASS")

    def test_zero_checks_are_not_success(self):
        with self.assertRaises(runner.VerificationError):
            self.execute("print('NPC_GENERATOR_PASS checks=0')", "NPC_GENERATOR_PASS")

    def test_partial_or_embedded_marker_is_not_success(self):
        for value in ("prefix NPC_GENERATOR_PASS checks=12", "NPC_GENERATOR_PASS checks=12 extra"):
            with self.subTest(value=value), self.assertRaises(runner.VerificationError):
                self.execute(f"print({value!r})", "NPC_GENERATOR_PASS")

    def test_nonzero_exit_rejected_even_with_marker(self):
        with self.assertRaises(runner.VerificationError):
            self.execute("print('NPC_GENERATOR_PASS checks=1'); raise SystemExit(7)", "NPC_GENERATOR_PASS")

    def test_script_and_engine_errors_override_marker(self):
        for error in ("SCRIPT ERROR: failed", "ERROR: failed", "  ERROR: failed"):
            with self.subTest(error=error), self.assertRaises(runner.VerificationError):
                self.execute(f"print({error!r}); print('NPC_GENERATOR_PASS checks=1')", "NPC_GENERATOR_PASS")

    def test_stderr_errors_are_checked(self):
        with self.assertRaises(runner.VerificationError):
            self.execute("import sys; print('ERROR: failed', file=sys.stderr)")

    def test_timeout_stops_process(self):
        with self.assertRaisesRegex(runner.VerificationError, "tiempo"):
            self.execute("import time; time.sleep(30)", timeout=0.08)

    def test_output_is_bounded(self):
        with patch.object(runner, "MAX_LOG_BYTES", 128), self.assertRaisesRegex(runner.VerificationError, "salida"):
            self.execute("print('x' * 512)")

    def test_timeout_validation(self):
        for timeout in (0, -1, 601):
            with self.subTest(timeout=timeout), self.assertRaises(ValueError):
                self.execute("pass", timeout=timeout)

    def test_missing_binary_is_controlled(self):
        with self.assertRaises(runner.VerificationError):
            runner.run_checked([str(self.root / "missing")], self.root, self.env, 1)

    def test_arguments_are_not_shell_expanded(self):
        path = self.root / "not-created"
        text = runner.run_checked([sys.executable, "-c", "import sys; print(sys.argv[1])", f"; touch {path}"], self.root, self.env, 5)
        self.assertIn("; touch", text)
        self.assertFalse(path.exists())

    def test_main_builds_real_tests_and_cleans_environment(self):
        calls = []
        def record(command, cwd, env, timeout, marker=None):
            calls.append((command, env.copy(), marker))
            return f"{marker} checks=1\n" if marker else "imported\n"
        with patch.object(runner, "run_checked", side_effect=record), patch("sys.stdout", new=io.StringIO()):
            result = runner.main(["--godot", sys.executable, "--graphics"])
        self.assertEqual(result, 0)
        self.assertEqual(len(calls), 3)
        self.assertIn("--editor", calls[0][0])
        self.assertIn("--headless", calls[1][0])
        self.assertNotIn("--headless", calls[2][0])
        for command, env, marker in calls[1:]:
            self.assertEqual(command[-2:], ["--", "--test"])
            self.assertTrue(marker.startswith("NPC_"))
            self.assertFalse(Path(env["HOME"]).exists())

    def test_main_reports_failure(self):
        with patch.object(runner, "run_checked", side_effect=runner.VerificationError("test")), patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(runner.main(["--godot", sys.executable]), 1)

    def test_missing_binary_does_not_trigger_download(self):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as result:
            runner.main(["--godot", str(self.root / "missing")])
        self.assertEqual(result.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
