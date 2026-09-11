#!/usr/bin/env python3
"""Validate and render the parity register locally; never run commands or use network.

Exit 0: structurally valid register (NOT product parity).
Exit 1: invalid register/files. Exit 2: --require-complete is not satisfied.
Evidence records are reviewable attestations, not independently verified CI results.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import urlparse

REPO = "EspacioKoop/espaciokooplagunakRemake"
ORIGINAL = "EspacioKoop/espaciokooplagunak"
GATES = {"G0": "Integridad de plataforma", "G1": "Paridad de modelo",
         "G2": "Paridad jugable", "G3": "Paridad de producto"}
STATUSES = {"pending": "Pendiente", "partial": "Parcial", "verified": "Evidencia registrada",
            "waived": "Renuncia aprobada"}
DECISIONS = {"reimplement", "replace", "review", "waive"}
SHA = re.compile(r"[0-9a-f]{40}\Z")
ID = re.compile(r"[a-z0-9][a-z0-9_.:-]{0,159}\Z")
MAX_BYTES = 2_000_000


def choice(value: Any, allowed: Any) -> bool:
    return isinstance(value, str) and value in allowed


class Invalid(ValueError):
    """Malformed or unverifiable register."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise Invalid(message)


def text(value: Any, where: str) -> str:
    require(isinstance(value, str) and bool(value.strip()), f"{where}: texto vacío o inválido")
    require(len(value) <= 8000 and not any(ord(c) < 32 for c in value),
            f"{where}: texto demasiado largo o con caracteres de control")
    return value


def integer(value: Any, where: str) -> int:
    require(type(value) is int and value > 0, f"{where}: entero positivo requerido")
    return value


def relative(value: Any, where: str) -> str:
    value = text(value, where)
    p = PurePosixPath(value)
    require(not p.is_absolute() and str(p) == value and ".." not in p.parts
            and "\\" not in value and ":" not in value and "#" not in value
            and "?" not in value and re.fullmatch(r"[A-Za-z0-9_./-]+", value) is not None, f"{where}: ruta relativa no segura")
    return value


