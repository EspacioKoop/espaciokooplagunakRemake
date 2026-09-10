"""Five actual Godot processes: host, two stations, wrong key and occupied station."""
from pathlib import Path
import os
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))
PORT = 29183

with tempfile.TemporaryDirectory(prefix="lagunak-network-") as temporary:
    processes = []
    try:
        for name in ["host", "nav", "eng", "bad", "busy"]:
            path = Path(temporary) / (name + ".log")
            stream = path.open("w")
            process = subprocess.Popen([GODOT, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_network.gd"), "--", "--test", "--case", name, "--port", str(PORT)], stdout=stream, stderr=subprocess.STDOUT)
            processes.append((name, process, stream, path))
            if name == "host":
                deadline = time.monotonic() + 10
                while "NETWORK_HOST_READY" not in path.read_text() and time.monotonic() < deadline:
                    if process.poll() is not None: break
                    time.sleep(.05)
                assert "NETWORK_HOST_READY" in path.read_text(), path.read_text()
        failed = []
        for name, process, stream, path in processes:
            code = process.wait(timeout=25)
            stream.close()
            output = path.read_text()
            print(output.strip())
            if code or "SCRIPT ERROR" in output or f"NETWORK_RESULT {name} failures=0" not in output: failed.append(name)
        assert not failed, "Network failures: " + ", ".join(failed)
        print("NETWORK_OK five actual processes")
    finally:
        for _, process, stream, _ in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            stream.close()
