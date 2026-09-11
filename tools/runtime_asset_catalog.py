#!/usr/bin/env python3
"""Build the executable's allowlisted model registry from committed pack manifests.

This is a runtime consumer, not the visual documentation index maintained in
docs/asset_library. It neither downloads data nor rewrites any model or manifest.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = "game/data/runtime_asset_library.json"
MANIFESTS = (
    ("base", "game/assets/models/manifest.json"),
    ("memory", "game/assets/models/memory_guardians.manifest.json"),
    ("orbita", "game/assets/models/orbita_pack/manifest.json"),
    ("orbita", "game/assets/models/orbita_pack/player_batch/manifest.json"),
    ("frontier", "game/assets/models/frontier_pack/manifest.json"),
    ("fieldkit", "game/assets/models/fieldkit_pack/manifest.json"),
)
# Rendering compatibility is deliberately narrower than the inspection catalogue.
CATEGORY_KINDS = {"ships": ["friendly", "hostile", "derelict"],
                  "worlds": ["planet"], "infrastructure": ["station"]}
BASE_KINDS = {"itsaso": ["friendly", "hostile", "derelict"],
              "transport": ["friendly", "hostile", "derelict"],
              "sentinel": ["hostile"], "station": ["station"], "planet": ["planet"],
              "asteroid": ["asteroid"], "beacon": ["beacon"],
              "anomaly": ["anomaly", "blackhole", "wormhole", "nebula"]}


def safe_file(root: Path, value: str, prefix: str, suffix: str) -> Path:
    if not isinstance(value, str) or not value.startswith(prefix) or not value.endswith(suffix):
        raise ValueError("Unexpected resource path")
    parts = PurePosixPath(value).parts
    if ".." in parts or "\\" in value or ":" in value or "//" in value:
        raise ValueError("Unsafe resource path")
    path = root / value
    if not path.resolve().is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f"Missing or escaping resource: {value}")
    return path


def text(value: object, limit: int) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise ValueError("Invalid catalogue text")
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError("Control characters in catalogue text")
    return value


def build_catalog(root: Path = ROOT) -> dict:
    rows, seen, inputs = [], set(), []
    for namespace, relative in MANIFESTS:
        path = safe_file(root, relative, "game/assets/models/", ".json")
        raw = path.read_bytes()
        doc = json.loads(raw)
        inputs.append({"manifest": relative, "sha256": hashlib.sha256(raw).hexdigest()})
        if namespace == "base":
            entries = []
            for row in doc["models"]:
                name = row["name"]
                source = "art/blender/leisure_assets.blend" if name == "leisure_bundle" else "art/blender/lagunak_assets.blend"
                category = ("ships" if name in ("itsaso", "transport", "sentinel") else
                            "worlds" if name == "planet" else
                            "environments" if name.endswith("_room") or name in ("hallway", "leisure_bundle") else "props")
                entries.append(dict(row, id="base/" + name, title=name.replace("_", " ").capitalize(),
                                    description="Recurso original de la aplicación.", source=source,
                                    resource="res://assets/models/" + row["file"],
                                    license="MIT", category=category,
                                    contact_kinds=BASE_KINDS.get(name, [])))
        elif namespace == "memory":
            entries = [dict(doc, id="memory/guardians", title="Guardianes · colección",
                            description="Conjunto de la galería de recuerdos.", category="avatars",
                            resource="res://assets/models/memory_guardians.glb")]
        else:
            if type(doc.get("version")) is not int or doc["version"] != 1 or not isinstance(doc.get("assets"), list):
                raise ValueError(f"Unsupported manifest schema: {relative}")
            entries = doc["assets"]
        for row in entries:
            identifier = row["id"]
            if "/" not in identifier:
                identifier = namespace + "/" + identifier
            if not re.fullmatch(r"[a-z0-9_]+/[a-zA-Z0-9_-]+", identifier) or not identifier.startswith(namespace + "/"):
                raise ValueError("Invalid or foreign model ID")
            if identifier in seen:
                raise ValueError("Duplicate model ID: " + identifier)
            resource = row.get("resource", row.get("glb"))
            if not isinstance(resource, str) or not resource.startswith("res://assets/models/"):
                raise ValueError("Only repository model resources are supported")
            runtime = safe_file(root, "game/" + resource[6:], "game/assets/models/", ".glb")
            digest = hashlib.sha256(runtime.read_bytes()).hexdigest()
            if not re.fullmatch(r"[a-f0-9]{64}", row.get("sha256", "")) or digest != row["sha256"]:
                raise ValueError("Model hash mismatch: " + identifier)
            source = text(row["source"], 256)
            source_file = safe_file(root, source, "art/blender/", ".blend")
            if row.get("source_sha256") and hashlib.sha256(source_file.read_bytes()).hexdigest() != row["source_sha256"]:
                raise ValueError("Blender source hash mismatch: " + identifier)
            category = text(row["category"], 40)
            kinds = row.get("contact_kinds", CATEGORY_KINDS.get(category, []))
            if identifier == "frontier/navigation_beacon":
                kinds = ["beacon"]
            result = {
                "id": identifier, "title": text(row["title"], 120),
                "category": category, "description": text(row.get("description", "Recurso de la biblioteca."), 500),
                "resource": resource, "source": source, "manifest": relative,
                "sha256": digest, "license": text(row.get("license", "MIT"), 80),
                "contact_kinds": kinds,
            }
            rows.append(result); seen.add(identifier)
    return {"format": "lagunak-runtime-assets", "version": 1, "sources": inputs,
            "assets": sorted(rows, key=lambda item: item["id"])}


def encoded(root: Path = ROOT) -> str:
    return json.dumps(build_catalog(root), ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        expected = encoded()
        target = ROOT / OUTPUT
        if args.check:
            if not target.is_file() or target.read_text(encoding="utf-8") != expected:
                raise ValueError("Runtime registry is stale; run tools/runtime_asset_catalog.py")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(expected, encoding="utf-8")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"RUNTIME_ASSETS_FAIL: {error}")
        return 1
    print(f"RUNTIME_ASSETS_OK models={len(json.loads(expected)['assets'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
