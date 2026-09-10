#!/usr/bin/env python3
"""Run three actual Godot peers and inspect their structured delivery assertions."""
from pathlib import Path
import argparse
import json
import os
import re
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")))
    args = parser.parse_args()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="lagunak-aux-rpc-") as temporary:
        directory = Path(temporary)
        processes = []
        try:
            for name in ("host", "member", "guest"):
                log = directory / (name + ".log")
                stream = log.open("w")
                process = subprocess.Popen([args.godot, "--headless", "--path", str(ROOT / "game"),
                    "--script", str(ROOT / "tests/test_authenticated_aux_rpc.gd"), "--", "--test",
                    "--case", name, "--port", str(port), "--coordination", str(directory)],
                    stdout=stream, stderr=subprocess.STDOUT,
                    env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1"})
                processes.append((name, process, stream, log))
                if name == "host":
                    deadline = time.monotonic() + 12
                    while not (directory / "host-ready.json").is_file() and time.monotonic() < deadline:
                        if process.poll() is not None:
                            break
                        time.sleep(0.025)
                    if not (directory / "host-ready.json").is_file():
                        raise RuntimeError("Host did not initialize: " + log.read_text())
            failures = []
            reports = {}
            for name, process, stream, log in processes:
                code = process.wait(timeout=30)
                stream.close()
                output = log.read_text()
                print(output.strip())
                result_path = directory / (name + "-result.json")
                if result_path.is_file():
                    reports[name] = json.loads(result_path.read_text())
                if code or re.search(r"^(?:SCRIPT ERROR|ERROR):", output, re.MULTILINE) or reports.get(name, {}).get("failures", -1) != 0:
                    failures.append(name)
            if failures:
                raise RuntimeError("Auxiliary RPC failures: " + ", ".join(failures))
            # Outcomes are real signal deliveries and Session state, not a
            # source-text assertion about how the production sender is written.
            if reports["guest"]["axis_updates"] != 0 or reports["guest"]["fleet_updates"] != 0:
                raise RuntimeError("Unauthenticated peer received auxiliary notifications")
            if reports["member"]["axis_updates"] < 3 or reports["member"]["fleet_updates"] < 3:
                raise RuntimeError("Authenticated peer did not receive both notifications")
            print("AUTHENTICATED_AUX_RPC_OK", sum(r["checks"] for r in reports.values()), "checks; three actual ENet processes")
        finally:
            for _, process, stream, _ in processes:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)
                stream.close()


if __name__ == "__main__":
    main()
