#!/usr/bin/env python3
"""Download pinned official Godot binaries and verify their published SHA-512."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.1"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/"
CACHE = ROOT / ".toolchain"

def download(name):
    CACHE.mkdir(exist_ok=True)
    sums = urllib.request.urlopen(BASE + "SHA512-SUMS.txt", timeout=60).read().decode()
    expected = next(line.split()[0] for line in sums.splitlines() if line.split()[-1].lstrip("*") == name)
    path = CACHE / name
    if path.exists() and hashlib.file_digest(path.open("rb"), "sha512").hexdigest() == expected:
        return path
    temporary = path.with_suffix(".partial")
    print("Downloading", name, flush=True)
    with urllib.request.urlopen(BASE + name, timeout=180) as response, temporary.open("wb") as target:
        shutil.copyfileobj(response, target, length=1024 * 1024)
    with temporary.open("rb") as source:
        actual = hashlib.file_digest(source, "sha512").hexdigest()
    if actual != expected:
        temporary.unlink()
        raise RuntimeError("Official checksum mismatch: " + name)
    temporary.replace(path)
    return path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--templates", action="store_true")
    args = parser.parse_args()
    archive = download(f"Godot_v{VERSION}-stable_linux.x86_64.zip")
    binary = CACHE / "godot"
    with zipfile.ZipFile(archive) as z:
        member = next(n for n in z.namelist() if n.endswith("linux.x86_64"))
        with z.open(member) as source, binary.open("wb") as dest:
            shutil.copyfileobj(source, dest)
    binary.chmod(0o755)
    if args.templates:
        archive = download(f"Godot_v{VERSION}-stable_export_templates.tpz")
        dest = CACHE / "data/godot/export_templates" / f"{VERSION}.stable"
        dest.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as z:
            for filename in ["linux_release.x86_64", "windows_release_x86_64.exe", "version.txt"]:
                with z.open("templates/" + filename) as source, (dest / filename).open("wb") as target:
                    shutil.copyfileobj(source, target)
    print("Godot ready:", binary, flush=True)

if __name__ == "__main__":
    main()
