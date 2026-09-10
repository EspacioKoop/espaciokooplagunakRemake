#!/usr/bin/env python3
"""Exercise live Godot UI and restart persistence in isolated local directories."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ERROR = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR|USER ERROR|FATAL(?: ERROR)?|READABILITY_FAIL):", re.MULTILINE)
SUMMARY = re.compile(r"READABILITY_RESULT checks=([0-9]+) failures=([0-9]+)")
MAX_LOG_BYTES = 2 * 1024 * 1024


def validate_output(code: int, output: str) -> None:
    """Reject false greens even when Godot exits zero after reporting an error."""
    clean = ANSI.sub("", output).replace("\r\n", "\n")
    if code != 0 or ERROR.search(clean):
        raise ValueError("Godot reported an error or exited unsuccessfully")
    lines = clean.splitlines()
    summaries = [line for line in lines if line.startswith("READABILITY_RESULT")]
    markers = [line for line in lines if line.startswith("READABILITY_OK")]
    match = SUMMARY.fullmatch(summaries[0]) if len(summaries) == 1 else None
    if match is None or int(match[1]) < 1 or int(match[2]) != 0 or markers != ["READABILITY_OK"]:
        raise ValueError("Expected one complete positive result with zero failures and one success marker")


def isolated_environment(directory: Path) -> dict[str, str]:
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(("LAGUNAK_", "READABILITY_")):
            env.pop(key)
    for key in ("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        location = directory / key.lower()
        location.mkdir()
        env[key] = str(location)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(ROOT / ".toolchain/godot"))
    parser.add_argument("--graphical", action="store_true")
    parser.add_argument("--screenshot", type=Path)
    args = parser.parse_args(argv)
    if args.screenshot and not args.graphical:
        parser.error("--screenshot requires --graphical")
    with tempfile.TemporaryDirectory(prefix="lagunak-readability-") as temp:
        directory = Path(temp)
        env = isolated_environment(directory)
        # Only a new capture in this invocation can satisfy the evidence gate.
        capture = directory / "readability.png"
        if args.screenshot:
            env["READABILITY_CAPTURE_PATH"] = str(capture)
        for restart in (False, True):
            command = [args.godot, "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
                       "--script", str(ROOT / "tests/test_readability.gd"), "--", "--test"]
            if restart:
                env.pop("READABILITY_CAPTURE_PATH", None)
                command.insert(1, "--headless")
                command.append("--verify-persisted")
            elif args.graphical:
                command.append("--require-display")
                if not env.get("DISPLAY"):
                    if not shutil.which("xvfb-run"):
                        raise SystemExit("Graphical validation requires xvfb-run or DISPLAY")
                    command = ["xvfb-run", "-a", "-s", "-screen 0 1600x900x24"] + command
            else:
                command.insert(1, "--headless")
            try:
                with tempfile.TemporaryFile() as log:
                    result = subprocess.run(command, env=env, stdout=log,
                                            stderr=subprocess.STDOUT, timeout=90, check=False)
                    log.seek(0)
                    raw = log.read(MAX_LOG_BYTES + 1)
                if len(raw) > MAX_LOG_BYTES:
                    raise ValueError("Godot output exceeded the log limit")
                output = raw.decode("utf-8", errors="replace")
                print(output, end="", flush=True)
                validate_output(result.returncode, output)
            except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                raise SystemExit(f"Readability test failed (restart={restart}): {error}") from error
        if args.screenshot:
            if not capture.is_file() or capture.stat().st_size < 1024:
                raise SystemExit("A new graphical capture is required")
            with capture.open("rb") as image:
                if image.read(8) != b"\x89PNG\r\n\x1a\n":
                    raise SystemExit("The new graphical capture is not a PNG")
            target = args.screenshot.resolve()
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(capture, target)
    print("READABILITY_RUNNER_OK")


if __name__ == "__main__":
    main()
