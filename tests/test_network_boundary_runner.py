"""Runner checks use no Godot, sockets, account data or network access."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from run_network_boundary import Job, isolated_environment, main, stop_job, validate_result


class ResultTests(unittest.TestCase):
    def test_success(self):
        validate_result("host", 0, "Godot\nNETWORK_BOUNDARY_RESULT host checks=7 failures=0\n")

    def test_nonzero_exit(self):
        with self.assertRaises(RuntimeError):
            validate_result("host", 1, "NETWORK_BOUNDARY_RESULT host checks=7 failures=0")

    def test_missing_wrong_empty_failed_or_duplicate_result(self):
        cases = ["", "NETWORK_BOUNDARY_RESULT client checks=7 failures=0",
                 "NETWORK_BOUNDARY_RESULT host checks=0 failures=0",
                 "NETWORK_BOUNDARY_RESULT host checks=7 failures=1",
                 "NETWORK_BOUNDARY_RESULT host checks=7 failures=0\n" * 2,
                 "NETWORK_BOUNDARY_RESULT host checks=7 failures=0 suffix"]
        for output in cases:
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                validate_result("host", 0, output)

    def test_errors_fail_even_with_success_marker(self):
        for error in ["SCRIPT ERROR: broken", "  ERROR: broken", "FATAL: broken",
                      "\x1b[31mERROR:\x1b[0m broken"]:
            with self.subTest(error=error), self.assertRaises(RuntimeError):
                validate_result("host", 0, error + "\nNETWORK_BOUNDARY_RESULT host checks=1 failures=0")

    def test_environment_isolated_without_mutating_parent(self):
        base = {"HOME": "/real/home", "XDG_DATA_HOME": "/real/data", "PATH": "/bin"}
        before = base.copy()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = isolated_environment(base, root, "synthetic-only")
            for variable in ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
                             "APPDATA", "LOCALAPPDATA"]:
                path = Path(result[variable])
                self.assertTrue(path.is_dir())
                self.assertTrue(path.is_relative_to(root))
            self.assertEqual(result["PATH"], base["PATH"])
            self.assertEqual(result["LAGUNAK_BOUNDARY_KEY"], "synthetic-only")
        self.assertEqual(base, before)

    def test_cleanup_terminates_live_process(self):
        process, stream = Mock(), Mock()
        process.poll.return_value = None
        stop_job(Job("host", process, stream, Path("unused")))
        process.terminate.assert_called_once()
        process.kill.assert_not_called()
        stream.close.assert_called_once()

    def test_cleanup_escalates_and_closes_stream(self):
        process, stream = Mock(), Mock()
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired("fixture", 2), 0]
        stop_job(Job("host", process, stream, Path("unused")))
        process.kill.assert_called_once()
        self.assertEqual(process.wait.call_count, 2)
        stream.close.assert_called_once()

    def test_cleanup_does_not_signal_finished_process(self):
        process, stream = Mock(), Mock()
        process.poll.return_value = 0
        stop_job(Job("host", process, stream, Path("unused")))
        process.terminate.assert_not_called()
        stream.close.assert_called_once()

    @patch("run_network_boundary.run", side_effect=FileNotFoundError("missing fixture engine"))
    def test_missing_engine_is_failure(self, run):
        self.assertEqual(main(["--godot", "/missing/godot"]), 1)

    @patch("run_network_boundary.run", side_effect=TimeoutError("fixture deadline"))
    def test_timeout_is_failure(self, run):
        self.assertEqual(main([]), 1)

    @patch("run_network_boundary.run", side_effect=RuntimeError("fixture failed"))
    def test_failed_case_is_failure(self, run):
        self.assertEqual(main([]), 1)

    @patch("run_network_boundary.run")
    def test_successful_orchestration_is_success(self, run):
        self.assertEqual(main(["--timeout", "75"]), 0)
        self.assertEqual(run.call_args.args[1], 75)


if __name__ == "__main__":
    unittest.main()
