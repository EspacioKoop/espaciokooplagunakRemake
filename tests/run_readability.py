#!/usr/bin/env python3
"""Exercise live Godot UI and restart persistence in isolated local directories."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(ROOT / ".toolchain/godot"))
    parser.add_argument("--graphical", action="store_true")
    parser.add_argument("--screenshot", type=Path)
    args = parser.parse_args()
    if args.screenshot and not args.graphical:
        parser.error("--screenshot requires --graphical")
    with tempfile.TemporaryDirectory(prefix="lagunak-readability-") as temp:
        env = dict(os.environ, XDG_DATA_HOME=temp, XDG_CONFIG_HOME=temp)
        if args.screenshot:
            target = args.screenshot.resolve()
            target.parent.mkdir(parents=True, exist_ok=True)
            env["READABILITY_CAPTURE_PATH"] = str(target)
        for restart in (False, True):
            command = [args.godot, "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
                       "--script", str(ROOT / "tests/test_readability.gd"), "--", "--test"]
            if restart:
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
                result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, timeout=90, check=False)
            except (OSError, subprocess.TimeoutExpired) as error:
                raise SystemExit(f"Readability test could not complete: {error}") from error
            print(result.stdout, end="", flush=True)
            if (result.returncode or "SCRIPT ERROR:" in result.stdout or "\nERROR:" in result.stdout
                    or "READABILITY_OK" not in result.stdout):
                raise SystemExit(f"Readability test failed (restart={restart}, exit={result.returncode})")
    print("READABILITY_RUNNER_OK")


if __name__ == "__main__":
    main()
