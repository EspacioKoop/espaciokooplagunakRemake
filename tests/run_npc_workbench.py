#!/usr/bin/env python3
"""Run real Godot NPC tests with isolated user data and bounded processes/logs."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time
from typing import Mapping, Sequence

ROOT = Path(__file__).resolve().parents[1]
MAX_LOG_BYTES = 2 * 1024 * 1024
ERROR_LINE = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR):", re.MULTILINE)


class VerificationError(RuntimeError):
    """A subprocess failed to provide valid test evidence."""


def isolated_environment(home: Path, source: Mapping[str, str] | None = None) -> dict[str, str]:
    source = os.environ if source is None else source
    allowed = ("PATH", "LANG", "LC_ALL", "DISPLAY", "XAUTHORITY", "LD_LIBRARY_PATH", "SystemRoot", "WINDIR")
    env = {key: source[key] for key in allowed if key in source}
    for key, suffix in {
        "HOME": "home", "USERPROFILE": "home", "XDG_DATA_HOME": "data",
        "XDG_CONFIG_HOME": "config", "XDG_CACHE_HOME": "cache",
        "APPDATA": "appdata", "LOCALAPPDATA": "localappdata",
        "TMPDIR": "tmp", "TEMP": "tmp", "TMP": "tmp",
    }.items():
        location = home / suffix
        location.mkdir(parents=True, exist_ok=True)
        env[key] = str(location)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


def _stop(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is None:
        try:
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
        except ProcessLookupError:
            pass
    process.wait()


def run_checked(command: Sequence[str], cwd: Path, env: Mapping[str, str], timeout: float,
                marker: str | None = None) -> str:
    if not 0 < timeout <= 600:
        raise ValueError("timeout must be within (0, 600] seconds")
    with tempfile.TemporaryFile() as output:
        try:
            process = subprocess.Popen(list(command), cwd=cwd, env=dict(env),
                                       stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=(os.name == "posix"))
        except OSError as exc:
            raise VerificationError(f"No se pudo ejecutar el proceso ({type(exc).__name__}).") from exc
        deadline = time.monotonic() + timeout
        problem = ""
        try:
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    problem = "El proceso superó el tiempo límite."
                    break
                if os.fstat(output.fileno()).st_size > MAX_LOG_BYTES:
                    problem = "El proceso superó el límite de salida."
                    break
                time.sleep(0.02)
        finally:
            _stop(process)
        output.seek(0)
        raw = output.read(MAX_LOG_BYTES + 1)
        if len(raw) > MAX_LOG_BYTES:
            problem = "El proceso superó el límite de salida."
        text = raw[:MAX_LOG_BYTES].decode("utf-8", errors="replace")
        if problem:
            raise VerificationError(problem)
        if process.returncode != 0:
            raise VerificationError(f"Salida no válida ({process.returncode}).\n{text[-12000:]}")
        if ERROR_LINE.search(text):
            raise VerificationError(f"Godot ha comunicado errores.\n{text[-12000:]}")
        if marker and not re.search(r"^" + re.escape(marker) + r" checks=[1-9][0-9]*\s*$", text, re.MULTILINE):
            raise VerificationError(f"Falta la evidencia final {marker}.\n{text[-12000:]}")
        return text


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / ".toolchain" / "godot")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--graphics", action="store_true", help="Run UI test on the current display (e.g. xvfb-run).")
    args = parser.parse_args(argv)
    if not 1 <= args.timeout <= 600:
        parser.error("--timeout debe estar entre 1 y 600")
    godot = args.godot.expanduser().resolve()
    if not godot.is_file():
        parser.error("No existe el ejecutable Godot. Ejecuta tools/bootstrap.py o indica --godot.")
    game = ROOT / "game"
    try:
        with tempfile.TemporaryDirectory(prefix="lagunak-npc-tests-") as directory:
            env = isolated_environment(Path(directory))
            common = [str(godot), "--audio-driver", "Dummy", "--path", str(game)]
            run_checked(common + ["--headless", "--editor", "--quit"], ROOT, env, args.timeout)
            for filename, marker, graphics in [
                ("test_npc_generator.gd", "NPC_GENERATOR_PASS", False),
                ("test_npc_workbench.gd", "NPC_WORKBENCH_PASS", args.graphics),
            ]:
                command = common + ([] if graphics else ["--headless"])
                command += ["--script", str(ROOT / "tests" / filename), "--", "--test"]
                text = run_checked(command, ROOT, env, args.timeout, marker)
                print(text, end="" if text.endswith("\n") else "\n")
    except VerificationError as exc:
        print(f"NPC_VERIFY_FAIL: {exc}")
        return 1
    print("NPC_VERIFY_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
