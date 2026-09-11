"""Finalize generated sources: engine-safe socket names and calibrated studio light.

This is the explicit source-writing stage of an initial build. It is not the
manual-edit exporter. Use export_sources.py for non-destructive re-export.
python art/blender/frontier_pack/tools/prepare_library.py --write-sources --render
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build_pack as pack


def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write-sources',action='store_true',help='Explicitly permit saving prepared .blend sources')
    parser.add_argument('--render',action='store_true')
    options=parser.parse_args(args)
    if not options.write_sources:
        parser.error('This preparation step writes sources: --write-sources is required')
    path=pack.MODELS/'manifest.json'
    manifest=json.loads(path.read_text())
    for entry in manifest['assets']:
        source=pack.ROOT/entry['source']
        bpy.ops.wm.open_mainfile(filepath=str(source))
        collection=bpy.data.collections.get('Asset_'+entry['id'])
        if collection is None:
            raise ValueError('Missing asset collection: '+entry['id'])
        pack.OBJECTS=list(collection.all_objects)
        pack.ROOT_OBJECT=next(o for o in pack.OBJECTS if o.get('asset_id')==entry['id'])
        # Blender auto suffixes contain dots, which Godot sanitizes in Node names.
        # Namespace sockets separately from render geometry and make names portable.
        counters={}
        for obj in sorted(pack.OBJECTS,key=lambda o:o.name):
            if not obj.get('socket'):
                continue
            original=obj.get('socket_semantic',obj.name)
            semantic=re.sub(r'\.\d+$','',original).removeprefix('Socket_')
            semantic=re.sub(r'[^A-Za-z0-9_]','_',semantic)
            obj['socket_semantic']=semantic
            counters[semantic]=counters.get(semantic,0)+1
            suffix='' if counters[semantic]==1 else '_'+str(counters[semantic]).zfill(2)
            obj.name='Socket_'+semantic+suffix
        pack.freeze_for_preview()
        low,high,_=pack.bounds()
        extent=max(high-low)
        for name,energy in [('Key',45),('Fill',18),('Rim',65)]:
            light=bpy.data.objects.get('__Studio_'+name)
            if light is not None:
                light.data.energy=energy*extent**2
        bpy.context.scene.world.node_tree.nodes['Background'].inputs[1].default_value=.30
        bpy.context.scene.cycles.samples=32
        bpy.context.scene.render.resolution_x=720
        bpy.context.scene.render.resolution_y=720
        entry['sockets']=[o.name for o in pack.OBJECTS if o.get('socket')]
        entry['socket_convention']='Socket_<semantic>[_02...]; +Y Blender / -Z glTF forward'
        entry['dimensions_m']=[round(float(high.x-low.x),5),round(float(high.z-low.z),5),round(float(high.y-low.y),5)]
        # Store animations active in sources, with rigs resting for comfortable editing.
        for obj in pack.OBJECTS:
            if obj.animation_data:
                for track in obj.animation_data.nla_tracks:
                    track.mute=False
        text=bpy.data.texts.get('ASSET_README.json')
        if text:
            text.clear()
            text.write(json.dumps(entry,ensure_ascii=False,indent=2))
        bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(source),compress=True)
        entry['source_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
        for obj in pack.OBJECTS:
            if obj.type=='ARMATURE':
                obj.data.pose_position='POSE'
        pack.optimize_export()
        pack.OBJECTS=list(collection.all_objects)
        output=pack.MODELS/(entry['id']+'.glb')
        pack.export_current(output)
        entry.update(pack.glb_info(output))
        if options.render:
            pack.freeze_for_preview()
            bpy.context.scene.render.filepath=str(pack.IMAGES/(entry['id']+'.png'))
            bpy.ops.render.render(write_still=True)
        print('PREPARED',entry['id'],flush=True)
    manifest['preparation_version']=1
    path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    if options.render:
        pack.sheets(manifest['assets'])
    print('FRONTIER_PREPARE_OK',len(manifest['assets']),flush=True)


if __name__=='__main__':
    main()
