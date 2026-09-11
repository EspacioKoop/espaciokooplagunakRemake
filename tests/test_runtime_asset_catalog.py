"""Runtime index validation: synthetic files only, no network or player data."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import runtime_asset_catalog as catalog

class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.model = self.root / "game/assets/models/sample/model.glb"
        self.source = self.root / "art/blender/sample/model.blend"
        self.manifest = self.root / "game/assets/models/sample/manifest.json"
        for path in (self.model, self.source, self.manifest): path.parent.mkdir(parents=True, exist_ok=True)
        self.model.write_bytes(b"synthetic-model")
        self.source.write_bytes(b"synthetic-blender-source")
        self.row = {"id": "sample/model", "resource": "res://assets/models/sample/model.glb",
                    "title": "Synthetic model", "category": "ships", "source": "art/blender/sample/model.blend",
                    "sha256": hashlib.sha256(self.model.read_bytes()).hexdigest(),
                    "source_sha256": hashlib.sha256(self.source.read_bytes()).hexdigest(), "license": "MIT"}
        self.doc = {"schema":"espaciokoop-asset-pack", "version":1, "assets":[self.row]}
        self.patcher = patch.object(catalog, "MANIFESTS", (("sample", "game/assets/models/sample/manifest.json"),))
        self.patcher.start(); self.addCleanup(self.patcher.stop)
    def build(self):
        self.manifest.write_text(json.dumps(self.doc), encoding="utf-8")
        return catalog.build_catalog(self.root)
    def test_valid_deterministic(self):
        first = self.build()
        self.assertEqual(first, self.build())
        self.assertEqual(first["assets"][0]["contact_kinds"], ["friendly", "hostile", "derelict"])
        self.assertEqual(self.model.read_bytes(), b"synthetic-model")
    def test_hash_mismatch(self):
        self.model.write_bytes(b"modified")
        with self.assertRaises(ValueError): self.build()
    def test_missing_model(self):
        self.model.unlink()
        with self.assertRaises(ValueError): self.build()
    def test_source_hash_mismatch(self):
        self.source.write_bytes(b"modified")
        with self.assertRaises(ValueError): self.build()
    def test_duplicate_identifier(self):
        self.doc["assets"].append(self.row.copy())
        with self.assertRaises(ValueError): self.build()
    def test_foreign_and_unsafe_identifiers(self):
        for value in ("other/model", "../model", "sample/../../model", "user://file", "sample/model\n"):
            with self.subTest(value=value):
                self.row["id"] = value
                with self.assertRaises(ValueError): self.build()
    def test_external_and_escaping_paths(self):
        for value in ("user://private.glb", "https://example.invalid/model.glb",
                      "res://assets/models/../../../secret.glb", "res://assets/models/sample\\model.glb"):
            with self.subTest(value=value):
                self.row["resource"] = value
                with self.assertRaises(ValueError): self.build()
    def test_blender_source_required(self):
        self.source.unlink()
        with self.assertRaises(ValueError): self.build()
    def test_source_cannot_escape(self):
        self.row["source"] = "../private.blend"
        with self.assertRaises(ValueError): self.build()
    def test_symlink_cannot_escape(self):
        self.model.unlink()
        self.model.symlink_to("/etc/hostname")
        with self.assertRaises(ValueError): self.build()
    def test_control_characters(self):
        self.row["title"] = "misleading\nname"
        with self.assertRaises(ValueError): self.build()
    def test_bad_version(self):
        self.doc["version"] = 2
        with self.assertRaises(ValueError): self.build()
    def test_no_implicit_equipment_gameplay(self):
        self.row["category"] = "weapons"
        self.assertEqual(self.build()["assets"][0]["contact_kinds"], [])

if __name__ == "__main__": unittest.main(verbosity=2)
