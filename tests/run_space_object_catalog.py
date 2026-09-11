#!/usr/bin/env python3
"""Run the station-template catalog through the real Godot production scripts."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=str(ROOT / ".toolchain/godot"))
    args = parser.parse_args()
    command = [
        args.godot,
        "--headless",
        "--audio-driver",
        "Dummy",
        "--path",
        str(ROOT / "game"),
        "--script",
        str(ROOT / "tests/test_space_object_catalog.gd"),
        "--",
        "--test",
    ]
    with tempfile.TemporaryDirectory(prefix="lagunak-space-object-catalog-") as directory:
        env = dict(os.environ, XDG_DATA_HOME=directory, XDG_CONFIG_HOME=directory)
        try:
            result = subprocess.run(
                command,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=120,
            )
        except subprocess.TimeoutExpired as error:
            output = error.stdout or ""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            print(output, end="")
            print("space-object catalog test timed out")
            return 124
    print(result.stdout, end="")
    if result.returncode:
        return result.returncode
    if re.search(r"^(?:SCRIPT ERROR|ERROR):", result.stdout, re.MULTILINE):
        return 1
    if not re.search(r"SPACE_OBJECT_CATALOG_RESULT checks=\d+ failures=0", result.stdout):
        print("missing successful space-object catalog marker")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
