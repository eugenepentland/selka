#!/usr/bin/env python3
"""Qualify the full scalar sweep port under LLVM/QBE and RC/native GC stress."""
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
    a = p.parse_args()
    source, work, compiler = a.source.resolve(), a.work.resolve(), a.compiler.resolve()
    repo = Path(__file__).resolve().parents[2]
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    env['TMPDIR'] = str(work / 'tmp')
    receipt = {'source': str(source),
               'source_sha256': {f.name: sha(f) for f in sorted(source.glob('*.my'))},
               'compiler': str(compiler), 'compiler_sha256': sha(compiler),
               'runs': []}
    for backend in ['llvm', 'qbe']:
        for runtime in ['rc', 'gc']:
            key = f'{backend}-{runtime}'
            cmd = [str(repo / 'scripts/build-slot.sh'), 'build', str(compiler),
                   'test', str(source), '--jobs', '2', '--max-steps', '1000000000',
                   '--timeout-ms', '120000', '--cache-dir',
                   str(work / f'cache-unit-qualified-{key}')]
            cmd += ['--release'] if backend == 'llvm' else ['--mode', 'ReleaseFast']
            cmd += ['--rc-runtime'] if runtime == 'rc' else ['--gc-stress']
            log = work / f'unit-qualified-{key}.log'
            with log.open('w') as out:
                run = subprocess.run(cmd, cwd=repo, env=env, stdout=out,
                                     stderr=subprocess.STDOUT)
            receipt['runs'].append({'command': cmd, 'TMPDIR': env['TMPDIR'],
                                    'status': run.returncode, 'log': str(log),
                                    'log_sha256': sha(log),
                                    'stdout': log.read_text()})
            (work / 'unit-qualified.json').write_text(json.dumps(receipt, indent=2) + '\n')
            assert run.returncode == 0, log
            print(f'PASS {key}', flush=True)
    assert {f.name: sha(f) for f in source.glob('*.my')} == receipt['source_sha256']
    assert sha(compiler) == receipt['compiler_sha256']
    receipt['verified_after'] = True
    (work / 'unit-qualified.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
