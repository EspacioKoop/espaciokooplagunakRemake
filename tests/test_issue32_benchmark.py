"""CLI and determinism contracts; discoverable with stdlib unittest."""
from __future__ import annotations

import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "issue32_benchmark.py"
spec = importlib.util.spec_from_file_location("issue32_benchmark_under_test", TOOL)
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


def run_cli(*args):
    return subprocess.run(
        [sys.executable, str(TOOL), *args], cwd=ROOT,
        text=True, capture_output=True, check=False, timeout=15,
    )


class Issue32BenchmarkTests(unittest.TestCase):
    def assert_report(self, report, names, rounds):
        self.assertEqual(report["schema"], 1)
        self.assertEqual(report["tool"], "issue32-benchmark")
        self.assertIs(report["pass"], True)
        self.assertEqual([p["profile"] for p in report["profiles"]], names)
        for profile in report["profiles"]:
            config = benchmark.SCENARIOS[profile["profile"]]
            expected_records = rounds * config["compartments"] * sum(
                entity % 37 == 0 for entity in range(config["entities"])
            )
            self.assertEqual(profile["rounds"], rounds)
            self.assertEqual(len(profile["samples"]), 3)
            self.assertIs(profile["pass"], True)
            self.assertIs(profile["metrics"]["deterministic"], True)
            self.assertIs(profile["limits"]["enforced"], False)
            self.assertEqual(profile["limits"]["max_ms"], config["budget_ms"])
            self.assertEqual(profile["limits"]["max_mib"], config["max_mib"])
            self.assertEqual(len({s["digest"] for s in profile["samples"]}), 1)
            for sample in profile["samples"]:
                self.assertRegex(sample["digest"], r"^[0-9a-f]{64}$")
                self.assertGreaterEqual(sample["elapsed_ms"], 0)
                self.assertEqual(sample["records"], expected_records)
                self.assertEqual(sample["peak_mib"], round(expected_records * 64 / 1048576, 6))

    def test_all_profiles_are_deterministic_and_emit_schema(self):
        with tempfile.TemporaryDirectory(prefix="issue32-benchmark-test-") as tmp:
            output = Path(tmp) / "report.json"
            result = run_cli("--profile", "all", "--rounds", "1", "--json", str(output))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_report(json.loads(output.read_text()), ["low", "recommended"], 1)

    def test_invalid_rounds_are_rejected(self):
        for rounds in ("0", "-1", "21"):
            with self.subTest(rounds=rounds):
                result = run_cli("--rounds", rounds)
                self.assertEqual(result.returncode, 2)
                self.assertIn("--rounds must be between 1 and 20", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_round_boundaries_are_inclusive(self):
        for rounds in (1, 20):
            with self.subTest(rounds=rounds):
                result = run_cli("--profile", "all", "--rounds", str(rounds))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_report(json.loads(result.stdout), ["low", "recommended"], rounds)

    def test_non_integer_rounds_are_rejected(self):
        for rounds in ("1.5", "true", "abc", ""):
            with self.subTest(rounds=rounds):
                result = run_cli("--rounds", rounds)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")

    def test_unknown_profile_is_rejected(self):
        result = run_cli("--profile", "unknown")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")

    def test_rejected_input_does_not_create_output(self):
        with tempfile.TemporaryDirectory(prefix="issue32-benchmark-test-") as tmp:
            output = Path(tmp) / "absent" / "report.json"
            result = run_cli("--rounds", "0", "--json", str(output))
            self.assertEqual(result.returncode, 2)
            self.assertFalse(output.parent.exists())

    def test_each_profile_can_be_selected(self):
        for name in ("low", "recommended"):
            with self.subTest(profile=name):
                result = run_cli("--profile", name)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_report(json.loads(result.stdout), [name], 1)

    def test_default_is_all_profiles_one_round(self):
        result = run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_report(json.loads(result.stdout), ["low", "recommended"], 1)

    def test_stdout_matches_nested_json_output(self):
        with tempfile.TemporaryDirectory(prefix="issue32-benchmark-test-") as tmp:
            output = Path(tmp) / "new" / "nested" / "report.json"
            result = run_cli("--json", str(output))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text(encoding="utf-8"), result.stdout)
            self.assertTrue(result.stdout.endswith("\n"))

    def test_digests_are_stable_across_processes(self):
        results = [run_cli("--rounds", "2") for _ in range(2)]
        for result in results:
            self.assertEqual(result.returncode, 0, result.stderr)
        digests = [
            [[s["digest"] for s in p["samples"]] for p in json.loads(result.stdout)["profiles"]]
            for result in results
        ]
        self.assertEqual(digests[0], digests[1])

    def test_non_deterministic_samples_fail(self):
        # Explicit unit-test doubles: these are not runtime measurements.
        samples = [dict(elapsed_ms=1.0, records=1, digest=char * 64, peak_mib=0.001)
                   for char in "abc"]
        with patch.object(benchmark, "workload", side_effect=samples):
            report = benchmark.run("low", 1)
        self.assertIs(report["pass"], False)
        self.assertIs(report["metrics"]["deterministic"], False)

    def test_main_propagates_failed_determinism(self):
        stdout = io.StringIO()
        with patch.object(sys, "argv", [str(TOOL), "--profile", "low"]), \
                patch.object(benchmark, "run", return_value={"pass": False}), \
                contextlib.redirect_stdout(stdout):
            status = benchmark.main()
        self.assertEqual(status, 1)
        self.assertIs(json.loads(stdout.getvalue())["pass"], False)

    def test_synthetic_timing_limits_are_not_release_gates(self):
        config = benchmark.SCENARIOS["low"]
        sample = dict(elapsed_ms=config["budget_ms"] * 2, records=1,
                      digest="a" * 64, peak_mib=config["max_mib"] * 2)
        with patch.object(benchmark, "workload", return_value=sample):
            report = benchmark.run("low", 1)
        self.assertIs(report["pass"], True)
        self.assertIs(report["limits"]["enforced"], False)

    def test_workload_preserves_profile_configuration(self):
        config = copy.deepcopy(benchmark.SCENARIOS["low"])
        before = copy.deepcopy(config)
        benchmark.workload(config, 1)
        self.assertEqual(config, before)


if __name__ == "__main__":
    unittest.main()
