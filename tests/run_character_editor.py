#!/usr/bin/env python3
"""Fail-closed character editor gates; every process gets disposable user data."""
from pathlib import Path
import argparse
import os
import re
import shutil
import socket
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))
ERRORS = re.compile(r"^(?:SCRIPT ERROR|ERROR):", re.MULTILINE)


def isolated_env(directory):
    env = os.environ.copy()
    for key, child in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                       ("XDG_CACHE_HOME", "cache")):
        location = directory / child
        location.mkdir(parents=True, exist_ok=True)
        env[key] = str(location)
    return env


def godot_command(script):
    return [GODOT, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
            "--script", str(ROOT / "tests" / script), "--", "--test"]


def checked_run(command, environment, marker=None):
    try:
        result = subprocess.run(command, env=environment, cwd=ROOT, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        print(output.decode(errors="replace") if isinstance(output, bytes) else output, flush=True)
        raise
    print(result.stdout, flush=True)
    if result.returncode or ERRORS.search(result.stdout) or (marker and not re.search(marker, result.stdout)):
        raise RuntimeError(f"Character gate failed: {command}")


def network(directory):
    # The host binds before any client is launched. A collision fails closed.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as candidate:
        candidate.bind(("127.0.0.1", 0))
        port = candidate.getsockname()[1]
    processes = []
    try:
        for name in ("host", "nav", "eng"):
            path = directory / f"{name}.log"
            stream = path.open("w", encoding="utf-8")
            command = godot_command("test_character_network.gd") + ["--case", name, "--port", str(port)]
            process = subprocess.Popen(command, cwd=ROOT, env=isolated_env(directory / name),
                                       stdout=stream, stderr=subprocess.STDOUT)
            processes.append((name, process, stream, path))
            if name == "host":
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    text = path.read_text(encoding="utf-8")
                    if "CHARACTER_HOST_READY" in text:
                        break
                    if process.poll() is not None or ERRORS.search(text):
                        raise RuntimeError(text)
                    time.sleep(.05)
                else:
                    raise RuntimeError("Character host did not become ready\n" + path.read_text())
        failed = []
        for name, process, stream, path in processes:
            code = process.wait(timeout=40)
            stream.close()
            output = path.read_text(encoding="utf-8")
            print(output, flush=True)
            if code or ERRORS.search(output) or not re.search(
                    rf"CHARACTER_NETWORK_RESULT {name} checks=\d+ failures=0", output):
                failed.append(name)
        if failed:
            raise RuntimeError("Character network failures: " + ", ".join(failed))
        print("CHARACTER_NETWORK_OK host plus two authenticated clients", flush=True)
    finally:
        for _, process, stream, _ in processes:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            stream.close()


def capture_export(directory, output, binary, env):
    """Exercise release-template UI with X11 input, not unsupported --script."""
    import hashlib
    import json
    from PIL import ImageGrab

    xdotool = shutil.which("xdotool") or str(ROOT / ".toolchain/display/usr/bin/xdotool")
    executable = binary.resolve()
    command = [str(executable), "--resolution", "1600x900", "--position", "0,0",
               "--audio-driver", "Dummy"]
    previous_authority = os.environ.get("XAUTHORITY")
    os.environ["XAUTHORITY"] = env["XAUTHORITY"]
    game = None
    logs = []

    def x(*args):
        return subprocess.check_output([xdotool, *args], env=env, text=True).strip()

    def wait_for(predicate, description, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if game is None or game.poll() is not None:
                raise RuntimeError("Export exited before " + description)
            if predicate():
                return
            time.sleep(.1)
        raise RuntimeError("Export did not reach " + description)

    def image():
        return ImageGrab.grab(xdisplay=env["DISPLAY"])

    def open_editor():
        assert game is not None
        wait_for(lambda: image().convert("RGB").getpixel((2, 2)) == (8, 19, 31),
                 "rendered application shell", timeout=120)
        windows = x("search", "--onlyvisible", "--pid", str(game.pid)).split()
        if len(windows) != 1:
            raise RuntimeError("Expected one isolated embedded application window")
        x("windowfocus", "--sync", windows[0])
        x("key", "F4")
        time.sleep(.5)
        x("mousemove", "1036", "120", "click", "1")
        time.sleep(.5)

    def persisted():
        saves = list(Path(env["XDG_DATA_HOME"]).glob("godot/app_userdata/**/expedition-systems.json"))
        if len(saves) != 1:
            return None
        try:
            return json.loads(saves[0].read_text())["profiles"]["self"]
        except (ValueError, KeyError, OSError):
            return None

    try:
        for attempt in range(2):
            log_path = directory / f"export-{attempt}.log"
            with log_path.open("w") as stream:
                game = subprocess.Popen(command, env=env, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
                try:
                    open_editor()
                    if attempt == 0:
                        x("mousemove", "640", "293", "click", "1", "key", "ctrl+a",
                          "type", "Tripulante probado")
                        x("mousemove", "1120", "710", "click", "1")
                        wait_for(lambda: (persisted() or {}).get("name") == "Tripulante probado",
                                 "profile saved through public editor controls")
                        profile = persisted()
                        if profile is None:
                            raise RuntimeError("Profile vanished after acknowledged save")
                        for key, expected in {"xp": 0, "level": 1, "focus": 3, "condition": 100,
                                              "traits": [], "milestones": [], "approach": "ingenio",
                                              "skills": dict.fromkeys(("pilotaje", "ciencia", "ingenieria",
                                                                        "negociacion", "combate"), 1)}.items():
                            if profile.get(key) != expected:
                                raise RuntimeError("Unexpected progression change: " + key)
                        image().save(output)
                    else:
                        # A second real UI edit after restarting proves load + persistence.
                        x("mousemove", "640", "293", "click", "1", "key", "End", "type", " recargado")
                        x("mousemove", "1120", "710", "click", "1")
                        wait_for(lambda: (persisted() or {}).get("name") == "Tripulante probado recargado",
                                 "persisted profile reloaded and edited after executable restart")
                finally:
                    if game.poll() is None:
                        game.terminate()
                        try:
                            game.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            game.kill()
                            game.wait(timeout=5)
            text = log_path.read_text()
            print(text, flush=True)
            if ERRORS.search(text):
                raise RuntimeError("Runtime errors in release export")
            logs.append(text)
        evidence = {"binary_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                    "input": "X11 F4, mouse and keyboard; no debug commands or external script",
                    "profile": persisted(), "restart_roundtrip": True, "runtime_logs": logs}
        output.with_suffix(".evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print("CHARACTER_EXPORT_OK public F4/edit/apply + persisted restart round-trip", flush=True)
    finally:
        if previous_authority is None:
            os.environ.pop("XAUTHORITY", None)
        else:
            os.environ["XAUTHORITY"] = previous_authority


def capture(directory, output, binary=None):
    display_root = ROOT / ".toolchain/display"
    xvfb = shutil.which("Xvfb") or str(display_root / "usr/bin/Xvfb")
    display = next(number for number in range(120, 600)
                   if not Path(f"/tmp/.X{number}-lock").exists()
                   and not Path(f"/tmp/.X11-unix/X{number}").exists())
    env = isolated_env(directory / "visual")
    env["DISPLAY"] = f":{display}"
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    env["LD_LIBRARY_PATH"] = str(display_root / "usr/lib/x86_64-linux-gnu") + ":" + env.get("LD_LIBRARY_PATH", "")
    authority = directory / "display-auth"
    def field(value):
        return struct.pack(">H", len(value)) + value
    authority.write_bytes(struct.pack(">H", 65535) + field(b"") + field(str(display).encode())
                          + field(b"MIT-MAGIC-COOKIE-1") + field(os.urandom(16)))
    authority.chmod(0o600)
    env["XAUTHORITY"] = str(authority)
    server = subprocess.Popen([xvfb, f":{display}", "-screen", "0", "1600x900x24",
                               "-nolisten", "tcp", "-auth", str(authority)],
                              env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    assert server.stderr is not None
    try:
        deadline = time.monotonic() + 10
        while not Path(f"/tmp/.X11-unix/X{display}").exists():
            if server.poll() is not None:
                raise RuntimeError(server.stderr.read().decode())
            if time.monotonic() > deadline:
                raise RuntimeError("Isolated graphical display failed to become ready")
            time.sleep(.05)
        output = output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.exists():
            raise RuntimeError(f"Refusing to overwrite capture evidence: {output}")
        if binary:
            capture_export(directory, output, binary, env)
        else:
            command = [GODOT, "--path", str(ROOT / "game"), "--resolution", "1600x900",
                       "--audio-driver", "Dummy", "--script", str(ROOT / "tests/test_character_editor.gd"),
                       "--", "--test", "--capture-to", str(output)]
            checked_run(command, env, r"CHARACTER_EDITOR_CAPTURE_OK")
        data = output.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != (1600, 900):
            raise RuntimeError("Invalid character editor screenshot")
        print(f"CHARACTER_CAPTURE_OK {output}", flush=True)
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait(timeout=5)
        server.stderr.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-to", type=Path, help="Capture the exercised editor on an isolated display")
    parser.add_argument("--binary", type=Path, help="Run the graphical check from an exported Linux binary")
    parser.add_argument("--capture-only", action="store_true", help="Run just the graphical editor gate")
    parser.add_argument("--from-crew", action="store_true", help="CI crew entry already ran crew regression")
    args = parser.parse_args()
    if args.capture_only and not args.capture_to:
        parser.error("--capture-only requires --capture-to")
    if args.binary and not args.capture_to:
        parser.error("--binary requires --capture-to")
    with tempfile.TemporaryDirectory(prefix="lagunak-character-") as temporary:
        directory = Path(temporary)
        if args.capture_only:
            capture(directory, args.capture_to, args.binary)
            return
        checked_run([GODOT, "--headless", "--editor", "--path", str(ROOT / "game"), "--quit"],
                    isolated_env(directory / "import"))
        for script, marker in (
            ("test_character_editor.gd", r"CHARACTER_EDITOR_TESTS \d+ checks; 0 failures"),
            ("test_crew.gd", r"CREW_TESTS \d+ checks; 0 failures"),
            ("test_expedition.gd", r"EXPEDITION_TESTS \d+ checks; 0 failures"),
            ("test_ground_combat.gd", r"GROUND_COMBAT_TESTS \d+ checks; 0 failures"),
        ):
            if args.from_crew and script == "test_crew.gd":
                continue
            command = godot_command(script)
            if script == "test_crew.gd":
                command += ["--character-child"]
            checked_run(command, isolated_env(directory / script.removesuffix(".gd")), marker)
        network(directory)
        if args.capture_to:
            capture(directory, args.capture_to, args.binary)
    print("CHARACTER_EDITOR_OK isolated format/UI/persistence/regression/ENet gates", flush=True)


if __name__ == "__main__":
    main()
