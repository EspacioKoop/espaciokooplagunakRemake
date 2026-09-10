"""Bounded, isolated ENet boundary regression; no real campaign or credentials."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
import tempfile
import time
from typing import TextIO

ROOT = Path(__file__).resolve().parents[1]
MAX_LOG_BYTES = 4 * 1024 * 1024
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ENGINE_ERROR = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR|FATAL):", re.M)


def validate_result(name: str, code: int, output: str) -> None:
    """A clean exit is insufficient: require one nonempty successful test result."""
    clean = ANSI.sub("", output)
    results = re.findall(
        rf"^NETWORK_BOUNDARY_RESULT {re.escape(name)} checks=(\d+) failures=(\d+)$",
        clean, re.M,
    )
    if (code != 0 or ENGINE_ERROR.search(clean) or len(results) != 1
            or int(results[0][0]) < 1 or int(results[0][1]) != 0):
        raise RuntimeError(f"Boundary case {name} failed (exit {code})")


def isolated_environment(base: dict[str, str], directory: Path, key: str) -> dict[str, str]:
    result = base.copy()
    for variable, folder in [("HOME", "home"), ("XDG_DATA_HOME", "data"),
                             ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"),
                             ("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata")]:
        target = directory / folder
        target.mkdir(parents=True, exist_ok=True)
        result[variable] = str(target)
    result["LAGUNAK_BOUNDARY_KEY"] = key
    result["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return result


@dataclass
class Job:
    name: str
    process: subprocess.Popen
    stream: TextIO
    log: Path


def stop_job(job: Job) -> None:
    try:
        if job.process.poll() is None:
            job.process.terminate()
            try:
                job.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                job.process.kill()
                job.process.wait(timeout=2)
    finally:
        job.stream.close()


def run(godot: str, timeout: float = 60.0, root: Path = ROOT) -> None:
    if not 15 <= timeout <= 120:
        raise ValueError("Timeout must be between 15 and 120 seconds")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.bind(("127.0.0.1", 0))
        port = udp.getsockname()[1]
    # Port selection is not a reservation; a bind collision fails the host test.
    with tempfile.TemporaryDirectory(prefix="lagunak-boundary-") as temporary:
        directory = Path(temporary)
        sync = directory / "sync"
        sync.mkdir()
        key = secrets.token_hex(32)
        jobs: list[Job] = []
        deadline = time.monotonic() + timeout

        def guard() -> None:
            if time.monotonic() >= deadline:
                raise TimeoutError("Network boundary deadline exceeded")
            for job in jobs:
                if job.log.stat().st_size > MAX_LOG_BYTES:
                    raise RuntimeError(f"Excessive log output in {job.name}")

        def spawn(name: str) -> Job:
            log = directory / f"{name}.log"
            stream = log.open("w", encoding="utf-8")
            try:
                process = subprocess.Popen(
                    [godot, "--headless", "--path", str(root / "game"), "--script",
                     str(root / "tests/test_network_boundary.gd"), "--", "--test",
                     "--case", name, "--port", str(port), "--sync-dir", str(sync)],
                    stdout=stream, stderr=subprocess.STDOUT,
                    env=isolated_environment(os.environ, directory / name, key),
                    cwd=root,
                )
            except BaseException:
                stream.close()
                raise
            job = Job(name, process, stream, log)
            jobs.append(job)
            return job

        def marker(name: str, living: list[Job]) -> None:
            while not (sync / name).exists():
                guard()
                if any(job.process.poll() is not None for job in living):
                    raise RuntimeError(f"A process exited before marker {name}")
                time.sleep(0.03)
            guard()

        def finish(job: Job) -> None:
            while job.process.poll() is None:
                guard()
                time.sleep(0.03)
            guard()
            job.stream.flush()
            validate_result(job.name, job.process.returncode,
                            job.log.read_text(encoding="utf-8", errors="replace"))

        try:
            finish(spawn("unit"))
            host = spawn("host")
            marker("host.ready", [host])
            finish(spawn("unauthenticated"))
            (sync / "unauthenticated.done").write_text("done", encoding="utf-8")
            marker("unauthenticated.checked", [host])
            victim = spawn("victim")
            marker("victim.ready", [host, victim])
            finish(spawn("navigation"))
            (sync / "stop").write_text("stop", encoding="utf-8")
            finish(victim)
            finish(host)
            print("NETWORK_BOUNDARY_OK five processes; real loopback ENet")
        finally:
            for job in reversed(jobs):
                stop_job(job)
            for job in jobs:
                print(f"--- {job.name} ---")
                # Fixture output only. Never print environment variables or keys.
                print(job.log.read_text(encoding="utf-8", errors="replace")[:MAX_LOG_BYTES])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")))
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args(argv)
    try:
        run(args.godot, args.timeout)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"NETWORK_BOUNDARY_FAILED: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
