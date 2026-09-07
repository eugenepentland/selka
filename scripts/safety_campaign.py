#!/usr/bin/env python3
"""Retain reproducible differential and malformed-source campaigns against a pinned CLI."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess
import tempfile
import time

import safety_interactions

ROOT = Path(__file__).resolve().parents[1]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def templates(rng):
    a, b = rng.randrange(-1000, 1001), rng.randrange(-1000, 1001)
    concrete = f'fn add(a:i64,b:i64)->i64{{return a+b;}}fn main()->i64{{return add({a},{b});}}'
    generic = f'fn add<T:copy>(a:T,b:T)->T{{return a;}}fn main()->i64{{return add::<i64>({a},{b})+{b};}}'
    # Exercise allocation, arena exit, fallible propagation, snapshots, pools and views.
    arena = (ROOT / 'examples/arenas.my').read_text().replace('append_buffer<Change>(buffer, 8)',
                                                            f'append_buffer<Change>(buffer, {a})')
    return [(concrete, a + b, 'concrete-arithmetic'), (generic, a + b, 'generic-copy'),
            (arena, 42 + a, 'arena-pool-buffer-result'), *safety_interactions.templates(rng)]


def execute(compiler, source, path, action):
    path.write_text(source)
    started = time.monotonic()
    try:
        flags = ['--max-steps=100000', '--max-frames=128'] if action == 'run' else []
        result = subprocess.run([str(compiler), action, str(path), '--diagnostics=json', *flags],
                                capture_output=True, text=True, timeout=15)
        return {'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr,
                'seconds': time.monotonic() - started}
    except subprocess.TimeoutExpired:
        return {'exit': None, 'stdout': '', 'stderr': 'timeout', 'seconds': time.monotonic() - started}


def malformed_failure(result):
    # Both valid and invalid mutations are allowed; host/internal failures are not.
    return result['exit'] not in (0, 1) or len(result['stderr']) > 1024 * 1024


def minimize(compiler, source, path):
    # Bounded delta debugging for crash/timeout/host failures, never assertion mismatches.
    granularity = 2
    attempts = 0
    while len(source) > 1 and attempts < 32:
        width = max(1, len(source) // granularity)
        reduced = False
        for start in range(0, len(source), width):
            candidate = source[:start] + source[start + width:]
            attempts += 1
            if malformed_failure(execute(compiler, candidate, path, 'check')):
                source, reduced = candidate, True
                break
            if attempts >= 32:
                break
        if not reduced:
            if granularity >= len(source):
                break
            granularity = min(len(source), granularity * 2)
    return source


def campaign(compiler, seed, rounds, output):
    compiler = Path(compiler).resolve()
    identity = digest(compiler.read_bytes())
    rng = random.Random(seed)
    rows = []
    with tempfile.TemporaryDirectory(prefix='mylang-safety-') as temporary:
        path = Path(temporary) / 'campaign.my'
        for _ in range(rounds):
            for source, expected, family in templates(rng):
                result = execute(compiler, source, path, 'run')
                valid = result['exit'] == 0 and result['stdout'] == str(expected) + '\n'
                rows.append({'family': family, 'source': source, 'source_sha256': digest(source.encode()),
                             'expected': expected, 'passed': valid, 'result': result})
                for mutation in range(3):
                    start = rng.randrange(len(source))
                    end = min(len(source), start + rng.randrange(1, 12))
                    text = source[:start] + rng.choice(['', '?', 'return ', '}', 'borrow mut ', '\x00']) + source[end:]
                    result = execute(compiler, text, path, 'check')
                    failed = malformed_failure(result)
                    row = {'family': family + '-mutation', 'mutation': mutation, 'source': text,
                           'source_sha256': digest(text.encode()), 'passed': not failed, 'result': result}
                    if failed:
                        row['minimized_source'] = minimize(compiler, text, path)
                    rows.append(row)
    if digest(compiler.read_bytes()) != identity:
        raise ValueError('compiler changed during campaign')
    report = {'version': 'safety-campaign-v1', 'seed': seed, 'rounds': rounds,
              'compiler_sha256': identity, 'generator_sha256': digest(Path(__file__).read_bytes()),
              'template_sha256': digest((ROOT / 'examples/arenas.my').read_bytes()),
              'interaction_generator_sha256': digest(Path(safety_interactions.__file__).read_bytes()),
              'coverage': {'kind': 'case-families-not-code-coverage', 'families': sorted({r['family'] for r in rows})},
              'passed': all(r['passed'] for r in rows), 'cases': rows}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT / 'zig-out/bin/mylang')
    parser.add_argument('--seed', type=int, default=20260907)
    parser.add_argument('--rounds', type=int, default=20)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.rounds <= 1000:
        parser.error('rounds must be 1..1000')
    report = campaign(args.compiler, args.seed, args.rounds, args.output)
    print(json.dumps({'passed': report['passed'], 'cases': len(report['cases']), 'report': str(args.output)}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
