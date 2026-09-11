#!/usr/bin/env python3
"""Verify GM authoring, persistence, the model library, UI and real ENet boundaries."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
PACK: str | None = None
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DIAGNOSTIC = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR|GM_LIVE_FAIL|GM_LIVE_UI_FAIL|RUNTIME_ASSET_FAIL|GM_NETWORK_FAIL)\b|Unicode parsing error", re.M)
PATTERNS = {
    "core": r"GM_LIVE_RESULT checks=([1-9][0-9]*) failures=0",
    "legacy": r"GM_HOT_CONSOLE_TESTS ([1-9][0-9]*) checks; 0 failures",
    "models": r"RUNTIME_ASSET_RESULT checks=([1-9][0-9]*) failures=0",
    "ui": r"GM_LIVE_UI_RESULT checks=([1-9][0-9]*) failures=0",
    "host": r"GM_NETWORK_RESULT case=host checks=([1-9][0-9]*) failures=0",
    "client": r"GM_NETWORK_RESULT case=client checks=([1-9][0-9]*) failures=0",
}


def validate_output(code: int, output: str, suite: str = "core") -> bool:
    clean = ANSI.sub("", output)
    pattern = PATTERNS[suite]
    prefix = pattern.split(" ", 1)[0]
    summaries = [line for line in clean.splitlines() if line.startswith(prefix)]
    return (code == 0 and not DIAGNOSTIC.search(clean) and len(summaries) == 1
            and re.fullmatch(pattern, summaries[0]) is not None)


def environment(folder: Path) -> dict[str, str]:
    env = dict(os.environ)
    for name in ("HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"):
        path = folder / name.lower()
        path.mkdir(parents=True, exist_ok=True)
        env[name] = str(path)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


def stop(process: subprocess.Popen) -> None:
    if process.poll() is None:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
        try:
            process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            if os.name == "posix": os.killpg(process.pid, signal.SIGKILL)
            else: process.kill()
            process.wait(timeout=4)


def command(godot: str, script: str, graphical: bool = False) -> list[str]:
    location = ["--main-pack", PACK] if PACK else ["--path", str(ROOT / "game")]
    result = [godot, "--audio-driver", "Dummy", *location,
              "--script", str(ROOT / "tests" / script), "--", "--test"]
    if not graphical: result.insert(1, "--headless")
    else: result.append("--require-display")
    return result


def execute(cmd: list[str], env: dict[str, str], suite: str, timeout: int = 120) -> str:
    process = subprocess.Popen(cmd, cwd=ROOT, env=env, text=True, encoding="utf-8",
                               errors="replace", stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               start_new_session=os.name == "posix")
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        stop(process)
        raise RuntimeError(f"{suite} exceeded {timeout} seconds") from error
    finally:
        stop(process)
    print(output, end="", flush=True)
    if not validate_output(process.returncode, output, suite):
        raise RuntimeError(f"{suite} failed (exit={process.returncode})")
    return output


def network(godot: str, folder: Path) -> list[str]:
    sync = folder / "sync"
    sync.mkdir()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    children = []
    outputs = []
    try:
        for role in ("host", "client"):
            log = folder / f"{role}.log"
            stream = log.open("w", encoding="utf-8")
            cmd = command(godot, "test_gm_live_network.gd")
            cmd += ["--gm-case", role, "--gm-port", str(port), "--gm-sync", str(sync)]
            process = subprocess.Popen(cmd, cwd=ROOT, env=environment(folder / role),
                                       stdout=stream, stderr=subprocess.STDOUT,
                                       start_new_session=os.name == "posix")
            children.append((role, process, stream, log))
            if role == "host":
                deadline = time.monotonic() + 20
                while "GM_NETWORK_HOST_READY" not in log.read_text(encoding="utf-8", errors="replace"):
                    if process.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError("GM host did not become ready: " + log.read_text())
                    time.sleep(0.05)
        for role, process, stream, log in children:
            process.wait(timeout=40)
            stream.close()
            output = log.read_text(encoding="utf-8", errors="replace")
            print(output, end="", flush=True)
            if not validate_output(process.returncode, output, role):
                raise RuntimeError(f"GM ENet {role} failed")
            outputs.append(output)
    finally:
        for _, process, stream, _ in children:
            stop(process)
            stream.close()
    return outputs


def validate_capture(path: Path) -> str:
    from PIL import Image
    if not path.is_file() or not 10000 <= path.stat().st_size <= 16 * 1024 * 1024:
        raise RuntimeError("Missing or implausible current-run capture")
    with Image.open(path) as image:
        if image.format != "PNG" or image.size != (1600, 900):
            raise RuntimeError("Invalid screenshot dimensions or format")
        image.verify()
    with Image.open(path) as image:
        image.load()
        if len(set(image.convert("RGB").getdata())) < 32:
            raise RuntimeError("Empty screenshot")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    global PACK
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(ROOT / ".toolchain/godot"))
    parser.add_argument("--graphical", action="store_true")
    parser.add_argument("--pack", type=Path, help="Run from an exported PCK, not the source project")
    parser.add_argument("--capture-dir", type=Path)
    args = parser.parse_args()
    if args.pack:
        if not args.pack.is_file(): parser.error("exported pack does not exist")
        PACK = str(args.pack.resolve())
    if args.capture_dir and not args.graphical: parser.error("captures require --graphical")
    try:
        with tempfile.TemporaryDirectory(prefix="lagunak-gm-live-") as temp:
            folder = Path(temp)
            env = environment(folder / "user")
            for script, suite in (("test_gm_hot_console.gd", "legacy"), ("test_gm_live.gd", "core"),
                                  ("test_runtime_assets.gd", "models")):
                execute(command(args.godot, script), env, suite)
            cmd = command(args.godot, "test_gm_live_ui.gd", args.graphical)
            captures = folder / "captures"
            if args.capture_dir:
                captures.mkdir()
                env["GM_LIVE_CAPTURE_DIR"] = str(captures)
            if args.graphical and not env.get("DISPLAY"):
                if not shutil.which("xvfb-run"): raise RuntimeError("Graphical validation requires xvfb-run or DISPLAY")
                cmd = ["xvfb-run", "-a", "-s", "-screen 0 1600x900x24"] + cmd
            execute(cmd, env, "ui")
            network(args.godot, folder)
            # Validate fresh outputs, then publish; failed runs leave old evidence intact.
            if args.capture_dir:
                names = ("gm-live.png", "runtime-asset-library.png")
                hashes = {name: validate_capture(captures / name) for name in names}
                args.capture_dir.mkdir(parents=True, exist_ok=True)
                for name in names:
                    target = args.capture_dir / name
                    pending = target.with_suffix(".png.tmp")
                    shutil.copyfile(captures / name, pending)
                    os.replace(pending, target)
                (args.capture_dir / "captures.json").write_text(json.dumps(hashes, indent=2) + "\n")
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(f"GM_LIVE_RUNNER_FAIL {error}", flush=True)
        return 1
    print("GM_LIVE_RUNNER_OK", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
