#!/usr/bin/env python3
"""Exercise imported model consumers and native input with an isolated local profile."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def environment(directory: Path) -> dict[str, str]:
    env = dict(os.environ)
    for key in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
        path = directory / key.lower()
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


def validate(code: int, output: str, capture: bool) -> dict:
    output = ANSI.sub("", output)
    if code != 0 or re.search(r"(?:SCRIPT ERROR|ERROR):|Unicode parsing error", output):
        raise ValueError("Godot execution failed")
    matches = re.findall(r"^TACTICAL_MODELS_RESULT (.+)$", output, re.M)
    if len(matches) != 1:
        raise ValueError("Missing or ambiguous test report")
    report = json.loads(matches[0])
    if not isinstance(report, dict) or type(report.get("checks")) is not int or report["checks"] < 1 or type(report.get("failures")) is not int or report["failures"] != 0 or report.get("passed") is not True or report.get("capture") is not capture:
        raise ValueError("Invalid or failed test report")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")))
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--pack", type=Path, help="Test an exported PCK without a loose project")
    args = parser.parse_args()
    if args.capture:
        args.capture = args.capture.resolve()
        args.capture.parent.mkdir(parents=True, exist_ok=True)
        args.capture.unlink(missing_ok=True)
    command = [args.godot, "--audio-driver", "Dummy"]
    command += ["--main-pack", str(args.pack.resolve())] if args.pack else ["--path", str(ROOT / "game")]
    command += ["--script", str(ROOT / "tests/test_tactical_models.gd")]
    command += ["--rendering-method", "gl_compatibility"] if args.capture else ["--headless"]
    command += ["--", "--test"]
    if args.capture:
        command += [f"--capture={args.capture}"]
    try:
        with tempfile.TemporaryDirectory(prefix="lagunak-tactical-models-") as temporary:
            result = subprocess.run(command, cwd=temporary if args.pack else ROOT, env=environment(Path(temporary)), capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180, check=False)
        output = result.stdout + result.stderr
        print(output, end="", flush=True)
        report = validate(result.returncode, output, args.capture is not None)
        if args.capture and (not args.capture.is_file() or args.capture.stat().st_size < 1024 or args.capture.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n"):
            raise ValueError("Fresh PNG evidence missing")
        print(f"TACTICAL_MODELS_OK {report['checks']} checks")
        return 0
    except (OSError, subprocess.TimeoutExpired, ValueError) as error:
        print(f"TACTICAL_MODELS_FAILED: {error}", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
