#!/usr/bin/env python3
"""Negative controls for the runner and fixed model bindings to canonical manifests."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import run_tactical_models as runner


def output(**changes: object) -> str:
    report = {"checks": 339, "failures": 0, "passed": True, "capture": False}
    report.update(changes)
    return "TACTICAL_MODELS_RESULT " + json.dumps(report) + "\n"


class RunnerTests(unittest.TestCase):
    def test_success(self) -> None:
        self.assertEqual(runner.validate(0, output(), False)["checks"], 339)
        self.assertTrue(runner.validate(0, output(capture=True), True)["passed"])

    def test_exit_status(self) -> None:
        with self.assertRaises(ValueError):
            runner.validate(1, output(), False)

    def test_engine_errors_even_with_success(self) -> None:
        for error in ["ERROR: synthetic", " SCRIPT ERROR: synthetic", "\x1b[31mERROR:\x1b[0m synthetic", "Unicode parsing error"]:
            with self.subTest(error=error), self.assertRaises(ValueError):
                runner.validate(0, error + "\n" + output(), False)

    def test_single_structured_report_required(self) -> None:
        for text in ["", "TACTICAL_MODELS_OK 339 checks", output() * 2, "TACTICAL_MODELS_RESULT {\n", "TACTICAL_MODELS_RESULT []\n"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                runner.validate(0, text, False)

    def test_report_types_and_failures(self) -> None:
        for change in [{"checks": 0}, {"checks": -1}, {"checks": True}, {"checks": 1.0}, {"failures": 1}, {"failures": False}, {"passed": 1}, {"passed": False}, {"capture": True}, {"capture": 0}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                runner.validate(0, output(**change), False)

    def test_graphics_cannot_reuse_headless_report(self) -> None:
        with self.assertRaises(ValueError):
            runner.validate(0, output(), True)

    def test_real_child_process_output(self) -> None:
        child = subprocess.run([sys.executable, "-c", "print('ERROR: synthetic')\nprint(" + repr(output()) + ")"], text=True, capture_output=True, check=True)
        with self.assertRaises(ValueError):
            runner.validate(child.returncode, child.stdout, False)

    def test_profile_isolation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = runner.environment(root)
            keys = ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"]
            self.assertEqual(len({env[k] for k in keys}), len(keys))
            self.assertTrue(all(Path(env[k]).is_dir() and Path(env[k]).is_relative_to(root) for k in keys))

    def test_exported_pack_has_no_loose_project_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            pack = Path(directory) / "game.pck"
            result = subprocess.CompletedProcess([], 0, output(), "")
            with patch.object(sys, "argv", ["runner", "--pack", str(pack)]), patch.object(runner.subprocess, "run", return_value=result) as run:
                self.assertEqual(runner.main(), 0)
            arguments = run.call_args.args[0]
            self.assertIn("--main-pack", arguments)
            self.assertNotIn("--path", arguments)
            self.assertNotEqual(Path(run.call_args.kwargs["cwd"]), runner.ROOT)
            self.assertEqual(arguments[arguments.index("--audio-driver") + 1], "Dummy")

    def test_capture_must_be_new(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "stale.png"
            image.write_bytes(b"\x89PNG\r\n\x1a\n" + b"stale" * 300)
            result = subprocess.CompletedProcess([], 0, output(capture=True), "")
            with patch.object(sys, "argv", ["runner", "--capture", str(image)]), patch.object(runner.subprocess, "run", return_value=result):
                self.assertEqual(runner.main(), 1)
            self.assertFalse(image.exists())

    def test_timeout_fails(self) -> None:
        with patch.object(sys, "argv", ["runner"]), patch.object(runner.subprocess, "run", side_effect=subprocess.TimeoutExpired("godot", 180)):
            self.assertEqual(runner.main(), 1)


class BindingTests(unittest.TestCase):
    def test_every_fixed_model_matches_its_manifest(self) -> None:
        root = runner.ROOT
        paths: set[str] = set()
        for consumer in ["game/world/tactical_models.gd", "game/world/pickup_model.gd"]:
            paths.update(re.findall(r'"(res://assets/models/[^"\n]+\.glb)"', (root / consumer).read_text(encoding="utf-8")))
        self.assertEqual(len(paths), 10, "Update the explicit tested consumer count when adding a binding")
        records = {}
        for manifest in (root / "game/assets/models").rglob("manifest.json"):
            document = json.loads(manifest.read_text(encoding="utf-8"))
            if not isinstance(document, dict):
                continue
            for asset in document.get("assets", []):
                resource = asset.get("resource", asset.get("glb", ""))
                if resource in paths:
                    self.assertNotIn(resource, records, "A resource has one authoritative manifest")
                    records[resource] = asset
        self.assertEqual(set(records), paths)
        for resource, asset in records.items():
            with self.subTest(resource=resource):
                data = (root / "game" / resource.removeprefix("res://")).read_bytes()
                self.assertEqual(struct.unpack_from("<4sII", data), (b"glTF", 2, len(data)))
                self.assertEqual(hashlib.sha256(data).hexdigest(), asset["sha256"])
                self.assertEqual(asset["units"], "metres")
                self.assertEqual(asset["license"], "MIT")
                self.assertEqual(hashlib.sha256((root / asset["source"]).read_bytes()).hexdigest(), asset["source_sha256"])
                if asset.get("category") == "weapons":
                    names = [s["name"] if isinstance(s, dict) else s for s in asset["sockets"]]
                    self.assertIn("socket_grip", names)
                    self.assertEqual(asset.get("attachment_socket"), "socket_grip")


if __name__ == "__main__":
    unittest.main(verbosity=2)
