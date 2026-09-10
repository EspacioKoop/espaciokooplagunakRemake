"""Validate binary headers, model manifests and generated PNGs without third-party tools."""
from pathlib import Path
import hashlib
import json
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
models = json.loads((ROOT / "game/assets/models/manifest.json").read_text())["models"]
assert len(models) == 21
for model in models:
    content = (ROOT / "game/assets/models" / model["file"]).read_bytes()
    assert content[:4] == b"glTF" and struct.unpack("<I", content[8:12])[0] == len(content), model["name"]
    assert hashlib.sha256(content).hexdigest() == model["sha256"], model["name"]
leisure = next(model for model in models if model["name"] == "leisure_bundle")
leisure_source = (ROOT / leisure["source"]).read_bytes()
assert leisure_source[:4] == bytes.fromhex("28b52ffd") or leisure_source[:7] == b"BLENDER"
assert hashlib.sha256(leisure_source).hexdigest() == leisure["source_sha256"]
assert len(leisure["submodels"]) == 6
source = (ROOT / "art/blender/lagunak_assets.blend").read_bytes()
assert source[:7] == b"BLENDER"
for filename in ["01_inicio", "02_puente", "03_ingenieria", "04_cubierta", "05_reactor", "06_atlas", "07_campana", "08_editor", "09_operaciones", "10_asistencia", "11_astillero", "12_museo", "13_libro", "14_playa", "15_cantina", "16_terraza", "17_estudio", "18_recuerdos", "19_poker"]:
    content = (ROOT / "docs/images" / (filename + ".png")).read_bytes()
    assert content[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", content[16:24]) == (1600, 900), filename
for platform, name, signature in [("linux", "EspaciokoopLagunak.x86_64", b"\x7fELF"), ("windows", "EspaciokoopLagunak.exe", b"MZ")]:
    file = ROOT / "build" / platform / name
    if file.exists():
        with file.open("rb") as source: assert source.read(len(signature)) == signature
checksums = ROOT / "dist/SHA256SUMS"
if checksums.exists():
    for line in checksums.read_text().splitlines():
        digest, filename = line.split("  ", 1)
        file = ROOT / "dist" / filename
        assert hashlib.sha256(file.read_bytes()).hexdigest() == digest
        with zipfile.ZipFile(file) as archive:
            assert archive.testzip() is None
            assert "LICENSE" in archive.namelist()
print("ARTIFACTS_OK editable Blender source, twenty-one GLBs, nineteen PNGs and available binary archives")
