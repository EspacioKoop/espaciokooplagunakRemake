#!/usr/bin/env python3
"""Run native assistance/training checks with disposable local user directories."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SUITES = (("test_cooperation.gd", "COOPERATION_TESTS", 40),
          ("test_assistance_training.gd", "ASSISTANCE_TRAINING_TESTS", 100))


def validate_output(output: str, marker: str, minimum: int) -> None:
    """Godot can exit zero after script errors; require an unambiguous summary."""
    if re.search(r"^\s*(?:SCRIPT ERROR|ERROR):", output, re.MULTILINE):
        raise ValueError("Godot reported a script or engine error")
    summaries = re.findall(rf"^{re.escape(marker)} (\d+) checks; (\d+) failures\s*$",
                           output, re.MULTILINE)
    if len(summaries) != 1:
        raise ValueError(f"Expected exactly one {marker} summary")
    checks, failures = map(int, summaries[0])
    if checks < minimum or failures:
        raise ValueError(f"Incomplete or failed {marker}: {checks} checks, {failures} failures")


def run_suite(binary: Path, script: str, marker: str, minimum: int,
              graphical: bool, output: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="lagunak-training-") as temporary:
        home = Path(temporary)
        env = os.environ.copy()
        for key, subdir in (("HOME", "home"), ("USERPROFILE", "home"),
                            ("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                            ("XDG_CACHE_HOME", "cache"), ("APPDATA", "appdata"),
                            ("LOCALAPPDATA", "localappdata")):
            directory = home / subdir
            directory.mkdir(exist_ok=True)
            env[key] = str(directory)
        # Do not inherit capture paths or headless-server/bridge options.
        for key in list(env):
            if key.startswith(("LAGUNAK_", "TRAINING_")):
                env.pop(key)
        if graphical and marker == "ASSISTANCE_TRAINING_TESTS":
            screenshot = output / "assistance-training.png"
            screenshot.unlink(missing_ok=True)  # A previous run is not evidence.
            env["TRAINING_SCREENSHOT"] = str(screenshot)
        command = [str(binary)]
        if not graphical:
            command.append("--headless")
        command += ["--path", str(ROOT / "game"), "--rendering-method", "gl_compatibility",
                    "--audio-driver", "Dummy", "--script", str(ROOT / "tests" / script),
                    "--", "--test"]
        logfile = output / f"{Path(script).stem}.log"
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                                    errors="replace", timeout=120, check=False)
        except subprocess.TimeoutExpired as exc:
            text = exc.stdout or ""
            if isinstance(text, bytes):
                text = text.decode("utf-8", errors="replace")
            logfile.write_text(text, encoding="utf-8")
            raise RuntimeError(f"{script} exceeded 120 seconds; see {logfile}") from exc
        logfile.write_text(result.stdout, encoding="utf-8")
        print(result.stdout, end="")
        if result.returncode:
            raise RuntimeError(f"{script} exited with {result.returncode}")
        validate_output(result.stdout, marker, minimum)
        if graphical and marker == "ASSISTANCE_TRAINING_TESTS":
            screenshot = output / "assistance-training.png"
            if not screenshot.is_file() or screenshot.stat().st_size < 1024:
                raise RuntimeError("Graphical training evidence is missing")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")))
    parser.add_argument("--graphical", action="store_true", help="Use a real display/Xvfb and capture the UI")
    parser.add_argument("--output", type=Path, default=ROOT / "build/assistance-training")
    args = parser.parse_args(argv)
    binary = Path(shutil.which(args.godot) or args.godot).resolve()
    if not binary.is_file():
        print(f"Godot not found: {binary}. Run tools/bootstrap.py and import game resources first.", file=sys.stderr)
        return 2
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    try:
        for script, marker, minimum in SUITES:
            run_suite(binary, script, marker, minimum, args.graphical, output)
    except (OSError, RuntimeError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print("ASSISTANCE_TRAINING_RUNNER_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
