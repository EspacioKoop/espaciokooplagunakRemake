"""Fail-closed runner contracts plus native negative/mutation controls.

Requires official Godot 4.7.1 (GODOT or .toolchain/godot); never silently skips
native tests. Logs use only disposable projects and synthetic catalog entries.
"""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("cosmography_runner", ROOT / "tests/run_cosmography_persistence.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
LOGS = Path(os.environ.get("COSMOGRAPHY_LOG_DIR", ROOT / "build/cosmography-contracts/runner-tests"))


def successful_output(suite, checks=None):
    """Synthetic protocol fixture only; native classes below execute Godot."""
    checks = runner.SUITES[suite] if checks is None else checks
    prefix = f"COSMOGRAPHY_{suite.upper()}"
    lines = [f"{prefix}_CHECK index={index} ok=true" for index in range(1, checks + 1)]
    payload = json.dumps({"checks": checks, "failures": 0}) if suite == "persistence" else f"checks={checks} failures=0"
    return "\n".join([*lines, f"{prefix}_RESULT {payload}"]) + "\n"


class CompletionTests(unittest.TestCase):
    def test_valid_complete_stream(self):
        for suite in runner.SUITES:
            with self.subTest(suite=suite):
                self.assertEqual(runner.completion(suite, successful_output(suite), 0),
                                 {"checks": runner.SUITES[suite], "failures": 0})

    def test_nonzero_exit_even_with_success_marker(self):
        for suite in runner.SUITES:
            for code in [1, 2, -9]:
                with self.subTest(suite=suite, code=code), self.assertRaises(ValueError):
                    runner.completion(suite, successful_output(suite), code)

    def test_diagnostics_even_with_zero_exit(self):
        for suite in runner.SUITES:
            for diagnostic in ["ERROR: failure", "SCRIPT ERROR: failure", "  ERROR: indented",
                               "\x1b[31mSCRIPT ERROR:\x1b[0m colored", f"COSMOGRAPHY_{suite.upper()}_FAIL bad"]:
                with self.subTest(suite=suite, diagnostic=diagnostic), self.assertRaises(ValueError):
                    runner.completion(suite, successful_output(suite) + diagnostic, 0)

    def test_missing_duplicate_or_foreign_summary(self):
        for suite in runner.SUITES:
            valid = successful_output(suite)
            foreign = successful_output("navigation" if suite == "persistence" else "persistence")
            for bad in ["", valid.rsplit("COSMOGRAPHY_", 1)[0], valid + valid, foreign, valid + foreign]:
                with self.subTest(suite=suite, output=bad[-80:]), self.assertRaises(ValueError):
                    runner.completion(suite, bad, 0)

    def test_assertion_count_and_order_must_match(self):
        for suite in runner.SUITES:
            valid = successful_output(suite)
            lines = valid.splitlines(keepends=True)
            for bad in ["".join(lines[1:]), "".join([lines[1], lines[0], *lines[2:]]),
                        valid.replace("index=1 ", "index=0 "), valid.replace("ok=true", "ok=false", 1),
                        lines[-1], lines[0] + valid]:
                with self.subTest(suite=suite), self.assertRaises(ValueError):
                    runner.completion(suite, bad, 0)

    def test_summary_cannot_precede_assertions(self):
        for suite in runner.SUITES:
            lines = successful_output(suite).splitlines(keepends=True)
            with self.subTest(suite=suite), self.assertRaises(ValueError):
                runner.completion(suite, lines[-1] + "".join(lines[:-1]), 0)

    def test_no_zero_or_truncated_test_success(self):
        for suite in runner.SUITES:
            for count in [0, 1, runner.SUITES[suite] - 1]:
                with self.subTest(suite=suite, count=count), self.assertRaises(ValueError):
                    runner.completion(suite, successful_output(suite, count), 0)

    def test_summary_types_failures_and_trailing_junk(self):
        base = successful_output("persistence").split("COSMOGRAPHY_PERSISTENCE_RESULT ")[0]
        for payload in ['{"checks":true,"failures":0}', '{"checks":14.0,"failures":0}',
                        '{"checks":14,"failures":false}', '{"checks":14,"failures":1}',
                        '{"checks":14,"failures":0,"failures":0}', '{"checks":14}', 'null', '[]',
                        '{"checks":14,"failures":0,"extra":1}', '{"checks":14,"failures":0}junk']:
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                runner.completion("persistence", base + "COSMOGRAPHY_PERSISTENCE_RESULT " + payload.replace('14', str(runner.SUITES['persistence'])), 0)
        for payload in ["checks=33 failures=1", "checks=33 failures=0 junk", "checks=33 failures=00 trailing"]:
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                runner.completion("navigation", "COSMOGRAPHY_NAVIGATION_RESULT " + payload, 0)


class IsolationTests(unittest.TestCase):
    def test_only_required_sources_copied_without_cache(self):
        for suite in runner.SUITES:
            with self.subTest(suite=suite), tempfile.TemporaryDirectory() as temporary:
                project = runner.isolated_project(ROOT, Path(temporary), suite)
                files = sorted(str(p.relative_to(project)) for p in project.rglob("*") if p.is_file())
                self.assertEqual(files, sorted(["project.godot", "core/cosmography_catalog.gd",
                                               f"core/cosmography_{suite}.gd", f"tests/test_cosmography_{suite}.gd"]))
                self.assertNotIn("autoload", (project / "project.godot").read_text())
                for name in ("cosmography_catalog.gd", f"cosmography_{suite}.gd"):
                    self.assertEqual((project / "core" / name).read_bytes(), (ROOT / "game/core" / name).read_bytes())
                self.assertEqual((project / f"tests/test_cosmography_{suite}.gd").read_bytes(),
                                 (ROOT / f"tests/test_cosmography_{suite}.gd").read_bytes())

    def test_profiles_are_separate_temporary_and_private(self):
        original = os.environ.copy()
        with tempfile.TemporaryDirectory() as temporary:
            env = runner.isolated_env(Path(temporary))
            paths = [Path(env[key]) for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR")]
            self.assertEqual(len(set(paths)), len(paths))
            for path in paths:
                self.assertTrue(path.is_relative_to(temporary))
                self.assertTrue(path.is_dir())
                self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        self.assertEqual(os.environ, original)

    def test_timeout_preserves_partial_output(self):
        for partial in [b"partial\n", "partial\n"]:
            with self.subTest(partial=partial), tempfile.TemporaryDirectory() as temporary:
                log = Path(temporary) / "timeout.log"
                with mock.patch.object(runner.subprocess, "run", side_effect=subprocess.TimeoutExpired("godot", 1, output=partial)):
                    with self.assertRaisesRegex(ValueError, "Timeout"):
                        runner.checked_process(["godot"], {}, Path(temporary), 1, log)
                self.assertEqual(log.read_text(), "partial\n")

    def test_real_process_timeout_preserves_output_and_exits(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "timeout.log"
            command = [sys.executable, "-I", "-c", "import time; print('real partial output', flush=True); time.sleep(30)"]
            with self.assertRaisesRegex(ValueError, "Timeout"):
                runner.checked_process(command, os.environ.copy(), Path(temporary), 1, log)
            self.assertEqual(log.read_text(), "real partial output\n")

    def test_parse_diagnostic_stops_before_running_suite(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "import.log"
            result = subprocess.CompletedProcess([], 0, "SCRIPT ERROR: import failed\n")
            with mock.patch.object(runner.subprocess, "run", return_value=result), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(ValueError, "Godot failed"):
                    runner.checked_process(["godot"], {}, Path(temporary), 1, log)
            self.assertEqual(log.read_text(), result.stdout)

    def test_absent_binary_and_bad_timeout_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stderr(io.StringIO()):
            output = Path(temporary)
            self.assertEqual(runner.run_suite("persistence", str(output / "absent"), output), 1)
            self.assertFalse(json.loads((output / "report.json").read_text())["ok"])
            for timeout in [0, -1, 121, True]:
                with self.subTest(timeout=timeout), self.assertRaises(ValueError):
                    runner.run_suite("persistence", "godot", output, timeout=timeout)


class NativeControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.godot = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))
        if not shutil.which(cls.godot):
            raise RuntimeError("Official Godot is required: bootstrap it or set GODOT; native tests are not skipped")
        LOGS.mkdir(parents=True, exist_ok=True)

    def invoke(self, suite, name, negative=False, root=ROOT):
        log_dir = LOGS / name
        buffer = io.StringIO()
        try:
            with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
                code = runner.run_suite(suite, self.godot, log_dir, timeout=30, inject_failure=negative, root=root)
        finally:
            log_dir.mkdir(parents=True, exist_ok=True)
            (log_dir / "runner.log").write_text(buffer.getvalue(), encoding="utf-8")
        output = (log_dir / "suite.log").read_text() if (log_dir / "suite.log").is_file() else ""
        report = json.loads((log_dir / "report.json").read_text())
        return code, output, report

    def test_native_positive_suites(self):
        for suite in runner.SUITES:
            with self.subTest(suite=suite):
                code, output, report = self.invoke(suite, f"{suite}-positive")
                self.assertEqual(code, 0, report)
                self.assertEqual(runner.completion(suite, output, 0)["checks"], report["checks"])
                self.assertTrue(report["ok"])

    def test_real_assertion_failure_after_every_native_test(self):
        for suite in runner.SUITES:
            with self.subTest(suite=suite):
                code, output, report = self.invoke(suite, f"{suite}-negative", negative=True)
                self.assertEqual(code, 1)
                self.assertFalse(report["ok"])
                self.assertIn("Godot failed (exit 1)", report["error"])
                self.assertIn("intentional negative control after the complete suite", output)
                self.assertNotIn("SCRIPT ERROR:", output)
                records = re.findall(rf"COSMOGRAPHY_{suite.upper()}_CHECK index=(\d+) ok=(true|false)", output)
                self.assertGreaterEqual(len(records), runner.SUITES[suite] + 1)
                self.assertEqual([int(index) for index, _ in records], list(range(1, len(records) + 1)))
                self.assertEqual([ok for _, ok in records], ["true"] * (len(records) - 1) + ["false"])
                summary = next(line for line in output.splitlines() if line.startswith(f"COSMOGRAPHY_{suite.upper()}_RESULT "))
                if suite == "persistence":
                    self.assertEqual(json.loads(summary.split("_RESULT ")[1]), {"checks": len(records), "failures": 1})
                else:
                    self.assertTrue(summary.endswith(f"checks={len(records)} failures=1"))

    def test_native_parse_failure_is_not_a_negative_control_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "game/core").mkdir(parents=True)
            (root / "tests").mkdir()
            shutil.copyfile(ROOT / "game/core/cosmography_catalog.gd", root / "game/core/cosmography_catalog.gd")
            shutil.copyfile(ROOT / "tests/test_cosmography_persistence.gd", root / "tests/test_cosmography_persistence.gd")
            (root / "game/core/cosmography_persistence.gd").write_text("extends RefCounted\nthis is not valid GDScript\n")
            code, output, report = self.invoke("persistence", "persistence-parse-error", root=root)
            self.assertEqual(code, 1)
            self.assertFalse(report["ok"])
            self.assertEqual(output, "", "Native suite must not start after compilation fails")
            self.assertIn("parse.log", report["error"])
            self.assertIn("SCRIPT ERROR:", (LOGS / "persistence-parse-error/parse.log").read_text())

    def test_version_regressions_are_killed_by_native_suites(self):
        # Executable mutations, not fabricated tool output. The coercive mutant
        # bounds types to avoid a runtime type error obscuring the real regression.
        original = "return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(value) and value == VERSION"
        mutants = {
            "int-only": "return typeof(value) == TYPE_INT and value == VERSION",
            "coercive": "return typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING] and int(value) == VERSION",
        }
        for suite in runner.SUITES:
            for name, replacement in mutants.items():
                with self.subTest(suite=suite, mutation=name), tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    (root / "game/core").mkdir(parents=True)
                    (root / "tests").mkdir()
                    for filename in ["cosmography_catalog.gd", f"cosmography_{suite}.gd"]:
                        shutil.copyfile(ROOT / "game/core" / filename, root / "game/core" / filename)
                    shutil.copyfile(ROOT / f"tests/test_cosmography_{suite}.gd", root / f"tests/test_cosmography_{suite}.gd")
                    component = root / f"game/core/cosmography_{suite}.gd"
                    source = component.read_text()
                    self.assertEqual(source.count(original), 1, "Update the mutation with the production version guard")
                    component.write_text(source.replace(original, replacement))
                    code, output, report = self.invoke(suite, f"{suite}-mutant-{name}", root=root)
                    self.assertEqual(code, 1)
                    self.assertIn("Godot failed (exit 1)", report["error"])
                    self.assertIn(f"COSMOGRAPHY_{suite.upper()}_FAIL", output)
                    self.assertIn(f"COSMOGRAPHY_{suite.upper()}_RESULT", output)
                    self.assertNotIn("SCRIPT ERROR:", output, "A parser/runtime error is not evidence of a killed logical mutant")


if __name__ == "__main__":
    unittest.main(verbosity=2)
