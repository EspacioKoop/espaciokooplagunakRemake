"""Reexport edited Lantegi .blend sources; previews reimport delivered GLBs.
MIT. No network, textures or external art. Static joins happen only in memory.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build import HERE, ROOT, SPECS
MODELS = ROOT / 'game/assets/models/lantegi_pack'
IMAGES = ROOT / 'docs/images/lantegi_pack'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bounds(root):
    bpy.context.view_layer.update()
    points = [ob.matrix_world @ Vector(co) for ob in [root, *root.children_recursive]
              if ob.type == 'MESH' for co in ob.bound_box]
    if not points:
        raise ValueError('No geometry under ' + root.name)
    return (Vector([min(p[i] for p in points) for i in range(3)]),
            Vector([max(p[i] for p in points) for i in range(3)]))


def optimise(root):
    groups = {}
    for ob in list(root.children_recursive):
        if ob.type != 'MESH':
            continue
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        for mod in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-7)
        bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-7)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        degenerate = [f for f in bm.faces if f.calc_area() <= 1e-12]
        if degenerate:
            bmesh.ops.delete(bm, geom=degenerate, context="FACES_ONLY")
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()
        if not ob.animation_data and not ob.children:
            groups.setdefault(ob.parent, []).append(ob)
    for parent, parts in groups.items():
        if len(parts) < 2:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        for ob in parts:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        parts[0].name = parent.name + '_mesh'


def glb_json(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', data)
    if (magic, version, length) != (0x46546C67, 2, len(data)):
        raise ValueError('Invalid GLB header')
    size, kind = struct.unpack_from('<II', data, 12)
    if kind != 0x4E4F534A:
        raise ValueError('Missing JSON')
    return json.loads(data[20:20 + size])


def sockets(doc):
    nodes = doc['nodes']
    parents = {child: i for i, node in enumerate(nodes) for child in node.get('children', [])}
    result = []
    for i, node in enumerate(nodes):
        if not node.get('name', '').startswith('socket_'):
            continue
        path, current, seen = [], i, set()
        while current is not None:
            if current in seen:
                raise ValueError('Cyclic hierarchy')
            seen.add(current)
            path.append(nodes[current].get('name', str(current)))
            current = parents.get(current)
        result.append({'name': node['name'], 'node_index': i,
                       'gltf_path': '/'.join(reversed(path))})
    if len({s['name'] for s in result}) != len(result):
        raise ValueError('Ambiguous socket names')
    return result


def render_glb(ident, target, destination, view=(1.2, 1.8, 1.1)):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(target))
    root = bpy.data.objects.get(ident)
    if root is None:
        raise ValueError('Lost root in GLB round trip: ' + ident)
    scene = bpy.context.scene
    scene.frame_set(1)
    low, high = bounds(root)
    centre = (low + high) * .5
    radius = max((high - low).length * .5, .15)
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 20
    scene.cycles.use_denoising = True
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 4
    scene.render.resolution_x = scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = True
    world = bpy.data.worlds.new('Inspection_world')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (.19, .23, .3, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = .4
    scene.world = world
    data = bpy.data.cameras.new('Inspection_camera')
    camera = bpy.data.objects.new(data.name, data)
    scene.collection.objects.link(camera)
    camera.location = centre + Vector(view).normalized() * radius * 5
    camera.rotation_euler = (centre - camera.location).to_track_quat('-Z', 'Y').to_euler()
    data.type = 'ORTHO'
    data.clip_start = .01
    data.clip_end = radius * 30
    bpy.context.view_layer.update()
    inv = camera.matrix_world.inverted()
    points = [inv @ (ob.matrix_world @ Vector(co)) for ob in root.children_recursive
              if ob.type == 'MESH' for co in ob.bound_box]
    span = max(max(p[i] for p in points) - min(p[i] for p in points) for i in (0, 1))
    data.ortho_scale = span * 1.23
    scene.camera = camera
    for name, direction, energy, tint in [
        ('Key', (2.3, 3, 4), 1100, (.83, .92, 1)),
        ('Fill', (-2.4, 1.5, 1.7), 750, (.4, .73, 1)),
        ('Rim', (1, -3, 2.3), 1350, (1, .6, .3)),
    ]:
        light = bpy.data.lights.new('Inspection_' + name, 'AREA')
        light.energy = energy * radius * radius
        light.color = tint
        light.shape = 'DISK'
        light.size = radius * 3
        lamp = bpy.data.objects.new(light.name, light)
        scene.collection.objects.link(lamp)
        lamp.location = centre + Vector(direction) * radius
        lamp.rotation_euler = (centre - lamp.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(destination)
    bpy.ops.render.render(write_still=True)


def contact_sheet(entries):
    from PIL import Image, ImageDraw, ImageFont
    page = Image.new('RGB', (1800, 1000), '#0b1823')
    draw = ImageDraw.Draw(page)
    try:
        path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
        title = ImageFont.truetype(path, 34)
        small = ImageFont.truetype(path, 16)
        label = ImageFont.truetype(path, 21)
    except OSError:
        title = small = label = ImageFont.load_default()
    draw.text((36, 22), 'LANTEGI / EQUIPO DE CAMPO', font=title, fill='#eff4ef')
    draw.text((38, 67), '6 herramientas + 2 armas ficticias + 2 naves / GLB reimportados en Blender', font=small, fill='#8fb4bf')
    for i, e in enumerate(entries):
        x, y = 25 + (i % 5) * 355, 109 + (i // 5) * 426
        draw.rounded_rectangle((x, y, x + 339, y + 410), radius=12, fill='#142b39')
        image = Image.open(IMAGES / (e['slug'] + '.png')).convert('RGBA')
        image.thumbnail((320, 318), Image.Resampling.LANCZOS)
        page.paste(image, (x + (339 - image.width) // 2, y + 5 + (318 - image.height) // 2), image)
        name, desc = e['title'].split(' · ')
        draw.text((x + 13, y + 328), name, font=label, fill='#eef4ef')
        draw.text((x + 13, y + 359), desc, font=small, fill='#8fb4bf')
        draw.text((x + 13, y + 382), f"{e['triangles']} tris / {len(e['sockets'])} anclajes", font=small, fill='#8fb4bf')
    draw.text((38, 976), 'Recursos reutilizables; no añade reglas de combate, reparación ni selección de nave.', font=small, fill='#8fb4bf')
    page.save(IMAGES / 'overview.png')


def export_one(root, target):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [root, *root.children_recursive]:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = root
    animated = any(ob.animation_data for ob in [root, *root.children_recursive])
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB', use_selection=True,
        export_yup=True, export_extras=True, export_animations=animated,
        export_animation_mode='SCENE', export_frame_range=True,
        export_anim_scene_split_object=False, export_cameras=False, export_lights=False,
        export_apply=False, export_copyright='Original Espaciokoop Lagunak art - MIT')
    return glb_json(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', action='store_true')
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    args = parser.parse_args(argv)
    MODELS.mkdir(parents=True, exist_ok=True)
    IMAGES.mkdir(parents=True, exist_ok=True)
    entries = []
    for ident, title, category, description, pivot in SPECS:
        source = HERE / (ident + '.blend')
        before = sha(source)
        bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
        root = bpy.data.objects.get(ident)
        if root is None or root.get('asset_id') != 'lantegi/' + ident:
            raise ValueError('Invalid source root: ' + ident)
        bpy.context.scene.frame_set(1)
        bpy.context.scene.name = 'mechanical_cycle'
        count = sum(ob.type == 'MESH' for ob in root.children_recursive)
        optimise(root)
        low, high = bounds(root)
        lo = [low.x, low.z, -high.y]
        hi = [high.x, high.z, -low.y]
        target = MODELS / (ident + '.glb')
        doc = export_one(root, target)
        tris = sum(doc['accessors'][p['indices']]['count'] // 3
                   for m in doc['meshes'] for p in m['primitives'])
        entry = {'id': 'lantegi/' + ident, 'slug': ident, 'version': 1, 'title': title,
            'category': category, 'description': description, 'units': 'metres',
            'axes': '+Y up; -Z forward', 'pivot': pivot, 'license': 'MIT',
            'source': str(source.relative_to(ROOT)), 'runtime': str(target.relative_to(ROOT)),
            'source_sha256': before, 'runtime_sha256': sha(target), 'bytes': target.stat().st_size,
            'triangles': tris, 'editable_parts': count, 'aabb_min': lo, 'aabb_max': hi,
            'dimensions': [hi[i] - lo[i] for i in range(3)], 'sockets': sockets(doc),
            'materials': [m.get('name', '') for m in doc.get('materials', [])],
            'animations': [a['name'] for a in doc.get('animations', [])],
            'status': 'exported', 'preview': 'docs/images/lantegi_pack/' + ident + '.png'}
        if sha(source) != before:
            raise ValueError('Exporter changed source')
        if not entry['animations']:
            raise ValueError('Missing mechanical animation: ' + ident)
        if args.render:
            render_glb(ident, target, IMAGES / (ident + '.png'))
        entries.append(entry)
        print('EXPORTED', ident, tris, flush=True)
    manifest = {'schema': 'espaciokoop-asset-pack', 'schema_version': 1, 'pack': 'lantegi',
                'blender_version': bpy.app.version_string, 'assets': entries,
                'limits': 'Rigid mechanical animation only. No game rules, collision, humanoid rig or automatic campaign integration.'}
    (MODELS / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if args.render:
        contact_sheet(entries)
    print('LANTEGI_EXPORT_PASS', len(entries), flush=True)


if __name__ == '__main__':
    main()
