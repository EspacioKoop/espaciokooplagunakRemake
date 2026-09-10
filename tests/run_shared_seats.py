"""Physical seat UI checks plus four real ENet processes and reconnection."""
from pathlib import Path
import os
import re
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))
BAD = re.compile(r"^(?:SCRIPT ERROR|ERROR):", re.M)

def main():
    unit = subprocess.run([GODOT, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_shared_seats.gd"), "--", "--test"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    print(unit.stdout, end="")
    assert unit.returncode == 0 and not BAD.search(unit.stdout) and re.search(r"SHARED_SEATS_RESULT checks=\d+ failures=0", unit.stdout), "physical seats UI failed"
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="lagunak-seats-") as temporary:
        processes = []
        try:
            for name in ["host", "player", "rival", "unauthenticated"]:
                path = Path(temporary) / (name + ".log")
                stream = path.open("w")
                process = subprocess.Popen([GODOT, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_shared_seats_network.gd"), "--", "--test", "--case", name, "--port", str(port), "--barriers", temporary], stdout=stream, stderr=subprocess.STDOUT)
                processes.append((name, process, stream, path))
                if name == "host":
                    deadline = time.monotonic() + 15
                    while "SHARED_SEATS_NETWORK_READY" not in path.read_text() and time.monotonic() < deadline:
                        if process.poll() is not None:
                            break
                        time.sleep(.05)
                    assert "SHARED_SEATS_NETWORK_READY" in path.read_text(), path.read_text()
            failed = []
            for name, process, stream, path in processes:
                code = process.wait(timeout=65)
                stream.close()
                output = path.read_text()
                print(output, end="")
                if code or BAD.search(output) or not re.search(rf"SHARED_SEATS_NETWORK_RESULT {name} checks=\d+ failures=0", output):
                    failed.append(name)
            assert not failed, "physical seat network failures: " + ", ".join(failed)
            print("SHARED_SEATS_NETWORK_OK four real processes, collision, privacy and reconnect")
            # A second pair runs with no SeatPresence node on the host, proving
            # additive discovery does not emit unknown-node RPC errors.
            for name in ["legacy_host", "legacy_client"]:
                path = Path(temporary) / (name + ".log")
                stream = path.open("w")
                process = subprocess.Popen([GODOT, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_shared_seats_network.gd"), "--", "--test", "--case", name, "--port", str(port), "--barriers", temporary], stdout=stream, stderr=subprocess.STDOUT)
                processes.append((name, process, stream, path))
                if name == "legacy_host":
                    deadline = time.monotonic() + 10
                    while "SHARED_SEATS_NETWORK_READY" not in path.read_text() and time.monotonic() < deadline:
                        if process.poll() is not None:
                            break
                        time.sleep(.05)
                    assert "SHARED_SEATS_NETWORK_READY" in path.read_text(), path.read_text()
            for name, process, stream, path in processes[-2:]:
                code = process.wait(timeout=25)
                stream.close()
                output = path.read_text()
                print(output, end="")
                assert code == 0 and not BAD.search(output) and re.search(rf"SHARED_SEATS_NETWORK_RESULT {name} checks=\d+ failures=0", output), name + " compatibility failed"
            print("SHARED_SEATS_LEGACY_OK old host/new client preserve position and yaw")
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
