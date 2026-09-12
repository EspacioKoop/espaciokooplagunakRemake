#!/usr/bin/env python3
"""Run the isolated cosmography navigation adapter with a pinned Godot binary."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MARKER = re.compile(r"COSMOGRAPHY_NAVIGATION_RESULT checks=(\d+) failures=0")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=str(ROOT / ".toolchain/godot"))
    args = parser.parse_args()
    command = [args.godot, "--headless", "--path", str(ROOT / "game"),
               "--audio-driver", "Dummy", "--script",
               str(ROOT / "tests/test_cosmography_navigation.gd"), "--", "--test"]
    with tempfile.TemporaryDirectory(prefix="lagunak-cosmography-navigation-") as directory:
        env = dict(os.environ, XDG_DATA_HOME=directory, XDG_CONFIG_HOME=directory)
        try:
            result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=60)
            output = result.stdout
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            print(output, end="", flush=True)
            raise SystemExit("Cosmography navigation test timed out before its completion marker") from error
    print(output, end="", flush=True)
    if result.returncode or re.search(r"^(?:SCRIPT ERROR|ERROR):", output, re.MULTILINE):
        return 1
    if not MARKER.search(output):
        raise SystemExit("Missing successful cosmography navigation completion marker")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
