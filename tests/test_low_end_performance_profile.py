#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import low_end_performance_profile as profile  # noqa: E402


class LowEndPerformanceProfileTests(unittest.TestCase):
    def test_profile_is_fixed_and_has_three_routes(self):
        self.assertEqual(profile.PROFILE["name"], "low-end")
        self.assertEqual(profile.PROFILE["resolution"], [960, 540])
        self.assertEqual(profile.ROUTES, ("ship_itsaso", "beach", "tables_3d"))
        self.assertEqual(profile.PROFILE["renderer"], "gl_compatibility")

    def test_measured_report_requires_exact_routes_and_never_certifies_hardware(self):
        report = profile.base_report(
            profile.parser().parse_args(["--mode", "headless"]), "measured"
        )
        report["routes"] = [
            {
                "id": route,
                "metrics": {"frames": 60, "elapsed_ms": 1000.0, "avg_fps": 60.0},
            }
            for route in profile.ROUTES
        ]
        profile.validate_report(report, "headless")
        report["limits"]["hardware_certified"] = True
        with self.assertRaises(ValueError):
            profile.validate_report(report, "headless")

    def test_missing_route_is_rejected(self):
        report = profile.base_report(
            profile.parser().parse_args(["--mode", "headless"]), "measured"
        )
        report["routes"] = [
            {"id": "ship_itsaso", "metrics": {"frames": 60, "elapsed_ms": 1000.0, "avg_fps": 60.0}}
        ]
        with self.assertRaises(ValueError):
            profile.validate_report(report, "headless")

    def test_missing_godot_fails_closed_and_writes_sanitized_reports(self):
        with tempfile.TemporaryDirectory(prefix="performance-test-") as temporary:
            folder = Path(temporary)
            json_path = folder / "report.json"
            markdown_path = folder / "report.md"
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tools/low_end_performance_profile.py"),
                    "--mode", "headless",
                    "--godot", str(folder / "missing-godot"),
                    "--output", str(json_path),
                    "--markdown", str(markdown_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("PERFORMANCE_PROFILE_BLOCKED", result.stdout)
            report = json.loads(json_path.read_text(encoding="utf-8"))
            self.assertEqual(report["status"], "blocked")
            self.assertEqual(report["routes"], [])
            self.assertFalse(report["limits"]["hardware_certified"])
            self.assertFalse(report["limits"]["fps_certified"])
            self.assertNotIn(str(folder), json.dumps(report))
            self.assertIn("No runtime metrics", markdown_path.read_text(encoding="utf-8"))

    def test_runner_points_to_production_scene_and_existing_routes(self):
        script = (ROOT / "tools/low_end_performance_profile.gd").read_text(encoding="utf-8")
        self.assertIn('load("res://main.tscn")', script)
        self.assertIn('"ship_itsaso"', script)
        self.assertIn('teleport_zone(9)', script)
        self.assertIn('social_table_display.gd', script)
        self.assertNotIn("Mock", script)


if __name__ == "__main__":
    unittest.main()
