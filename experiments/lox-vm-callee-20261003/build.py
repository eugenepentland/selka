#!/usr/bin/env python3
"""Build one checked Lox guest with private outputs and full identity receipts."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def hashes(source):
    return {str(p.relative_to(source)): sha(p)
            for p in sorted(source.rglob('*')) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--backend', choices=['llvm', 'qbe'], required=True)
    parser.add_argument('--runtime', choices=['rc', 'gc'], required=True)
    args = parser.parse_args()
    source, compiler, work = [p.resolve() for p in
                              [args.source, args.compiler, args.work]]
    root = Path(__file__).resolve().parents[2]
    work.mkdir(parents=True, exist_ok=True)
    tag = args.backend + '-' + args.runtime
    binary = work / tag
    assert not binary.exists(), 'refuse output overwrite'
    (work / 'tmp').mkdir(exist_ok=True)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    env['TMPDIR'] = str(work / 'tmp')
    before = hashes(source)
    compiler_before = sha(compiler)
    argv = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler),
            'build', str(source / 'main.my'), '--project', '--backend',
            args.backend, '--' + args.runtime + '-runtime', '--keep-symbols',
            '--cache-dir', str(work / ('cache-' + tag)), '-o', str(binary)]
    if args.backend == 'llvm':
        argv += ['--llvm-opt', '3', '--lto']
    row = {'argv': argv, 'cwd': str(root),
           'environment': {'TMPDIR': env['TMPDIR']},
           'source': str(source), 'source_files': before,
           'compiler_sha256': compiler_before,
           'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    with (work / (tag + '.log')).open('wb') as log:
        row['status'] = subprocess.run(argv, cwd=root, env=env,
                                       stdout=log, stderr=log).returncode
    assert row['status'] == 0, row
    row['source_verified_after'] = hashes(source) == before
    row['compiler_verified_after'] = sha(compiler) == compiler_before
    assert row['source_verified_after'] and row['compiler_verified_after']
    manifest = Path(str(binary) + '.qbe-manifest.json')
    doc = json.loads(manifest.read_text())
    row.update(binary=str(binary), binary_sha256=sha(binary),
               manifest_sha256=sha(manifest),
               codegen={k: doc[k] for k in ['backend', 'optimization', 'lto', 'abi']},
               runtime_object=doc['runtime_object'],
               runtime_object_sha256=sha(doc['runtime_object']),
               finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    (work / (tag + '.json')).write_text(json.dumps(row, indent=2) + '\n')
    print(binary, row['binary_sha256'])


if __name__ == '__main__':
    main()
