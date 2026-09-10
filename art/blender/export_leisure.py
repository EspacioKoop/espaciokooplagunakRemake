"""Export the edited leisure showroom without overwriting the Blender source."""
from pathlib import Path
import hashlib
import json
import bpy

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/blender/leisure_assets.blend"
NAMES = ["museum_hall", "cantina", "terrace", "studio", "memories_hall", "beach"]


def export():
    if Path(bpy.data.filepath) != SOURCE:
        bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    roots = [bpy.data.objects[name] for name in NAMES]
    positions = [root.location.copy() for root in roots]
    output = ROOT / "game/assets/models/leisure_bundle.glb"
    try:
        for root in roots:
            root.location = (0, 0, 0)
        bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB",
            export_apply=True, export_cameras=False, export_lights=False, export_yup=True)
    finally:
        for root, position in zip(roots, positions):
            root.location = position
    manifest_path = output.parent / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["models"] = [entry for entry in manifest["models"] if entry["name"] != "leisure_bundle"]
    manifest["models"].append({"name": "leisure_bundle", "file": output.name,
        "source": "art/blender/leisure_assets.blend", "submodels": NAMES,
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest()})
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print("LEISURE_EXPORT_OK", len(roots), output.stat().st_size, flush=True)


if __name__ == "__main__":
    export()
