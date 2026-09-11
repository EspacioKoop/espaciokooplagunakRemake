#!/usr/bin/env python3
"""Check sound captions in the real shell, audio playback and an independent restart."""
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
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ERROR = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR|USER ERROR|FATAL(?: ERROR)?|SOUND_CAPTIONS_FAIL):", re.M)
SUMMARY = re.compile(r"SOUND_CAPTIONS_RESULT checks=([0-9]+) failures=([0-9]+)")
MAX_LOG_BYTES = 2 * 1024 * 1024
IMAGES = ("sound-captions.png", "sound-caption-settings.png")


def validate_output(code: int, output: str) -> int:
    clean = ANSI.sub("", output).replace("\r\n", "\n")
    if code != 0 or ERROR.search(clean):
        raise ValueError("Engine reported an error")
    summaries = [line for line in clean.splitlines() if line.startswith("SOUND_CAPTIONS_RESULT")]
    markers = [line for line in clean.splitlines() if line.startswith("SOUND_CAPTIONS_OK")]
    match = SUMMARY.fullmatch(summaries[0]) if len(summaries) == 1 else None
    if match is None or int(match[1]) < 1 or int(match[2]) != 0 or markers != ["SOUND_CAPTIONS_OK"]:
        raise ValueError("Missing unique complete positive result and success marker")
    return int(match[1])


def isolated_environment(directory: Path) -> dict[str, str]:
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(("LAGUNAK_", "SOUND_CAPTION_")):
            env.pop(key)
    for key in ("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        location = directory / key.lower()
        location.mkdir()
        env[key] = str(location)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


def run_checked(command: list[str], env: dict[str, str], timeout: int = 90) -> int:
    with tempfile.TemporaryFile() as log:
        result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=timeout, check=False)
        log.seek(0)
        raw = log.read(MAX_LOG_BYTES + 1)
    if len(raw) > MAX_LOG_BYTES:
        raise ValueError("Engine log exceeded limit")
    output = raw.decode("utf-8", errors="replace")
    print(output, end="", flush=True)
    return validate_output(result.returncode, output)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(ROOT / ".toolchain/godot"))
    parser.add_argument("--graphical", action="store_true")
    parser.add_argument("--output", type=Path, help="Publish report and fresh graphical captures after all tests pass")
    args = parser.parse_args(argv)
    counts = {}
    with tempfile.TemporaryDirectory(prefix="lagunak-sound-captions-") as temp:
        directory = Path(temp)
        env = isolated_environment(directory)
        captures = directory / "captures"
        captures.mkdir()
        for phase in ("main", "restart", "audio"):
            env.pop("SOUND_CAPTION_CAPTURE_DIR", None)
            command = [str(Path(args.godot).resolve()), "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
                       "--script", str(ROOT / "tests/test_sound_captions.gd"), "--"]
            if phase == "main" and args.graphical:
                command.extend(["--test", "--require-display"])
                if args.output:
                    env["SOUND_CAPTION_CAPTURE_DIR"] = str(captures)
                if not env.get("DISPLAY"):
                    if not shutil.which("xvfb-run"):
                        raise SystemExit("Graphical verification requires DISPLAY or xvfb-run")
                    command = ["xvfb-run", "-a", "-s", "-screen 0 1600x900x24"] + command
            else:
                command.insert(1, "--headless")
                command += ["--verify-audio"] if phase == "audio" else ["--test"]
                if phase == "restart": command.append("--verify-persisted")
            try:
                counts[phase] = run_checked(command, env)
            except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                raise SystemExit(f"Sound captions failed ({phase}): {error}") from error
        if args.output:
            # Never accept an image from a previous invocation or publish a partial suite.
            if args.graphical:
                for name in IMAGES:
                    image = captures / name
                    if not image.is_file() or image.stat().st_size < 1024 or image.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
                        raise SystemExit("Missing fresh graphical evidence: " + name)
            output = args.output.resolve()
            output.mkdir(parents=True, exist_ok=True)
            if args.graphical:
                for name in IMAGES: shutil.copyfile(captures / name, output / name)
            paths = ["game/ui/app.gd", "game/ui/sound_captions.gd", "game/audio/sound_caption_queue.gd",
                     "game/input/sound_caption_profile.gd", "tests/test_sound_captions.gd", "tests/run_sound_captions.py"]
            report = {"checks": counts, "failures": 0, "graphical": args.graphical,
                      "sha256": {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths}}
            (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SOUND_CAPTIONS_RUNNER_OK")


if __name__ == "__main__":
    main()
