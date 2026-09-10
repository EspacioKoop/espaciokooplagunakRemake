#!/usr/bin/env python3
"""Run real Godot tests with isolated local state and positive success markers."""
from __future__ import annotations
import os
from pathlib import Path
import shutil
import struct
import subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/orbita'


def run(name,cmd,marker=None):
    OUT.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy()
    for variable,folder in [('HOME','home'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data'),('XDG_CACHE_HOME','cache')]:
        path=OUT/'isolated'/folder; path.mkdir(parents=True,exist_ok=True); env[variable]=str(path)
    env['GODOT_SILENCE_ROOT_WARNING']='1'
    result=subprocess.run(cmd,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=240)
    text=result.stdout
    (OUT/(name+'.log')).write_text(text,encoding='utf-8')
    print(text[-16000:],flush=True)
    if result.returncode or 'SCRIPT ERROR' in text or 'ERROR:' in text or 'ORBITA_ASSERT_FAIL' in text:
        raise RuntimeError(name+' failed; inspect '+str(OUT/(name+'.log')))
    if marker and marker not in text: raise RuntimeError(name+' missing positive marker '+marker)


def main():
    godot=ROOT/'.toolchain/godot'
    if not godot.is_file(): raise SystemExit('Run python tools/bootstrap.py first')
    run('godot-import',[str(godot),'--headless','--editor','--path','game','--quit'])
    run('godot-tests',[str(godot),'--headless','--path','game','--script','../tests/orbita_pack/test_import.gd'],'ORBITA_GODOT_PASS assets=12')
    if not shutil.which('xvfb-run'): raise SystemExit('xvfb-run required for the real rendered capture')
    capture=OUT/'godot-viewer.png'
    # The visual CI runner has no sound device. Keep strict ERROR detection;
    # explicitly select Godot's null audio backend instead of hiding ALSA errors.
    run('godot-capture',['xvfb-run','-a',str(godot),'--path','game','--rendering-method','gl_compatibility',
        '--audio-driver','Dummy','--resolution','1600x900','res://asset_lab/orbita_pack/viewer.tscn',
        '--','--orbita-capture='+str(capture)],'ORBITA_CAPTURE_PASS')
    data=capture.read_bytes()
    if data[:8]!=b'\x89PNG\r\n\x1a\n' or struct.unpack_from('>II',data,16)!=(1600,900):
        raise RuntimeError('Capture missing or wrong dimensions')
    print('ORBITA_RUNTIME_PASS',flush=True)

if __name__=='__main__': main()
