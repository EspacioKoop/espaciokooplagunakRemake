#!/usr/bin/env python3
"""Run briefing gates with disposable user data; no player data is read or sent."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DIAGNOSTIC = re.compile(r"^(?:SCRIPT ERROR:|ERROR:|Parse Error:|Unicode parsing error|WARNING:)", re.I)
RESULT = re.compile(r"^MISSION_BRIEFING_RESULT checks=([1-9]\d*) failures=0$", re.M)
# Same narrowly pinned pre-existing import warning as run_character_editor.py.
# Never permitted during the actual test, never for another source hash.
IMPORT_WARNING = "Unicode parsing error, some characters were replaced with � (U+FFFD): Unexpected NUL character"
IMPORT_HASH = "5d47e74bcab86b2f4ab5579d8e7754b61066c640958e2e383d9fdeb8abb9236a"
VSYNC_WARNING = "WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver."


def diagnostics(text: str, *, import_phase: bool = False, graphics: bool = False) -> list[str]:
    errors = []
    import_allowance = 0
    for line in ANSI.sub("", text).splitlines():
        line = line.strip()
        if not DIAGNOSTIC.match(line):
            continue
        if graphics and line == VSYNC_WARNING:
            continue
        if import_phase and line == IMPORT_WARNING and import_allowance == 0:
            source = ROOT / "game/core/cosmography_catalog.gd"
            if source.is_file() and hashlib.sha256(source.read_bytes()).hexdigest() == IMPORT_HASH:
                import_allowance += 1
                continue
        errors.append(line)
    return errors


def validate_result(text: str, code: int, *, require_result: bool = True,
                    import_phase: bool = False, graphics: bool = False) -> int:
    errors = diagnostics(text, import_phase=import_phase, graphics=graphics)
    if code or errors:
        raise RuntimeError(f"Engine process failed (exit {code}): " + "; ".join(errors))
    matches = RESULT.findall(ANSI.sub("", text))
    if require_result and len(matches) != 1:
        raise RuntimeError("Missing or ambiguous positive briefing result marker")
    return int(matches[0]) if matches else 0


def run_command(command: list[str], env: dict[str, str], *, import_phase: bool = False,
                graphics: bool = False, timeout: int = 180) -> int:
    if import_phase and "--editor" not in command:
        raise ValueError("Import-only exception requires an editor import command")
    result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=timeout, check=False)
    print(result.stdout, flush=True)
    return validate_result(result.stdout, result.returncode, require_result=not import_phase,
                           import_phase=import_phase, graphics=graphics)


def self_test() -> None:
    good = "MISSION_BRIEFING_RESULT checks=1 failures=0"
    fixtures = [
        (good, 0, False, True),
        (good, 1, False, False),
        ("missing marker", 0, False, False),
        ("MISSION_BRIEFING_RESULT checks=0 failures=0", 0, False, False),
        ("MISSION_BRIEFING_RESULT checks=1 failures=1", 0, False, False),
        (good + "\n" + good, 0, False, False),
        ("ERROR: fixture\n" + good, 0, False, False),
        ("  \x1b[31mSCRIPT ERROR:\x1b[0m fixture\n" + good, 0, False, False),
        ("Parse Error: fixture\n" + good, 0, False, False),
        ("WARNING: unknown fixture\n" + good, 0, False, False),
        (IMPORT_WARNING + "\n" + good, 0, False, False),
        (VSYNC_WARNING + "\n" + good, 0, False, False),
        (VSYNC_WARNING + "\n" + good, 0, True, True),
    ]
    for output, code, graphics, expected in fixtures:
        accepted = True
        try:
            validate_result(output, code, graphics=graphics)
        except RuntimeError:
            accepted = False
        if accepted != expected:
            raise AssertionError("Runner accepted or rejected a synthetic fixture incorrectly")
    print(f"MISSION_BRIEFING_RUNNER_OK {len(fixtures)} synthetic diagnostic controls", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="Only test the Python gate, not Godot")
    parser.add_argument("--graphical", action="store_true", help="Also run real window widgets under an existing display")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        return 0
    godot = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))
    with tempfile.TemporaryDirectory(prefix="lagunak-briefing-") as directory:
        env = os.environ.copy()
        for variable, child in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                                ("XDG_CACHE_HOME", "cache")):
            location = Path(directory) / child
            location.mkdir()
            env[variable] = str(location)
        run_command([godot, "--headless", "--editor", "--path", str(ROOT / "game"), "--quit"],
                    env, import_phase=True)
        command = [godot, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
                   "--script", str(ROOT / "tests/test_mission_briefing.gd"), "--", "--test"]
        count = run_command(command, env)
        graphic_count = 0
        if args.graphical:
            if not env.get("DISPLAY"):
                raise RuntimeError("Graphical test requested without DISPLAY; use xvfb-run")
            env["LIBGL_ALWAYS_SOFTWARE"] = "1"
            graphic_command = [part for part in command if part != "--headless"]
            graphic_count = run_command(graphic_command, env, graphics=True)
    summary = f"Mission briefing: {count} headless checks; {graphic_count} graphical checks; 13 synthetic runner controls.\n"
    print(summary, flush=True)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
            stream.write(summary)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, AssertionError, subprocess.TimeoutExpired) as error:
        message = str(error).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::error title=Mission briefing gate::{message}", file=sys.stderr)
        raise SystemExit(1)
