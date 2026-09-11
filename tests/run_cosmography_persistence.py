#!/usr/bin/env python3
"""Run the standalone cosmography persistence contract with Godot 4."""
from pathlib import Path
import os
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
project = root / "game"
godot = os.environ.get("GODOT", str(root / ".toolchain/godot"))
if "--godot" in sys.argv:
    index = sys.argv.index("--godot")
    if index + 1 >= len(sys.argv): raise SystemExit("--godot requiere una ruta")
    godot = sys.argv[index + 1]
elif len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
    godot = sys.argv[1]
command = [godot, "--headless", "--path", str(project), "--script",
           "res://../tests/test_cosmography_persistence.gd", "--", "--test"]
raise SystemExit(subprocess.run(command, cwd=root, text=True).returncode)
