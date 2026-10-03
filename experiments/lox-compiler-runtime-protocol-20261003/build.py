#!/usr/bin/env python3
"""Build isolated Lox source variants and record exact checked compiler inputs."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', type=Path, required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--runtime', choices=['rc', 'gc'], default='rc')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    work, source, compiler = args.work.resolve(), args.source.resolve(), args.compiler.resolve()
    if not args.name.replace('-', '').replace('_', '').isalnum():
        raise ValueError('name must contain letters, digits, hyphens or underscores')
    sources = {p.name: sha(p) for p in sorted(source.glob('*.my'))}
    record = {'compiler': str(compiler), 'compiler_sha256': sha(compiler),
              'source': str(source), 'source_sha256': sources,
              'runtime': args.runtime, 'qbe': str(args.qbe.resolve()),
              'qbe_sha256': sha(args.qbe.resolve()), 'builds': []}
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    env['TMPDIR'] = str(work / 'tmp')
    (work / 'bin').mkdir(exist_ok=True)
    (work / 'tmp').mkdir(exist_ok=True)
    for backend in ['llvm', 'qbe']:
        name = args.name + '-' + backend
        binary = work / 'bin' / name
        if binary.exists():
            raise ValueError(f'refusing to overwrite {binary}')
        argv = [str(repo / 'scripts/build-slot.sh'), 'build', str(compiler),
                'build', str(source / 'main.my'), '--project', '--backend', backend]
        if backend == 'qbe':
            argv += ['--qbe', str(args.qbe.resolve())]
        if backend == 'llvm':
            argv += ['--llvm-opt', '3', '--lto']
        argv += ['--' + args.runtime + '-runtime', '--keep-symbols', '--cache-dir',
                 str(work / ('cache-' + name)), '-o', str(binary)]
        build = {'argv': argv, 'cwd': str(repo), 'environment': {'TMPDIR': env['TMPDIR']},
                 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
        with (work / ('build-' + name + '.log')).open('w') as out:
            result = subprocess.run(argv, cwd=repo, env=env, stdout=out, stderr=subprocess.STDOUT)
        build.update(status=result.returncode,
                     finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
        if result.returncode == 0:
            build['binary_sha256'] = sha(binary)
            manifest = binary.with_suffix(binary.suffix + '.qbe-manifest.json')
            metadata = json.loads(manifest.read_text())
            build['manifest_sha256'] = sha(manifest)
            build['codegen'] = {k: metadata[k] for k in ('backend', 'optimization', 'lto', 'abi')}
            build['runtime_object'] = metadata['runtime_object']
            build['runtime_object_sha256'] = sha(Path(metadata['runtime_object']))
        record['builds'].append(build)
        (work / (args.name + '-build.json')).write_text(json.dumps(record, indent=2) + '\n')
        if result.returncode:
            raise SystemExit(result.returncode)
        print(name, build['binary_sha256'], flush=True)
    assert sha(args.qbe.resolve()) == record['qbe_sha256']
    assert sha(compiler) == record['compiler_sha256']
    assert {p.name: sha(p) for p in sorted(source.glob('*.my'))} == sources


if __name__ == '__main__':
    main()
