"""Run real Godot validation. Fail on errors, missing markers or zero checks. MIT."""
from __future__ import annotations
import os
import re
import shutil
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/itsasargi'
ANSI=re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
ERROR=re.compile(r'(?im)^\s*(?:SCRIPT ERROR|ERROR)(?::|\s)')


def run(name,command,marker=None,timeout=300):
    env=os.environ.copy();env['LIBGL_ALWAYS_SOFTWARE']='1'
    result=subprocess.run([str(x) for x in command],cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
    text=ANSI.sub('',result.stdout)
    (OUT/(name+'.log')).write_text(text,encoding='utf-8')
    print(text,flush=True)
    if result.returncode or ERROR.search(text):raise SystemExit(f'{name} failed, exit {result.returncode}')
    if marker and not re.search(marker,text):raise SystemExit(name+' missing success marker')
    return text


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    godot=ROOT/'.toolchain/godot'
    if not godot.exists():raise SystemExit('Run tools/bootstrap.py first')
    run('godot-import',[godot,'--headless','--editor','--path',ROOT/'game','--quit'],timeout=300)
    text=run('godot-tests',[godot,'--headless','--path',ROOT/'game','--fixed-fps','60','--script',ROOT/'tests/itsasargi_pack/test_import.gd'],r'ITSASARGI_GODOT_PASS checks=\s*[1-9]\d* failures=\s*0',timeout=300)
    run('godot-capture',['xvfb-run','-a',godot,'--path',ROOT/'game','--rendering-method','gl_compatibility','--audio-driver','Dummy','--script',ROOT/'tests/itsasargi_pack/capture.gd'],r'ITSASARGI_CAPTURE_PASS',timeout=240)
    from PIL import Image
    for name in ['itsasargi_tool','itsasargi_ship','bizi_0_orbit','bizi_0_surface','bizi_1_orbit','bizi_1_surface']:
        image=OUT/(name+'.png')
        with Image.open(image) as im:
            if im.size!=(1600,900):raise SystemExit('Wrong screenshot dimensions '+name)
        folder='bizi_planets' if name.startswith('bizi_') else 'itsasargi_pack'
        target=ROOT/'docs/images'/folder/('godot_'+name+'.png')
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(image,target)
    print('GODOT_RUNNER_PASS')

if __name__=='__main__':main()
