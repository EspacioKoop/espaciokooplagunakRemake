"""Runner unit tests. These do NOT replace the real Godot integration test."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import run_alert_late_join as runner


class RunnerTests(unittest.TestCase):
    def test_exact_success(self):
        self.assertEqual(runner.result_checks("host", 0, "ALERT_RESULT host checks=21 failures=0\n"), 21)

    def test_failure_outputs(self):
        outputs = [
            "", "ALERT_RESULT host checks=0 failures=0\n", "ALERT_RESULT host checks=21 failures=1\n",
            "ALERT_RESULT armas checks=21 failures=0\n",
            "ALERT_RESULT host checks=21 failures=0\n" * 2,
            "SCRIPT ERROR: failed\nALERT_RESULT host checks=21 failures=0\n",
            "  ERROR: failed\nALERT_RESULT host checks=21 failures=0\n",
            "\x1b[31mERROR:\x1b[0m failed\nALERT_RESULT host checks=21 failures=0\n",
            "Parse Error: failed\nALERT_RESULT host checks=21 failures=0\n",
        ]
        for output in outputs:
            with self.subTest(output=output):
                with self.assertRaises(RuntimeError):
                    runner.result_checks("host", 0, output)

    def test_nonzero_exit_never_passes(self):
        with self.assertRaises(RuntimeError):
            runner.result_checks("host", 1, "ALERT_RESULT host checks=21 failures=0\n")

    def test_environment_isolation(self):
        original = os.environ.copy()
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            first = runner.isolated_environment(base / "one")
            second = runner.isolated_environment(base / "two")
            for name in ["HOME", "USERPROFILE", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"]:
                self.assertNotEqual(first[name], second[name])
                self.assertTrue(Path(first[name]).is_relative_to(base))
                self.assertTrue(Path(first[name]).is_dir())
        self.assertEqual(dict(os.environ), dict(original))

    def test_invalid_ports(self):
        for port in [-1, 1, 1023, 65536]:
            with self.subTest(port=port), self.assertRaises(ValueError):
                runner.select_port(port)
        self.assertEqual(runner.select_port(23456), 23456)

    def test_port_selection_closes_probe(self):
        probe = Mock()
        probe.getsockname.return_value = ("0.0.0.0", 34567)
        context = Mock()
        context.__enter__ = Mock(return_value=probe)
        context.__exit__ = Mock(return_value=False)
        with patch.object(runner.socket, "socket", return_value=context):
            self.assertEqual(runner.select_port(0), 34567)
        probe.bind.assert_called_once_with(("0.0.0.0", 0))
        context.__exit__.assert_called_once()

    def test_cleanup_kills_stubborn_child_and_closes_all_logs(self):
        stubborn, ended = Mock(), Mock()
        stubborn.poll.return_value = None
        stubborn.wait.side_effect = [subprocess.TimeoutExpired("godot", 3), 0]
        ended.poll.return_value = 0
        streams = [Mock(), Mock()]
        children = [runner.Child("host", stubborn, streams[0], Path("host.log")),
                    runner.Child("armas", ended, streams[1], Path("armas.log"))]
        runner.stop_children(children)
        stubborn.terminate.assert_called_once()
        stubborn.kill.assert_called_once()
        ended.terminate.assert_not_called()
        for stream in streams:
            stream.close.assert_called_once()

    def test_failed_import_invalidates_previous_success_report(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            (output / "result.json").write_text('{"ok": true}')
            completed = subprocess.CompletedProcess([], 0, "SCRIPT ERROR: broken\n", "")
            with patch.object(runner.subprocess, "run", return_value=completed):
                with self.assertRaisesRegex(RuntimeError, "import failed"):
                    runner.run("godot", output, requested_port=23456)
            self.assertFalse(runner.json.loads((output / "result.json").read_text())["ok"])
            self.assertIn("SCRIPT ERROR", (output / "import.log").read_text())

    def test_failed_process_start_leaves_report(self):
        with tempfile.TemporaryDirectory() as temp:
            with patch.object(runner.subprocess, "run", side_effect=FileNotFoundError("missing Godot")):
                with self.assertRaises(FileNotFoundError):
                    runner.run("godot", Path(temp), requested_port=23456)
            report = runner.json.loads((Path(temp) / "result.json").read_text())
            self.assertFalse(report["ok"])
            self.assertEqual(report["cases"], {})

    def test_timeout_validation(self):
        with self.assertRaises(ValueError):
            runner.run("godot", Path("unused"), timeout=1)

    def test_roles_are_eight_distinct_stations(self):
        self.assertEqual(len(runner.CASES), 8)
        self.assertEqual(len(set(runner.CASES)), 8)
        self.assertEqual(runner.CASES[0], "host")


if __name__ == "__main__":
    unittest.main()