def local_file(root: Path, value: Any, where: str) -> Path:
    rel = relative(value, where)
    root = root.resolve()
    target = root / rel
    require(target.resolve().is_relative_to(root), f"{where}: enlace fuera del repositorio")
    require(target.is_file(), f"{where}: no existe el archivo {rel}")
    return target


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, f"JSON: clave duplicada {key}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    try:
        with path.open("rb") as stream:
            raw = stream.read(MAX_BYTES + 1)
        require(len(raw) <= MAX_BYTES, f"{path.name}: supera {MAX_BYTES} bytes")
        return json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object,
                          parse_constant=lambda value: (_ for _ in ()).throw(Invalid(f"JSON: {value} no finito")))
    except (OSError, UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise Invalid(f"{path.name}: no se puede leer JSON válido ({type(exc).__name__})") from exc


def github_url(value: Any, where: str, kind: str) -> str:
    value = text(value, where)
    url = urlparse(value)
    require(url.scheme == "https" and url.netloc == "github.com" and not url.query,
            f"{where}: enlace GitHub HTTPS sin credenciales ni query requerido")
    prefix = "/" + REPO + "/"
    require(url.path.startswith(prefix), f"{where}: repositorio incorrecto")
    suffix = url.path[len(prefix):]
    pattern = r"actions/runs/[1-9][0-9]*(?:/job/[1-9][0-9]*)?" if kind == "run" else r"(?:issues|pull)/[1-9][0-9]*"
    require(re.fullmatch(pattern, suffix) is not None, f"{where}: enlace de {kind} inválido")
    require(not url.fragment or re.fullmatch(r"(?:issuecomment-|discussion_r|pullrequestreview-|step:)[0-9]+(?:[:][0-9]+)?", url.fragment) is not None,
            f"{where}: fragmento no seguro")
    return value


def validate_evidence(evidence: Any, root: Path, where: str) -> list[dict[str, Any]]:
    require(isinstance(evidence, list), f"{where}: debe ser lista")
    for index, entry in enumerate(evidence):
        at = f"{where}[{index}]"
        require(isinstance(entry, dict), f"{at}: debe ser objeto")
        kind = entry.get("kind")
        if choice(kind, {"implementation", "test", "document"}):
            local_file(root, entry.get("path"), at)
            if kind == "test":
                require(entry["path"].startswith("tests/"), f"{at}: prueba fuera de tests/")
        elif kind == "run":
            github_url(entry.get("url"), at, "run")
            require(isinstance(entry.get("revision"), str) and bool(SHA.fullmatch(entry["revision"])),
                    f"{at}: SHA inmutable requerido")
            require(choice(entry.get("result"), {"passed", "failed", "pending"}), f"{at}: resultado inválido")
            text(entry.get("checks"), at + ".checks")
        else:
            raise Invalid(f"{at}: tipo de evidencia desconocido")
    return evidence


def validate_item(item: Any, root: Path) -> None:
    require(isinstance(item, dict), "item: debe ser objeto")
    key = text(item.get("id"), "item.id")
    require(bool(ID.fullmatch(key)), f"{key}: identificador inválido")
    require(choice(item.get("gate"), GATES), f"{key}: gate desconocido")
    require(choice(item.get("priority"), {"P0", "P1", "P2"}), f"{key}: prioridad inválida")
    require(choice(item.get("scope"), {"parity", "proposal"}), f"{key}: alcance inválido")
    require(choice(item.get("status"), STATUSES), f"{key}: estado desconocido")
    require(choice(item.get("decision"), DECISIONS), f"{key}: decisión desconocida")
    for field in ("original", "equivalent", "acceptance", "note"):
        text(item.get(field), key + "." + field)
    source = item.get("source")
    if isinstance(source, str) and source.startswith("issue:"):
        require(re.fullmatch(r"issue:[1-9][0-9]*", source) is not None, f"{key}: issue fuente inválido")
    else:
        relative(source, key + ".source")
    if "source_line" in item:
        integer(item["source_line"], key + ".source_line")
    integer(item.get("owner_issue"), key + ".owner_issue")
    evidence = validate_evidence(item.get("evidence"), root, key + ".evidence")
    if item["status"] == "verified":
        require(item["decision"] in {"reimplement", "replace"}, f"{key}: decisión no resuelta")
        kinds = {e["kind"] for e in evidence}
        require({"implementation", "test", "run"} <= kinds, f"{key}: cierre sin implementación, prueba y ejecución")
        runs = [e for e in evidence if e["kind"] == "run"]
        require(all(e["result"] == "passed" for e in runs), f"{key}: ejecución pendiente o fallida")
        require(len({e["revision"] for e in runs}) == 1, f"{key}: ejecuciones de SHAs distintos")
    if item["status"] == "waived" or item["decision"] == "waive":
        require(item["status"] == "waived" and item["decision"] == "waive", f"{key}: renuncia incoherente")
        github_url(item.get("approval"), key + ".approval", "review")


def ship_items(root: Path, spec: dict[str, Any], revision: str) -> list[dict[str, Any]]:
    path = spec.get("path")
    require(path == "game/data/ship_templates.json", "catálogo de naves: ruta canónica requerida")
    raw = load_json(local_file(root, path, "catálogo de naves"))
    require(isinstance(raw, dict) and type(raw.get("format")) is int and raw["format"] == 1,
            "catálogo de naves: formato desconocido")
    require(raw.get("reference") == revision, "catálogo de naves: referencia original distinta")
    integer(spec.get("owner_issue"), "catálogo.owner_issue")
    rows: list[dict[str, Any]] = []
    declarations: set[tuple[str, int]] = set()
    ids: set[str] = set()
    for section in ("templates", "excluded"):
        require(isinstance(raw.get(section), list), f"catálogo.{section}: lista requerida")
        for ship in raw[section]:
            require(isinstance(ship, dict), "catálogo: entrada no es objeto")
            name = text(ship.get("name"), "nave.name")
            source = relative(ship.get("source" if section == "templates" else "file"), "nave.source")
            require("/" not in source and source.endswith(".lua"), "nave.source: fichero Lua simple requerido")
            line = integer(ship.get("line"), "nave.line")
            declaration = (source, line)
            require(declaration not in declarations, f"catálogo: declaración duplicada {source}:{line}")
            declarations.add(declaration)
            if section == "templates":
                ident = text(ship.get("id"), "nave.id")
                require(bool(ID.fullmatch(ident)) and ident not in ids, "catálogo: id inválido o duplicado")
                ids.add(ident)
                limitations = ship.get("unsupported")
                require(isinstance(limitations, list), "nave.unsupported: lista requerida")
                for limitation in limitations:
                    text(limitation, "nave.unsupported")
                key = "ship:" + ident
                equivalent = "Astillero: " + ident
                note = "Adaptación parcial; también faltan prestaciones comunes descritas en SHIP_TEMPLATES.md."
                if limitations:
                    note += " Métodos no representados: " + ", ".join(limitations) + "."
            else:
                reasons = ship.get("reasons")
                require(isinstance(reasons, list) and bool(reasons), "exclusión sin motivo")
                for reason in reasons:
                    text(reason, "nave.reasons")
                key = f"ship-excluded:{source.lower()}:{line}"
                equivalent = "No ofrecida por el selector actual"
                note = "Exclusión técnica, NO renuncia de producto: " + "; ".join(reasons) + "."
            rows.append({"id": key, "gate": "G1", "priority": "P0", "scope": "parity",
                         "original": name, "source": "scripts/shiptemplates/" + source,
                         "source_line": line, "equivalent": equivalent,
                         "status": "partial" if section == "templates" else "pending",
                         "decision": "reimplement", "owner_issue": spec["owner_issue"],
                         "acceptance": "Auditar prestaciones efectivas de esta declaración y herencia; implementar sus diferencias y probar selección, combate y guardado, o registrar una decisión aprobada.",
                         "note": note,
                         "evidence": [{"kind": "document", "path": "docs/SHIP_TEMPLATES.md"},
                                      {"kind": "implementation", "path": path},
                                      {"kind": "test", "path": "tests/test_ship_templates.gd"}]})
    require(bool(rows), "catálogo de naves vacío")
    return rows


def collect(data: Any, root: Path) -> list[dict[str, Any]]:
    require(isinstance(data, dict), "registro: objeto requerido")
    require(type(data.get("version")) is int and data["version"] == 1, "registro: versión no soportada")
    require(data.get("source_repository") == ORIGINAL, "registro: repositorio de referencia incorrecto")
    for field in ("source_revision", "remake_revision"):
        require(isinstance(data.get(field), str) and bool(SHA.fullmatch(data[field])), f"registro.{field}: SHA requerido")
    coverage = data.get("coverage")
    require(isinstance(coverage, dict) and type(coverage.get("complete")) is bool, "coverage.complete: booleano requerido")
    text(coverage.get("note"), "coverage.note")
    if coverage["complete"]:
        github_url(coverage.get("review"), "coverage.review", "review")
    require(isinstance(data.get("items"), list) and bool(data["items"]), "registro.items: lista no vacía requerida")
    require(isinstance(data.get("catalogs"), list), "registro.catalogs: lista requerida")
    rows = list(data["items"])
    require(len(data["catalogs"]) <= 1, "catálogo de naves duplicado")
    generated: dict[str, dict[str, Any]] = {}
    for spec in data["catalogs"]:
        require(isinstance(spec, dict) and spec.get("type") == "ship_templates", "adaptador de catálogo desconocido")
        for row in ship_items(root, spec, data["source_revision"]):
            generated[row["id"]] = row
    overrides = data.get("overrides", {})
    require(isinstance(overrides, dict), "overrides: objeto requerido")
    for key, changes in overrides.items():
        require(key in generated, f"override sin declaración: {key}")
        require(isinstance(changes, dict) and bool(changes), f"override vacío: {key}")
        require(set(changes) <= {"status", "decision", "acceptance", "note", "evidence", "approval"},
                f"override modifica identidad/alcance: {key}")
        generated[key] = {**generated[key], **changes}
    rows.extend(generated.values())
    seen: set[str] = set()
    for row in rows:
        validate_item(row, root)
        if row["status"] == "verified":
            require(all(e["revision"] == data["remake_revision"] for e in row["evidence"] if e["kind"] == "run"),
                    f"{row['id']}: ejecución no corresponde al remake auditado")
        require(row["id"] not in seen, f"id duplicado: {row['id']}")
        seen.add(row["id"])
    require({r["gate"] for r in rows if r["scope"] == "parity"} == set(GATES), "faltan gates de paridad G0–G3")
    return sorted(rows, key=lambda r: (r["gate"], r["priority"], r["id"]))


def blockers(data: dict[str, Any], rows: list[dict[str, Any]], candidate: str | None) -> list[str]:
    result = []
    if not data["coverage"]["complete"]:
        result.append("Inventario no exhaustivo: no certifica el catálogo completo del original.")
    if not candidate or not SHA.fullmatch(candidate):
        result.append("Falta --candidate con el SHA completo que se pretende validar.")
    if candidate and candidate != data["remake_revision"]:
        result.append("El candidato no coincide con el remake auditado.")
    for row in rows:
        if row["scope"] != "parity":
            continue
        if row["status"] not in {"verified", "waived"}:
            result.append(row["id"] + ": " + STATUSES[row["status"]])
        elif row["status"] == "verified" and any(e["revision"] != candidate for e in row["evidence"] if e["kind"] == "run"):
            result.append(row["id"] + ": evidencia de otro SHA")
    return result


def cell(value: str) -> str:
    # Raw HTML, Markdown links/images and table delimiters cannot be injected by a name.
    value = html.escape(value, quote=True)
    for char in ("\\", "`", "*", "_", "[", "]", "|", "~"):
        value = value.replace(char, f"&#{ord(char)};")
    return value


def markdown(data: dict[str, Any], rows: list[dict[str, Any]], candidate: str | None) -> str:
    pending = blockers(data, rows, candidate)
    lines = ["# Evidencias e inventario de paridad — #32", "",
             "Registro estructural; los enlaces a ejecuciones requieren revisión. No ejecuta el juego ni autoriza una release.", "",
             f"Original: `{data['source_revision']}`. Lectura del remake: `{data['remake_revision']}`.",
             "", "**Cobertura:** " + cell(data["coverage"]["note"]), "",
             "**Resultado de cierre:** " + ("BLOQUEADO" if pending else "EVIDENCIAS REGISTRADAS; REQUIERE REVISIÓN") + ".", "",
             "## Gates", "", "| Gate | Filas de paridad | Pendientes/parciales |", "|---|---:|---:|"]
    for gate, title in GATES.items():
        group = [r for r in rows if r["scope"] == "parity" and r["gate"] == gate]
        count = sum(r["status"] not in {"verified", "waived"} for r in group)
        lines.append(f"| {gate} — {title} | {len(group)} | {count} |")
    for scope, title in (("parity", "Original → remake"), ("proposal", "Propuestas separadas: no bloquean la paridad")):
        lines += ["", "## " + title, "", "| ID / gate | Original y fuente | Equivalente actual | Estado / decisión / responsable | Criterio de cierre y límites | Evidencias |", "|---|---|---|---|---|---|"]
        for r in rows:
            if r["scope"] != scope:
                continue
            if r["source"].startswith("issue:"):
                source = f"https://github.com/{REPO}/issues/{r['source'].split(':')[1]}"
            else:
                source = f"https://github.com/{ORIGINAL}/blob/{data['source_revision']}/{r['source']}"
                if r.get("source_line"):
                    source += "#L" + str(r["source_line"])
            evidence = []
            for e in r["evidence"]:
                if e["kind"] == "run":
                    evidence.append(f"[ejecución {cell(e['result'])}]({e['url']})")
                else:
                    link = f"https://github.com/{REPO}/blob/{data['remake_revision']}/{e['path']}"
                    evidence.append(f"[{cell(e['path'])}]({link})")
            if r.get("approval"):
                evidence.append(f"[aprobación]({r['approval']})")
            owner = f"[#{r['owner_issue']}](https://github.com/{REPO}/issues/{r['owner_issue']})"
            lines.append(f"| {cell(r['id'])} / {r['gate']} | [{cell(r['original'])}]({source}) | {cell(r['equivalent'])} | {STATUSES[r['status']]} / {r['decision']} / {owner} | {cell(r['acceptance'])} {cell(r['note'])} | {'; '.join(evidence) or 'Sin ejecución registrada'} |")
    lines += ["", "Las exclusiones técnicas de naves siguen pendientes; no son renuncias aprobadas. Las propuestas no amplían automáticamente #1.", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--inventory", default="docs/parity/issue32_inventory.json")
    parser.add_argument("--markdown", type=Path, help="Escribe informe local, sin publicar ni enviar datos")
    parser.add_argument("--require-complete", action="store_true")
    parser.add_argument("--candidate", help="SHA completo al evaluar cierre; no se deduce de main")
    args = parser.parse_args(argv)
    try:
        if args.candidate is not None:
            require(bool(SHA.fullmatch(args.candidate)), "--candidate: SHA completo requerido")
        data = load_json(local_file(args.root, args.inventory, "inventario"))
        rows = collect(data, args.root)
        if args.markdown:
            args.markdown.write_text(markdown(data, rows, args.candidate), encoding="utf-8")
        print(f"Registro válido: {len(rows)} filas; NO equivale a paridad funcional verificada.")
        missing = blockers(data, rows, args.candidate)
        if args.require_complete and missing:
            print("Cierre bloqueado:\n" + "\n".join(missing), file=sys.stderr)
            return 2
        return 0
    except (Invalid, OSError, RecursionError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
