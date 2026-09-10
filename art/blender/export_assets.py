"""Export each editable collection to a centered, merged GLB without changing the .blend.

Run with Blender 4.5+: blender --background art/blender/lagunak_assets.blend
    --python art/blender/export_assets.py
Also supports the official bpy Python module.
"""
from pathlib import Path
import hashlib
import json
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/blender/lagunak_assets.blend"
OUTPUT = ROOT / "game/assets/models"
OUTPUT.mkdir(parents=True, exist_ok=True)
if Path(bpy.data.filepath) != SOURCE:
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
original_scene = bpy.context.scene
collections = [c for c in bpy.data.collections if c.name != "Collection"]
manifest = []
for collection in collections:
    originals = [o for o in collection.all_objects if o.type == "MESH"]
    if not originals:
        continue
    # The editable showroom uses a 48 m × 55 m grid. Remove only that grid offset.
    average = sum((o.matrix_world.translation for o in originals), Vector()) / len(originals)
    offset = Vector((round(average.x / 48) * 48, round(average.y / 55) * 55, 0))
    graph = bpy.context.evaluated_depsgraph_get()
    meshes = [(o.name, bpy.data.meshes.new_from_object(o.evaluated_get(graph), depsgraph=graph), o.matrix_world.copy()) for o in originals]
    temporary_scene = bpy.data.scenes.new("Export_" + collection.name)
    bpy.context.window.scene = temporary_scene
    for name, mesh, matrix in meshes:
        duplicate = bpy.data.objects.new(name, mesh)
        temporary_scene.collection.objects.link(duplicate)
        matrix.translation -= offset
        duplicate.matrix_world = matrix
        duplicate.select_set(True)
        bpy.context.view_layer.objects.active = duplicate
    bpy.ops.object.join()
    combined = bpy.context.object
    combined.name = collection.name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    dimensions = [round(float(v), 4) for v in combined.dimensions]
    path = OUTPUT / (collection.name + ".glb")
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
        export_apply=True, export_cameras=False, export_lights=False, export_yup=True)
    manifest.append({"name": collection.name, "file": path.name, "editable_parts": len(originals),
        "dimensions_blender_xyz": dimensions, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    bpy.context.window.scene = original_scene
    bpy.data.scenes.remove(temporary_scene)
    print("EXPORTED", collection.name, dimensions, flush=True)
assert len(manifest) == 20, f"Expected 20 models, got {len(manifest)}"
manifest_path = OUTPUT / "manifest.json"
if manifest_path.exists():
    manifest += [entry for entry in json.loads(manifest_path.read_text())["models"]
                 if entry.get("source") == "art/blender/leisure_assets.blend"]
manifest_path.write_text(json.dumps({"blender": bpy.app.version_string, "models": manifest}, indent=2) + "\n")
