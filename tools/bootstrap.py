#!/usr/bin/env python3
"""Download pinned official Godot binaries and verify their published SHA-512."""
import argparse
import hashlib
import platform
from pathlib import Path
import shutil
import urllib.request
import zipfile
from export_targets import GODOT_VERSION, TARGETS, add_target_argument, selected_targets, template_directory

ROOT = Path(__file__).resolve().parents[1]
VERSION = GODOT_VERSION
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/"
CACHE = ROOT / ".toolchain"

def download(name):
    CACHE.mkdir(exist_ok=True)
    sums = urllib.request.urlopen(BASE + "SHA512-SUMS.txt", timeout=60).read().decode()
    expected = next(line.split()[0] for line in sums.splitlines() if line.split()[-1].lstrip("*") == name)
    path = CACHE / name
    if path.exists():
        with path.open("rb") as source:
            if hashlib.file_digest(source, "sha512").hexdigest() == expected:
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
    parser.add_argument("--templates-only", action="store_true", help="Keep an existing GODOT editor; install only selected templates.")
    add_target_argument(parser)
    args = parser.parse_args()
    binary = CACHE / "godot"
    if not args.templates_only:
        if platform.system() != "Linux" or platform.machine().lower() not in ("x86_64", "amd64"):
            parser.error("This bootstrap installs the Linux x86_64 cross-export editor. Use a Linux build host or --templates-only with your own editor.")
        archive = download(f"Godot_v{VERSION}-stable_linux.x86_64.zip")
        with zipfile.ZipFile(archive) as z:
            member = next(n for n in z.namelist() if n.endswith("linux.x86_64"))
            with z.open(member) as source, binary.open("wb") as dest:
                shutil.copyfileobj(source, dest)
        binary.chmod(0o755)
    if args.templates or args.templates_only:
        archive = download(f"Godot_v{VERSION}-stable_export_templates.tpz")
        dest = template_directory(ROOT)
        dest.mkdir(parents=True, exist_ok=True)
        filenames = ["version.txt"]
        for name in selected_targets(args.targets):
            filenames.extend(TARGETS[name].templates)
        with zipfile.ZipFile(archive) as z:
            for filename in filenames:
                with z.open("templates/" + filename) as source, (dest / filename).open("wb") as target:
                    shutil.copyfileobj(source, target)
        print("Templates ready:", ", ".join(selected_targets(args.targets)), flush=True)
    if not args.templates_only:
        print("Godot ready:", binary, flush=True)

if __name__ == "__main__":
    main()
