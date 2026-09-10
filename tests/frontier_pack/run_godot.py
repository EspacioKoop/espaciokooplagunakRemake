"""Run real Godot import/animation/gallery tests in a disposable project.
The production project, autoloads, private saves and network state are never loaded.
python tests/frontier_pack/run_godot.py --capture
"""
from __future__ import annotations
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
PROJECT='''config_version=5
[application]
config/name="Frontier Asset Lab"
run/main_scene="res://asset_lab/frontier_pack/showcase.tscn"
[display]
window/size/viewport_width=1280
window/size/viewport_height=800
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'''


def execute(command,environment,timeout):
    result=subprocess.run([str(x) for x in command],env=environment,text=True,
        stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout,check=False)
    print(result.stdout,flush=True)
    if result.returncode or re.search(r'(^|\n)(?:SCRIPT ERROR:|ERROR:)',result.stdout):
        raise RuntimeError('Godot process failed: '+repr(command)+'\n'+result.stdout)
    return result.stdout


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',type=Path,default=ROOT/'.toolchain/godot')
    parser.add_argument('--capture',action='store_true')
    options=parser.parse_args()
    engine=options.godot.resolve()
    if not engine.is_file():
        raise FileNotFoundError('Run python3 tools/bootstrap.py or supply --godot /path/to/godot')
    destination=ROOT/'game/assets/models/frontier_pack/godot_validation.json'
    with tempfile.TemporaryDirectory(prefix='lagunak-frontier-') as folder:
        isolated=Path(folder)
        (isolated/'project.godot').write_text(PROJECT)
        shutil.copytree(ROOT/'game/assets/models/frontier_pack',isolated/'assets/models/frontier_pack',
            ignore=shutil.ignore_patterns('*.import','*.log','godot_validation.json'))
        shutil.copytree(ROOT/'game/asset_lab/frontier_pack',isolated/'asset_lab/frontier_pack')
        (isolated/'tests').mkdir()
        shutil.copy2(ROOT/'tests/frontier_pack/test_import.gd',isolated/'tests/test_import.gd')
        environment=dict(os.environ,XDG_DATA_HOME=str(isolated/'userdata'),XDG_CONFIG_HOME=str(isolated/'config'),
                         GODOT_SILENCE_ROOT_WARNING='1')
        logs=[]
        logs.append(execute([engine,'--headless','--editor','--path',isolated,'--quit'],environment,180))
        logs.append(execute([engine,'--headless','--path',isolated,'--script','res://tests/test_import.gd'],environment,180))
        marker='FRONTIER_GODOT_RESULT '
        lines=[line for line in logs[-1].splitlines() if line.startswith(marker)]
        if len(lines)!=1:
            raise RuntimeError('Missing definitive Godot test result')
        result=json.loads(lines[0][len(marker):])
        if result.get('passed') is not True:
            raise RuntimeError('Godot assertions failed')
        result['scope']='Isolated Godot import, animations and real gallery. Not full campaign/network QA.'
        result['capture']=False
        if options.capture:
            image=ROOT/'docs/images/frontier_pack/godot_lab.png'
            image.parent.mkdir(parents=True,exist_ok=True)
            command=[engine,'--path',isolated,'--rendering-method','gl_compatibility',
                     '--resolution','1280x800','--','--frontier-capture='+str(image)]
            if not environment.get('DISPLAY'):
                if not shutil.which('xvfb-run'):
                    raise RuntimeError('xvfb-run or a display is required for capture')
                command=['xvfb-run','-a']+command
            logs.append(execute(command,environment,90))
            if not image.is_file() or image.stat().st_size<10000:
                raise RuntimeError('Capture missing or unexpectedly small')
            result['capture']=True
        destination.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        (destination.parent/'godot_import.log').write_text('\n'.join(logs))
        print('FRONTIER_GODOT_OK',result['checks'])


if __name__=='__main__':
    main()
