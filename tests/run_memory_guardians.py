#!/usr/bin/env python3
"""Validate memory model provenance and exercise the actual standalone deck.

--capture needs an available DISPLAY (CI uses xvfb-run). --binary runs the
same scene exercise against an exported Linux executable, not the editor.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(command, env):
    result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    print(result.stdout, end="")
    if result.returncode or "SCRIPT ERROR:" in result.stdout or "\nERROR:" in result.stdout:
        raise SystemExit(result.returncode or 1)
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("GODOT", ROOT / ".toolchain/godot")))
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--capture", type=Path)
    args = parser.parse_args()
    manifest = json.loads((ROOT / "game/assets/models/memory_guardians.manifest.json").read_text())
    assert manifest["version"] == 1 and manifest["license"] == "MIT"
    for key, hash_key in [("source", "source_sha256"), ("file", "sha256")]:
        path = (ROOT / manifest[key]).resolve()
        assert path.is_relative_to(ROOT) and path.is_file()
        assert hashlib.sha256(path.read_bytes()).hexdigest() == manifest[hash_key], path
    binary = (ROOT / manifest["file"]).read_bytes()
    magic, version, size, json_size, chunk_type = struct.unpack_from("<4sIIII", binary)
    assert magic == b"glTF" and version == 2 and size == len(binary) and chunk_type == 0x4E4F534A
    gltf = json.loads(binary[20:20 + json_size])
    names = [node.get("name", "") for node in gltf["nodes"]]
    assert all(name in names for name in manifest["submodels"])
    assert len([name for name in names if name.startswith("Gaze")]) == 2
    print("MEMORY_ASSETS: .blend and GLB hashes, three roots and two gaze pivots verified")
    env = os.environ.copy()
    if not args.binary:
        run([str(args.godot), "--headless", "--editor", "--path", str(ROOT / "game"), "--quit"], env)
    command = [str(args.binary or args.godot)]
    if not args.binary:
        command += ["--path", str(ROOT / "game")]
    if args.capture:
        args.capture = args.capture.resolve()
        args.capture.parent.mkdir(parents=True, exist_ok=True)
        env["MEMORY_CAPTURE_PATH"] = str(args.capture)
        env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        command += ["--resolution", "1600x900", "--position", "0,0"]
    else:
        command += ["--headless"]
    command += ["--audio-driver", "Dummy"]
    if args.binary:
        command += ["--", "--test", "--memory-capture" if args.capture else "--memory-smoke"]
    else:
        command += ["--script", str(ROOT / "tests/test_memory_guardians.gd"), "--", "--test"]
        if args.capture:
            command += ["--memory-test-capture"]
    output = run(command, env)
    assert ("MEMORY_EXPORT_TESTS" if args.binary else "MEMORY_TESTS") in output and "; 0 failures" in output
    if args.capture:
        data = args.capture.read_bytes()
        assert data[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", data[16:24]) == (1600, 900)
        print("MEMORY_CAPTURE: actual standalone viewport verified at 1600x900")


if __name__ == "__main__":
    main()
