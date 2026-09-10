"""Executed with bpy installed. Verify source -> GLB round-trip for all 24 models."""
from __future__ import annotations
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]


def main():
    directory=ROOT/'game/assets/models/frontier_pack'
    manifest=json.loads((directory/'manifest.json').read_text())
    before={entry['source']:hashlib.sha256((ROOT/entry['source']).read_bytes()).hexdigest() for entry in manifest['assets']}
    spec=importlib.util.spec_from_file_location('frontier_validate',Path(__file__).with_name('validate_pack.py'))
    validator=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    results=[]
    with tempfile.TemporaryDirectory(prefix='frontier-roundtrip-') as folder:
        subprocess.run([sys.executable,str(ROOT/'art/blender/frontier_pack/tools/export_sources.py'),
            '--output-dir',folder],check=True,timeout=300)
        exported=json.loads((Path(folder)/'roundtrip.json').read_text())
        by_id={entry['id']:entry for entry in exported['assets']}
        for old in manifest['assets']:
            new=by_id[old['id']]
            for field in ['triangles','mesh_nodes','materials','skins','joints']:
                if old[field]!=new[field]:
                    raise ValueError(old['id']+': changed round-trip '+field)
            for field in ['animations','sockets']:
                if set(old[field])!=set(new[field]):
                    raise ValueError(old['id']+': changed round-trip '+field)
            if any(abs(a-b)>1e-3 for a,b in zip(old['dimensions_m'],new['dimensions_m'])):
                raise ValueError(old['id']+': round-trip bounds changed')
            validator.validate_asset(Path(folder)/(old['id']+'.glb'),new)
            if before[old['source']]!=hashlib.sha256((ROOT/old['source']).read_bytes()).hexdigest():
                raise ValueError('Source file was modified during export: '+old['source'])
            results.append({'id':old['id'],'source_unchanged':True,'geometry_and_clips_preserved':True})
    report={'passed':True,'assets_checked':len(results),'scope':'Reopen all editable Blender sources and re-export without overwriting sources. Structural equivalence, not byte-identical exporter output.','assets':results}
    (directory/'roundtrip_validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('FRONTIER_ROUNDTRIP_OK',len(results))


if __name__=='__main__':
    main()
