#!/usr/bin/env python3
"""Validate the bounded original-to-remake scenario inventory offline.

Exit 0 means the inventory is structurally complete for its declared 38-source-file
scope and matches the local campaign IDs. It does not claim gameplay parity.
Exit 1 means the corpus or local catalog is invalid; exit 2 means --require-complete
was requested even though this deliberately bounded corpus is not exhaustive.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

SOURCE_REVISION = "fecd0740545f485d2402c6dfe4b47d5a859cb96c"
REMAKE_SNAPSHOT = "8b1dcf27683a00972b03d5203606eab12f31fe2d"
CORPUS = "docs/parity/scenario_corpus.json"
CAMPAIGN = "game/data/campaign.json"
SHA1 = re.compile(r"[0-9a-f]{40}\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")
SCENARIO_PATH = re.compile(r"scripts/scenario_[0-9]+_[A-Za-z0-9_-]+\.lua\Z")
EXPECTED_IDS = {
    "scenario:" + number
    for number in (
        "00", "02", "03", "05", "06", "07", "08", "10", "20", "27", "29", "30",
        "31", "32", "33", "34", "39", "44", "47", "48", "49", "50", "51", "53",
        "54", "55", "56", "57", "58", "59", "60", "62", "74", "79", "81", "88",
        "90", "99",
    )
}
EXPECTED_MISSIONS = ["itsasoratu", "oihartzuna", "aterpe", "zaindari", "berpiztu", "elkarlana"]
STATUSES = {"unmapped_in_current_catalog", "candidate_only"}


class Invalid(ValueError):
    """Raised for malformed or contradictory corpus data."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise Invalid(message)


def nonempty_string(value: Any, where: str) -> str:
    require(isinstance(value, str) and bool(value.strip()), f"{where}: texto requerido")
    require(not any(ord(char) < 32 for char in value), f"{where}: carácter de control")
    return value


