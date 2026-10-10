#!/usr/bin/env python3
"""Confirm all M0 counterfactuals, checking stdout and generated files on every run."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import time

from quiet import quiet

ROOT = Path(__file__).resolve().parents[3]
AREA = Path(__file__).resolve().parents[1]


def execute(binary, args, cwd, output):
    if output and output.exists():
        shutil.rmtree(output)
    start = time.perf_counter_ns()
    proc = subprocess.run(['taskset', '-c', '10', str(binary), *args], cwd=cwd,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600)
    elapsed = (time.perf_counter_ns() - start) / 1e6
    digest = hashlib.sha256(proc.stdout)
    if output:
        for path in sorted(output.rglob('*')):
            if path.is_file():
                digest.update(str(path.relative_to(output)).encode() + path.read_bytes())
    if proc.returncode:
        raise RuntimeError(f'{binary}: exit {proc.returncode}: {proc.stderr[-2000:]!r}')
    return elapsed, digest.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=9)
    parser.add_argument('--warmups', type=int, default=2)
    args = parser.parse_args()
    groups = []
    for name in ('lox', 'eda-rds3+flat', 'eda-labstation'):
        directory = args.work.resolve() / name
        cpu8 = json.loads((directory / 'result.json').read_text())
        for case, data in cpu8['cases'].items():
            rejected = {label: {'status': variant['status'], 'output_matches_real': variant['output_matches_real']}
                        for label, variant in data['variants'].items()
                        if variant['status'] or not variant['output_matches_real']}
            if 'real' in rejected or 'base' in rejected:
                raise RuntimeError(f'invalid production control: {case}')
            if name == 'lox' and rejected:
                raise RuntimeError(f'invalid Lox exit probe: {case}: {rejected}')
            argv = data['args']
            output = Path(argv[argv.index('--out-dir') + 1]) if '--out-dir' in argv else None
            if output and not output.is_relative_to(ROOT):
                raise RuntimeError('counterfactual output must be owned')
            cwd = ROOT / ('.mylang-cache/lox' if name == 'lox' else '.mylang-cache/eda-src')
            binaries = {label: directory / ('real' if label == 'real' else label + '.exe')
                        for label in data['variants'] if label not in rejected}
            groups.append((name + ':' + case, argv, cwd, output, binaries, rejected))
    result = {'cpu': 10, 'rounds': args.rounds, 'warmups': args.warmups, 'groups': {}}
    rng = random.Random(20261009)
    with quiet():
        result['load_start'] = os.getloadavg()
        for group, argv, cwd, output, binaries, rejected in groups:
            expected = execute(binaries['real'], argv, cwd, output)[1]
            samples = {label: [] for label in binaries}
            for round_index in range(args.rounds + args.warmups):
                order = list(binaries)
                rng.shuffle(order)
                for label in order:
                    ms, digest = execute(binaries[label], argv, cwd, output)
                    if digest != expected:
                        raise RuntimeError(f'output mismatch: {group}/{label}, round {round_index}')
                    if round_index >= args.warmups:
                        samples[label].append(ms)
            medians = {label: statistics.median(values) for label, values in samples.items()}
            result['groups'][group] = {'output_sha256': expected, 'all_outputs_match': True, 'rejected_cpu8_variants': rejected,
                'arms': {label: {'median_ms': medians[label], 'ratio_to_base': medians[label] / medians['base'],
                                 'ratio_to_real': medians[label] / medians['real'], 'samples_ms': values}
                         for label, values in samples.items()}}
            print(group, {label: round(value / medians['base'], 3) for label, value in medians.items()}, flush=True)
            args.out.write_text(json.dumps(result, indent=1) + '\n')
        result['load_end'] = os.getloadavg()
        result['complete'] = True
        args.out.write_text(json.dumps(result, indent=1) + '\n')


if __name__ == '__main__':
    main()
