#!/usr/bin/env python3
"""Run the real Godot structural-comparison suite with isolated user data."""
from __future__ import annotations

import argparse
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MARKER = re.compile(r"^SHIP_CONFIGURATION_DIFF_TESTS (\d+) checks; (\d+) failures$", re.MULTILINE)
ERROR = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR|USER ERROR):", re.MULTILINE)
MAX_OUTPUT = 2_000_000


class VerificationError(RuntimeError):
    """A missing tool, incomplete run, or failed verification."""


def validate_result(result: subprocess.CompletedProcess[str]) -> str:
    output = result.stdout or ""
    if len(output.encode("utf-8")) > MAX_OUTPUT:
        raise VerificationError("La salida de Godot supera el límite de 2 MB.")
    if result.returncode != 0 or ERROR.search(output):
        raise VerificationError(f"Godot no superó la verificación (salida {result.returncode}).\n{output}")
    markers = MARKER.findall(output)
    if len(markers) != 1 or int(markers[0][0]) < 1 or int(markers[0][1]) != 0:
        raise VerificationError("Falta un único resultado completo sin fallos.\n" + output)
    return output


def run_suite(godot: Path, *, root: Path = ROOT, headless: bool = False, timeout: float = 120) -> str:
    if not math.isfinite(timeout) or not 1 <= timeout <= 300:
        raise VerificationError("El límite de ejecución debe estar entre 1 y 300 segundos.")
    root = root.resolve()
    godot = godot.expanduser().resolve()
    script = root / "tests" / "test_ship_configuration_diff.gd"
    if not godot.is_file() or not os.access(godot, os.X_OK):
        raise VerificationError("No hay un ejecutable Godot disponible en la ruta indicada.")
    if not (root / "game" / "project.godot").is_file() or not script.is_file():
        raise VerificationError("Falta el proyecto o la suite de comparación estructural.")
    command = [str(godot)]
    if headless:
        command.append("--headless")
    command += ["--audio-driver", "Dummy", "--path", str(root / "game"), "--script", str(script), "--", "--test"]
    with tempfile.TemporaryDirectory(prefix="lagunak-ship-diff-") as temporary:
        env = os.environ.copy()
        for variable, folder in (("HOME", "home"), ("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache"), ("APPDATA", "appdata"), ("LOCALAPPDATA", "localappdata")):
            directory = Path(temporary) / folder
            directory.mkdir()
            env[variable] = str(directory)
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"
        try:
            result = subprocess.run(command, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, encoding="utf-8", errors="replace", timeout=timeout, check=False)
        except subprocess.TimeoutExpired as error:
            raise VerificationError("Godot agotó el límite; la suite no se considera aprobada.") from error
        except OSError as error:
            raise VerificationError("No se pudo ejecutar Godot.") from error
        return validate_result(result)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("GODOT", ROOT / ".toolchain" / "godot")))
    parser.add_argument("--headless", action="store_true", help="Sin ventana; para validación gráfica, usar xvfb-run sin esta opción.")
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args(argv)
    try:
        print(run_suite(args.godot, headless=args.headless, timeout=args.timeout), end="")
    except VerificationError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
