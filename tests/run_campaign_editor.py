#!/usr/bin/env python3
"""Exercise the real campaign editor without touching a player's save directory."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=str(ROOT / ".toolchain/godot"))
    parser.add_argument("--capture", action="store_true")
    args = parser.parse_args()
    command = [args.godot, "--path", str(ROOT / "game"), "--audio-driver", "Dummy",
               "--script", str(ROOT / "tests/test_campaign_editor.gd"), "--", "--test"]
    if args.capture:
        command += ["--campaign-capture"]
    else:
        command.insert(1, "--headless")
    with tempfile.TemporaryDirectory(prefix="lagunak-campaign-") as directory:
        env = dict(os.environ, XDG_DATA_HOME=directory, XDG_CONFIG_HOME=directory)
        try:
            result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=60)
            output = result.stdout
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            print(output, flush=True)
            raise SystemExit("Campaign test did not reach its completion marker in 60 seconds") from error
    print(output, end="", flush=True)
    if result.returncode or re.search(r"^(?:SCRIPT ERROR|ERROR):", output, re.MULTILINE):
        raise SystemExit(1)
    if not re.search(r"CAMPAIGN_OK \d+ checks; 0 failures", output):
        raise SystemExit("Missing successful campaign completion marker")


if __name__ == "__main__":
    main()
