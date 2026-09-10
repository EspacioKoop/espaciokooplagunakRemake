#!/usr/bin/env python3
"""Terminal regression with disposable user data and fail-closed diagnostics."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "8b1dcf27683a00972b03d5203606eab12f31fe2d"
BASELINE_APP_BLOB = "e5de540c1b317d69b4126dc895d42074fbaf9eb3"
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
RESULT = re.compile(r"^TERMINAL_TRANSITION_RESULT checks=([1-9]\d*) failures=(\d+)$", re.M)
DIAGNOSTIC = re.compile(r"^(?:SCRIPT ERROR:|ERROR:|WARNING:|Parse Error:|Unicode parsing error)", re.I)
VSYNC = "WARNING: Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver."
NUL_WARNING = "Unicode parsing error, some characters were replaced with \ufffd (U+FFFD): Unexpected NUL character"
NUL_SOURCE_SHA256 = "5d47e74bcab86b2f4ab5579d8e7754b61066c640958e2e383d9fdeb8abb9236a"


def isolated_env(directory: Path) -> dict[str, str]:
    env = os.environ.copy()
    for key, name in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"),
                      ("XDG_CACHE_HOME", "cache")):
        path = directory / name
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    return env


def diagnostics(text: str, *, graphics: bool = False, import_source: Path | None = None) -> list[str]:
    errors = []
    allowed_nul = False
    for raw in ANSI.sub("", text).splitlines():
        line = raw.strip()
        if not DIAGNOSTIC.match(line):
            continue
        if graphics and line == VSYNC:
            continue
        # Same existing, file-pinned import exception as run_character_editor.py.
        # Never allow this diagnostic during actual gameplay or for changed code.
        if (line == NUL_WARNING and import_source is not None and not allowed_nul
                and import_source.is_file()
                and hashlib.sha256(import_source.read_bytes()).hexdigest() == NUL_SOURCE_SHA256):
            allowed_nul = True
            continue
        errors.append(line)
    return errors


def validates_gameplay(code: int, output: str) -> bool:
    matches = RESULT.findall(ANSI.sub("", output))
    return (code == 0 and not diagnostics(output, graphics=True) and len(matches) == 1
            and int(matches[0][0]) >= 100 and int(matches[0][1]) == 0)


def run(command: list[str], env: dict[str, str], log: Path, timeout: float = 240) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, text=True, encoding="utf-8",
                                errors="replace", stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=timeout, check=False)
    except subprocess.TimeoutExpired as exc:
        partial = exc.stdout or b""
        log.write_text(partial.decode(errors="replace") if isinstance(partial, bytes) else partial)
        raise RuntimeError("Terminal gate timed out; see " + str(log)) from exc
    log.write_text(result.stdout, encoding="utf-8")
    print(result.stdout, flush=True)
    return result


def immutable_baseline(directory: Path) -> Path:
    """Materialize the whole pinned game, never mix old UI with current inputs."""
    archive = directory / "baseline.tar"
    with archive.open("wb") as output:
        subprocess.run(["git", "archive", "--format=tar", BASELINE, "game"],
                       cwd=ROOT, stdout=output, check=True, timeout=60)
    destination = directory / "baseline-source"
    with tarfile.open(archive, "r:") as source:
        for member in source:
            relative = PurePosixPath(member.name)
            if (relative.is_absolute() or not relative.parts or relative.parts[0] != "game"
                    or ".." in relative.parts or not (member.isdir() or member.isfile())):
                raise RuntimeError("Unsafe path or link in baseline game archive")
            target = destination.joinpath(*relative.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                data = source.extractfile(member)
                if data is None:
                    raise RuntimeError("Missing baseline file data")
                with data, target.open("wb") as output:
                    shutil.copyfileobj(data, output)
    archive.unlink()
    return destination / "game"


def self_test() -> None:
    """These are runner fixtures, never claimed as game or graphics tests."""
    valid = "TERMINAL_TRANSITION_RESULT checks=150 failures=0\n"
    cases = [(0, valid, True), (1, valid, False), (0, "", False),
             (0, valid.replace("150", "0"), False), (0, valid.replace("150", "10"), False),
             (0, valid.replace("failures=0", "failures=1"), False),
             (0, "  \x1b[31mSCRIPT ERROR:\x1b[0m fixture\n" + valid, False),
             (0, "ERROR: fixture\n" + valid, False), (0, "WARNING: new warning\n" + valid, False),
             (0, NUL_WARNING + "\n" + valid, False), (0, VSYNC + "\n" + valid, True),
             (0, valid + valid, False)]
    for code, output, expected in cases:
        fixture = subprocess.run([sys.executable, "-c", f"import sys; print({output!r}, end=''); sys.exit({code})"],
                                 capture_output=True, text=True, timeout=5, check=False)
        if validates_gameplay(fixture.returncode, fixture.stdout) != expected:
            raise AssertionError("Terminal runner accepted an invalid subprocess fixture")
    print(f"TERMINAL_RUNNER_SELF_TEST_OK {len(cases)} subprocess fixtures")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--verify-baseline", action="store_true")
    parser.add_argument("--output", type=Path, default=ROOT / "build/terminal-transition")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        return 0
    godot = Path(os.environ.get("GODOT", str(ROOT / ".toolchain/godot"))).resolve()
    if not godot.is_file():
        raise RuntimeError("Run tools/bootstrap.py first or provide GODOT")
    if not os.environ.get("DISPLAY"):
        raise RuntimeError("A graphical display is required; use xvfb-run -a")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lagunak-terminal-") as scratch:
        directory = Path(scratch)
        import_result = run([str(godot), "--headless", "--editor", "--path", str(ROOT / "game"), "--quit"],
                            isolated_env(directory / "import"), output / "import.log", timeout=120)
        if import_result.returncode or diagnostics(import_result.stdout, import_source=ROOT / "game/core/cosmography_catalog.gd"):
            raise RuntimeError("Resource import failed")
        script = str(ROOT / "tests/test_terminal_transition.gd")
        def command(project: Path, extra: list[str]) -> list[str]:
            return [str(godot), "--path", str(project), "--resolution", "1600x900",
                    "--audio-driver", "Dummy", "--script", script, "--", "--test", *extra]
        evidence: dict[str, object] = {"scope": "real application scene via Godot source runner; not a release binary",
                                       "godot_sha256": hashlib.sha256(godot.read_bytes()).hexdigest(),
                                       "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()}
        if args.verify_baseline:
            original = subprocess.check_output(["git", "show", BASELINE + ":game/ui/app.gd"], cwd=ROOT)
            blob = hashlib.sha1(b"blob " + str(len(original)).encode() + b"\0" + original).hexdigest()
            if blob != BASELINE_APP_BLOB:
                raise RuntimeError("Unexpected baseline application source")
            baseline_game = immutable_baseline(directory)
            if (baseline_game / "ui/app.gd").read_bytes() != original:
                raise RuntimeError("Baseline archive differs from the audited application")
            baseline_import = run([str(godot), "--headless", "--editor", "--path", str(baseline_game), "--quit"],
                                  isolated_env(directory / "baseline-import"), output / "baseline-import.log", timeout=120)
            if baseline_import.returncode or diagnostics(baseline_import.stdout, import_source=baseline_game / "core/cosmography_catalog.gd"):
                raise RuntimeError("Pinned baseline resource import failed")
            baseline = run(command(baseline_game, ["--probe-only"]), isolated_env(directory / "baseline-user"),
                           output / "baseline.log")
            text = ANSI.sub("", baseline.stdout)
            match = RESULT.findall(text)
            expected = (baseline.returncode == 1 and len(match) == 1 and int(match[0][1]) > 0
                        and "TERMINAL_FAIL source survives input" in text
                        and "set_input_as_handled" in text and "Parse Error" not in text)
            if not expected:
                raise RuntimeError("Baseline did not reproduce the specific terminal lifetime failure")
            evidence["baseline"] = {"commit": BASELINE, "app_blob": blob, "game_snapshot": "entire pinned game directory", "specific_failure_reproduced": True}
            print("TERMINAL_BASELINE_REPRODUCED synchronous receiver detaches the input source", flush=True)
        current = run(command(ROOT / "game", ["--evidence-dir", str(output)]),
                      isolated_env(directory / "fixed-user"), output / "fixed.log")
        if not validates_gameplay(current.returncode, current.stdout):
            raise RuntimeError("Terminal gameplay regression failed; see fixed.log")
        evidence["result"] = RESULT.findall(ANSI.sub("", current.stdout))[0]
        evidence["app_sha256"] = hashlib.sha256((ROOT / "game/ui/app.gd").read_bytes()).hexdigest()
        for name in ("terminal-navigation.png", "terminal-return.png"):
            image = output / name
            if not image.is_file() or image.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
                raise RuntimeError("Missing rendered evidence: " + name)
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        print("TERMINAL_GATE_OK", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print("TERMINAL_GATE_FAILED: " + str(exc), file=sys.stderr)
        raise SystemExit(1) from exc
