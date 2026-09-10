"""Exercise the real Godot loopback HTTP server using raw HTTP requests."""
from pathlib import Path
import json
import os
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))
TOKEN = "lagunak-telemetry-test-only"
checks = 0

def request(method="GET", path="/v1/state", headers=None):
    pairs = [("Host", "127.0.0.1:29184"), *(headers if headers is not None else [("Authorization", "Bearer " + TOKEN)])]
    raw = f"{method} {path} HTTP/1.1\r\n" + "".join(f"{key}: {value}\r\n" for key, value in pairs) + "\r\n"
    with socket.create_connection(("127.0.0.1", 29184), timeout=4) as connection:
        connection.sendall(raw.encode())
        result = bytearray()
        while True:
            chunk = connection.recv(65536)
            if not chunk: break
            result.extend(chunk)
    head, body = bytes(result).split(b"\r\n\r\n", 1)
    return int(head.split(b" ")[1]), head.decode(), json.loads(body) if body else None

def check(value, description):
    global checks
    checks += 1
    assert value, description

with tempfile.TemporaryDirectory(prefix="lagunak-http-") as temporary:
    log = Path(temporary) / "server.log"
    with log.open("w") as stream:
        process = subprocess.Popen([GODOT, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_telemetry.gd"), "--", "--test"], stdout=stream, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 10
            while "TELEMETRY_READY" not in log.read_text() and time.monotonic() < deadline:
                if process.poll() is not None: break
                time.sleep(.05)
            assert "TELEMETRY_READY" in log.read_text(), log.read_text()
            status, _, state = request()
            check(status == 200 and state["status"] == "active", "authenticated state")
            check("contacts" not in state["mission"], "mission catalogue redacted")
            check(state["contacts"][3]["kind"] == "unknown", "unidentified contact redacted")
            check(request(headers=[])[0] == 401, "token required")
            check(request(headers=[("Authorization", "Bearer wrong")])[0] == 401, "wrong token")
            check(request("POST")[0] == 405, "no write endpoint")
            check(request(path="/unknown")[0] == 404, "unknown endpoint")
            check(request(headers=[("Authorization", "Bearer " + TOKEN), ("Origin", "https://untrusted.invalid")])[0] == 403, "origin restriction")
            status, head, _ = request(headers=[("Authorization", "Bearer " + TOKEN), ("Origin", "http://localhost:30000")])
            check(status == 200 and "Access-Control-Allow-Origin: http://localhost:30000" in head, "exact allowed origin")
            check(request("OPTIONS", headers=[("Origin", "http://localhost:30000")])[0] == 204, "browser preflight")
            check(request(headers=[("Authorization", "Bearer " + TOKEN), ("authorization", "Bearer " + TOKEN)])[0] == 400, "duplicate headers")
            check(request(path="/v1/events?after=0")[2]["events"], "event cursor")
            check(request(path="/v1/events?after=no")[0] == 400, "invalid event cursor")
            check(request(headers=[("X-Oversized", "a" * 8200)])[0] == 431, "bounded header size")
            print(f"TELEMETRY_OK {checks} real HTTP checks")
        finally:
            process.terminate()
            process.wait(timeout=5)
