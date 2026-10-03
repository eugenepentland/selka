#!/usr/bin/env python3
"""Build one immutable table read arm with a frozen compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--name', required=True)
    p.add_argument('--runtime', choices=['rc', 'gc'], required=True)
    a = p.parse_args()
    source, work, compiler = a.source.resolve(), a.work.resolve(), a.compiler.resolve()
    repo = Path(__file__).resolve().parents[2]
    work.joinpath('bin').mkdir(parents=True, exist_ok=True)
    work.joinpath('tmp').mkdir(exist_ok=True)
    hashes = {f.name: sha(f) for f in sorted(source.glob('*.my'))}
    compiler_hash = sha(compiler)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    env['TMPDIR'] = str(work / 'tmp')
    receipt = {'source': str(source), 'source_sha256': hashes,
               'compiler': str(compiler), 'compiler_sha256': compiler_hash,
               'runtime': a.runtime, 'binaries': {}, 'commands': []}
    for backend in ['llvm', 'qbe']:
        key = f'{a.name}-{backend}' if a.runtime == 'rc' else f'{a.name}-gc-{backend}'
        binary = work / 'bin' / key
        assert not binary.exists(), f'refusing to replace an existing binary: {binary}'
        cmd = [str(repo / 'scripts/build-slot.sh'), 'build', str(compiler), 'build',
               str(source / 'main.my'), '--project', '--backend', backend,
               f'--{a.runtime}-runtime', '--keep-symbols', '--cache-dir',
               str(work / f'cache-{key}'), '-o', str(binary)]
        if backend == 'llvm':
            cmd += ['--llvm-opt', '3', '--lto']
        log = work / f'build-{key}.log'
        with log.open('w') as out:
            result = subprocess.run(cmd, cwd=repo, env=env, stdout=out,
                                    stderr=subprocess.STDOUT)
        row = {'command': cmd, 'TMPDIR': env['TMPDIR'], 'status': result.returncode,
               'log': str(log)}
        receipt['commands'].append(row)
        assert result.returncode == 0, log
        manifest = binary.with_name(binary.name + '.qbe-manifest.json')
        build = json.loads(manifest.read_text())
        receipt['binaries'][key] = {'path': str(binary), 'sha256': sha(binary),
                                  'manifest_sha256': sha(manifest),
                                  'backend': build['backend'],
                                  'optimization': build['optimization'],
                                  'lto': build['lto'],
                                  'runtime_object': build['runtime_object'],
                                  'runtime_object_sha256': sha(build['runtime_object'])}
        assert {f.name: sha(f) for f in source.glob('*.my')} == hashes
        assert sha(compiler) == compiler_hash
        (work / f'build-{a.name}-{a.runtime}.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print(f'built {key}', flush=True)


if __name__ == '__main__':
    main()
