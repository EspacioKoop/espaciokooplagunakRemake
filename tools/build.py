#!/usr/bin/env python3
"""Export the standalone applications using the pinned official Godot templates."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT", ROOT / ".toolchain/godot"))
env = os.environ.copy()
env["XDG_DATA_HOME"] = str(ROOT / ".toolchain/data")
template_dir = ROOT / ".toolchain/data/godot/export_templates/4.7.1.stable"
if not GODOT.exists() or not (template_dir / "linux_release.x86_64").exists():
    subprocess.run([sys.executable, str(ROOT / "tools/bootstrap.py"), "--templates"], check=True)
for platform, filename in [("Linux", "linux/EspaciokoopLagunak.x86_64"), ("Windows", "windows/EspaciokoopLagunak.exe")]:
    target = ROOT / "build" / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(GODOT), "--headless", "--path", str(ROOT / "game"), "--export-release", platform, str(target)], env=env, check=True)
    assert target.stat().st_size > 1000000, f"Invalid export: {target}"
    if platform == "Linux": target.chmod(0o755)
    print("EXPORTED", target.name, target.stat().st_size)
