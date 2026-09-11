#!/usr/bin/env python3
"""Run the native station school with isolated profiles and fresh evidence."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))")
ERROR = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR):|Unicode parsing error", re.MULTILINE)
MARKER = "CREW_TRAINING_RESULT "


def check_log(output: str) -> str:
    cleaned = ANSI.sub("", output).replace("\r\n", "\n")
    if ERROR.search(cleaned):
        raise ValueError("Godot reported an engine/script error")
    return cleaned


def validate_output(output: str) -> dict:
    lines = [line[len(MARKER):] for line in check_log(output).splitlines() if line.startswith(MARKER)]
    if len(lines) != 1:
        raise ValueError("Expected one unambiguous training result")
    result = json.loads(lines[0])
    if not isinstance(result, dict):
        raise ValueError("Training result must be an object")
    if type(result.get("checks")) is not int or result["checks"] < 150:
        raise ValueError("Incomplete training checks")
    if type(result.get("failures")) is not int or result["failures"] != 0:
        raise ValueError("Native checks failed")
    if type(result.get("courses")) is not int or result["courses"] != 9:
        raise ValueError("All nine courses must complete")
    if result.get("first_mission") is not True or result.get("ui") is not True:
        raise ValueError("Native first mission and UI must be exercised")
    return result


def isolated_environment(directory: Path) -> dict[str, str]:
    env = {k: v for k, v in os.environ.items() if not k.startswith(("LAGUNAK_", "CREW_TRAINING_"))}
    for key in ("HOME", "USERPROFILE", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
        folder = directory / key.lower()
        folder.mkdir(parents=True, exist_ok=True)
        env[key] = str(folder)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


def execute(command: list[str], env: dict[str, str], logfile: Path) -> str:
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                                errors="replace", timeout=180, check=False)
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or b""
        logfile.write_text(partial.decode("utf-8", "replace") if isinstance(partial, bytes) else partial, encoding="utf-8")
        raise RuntimeError("Godot exceeded the native test time limit") from error
    logfile.write_text(result.stdout, encoding="utf-8")
    print(result.stdout, end="")
    if result.returncode:
        raise RuntimeError(f"Godot exited with status {result.returncode}")
    check_log(result.stdout)
    return result.stdout


def validate_capture(path: Path) -> str:
    from PIL import Image
    if not path.is_file() or path.stat().st_size < 1024:
        raise ValueError("Fresh rendered capture is missing")
    with Image.open(path) as image:
        if image.format != "PNG" or image.size != (940, 860):
            raise ValueError("Unexpected capture format/dimensions")
        image.verify()
    with Image.open(path) as image:
        image.load()
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(binary: Path, output: Path, graphical: bool) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    # A previous success report must not survive a failed verification.
    (output / "result.json").unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix="lagunak-crew-training-") as temporary:
        directory = Path(temporary)
        env = isolated_environment(directory)
        execute([str(binary), "--headless", "--editor", "--path", str(ROOT / "game"), "--quit", "--", "--test"], env, output / "import.log")
        capture = directory / "new-school.png"
        if graphical:
            env["CREW_TRAINING_SCREENSHOT"] = str(capture)
        command = [str(binary)] + ([] if graphical else ["--headless"])
        command += ["--path", str(ROOT / "game"), "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
                    "--script", str(ROOT / "tests/test_crew_training.gd"), "--", "--test"]
        result = validate_output(execute(command, env, output / "training.log"))
        if graphical:
            result["capture_sha256"] = validate_capture(capture)
            staging = output / "school.png.tmp"
            try:
                shutil.copyfile(capture, staging)
                staging.replace(output / "school.png")
            finally:
                staging.unlink(missing_ok=True)
        result["graphical"] = graphical
        (output / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")))
    parser.add_argument("--graphical", action="store_true")
    parser.add_argument("--output", type=Path, default=ROOT / "build/crew-training")
    args = parser.parse_args(argv)
    binary = Path(shutil.which(args.godot) or args.godot).resolve()
    if not binary.is_file():
        print("CREW_TRAINING_FAILED: Godot not found; run tools/bootstrap.py")
        return 2
    try:
        run(binary, args.output.resolve(), args.graphical)
    except (OSError, ValueError, RuntimeError, ImportError) as error:
        print(f"CREW_TRAINING_FAILED: {error}")
        return 1
    print("CREW_TRAINING_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
