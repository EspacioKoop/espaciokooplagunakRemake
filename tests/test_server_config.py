"""Negative deployment boundaries and healthcheck, independent of Docker availability."""
from pathlib import Path
import json
import os
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from server_config import ConfigError, configuration, read_key
from healthcheck import healthy

class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.key = self.directory / "key"
        self.key.write_text("synthetic-deployment-key\n")
        self.env = {"LAGUNAK_KEY_FILE": str(self.key)}
    def tearDown(self):
        self.temp.cleanup()
    def test_configuration_contains_no_key_value(self):
        value = configuration(self.env)
        self.assertEqual(value["port"], 27840)
        self.assertEqual(value["mission_index"], -1)
        self.assertNotIn("synthetic-deployment-key", json.dumps(value))
    def test_ports_mission_and_modes_fail_closed(self):
        for option, cases in {"LAGUNAK_PORT": ["0", "65536", "-1", "27840x", " 27840", "1e4"], "LAGUNAK_MISSION_INDEX": ["-2", "256", "0.5", ""], "LAGUNAK_LOAD_MODE": ["replace", "", "AUTO"]}.items():
            for value in cases:
                with self.subTest(option=option, value=value), self.assertRaises(ConfigError):
                    configuration({**self.env, option: value})
    def test_secret_file_required(self):
        for path in ["", "relative-key", str(self.directory), str(self.directory / "missing")]:
            with self.assertRaises(ConfigError): configuration({"LAGUNAK_KEY_FILE": path})
    def test_secret_limits_and_injection(self):
        for value in [b"short", b"a" * 129, b"a" * 128 + b"\n" * 4 + b"trailer", b"x" * 16 + b"\x00", b"a b" * 12, b"\xff" * 20]:
            self.key.write_bytes(value)
            with self.assertRaises(ConfigError): read_key(str(self.key))
    def test_health_requires_live_process_and_recent_host_tick(self):
        path = self.directory / "health.json"
        self.assertFalse(healthy(self.directory))
        path.write_text(json.dumps({"version": 1, "host": True, "pid": os.getpid()}))
        self.assertTrue(healthy(self.directory))
        os.utime(path, (time.time() - 10, time.time() - 10))
        self.assertFalse(healthy(self.directory))
        for value in [{"version": 1, "host": False, "pid": os.getpid()}, {"version": 1, "host": True, "pid": -1}, [], "bad"]:
            path.write_text(json.dumps(value))
            self.assertFalse(healthy(self.directory))

if __name__ == "__main__": unittest.main()
