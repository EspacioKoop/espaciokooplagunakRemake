#!/usr/bin/env python3
"""Run the second batch in real Godot; retain strict error detection and logs."""
from __future__ import annotations
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parent))
import run as original

ROOT=original.ROOT
OUT=original.OUT


def main():
    godot=ROOT/'.toolchain/godot'
    if not godot.is_file():
        raise SystemExit('Run python tools/bootstrap.py first')
    original.run('player-godot-import',[str(godot),'--headless','--editor','--path','game','--quit'])
    original.run('player-godot-tests',[str(godot),'--headless','--path','game','--script','../tests/orbita_pack/test_player_batch.gd'],
                 'ORBITA_PLAYER_GODOT_PASS assets=10 library=22')
    captures=[]
    for ident in ('argi_worklight','uhina_arc_emitter','balea_rescue_ship'):
        path=OUT/('player-'+ident+'.png')
        original.run('capture-'+ident,['xvfb-run','-a',str(godot),'--path','game','--rendering-method','gl_compatibility',
            '--audio-driver','Dummy','--resolution','1600x900','res://asset_lab/orbita_pack/player_batch.tscn',
            '--','--orbita-select=orbita/'+ident,'--orbita-capture='+str(path)],'ORBITA_CAPTURE_PASS')
        data=path.read_bytes()
        if data[:8]!=b'\x89PNG\r\n\x1a\n' or struct.unpack_from('>II',data,16)!=(1600,900):
            raise RuntimeError('Incorrect Godot capture: '+ident)
        captures.append(path.name)
    (OUT/'player-runtime.json').write_text(json.dumps({'status':'pass','assets':10,'library_assets':22,'captures':captures},indent=2)+'\n')
    print('ORBITA_PLAYER_RUNTIME_PASS assets=10 library=22',flush=True)


if __name__=='__main__':
    main()
