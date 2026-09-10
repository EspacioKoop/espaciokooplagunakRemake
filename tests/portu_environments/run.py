"""Strict real-engine runner. Keeps user settings/saves outside the test process. MIT."""
from __future__ import annotations
import os
import re
import shutil
import subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/portu'
ANSI=re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
ERROR=re.compile(r'(?im)^\s*(?:SCRIPT ERROR|ERROR)(?::|\s)')


def execute(name,args,marker=None,timeout=240):
    env=os.environ.copy()
    env.update(LIBGL_ALWAYS_SOFTWARE='1',GODOT_SILENCE_ROOT_WARNING='1')
    for variable,folder in [('HOME','home'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data'),('XDG_CACHE_HOME','cache')]:
        target=OUT/folder;target.mkdir(parents=True,exist_ok=True);env[variable]=str(target)
    try:
        p=subprocess.run([str(x) for x in args],cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        text=exc.stdout or b''
        if isinstance(text,bytes):text=text.decode(errors='replace')
        (OUT/(name+'.log')).write_text(text+'\nRUNNER_TIMEOUT\n')
        raise SystemExit(name+' timed out')
    text=ANSI.sub('',p.stdout);(OUT/(name+'.log')).write_text(text)
    print(text,flush=True)
    if p.returncode or ERROR.search(text):raise SystemExit(name+' failed: '+str(p.returncode))
    if marker and not re.search(marker,text):raise SystemExit(name+' missing positive nonzero success marker')


def main():
    OUT.mkdir(parents=True,exist_ok=True);godot=ROOT/'.toolchain/godot'
    if not godot.is_file():raise SystemExit('Run tools/bootstrap.py')
    execute('import',[godot,'--headless','--editor','--path','game','--quit'])
    execute('runtime',[godot,'--headless','--path','game','--fixed-fps','60','--script',ROOT/'tests/portu_environments/runtime.gd'],r'PORTU_RUNTIME_PASS checks=\s*[1-9]\d* failures=\s*0')
    execute('capture',['xvfb-run','-a',godot,'--path','game','--rendering-method','gl_compatibility','--audio-driver','Dummy','--fixed-fps','60','--script',ROOT/'tests/portu_environments/runtime.gd','--','--capture'],r'PORTU_CAPTURE_PASS checks=\s*[1-9]\d* failures=\s*0',timeout=300)
    from PIL import Image,ImageStat
    for i in range(8):
        for mode in ('overview','walk'):
            p=OUT/(mode+'_'+str(i)+'.png')
            with Image.open(p) as im:
                if im.size!=(1600,900) or max(ImageStat.Stat(im.convert('RGB')).var)<8:raise SystemExit('Invalid/blank capture '+p.name)
            target=ROOT/'docs/images/portu_environments'/('godot_'+p.name)
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    print('PORTU_RUNNER_PASS captures=16')

if __name__=='__main__':main()
