"""Export edited sources without rebuilding or overwriting the artist's .blend."""
from pathlib import Path
import hashlib
import json
import bpy

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/blender/memory_guardians.blend"
OUTPUT = ROOT / "game/assets/models/memory_guardians.glb"
NAMES = ["memory_keeper", "memory_sentinel", "memory_prism"]


def export():
    if Path(bpy.data.filepath) != SOURCE:
        bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    bpy.ops.object.select_all(action="DESELECT")
    for name in NAMES:
        root = bpy.data.objects[name]
        root.select_set(True)
        for child in root.children_recursive:
            child.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB",
        use_selection=True, export_apply=True, export_cameras=False,
        export_lights=False, export_yup=True)
    document = {"version": 1, "license": "MIT", "blender": bpy.app.version_string,
        "source": str(SOURCE.relative_to(ROOT)), "file": str(OUTPUT.relative_to(ROOT)),
        "submodels": NAMES,
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest()}
    OUTPUT.with_suffix(".manifest.json").write_text(json.dumps(document, indent=2) + "\n")
    print("MEMORY_EXPORT_OK", len(NAMES), OUTPUT.stat().st_size, flush=True)


if __name__ == "__main__":
    export()
