"""Eight real Godot/ENet processes; no campaign files or external network services."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time
from typing import TextIO

ROOT = Path(__file__).resolve().parents[1]
CASES = ("host", "navegacion", "ingenieria", "armas", "sensores", "comunicaciones", "enlace", "reparaciones")
ERROR = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR|Parse Error|ALERT_FAIL):?", re.MULTILINE)
RESULT = re.compile(r"^ALERT_RESULT ([a-z]+) checks=(\d+) failures=(\d+)\s*$", re.MULTILINE)
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def clean_output(output: str) -> str:
    return ANSI.sub("", output)


def result_checks(case: str, returncode: int, output: str) -> int:
    """Fail closed, including Godot errors that sometimes exit with status zero."""
    output = clean_output(output)
    if returncode != 0:
        raise RuntimeError(f"{case}: process exited with {returncode}")
    if ERROR.search(output):
        raise RuntimeError(f"{case}: Godot reported an error")
    results = RESULT.findall(output)
    if len(results) != 1 or results[0][0] != case:
        raise RuntimeError(f"{case}: missing, duplicate or wrong-process result")
    _, count, failures = results[0]
    if int(count) < 10 or int(failures) != 0:
        raise RuntimeError(f"{case}: incomplete checks or failed assertions")
    return int(count)


def isolated_environment(base: Path) -> dict[str, str]:
    env = os.environ.copy()
    for variable, suffix in (
        ("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
        ("XDG_CACHE_HOME", "cache"), ("APPDATA", "roaming"),
        ("LOCALAPPDATA", "local"), ("HOME", "home"), ("USERPROFILE", "profile"),
    ):
        path = base / suffix
        path.mkdir(parents=True, exist_ok=True)
        env[variable] = str(path)
    return env


def select_port(requested: int) -> int:
    if requested:
        if not 1024 <= requested <= 65535:
            raise ValueError("UDP port must be between 1024 and 65535")
        return requested
    # Selection is best-effort; a bind race fails visibly in host_session.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("0.0.0.0", 0))
        return int(probe.getsockname()[1])


@dataclass
class Child:
    case: str
    process: subprocess.Popen
    stream: TextIO
    log: Path

    def output(self) -> str:
        return self.log.read_text(encoding="utf-8", errors="replace")


def stop_children(children: list[Child]) -> None:
    """Reap every started child, even if startup or an earlier wait failed."""
    for child in children:
        if child.process.poll() is None:
            child.process.terminate()
    for child in children:
        try:
            child.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            child.process.kill()
            child.process.wait(timeout=3)
        finally:
            child.stream.close()


def wait_for_host(host: Child, seconds: float = 20.0) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        output = clean_output(host.output())
        if host.process.poll() is not None or ERROR.search(output):
            raise RuntimeError("host failed before announcing red alert")
        if re.search(r"^ALERT_HOST_READY roja\s*$", output, re.MULTILINE):
            return
        time.sleep(0.05)
    raise RuntimeError("host startup timed out")


def run(godot: str, report_dir: Path, requested_port: int = 0, timeout: float = 100.0) -> dict:
    if timeout < 20 or timeout > 300:
        raise ValueError("Timeout must be between 20 and 300 seconds")
    port = select_port(requested_port)
    report_dir.mkdir(parents=True, exist_ok=True)
    # Invalidate an old green report before starting a new run.
    report_path = report_dir / "result.json"
    report_path.unlink(missing_ok=True)
    children: list[Child] = []
    report: dict = {"schema_version": 1, "ok": False, "cases": {}, "port": port}
    with tempfile.TemporaryDirectory(prefix="lagunak-alert-") as temporary:
        work = Path(temporary)
        sync_dir = work / "phases"
        sync_dir.mkdir()
        try:
            import_result = subprocess.run(
                [godot, "--headless", "--editor", "--path", str(ROOT / "game"), "--quit", "--", "--test"],
                env=isolated_environment(work / "import"),
                capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180,
            )
            import_output = import_result.stdout + import_result.stderr
            (report_dir / "import.log").write_text(import_output, encoding="utf-8")
            if import_result.returncode or ERROR.search(clean_output(import_output)):
                raise RuntimeError("Godot project import failed")
            deadline = time.monotonic() + timeout
            for case in CASES:
                path = report_dir / f"{case}.log"
                stream = path.open("w", encoding="utf-8")
                try:
                    process = subprocess.Popen(
                        [godot, "--headless", "--path", str(ROOT / "game"),
                         "--script", str(ROOT / "tests/test_alert_late_join.gd"),
                         "--", "--test", "--case", case, "--port", str(port),
                         "--sync-dir", str(sync_dir)],
                        stdout=stream, stderr=subprocess.STDOUT,
                        env=isolated_environment(work / case),
                    )
                except BaseException:
                    stream.close()
                    raise
                child = Child(case, process, stream, path)
                children.append(child)
                if case == "host":
                    wait_for_host(child)
            # Do not wait on one child while another has already failed.
            while any(child.process.poll() is None for child in children):
                for child in children:
                    code = child.process.poll()
                    if code is not None and code != 0:
                        raise RuntimeError(f"{child.case}: process failed with {code}")
                if time.monotonic() >= deadline:
                    raise RuntimeError("ENet regression timed out")
                time.sleep(0.05)
            for child in children:
                child.stream.close()
                count = result_checks(child.case, child.process.returncode, child.output())
                report["cases"][child.case] = {"checks": count, "failures": 0}
            report["checks"] = sum(case["checks"] for case in report["cases"].values())
            report["ok"] = True
        except BaseException as error:
            report["error"] = str(error)
            raise
        finally:
            stop_children(children)
            report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
            for child in children:
                print(f"--- {child.case} ---\n{child.output().strip()}", flush=True)
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")))
    parser.add_argument("--output", type=Path, default=ROOT / "dist/alert-late-join")
    parser.add_argument("--port", type=int, default=0, help="0 selects an available UDP port")
    parser.add_argument("--timeout", type=float, default=100.0)
    args = parser.parse_args(argv)
    try:
        report = run(args.godot, args.output.resolve(), args.port, args.timeout)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ALERT_NETWORK_FAILED: {error}", file=sys.stderr)
        return 1
    print(f"ALERT_NETWORK_OK {len(CASES)} real processes; {report['checks']} checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
