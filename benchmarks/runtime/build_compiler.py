#!/usr/bin/env python3
"""Build a compiler and bind its installed bytes to a checked Git source snapshot."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

SCHEMA = 'mylang-runtime-compiler-build-v1'
INPUTS = ('src', 'vendor/qbe', 'docs', 'build.zig', 'build.zig.zon', '.zigversion', '.qbeversion')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def snapshot(root, revision):
    if re.fullmatch(r'[0-9a-f]{40}', revision) is None:
        raise ValueError('source revision must be a full Git commit SHA')
    subprocess.run(['git', '-C', str(root), 'cat-file', '-e', revision + '^{commit}'], check=True)
    subprocess.run(['git', '-C', str(root), 'diff', '--exit-code', revision, '--', *INPUTS], check=True,
                   capture_output=True)
    names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--', *INPUTS], text=True).splitlines()
    untracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--others', '--exclude-standard',
                                         '--', *INPUTS], text=True).splitlines()
    if untracked:
        raise ValueError('untracked compiler inputs: ' + ', '.join(untracked))
    return {name: digest(root / name) for name in names}


def validate_receipt(receipt, compiler, artifacts=False):
    if receipt.get('schema') != SCHEMA or receipt.get('status') != 'complete':
        raise ValueError('missing complete compiler build receipt')
    if re.fullmatch(r'[0-9a-f]{40}', receipt.get('source_revision', '')) is None:
        raise ValueError('invalid receipt source revision')
    if receipt.get('sources_before') != receipt.get('sources_after') or not receipt.get('sources_before'):
        raise ValueError('compiler sources changed during build')
    if receipt.get('exit_status') != 0 or receipt.get('compiler_sha256') != digest(compiler):
        raise ValueError('compiler differs from recorded successful build')
    if 'compiler_optimize' in receipt:
        mode = receipt['compiler_optimize']
        if mode not in ('Debug', 'ReleaseFast') or '-Doptimize=' + mode not in receipt.get('command', []):
            raise ValueError('compiler optimization mode differs from recorded command')
    if artifacts:
        if snapshot(Path(receipt['source_root']), receipt['source_revision']) != receipt['sources_after']:
            raise ValueError('compiler sources differ from receipt')
        for path, expected in receipt['installed_assets'].items():
            if digest(path) != expected:
                raise ValueError('installed compiler asset differs from receipt: ' + path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--zig', default='zig')
    parser.add_argument('--optimize', choices=('Debug', 'ReleaseFast'), default='ReleaseFast',
                        help='compiler build mode; guest build modes remain separately recorded')
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root, work = args.source_root.resolve(), args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    (work / 'tmp').mkdir(exist_ok=True)
    before = snapshot(root, args.source_revision)
    command = [str(root / 'scripts/build-slot.sh'), 'build', args.zig, 'build', '-Doptimize=' + args.optimize,
               '-Dcompiler-only=true', '-j2', '--summary', 'all']
    environment = {**os.environ, 'TMPDIR': str(work / 'tmp'), 'ZIG_LOCAL_CACHE_DIR': str(work / 'compiler-zig-local'),
                   'ZIG_GLOBAL_CACHE_DIR': str(work / 'compiler-zig-global')}
    started = datetime.now(timezone.utc).isoformat()
    log = work / 'compiler-build.log'
    with log.open('w') as output:
        done = subprocess.run(command, cwd=root, env=environment, stdout=output, stderr=subprocess.STDOUT)
    if done.returncode:
        raise RuntimeError('compiler build failed; see ' + str(log))
    after = snapshot(root, args.source_revision)
    if before != after:
        raise ValueError('compiler sources changed during build')
    compiler = root / 'zig-out/bin/mylang'
    assets = [root / 'zig-out/bin/qbe', *sorted((root / 'zig-out/lib/mylang-runtime').rglob('*'))]
    receipt = {'schema': SCHEMA, 'status': 'complete', 'source_root': str(root), 'source_revision': args.source_revision,
               'sources_before': before, 'sources_after': after, 'compiler_path': str(compiler), 'compiler_sha256': digest(compiler),
               'command': command, 'compiler_optimize': args.optimize,
               'exit_status': done.returncode, 'build_environment': {key: environment[key] for key in
                   ('TMPDIR', 'ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR')},
               'installed_assets': {str(path): digest(path) for path in assets if path.is_file()},
               'build_log': {'path': str(log), 'sha256': digest(log)},
               'started_utc': started, 'finished_utc': datetime.now(timezone.utc).isoformat(),
               'provenance_limit': 'Local build receipt records checked source bytes and subprocess outputs; it is not an independently attested reproducible build.'}
    zig = Path(shutil.which(args.zig) or args.zig).resolve()
    receipt['zig'] = {'path': str(zig), 'sha256': digest(zig),
                      'version': subprocess.check_output([str(zig), 'version'], text=True).strip()}
    receipt['build_wrapper_sha256'] = digest(root / 'scripts/build-slot.sh')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2) + '\n')
    print('PASS compiler build receipt: ' + str(args.output))


if __name__ == '__main__':
    main()
