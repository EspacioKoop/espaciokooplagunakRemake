#!/usr/bin/env python3
"""Run the standalone cosmography persistence contract with Godot 4."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
project = root / "game"
godot = sys.argv[1] if len(sys.argv) > 1 else "godot"
command = [godot, "--headless", "--path", str(project), "--script",
           "res://../tests/test_cosmography_persistence.gd", "--", "--test"]
raise SystemExit(subprocess.run(command, cwd=root, text=True).returncode)
