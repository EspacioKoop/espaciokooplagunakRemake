"""Run Fieldkit Godot tests with isolated state, timeouts and positive markers."""
from __future__ import annotations
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/fieldkit'


def run(name,command,marker=None):
    OUT.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy()
    for variable,folder in [('HOME','home'),('XDG_CONFIG_HOME','config'),('XDG_DATA_HOME','data'),('XDG_CACHE_HOME','cache')]:
        destination=OUT/'isolated'/folder
        destination.mkdir(parents=True,exist_ok=True)
        env[variable]=str(destination)
    env['GODOT_SILENCE_ROOT_WARNING']='1'
    logfile=OUT/(name+'.log')
    with logfile.open('w',encoding='utf-8') as stream:
        try:
            result=subprocess.run(command,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=240)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(name+' timed out; '+str(logfile)) from exc
    if logfile.stat().st_size>24*1024*1024:
        raise RuntimeError(name+' exceeded output limit')
    text=logfile.read_text(encoding='utf-8',errors='replace')
    print(text[-20000:],flush=True)
    if result.returncode or any(token in text for token in ('SCRIPT ERROR','ERROR:','FIELDKIT_ASSERT_FAIL')):
        raise RuntimeError(name+' failed; '+str(logfile))
    if marker and marker not in text:
        raise RuntimeError(name+' missing positive marker: '+marker)


def main():
    godot=ROOT/'.toolchain/godot'
    if not godot.is_file():
        raise SystemExit('Run python tools/bootstrap.py first')
    common=[str(godot),'--audio-driver','Dummy','--path','game']
    run('godot-import',common+['--headless','--editor','--quit'])
    run('godot-tests',common+['--headless','--script','../tests/fieldkit_pack/test_runtime.gd'],'FIELDKIT_GODOT_PASS assets=10')
    if not shutil.which('xvfb-run'):
        raise SystemExit('xvfb-run required for graphical validation')
    images=OUT/'captures'
    run('godot-captures',['xvfb-run','-a']+common+['--rendering-method','gl_compatibility','--resolution','1600x900',
        '--script','../tests/fieldkit_pack/capture.gd','--','--fieldkit-output='+str(images)],'FIELDKIT_CAPTURE_PASS frames=18')
    from PIL import Image,ImageStat
    expected=['asset_%02d.png'%i for i in range(10)]+['equipped_%02d.png'%i for i in range(8)]
    for filename in expected:
        with Image.open(images/filename) as image:
            if image.size!=(1600,900):
                raise RuntimeError('Unexpected screenshot size: '+filename)
            # Excludes the UI panel; detects blank stage/equipment captures.
            sample=image.convert('RGB').crop((500,100,1550,800))
            if max(ImageStat.Stat(sample).stddev)<3:
                raise RuntimeError('Asset not visible in capture: '+filename)
    (OUT/'runtime.json').write_text(json.dumps({'godot_tests':'passed','capture_count':18,'resolution':[1600,900],'audio_backend':'Dummy'},indent=2)+'\n')
    print('FIELDKIT_RUNTIME_PASS captures=18',flush=True)


if __name__=='__main__':
    main()
