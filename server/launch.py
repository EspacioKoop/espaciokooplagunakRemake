#!/usr/bin/env python3
"""Run Godot as the only gameplay authority and translate SIGTERM into a clean save."""
from pathlib import Path
import json
import os
import signal
import subprocess
import sys
import time
from server_config import ConfigError, configuration

ROOT = Path(__file__).resolve().parents[1]

def main():
    stopping = False
    def request_stop(_signum, _frame):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    try:
        settings = configuration()
        runtime = Path(os.environ.get("LAGUNAK_RUNTIME_DIR", "/tmp/lagunak-runtime"))
        data = Path(os.environ.get("XDG_DATA_HOME", "/var/lib/lagunak"))
        if not runtime.is_absolute() or not data.is_absolute():
            raise ConfigError("Runtime and data directories must be absolute")
        runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        data.mkdir(parents=True, exist_ok=True)
        # The deployment must fail before opening the game if persistence is unwritable.
        probe = data / ".write-probe"
        probe.write_bytes(b"")
        probe.unlink()
        for name in ["health.json", "stop"]:
            (runtime / name).unlink(missing_ok=True)
        settings_path = runtime / "settings.json"
        settings_path.write_text(json.dumps(settings), encoding="utf8")
        settings_path.chmod(0o600)
    except (ConfigError, OSError):
        print("SERVER_CONFIG_ERROR: check the key file, validated settings and writable data volume", file=sys.stderr)
        return 2
    env = {**os.environ, "XDG_DATA_HOME": str(data), "LAGUNAK_RUNTIME_DIR": str(runtime), "LAGUNAK_SETTINGS": str(settings_path)}
    binary = env.get("GODOT", "godot")
    try:
        child = subprocess.Popen([binary, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"), "--script", str(ROOT / "server/dedicated.gd")], env=env)
    except OSError:
        print("SERVER_START_ERROR: Godot could not be started", file=sys.stderr)
        return 2
    deadline = None
    try:
        while child.poll() is None:
            if stopping and deadline is None:
                (runtime / "stop").touch()
                deadline = time.monotonic() + 12
            if deadline is not None and time.monotonic() >= deadline:
                child.kill()
                print("SERVER_STOP_ERROR: clean shutdown timed out", file=sys.stderr)
                return 1
            time.sleep(.1)
        return child.returncode
    finally:
        if child.poll() is None:
            child.kill()
        child.wait(timeout=3)
        (runtime / "health.json").unlink(missing_ok=True)
        settings_path.unlink(missing_ok=True)

if __name__ == "__main__":
    sys.exit(main())
