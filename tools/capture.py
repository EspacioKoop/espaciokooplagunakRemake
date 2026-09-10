#!/usr/bin/env python3
"""Capture eight real application views using an isolated Xvfb display."""
import argparse
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "docs/images")
    parser.add_argument("--binary", type=Path)
    args = parser.parse_args()
    binary = args.binary or ROOT / ".toolchain/godot"
    display_root = ROOT / ".toolchain/display"
    xvfb = shutil.which("Xvfb") or str(display_root / "usr/bin/Xvfb")
    args.output.mkdir(parents=True, exist_ok=True)
    # Keep display and game within one process group; this also works in isolated runners.
    display = 99
    env = os.environ.copy()
    env["DISPLAY"] = f"127.0.0.1:{display}"
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    libs = display_root / "usr/lib/x86_64-linux-gnu"
    env["LD_LIBRARY_PATH"] = str(libs) + ":" + env.get("LD_LIBRARY_PATH", "")
    with tempfile.TemporaryDirectory(prefix="lagunak-display-") as temporary:
        auth = Path(temporary) / "authority"
        def field(value): return struct.pack(">H", len(value)) + value
        auth.write_bytes(struct.pack(">H", 65535) + field(b"") + field(str(display).encode()) + field(b"MIT-MAGIC-COOKIE-1") + field(os.urandom(16)))
        auth.chmod(0o600)
        env["XAUTHORITY"] = str(auth)
        command = [xvfb, ":" + str(display), "-screen", "0", "1600x900x24", "-listen", "tcp", "-nolisten", "unix", "-nolisten", "local", "-auth", str(auth)]
        xkb = display_root / "usr/share/X11/xkb"
        if xkb.exists(): command += ["-xkbdir", str(xkb)]
        server = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                if server.poll() is not None:
                    raise RuntimeError(server.stderr.read().decode())
                try:
                    with socket.create_connection(("127.0.0.1", 6000 + display), timeout=.1): pass
                    break
                except OSError: time.sleep(.05)
            command = [str(binary)]
            if args.binary is None: command += ["--path", str(ROOT / "game")]
            command += ["--resolution", "1600x900", "--position", "0,0", "--audio-driver", "Dummy", "--", "--capture", "--capture-dir", str(args.output.resolve())]
            result = subprocess.run(command, env=env, cwd=ROOT, timeout=180)
            if result.returncode: raise SystemExit(result.returncode)
        finally:
            server.terminate()
            try: server.wait(timeout=5)
            except subprocess.TimeoutExpired: server.kill(); server.wait()
        for filename in ["01_inicio", "02_puente", "03_ingenieria", "04_cubierta", "05_reactor", "06_atlas", "07_campana", "08_editor"]:
            data = (args.output / (filename + ".png")).read_bytes()
            assert data[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", data[16:24]) == (1600, 900), filename
        print("Verified eight real screenshots at 1600×900.")

if __name__ == "__main__": main()