def load_json(path: Path) -> Any:
    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            require(key not in result, f"{path}: clave JSON duplicada {key}")
            result[key] = value
        return result

    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object,
                          parse_constant=lambda value: (_ for _ in ()).throw(Invalid(f"JSON no finito: {value}")))
    except (OSError, UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise Invalid(f"{path}: JSON inválido ({type(exc).__name__})") from exc


def validate(root: Path) -> tuple[int, int]:
    corpus = load_json(root / CORPUS)
    require(isinstance(corpus, dict) and corpus.get("schema_version") == 1, "corpus: schema_version 1 requerido")
    source = corpus.get("source")
    require(isinstance(source, dict), "corpus.source: objeto requerido")
    assert isinstance(source, dict)
    require(source.get("repository") == "EspacioKoop/espaciokooplagunak", "corpus.source: repositorio incorrecto")
    require(source.get("revision") == SOURCE_REVISION and SHA.fullmatch(source["revision"]), "corpus.source.revision: SHA incorrecto")
    require(source.get("tree_scope") == "scripts/scenario_*.lua", "corpus.source.tree_scope: alcance incorrecto")

    snapshot = corpus.get("remake_snapshot")
    require(isinstance(snapshot, dict), "corpus.remake_snapshot: objeto requerido")
    assert isinstance(snapshot, dict)
    require(snapshot.get("repository") == "EspacioKoop/espaciokooplagunakRemake", "corpus.remake_snapshot: repositorio incorrecto")
    require(snapshot.get("revision") == REMAKE_SNAPSHOT and SHA.fullmatch(snapshot["revision"]), "corpus.remake_snapshot.revision: SHA incorrecto")
    require(snapshot.get("path") == CAMPAIGN, "corpus.remake_snapshot.path: ruta incorrecta")
    mission_ids = snapshot.get("mission_ids")
    require(isinstance(mission_ids, list) and mission_ids == EXPECTED_MISSIONS, "corpus.remake_snapshot.mission_ids: catálogo esperado distinto")
    require(len(set(mission_ids)) == len(mission_ids), "corpus.remake_snapshot.mission_ids: IDs duplicados")

    coverage = corpus.get("coverage")
    require(isinstance(coverage, dict) and coverage.get("complete") is False, "coverage.complete debe conservar false")
    assert isinstance(coverage, dict)
    require(coverage.get("recorded_records") == len(EXPECTED_IDS), "coverage.recorded_records: conteo incorrecto")
    require(coverage.get("original_scenario_count") == len(EXPECTED_IDS), "coverage.original_scenario_count: conteo incorrecto")
    require(coverage.get("remake_catalog_count") == len(EXPECTED_MISSIONS), "coverage.remake_catalog_count: conteo incorrecto")

    policy = corpus.get("mapping_policy")
    require(isinstance(policy, dict) and policy.get("parity_claim") is False, "mapping_policy.parity_claim debe ser false")
    assert isinstance(policy, dict)
    require(policy.get("human_review_required") is True, "mapping_policy.human_review_required debe ser true")

    records = corpus.get("records")
    require(isinstance(records, list) and len(records) == len(EXPECTED_IDS), "records: el corpus no cubre exactamente las 38 entradas declaradas")
    assert isinstance(records, list)
    seen: set[str] = set()
    for index, record in enumerate(records):
        where = f"records[{index}]"
        require(isinstance(record, dict), f"{where}: objeto requerido")
        identifier = nonempty_string(record.get("id"), where + ".id")
        require(identifier in EXPECTED_IDS, f"{where}.id: escenario fuera del alcance declarado ({identifier})")
        require(identifier not in seen, f"{where}.id: duplicado ({identifier})")
        seen.add(identifier)
        original = record.get("original")
        require(isinstance(original, dict), f"{where}.original: objeto requerido")
        assert isinstance(original, dict)
        number = original.get("number")
        require(type(number) is int and number >= 0, f"{where}.original.number: entero requerido")
        require(identifier == f"scenario:{number:02d}", f"{where}: id y número no coinciden")
        nonempty_string(original.get("name"), where + ".original.name")
        declared_type = original.get("declared_type")
        require(declared_type is None or isinstance(declared_type, str), f"{where}.original.declared_type: string o null requerido")
        path = nonempty_string(original.get("path"), where + ".original.path")
        require(bool(SCENARIO_PATH.fullmatch(path)), f"{where}.original.path: ruta de escenario insegura o inesperada")
        require(path.removeprefix("scripts/scenario_").split("_", 1)[0] == f"{number:02d}", f"{where}: ruta y número no coinciden")
        blob = nonempty_string(original.get("blob_sha1"), where + ".original.blob_sha1")
        require(SHA1.fullmatch(blob), f"{where}.original.blob_sha1: SHA-1 inválido")

        remake = record.get("remake")
        require(isinstance(remake, dict), f"{where}.remake: objeto requerido")
        assert isinstance(remake, dict)
        require(remake.get("status") in STATUSES, f"{where}.remake.status: estado no permitido")
        require(remake.get("evidence_path") == CAMPAIGN, f"{where}.remake.evidence_path: ruta incorrecta")
        mapped = remake.get("mission_ids")
        require(isinstance(mapped, list) and all(isinstance(value, str) for value in mapped), f"{where}.remake.mission_ids: lista de IDs requerida")
        require(set(mapped) <= set(EXPECTED_MISSIONS), f"{where}.remake.mission_ids: ID inexistente")
        require(record.get("decision") == "human_review", f"{where}.decision: solo se permite human_review en este inventario")
        nonempty_string(record.get("note"), where + ".note")
    require(seen == EXPECTED_IDS, "records: falta o sobra una entrada del conjunto esperado")

    campaign = load_json(root / CAMPAIGN)
    require(isinstance(campaign, dict) and isinstance(campaign.get("missions"), list), "campaign: missions no es una lista")
    assert isinstance(campaign, dict)
    actual = [mission.get("id") for mission in campaign["missions"] if isinstance(mission, dict)]
    require(actual == EXPECTED_MISSIONS, "campaign: IDs locales no coinciden con el catálogo registrado")
    return len(records), len(actual)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args(argv)
    try:
        record_count, mission_count = validate(args.root)
        print(f"Corpus válido: {record_count} escenarios originales contrastados con {mission_count} misiones del catálogo local.")
        print("Cobertura global NO exhaustiva; no equivale a paridad jugable verificada.")
        if args.require_complete:
            print("ERROR: el corpus es deliberadamente acotado y coverage.complete=false", file=sys.stderr)
            return 2
        return 0
    except (Invalid, OSError, RecursionError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
