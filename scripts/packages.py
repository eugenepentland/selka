#!/usr/bin/env python3
"""Build offline local dependencies from explicit namespaces and content-locked files."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile

import navigate

MAX_BYTES = 16 * 1024 * 1024


def package_files(package, base):
    name = package['name']
    if not re.fullmatch('[A-Za-z_][A-Za-z_0-9]*', name) or name.startswith('std_'):
        raise ValueError('invalid or reserved package namespace: ' + name)
    root = (base / package['root']).resolve(strict=True)
    inventory = navigate.sources(root)
    if not inventory:
        raise ValueError('empty dependency: ' + name)
    for path in inventory:
        if path != name + '.my' and not path.startswith(name + '/'):
            raise ValueError('dependency source must declare its package namespace: ' + path)
    return root, inventory


def lock(config_path, output):
    config = json.loads(config_path.read_text())
    packages, names = [], set()
    for package in config['packages']:
        if package['name'] in names:
            raise ValueError('duplicate package namespace: ' + package['name'])
        names.add(package['name'])
        root, inventory = package_files(package, config_path.parent)
        # Absolute local roots are explicit and transport-free; relocation requires re-locking.
        packages.append({'name': package['name'], 'root': str(root), 'files': inventory})
    manifest = {'version': 'package-lock-v1', 'packages': packages}
    output.write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def snapshot(entry, lock_path, directory):
    manifest = json.loads(navigate.bounded_read(lock_path, MAX_BYTES))
    if manifest.get('version') != 'package-lock-v1':
        raise ValueError('unsupported package lock')
    app_root = entry.parent.resolve()
    app_files = navigate.sources(app_root)
    if entry.name not in app_files:
        raise ValueError('entry is absent from application source inventory')
    inventories = [(app_root, app_files)]
    names = set()
    for package in manifest['packages']:
        if package['name'] in names:
            raise ValueError('duplicate or incompatible package namespace: ' + package['name'])
        names.add(package['name'])
        root, actual = package_files(package, lock_path.parent)
        if actual != package['files']:
            raise ValueError('locked dependency changed: ' + package['name'])
        inventories.append((root, actual))
    used, total = set(), 0
    for root, inventory in inventories:
        for relative, expected in inventory.items():
            path = PurePosixPath(relative)
            if path.is_absolute() or '..' in path.parts or relative in used:
                raise ValueError('duplicate or invalid module path: ' + relative)
            if path.name.startswith('std_'):
                raise ValueError('application/dependency cannot replace a standard module: ' + relative)
            used.add(relative)
            data = navigate.bounded_read(root / relative, MAX_BYTES - total)
            total += len(data)
            if hashlib.sha256(data).hexdigest() != expected:
                raise ValueError('source changed during package snapshot: ' + relative)
            destination = directory / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
    copy_project_config(app_root, directory)
    return manifest


def copy_project_config(app_root, directory):
    """Mirror the nearest mylang.json into the staged application root.

    A configuration in the entry directory brings its relative policy along so
    the compiler's own discovery and enforcement run against the locked
    snapshot. An ancestor configuration is still copied, but a relative policy
    that would escape the staged root is deliberately left out: the compiler
    then reports a missing required policy instead of silently skipping it.
    """
    for base in (app_root, *app_root.parents):
        config = base / 'mylang.json'
        if not config.is_file():
            continue
        raw = navigate.bounded_read(config, MAX_BYTES)
        (directory / 'mylang.json').write_bytes(raw)
        if base != app_root:
            return
        try:
            document = json.loads(raw)
        except ValueError:
            return
        if not isinstance(document, dict):
            return
        policy = document.get('import_policy')
        if not isinstance(policy, str) or not policy:
            return
        candidate = PurePosixPath(policy)
        if candidate.is_absolute():
            return
        if '..' in candidate.parts:
            return
        target = base / policy
        if not target.is_file():
            return
        destination = directory / policy
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(navigate.bounded_read(target, MAX_BYTES))
        return


def run(entry, lock_path, compiler, action, receipt_path=None):
    compiler = compiler.resolve()
    compiler_hash = navigate.compiler_identity(compiler)
    with tempfile.TemporaryDirectory(prefix='mylang-packages-') as temporary:
        stage = Path(temporary)
        manifest = snapshot(entry.resolve(), lock_path.resolve(), stage)
        staged_entry = stage / entry.name
        dependencies = subprocess.run([str(compiler), 'project-dependencies', str(staged_entry)],
                                      capture_output=True, text=True, timeout=60)
        if dependencies.returncode:
            return dependencies
        receipt = {'version': 'package-build-v1', 'lock_sha256': navigate.digest(manifest),
                   'compiler_sha256': compiler_hash, 'dependencies': json.loads(dependencies.stdout)}
        # `run-project` reports the entry point's int result only on request.
        reporting = ['--print-result'] if action == 'run-project' else []
        result = subprocess.run([str(compiler), action, str(staged_entry), *reporting],
                                capture_output=True, text=True, timeout=60)
        if navigate.compiler_identity(compiler) != compiler_hash:
            raise ValueError('compiler changed during package build')
        if receipt_path is not None and result.returncode == 0:
            receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    locking = commands.add_parser('lock')
    locking.add_argument('config', type=Path)
    locking.add_argument('--output', type=Path, required=True)
    building = commands.add_parser('build')
    building.add_argument('entry', type=Path)
    building.add_argument('--lock', type=Path, required=True)
    building.add_argument('--compiler', type=Path, default=Path(__file__).resolve().parents[1] / 'zig-out/bin/mylang')
    building.add_argument('--command', choices=['check-project', 'run-project', 'index-project', 'emit-project-qbe'], default='check-project')
    building.add_argument('--receipt', type=Path)
    args = parser.parse_args()
    try:
        if args.action == 'lock':
            lock(args.config.resolve(), args.output)
            return 0
        result = run(args.entry, args.lock, args.compiler, args.command, args.receipt)
        print(result.stdout, end='')
        import sys
        print(result.stderr, end='', file=sys.stderr)
        return result.returncode
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        import sys
        print('packages: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
