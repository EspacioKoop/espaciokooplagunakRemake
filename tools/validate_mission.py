#!/usr/bin/env python3
"""Validate native mission JSON locally, using Godot's Catalog as authority.

Python checks transport safety, not game rules. No downloads, sockets, shell,
mission execution, or writes to the input files are performed by this tool.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
import math
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MAX_BYTES = 256 * 1024
MAX_DEPTH = 32
MAX_FILES = 32
FORMAT = "lagunak-mission-validation"
ENGINE_ERROR = re.compile(r"(?m)^\s*(?:SCRIPT ERROR|ERROR|FATAL ERROR):")


class InvalidDocument(ValueError):
    """The supplied document cannot be transported safely as mission JSON."""


@dataclass(frozen=True)
class Result:
    path: str
    status: str
    message: str


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidDocument("El JSON contiene claves duplicadas.")
        result[key] = value
    return result


def _constant(_: str) -> None:
    raise InvalidDocument("El JSON contiene un número no finito.")


def read_document(path: Path) -> Any:
    # O_NONBLOCK + fstat also prevent accidentally waiting on a FIFO/device.
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0))
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise OSError("Se requiere un archivo regular.")
        raw = stream.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise InvalidDocument("La misión supera los 256 KiB del editor.")
    try:
        document = json.loads(raw.decode("utf-8"), object_pairs_hook=_pairs,
                              parse_constant=_constant)
    except InvalidDocument:
        raise
    except UnicodeError as error:
        raise InvalidDocument("La misión debe estar codificada en UTF-8 sin BOM.") from error
    except json.JSONDecodeError as error:
        raise InvalidDocument(f"JSON inválido en línea {error.lineno}, columna {error.colno}.") from error
    except (RecursionError, ValueError, OverflowError) as error:
        raise InvalidDocument("JSON demasiado complejo o número fuera de rango.") from error
    pending = [(document, 0)]
    while pending:
        value, depth = pending.pop()
        if depth > MAX_DEPTH:
            raise InvalidDocument("El JSON supera los 32 niveles de anidación.")
        if isinstance(value, float) and not math.isfinite(value):
            raise InvalidDocument("El JSON contiene un número no finito.")
        if isinstance(value, int) and not isinstance(value, bool) and abs(value) > 2**53 - 1:
            raise InvalidDocument("Un entero supera el rango exacto de JSON en Godot.")
        if isinstance(value, str):
            try:
                value.encode("utf-8")
            except UnicodeError as error:
                raise InvalidDocument("El JSON contiene Unicode incompleto.") from error
        elif isinstance(value, dict):
            pending.extend((item, depth + 1) for item in value.values())
            pending.extend((key, depth + 1) for key in value)
        elif isinstance(value, list):
            pending.extend((item, depth + 1) for item in value)
    return document


def isolated_environment(directory: Path) -> dict[str, str]:
    env = os.environ.copy()
    # Godot autoloads must never read/write the player's real user:// directory.
    for variable in ("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA",
                     "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        location = directory / variable.lower()
        location.mkdir()
        env[variable] = str(location)
    env["GODOT_SILENCE_ROOT_WARNING"] = "1"
    return env


def validate_one(path: Path, godot: str, timeout: float = 30,
                 root: Path = ROOT) -> Result:
    label = str(path)
    try:
        document = read_document(path)
    except InvalidDocument as error:
        return Result(label, "invalid", str(error))
    except OSError:
        return Result(label, "error", "No se pudo leer un archivo regular de entrada.")
    executable = shutil.which(godot)
    if executable is None:
        return Result(label, "error", "Godot no está disponible; indica --godot o prepara .toolchain/godot.")
    if not (root / "game/project.godot").is_file():
        return Result(label, "error", "No se encuentra game/project.godot junto a la herramienta.")
    try:
        with tempfile.TemporaryDirectory(prefix="lagunak-mission-") as name:
            temporary = Path(name)
            source, report = temporary / "mission.json", temporary / "report.json"
            source.write_text(json.dumps(document, ensure_ascii=False, allow_nan=False, separators=(",", ":")), encoding="utf-8")
            command = [str(Path(executable).resolve()), "--headless", "--path", str(root / "game"),
                       "--log-file", str(temporary / "godot.log"),
                       "--script", str(root / "tools/mission_validator.gd"),
                       "--", "--test", str(source), str(report)]
            process = subprocess.run(command, cwd=root, env=isolated_environment(temporary),
                                     capture_output=True, text=True, encoding="utf-8",
                                     errors="replace", timeout=timeout, check=False)
            if ENGINE_ERROR.search(process.stdout + "\n" + process.stderr):
                return Result(label, "error", "Godot notificó un error; revisa la importación y los scripts del proyecto.")
            if not report.is_file() or report.stat().st_size > 8192:
                return Result(label, "error", "Godot no produjo un informe válido; importa primero el proyecto.")
            payload = json.loads(report.read_text(encoding="utf-8"))
            if (not isinstance(payload, dict) or payload.get("format") != FORMAT
                    or type(payload.get("version")) is not int or payload["version"] != 1
                    or type(payload.get("valid")) is not bool
                    or not isinstance(payload.get("error"), str)):
                return Result(label, "error", "Informe de Godot incompatible.")
            valid, error = payload["valid"], payload["error"]
            if process.returncode != (0 if valid else 1) or valid != (error == ""):
                return Result(label, "error", "El resultado y el código de salida de Godot no coinciden.")
            return Result(label, "valid" if valid else "invalid", error)
    except subprocess.TimeoutExpired:
        return Result(label, "error", "Godot superó el tiempo límite; no se da la misión por válida.")
    except (OSError, ValueError, RecursionError):
        return Result(label, "error", "No se pudo ejecutar Godot o leer su informe.")


def _timeout(value: str) -> float:
    try:
        seconds = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("El tiempo debe ser un número entre 1 y 300 segundos.") from error
    if not math.isfinite(seconds) or not 1 <= seconds <= 300:
        raise argparse.ArgumentTypeError("El tiempo debe estar entre 1 y 300 segundos.")
    return seconds


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("missions", nargs="+", type=Path, help="Archivos JSON de misión, no campañas ni guardados.")
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(ROOT / ".toolchain/godot")),
                        help="Ejecutable local de Godot (también acepta la variable GODOT).")
    parser.add_argument("--timeout", type=_timeout, default=30, help="Límite por archivo, entre 1 y 300 segundos.")
    parser.add_argument("--json", action="store_true", help="Informe JSON; no incluye el contenido de las misiones.")
    args = parser.parse_args(argv)
    if len(args.missions) > MAX_FILES:
        parser.error(f"Se permiten como máximo {MAX_FILES} archivos por llamada.")
    results = [validate_one(path, args.godot, args.timeout) for path in args.missions]
    if args.json:
        print(json.dumps({"format": FORMAT, "version": 1, "results": [asdict(item) for item in results]},
                         ensure_ascii=True))
    else:
        for item in results:
            # Escape control characters from untrusted filenames/messages in terminals.
            suffix = ": " + json.dumps(item.message, ensure_ascii=True) if item.message else ""
            print(f"{item.status.upper()} {json.dumps(item.path, ensure_ascii=True)}{suffix}")
    return 2 if any(item.status == "error" for item in results) else int(any(item.status == "invalid" for item in results))


if __name__ == "__main__":
    raise SystemExit(main())
