"""Run real Godot asset tests in a disposable project, never the live game."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
ERROR = re.compile(r'^\s*(?:SCRIPT ERROR|ERROR|USER ERROR|FATAL(?: ERROR)?|FRONTIER_TEST_FAIL):', re.M)
MAX_LOG_BYTES = 4 * 1024 * 1024
PROJECT = '''config_version=5
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


def execute(command, environment, timeout):
    with tempfile.TemporaryFile() as output:
        result = subprocess.run([str(x) for x in command], env=environment,
            stdout=output, stderr=subprocess.STDOUT, timeout=timeout, check=False)
        output.seek(0)
        raw = output.read(MAX_LOG_BYTES + 1)
    if len(raw) > MAX_LOG_BYTES:
        raise RuntimeError('Godot output exceeds the log limit')
    text = raw.decode('utf-8', errors='replace')
    print(text, flush=True)
    if result.returncode or ERROR.search(ANSI.sub('', text)):
        raise RuntimeError('Godot process failed')
    return text


def decode_result(output):
    marker = 'FRONTIER_GODOT_RESULT '
    lines = [line for line in ANSI.sub('', output).splitlines()
             if line.startswith('FRONTIER_GODOT_RESULT')]
    if len(lines) != 1 or not lines[0].startswith(marker):
        raise RuntimeError('Missing unique definitive Godot test result')
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate result key')
            result[key] = value
        return result
    try:
        result = json.loads(lines[0][len(marker):], object_pairs_hook=pairs)
    except ValueError as error:
        raise RuntimeError('Malformed Godot test result') from error
    if (not isinstance(result, dict) or set(result) != {'checks', 'failures', 'assets', 'passed'}
            or type(result['checks']) is not int or result['checks'] <= 0
            or type(result['assets']) is not int or result['assets'] != 24
            or type(result['failures']) is not list or result['failures'] != []
            or result['passed'] is not True):
        raise RuntimeError('Inconsistent or failed Godot test result')
    return result


def isolated_environment(directory):
    allowed = ('PATH', 'LANG', 'LC_ALL', 'DISPLAY', 'XAUTHORITY', 'LD_LIBRARY_PATH', 'SystemRoot', 'WINDIR')
    env = {key: os.environ[key] for key in allowed if key in os.environ}
    for key in ('HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
        target = directory / key.lower()
        target.mkdir()
        env[key] = str(target)
    env['GODOT_SILENCE_ROOT_WARNING'] = '1'
    return env


def validate_capture(path):
    from PIL import Image
    if not path.is_file() or path.is_symlink() or not 10000 <= path.stat().st_size <= 10 * 1024 * 1024:
        raise RuntimeError('A new capture of the current invocation is required')
    with Image.open(path) as image:
        if image.format != 'PNG' or image.size != (1280, 800):
            raise RuntimeError('Unexpected capture format or dimensions')
        image.verify()
    with Image.open(path) as image:
        image.load()
    return hashlib.sha256(path.read_bytes()).hexdigest()


def publish_file(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Replace atomically on the destination filesystem; preserve old evidence on failure.
    fd, name = tempfile.mkstemp(prefix='.frontier-', dir=destination.parent)
    os.close(fd)
    staging = Path(name)
    try:
        shutil.copyfile(source, staging)
        os.replace(staging, destination)
    finally:
        staging.unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.toolchain/godot')
    parser.add_argument('--capture', action='store_true')
    options = parser.parse_args(argv)
    engine = options.godot.resolve()
    if not engine.is_file():
        raise FileNotFoundError('Run tools/bootstrap.py or supply --godot')
    destination = ROOT / 'game/assets/models/frontier_pack/godot_validation.json'
    with tempfile.TemporaryDirectory(prefix='lagunak-frontier-') as folder:
        isolated = Path(folder)
        (isolated / 'project.godot').write_text(PROJECT, encoding='utf-8')
        shutil.copytree(ROOT / 'game/assets/models/frontier_pack', isolated / 'assets/models/frontier_pack',
            ignore=shutil.ignore_patterns('*.import', '*.log', 'godot_validation.json'))
        shutil.copytree(ROOT / 'game/asset_lab/frontier_pack', isolated / 'asset_lab/frontier_pack')
        (isolated / 'tests').mkdir()
        shutil.copy2(ROOT / 'tests/frontier_pack/test_import.gd', isolated / 'tests/test_import.gd')
        environment = isolated_environment(isolated)
        logs = [execute([engine, '--headless', '--editor', '--path', isolated, '--quit'], environment, 180)]
        logs.append(execute([engine, '--headless', '--path', isolated, '--script', 'res://tests/test_import.gd'], environment, 180))
        result = decode_result(logs[-1])
        result['scope'] = 'Isolated Godot import, animations and real gallery. Not full campaign/network QA.'
        result['capture'] = False
        if options.capture:
            # This path has never existed; committed images cannot satisfy this check.
            image = isolated / 'new-capture.png'
            command = [engine, '--path', isolated, '--rendering-method', 'gl_compatibility',
                       '--audio-driver', 'Dummy', '--resolution', '1280x800', '--',
                       '--frontier-capture=' + str(image)]
            if not environment.get('DISPLAY'):
                if not shutil.which('xvfb-run'):
                    raise RuntimeError('xvfb-run or a display is required for capture')
                command = ['xvfb-run', '-a'] + command
            logs.append(execute(command, environment, 90))
            result['capture_sha256'] = validate_capture(image)
            publish_file(image, ROOT / 'docs/images/frontier_pack/godot_lab.png')
            result['capture'] = True
        report = isolated / 'verified-report.json'
        report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        publish_file(report, destination)
        (destination.parent / 'godot_import.log').write_text('\n'.join(logs), encoding='utf-8')
        print('FRONTIER_GODOT_OK', result['checks'])


if __name__ == '__main__':
    main()
