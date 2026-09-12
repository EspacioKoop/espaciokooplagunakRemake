#!/usr/bin/env python3
"""Run real cosmography contracts in a tiny, disposable Godot project.

Shared runner machinery lives here so the navigation entry point uses the same
failure policy. Only the catalog, the selected component and its native test are
copied; no autoload, game asset, player profile or existing import cache is used.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
GODOT_VERSION = "4.7.1"
# Minimum complete regression counts; new assertions may raise these floors.
SUITES = {"persistence": 269, "navigation": 222}
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DIAGNOSTIC = re.compile(r"(?:SCRIPT ERROR|ERROR):|COSMOGRAPHY_\w+_FAIL\b")
PROJECT = '''config_version=5
[application]
config/name="Cosmography contract tests"
[rendering]
renderer/rendering_method="gl_compatibility"
[audio]
driver/driver="Dummy"
'''


def clean_output(output: str) -> str:
    return ANSI.sub("", output)


def completion(suite: str, output: str, returncode: int) -> dict:
    """Require exactly one matching summary and every numbered assertion."""
    output = clean_output(output)
    if returncode != 0:
        raise ValueError(f"Godot exited with {returncode}")
    if DIAGNOSTIC.search(output):
        raise ValueError("Godot reported a diagnostic or failed assertion")
    prefix = f"COSMOGRAPHY_{suite.upper()}"
    summaries = [line for line in output.splitlines() if "COSMOGRAPHY_" in line and "_RESULT" in line]
    if len(summaries) != 1 or not summaries[0].startswith(prefix + "_RESULT "):
        raise ValueError("Missing, duplicate or foreign suite completion marker")
    payload = summaries[0].removeprefix(prefix + "_RESULT ")
    if suite == "persistence":
        def unique_keys(pairs):
            value = {}
            for key, item in pairs:
                if key in value:
                    raise ValueError("Duplicate summary key")
                value[key] = item
            return value
        try:
            summary = json.loads(payload, object_pairs_hook=unique_keys)
        except json.JSONDecodeError as error:
            raise ValueError("Malformed completion summary") from error
    else:
        match = re.fullmatch(r"checks=(\d+) failures=(\d+)", payload)
        if not match:
            raise ValueError("Malformed completion summary")
        summary = dict(zip(("checks", "failures"), map(int, match.groups())))
    if (not isinstance(summary, dict) or set(summary) != {"checks", "failures"}
            or any(type(summary[key]) is not int for key in summary)
            or summary["checks"] < SUITES[suite] or summary["failures"] != 0):
        raise ValueError("Invalid counts or failing completion summary")
    records = [line for line in output.splitlines() if "COSMOGRAPHY_" in line and "_CHECK" in line]
    expected = [f"{prefix}_CHECK index={index} ok=true" for index in range(1, summary["checks"] + 1)]
    if records != expected:
        raise ValueError("Summary does not match the complete successful assertion stream")
    contract_lines = [line for line in output.splitlines() if "COSMOGRAPHY_" in line]
    if not contract_lines or contract_lines[-1] != summaries[0]:
        raise ValueError("Completion must follow all assertions")
    return summary


def isolated_project(root: Path, destination: Path, suite: str) -> Path:
    project = destination / "project"
    (project / "core").mkdir(parents=True)
    (project / "tests").mkdir()
    for name in ("cosmography_catalog.gd", f"cosmography_{suite}.gd"):
        shutil.copyfile(root / "game/core" / name, project / "core" / name)
    shutil.copyfile(root / f"tests/test_cosmography_{suite}.gd",
                    project / f"tests/test_cosmography_{suite}.gd")
    (project / "project.godot").write_text(PROJECT, encoding="utf-8")
    return project


def isolated_env(directory: Path) -> dict:
    env = os.environ.copy()
    for name in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR"):
        path = directory / name.lower()
        path.mkdir(mode=0o700)
        env[name] = str(path)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


def checked_process(command: list, env: dict, cwd: Path, timeout: int, log: Path) -> tuple:
    try:
        result = subprocess.run(command, cwd=cwd, env=env, text=True, encoding="utf-8",
                                errors="replace", stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout, check=False)
        output = result.stdout
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        log.write_text(output, encoding="utf-8")
        raise ValueError(f"Timeout after {timeout}s; partial output retained in {log.name}") from error
    except OSError as error:
        log.write_text(f"Unable to start Godot: {error}\n", encoding="utf-8")
        raise ValueError("Unable to start Godot; see log") from error
    log.write_text(output, encoding="utf-8")
    print(output, end="" if output.endswith("\n") else "\n", flush=True)
    if result.returncode != 0 or DIAGNOSTIC.search(clean_output(output)):
        raise ValueError(f"Godot failed (exit {result.returncode}); see {log.name}")
    return result.returncode, output


def run_suite(suite: str, godot: str, output_dir: Path, timeout: int = 60,
              inject_failure: bool = False, root: Path = ROOT) -> int:
    if suite not in SUITES or type(timeout) is not int or not 1 <= timeout <= 120:
        raise ValueError("Unknown suite or timeout outside 1..120 seconds")
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    report = {"suite": suite, "ok": False, "checks": 0, "negative_control": inject_failure}
    try:
        # Resolve before replacing HOME/cwd; a supplied path remains read-only.
        executable = shutil.which(godot)
        if executable is None:
            raise ValueError("Godot binary not found")
        executable = str(Path(executable).resolve())
        with tempfile.TemporaryDirectory(prefix=f"lagunak-cosmography-{suite}-") as temporary:
            directory = Path(temporary)
            env = isolated_env(directory)
            project = isolated_project(root, directory, suite)
            _, version = checked_process([executable, "--version"], env, project,
                                         min(timeout, 10), output_dir / "version.log")
            if not re.fullmatch(re.escape(GODOT_VERSION) + r"\.stable\.official\.[0-9a-f]+", version.strip()):
                raise ValueError(f"Expected official Godot {GODOT_VERSION}.stable")
            report["godot_version"] = version.strip()
            common = [executable, "--headless", "--path", str(project), "--audio-driver", "Dummy"]
            script = f"res://tests/test_cosmography_{suite}.gd"
            # Pure scripts preload their real dependencies: compile them without
            # launching an editor, scanning assets or depending on a class cache.
            checked_process([*common, "--check-only", "--script", script], env, project,
                            timeout, output_dir / "parse.log")
            command = [*common, "--script", script, "--", "--test"]
            if inject_failure:
                command.append("--inject-failure")
            code, output = checked_process(command, env, project, timeout, output_dir / "suite.log")
            report.update(completion(suite, output, code))
            # Negative mode is never a pass, even if injection becomes disconnected.
            if inject_failure:
                raise ValueError("Negative control did not produce the required native failure")
            report["ok"] = True
    except (ValueError, OSError) as error:
        report["error"] = str(error)
        print(f"COSMOGRAPHY_RUNNER_FAILED {suite}: {error}", file=sys.stderr)
    finally:
        (output_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if report["ok"] else 1


def main(suite: str = "persistence", argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", nargs="?", help="Legacy positional Godot path")
    parser.add_argument("--godot", help="Official pinned editor (never downloaded by this runner)")
    parser.add_argument("--timeout", type=int, default=60, help="Per-phase timeout, 1..120 seconds")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--negative-control", action="store_true", help="Run every test, then fail deliberately; exits nonzero")
    args = parser.parse_args(argv)
    if not 1 <= args.timeout <= 120 or (args.godot and args.binary):
        parser.error("Use one Godot argument and a timeout in 1..120 seconds")
    godot = args.godot or args.binary or os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))
    suffix = "-negative" if args.negative_control else ""
    output_dir = args.output_dir or ROOT / f"build/cosmography-contracts/{suite}{suffix}"
    return run_suite(suite, godot, output_dir, args.timeout, args.negative_control)


if __name__ == "__main__":
    raise SystemExit(main())
