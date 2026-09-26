#!/usr/bin/env python3
"""Compare scalar receiver loan traffic using preserved Debug compiler installs."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    result = []
    cases = [('scalar', HERE / 'scalar.my', 0, '495000\n'),
             ('regressions', ROOT / 'tests/lang/rc_read_loans.my', 0, ''),
             ('trap', HERE / 'trap.my', 1, ''),
             ('callback', HERE / 'callback.my', 0, '7\n')]
    for side, supplied in [('before', args.before), ('after', args.after)]:
        compiler = supplied.resolve()
        for backend in ['qbe', 'llvm']:
            for name, source, status, stdout in cases:
                binary = work / f'{side}-{name}-{backend}'
                cmd = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(source),
                       '--rc-runtime=stats', '--backend', backend, '--mode', 'ReleaseFast',
                       '--cache-dir=' + str(work / ('cache-' + side)), '-o', str(binary)]
                if backend == 'qbe':
                    cmd += ['--qbe=' + str(compiler.parent / 'qbe')]
                else:
                    cmd += ['--llvm-opt', '3', '--lto']
                subprocess.run(cmd, cwd=ROOT, check=True)
                run = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True, timeout=120)
                rows = [json.loads(line.split(' ', 1)[1]) for line in run.stderr.splitlines()
                        if line.startswith('MYLANG_RC_COUNTS ')]
                assert run.returncode == status and run.stdout == stdout and len(rows) == 1, (cmd, run.returncode, run.stdout, run.stderr)
                count = rows[0]
                assert not count['saturated'] and count['heap_allocate'] == count['retire'], count
                assert count['owner_acquire'] + count['heap_allocate'] == count['owner_release'], count
                assert count['hold_acquire'] == count['hold_release'], count
                result.append(dict(side=side, backend=backend, name=name, command=cmd,
                                   compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                                   source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                                   binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                                   exit=run.returncode, stdout=run.stdout, stderr=run.stderr, counts=count))
                args.output.write_text(json.dumps(result, indent=2) + '\n')
                print(side, backend, name, count, flush=True)
    for backend in ['qbe', 'llvm']:
        old = next(x['counts'] for x in result if x['backend'] == backend and x['side'] == 'before' and x['name'] == 'scalar')
        new = next(x['counts'] for x in result if x['backend'] == backend and x['side'] == 'after' and x['name'] == 'scalar')
        assert old['owner_acquire'] > new['owner_acquire']
        assert old['owner_acquire'] - new['owner_acquire'] == old['owner_release'] - new['owner_release']


if __name__ == '__main__':
    main()
