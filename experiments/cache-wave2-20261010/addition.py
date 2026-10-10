#!/usr/bin/env python3
"""Measure independent test additions after the paired synthetic edit matrix."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path

import qualify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('benchmarks', type=Path, nargs='+')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=3)
    args = parser.parse_args()
    assert args.rounds > 0
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {'started_utc': datetime.now(timezone.utc).isoformat(),
              'execution_context': {'affinity': sorted(os.sched_getaffinity(0)), 'jobs': 4},
              'method': 'Same restored sources and variant caches as completed synthetic matrices; '
                        'add one independent two-function module with one test and a fresh literal each round; '
                        'force the candidate as an execution/key oracle; remove the module and verify restoration.',
              'inputs': {}, 'records': []}

    def save():
        (output / 'results.json').write_text(json.dumps(report, indent=2) + '\n')

    for benchmark in args.benchmarks:
        benchmark = benchmark.resolve()
        evidence = benchmark / 'results.json'
        previous = json.loads(evidence.read_text())
        assert previous.get('completed_utc'), 'The edit matrix must finish first'
        for compiler in previous['compilers'].values():
            assert qualify.digest(compiler['path']) == compiler['sha256'], 'Compiler changed since edit matrix'
        report['inputs'][str(benchmark)] = {'sha256': qualify.digest(evidence),
                                          'compilers': previous['compilers']}
        for fixture in previous['fixtures']:
            assert fixture.startswith('synthetic-')
            source = benchmark / fixture / 'source'
            added = source / 'independent_test.my'
            assert not added.exists()
            original = next(row for row in previous['records'] if row['fixture'] == fixture and row['phase'] == 'cold')
            variants = [('baseline', 'baseline', 'zlib'), ('candidate-zlib', 'candidate', 'zlib'),
                        ('candidate-none', 'candidate', 'none')]
            seen = {variant: set() for variant, _, _ in variants}
            original_keys = {variant: qualify.keys(next(row for row in previous['records']
                             if row['fixture'] == fixture and row['phase'] == 'cold' and row['variant'] == variant))
                             for variant, _, _ in variants}

            def run(variant, compiler, encoding, phase, sample, force=False):
                row = qualify.run(previous['compilers'][compiler]['path'], source, '.',
                                  benchmark / fixture / ('oracle-' + variant if force else variant), output / 'raw',
                                  f'{fixture}-{variant}-{phase}-{sample}', ['--max-frames=1024'],
                                  ['MYLANG_STAGE_CACHE_COMPRESSION=' + encoding], force)
                row.update(fixture=fixture, variant=variant, encoding=encoding, phase=phase, sample=sample)
                report['records'].append(row)
                save()
                print(json.dumps({k: row[k] for k in ['fixture', 'variant', 'phase', 'sample', 'wall_s', 'counts']}), flush=True)
                return row

            try:
                for sample in range(args.rounds):
                    added.write_text(f'func value() -> int:\n    return {2000000 + sample}\n\n'
                                     'public func test_independent() -> bool:\n    return value() > 0\n')
                    results = {}
                    for variant, compiler, encoding in (variants if sample % 2 == 0 else list(reversed(variants))):
                        row = run(variant, compiler, encoding, 'addition', sample)
                        assert row['counts'].get('failed', 0) == 0 and row['counts'].get('passed', 0) == 1, row['counts']
                        assert row['counts'].get('cached', 0) == len(original['report']['tests']), row['counts']
                        current_keys = qualify.keys(row)
                        assert all(current_keys.get(name) == key for name, key in original_keys[variant].items())
                        new_keys = tuple(sorted((name, key) for name, key in qualify.keys(row).items()
                                                if name not in qualify.keys(original)))
                        assert len(new_keys) == 1 and new_keys[0][1] is not None and new_keys not in seen[variant]
                        seen[variant].add(new_keys)
                        results[variant] = row
                    assert all(qualify.normalized(row) == qualify.normalized(results['baseline']) for row in results.values())
                    forced = run('candidate-zlib', 'candidate', 'zlib', 'addition-forced', sample, True)
                    assert not forced['counts'].get('cached', 0)
                    assert qualify.normalized(forced) == qualify.normalized(results['candidate-zlib'])
                    assert qualify.keys(forced) == qualify.keys(results['candidate-zlib'])
                    added.unlink()
                    for variant, compiler, encoding in variants:
                        restored = run(variant, compiler, encoding, 'restore-addition', sample)
                        assert qualify.normalized(restored) == qualify.normalized(original)
                        assert not restored['counts'].get('passed', 0)
                        assert qualify.keys(restored) == original_keys[variant]
            finally:
                added.unlink(missing_ok=True)
    report['completed_utc'] = datetime.now(timezone.utc).isoformat()
    save()


if __name__ == '__main__':
    main()
