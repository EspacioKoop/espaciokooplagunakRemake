#!/usr/bin/env python3
"""Exercise the real campaign editor without touching a player's save directory."""
import argparse
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def run_peers(godot):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="lagunak-campaign-peers-") as directory:
        processes = []
        try:
            for name in ["host", "client"]:
                logfile = Path(directory) / f"{name}.log"
                stream = logfile.open("w")
                env = dict(os.environ, XDG_DATA_HOME=str(Path(directory) / name),
                           XDG_CONFIG_HOME=str(Path(directory) / name))
                process = subprocess.Popen([godot, "--headless", "--path", str(ROOT / "game"),
                                            "--script", str(ROOT / "tests/test_campaign_editor.gd"),
                                            "--", "--test", "--campaign-peer", name, "--port", str(port)],
                                           env=env, stdout=stream, stderr=subprocess.STDOUT)
                processes.append((name, process, stream, logfile))
                if name == "host":
                    deadline = time.monotonic() + 8
                    while "CAMPAIGN_HOST_READY" not in logfile.read_text() and time.monotonic() < deadline:
                        if process.poll() is not None:
                            break
                        time.sleep(0.05)
                    if "CAMPAIGN_HOST_READY" not in logfile.read_text():
                        raise RuntimeError("Host not ready: " + logfile.read_text())
            for name, process, stream, logfile in processes:
                result = process.wait(timeout=15)
                stream.flush()
                output = logfile.read_text()
                print(output, end="", flush=True)
                marker = rf"CAMPAIGN_PEER_OK {name} checks=\d+ failures=0"
                if result or re.search(r"^(SCRIPT ERROR|ERROR):", output, re.MULTILINE) or not re.search(marker, output):
                    raise RuntimeError("Campaign network regression failed: " + name)
        finally:
            for _, process, stream, _ in processes:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
                stream.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=str(ROOT / ".toolchain/godot"))
    parser.add_argument("--capture", action="store_true")
    args = parser.parse_args()
    command = [args.godot, "--path", str(ROOT / "game"), "--audio-driver", "Dummy",
               "--script", str(ROOT / "tests/test_campaign_editor.gd"), "--", "--test"]
    if args.capture:
        command += ["--campaign-capture"]
    else:
        command.insert(1, "--headless")
    with tempfile.TemporaryDirectory(prefix="lagunak-campaign-") as directory:
        env = dict(os.environ, XDG_DATA_HOME=directory, XDG_CONFIG_HOME=directory)
        try:
            result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=60)
            output = result.stdout
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            print(output, flush=True)
            raise SystemExit("Campaign test did not reach its completion marker in 60 seconds") from error
    print(output, end="", flush=True)
    if result.returncode or re.search(r"^(?:SCRIPT ERROR|ERROR):", output, re.MULTILINE):
        raise SystemExit(1)
    if not re.search(r"CAMPAIGN_OK \d+ checks; 0 failures", output):
        raise SystemExit("Missing successful campaign completion marker")
    run_peers(args.godot)


if __name__ == "__main__":
    main()
