#!/usr/bin/env python3
"""Run GM regression tests using synthetic data and isolated user directories."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
RESULT = re.compile(r"^GM_LIVE_RESULT checks=([1-9][0-9]*) failures=0$", re.M)


def validate_output(code: int, output: str) -> bool:
    clean = ANSI.sub("", output)
    lines = clean.splitlines()
    return (code == 0 and not re.search(r"^\s*(?:SCRIPT ERROR|ERROR|GM_LIVE_FAIL)\b|Unicode parsing error", clean, re.M)
            and len(RESULT.findall(clean)) == 1
            and sum(line.startswith("GM_LIVE_RESULT") for line in lines) == 1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(ROOT / ".toolchain/godot"))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="lagunak-gm-live-") as directory:
        env = dict(os.environ)
        for name in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
            path = Path(directory) / name.lower()
            path.mkdir()
            env[name] = str(path)
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        command = [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
                   "--script", str(ROOT / "tests/test_gm_live.gd"), "--", "--test"]
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace", timeout=120, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            print(f"GM_LIVE_RUNNER_FAIL {error}")
            return 1
        output = result.stdout + result.stderr
        print(output, end="")
        if not validate_output(result.returncode, output):
            return 1
    print("GM_LIVE_RUNNER_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
