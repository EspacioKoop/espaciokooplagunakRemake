"""Run repository-pinned Godot against the isolated Bizigai asset laboratory."""
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'build/bizigai'
BAD=re.compile(r'SCRIPT ERROR:|^ERROR:|Parse Error:|BIZIGAI_TEST_FAIL:',re.MULTILINE)


def run(name,command,timeout=300,marker=None):
    result=subprocess.run(command,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
    (OUT/(name+'.log')).write_text(result.stdout,encoding='utf-8')
    print(result.stdout)
    if result.returncode or BAD.search(result.stdout):
        raise RuntimeError('%s failed: exit=%d'%(name,result.returncode))
    if marker and marker not in result.stdout:
        raise RuntimeError(name+' did not reach completion marker')


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    godot=ROOT/'.toolchain/godot'
    if not godot.is_file(): raise FileNotFoundError('Run python tools/bootstrap.py first')
    game=str(ROOT/'game'); script=str(ROOT/'tests/bizigai_pack/test_lab.gd')
    run('import',[str(godot),'--headless','--editor','--path',game,'--quit'],timeout=420)
    run('headless',[str(godot),'--headless','--path',game,'--audio-driver','Dummy','--script',script],marker='BIZIGAI_GODOT_PASS')
    run('graphical',['xvfb-run','-a',str(godot),'--path',game,'--rendering-method','gl_compatibility','--audio-driver','Dummy','--script',script,'--','--capture'],marker='BIZIGAI_GODOT_PASS')
    from PIL import Image,ImageStat
    for world in ['lurga','elur']:
        for tier in ['orbital','surface']:
            path=ROOT/'docs/images/bizigai_pack'/('%s_%s.png'%(world,tier))
            with Image.open(path) as image:
                if image.size!=(1600,900): raise ValueError('Wrong capture dimensions')
                if max(ImageStat.Stat(image.convert('RGB')).stddev)<12: raise ValueError('Blank capture')
    print('BIZIGAI_RUNTIME_PASS import=headless+graphical captures=4')

if __name__=='__main__': main()
