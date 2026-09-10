#!/usr/bin/env python3
"""Fail-closed Godot report tests; isolate all user data."""
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
RESULT = r"^SESSION_REPORT_RESULT checks=[1-9]\d* failures=0$"
VSYNC_WARNING = "WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver."
IMPORT_WARNING = "Unicode parsing error, some characters were replaced with � (U+FFFD): Unexpected NUL character"
IMPORT_SHA256 = "5d47e74bcab86b2f4ab5579d8e7754b61066c640958e2e383d9fdeb8abb9236a"


def diagnostics(output: str, *, import_phase: bool = False, graphics: bool = False) -> list[str]:
    errors: list[str] = []
    allowed_import = 0
    for raw in ANSI.sub("", output).splitlines():
        line = raw.strip()
        if not DIAGNOSTIC.match(line):
            continue
        if graphics and line == VSYNC_WARNING:
            continue
        # The existing character gate uses this exact, source-pinned exception.
        # It cannot mask a runtime error or a changed cosmography file.
        source = ROOT / "game/core/cosmography_catalog.gd"
        if import_phase and line == IMPORT_WARNING and allowed_import == 0 and source.is_file():
            if hashlib.sha256(source.read_bytes()).hexdigest() == IMPORT_SHA256:
                allowed_import += 1
                continue
        errors.append(line)
    return errors


def accepted(output: str, code: int, marker: str | None, *, import_phase: bool = False,
             graphics: bool = False) -> bool:
    return code == 0 and not diagnostics(output, import_phase=import_phase, graphics=graphics) and (
        marker is None or re.search(marker, ANSI.sub("", output), re.M) is not None)


def checked_run(command: list[str], environment: dict[str, str], marker: str | None = None,
                *, import_phase: bool = False, graphics: bool = False) -> None:
    if import_phase and "--editor" not in command:
        raise ValueError("Import exceptions require the editor import phase")
    try:
        result = subprocess.run(command, cwd=ROOT, env=environment, text=True, encoding="utf-8",
                                errors="replace", stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=120, check=False)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        print(output.decode(errors="replace") if isinstance(output, bytes) else output, flush=True)
        raise RuntimeError("Session report gate timed out") from error
    print(result.stdout, flush=True)
    if not accepted(result.stdout, result.returncode, marker, import_phase=import_phase, graphics=graphics):
        raise RuntimeError("Session report gate failed: " + " ".join(command))


def self_test() -> None:
    good = "SESSION_REPORT_RESULT checks=12 failures=0"
    cases = [
        (good, 0, False, True), (good, 1, False, False),
        ("missing marker", 0, False, False),
        ("SESSION_REPORT_RESULT checks=0 failures=0", 0, False, False),
        ("SESSION_REPORT_RESULT checks=12 failures=1", 0, False, False),
        ("SCRIPT ERROR: fixture\n" + good, 0, False, False),
        ("  \x1b[31mERROR:\x1b[0m fixture\n" + good, 0, False, False),
        ("Parse Error: fixture\n" + good, 0, False, False),
        ("WARNING: unexpected fixture\n" + good, 0, False, False),
        (IMPORT_WARNING + "\n" + good, 0, False, False),
        (VSYNC_WARNING + "\n" + good, 0, False, False),
        (VSYNC_WARNING + "\n" + good, 0, True, True),
    ]
    for text, code, graphics, expected in cases:
        # Actual subprocess fixtures verify this runner, not gameplay or ENet.
        result = subprocess.run([sys.executable, "-c", f"import sys; print({text!r}); sys.exit({code})"],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=10, check=False)
        if accepted(result.stdout, result.returncode, RESULT, graphics=graphics) != expected:
            raise RuntimeError("Runner diagnostic/exit-code/marker contract failed")
    print(f"SESSION_REPORT_RUNNER_OK controls={len(cases)}", flush=True)


def isolated_env(directory: Path) -> dict[str, str]:
    environment = os.environ.copy()
    for variable, child in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                            ("XDG_CACHE_HOME", "cache")):
        destination = directory / child
        destination.mkdir(parents=True)
        environment[variable] = str(destination)
    environment["LIBGL_ALWAYS_SOFTWARE"] = "1"
    environment["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return environment


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="Only run synthetic runner controls")
    parser.add_argument("--graphics", action="store_true", help="Use an existing isolated X11 display")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        return 0
    if args.graphics and not os.environ.get("DISPLAY"):
        parser.error("--graphics requires an isolated display, e.g. xvfb-run -a")
    godot = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))
    with tempfile.TemporaryDirectory(prefix="lagunak-session-report-") as temporary:
        environment = isolated_env(Path(temporary))
        checked_run([godot, "--headless", "--editor", "--path", str(ROOT / "game"), "--quit"],
                    environment, import_phase=True)
        command = [godot, "--audio-driver", "Dummy", "--path", str(ROOT / "game")]
        if not args.graphics:
            command.append("--headless")
        command += ["--script", str(ROOT / "tests/test_session_report.gd"), "--", "--test"]
        checked_run(command, environment, RESULT, graphics=args.graphics)
    print("SESSION_REPORT_GATE_OK", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from error
