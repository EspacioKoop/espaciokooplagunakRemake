#!/usr/bin/env python3
"""Run deterministic storage properties without reading the player's user data."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ENGINE_ERROR = re.compile(r"(?:SCRIPT ERROR|ERROR):|Unicode parsing error")
RESULT = re.compile(
    r"^STORAGE_PROPERTY_TESTS ([1-9][0-9]*) checks; ([0-9]+) failures; "
    r"seed=([0-9]+); samples=([0-9]+)$", re.MULTILINE
)


def validate_output(code: int, output: str, seed: int, samples: int) -> str:
    """An exit code alone is insufficient: Godot may log script errors and exit 0."""
    if code:
        return f"Godot exited with status {code}."
    if ENGINE_ERROR.search(output):
        return "Godot reported an engine or script error."
    matches = RESULT.findall(output)
    if len(matches) != 1:
        return "Missing or ambiguous storage test result."
    _, failures, actual_seed, actual_samples = map(int, matches[0])
    if failures or actual_seed != seed or actual_samples != samples:
        return "Failed properties or unexpected reproduction parameters."
    return ""


def isolated_environment(directory: Path) -> dict[str, str]:
    env = dict(os.environ)
    # Godot user:// and optional local preference autoloads must never see real saves.
    for variable in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
        folder = directory / variable.lower()
        folder.mkdir(parents=True, exist_ok=True)
        env[variable] = str(folder)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


class RunnerTests(unittest.TestCase):
    good = "STORAGE_PROPERTY_TESTS 42 checks; 0 failures; seed=7; samples=8\n"

    def test_success(self) -> None:
        self.assertEqual(validate_output(0, self.good, 7, 8), "")

    def test_nonzero_exit(self) -> None:
        self.assertTrue(validate_output(1, self.good, 7, 8))

    def test_missing_result(self) -> None:
        self.assertTrue(validate_output(0, "Godot started\n", 7, 8))

    def test_script_error_even_with_success(self) -> None:
        self.assertTrue(validate_output(0, "SCRIPT ERROR: failure\n" + self.good, 7, 8))

    def test_engine_error_even_with_success(self) -> None:
        self.assertTrue(validate_output(0, "ERROR: failure\n" + self.good, 7, 8))

    def test_failed_check(self) -> None:
        self.assertTrue(validate_output(0, self.good.replace("0 failures", "1 failures"), 7, 8))

    def test_duplicate_result(self) -> None:
        self.assertTrue(validate_output(0, self.good * 2, 7, 8))

    def test_wrong_parameters(self) -> None:
        self.assertTrue(validate_output(0, self.good, 6, 8))
        self.assertTrue(validate_output(0, self.good, 7, 9))

    def test_zero_checks(self) -> None:
        self.assertTrue(validate_output(0, self.good.replace("42 checks", "0 checks"), 7, 8))

    def test_environment_isolation(self) -> None:
        before = dict(os.environ)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            env = isolated_environment(root)
            for variable in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
                self.assertTrue(Path(env[variable]).is_relative_to(root))
                self.assertTrue(Path(env[variable]).is_dir())
        self.assertEqual(dict(os.environ), before)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")))
    parser.add_argument("--seed", type=int, default=3204301)
    parser.add_argument("--samples", type=int, default=64)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(RunnerTests))
        return 0 if result.wasSuccessful() else 1
    if not 0 <= args.seed <= 2147483647 or not 1 <= args.samples <= 512:
        parser.error("seed must be 0..2147483647 and samples 1..512")
    command = [args.godot, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_storage_properties.gd"), "--", "--test", f"--seed={args.seed}", f"--samples={args.samples}"]
    with tempfile.TemporaryDirectory(prefix="lagunak-storage-properties-") as temporary:
        try:
            result = subprocess.run(command, cwd=ROOT, env=isolated_environment(Path(temporary)), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", timeout=180, check=False)
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b""
            print(output.decode("utf-8", "replace") if isinstance(output, bytes) else output, end="", flush=True)
            print("STORAGE_PROPERTIES_FAILED: Godot timed out.", flush=True)
            return 1
        except OSError as error:
            print(f"STORAGE_PROPERTIES_FAILED: cannot start Godot: {error}", flush=True)
            return 1
    print(result.stdout, end="", flush=True)
    failure = validate_output(result.returncode, result.stdout, args.seed, args.samples)
    if failure:
        print("STORAGE_PROPERTIES_FAILED: " + failure, flush=True)
        return 1
    print("STORAGE_PROPERTIES_OK", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
