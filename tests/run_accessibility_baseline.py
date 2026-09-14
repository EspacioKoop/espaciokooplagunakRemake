#!/usr/bin/env python3
"""Run the real accessibility components in a disposable, imported Godot project."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from export_targets import GODOT_VERSION

SOURCES = {
    "game/core/accessibility_settings.gd": "core/accessibility_settings.gd",
    "game/ui/accessibility/redundant_signal.gd": "ui/accessibility/redundant_signal.gd",
    "game/ui/accessibility/subtitle_bus.gd": "ui/accessibility/subtitle_bus.gd",
    "tests/test_accessibility_baseline.gd": "tests/test_accessibility_baseline.gd",
}
# Keep in sync with the GDScript suite; losing a check must not silently pass.
EXPECTED_CHECKS = 36
RESULT_PREFIX = "ACCESSIBILITY_BASELINE_OK"
CHECK_PREFIX = "ACCESSIBILITY_CHECK_OK "
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DIAGNOSTIC = re.compile(r"\b(?:SCRIPT ERROR|ERROR):|\bACCESSIBILITY_CHECK_FAILED\b")
PROJECT = '''config_version=5

[application]
config/name="Accessibility baseline isolated tests"
config/features=PackedStringArray("4.7", "GL Compatibility")

[rendering]
renderer/rendering_method="gl_compatibility"

[audio]
driver/enable_input=false
'''


class BaselineFailure(RuntimeError):
    """A failed process or incomplete/invalid suite result."""


def validate_stage(stage: dict, output: str) -> str:
    clean = ANSI.sub("", output)
    if stage["timed_out"]:
        raise BaselineFailure(f'{stage["name"]}: timeout; partial output: {stage["log"]}')
    if stage["returncode"] != 0:
        raise BaselineFailure(f'{stage["name"]}: exit {stage["returncode"]}; log: {stage["log"]}')
    if DIAGNOSTIC.search(clean):
        raise BaselineFailure(f'{stage["name"]}: engine/check diagnostic; log: {stage["log"]}')
    return clean


def validate_version(output: str) -> str:
    version = output.strip()
    if not re.fullmatch(re.escape(GODOT_VERSION) + r"\.stable\.official\.[0-9a-f]{9,40}", version):
        raise BaselineFailure(f"Expected official Godot {GODOT_VERSION}.stable; got {version!r}")
    return version


def validate_suite(output: str) -> int:
    lines = [line.strip() for line in ANSI.sub("", output).splitlines() if line.strip()]
    if DIAGNOSTIC.search(output):
        raise BaselineFailure("Suite reported a diagnostic")
    markers = [line for line in lines if RESULT_PREFIX in line]
    if len(markers) != 1:
        raise BaselineFailure("Expected exactly one accessibility result marker")
    match = re.fullmatch(RESULT_PREFIX + r" checks=([1-9][0-9]*) failures=0", markers[0])
    if not match or lines[-1] != markers[0]:
        raise BaselineFailure("Malformed or non-final accessibility result marker")
    checks = [line[len(CHECK_PREFIX):] for line in lines if line.startswith(CHECK_PREFIX)]
    count = int(match.group(1))
    if count != EXPECTED_CHECKS or len(checks) != count or len(set(checks)) != count:
        raise BaselineFailure("Incomplete, duplicate or inconsistent accessibility checks")
    return count


def isolated_environment(workspace: Path) -> dict[str, str]:
    env = os.environ.copy()
    for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
        path = workspace / key.lower()
        path.mkdir()
        env[key] = str(path)
    return env


def prepare_project(root: Path, project: Path) -> dict[str, str]:
    project.mkdir()
    (project / "project.godot").write_text(PROJECT, encoding="utf-8")
    manifest = {}
    for source, target in SOURCES.items():
        data = (root / source).read_bytes()
        destination = project / target
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        manifest[source] = hashlib.sha256(data).hexdigest()
    return manifest


def run_stage(name: str, command: list[str], env: dict[str, str], cwd: Path,
              logs: Path, timeout: float, stages: list[dict]) -> str:
    log = logs / f"{name}.log"
    stage = {"name": name, "command": command, "timeout_seconds": timeout,
             "returncode": None, "timed_out": False, "log": str(log)}
    stages.append(stage)
    started = time.monotonic()
    # Write directly to disk: output survives a timeout or an interrupted runner.
    with log.open("wb") as stream:
        try:
            process = subprocess.run(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                     stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
            stage["returncode"] = process.returncode
        except subprocess.TimeoutExpired:
            # subprocess.run kills and waits for its child before raising.
            stage["timed_out"] = True
        except OSError as error:
            stream.write((str(error) + "\n").encode("utf-8"))
    stage["elapsed_seconds"] = round(time.monotonic() - started, 3)
    output = log.read_text(encoding="utf-8", errors="replace")
    return validate_stage(stage, output)


def run_baseline(godot: Path, log_parent: Path, timeout: float = 30.0,
                 root: Path = ROOT) -> dict:
    if not math.isfinite(timeout) or not 0 < timeout <= 120:
        raise BaselineFailure("Timeout must be finite and in (0, 120] seconds per process")
    log_parent.mkdir(parents=True, exist_ok=True)
    # Each attempt has independent logs: an earlier green cannot survive a failure.
    logs = Path(tempfile.mkdtemp(prefix="run-", dir=log_parent)).resolve()
    report = {"status": "failed", "godot_version": None, "checks": 0,
              "sources_sha256": {}, "stages": [], "logs": str(logs),
              "scope": "real isolated components; not application/GUI/accessibility certification"}
    try:
        godot = godot.expanduser().resolve(strict=True)
        with tempfile.TemporaryDirectory(prefix="lagunak-accessibility-") as directory:
            workspace = Path(directory)
            env = isolated_environment(workspace)
            project = workspace / "project"
            report["sources_sha256"] = prepare_project(root, project)

            def stage(name: str, arguments: list[str], seconds: float = timeout) -> str:
                return run_stage(name, [str(godot), *arguments], env, workspace,
                                 logs, seconds, report["stages"])

            report["godot_version"] = validate_version(stage("version", ["--version"], min(10, timeout)))
            # Component-only tests must not auto-connect to a desktop screen reader.
            headless = ["--headless", "--accessibility", "disabled"]
            stage("import", [*headless, "--editor", "--path", str(project), "--import"])
            if not (project / ".godot/global_script_class_cache.cfg").is_file():
                raise BaselineFailure("Import did not create the global script class cache")
            output = stage("suite", [*headless, "--path", str(project), "--script",
                                     "res://tests/test_accessibility_baseline.gd", "--", "--test"])
            report["checks"] = validate_suite(output)
            report["status"] = "passed"
    except (BaselineFailure, OSError) as error:
        report["error"] = str(error)
    finally:
        (logs / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("GODOT", ROOT / ".toolchain/godot")))
    parser.add_argument("--log-dir", type=Path, default=ROOT / "build/accessibility-baseline")
    parser.add_argument("--timeout", type=float, default=30.0, help="Seconds per Godot process (maximum 120)")
    args = parser.parse_args(argv)
    try:
        report = run_baseline(args.godot, args.log_dir, args.timeout)
    except (BaselineFailure, OSError) as error:
        print(f"ACCESSIBILITY_RUNNER_FAILED: {error}", file=sys.stderr)
        return 1
    print(f'Accessibility logs: {report["logs"]}')
    if report["status"] != "passed":
        print(f'ACCESSIBILITY_RUNNER_FAILED: {report["error"]}', file=sys.stderr)
        return 1
    print(f'ACCESSIBILITY_RUNNER_OK checks={report["checks"]} failures=0')
    return 0


if __name__ == "__main__":
    sys.exit(main())
