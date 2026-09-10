#!/usr/bin/env python3
"""Run controls contracts and actual UI events with isolated local preferences."""
import argparse
import os
from pathlib import Path
import subprocess
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=str(ROOT / '.toolchain/godot'))
    parser.add_argument('--graphical', action='store_true', help='Require Xvfb or DISPLAY and test captured movement')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='lagunak-input-') as temp:
        env = dict(os.environ, XDG_DATA_HOME=temp, XDG_CONFIG_HOME=temp)
        for script in ['test_input_controls.gd', 'test_input_ui.gd']:
            command = [args.godot, '--headless', '--path', str(ROOT / 'game'), '--script', str(ROOT / 'tests' / script), '--', '--test']
            if args.graphical and script == 'test_input_ui.gd':
                command.remove('--headless')
                command += ['--require-display']
                if not env.get('DISPLAY'):
                    if not shutil.which('xvfb-run'):
                        raise SystemExit('Graphical input validation requires xvfb-run or DISPLAY')
                    command = ['xvfb-run', '-a', '-s', '-screen 0 1600x900x24'] + command
            result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
            print(result.stdout, end='')
            if result.returncode or 'SCRIPT ERROR:' in result.stdout or '\nERROR:' in result.stdout:
                raise SystemExit(f'{script} failed (exit {result.returncode})')
    print('INPUT_RUNNER_OK')

if __name__ == '__main__':
    main()
