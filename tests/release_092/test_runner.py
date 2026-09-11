"""Negative controls for acceptance of the actual downloadable application."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("release092_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
GOOD = "TERMINAL_TRANSITION_RESULT checks=161 failures=0\n"


class AcceptanceTests(unittest.TestCase):
    def test_full_unique_success(self):
        self.assertEqual(runner.validate_output(0, GOOD, "terminals"), 161)
        self.assertEqual(runner.validate_output(0, "LEISURE_TESTS 135 checks; 0 failures\n", "leisure"), 135)
        self.assertEqual(runner.validate_output(0, "EXPORT_CONTRACT_RESULT checks=16 failures=0\n", "contract"), 16)

    def test_diagnostics_before_or_after_success_fail(self):
        for diagnostic in ("ERROR: boom", "  SCRIPT ERROR: boom", "Unicode parsing error", "\x1b[31mERROR:\x1b[0m boom"):
            for value in (diagnostic + "\n" + GOOD, GOOD + diagnostic):
                with self.subTest(value=value), self.assertRaises(ValueError): runner.validate_output(0, value, "terminals")

    def test_nonzero_exit_and_bad_reports_fail(self):
        with self.assertRaises(ValueError): runner.validate_output(1, GOOD, "terminals")
        for value in ("", GOOD * 2, GOOD.replace("161", "0"), GOOD.replace("161", "8"), GOOD.replace("failures=0", "failures=1"), GOOD.rstrip() + " extra\n", "TERMINAL_TRANSITION_OK\n"):
            with self.subTest(value=value), self.assertRaises(ValueError): runner.validate_output(0, value, "terminals")

    def test_windows_newlines_and_colours(self):
        self.assertEqual(runner.validate_output(0, "\x1b[32m" + GOOD.replace("\n", "\r\n") + "\x1b[0m", "terminals"), 161)

    def test_profiles_are_separate_and_local(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {"LAGUNAK_PRIVATE": "canary", "GODOT_CUSTOM": "canary"}):
            env = runner.isolated_environment(Path(temp))
            self.assertNotIn("LAGUNAK_PRIVATE", env)
            self.assertNotIn("GODOT_CUSTOM", env)
            for key in ("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                self.assertTrue(Path(env[key]).is_relative_to(temp))
                self.assertTrue(Path(env[key]).is_dir())

    def test_relocation_only_changes_test_imports(self):
        content = runner.prepare.rendered()
        for name in runner.SCRIPTS:
            original = (runner.ROOT / "tests" / name).read_text()
            relocated = content[runner.prepare.FIXTURE_DIR + "/" + name].decode()
            for helper in ("test_ship_corridors.gd", "test_ship_deck_layout.gd"):
                relocated = relocated.replace('"res://release_acceptance/fixtures/' + helper + '"', '"res://../tests/' + helper + '"')
            self.assertEqual(original, relocated)
        self.assertIn(b'"res://main.tscn"', content[runner.prepare.FIXTURE_DIR + "/test_terminal_transition.gd"])

    def test_modified_embedded_assertions_and_extra_files_are_rejected(self):
        import shutil
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in runner.SCRIPTS:
                (root / "tests").mkdir(exist_ok=True)
                shutil.copyfile(runner.ROOT / "tests" / name, root / "tests" / name)
            (root / "tests/release_092").mkdir()
            shutil.copyfile(Path(__file__).with_name("test_export_contract.gd"), root / "tests/release_092/test_export_contract.gd")
            runner.prepare.prepare(root)
            runner.prepare.prepare(root, check=True)
            fixture = root / runner.prepare.FIXTURE_DIR / "test_terminal_transition.gd"
            fixture.write_text(fixture.read_text() + "\n# unexpected edit\n")
            with self.assertRaises(ValueError): runner.prepare.prepare(root, check=True)
            runner.prepare.prepare(root)
            (fixture.parent / "foreign.gd").write_text("extends Node")
            with self.assertRaises(ValueError): runner.prepare.prepare(root, check=True)

    def test_template_commands_never_override_paths_or_run_external_scripts(self):
        for phase in ("contract", "terminals", "leisure"):
            command = runner.embedded_command(Path("/tmp/app"), phase, Path("/tmp/captures"))
            self.assertIn("--test", command)
            self.assertIn("--release-acceptance=" + phase, command)
            self.assertFalse({"--script", "--path", "--main-pack", "--main-loop", "--scene"}.intersection(command))
        with self.assertRaises(ValueError): runner.embedded_command(Path("/tmp/app"), "../foreign", Path("/tmp/captures"))

    def test_zip_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            package = root / "bad.zip"
            with zipfile.ZipFile(package, "w") as z: z.writestr("../escape", "bad")
            with self.assertRaises(ValueError): runner.extract_binary(package, root)
            self.assertFalse((root.parent / "escape").exists())

    def test_missing_or_non_executable_download_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for data in (b"short", b"not an ELF" + b"x" * 1_000_000):
                package = root / "bad.zip"
                with zipfile.ZipFile(package, "w") as z:
                    z.writestr("LICENSE", "fixture")
                    z.writestr("EspaciokoopLagunak.x86_64", data)
                with self.assertRaises(ValueError): runner.extract_binary(package, root)

    def test_timeout_is_failure_with_evidence(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with self.assertRaises(subprocess.TimeoutExpired):
                runner.run_checked([sys.executable, "-c", "import time; time.sleep(2)"], os.environ.copy(), root, root / "timeout.log", "terminals", timeout=.05)
            self.assertIn("RUNNER_TIMEOUT", (root / "timeout.log").read_text())

    def test_oversize_log_is_failure(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(runner, "MAX_LOG_BYTES", 8):
            root = Path(temp)
            with self.assertRaises(ValueError):
                runner.run_checked([sys.executable, "-c", "print('x'*30)"], os.environ.copy(), root, root / "log", "terminals")

    def test_stale_report_removed_before_failed_acceptance(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "report.json").write_text("stale success")
            for name in runner.IMAGES: (root / name).write_text("old capture")
            with self.assertRaises(ValueError): runner.main(["--output", temp, "--package", str(root / "old-version.zip")])
            self.assertFalse((root / "report.json").exists())
            self.assertTrue(all(not (root / name).exists() for name in runner.IMAGES))

    def test_missing_or_wrong_capture_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "image.png"
            path.write_bytes(b"not a png")
            with self.assertRaises(ValueError): runner.verify_image(path)


if __name__ == "__main__": unittest.main(verbosity=2)
