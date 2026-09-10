"""Real Godot HTTP + authenticated ENet peers; no Foundry installation implied."""
from pathlib import Path
import json
import os
import re
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))
checks = 0

def check(value, label):
    global checks
    checks += 1
    assert value, label

def free_port(kind=socket.SOCK_STREAM):
    with socket.socket(type=kind) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]

def wait_for(predicate, logs, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate(): return
        time.sleep(.05)
    raise AssertionError("Timeout: " + "\n".join(path.read_text() for path in logs))

with tempfile.TemporaryDirectory(prefix="lagunak-foundry-") as temporary:
    directory = Path(temporary)
    http, udp = free_port(), free_port(socket.SOCK_DGRAM)
    ready_path = directory / "synthetic-credentials.json"
    processes, logs, streams = [], [], []
    env = {**os.environ, "XDG_DATA_HOME": str(directory / "userdata"), "FOUNDRY_TEST_HTTP": str(http), "FOUNDRY_TEST_UDP": str(udp), "FOUNDRY_TEST_READY": str(ready_path), "FOUNDRY_TEST_CONTROL": str(directory)}
    def launch(name, args):
        log = directory / (name + ".log")
        stream = log.open("w")
        process = subprocess.Popen([GODOT, "--headless", "--path", str(ROOT / "game"), "--script", str(ROOT / "tests/test_foundry_authority.gd"), "--", "--test", *args], env=env, stdout=stream, stderr=subprocess.STDOUT)
        logs.append(log); processes.append(process); streams.append(stream)
        return process
    def request(path="/v2/view", token=None, user="foundry_navegacion", method="GET", value=None, headers=None, raw_body=None, fragmented=False, host=None):
        body = raw_body if raw_body is not None else (json.dumps(value).encode() if value is not None else b"")
        pairs = [("Host", host or f"127.0.0.1:{http}"), ("Authorization", "Bearer " + (token or credentials["users"]["navegacion"]["token"])), ("X-Lagunak-User", user)]
        if method == "POST": pairs += [("Content-Type", "application/json"), ("Content-Length", str(len(body)))]
        if headers: pairs += headers
        raw = (f"{method} {path} HTTP/1.1\r\n" + "".join(f"{key}: {val}\r\n" for key, val in pairs) + "\r\n").encode()
        with socket.create_connection(("127.0.0.1", http), timeout=4) as connection:
            connection.sendall(raw + (body[:2] if fragmented else body))
            if fragmented: time.sleep(.08); connection.sendall(body[2:])
            result = bytearray()
            while chunk := connection.recv(65536): result.extend(chunk)
        head, data = bytes(result).split(b"\r\n\r\n", 1)
        return int(head.split(b" ")[1]), head.decode(), json.loads(data) if data else None
    try:
        launch("host", ["--foundry-server"])
        wait_for(lambda: "FOUNDRY_HOST_READY" in logs[0].read_text(), logs)
        nav = launch("navigation", ["--foundry-peer", "navegacion"])
        launch("engineering", ["--foundry-peer", "ingenieria"])
        wait_for(ready_path.exists, logs)
        credentials = json.loads(ready_path.read_text())
        status, _, view = request()
        check(status == 200 and view["identity"] == {"user_id": "foundry_navegacion", "role": "navegacion"}, "identity from native host")
        check(view["crew"]["name"] == "Crew navegacion" and "Crew ingenieria" not in json.dumps(view), "own crew only")
        check("profiles" not in view and "lounge" not in view and "operations" not in view and "campaign_document" not in view, "closed projection")
        check(request(user="foundry_mando")[0] == 401, "user header alone cannot impersonate")
        check(request(token=credentials["legacy"])[0] == 401, "root read-only token cannot enter v2")
        check(request(path="/v1/state")[0] == 401, "personal token cannot enter root endpoint")
        public = request(path="/v1/state", token=credentials["legacy"])[2]
        check("crew" not in public and "CANARY" not in json.dumps(public), "legacy positive projection")
        check(request(headers=[("Origin", "https://other.invalid")])[0] == 403, "origin rejected")
        status, head, _ = request(method="OPTIONS", headers=[("Origin", "http://localhost:30000"), ("Access-Control-Request-Method", "POST"), ("Access-Control-Request-Headers", "authorization,x-lagunak-user,content-type")])
        check(status == 204 and "X-Lagunak-User" in head and "GET, POST, OPTIONS" in head, "CORS preflight for personal control")
        check(request(headers=[("host", "attacker.invalid")])[0] == 400, "duplicate host rejected")
        check(request(host="attacker.invalid")[0] == 403, "DNS rebinding host rejected")
        check(request(headers=[("Content-Length", "-1")])[0] == 400, "negative body length rejected")
        check(request(method="POST", path="/v2/command", raw_body=b"{" * 2049)[0] == 413, "body bounded")
        check(request(method="POST", path="/v2/command", raw_body=b"null")[0] == 400, "non-object JSON rejected")
        check(request(method="POST", path="/v2/command", raw_body=b"{")[0] == 400, "invalid JSON rejected")
        check(request(method="POST", path="/v2/command", raw_body=b"\xff")[0] == 400, "invalid wire encoding rejected without decoder errors")
        check(request(method="POST", path="/v2/command", value={}, headers=[("Transfer-Encoding", "chunked")])[0] == 400, "chunking rejected")
        envelope = {"run_id": view["run_id"], "sequence": view["sequence"], "operation": "helm", "args": {"heading": 45, "throttle": .2}}
        def order(payload, **kwargs):
            time.sleep(.24)
            return request(method="POST", path="/v2/command", value=payload, **kwargs)
        check(order({**envelope, "role": "mando"})[0] == 400, "role injection rejected")
        check(order({**envelope, "operation": "alert", "args": {"level": "roja"}})[0] == 403, "out-of-station command rejected")
        check(order({**envelope, "args": {"heading": "45", "throttle": .2}})[0] == 400, "coerced numeric arguments rejected")
        check(order({**envelope, "args": {"heading": 45, "throttle": 100}})[0] == 400, "out-of-range arguments rejected")
        check(order({**envelope, "args": {"heading": {}, "throttle": .2}})[0] == 400, "nested args rejected")
        status, _, result = order(envelope, fragmented=True)
        check(status == 200 and result["ok"] and result["sequence"] == 2, "fragmented POST applies native helm")
        updated = request()[2]
        check(updated["ship"]["throttle"] == .2 and updated["ship"]["target_heading"] == 45, "observable real simulation effect")
        check(order(envelope)[0] == 409, "replay rejected over actual HTTP")
        check(order({**envelope, "sequence": 2, "run_id": "stale"})[0] == 409, "stale run rejected over actual HTTP")
        engineer = credentials["users"]["ingenieria"]
        readonly = request(token=engineer["token"], user=engineer["user"])[2]
        check(readonly["commands"] == [] and readonly["crew"]["name"] == "Crew ingenieria", "read-only personal view")
        check(order({**envelope, "sequence": 1, "operation": "power", "args": {"system": "reactor", "value": 1}}, token=engineer["token"], user=engineer["user"])[0] == 403, "read-only token cannot execute own station either")
        node = subprocess.run(["node", str(ROOT / "integrations/foundry/tests/live-client.mjs")], env={**env, "FOUNDRY_TEST_BASE": f"http://127.0.0.1:{http}"}, text=True, capture_output=True, timeout=12)
        check(node.returncode == 0, "live Node client: " + node.stdout + node.stderr)
        time.sleep(1.05)
        statuses = [request(method="POST", path="/v2/command", value={})[0] for _ in range(8)]
        check(429 in statuses, "per-capability rate limit")
        (directory / "disconnect-navegacion").touch()
        nav.wait(timeout=5)
        wait_for(lambda: request()[0] == 401, logs, 5)
        check(request()[0] == 401, "native disconnect revokes delegated token")
        for path in logs:
            check(not re.search(r"^(?:SCRIPT ERROR|ERROR):", path.read_text(), re.M), "Godot clean: " + path.name)
        print(f"FOUNDRY_HTTP_OK {checks} checks; three real Godot processes and live Node client")
    finally:
        for process in processes:
            if process.poll() is None: process.terminate(); process.wait(timeout=5)
        for stream in streams: stream.close()
