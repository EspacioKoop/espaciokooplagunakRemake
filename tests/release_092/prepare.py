#!/usr/bin/env python3
"""Derive embedded acceptance fixtures without editing or weakening source assertions."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ("test_terminal_transition.gd", "test_leisure.gd", "test_ship_corridors.gd", "test_ship_deck_layout.gd")
FIXTURE_DIR = "game/release_acceptance/fixtures"
MANIFEST = "game/data/release_acceptance_sources.json"


def rendered(root: Path = ROOT) -> dict[str, bytes]:
    inputs = ["tests/" + name for name in SCRIPTS] + ["tests/release_092/test_export_contract.gd"]
    output = {}
    sources = {}
    for source_path in inputs:
        raw = (root / source_path).read_bytes()
        text = raw.decode("utf-8")
        for helper in ("test_ship_corridors.gd", "test_ship_deck_layout.gd"):
            text = text.replace('"res://../tests/' + helper + '"', '"res://release_acceptance/fixtures/' + helper + '"')
        if "res://../tests/" in text:
            raise ValueError("Unreviewed test dependency: " + source_path)
        target = FIXTURE_DIR + "/" + Path(source_path).name
        output[target] = text.encode("utf-8")
        sources[source_path] = {"source_sha256": hashlib.sha256(raw).hexdigest(), "fixture": target,
                                "fixture_sha256": hashlib.sha256(output[target]).hexdigest()}
    output[MANIFEST] = (json.dumps({"schema": 1, "sources": sources}, indent=2, sort_keys=True) + "\n").encode("utf-8")
    return output


def prepare(root: Path = ROOT, check: bool = False) -> None:
    expected = rendered(root)
    for name, content in expected.items():
        path = root / name
        if check:
            if not path.is_file() or path.read_bytes() != content:
                raise ValueError("Stale or modified embedded test fixture: " + name)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    actual = {str(path.relative_to(root)) for path in (root / FIXTURE_DIR).rglob("*") if path.is_file() and not path.name.endswith(".gd.uid")}
    if actual != set(expected) - {MANIFEST}:
        raise ValueError("Unexpected embedded fixture files")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    prepare(check=args.check)
    print("EMBEDDED_FIXTURES_VERIFIED 5 unchanged assertion suites")
