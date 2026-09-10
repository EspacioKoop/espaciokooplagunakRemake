"""Run the project-pinned Godot against real delivered model files."""
from __future__ import annotations
import os
from pathlib import Path
import re
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/lantegi'
ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
ERROR = re.compile(r'(?m)^\s*(?:SCRIPT ERROR|ERROR|FATAL):')


def run(command, name, marker=None, timeout=300):
    OUT.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([str(x) for x in command], cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    text = ANSI.sub('', result.stdout)
    (OUT / (name + '.log')).write_text(text)
    print(text, flush=True)
    if result.returncode or ERROR.search(text):
        raise RuntimeError(f'{name}: engine/process failure ({result.returncode})')
    if marker and not re.search(marker, text):
        raise RuntimeError(name + ': success marker missing')
    return text


def main():
    godot = ROOT / '.toolchain/godot'
    if not godot.is_file():
        raise SystemExit('Run python tools/bootstrap.py first')
    run([godot, '--headless', '--editor', '--path', 'game', '--quit'], 'godot-import', timeout=600)
    log = run([godot, '--headless', '--path', 'game', '--script', '../tests/lantegi_pack/test_import.gd'],
              'godot-tests', r'LANTEGI_GODOT_TESTS checks=[1-9]\d* failures=0')
    run(['xvfb-run', '-a', godot, '--path', 'game', '--rendering-method', 'gl_compatibility',
         '--audio-driver', 'Dummy', '--resolution', '1600x900',
         'res://asset_lab/lantegi_pack/viewer.tscn', '--', '--capture-lantegi'],
        'godot-capture', r'LANTEGI_CAPTURE_PASS')
    from PIL import Image
    picture = OUT / 'godot_viewer.png'
    image = Image.open(picture).convert('RGB')
    if image.size != (1600, 900) or max(image.getextrema()[0]) - min(image.getextrema()[0]) < 30:
        raise RuntimeError('Invalid or blank screenshot')
    target = ROOT / 'docs/images/lantegi_pack/godot_viewer.png'
    target.write_bytes(picture.read_bytes())
    print('LANTEGI_RUNTIME_PASS')


if __name__ == '__main__':
    main()
