#!/usr/bin/env python3
"""Run native comparison and existing loadout UI tests with disposable user data."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Mapping, Sequence

ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ERROR = re.compile(r"(?:SCRIPT ERROR|ERROR):")
MAX_LOG_BYTES = 2 * 1024 * 1024
SUITES = (
    ("test_loadout_comparison.gd", "LOADOUT_COMPARISON_TESTS"),
    ("test_loadout_editor.gd", "LOADOUT_EDITOR_TESTS"),
)


class VerificationError(RuntimeError):
    """An engine process did not provide a complete, error-free result."""


def check_output(returncode: int, output: str, marker: str | None) -> None:
    clean = ANSI.sub("", output)
    if returncode != 0:
        raise VerificationError(f"Godot terminó con código {returncode}.")
    if ERROR.search(clean):
        raise VerificationError("Godot produjo un ERROR o SCRIPT ERROR.")
    if marker is not None:
        pattern = rf"^{re.escape(marker)}\s+(\d+) checks;\s+(\d+) failures\s*$"
        summaries = re.findall(pattern, clean, flags=re.MULTILINE)
        if len(summaries) != 1:
            raise VerificationError(f"Falta un resumen único y completo: {marker}.")
        count, failures = map(int, summaries[0])
        if count < 1 or failures != 0:
            raise VerificationError(
                f"Resumen inválido: {count} comprobaciones, {failures} fallos."
            )


def isolated_environment(directory: Path, original: Mapping[str, str]) -> dict[str, str]:
    env = dict(original)
    folders = {
        "HOME": "home",
        "USERPROFILE": "home",
        "XDG_DATA_HOME": "data",
        "XDG_CONFIG_HOME": "config",
        "XDG_CACHE_HOME": "cache",
        "APPDATA": "appdata",
        "LOCALAPPDATA": "localappdata",
    }
    for name, suffix in folders.items():
        path = directory / suffix
        path.mkdir(parents=True, exist_ok=True)
        env[name] = str(path)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


def run_step(
    command: Sequence[str],
    env: Mapping[str, str],
    marker: str | None,
    timeout: float = 120,
) -> None:
    with tempfile.TemporaryFile() as log:
        try:
            result = subprocess.run(
                list(command), cwd=ROOT, env=dict(env), stdin=subprocess.DEVNULL,
                stdout=log, stderr=subprocess.STDOUT, timeout=timeout,
                check=False, shell=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise VerificationError("Godot superó el límite de tiempo; proceso terminado.") from exc
        except OSError as exc:
            raise VerificationError("No se pudo ejecutar Godot.") from exc
        length = log.tell()
        log.seek(0)
        output = log.read(MAX_LOG_BYTES).decode("utf-8", errors="replace")
    print(output, end="" if output.endswith("\n") else "\n")
    if length > MAX_LOG_BYTES:
        raise VerificationError("El registro supera el límite permitido.")
    check_output(result.returncode, output, marker)


def resolve_godot(value: str) -> str:
    candidate = Path(value).expanduser()
    if candidate.is_file():
        return str(candidate.resolve())
    found = shutil.which(value)
    if found is None:
        raise VerificationError(
            "Godot no está disponible. Ejecuta python3 tools/bootstrap.py o usa --godot."
        )
    return found


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(ROOT / ".toolchain" / "godot"))
    parser.add_argument(
        "--headless", action="store_true",
        help="Sin ventana; no sustituye la prueba gráfica.",
    )
    args = parser.parse_args(argv)
    try:
        engine = resolve_godot(args.godot)
        with tempfile.TemporaryDirectory(prefix="lagunak-loadout-comparison-") as directory:
            env = isolated_environment(Path(directory), os.environ)
            run_step(
                [engine, "--headless", "--editor", "--path", str(ROOT / "game"), "--quit"],
                env, None, 180,
            )
            for script, marker in SUITES:
                command = [engine, "--audio-driver", "Dummy", "--path", str(ROOT / "game")]
                if args.headless:
                    command.append("--headless")
                command += ["--script", str(ROOT / "tests" / script), "--", "--test"]
                run_step(command, env, marker)
    except VerificationError as exc:
        print(f"VERIFICATION FAILED: {exc}", file=sys.stderr)
        return 1
    print("LOADOUT_COMPARISON_RUNNER_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
