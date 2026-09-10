"""Boot the production supervisor and real Godot host, authorize clients, stop and resume."""
from pathlib import Path
import hashlib
import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))

def free_port():
    with socket.socket(type=socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]

def wait_for(predicate, process, log, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline and process.poll() is None:
        if predicate(): return
        time.sleep(.05)
    raise AssertionError(log.read_text())

def run_peer(env, mode="command"):
    result = subprocess.run([GODOT, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_dedicated_server.gd"), "--", "--test"], env={**env, "LAGUNAK_TEST_MODE": mode}, text=True, capture_output=True, timeout=15)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "failures=0" in output and not re.search(r"^(?:SCRIPT ERROR|ERROR):", output, re.M), output
    match = re.search(r"DEDICATED_RUN (\w+)", output)
    return match.group(1) if match else ""

def read_save(path):
    document = json.loads(path.read_text())
    assert hashlib.sha256(document["payload"].encode()).hexdigest() == document["sha256"]
    return json.loads(document["payload"])

def main():
    with tempfile.TemporaryDirectory(prefix="lagunak-dedicated-") as temporary:
        directory = Path(temporary)
        key = directory / "key"
        key.write_text("synthetic-deployment-key-0123456789")
        port = free_port()
        runtime = directory / "runtime"
        data = directory / "data"
        env = {**os.environ, "GODOT": GODOT, "XDG_DATA_HOME": str(data), "LAGUNAK_RUNTIME_DIR": str(runtime), "LAGUNAK_KEY_FILE": str(key), "LAGUNAK_PORT": str(port), "LAGUNAK_TEST_PORT": str(port), "LAGUNAK_TEST_ADDRESS": "127.0.0.1"}
        def start(suffix, options=None):
            log = directory / (suffix + ".log")
            stream = log.open("w")
            process = subprocess.Popen([sys.executable, str(ROOT / "server/launch.py")], env={**env, **(options or {})}, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            return process, stream, log
        run_id = ""
        for mode in ["command", "resume"]:
            process, stream, log = start(mode)
            try:
                wait_for(lambda: (runtime / "health.json").exists(), process, log)
                assert subprocess.run([sys.executable, str(ROOT / "server/healthcheck.py")], env=env).returncode == 0
                peer_env = {**env, "XDG_DATA_HOME": str(directory / "client"), "LAGUNAK_TEST_RUN": run_id}
                if mode == "command": run_peer(peer_env, "bad")
                run_id = run_peer(peer_env, mode)
                process.terminate()
                assert process.wait(timeout=15) == 0, log.read_text()
                assert "SERVER_STOPPED saved=true" in log.read_text(), log.read_text()
                assert not re.search(r"^(?:SCRIPT ERROR|ERROR):", log.read_text(), re.M), log.read_text()
                assert key.read_text() not in log.read_text()
                assert not (runtime / "health.json").exists()
                saves = list(data.rglob("campaign.json"))
                assert len(saves) == 1
                saved = read_save(saves[0])
                assert saved["run_id"] == run_id and saved["ship"]["alert"] == "roja"
            finally:
                if process.poll() is None:
                    process.terminate()
                    try: process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=3)
                stream.close()
        # No implicit overwrite of an existing campaign, and no forged unlock.
        for name, options in [("new-denied", {"LAGUNAK_LOAD_MODE": "new"}), ("locked-denied", {"LAGUNAK_MISSION_INDEX": "1"})]:
            process, stream, log = start(name, options)
            assert process.wait(timeout=10) == 2, log.read_text()
            stream.close()
            assert read_save(saves[0])["run_id"] == run_id
        original = saves[0].read_bytes()
        saves[0].write_bytes(b"corrupt")
        saves[0].with_name("campaign.json.bak").write_bytes(b"corrupt-backup")
        process, stream, log = start("corrupt-denied")
        assert process.wait(timeout=10) == 2
        stream.close()
        assert saves[0].read_bytes() == b"corrupt"
        assert not (runtime / "health.json").exists()
        assert len(original) > 100
        print("DEDICATED_OK real host/authentication/authority/shutdown/persistence/restart/negative recovery")

if __name__ == "__main__": main()
