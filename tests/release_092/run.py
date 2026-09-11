#!/usr/bin/env python3
"""Test the Linux download itself with synthetic profiles and no loose game fallback."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from export_targets import VERSION, checked_zip, package_name
sys.path.insert(0, str(Path(__file__).parent))
import prepare

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ERROR = re.compile(r"(?im)^\s*(?:SCRIPT ERROR|ERROR|USER ERROR|FATAL(?: ERROR)?):|Unicode parsing error")
MAX_LOG_BYTES = 8 * 1024 * 1024
SCRIPTS = ("test_terminal_transition.gd", "test_leisure.gd", "test_ship_corridors.gd", "test_ship_deck_layout.gd")
IMAGES = ("terminal-navigation.png", "terminal-return.png")


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def validate_output(code: int, text: str, phase: str) -> int:
    clean = ANSI.sub("", text).replace("\r\n", "\n")
    if code or ERROR.search(clean):
        raise ValueError(f"{phase}: engine error or nonzero exit")
    prefix, pattern, minimum = {
        "contract": ("EXPORT_CONTRACT_RESULT", r"EXPORT_CONTRACT_RESULT checks=(\d+) failures=(\d+)", 16),
        "terminals": ("TERMINAL_TRANSITION_RESULT", r"TERMINAL_TRANSITION_RESULT checks=(\d+) failures=(\d+)", 161),
        "leisure": ("LEISURE_TESTS", r"LEISURE_TESTS (\d+) checks; (\d+) failures", 100),
    }[phase]
    summaries = [line for line in clean.splitlines() if line.startswith(prefix)]
    match = re.fullmatch(pattern, summaries[0]) if len(summaries) == 1 else None
    if match is None or int(match[1]) < minimum or int(match[2]) != 0:
        raise ValueError(f"{phase}: missing, ambiguous or failed full result")
    return int(match[1])


def isolated_environment(directory: Path) -> dict[str, str]:
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("LAGUNAK_", "GODOT_")):
            env.pop(key)
    for key in ("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        path = directory / key.lower()
        path.mkdir(parents=True)
        env[key] = str(path)
    env.update(GODOT_SILENCE_ROOT_WARNING="1", LIBGL_ALWAYS_SOFTWARE="1")
    return env


def embedded_command(binary: Path, phase: str, captures: Path) -> list[str]:
    if phase not in ("contract", "terminals", "leisure"):
        raise ValueError("Unknown embedded acceptance phase")
    command = [str(binary), "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility", "--", "--test", "--release-acceptance=" + phase]
    if phase == "contract":
        command += ["--expected-version=" + VERSION, "--expected-fixtures=" + digest(ROOT / prepare.MANIFEST)]
    if phase == "terminals":
        command += ["--evidence-dir", str(captures)]
    return command


def extract_binary(package: Path, target: Path) -> Path:
    with checked_zip(package) as archive:
        entry = archive.getinfo("EspaciokoopLagunak.x86_64")
        if entry.file_size < 1_000_000 or entry.file_size > 2 * 1024**3:
            raise ValueError("Missing or implausible exported application")
        if "LICENSE" not in archive.namelist():
            raise ValueError("Download lacks its license")
        binary = target / entry.filename
        with archive.open(entry) as source, binary.open("wb") as output:
            shutil.copyfileobj(source, output)
    with binary.open("rb") as stream:
        if stream.read(4) != b"\x7fELF":
            raise ValueError("Download does not contain an ELF application")
    binary.chmod(0o755)
    return binary


def run_checked(command: list[str], environment: dict[str, str], cwd: Path, log_path: Path, phase: str, timeout: float = 240) -> int:
    with tempfile.TemporaryFile() as log:
        try:
            process = subprocess.Popen(command, cwd=cwd, env=environment, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            log.seek(0)
            log_path.write_bytes(log.read(MAX_LOG_BYTES) + b"\nRUNNER_TIMEOUT\n")
            raise
        log.seek(0)
        raw = log.read(MAX_LOG_BYTES + 1)
    if len(raw) > MAX_LOG_BYTES:
        raise ValueError("Engine log exceeded bounded size")
    text = ANSI.sub("", raw.decode("utf-8", errors="replace"))
    log_path.write_text(text, encoding="utf-8")
    print(text[-4000:], end="", flush=True)
    return validate_output(process.returncode, text, phase)


def verify_image(path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 1024 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR" or struct.unpack(">II", data[16:24]) != (1600, 900):
        raise ValueError("Missing fresh 1600x900 graphical evidence: " + path.name)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, default=ROOT / "dist" / package_name("linux"))
    parser.add_argument("--output", type=Path, default=ROOT / "build/release-092")
    args = parser.parse_args(argv)
    package = args.package.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / "report.json").unlink(missing_ok=True)
    for name in IMAGES:
        (output / name).unlink(missing_ok=True)
    if package.name != package_name("linux"):
        raise ValueError("Package name does not match the explicit release version")
    prepare.prepare(check=True)
    package_hash = digest(package)
    counts = {}
    with tempfile.TemporaryDirectory(prefix="lagunak-export-acceptance-") as temporary:
        directory = Path(temporary)
        binary = extract_binary(package, directory)
        binary_hash = digest(binary)
        captures = directory / "captures"
        captures.mkdir()
        for phase in ("contract", "terminals", "leisure"):
            profile = directory / phase
            profile.mkdir()
            env = isolated_environment(profile)
            # Deliberately empty cwd: no project.godot, .godot or game sources.
            work = profile / "empty"
            work.mkdir()
            command = embedded_command(binary, phase, captures)
            if not env.get("DISPLAY"):
                if not shutil.which("xvfb-run"):
                    raise ValueError("Real display or xvfb-run is required; headless is not a substitute")
                command = ["xvfb-run", "-a", "-s", "-screen 0 1600x900x24", *command]
            counts[phase] = run_checked(command, env, work, output / (phase + ".log"), phase)
        for name in IMAGES: verify_image(captures / name)
        if digest(binary) != binary_hash or digest(package) != package_hash:
            raise ValueError("The tested download changed during acceptance")
        for name in IMAGES: shutil.copyfile(captures / name, output / name)
        sources = [ROOT / "tests" / name for name in SCRIPTS] + [Path(__file__), Path(__file__).with_name("test_export_contract.gd"), ROOT / "game/release_acceptance/dispatch.gd", Path(__file__).with_name("prepare.py")]
        report = {"version": VERSION, "package": package.name, "package_sha256": package_hash, "binary_sha256": binary_hash,
                  "checks": counts, "failures": 0, "graphical": True, "loose_project_fallback": False, "embedded_fixtures": True, "fixture_manifest_sha256": digest(ROOT / prepare.MANIFEST),
                  "sources_sha256": {str(path.relative_to(ROOT)): digest(path) for path in sources},
                  "limits": "Synthetic fixtures; terminal positioning is not an uninterrupted human walk. Existing leisure tests physically traverse six links both ways and inspect thirteen destinations. No user hardware or human playtest certification."}
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("EXPORTED_RELEASE_ACCEPTANCE_OK", json.dumps(counts), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        raise SystemExit("EXPORTED_RELEASE_ACCEPTANCE_FAILED: " + str(error)) from error
