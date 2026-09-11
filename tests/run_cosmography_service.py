#!/usr/bin/env python3
"""Run the campaign-facing cosmography service regression."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RESULT = re.compile(r"^COSMOGRAPHY_SERVICE_RESULT checks=([1-9][0-9]*) failures=0$", re.M)
DIAGNOSTIC = re.compile(r"^(?:SCRIPT ERROR|ERROR|COSMOGRAPHY_SERVICE_FAIL)\b", re.M)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=str(ROOT / ".toolchain/godot"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="lagunak-cosmography-service-") as folder:
        env = dict(os.environ)
        for name in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
            path = Path(folder) / name.lower()
            path.mkdir(parents=True, exist_ok=True)
            env[name] = str(path)
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        command = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
                   "--script", str(ROOT / "tests/test_cosmography_service.gd"), "--", "--test"]
        try:
            completed = subprocess.run(command, cwd=ROOT, env=env, text=True, encoding="utf-8",
                                       errors="replace", stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        except (OSError, subprocess.TimeoutExpired) as error:
            print(f"COSMOGRAPHY_SERVICE_RUNNER_FAIL {error}")
            return 1
        print(completed.stdout, end="")
        matches = RESULT.findall(completed.stdout)
        if completed.returncode != 0 or len(matches) != 1 or DIAGNOSTIC.search(completed.stdout):
            print("COSMOGRAPHY_SERVICE_RUNNER_FAIL invalid Godot result")
            return 1
    print(f"COSMOGRAPHY_SERVICE_RUNNER_OK checks={matches[0]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
