import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
TOOL = ROOT / "tools/issue32_benchmark.py"


def run_benchmark(*args):
    return subprocess.run(
        [sys.executable, str(TOOL), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


class Issue32BenchmarkTests(unittest.TestCase):
    def test_all_profiles_are_deterministic_and_emit_schema(self):
        with tempfile.TemporaryDirectory(prefix="issue32-benchmark-") as directory:
            output_path = Path(directory) / "report.json"
            result = run_benchmark(
                "--profile", "all", "--rounds", "1", "--json", str(output_path)
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(output_path.read_text())
            self.assertEqual(data["schema"], 1)
            self.assertTrue(data["pass"])
            self.assertEqual(
                {profile["profile"] for profile in data["profiles"]},
                {"low", "recommended"},
            )
            self.assertTrue(
                all(profile["metrics"]["deterministic"] for profile in data["profiles"])
            )
            self.assertTrue(
                all(not profile["limits"]["enforced"] for profile in data["profiles"])
            )

    def test_invalid_rounds_are_rejected(self):
        result = run_benchmark("--rounds", "0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--rounds must be between 1 and 20", result.stderr)


if __name__ == "__main__":
    unittest.main()
