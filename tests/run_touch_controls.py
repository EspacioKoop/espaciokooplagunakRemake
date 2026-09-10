#!/usr/bin/env python3
"""Exercise real ScreenTouch/ScreenDrag events with isolated local preferences."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=str(ROOT / '.toolchain/godot'))
    parser.add_argument('--graphical', action='store_true')
    parser.add_argument('--screenshot', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='lagunak-touch-') as temporary:
        env = dict(os.environ, XDG_DATA_HOME=temporary, XDG_CONFIG_HOME=temporary)
        if args.screenshot:
            args.screenshot.resolve().parent.mkdir(parents=True, exist_ok=True)
            env['TOUCH_CAPTURE_PATH'] = str(args.screenshot.resolve())
        command = [args.godot, '--audio-driver', 'Dummy', '--path', str(ROOT / 'game'), '--script', str(ROOT / 'tests/test_touch_controls.gd'), '--', '--test']
        if args.graphical:
            if not env.get('DISPLAY'):
                if not shutil.which('xvfb-run'):
                    raise SystemExit('Graphical touch smoke requires DISPLAY or xvfb-run')
                command = ['xvfb-run', '-a', '-s', '-screen 0 1600x900x24'] + command
        else:
            command.insert(1, '--headless')
        result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
        print(result.stdout, end='')
        if result.returncode or re.search(r'(?m)^(?:SCRIPT ERROR|ERROR):', result.stdout) or 'TOUCH_CONTROLS_OK' not in result.stdout:
            raise SystemExit('Touch controls verification failed')
    print('TOUCH_RUNNER_OK')

if __name__ == '__main__':
    main()
