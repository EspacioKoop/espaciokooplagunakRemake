"""Export saved .blend files without rebuilding geometry or saving over the source.

blender -b --python art/blender/frontier_pack/tools/export_sources.py
blender -b --python art/blender/frontier_pack/tools/export_sources.py -- --asset haizea_scout
Use --output-dir for a round-trip check that leaves committed GLBs unchanged.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import sys
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import build_pack as pack


def export_one(entry,output):
    source=pack.ROOT/entry['source']
    before=hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    collection=bpy.data.collections.get('Asset_'+entry['id'])
    if collection is None:
        raise ValueError('Missing asset collection: '+entry['id'])
    pack.OBJECTS=list(collection.all_objects)
    roots=[o for o in pack.OBJECTS if o.get('asset_id')==entry['id']]
    if len(roots)!=1:
        raise ValueError('Expected exactly one identified asset root')
    pack.ROOT_OBJECT=roots[0]
    # The manifest describes the neutral pose, not whichever NLA frame happens
    # to be active when the file opens (notably the turret's Scan rotation).
    # Freeze only the in-memory scene, then restore tracks for animation export.
    tracks=[(track,track.mute) for obj in pack.OBJECTS if obj.animation_data
            for track in obj.animation_data.nla_tracks]
    pack.freeze_for_preview()
    low,high,_=pack.bounds()
    for track,muted in tracks:
        track.mute=muted
    for obj in pack.OBJECTS:
        if obj.type=='ARMATURE':
            obj.data.pose_position='POSE'
    bpy.context.view_layer.update()
    sockets=[o.name for o in pack.OBJECTS if o.get('socket')]
    pack.optimize_export()
    # Exclude studio objects or unrelated objects a modeller added outside the asset collection.
    pack.OBJECTS=list(collection.all_objects)
    path=output/(entry['id']+'.glb')
    pack.export_current(path)
    after=hashlib.sha256(source.read_bytes()).hexdigest()
    if before!=after:
        raise RuntimeError('Exporter unexpectedly modified a Blender source')
    updated=dict(entry)
    updated.update(pack.glb_info(path))
    updated.update(source_sha256=after,sockets=sockets,
        dimensions_m=[round(float(high.x-low.x),5),round(float(high.z-low.z),5),round(float(high.y-low.y),5)])
    return updated


def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset',choices=[s[0] for s in pack.SPECS])
    parser.add_argument('--output-dir',type=Path,default=pack.MODELS)
    options=parser.parse_args(args)
    output=options.output_dir.resolve()
    if output==pack.SOURCES or pack.SOURCES in output.parents:
        raise ValueError('Export directory cannot be inside the editable source library')
    output.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((pack.MODELS/'manifest.json').read_text())
    entries=[]
    for entry in manifest['assets']:
        if options.asset and entry['id']!=options.asset:
            entries.append(entry)
            continue
        entries.append(export_one(entry,output))
    manifest['assets']=entries
    if output==pack.MODELS:
        (output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    else:
        selected=[e for e in entries if not options.asset or e['id']==options.asset]
        (output/'roundtrip.json').write_text(json.dumps({'assets':selected,'source_files_unchanged':True},indent=2)+'\n')
    print('FRONTIER_EXPORT_OK',options.asset or len(entries),'sources unchanged')


if __name__=='__main__':
    main()
