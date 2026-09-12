"""Negative controls for the native guided-connection runner (no real credentials)."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_hamachi_network import CASES, managed_process, validate_result, wait_ready


class HamachiRunnerTests(unittest.TestCase):
    def test_all_complete_results(self):
        for case, checks in CASES.items():
            with self.subTest(case=case):
                result = validate_result(case, 0, f"HAMACHI_RESULT {case} checks={checks} failures=0\n")
                self.assertEqual(result["checks"], checks)

    def test_nonzero_exit(self):
        with self.assertRaises(ValueError):
            validate_result("host", 1, "HAMACHI_RESULT host checks=99 failures=0\n")

    def test_zero_checks(self):
        with self.assertRaises(ValueError):
            validate_result("host", 0, "HAMACHI_RESULT host checks=0 failures=0\n")

    def test_insufficient_checks(self):
        with self.assertRaises(ValueError):
            validate_result("good", 0, "HAMACHI_RESULT good checks=1 failures=0\n")

    def test_logical_failures(self):
        with self.assertRaises(ValueError):
            validate_result("good", 0, "HAMACHI_RESULT good checks=99 failures=1\n")

    def test_missing_and_incomplete_result(self):
        for text in ("", "HAMACHI_RESULT", "HAMACHI_RESULT host failures=0", "HAMACHI_RESULT host checks=9 failures=0suffix"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                validate_result("host", 0, text)

    def test_duplicate_result(self):
        with self.assertRaises(ValueError):
            validate_result("host", 0, "HAMACHI_RESULT host checks=99 failures=0\n" * 2)

    def test_other_case_result(self):
        with self.assertRaises(ValueError):
            validate_result("host", 0, "HAMACHI_RESULT good checks=99 failures=0\n")

    def test_unknown_case(self):
        with self.assertRaises(ValueError):
            validate_result("unknown", 0, "HAMACHI_RESULT unknown checks=99 failures=0\n")

    def test_errors_rejected_despite_green_marker(self):
        for error in ("ERROR: fault", "  SCRIPT ERROR: fault", "\x1b[31m  ERROR: fault\x1b[0m"):
            with self.subTest(error=error), self.assertRaises(ValueError):
                validate_result("host", 0, error + "\nHAMACHI_RESULT host checks=99 failures=0\n")

    def test_real_false_green_process(self):
        process = subprocess.run([sys.executable, "-c", "print('ERROR: synthetic fault'); print('HAMACHI_RESULT host checks=99 failures=0')"], capture_output=True, text=True, check=True, timeout=5)
        with self.assertRaises(ValueError):
            validate_result("host", process.returncode, process.stdout)

    def test_readiness_fails_if_process_exited(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "host.log"
            log.write_text("HAMACHI_HOST_READY\n")
            with self.assertRaises(RuntimeError):
                wait_ready(Mock(poll=lambda: 0), log, timeout=0.05)

    def test_readiness_rejects_error_before_ready(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "host.log"
            log.write_text("  ERROR: broken\nHAMACHI_HOST_READY\n")
            with self.assertRaises(RuntimeError):
                wait_ready(Mock(poll=lambda: None), log, timeout=0.05)

    def test_readiness_timeout(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "host.log"
            log.write_text("")
            with self.assertRaises(TimeoutError):
                wait_ready(Mock(poll=lambda: None), log, timeout=0.05)

    def test_managed_process_terminates_on_exception(self):
        process = None
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(RuntimeError):
                with managed_process([sys.executable, "-c", "import time; time.sleep(30)"], Path(tmp) / "process.log", os.environ.copy()) as process:
                    raise RuntimeError("synthetic consumer failure")
            self.assertIsNotNone(process)
            assert process is not None
            self.assertIsNotNone(process.poll())

    def test_real_process_timeout_is_not_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            with managed_process([sys.executable, "-c", "import time; time.sleep(30)"], Path(tmp) / "process.log", os.environ.copy()) as process:
                with self.assertRaises(subprocess.TimeoutExpired):
                    process.wait(timeout=0.05)
            self.assertIsNotNone(process.poll())


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(HamachiRunnerTests)
    if suite.countTestCases() < 16:
        raise SystemExit("Insufficient runner negative controls")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
