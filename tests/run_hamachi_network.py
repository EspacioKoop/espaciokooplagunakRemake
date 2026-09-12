#!/usr/bin/env python3
"""Exercise native guided UI over real local ENet sockets, not a Hamachi tunnel."""
from contextlib import contextmanager
import argparse
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CASES = {"host": 12, "bad": 7, "busy": 7, "good": 18}
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def validate_result(case, returncode, output):
    if case not in CASES:
        raise ValueError("Unknown network case")
    text = ANSI.sub("", output)
    if returncode != 0 or re.search(r"^\s*(?:SCRIPT ERROR|ERROR):", text, re.M):
        raise ValueError(f"{case}: process or Godot error")
    matches = re.findall(rf"^HAMACHI_RESULT {case} checks=(\d+) failures=(\d+)$", text, re.M)
    if len(matches) != 1:
        raise ValueError(f"{case}: missing or repeated complete result")
    checks, failures = map(int, matches[0])
    if checks < CASES[case] or failures:
        raise ValueError(f"{case}: insufficient checks or logical failure")
    return {"case": case, "checks": checks, "failures": failures, "exit": returncode}


@contextmanager
def managed_process(command, log_path, env):
    with log_path.open("w", encoding="utf-8") as stream:
        process = subprocess.Popen(command, env=env, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        try:
            yield process
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)


def wait_ready(process, path, timeout=12.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        text = path.read_text(encoding="utf-8", errors="replace")
        if process.poll() is not None:
            raise RuntimeError("Host exited before readiness")
        if re.search(r"^\s*(?:SCRIPT ERROR|ERROR):", ANSI.sub("", text), re.M):
            raise RuntimeError("Host error before readiness")
        if "HAMACHI_HOST_READY\n" in text:
            return
        time.sleep(0.04)
    raise TimeoutError("Host readiness deadline exceeded")


def safe_diagnostic(case, text):
    """Only fixed enums and integer counters can escape private process logs."""
    if case not in CASES:
        raise ValueError("Unknown diagnostic case")
    text = ANSI.sub("", text)
    result = re.findall(rf"^HAMACHI_RESULT {case} checks=(\d+) failures=(\d+)$", text, re.M)
    states = re.findall(rf"^HAMACHI_STATE {case} accepted=(true|false) rejected=(true|false) mode=(offline|host|client)$", text, re.M)
    failures = re.findall(r"HAMACHI_FAIL (\d+) ", text)
    return {"case": case, "results": [[int(a), int(b)] for a,b in result[:2]],
            "failed_checks": [int(n) for n in failures[:32]], "states": states[:2],
            "engine_errors": len(re.findall(r"^\s*(?:SCRIPT ERROR|ERROR):", text, re.M))}


def run(godot, output):
    output.mkdir(parents=True, exist_ok=True)
    report_path = output / "report.json"
    report = {"ok": False, "method": "production UI and real same-machine ENet sockets",
              "hamachi_tunnel_tested": False, "cases": []}
    # The handoff contains an ephemeral authentication key; no values go to logs
    # or reports. Private directories and inherited umask protect all child files.
    old_umask = os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(prefix="lagunak-hamachi-network-") as temporary:
            root = Path(temporary)
            exchange = root / "exchange"
            exchange.mkdir(mode=0o700)
            # Select the primary local route, not the first adapter returned by
            # Godot (CI hosts may expose isolated bridge/link-local interfaces).
            # UDP connect selects a source address but sends NO packet.
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as route:
                route.connect(("192.0.2.1", 9))
                address = route.getsockname()[0]
            (exchange / "local-address").write_text(address, encoding="utf-8")
            report["address_selection"] = "primary local route; no external packet sent"
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as candidate:
                candidate.bind(("127.0.0.1", 0))
                port = candidate.getsockname()[1]
            def settings(case):
                env = os.environ.copy()
                profile = root / case
                profile.mkdir(mode=0o700)
                for name in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                    env[name] = str(profile / name)
                command = [str(godot), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
                           "--script", str(ROOT / "tests/test_hamachi_peer.gd"), "--", "--test",
                           "--case", case, "--port", str(port), "--exchange", str(exchange)]
                return command, env
            command, env = settings("host")
            host_log = output / "host.log"
            with managed_process(command, host_log, env) as host:
                wait_ready(host, host_log)
                for case in ("bad", "busy", "good"):
                    command, env = settings(case)
                    log = output / f"{case}.log"
                    with managed_process(command, log, env) as child:
                        code = child.wait(timeout=15)
                    report["cases"].append(validate_result(case, code, log.read_text(encoding="utf-8")))
                code = host.wait(timeout=8)
            report["cases"].append(validate_result("host", code, host_log.read_text(encoding="utf-8")))
            report["ok"] = True
    finally:
        report["diagnostics"] = [safe_diagnostic(case, (output / f"{case}.log").read_text(encoding="utf-8", errors="replace"))
                                 for case in CASES if (output / f"{case}.log").is_file()]
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        os.umask(old_umask)
        if not report["ok"]:
            print("HAMACHI_DIAGNOSTIC " + json.dumps(report["diagnostics"]))
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("GODOT", ROOT / ".toolchain/godot")))
    parser.add_argument("--output", type=Path, default=ROOT / "build/release-092/hamachi-network")
    args = parser.parse_args(argv)
    try:
        report = run(args.godot.resolve(), args.output.resolve())
    except (OSError, ValueError, RuntimeError, TimeoutError, subprocess.TimeoutExpired):
        # Controlled message only: never echo an invitation, endpoint, or key.
        print("HAMACHI_NETWORK_FAILED: inspect the local per-case logs and report")
        return 1
    print("HAMACHI_NETWORK_OK " + str(sum(case["checks"] for case in report["cases"])) +
          " checks; four real processes; wrong key, occupied station and reconnect covered")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
