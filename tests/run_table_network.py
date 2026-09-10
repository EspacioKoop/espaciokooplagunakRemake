"""Three actual Godot processes: table host, player with reconnect, and spectator."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))
PORT = 29187

with tempfile.TemporaryDirectory(prefix="lagunak-network-") as temporary:
    processes = []
    try:
        for name in ["host", "player", "spectator"]:
            path = Path(temporary) / (name + ".log")
            stream = path.open("w")
            process = subprocess.Popen([GODOT, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_table_network.gd"), "--", "--test", "--case", name, "--port", str(PORT)], stdout=stream, stderr=subprocess.STDOUT)
            processes.append((name, process, stream, path))
            if name == "host":
                deadline = time.monotonic() + 10
                while "TABLE_NETWORK_READY" not in path.read_text() and time.monotonic() < deadline:
                    if process.poll() is not None: break
                    time.sleep(.05)
                assert "TABLE_NETWORK_READY" in path.read_text(), path.read_text()
        failed = []
        for name, process, stream, path in processes:
            code = process.wait(timeout=25)
            stream.close()
            output = path.read_text()
            print(output.strip())
            if code or re.search(r"^(?:SCRIPT ERROR|ERROR):", output, re.M) or not re.search(rf"TABLE_NETWORK_RESULT {name} checks=\d+ failures=0", output): failed.append(name)
        assert not failed, "Network failures: " + ", ".join(failed)
        print("TABLE_NETWORK_OK three processes including authenticated reconnect")
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
