#!/usr/bin/env python3
"""Run named guest Boolean laws over seeded integer domains and retain counterexamples.

An experiment, not part of mylang: see docs/experiments/guest-laws.md.
"""
import argparse
import json
from pathlib import Path
import random

import test_project


def invoke(compiler, entry, name, arguments):
    report = test_project.run(compiler, entry, name, {name: {'arguments': arguments, 'expected': True}})
    if len(report['tests']) != 1:
        raise ValueError('law must identify one exported test_ function: ' + name)
    return report['tests'][0], report['snapshot_sha256']


def campaign(compiler, entry, laws, seed, samples):
    rng = random.Random(seed)
    rows = []
    snapshot = None
    for name, domains in sorted(laws.items()):
        for parameter, domain in domains.items():
            if len(domain) != 2 or any(type(n) is not int for n in domain) or domain[0] > domain[1]:
                raise ValueError('invalid integer domain for ' + parameter)
        for sample in range(samples):
            arguments = {key: str(rng.randint(*domain)) for key, domain in sorted(domains.items())}
            outcome, identity = invoke(compiler, entry, name, arguments)
            if snapshot is not None and snapshot != identity:
                raise ValueError('source/compiler snapshot changed during law campaign')
            snapshot = identity
            row = {'law': name, 'sample': sample, 'arguments': arguments, 'outcome': outcome}
            if outcome['status'] in ('failed', 'trap'):
                reduced = dict(arguments)
                attempts = 0
                for parameter, domain in sorted(domains.items()):
                    for target in (0, -1, 1, int(reduced[parameter]) // 2):
                        if not domain[0] <= target <= domain[1] or abs(target) >= abs(int(reduced[parameter])):
                            continue
                        candidate = dict(reduced, **{parameter: str(target)})
                        result, current = invoke(compiler, entry, name, candidate)
                        attempts += 1
                        if current != snapshot:
                            raise ValueError('source changed during counterexample reduction')
                        if result['status'] == outcome['status']:
                            reduced = candidate
                row['reduced_arguments'] = reduced
                row['reduction_attempts'] = attempts
            rows.append(row)
    return {'version': 'guest-laws-v1', 'seed': seed, 'samples_per_law': samples,
            'snapshot_sha256': snapshot, 'evidence_kind': 'sampled-counterexamples-not-proof',
            'passed': bool(rows) and all(r['outcome']['status'] == 'passed' for r in rows), 'cases': rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('entry', type=Path)
    parser.add_argument('--laws', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, default=Path(__file__).resolve().parents[2] / 'zig-out/bin/mylang')
    parser.add_argument('--seed', type=int, default=20260907)
    parser.add_argument('--samples', type=int, default=20)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.samples <= 1000:
        parser.error('samples must be 1..1000')
    report = campaign(args.compiler, args.entry, json.loads(args.laws.read_text()), args.seed, args.samples)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'cases': len(report['cases']), 'output': str(args.output)}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
