#!/usr/bin/env python3
"""Run three real ENet peers; client readiness is not host acknowledgement."""
from __future__ import annotations

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
CASES = ("host", "member", "guest")
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ENGINE_ERROR = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR|AUX_RPC_FAIL)\b|Unicode parsing error", re.M)
MIN_CHECKS = {"host": 11, "member": 5, "guest": 7}


def validate_result(name: str, code: int, output: str, document: object) -> dict:
    """Require the exact same, strictly typed, successful result on disk and stdout."""
    clean = ANSI.sub("", output)
    if name not in CASES or code != 0 or ENGINE_ERROR.search(clean):
        raise ValueError(f"{name}: process or engine failure")
    lines = [line.strip() for line in clean.splitlines() if line.strip().startswith("AUX_RPC_RESULT")]
    if len(lines) != 1 or not lines[0].startswith("AUX_RPC_RESULT "):
        raise ValueError(f"{name}: missing or ambiguous result")
    try:
        printed = json.loads(lines[0][len("AUX_RPC_RESULT "):])
    except (ValueError, TypeError) as error:
        raise ValueError(f"{name}: malformed result") from error
    keys = {"case", "checks", "failures", "axis_updates", "fleet_updates"}
    for result in (document, printed):
        if not isinstance(result, dict) or set(result) != keys or result["case"] != name:
            raise ValueError(f"{name}: unexpected result identity or fields")
        for field in keys - {"case"}:
            if type(result[field]) is not int or not 0 <= result[field] <= 100000:
                raise ValueError(f"{name}: invalid {field}")
        if result["checks"] < MIN_CHECKS[name] or result["failures"] != 0:
            raise ValueError(f"{name}: missing or failed assertions")
    if printed != document:
        raise ValueError(f"{name}: stdout and file disagree")
    if name == "guest" and (document["axis_updates"] or document["fleet_updates"]):
        raise ValueError("Unauthenticated peer received auxiliary notifications")
    if name == "member" and min(document["axis_updates"], document["fleet_updates"]) < 3:
        raise ValueError("Authenticated peer did not receive both notifications")
    return document


def isolated_environment(directory: Path) -> dict[str, str]:
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
    for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
        folder = directory / key.lower()
        folder.mkdir(parents=True, exist_ok=True)
        env[key] = str(folder)
    return env


def run(godot: str, order: str, gap_ms: int, evidence: Path | None = None) -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="lagunak-aux-rpc-") as temporary:
        directory = Path(temporary)
        processes = []
        failures = []
        reports = {}
        names = ("host", "member", "guest") if order == "member-first" else ("host", "guest", "member")
        try:
            for index, name in enumerate(names):
                if index == 2 and gap_ms:
                    time.sleep(gap_ms / 1000)
                log = directory / (name + ".log")
                stream = log.open("w", encoding="utf-8")
                try:
                    process = subprocess.Popen(
                        [godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
                         "--script", str(ROOT / "tests/test_authenticated_aux_rpc.gd"), "--", "--test",
                         "--case", name, "--port", str(port), "--coordination", str(directory)],
                        stdout=stream, stderr=subprocess.STDOUT, cwd=ROOT,
                        env=isolated_environment(directory / name))
                except OSError:
                    stream.close()
                    raise
                processes.append((name, process, stream, log))
                if name == "host":
                    deadline = time.monotonic() + 12
                    while not (directory / "host-ready.json").is_file() and time.monotonic() < deadline:
                        if process.poll() is not None:
                            break
                        time.sleep(0.025)
                    if not (directory / "host-ready.json").is_file():
                        raise RuntimeError("Host did not initialize")
            # One wall-clock deadline shared by all peers, not three additive waits.
            deadline = time.monotonic() + 30
            for name, process, stream, log in processes:
                try:
                    code = process.wait(timeout=max(0.01, deadline - time.monotonic()))
                    stream.flush()
                    result_path = directory / (name + "-result.json")
                    if not result_path.is_file() or result_path.stat().st_size > 4096:
                        raise ValueError(f"{name}: missing or oversized result file")
                    report = json.loads(result_path.read_text(encoding="utf-8"))
                    reports[name] = validate_result(name, code, log.read_text(encoding="utf-8", errors="replace"), report)
                except (ValueError, OSError, subprocess.TimeoutExpired) as error:
                    failures.append(f"{name}: {error}")
            if failures:
                raise RuntimeError("Auxiliary RPC failures: " + "; ".join(failures))
        finally:
            for name, process, stream, log in processes:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=3)
                stream.close()
                output = log.read_text(encoding="utf-8", errors="replace")
                print(output.strip(), flush=True)
                if evidence is not None:
                    evidence.mkdir(parents=True, exist_ok=True)
                    (evidence / (name + ".log")).write_text(output, encoding="utf-8")
            if evidence is not None:
                evidence.mkdir(parents=True, exist_ok=True)
                (evidence / "summary.json").write_text(json.dumps({"order": order, "startup_gap_ms": gap_ms,
                    "reports": reports, "complete": len(reports) == 3 and not failures,
                    "failures": failures}, indent=2) + "\n", encoding="utf-8")
        total = sum(report["checks"] for report in reports.values())
        print(f"AUTHENTICATED_AUX_RPC_OK {total} checks; three actual ENet processes; {order}; gap_ms={gap_ms}")
        return total


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")))
    parser.add_argument("--startup-order", choices=("member-first", "guest-first"), default="member-first")
    parser.add_argument("--startup-gap-ms", type=int, default=0)
    parser.add_argument("--evidence-dir", type=Path)
    args = parser.parse_args()
    if not 0 <= args.startup_gap_ms <= 2000:
        parser.error("startup gap must be 0..2000 ms")
    try:
        run(args.godot, args.startup_order, args.startup_gap_ms, args.evidence_dir)
    except (OSError, RuntimeError) as error:
        print(f"AUTHENTICATED_AUX_RPC_FAILED {error}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
