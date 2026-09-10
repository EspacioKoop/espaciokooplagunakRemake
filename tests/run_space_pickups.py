#!/usr/bin/env python3
"""Run pickup logic, affected regressions and two real ENet processes."""
import argparse
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
ERROR = re.compile(r"(?:SCRIPT ERROR|ERROR):|Unicode parsing error|failures=[1-9]")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")))
    args = parser.parse_args()
    env = {**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"}
    def command(script):
        return [args.godot, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests" / script), "--", "--test"]
    for script in ["test_space_pickups.gd", "test_ship_physics.gd", "test_ship_quadrants_collisions.gd", "test_core.gd", "test_operations.gd", "test_loadout_editor.gd"]:
        result = subprocess.run(command(script), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, timeout=90)
        print(result.stdout, end="", flush=True)
        if result.returncode or ERROR.search(result.stdout):
            raise SystemExit("Failed: " + script)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="lagunak-pickups-") as temporary:
        directory = Path(temporary)
        peers = []
        try:
            for mode in ["host", "client"]:
                log = directory / (mode + ".log")
                stream = log.open("w")
                process = subprocess.Popen(command("test_space_pickups_network.gd") + ["--case", mode, "--port", str(port), "--coordination", temporary], stdout=stream, stderr=subprocess.STDOUT, env=env)
                peers.append((mode, process, stream, log))
                if mode == "host":
                    deadline = time.monotonic() + 15
                    while not (directory / "host-ready").exists() and time.monotonic() < deadline and process.poll() is None:
                        time.sleep(0.025)
                    if not (directory / "host-ready").exists():
                        raise RuntimeError("Host did not start: " + log.read_text())
            failed = []
            for mode, process, stream, log in peers:
                code = process.wait(timeout=50)
                stream.close()
                output = log.read_text()
                print(output, end="", flush=True)
                if code or ERROR.search(output) or "SPACE_PICKUP_NETWORK_RESULT " + mode not in output:
                    failed.append(mode)
            if failed:
                raise RuntimeError("ENet failures: " + ", ".join(failed))
        finally:
            for _, process, stream, _ in peers:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)
                stream.close()
    print("SPACE_PICKUPS_OK")

if __name__ == "__main__":
    main()
