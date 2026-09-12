#!/usr/bin/env python3
"""Inventario local de un commit Git: lee blobs versionados, nunca partidas o untracked.

La inspección estructural NO acredita revisión semántica, ejecución ni paridad.
Sólo biblioteca estándar; no red, checkout, submódulos, LFS ni escrituras remotas.
"""
from __future__ import annotations

import argparse
import ast
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
from typing import Any

MAX_TOTAL_BYTES = 512 * 1024 * 1024


class InventoryError(RuntimeError):
    """Fallo local sin volcar archivos ni credenciales."""


def git(repo: Path, *args: str, input_data: bytes | None = None) -> bytes:
    env = os.environ.copy()
    for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE'):
        env.pop(key, None)
    env.update(GIT_TERMINAL_PROMPT='0', GIT_NO_LAZY_FETCH='1',
               GIT_NO_REPLACE_OBJECTS='1', GIT_OPTIONAL_LOCKS='0',
               GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
    try:
        result = subprocess.run(
            ['git', '-c', 'protocol.allow=never', '-C', str(repo), *args],
            input=input_data, capture_output=True, timeout=120, env=env, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise InventoryError('No se pudo ejecutar la lectura local de Git.') from exc
    if result.returncode:
        raise InventoryError('Git no pudo leer el commit local completo; no se descargan objetos ausentes.')
    return result.stdout


def inspect_blob(path: str, data: bytes) -> dict[str, Any]:
    result: dict[str, Any] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    suffix = Path(path).suffix.lower()
    try:
        source = data.decode('utf-8')
        if '\0' in source:
            raise ValueError('binary')
    except (UnicodeError, ValueError):
        source = None
    result['kind'] = 'text' if source is not None else 'binary'
    if source is not None:
        result['lines'] = len(source.splitlines())
        result['references'] = sorted(set(re.findall(r'res://[^\s\"\'\)\],]+', source)))
        if data.startswith(b'version https://git-lfs.github.com/spec/v1\n'):
            result['kind'] = 'lfs-pointer-not-downloaded'
        if suffix == '.py':
            try:
                tree = ast.parse(source, filename=path)
                result['python_syntax'] = 'valid'
                result['symbols'] = [node.name for node in tree.body
                                     if isinstance(node, (ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef))]
            except SyntaxError:
                result['python_syntax'] = 'invalid'
        elif suffix in {'.gd', '.gdshader'}:
            result['symbols'] = re.findall(r'(?m)^(?:static\s+)?(?:func|class_name|shader_type)\s+([A-Za-z_][A-Za-z_0-9]*)', source)
        elif suffix == '.json':
            try:
                def invalid_constant(_value: str) -> None:
                    raise ValueError('non-finite')
                value = json.loads(source, parse_constant=invalid_constant)
                result['json_syntax'] = 'valid'
                result['json_type'] = type(value).__name__
                if isinstance(value, dict):
                    result['json_keys'] = sorted(value)
                elif isinstance(value, list):
                    result['json_items'] = len(value)
            except (ValueError, RecursionError):
                result['json_syntax'] = 'invalid'
    if suffix == '.glb':
        result['glb'] = inspect_glb(data)
    elif suffix == '.blend':
        result['blend_header'] = (data[:12].decode('ascii', 'replace')
                                  if data.startswith(b'BLENDER') else 'compressed-or-unrecognized')
    elif suffix == '.png' and data.startswith(b'\x89PNG\r\n\x1a\n') and len(data) >= 24:
        result['image_size'] = list(struct.unpack('>II', data[16:24]))
    return result


def inspect_glb(data: bytes) -> dict[str, Any]:
    try:
        magic, version, length = struct.unpack_from('<4sII', data)
        if magic != b'glTF' or version != 2 or length != len(data):
            raise ValueError('header')
        offset = 12
        document = None
        chunks = 0
        while offset < length:
            size, kind = struct.unpack_from('<II', data, offset)
            offset += 8
            if size % 4 or offset + size > length:
                raise ValueError('chunk')
            if chunks == 0 and kind != 0x4E4F534A:
                raise ValueError('first chunk')
            if kind == 0x4E4F534A:
                if document is not None:
                    raise ValueError('duplicate JSON')
                document = json.loads(data[offset:offset + size].decode('utf-8'))
            offset += size
            chunks += 1
        if offset != length or not isinstance(document, dict):
            raise ValueError('document')
        uris = [x.get('uri') for key in ('buffers', 'images')
                for x in document.get(key, []) if isinstance(x, dict) and x.get('uri')]
        return {'structure': 'valid', 'chunks': chunks,
                'meshes': len(document.get('meshes', [])), 'nodes': len(document.get('nodes', [])),
                'external_uris': sum(not str(uri).startswith('data:') for uri in uris)}
    except (ValueError, TypeError, KeyError, UnicodeError, struct.error, RecursionError):
        return {'structure': 'invalid'}


def inventory(repo: Path, revision: str = 'HEAD') -> dict[str, Any]:
    if (not re.fullmatch(r'[A-Za-z0-9_./-]+', revision) or revision.startswith('-')
            or '..' in revision):
        raise InventoryError('Referencia local no válida.')
    sha = git(repo, 'rev-parse', '--verify', '--end-of-options', revision + '^{commit}').decode().strip()
    tree_sha = git(repo, 'rev-parse', '--verify', sha + '^{tree}').decode().strip()
    if not re.fullmatch(r'[0-9a-f]{40,64}', sha):
        raise InventoryError('Identificador de commit no válido.')
    records = git(repo, 'ls-tree', '-r', '-l', '-z', '--full-tree', sha).split(b'\0')
    entries: list[dict[str, Any]] = []
    for record in records:
        if not record:
            continue
        try:
            metadata, raw_path = record.split(b'\t', 1)
            mode, kind, oid, size = metadata.decode('ascii').split()
            path = raw_path.decode('utf-8', 'surrogateescape')
            entries.append({'path': path, 'mode': mode, 'object_type': kind,
                            'git_object': oid, 'bytes': int(size) if size != '-' else 0})
        except (ValueError, UnicodeError) as exc:
            raise InventoryError('Árbol Git incompleto o no interpretable.') from exc
    total = sum(x['bytes'] for x in entries)
    if total > MAX_TOTAL_BYTES:
        raise InventoryError('Árbol superior al límite de lectura; no se presenta un inventario parcial como completo.')
    blobs = [x for x in entries if x['object_type'] == 'blob']
    batch = git(repo, 'cat-file', '--batch', input_data=''.join(x['git_object'] + '\n' for x in blobs).encode())
    offset = 0
    for entry in blobs:
        end = batch.find(b'\n', offset)
        header = batch[offset:end].decode('ascii').split()
        if end == -1 or header != [entry['git_object'], 'blob', str(entry['bytes'])]:
            raise InventoryError('Blob ausente o respuesta Git no verificable.')
        start = end + 1
        stop = start + entry['bytes']
        if stop >= len(batch) or batch[stop:stop + 1] != b'\n':
            raise InventoryError('Contenido Git truncado.')
        data = batch[start:stop]
        if entry['mode'] == '120000':
            # Hash the link target text, never resolve or follow it.
            entry.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), kind='symlink-not-followed')
        else:
            entry.update(inspect_blob(entry['path'], data))
        offset = stop + 1
    if offset != len(batch):
        raise InventoryError('Contenido Git adicional no esperado.')
    for entry in entries:
        if entry['object_type'] != 'blob':
            entry['kind'] = 'gitlink-not-expanded'
    return {'schema_version': 1, 'source_commit': sha, 'source_tree': tree_sha,
            'coverage': {'tracked_entries': len(entries), 'blobs_read': len(blobs),
                         'all_tracked_blobs_read': len(blobs) == len(entries),
                         'semantic_review': False, 'runtime_validation': False},
            'total_bytes': total, 'kinds': dict(sorted(Counter(x['kind'] for x in entries).items())),
            'files': entries}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path('.'))
    parser.add_argument('--revision', default='HEAD')
    args = parser.parse_args()
    try:
        print(json.dumps(inventory(args.repo, args.revision), ensure_ascii=True, indent=2))
        return 0
    except InventoryError as exc:
        print(f'Error: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
