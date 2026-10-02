#!/usr/bin/env python3
"""Build the scalar lookup experiment with the frozen audited compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--runtime', choices=['rc', 'gc'], required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    repo = Path(__file__).resolve().parents[2]
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    env['TMPDIR'] = str(work / 'tmp')
    compiler = args.compiler.resolve()
    compiler_sha = sha(compiler)
    commands = []
    for arm in ['control', 'candidate']:
        for backend in ['llvm', 'qbe']:
            key = f'{arm}-{backend}' if args.runtime == 'rc' else f'{arm}-gc-{backend}'
            binary = work / 'bin' / key
            assert not binary.exists(), f'refusing to replace measurement binary: {binary}'
            command = [str(repo / 'scripts/build-slot.sh'), 'build', str(compiler), 'build',
                       str(work / arm / 'lox/benchmarks/lox/ports/mylang/main.my'),
                       '--project', '--backend', backend, f'--{args.runtime}-runtime',
                       '--keep-symbols', '--cache-dir', str(work / f'cache-build-{key}'),
                       '-o', str(binary)]
            if backend == 'llvm':
                command.extend(['--llvm-opt', '3', '--lto'])
            log = work / f'build-{key}.log'
            with log.open('w') as output:
                result = subprocess.run(command, cwd=repo, env=env, stdout=output,
                                        stderr=subprocess.STDOUT)
            commands.append({'key': key, 'command': command, 'TMPDIR': env['TMPDIR'],
                             'status': result.returncode, 'log': str(log)})
            assert result.returncode == 0, log
            commands[-1]['binary_sha256'] = sha(binary)
            manifest_path = work / 'binaries.json'
            manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {
                'binaries': {}, 'binary_sha256': {}, 'source_hashes': {}}
            manifest['compiler'] = str(compiler)
            manifest['compiler_sha256'] = compiler_sha
            manifest['source_hashes'][arm] = {
                p.name: sha(p) for p in
                (work / arm / 'lox/benchmarks/lox/ports/mylang').glob('*.my')}
            manifest['binaries'][key] = str(binary)
            manifest['binary_sha256'][key] = sha(binary)
            manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
            print(f'built {key}', flush=True)
    assert sha(compiler) == compiler_sha
    (work / f'build-{args.runtime}-commands.json').write_text(json.dumps(
        {'compiler': str(compiler), 'compiler_sha256': compiler_sha, 'commands': commands},
        indent=2) + '\n')


if __name__ == '__main__':
    main()
