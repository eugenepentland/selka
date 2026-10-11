#!/usr/bin/env python3
"""Repeat frozen task fixtures; preserve hashes, statuses, counters and stderr."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'experiments/zero-rc-20261011'))
import audit

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--repetitions', type=int, default=100)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    result = {'schema': 'zero-rc-tasks-repetitions-v1', 'runs': [], 'fixtures': {}}
    for variant in ('take', 'exit'):
        for mode in ('release', 'tsan'):
            binary = (args.fixtures / (variant + '-' + mode)).resolve()
            identity = digest(binary)
            result['fixtures'][binary.name] = {'path': str(binary), 'sha256': identity,
                                              'llvm_sha256': digest(str(binary) + '.ll')}
            for iteration in range(args.repetitions):
                name = binary.name + '-' + str(iteration)
                counters = (args.output / ('counts-' + name + '.json')).resolve()
                env = dict(os.environ, MYLANG_THREADS='8', MYL_CORE_LEAKCHECK='1')
                env.pop('MYLANG_COUNTERS', None)
                if mode != 'tsan':
                    env['MYLANG_COUNTERS'] = str(counters)
                run = subprocess.run([binary], env=env, capture_output=True, timeout=30)
                (args.output / (name + '.stdout')).write_bytes(run.stdout)
                (args.output / (name + '.stderr')).write_bytes(run.stderr)
                assert run.returncode == 0 and not run.stderr, (name, run.returncode, run.stderr)
                assert run.stdout == (b'1110\n' if variant == 'take' else b'0\n'), name
                record = {'fixture': binary.name, 'iteration': iteration, 'status': run.returncode}
                if mode != 'tsan':
                    checked = audit.audit(counters)
                    assert checked['observed_rc_free'] and checked['managed_leak_free'], checked
                    record['audit'] = checked
                result['runs'].append(record)
            assert digest(binary) == identity
            print('pass', binary.name, args.repetitions, flush=True)
    result['summary'] = {'runs': len(result['runs']), 'counted': 2 * args.repetitions,
                         'thread_sanitized': 2 * args.repetitions, 'threads': 8}
    (args.output / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result['summary']), flush=True)
if __name__ == '__main__':
    main()
