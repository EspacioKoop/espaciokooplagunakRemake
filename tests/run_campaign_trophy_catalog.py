#!/usr/bin/env python3
"""Fail-closed runner for the campaign trophy vertical."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DIAGNOSTIC = re.compile(r"^(?:SCRIPT ERROR:|ERROR:|Parse Error:|Unicode parsing error|WARNING:)", re.I)
RESULT = re.compile(r"^CAMPAIGN_TROPHY_RESULT checks=[1-9]\d* failures=0$")
VSYNC_WARNING = "WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver."
IMPORT_SHUTDOWN_WARNING = "WARNING: Scan thread aborted..."


def clean(output: str) -> str:
    return ANSI.sub("", output)


def accepted(output: str, code: int, *, graphics: bool = False, require_result: bool = True) -> bool:
    lines = clean(output).splitlines()
    diagnostics = [line.strip() for line in lines if DIAGNOSTIC.match(line.strip())]
    if graphics:
        diagnostics = [line for line in diagnostics if line != VSYNC_WARNING]
    return code == 0 and not diagnostics and (
        not require_result or any(RESULT.fullmatch(line.strip()) for line in lines)
    )


def self_test() -> None:
    good = "CAMPAIGN_TROPHY_RESULT checks=21 failures=0"
    cases = [
        (good, 0, False, True),
        (good, 1, False, False),
        ("missing marker", 0, False, False),
        ("CAMPAIGN_TROPHY_RESULT checks=0 failures=0", 0, False, False),
        ("CAMPAIGN_TROPHY_RESULT checks=21 failures=1", 0, False, False),
        ("SCRIPT ERROR: fixture\n" + good, 0, False, False),
        ("ERROR: fixture\n" + good, 0, False, False),
        ("Parse Error: fixture\n" + good, 0, False, False),
        ("WARNING: unexpected fixture\n" + good, 0, False, False),
        (VSYNC_WARNING + "\n" + good, 0, True, True),
    ]
    for text, code, graphics, expected in cases:
        if accepted(text, code, graphics=graphics) != expected:
            raise RuntimeError("Campaign trophy runner diagnostic/marker contract failed")
    print(f"CAMPAIGN_TROPHY_RUNNER_OK controls={len(cases)}", flush=True)


def isolated_env(directory: Path) -> dict[str, str]:
    environment = os.environ.copy()
    for variable, child in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        destination = directory / child
        destination.mkdir(parents=True)
        environment[variable] = str(destination)
    environment["LIBGL_ALWAYS_SOFTWARE"] = "1"
    environment["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return environment


def import_project(godot: str) -> None:
    # A fresh checkout needs Godot's global class cache before autoloads parse.
    # Reuse an existing cache so repeated tests do not start a second editor
    # scanner while another local Godot process is active.
    import_command = [godot, "--headless", "--editor", "--path", str(ROOT / "game"), "--quit-after", "2"]
    import_environment = os.environ.copy()
    import_environment["GODOT_SILENCE_ROOT_WARNING"] = "1"
    imported = subprocess.run(
        import_command,
        cwd=ROOT,
        env=import_environment,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
        check=False,
    )
    print(imported.stdout, flush=True)
    import_output = imported.stdout.replace(IMPORT_SHUTDOWN_WARNING, "")
    if not accepted(import_output, imported.returncode, require_result=False):
        raise RuntimeError("Campaign trophy import phase failed")


def run_godot(godot: str, *, graphics: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="lagunak-campaign-trophies-") as temporary:
        environment = isolated_env(Path(temporary))
        cache = ROOT / "game/.godot/global_script_class_cache.cfg"
        if not cache.is_file():
            import_project(godot)
        command = [godot, "--audio-driver", "Dummy", "--path", str(ROOT / "game")]
        if not graphics:
            command.append("--headless")
        command += ["--script", str(ROOT / "tests/test_campaign_trophy_catalog.gd"), "--", "--test"]
        result = subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
            check=False,
        )
        print(result.stdout, flush=True)
        if not accepted(result.stdout, result.returncode, graphics=graphics):
            raise RuntimeError("Campaign trophy Godot gate failed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="Only run synthetic runner controls")
    parser.add_argument("--graphics", action="store_true", help="Use an existing isolated X11 display")
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")))
    args = parser.parse_args()
    self_test()
    if args.self_test:
        return 0
    if args.graphics and not os.environ.get("DISPLAY"):
        parser.error("--graphics requires an isolated display, e.g. xvfb-run -a")
    if not Path(args.godot).is_file():
        raise RuntimeError(f"Godot executable not found: {args.godot}")
    run_godot(args.godot, graphics=args.graphics)
    print("CAMPAIGN_TROPHY_GATE_OK", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from error
