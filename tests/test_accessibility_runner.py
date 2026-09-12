"""Stdlib runner regressions; process fixtures are not Godot/GUI evidence."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

import run_accessibility_baseline as runner


def successful_output():
    return "\n".join([
        *(f"{runner.CHECK_PREFIX}check-{i}" for i in range(runner.EXPECTED_CHECKS)),
        f"{runner.RESULT_PREFIX} checks={runner.EXPECTED_CHECKS} failures=0",
    ]) + "\n"


class ResultTests(unittest.TestCase):
    def test_accepts_complete_result(self):
        self.assertEqual(runner.validate_suite(successful_output()), runner.EXPECTED_CHECKS)

    def test_accepts_ansi_and_crlf(self):
        output = "\x1b[32m" + successful_output().replace("\n", "\r\n") + "\x1b[0m"
        self.assertEqual(runner.validate_suite(output), runner.EXPECTED_CHECKS)

    def test_missing_or_foreign_marker(self):
        for output in ("", "ANOTHER_SUITE_OK checks=36 failures=0", "ACCESSIBILITY_BASELINE_OKAY"):
            with self.subTest(output=output), self.assertRaises(runner.BaselineFailure):
                runner.validate_suite(output)

    def test_duplicate_marker(self):
        with self.assertRaises(runner.BaselineFailure):
            runner.validate_suite(successful_output() + successful_output())

    def test_marker_must_be_final(self):
        with self.assertRaises(runner.BaselineFailure):
            runner.validate_suite(successful_output() + "unfinished cleanup\n")

    def test_malformed_or_nonzero_result(self):
        for mutation in ("failures=1", "failures=-1", "failures=0 extra"):
            with self.subTest(mutation=mutation), self.assertRaises(runner.BaselineFailure):
                runner.validate_suite(successful_output().replace("failures=0", mutation))

    def test_count_cannot_be_lowered_inflated_or_zero(self):
        for count in (0, 8, runner.EXPECTED_CHECKS - 1, runner.EXPECTED_CHECKS + 1):
            output = successful_output().replace(f"checks={runner.EXPECTED_CHECKS}", f"checks={count}")
            with self.subTest(count=count), self.assertRaises(runner.BaselineFailure):
                runner.validate_suite(output)

    def test_missing_check_transcript(self):
        with self.assertRaises(runner.BaselineFailure):
            runner.validate_suite(successful_output().split("\n", 1)[1])

    def test_duplicate_check_transcript(self):
        with self.assertRaises(runner.BaselineFailure):
            runner.validate_suite(successful_output().replace("check-1\n", "check-0\n"))

    def test_engine_diagnostics_even_after_success(self):
        for diagnostic in ("ERROR: broken", "SCRIPT ERROR: bad type", "  ERROR: indented",
                           "\x1b[31mSCRIPT ERROR:\x1b[0m hidden", "ACCESSIBILITY_CHECK_FAILED bad"):
            with self.subTest(diagnostic=diagnostic), self.assertRaises(runner.BaselineFailure):
                runner.validate_stage({"name": "suite", "timed_out": False, "returncode": 0, "log": "log"},
                                      successful_output() + diagnostic)

    def test_wrong_or_unofficial_version(self):
        for version in ("4.3.0.stable.official.a13da4feb", "4.7.10.stable.official.a13da4feb",
                        "4.7.1.dev.official.a13da4feb", "4.7.1.stable.custom.a13da4feb",
                        "4.7.1.stable.official", "noise\n4.7.1.stable.official.a13da4feb"):
            with self.subTest(version=version), self.assertRaises(runner.BaselineFailure):
                runner.validate_version(version)

    def test_exact_official_version(self):
        version = f"{runner.GODOT_VERSION}.stable.official.a13da4feb"
        self.assertEqual(runner.validate_version(version + "\n"), version)


class IsolationTests(unittest.TestCase):
    def test_sources_are_exact_and_no_autoloads_or_assets_are_copied(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            manifest = runner.prepare_project(runner.ROOT, project)
            expected = {"project.godot", *runner.SOURCES.values()}
            self.assertEqual({p.relative_to(project).as_posix() for p in project.rglob("*") if p.is_file()}, expected)
            self.assertNotIn("[autoload]", (project / "project.godot").read_text())
            self.assertFalse((project / ".godot").exists())
            for source, target in runner.SOURCES.items():
                data = (runner.ROOT / source).read_bytes()
                self.assertEqual((project / target).read_bytes(), data)
                self.assertEqual(manifest[source], hashlib.sha256(data).hexdigest())

    def test_profiles_are_disposable_and_parent_environment_unchanged(self):
        before = os.environ.copy()
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp)
            env = runner.isolated_environment(workspace)
            paths = []
            for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
                self.assertEqual(Path(env[key]).parent, workspace)
                self.assertTrue(Path(env[key]).is_dir())
                paths.append(env[key])
            self.assertEqual(len(set(paths)), len(paths))
            self.assertEqual(dict(os.environ), before)
        self.assertFalse(workspace.exists())

    def test_timeout_is_bounded_and_finite(self):
        for timeout in (0, -1, 121, float("nan"), float("inf")):
            with self.subTest(timeout=timeout), self.assertRaises(runner.BaselineFailure):
                runner.run_baseline(Path("unused"), Path("unused"), timeout)


class ProcessTests(unittest.TestCase):
    def run_python(self, code, timeout=5):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.logs = Path(self.temporary.name)
        self.stages = []
        return runner.run_stage("fixture", [sys.executable, "-c", code], os.environ.copy(),
                                self.logs, self.logs, timeout, self.stages)

    def test_real_subprocess_success_and_stderr_capture(self):
        output = self.run_python("import sys; print('stdout'); print('stderr', file=sys.stderr)")
        self.assertIn("stdout", output)
        self.assertIn("stderr", output)
        self.assertEqual(self.stages[0]["returncode"], 0)
        self.assertEqual((self.logs / "fixture.log").read_text(), output)

    def test_nonzero_exit_cannot_be_overridden_by_marker(self):
        with self.assertRaises(runner.BaselineFailure):
            self.run_python(f"print({successful_output()!r}); raise SystemExit(7)")
        self.assertEqual(self.stages[0]["returncode"], 7)

    def test_zero_exit_with_script_error_fails(self):
        with self.assertRaises(runner.BaselineFailure):
            self.run_python("import sys; print('SCRIPT ERROR: fixture', file=sys.stderr)")
        self.assertEqual(self.stages[0]["returncode"], 0)

    def test_timeout_preserves_partial_stdout_and_stderr(self):
        with self.assertRaisesRegex(runner.BaselineFailure, "timeout"):
            self.run_python("import time,sys; print('partial stdout',flush=True); "
                            "print('partial stderr',file=sys.stderr,flush=True); time.sleep(30)", timeout=0.5)
        self.assertTrue(self.stages[0]["timed_out"])
        log = (self.logs / "fixture.log").read_text()
        self.assertIn("partial stdout", log)
        self.assertIn("partial stderr", log)

    def test_missing_executable_fails_and_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            stages = []
            path = Path(tmp)
            with self.assertRaises(runner.BaselineFailure):
                runner.run_stage("missing", [str(path / "absent")], os.environ.copy(), path, path, 1, stages)
            self.assertIsNone(stages[0]["returncode"])
            self.assertTrue((path / "missing.log").read_text())


class OrchestrationTests(unittest.TestCase):
    """Mock only the engine boundary; verify the real runner orchestration."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.workspace = Path(self.temporary.name)
        self.import_cache = True
        self.fail_stage = None
        self.calls = []
        self.version = f"{runner.GODOT_VERSION}.stable.official.a13da4feb"
        self.suite_output = successful_output()

    def engine(self, name, command, env, cwd, logs, timeout, stages):
        self.calls.append((name, command, env, cwd))
        if name == self.fail_stage:
            raise runner.BaselineFailure("injected " + name + " failure")
        if name == "version":
            return self.version
        project = Path(command[command.index("--path") + 1])
        self.assertEqual(command[command.index("--accessibility") + 1], "disabled")
        if name == "import":
            self.assertIn("--editor", command)
            self.assertIn("--import", command)
            self.assertFalse((project / ".godot").exists())
            if self.import_cache:
                (project / ".godot").mkdir()
                (project / ".godot/global_script_class_cache.cfg").write_text("fixture")
            return ""
        self.assertEqual(name, "suite")
        self.assertEqual(command[-4:], ["--script", "res://tests/test_accessibility_baseline.gd", "--", "--test"])
        self.assertTrue((project / ".godot/global_script_class_cache.cfg").is_file())
        return self.suite_output

    def run_fixture(self, root=runner.ROOT):
        with mock.patch.object(runner, "run_stage", side_effect=self.engine):
            return runner.run_baseline(Path(sys.executable), self.workspace / "logs", root=root)

    def test_import_precedes_suite_and_cleanup_is_complete(self):
        report = self.run_fixture()
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["checks"], runner.EXPECTED_CHECKS)
        self.assertEqual([name for name, *_ in self.calls], ["version", "import", "suite"])
        self.assertFalse(self.calls[0][3].exists())
        self.assertEqual(json.loads((Path(report["logs"]) / "summary.json").read_text()), report)

    def test_import_failure_stops_suite_and_persists_failure(self):
        self.fail_stage = "import"
        report = self.run_fixture()
        self.assertEqual(report["status"], "failed")
        self.assertEqual([name for name, *_ in self.calls], ["version", "import"])
        self.assertFalse(self.calls[0][3].exists())
        self.assertEqual(json.loads((Path(report["logs"]) / "summary.json").read_text())["status"], "failed")

    def test_missing_cache_is_not_a_successful_import(self):
        self.import_cache = False
        report = self.run_fixture()
        self.assertEqual(report["status"], "failed")
        self.assertIn("cache", report["error"])
        self.assertEqual([name for name, *_ in self.calls], ["version", "import"])

    def test_wrong_version_stops_import(self):
        self.version = "4.3.0.stable.official.a13da4feb"
        report = self.run_fixture()
        self.assertEqual(report["status"], "failed")
        self.assertEqual([name for name, *_ in self.calls], ["version"])

    def test_stale_success_cannot_validate_later_failure(self):
        first = self.run_fixture()
        self.suite_output = ""
        second = self.run_fixture()
        self.assertEqual(first["status"], "passed")
        self.assertEqual(second["status"], "failed")
        self.assertNotEqual(first["logs"], second["logs"])
        self.assertEqual(second["checks"], 0)

    def test_missing_source_fails_without_running_engine(self):
        report = self.run_fixture(root=self.workspace)
        self.assertEqual(report["status"], "failed")
        self.assertEqual(self.calls, [])

    def test_cli_missing_binary_returns_failure(self):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            status = runner.main(["--godot", str(self.workspace / "missing"), "--log-dir", str(self.workspace / "logs")])
        self.assertEqual(status, 1)


if __name__ == "__main__":
    unittest.main()
