#!/usr/bin/env python3
"""Valida y sincroniza milestones: sin red en check, sin escrituras por defecto."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime
from typing import Any

MARKER = "<!-- normas-platino:milestone:v1 -->"
API_VERSION = "2026-03-10"
MAX_CONFIG = 1_048_576


class Error(RuntimeError):
    """Error esperado, apto para mostrar sin volcar respuestas ni credenciales."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise Error(message)


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, "JSON con claves duplicadas.")
        result[key] = value
    return result


def text(value: Any, limit: int, multiline: bool = False) -> bool:
    return (isinstance(value, str) and 0 < len(value.strip()) <= limit
            and value == value.strip()
            and all(ord(c) >= 32 or (multiline and c == "\n") for c in value)
            and "\x7f" not in value)


def validate(config: Any) -> dict[str, Any]:
    require(isinstance(config, dict), "La configuración debe ser un objeto JSON.")
    require(set(config) == {"schema_version", "repository", "milestones"},
            "Campos requeridos: schema_version, repository y milestones, sin extras.")
    require(type(config["schema_version"]) is int and config["schema_version"] == 1,
            "schema_version debe ser el entero 1.")
    repo = config["repository"]
    require(isinstance(repo, str) and re.fullmatch(
        r"[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", repo) is not None,
        "repository debe ser ORGANIZACION/REPOSITORIO de github.com.")
    require(isinstance(config["milestones"], list), "milestones debe ser una lista.")
    titles: set[str] = set()
    issues: set[int] = set()
    for item in config["milestones"]:
        require(isinstance(item, dict), "Cada milestone debe ser un objeto.")
        require({"title", "description", "issues"} <= set(item)
                <= {"title", "description", "issues", "due_on"},
                "Cada milestone requiere title, description e issues; due_on es opcional.")
        require(text(item["title"], 200), "Título vacío, demasiado largo o con controles.")
        key = item["title"].casefold()
        require(key not in titles, "Milestones duplicados, incluso cambiando mayúsculas.")
        titles.add(key)
        require(text(item["description"], 20_000, multiline=True)
                and MARKER not in item["description"], "Descripción no válida.")
        if "due_on" in item:
            date = item["due_on"]
            require(isinstance(date, str) and re.fullmatch(
                r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", date) is not None,
                "due_on debe ser una fecha UTC YYYY-MM-DDTHH:MM:SSZ; no null.")
            try:
                datetime.strptime(date, "%Y-%m-%dT%H:%M:%SZ")
            except ValueError:
                raise Error("due_on contiene una fecha inexistente.") from None
        require(isinstance(item["issues"], list), "issues debe ser una lista de enteros.")
        for number in item["issues"]:
            require(type(number) is int and number > 0, "Número de issue no válido.")
            require(number not in issues, "Un issue no puede repetirse ni ocupar dos milestones.")
            issues.add(number)
    return config


def load(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as stream:
            data = stream.read(MAX_CONFIG + 1)
        require(len(data) <= MAX_CONFIG, "Configuración demasiado grande.")
        return validate(json.loads(data, object_pairs_hook=unique_object))
    except (OSError, UnicodeError, ValueError, RecursionError):
        raise Error("No se pudo leer una configuración JSON UTF-8 válida.") from None


class GitHub:
    """Usa la autenticación existente de gh; no lee ni imprime el token."""

    def __init__(self, repository: str) -> None:
        self.prefix = f"repos/{repository}"
        self.writable = False

    def request(self, method: str, suffix: str = "", payload: Any = None) -> Any:
        require(method in {"GET", "POST", "PATCH"}, "Método no permitido.")
        require(method == "GET" or self.writable, "Escritura no autorizada.")
        # Ni URLs externas ni endpoints elegidos por el contenido remoto.
        require(re.fullmatch(r"(?:/milestones(?:/\d+)?(?:\?state=all&per_page=100&page=\d+)?|/issues/\d+)?",
                             suffix) is not None, "Endpoint fuera del alcance.")
        command = ["gh", "api", "--hostname", "github.com", "--method", method,
                   "-H", "Accept: application/vnd.github+json",
                   "-H", f"X-GitHub-Api-Version: {API_VERSION}", self.prefix + suffix]
        if payload is not None:
            command += ["--input", "-"]
        env = os.environ.copy()
        env.pop("GH_DEBUG", None)
        env["GH_PROMPT_DISABLED"] = "1"
        try:
            result = subprocess.run(command, input=None if payload is None else json.dumps(payload),
                                    capture_output=True, text=True, encoding="utf-8",
                                    timeout=60, check=False, env=env)
        except (OSError, subprocess.TimeoutExpired, UnicodeError):
            raise Error("No se pudo ejecutar gh: comprueba instalación, acceso y conexión.") from None
        require(result.returncode == 0,
                "GitHub rechazó la operación: comprueba acceso y límites; no se reintenta automáticamente.")
        try:
            return json.loads(result.stdout)
        except (ValueError, RecursionError):
            raise Error("GitHub devolvió una respuesta JSON no válida.") from None


def snapshot(api: GitHub, config: dict[str, Any]) -> dict[str, Any]:
    repo = api.request("GET")
    require(isinstance(repo, dict) and isinstance(repo.get("full_name"), str)
            and repo["full_name"].casefold() == config["repository"].casefold(),
            "El repositorio remoto no coincide; revisa también posibles traslados.")
    require(repo.get("archived") is False, "El repositorio está archivado o su estado es desconocido.")
    milestones: list[dict[str, Any]] = []
    page = 1
    seen: set[int] = set()
    while True:
        batch = api.request("GET", f"/milestones?state=all&per_page=100&page={page}")
        require(isinstance(batch, list) and all(isinstance(x, dict) for x in batch),
                "Listado de milestones incompleto o inválido.")
        for entry in batch:
            number = entry.get("number")
            require(type(number) is int and number > 0 and number not in seen
                    and text(entry.get("title"), 200)
                    and entry.get("state") in {"open", "closed"}
                    and isinstance(entry.get("description"), (str, type(None)))
                    and "due_on" in entry, "Milestone incompleto o paginación repetida.")
            seen.add(number)
            milestones.append({k: entry.get(k) for k in
                               ("number", "title", "description", "due_on", "state")})
        if len(batch) < 100:
            break
        page += 1
        require(page <= 1000, "Paginación excesiva; no se acepta un listado incompleto.")
    issues = {}
    for item in config["milestones"]:
        for number in item["issues"]:
            issue = api.request("GET", f"/issues/{number}")
            require(isinstance(issue, dict) and issue.get("number") == number
                    and "pull_request" not in issue, "Referencia inexistente, inválida o perteneciente a un PR.")
            require(issue.get("state") in {"open", "closed"} and "milestone" in issue,
                    "Estado de issue incompleto.")
            milestone = issue["milestone"]
            require(milestone is None or (isinstance(milestone, dict)
                    and type(milestone.get("number")) is int), "Milestone del issue no válido.")
            issues[str(number)] = {"state": issue["state"],
                                   "milestone": None if milestone is None else milestone["number"]}
    # No retenemos cuerpos de issues, comentarios, usuarios ni otras respuestas.
    return {"milestones": milestones, "issues": issues}


def plan(config: dict[str, Any], state: dict[str, Any]) -> dict[str, Any]:
    actions = []
    before = []
    for item in config["milestones"]:
        matches = [x for x in state["milestones"] if isinstance(x.get("title"), str)
                   and x["title"].casefold() == item["title"].casefold()]
        require(len(matches) <= 1, "Título remoto ambiguo: resuelve los milestones duplicados.")
        current = matches[0] if matches else None
        desired = {"description": item["description"] + "\n\n" + MARKER}
        if "due_on" in item:
            desired["due_on"] = item["due_on"]
        number = None
        if current is None:
            actions.append({"kind": "create", "title": item["title"],
                            "payload": {"title": item["title"], "state": "open", **desired}})
        else:
            number = current.get("number")
            require(type(number) is int and number > 0
                    and current.get("state") in {"open", "closed"}
                    and isinstance(current.get("description"), (str, type(None)))
                    and "due_on" in current, "Datos de milestone incompletos.")
            require(current["title"] == item["title"], "El título remoto difiere en mayúsculas; coordina el cambio.")
            before.append({k: current.get(k) for k in
                           ("number", "title", "description", "due_on", "state")})
            description = current.get("description") or ""
            changes = {k: v for k, v in desired.items() if current.get(k) != v}
            # Un milestone manual idéntico puede usarse, pero no se toma su propiedad.
            if description == item["description"]:
                changes.pop("description", None)
            if changes:
                require(description.endswith("\n\n" + MARKER),
                        "Conflicto con un milestone manual: no se sobreescribe ni adopta automáticamente.")
                require(current["state"] == "open", "No se modifica un milestone cerrado.")
                actions.append({"kind": "update", "title": item["title"],
                                "number": number, "payload": changes})
        for issue_number in item["issues"]:
            issue = state["issues"][str(issue_number)]
            if number is not None and issue["milestone"] == number:
                continue
            require(issue["state"] == "open", "No se asigna una versión nueva a un issue cerrado.")
            require(issue["milestone"] is None, "El issue ya tiene otro milestone: requiere decisión manual.")
            require(current is None or current["state"] == "open", "No se añaden issues a un milestone cerrado.")
            actions.append({"kind": "assign", "title": item["title"], "issue": issue_number})
    result = {"repository": config["repository"], "before": before,
              "issues": state["issues"], "actions": actions}
    digest = hashlib.sha256(json.dumps(result, sort_keys=True, ensure_ascii=True).encode()).hexdigest()
    return {**result, "approval": digest}


def sync(config: dict[str, Any], repository: str, apply: bool = False,
         approval: str | None = None, api: GitHub | None = None) -> dict[str, Any]:
    validate(config)
    require(repository.casefold() == config["repository"].casefold(),
            "--repo no coincide con repository; no se consulta ni modifica GitHub.")
    require((apply and approval is not None and re.fullmatch(r"[0-9a-f]{64}", approval) is not None)
            or (not apply and approval is None), "Aplicar requiere --apply y --approve con la huella de la vista previa.")
    api = api or GitHub(config["repository"])
    candidate = plan(config, snapshot(api, config))
    if not apply:
        return candidate
    require(approval == candidate["approval"], "El plan ha cambiado o no está aprobado. Genera y revisa otra vista previa.")
    # Relectura antes de la primera escritura. No es una transacción ni un cerrojo.
    fresh = snapshot(api, config)
    require(plan(config, fresh)["approval"] == approval, "El remoto cambió durante la comprobación; no se aplica el plan.")
    ids = {x["title"]: x["number"] for x in fresh["milestones"]}
    api.writable = True
    try:
        for action in candidate["actions"]:
            kind = action["kind"]
            if kind == "create":
                created = api.request("POST", "/milestones", action["payload"])
                require(isinstance(created, dict) and type(created.get("number")) is int
                        and created["number"] > 0, "No se pudo verificar el milestone creado.")
                ids[action["title"]] = created["number"]
            elif kind == "update":
                api.request("PATCH", f"/milestones/{action['number']}", action["payload"])
            else:
                api.request("PATCH", f"/issues/{action['issue']}", {"milestone": ids[action["title"]]})
        remaining = plan(config, snapshot(api, config))
        require(not remaining["actions"], "La verificación remota no coincide con el resultado esperado.")
    except Error as exc:
        raise Error(f"{exc} Puede haber cambios parciales: revisa el remoto y genera otro plan; no hay rollback automático.") from None
    finally:
        api.writable = False
    return {"repository": repository, "applied": len(candidate["actions"]), "verified": True}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("check", "sync"):
        command = commands.add_parser(name)
        command.add_argument("config", type=Path)
        if name == "sync":
            command.add_argument("--repo", required=True)
            command.add_argument("--apply", action="store_true")
            command.add_argument("--approve")
    args = parser.parse_args(argv)
    try:
        config = load(args.config)
        result = ({"valid": True, "repository": config["repository"], "network": False}
                  if args.command == "check" else
                  sync(config, args.repo, args.apply, args.approve))
        print(json.dumps(result, ensure_ascii=True, indent=2))
        return 0
    except Error as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
