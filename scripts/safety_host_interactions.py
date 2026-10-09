#!/usr/bin/env python3
"""Retain generated managed-arena and host-failure cleanup checks against a pinned byte runner."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess
import tempfile
import time

IO = '''


public host func length() -> int effects(host)
public host func byte(index: int) -> u8 effects(host)
public host func put(value: u8) -> int effects(host)
'''

GUEST = '''import io


func main() -> int:
    with arena():
        mut values: int[] = []
        values.append(VALUE)
        _ = io.put(u8(values[0]))
        OPERATION
    return 0
'''


def campaign(runner, seed, rounds, output):
    runner = Path(runner).resolve()
    identity = hashlib.sha256(runner.read_bytes()).hexdigest()
    rng, rows = random.Random(seed), []
    with tempfile.TemporaryDirectory(prefix='safety-host-') as directory:
        root = Path(directory)
        (root / 'io.my').write_text(IO)
        for _ in range(rounds):
            value = rng.randrange(256)
            for mode in ('success', 'provider-failure', 'callback-budget'):
                operation = '_ = io.byte(-1)' if mode == 'provider-failure' else '_ = io.put(0)'
                source = GUEST.replace('VALUE', str(value)).replace('OPERATION', operation)
                (root / 'main.my').write_text(source)
                flags = ['--memory-report', '--max-steps=100000', '--max-runtime-bytes=1000000']
                if mode == 'callback-budget':
                    flags.append('--max-calls=1')
                started = time.monotonic()
                command = [str(runner), '--project', str(root), *flags]
                try:
                    result = subprocess.run(command, input=b'\0\xff', capture_output=True, timeout=15)
                except subprocess.TimeoutExpired as error:
                    result = subprocess.CompletedProcess(command, None, error.stdout or b'', (error.stderr or b'') + b'\ntimeout')
                report = next((json.loads(line) for line in result.stderr.splitlines() if line.startswith(b'{')), None)
                expected = bytes([value, 0]) if mode == 'success' else b''
                passed = (result.returncode == 0 if mode == 'success' else result.returncode == 1)
                passed = passed and result.stdout == expected and report is not None and report['total']['live'] == 0
                passed = passed and report['vm_categories']['guest_backing']['peak'] > 0
                expected_trap = {'provider-failure': b'error[R_HOST_FAILURE]', 'callback-budget': b'error[R_HOST_LIMIT]'}.get(mode)
                if expected_trap:
                    passed = passed and expected_trap in result.stderr
                rows.append({'mode': mode, 'source': source, 'flags': flags, 'passed': passed,
                             'seconds': time.monotonic() - started, 'exit': result.returncode,
                             'stdout_hex': result.stdout.hex(), 'stderr': result.stderr.decode(errors='replace')})
    if hashlib.sha256(runner.read_bytes()).hexdigest() != identity:
        raise ValueError('runner changed during campaign')
    report = {'version': 'host-interaction-campaign-v1', 'seed': seed, 'rounds': rounds,
              'runner_sha256': identity, 'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'provider_source': IO, 'input_hex': '00ff', 'coverage': 'generated-case-families-not-code-coverage',
              'passed': all(row['passed'] for row in rows), 'cases': rows}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=20260907)
    parser.add_argument('--rounds', type=int, default=20)
    args = parser.parse_args()
    if not 1 <= args.rounds <= 1000:
        parser.error('rounds must be 1..1000')
    report = campaign(args.runner, args.seed, args.rounds, args.output)
    print(json.dumps({'passed': report['passed'], 'cases': len(report['cases'])}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
