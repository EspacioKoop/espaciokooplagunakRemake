"""Cosmetic validation/UI plus four real ENet processes, isolated user data."""
from pathlib import Path
import os
import re
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))


def main():
    with tempfile.TemporaryDirectory(prefix="lagunak-avatar-") as directory:
        temporary = Path(directory)
        environment = {**os.environ, "XDG_DATA_HOME": str(temporary / "unit-data")}
        command = [GODOT, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_avatar_customization.gd"), "--", "--test"]
        unit = subprocess.run(command, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=50)
        print(unit.stdout.strip())
        assert unit.returncode == 0 and not re.search(r"^(?:SCRIPT ERROR|ERROR):", unit.stdout, re.M)
        assert re.search(r"AVATAR_RESULT checks=\d+ failures=0", unit.stdout)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reserve:
            reserve.bind(("127.0.0.1", 0))
            port = reserve.getsockname()[1]
        run_network(temporary, port, ["host", "player", "spectator", "intruder"])
        run_network(temporary, port, ["legacy_host", "legacy_client"])


def run_network(temporary, port, cases):
    processes = []
    try:
        for name in cases:
            path = temporary / (name + ".log")
            stream = path.open("w")
            environment = {**os.environ, "XDG_DATA_HOME": str(temporary / (name + "-data"))}
            command = [GODOT, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_avatar_network.gd"), "--", "--test", "--case", name, "--port", str(port)]
            process = subprocess.Popen(command, env=environment, stdout=stream, stderr=subprocess.STDOUT)
            processes.append((name, process, stream, path))
            if name in ["host", "legacy_host"]:
                deadline = time.monotonic() + 10
                while "AVATAR_NETWORK_READY" not in path.read_text() and time.monotonic() < deadline:
                    if process.poll() is not None:
                        break
                    time.sleep(0.05)
                assert "AVATAR_NETWORK_READY" in path.read_text(), path.read_text()
        failed = []
        for name, process, stream, path in processes:
            code = process.wait(timeout=35)
            stream.close()
            output = path.read_text()
            print(output.strip())
            if code or re.search(r"^(?:SCRIPT ERROR|ERROR):", output, re.M) or not re.search(rf"AVATAR_NETWORK_RESULT {name} checks=\d+ failures=0", output):
                failed.append(name)
        assert not failed, "Avatar network failures: " + ", ".join(failed)
        print("AVATAR_NETWORK_OK " + ",".join(cases))
    except Exception:
        for name, _, _, path in processes:
            print(name, path.read_text(), flush=True)
        raise
    finally:
        for _, process, stream, _ in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            stream.close()

if __name__ == "__main__":
    main()
