#!/usr/bin/env python3
"""Paired first-edit directory benchmarks: current EDA/Lox and synthetic graphs."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import statistics

import qualify


def generated(root, lines):
    """Generate bounded chains with every function reachable from an executed test."""
    root.mkdir(parents=True)
    (root / 'mylang.json').write_text('{"version":1}\n')
    shared = 'public func value() -> int:\n    _ = 0\n    return 1\n'
    (root / 'shared.my').write_text(shared)
    remaining = lines - len(shared.splitlines())
    nodes = tests = modules = closure_visits = 0
    while remaining >= 17:
        count = min(256, (remaining - 11) // 6)
        assert count > 0
        text = ['import shared\n\n']
        for index in range(count):
            callee = f'f_{index + 1:04d}()' if index + 1 < count else 'shared.value()'
            text.append(f'func f_{index:04d}() -> int:\n    const marker = 0\n    _ = marker\n    return {callee} + marker\n\n\n')
        text.append('public func test_chain() -> bool:\n    return f_0000() >= 1\n\n')
        text.append(f'public func test_tail() -> bool:\n    return f_{count // 2:04d}() >= 1\n\n')
        content = ''.join(text)
        used = len(content.splitlines())
        assert used <= remaining
        (root / f'm{modules:04d}.my').write_text(content)
        remaining -= used
        nodes += count + 2
        tests += 2
        modules += 1
        closure_visits += count + (count - count // 2) + 4
    assert nodes + 1 < 100000 and tests < 1000000
    with (root / 'shared.my').open('a') as stream:
        stream.write('\n' * remaining)
    actual = sum(len(p.read_text().splitlines()) for p in root.glob('*.my'))
    assert actual == lines, (actual, lines)
    return {'kind': 'synthetic reachable private chains; distinct from EDA replicas',
            'physical_lines': actual, 'functions': nodes + 1, 'test_roots': tests,
            'maximum_chain_depth': 256, 'test_modules': modules,
            'structure': 'two overlapping roots per module; a same-line head edit leaves the tail root unaffected',
            'estimated_total_closure_visits': closure_visits}


def first_body_edit(text, token):
    # Preserve semantics; include the token in reachable canonical Core.
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if re.match(r'^(?:public )?func \w+', line) and line.rstrip().endswith(':'):
            lines.insert(index + 1, f'    assert {token} > 0\n')
            return ''.join(lines)
    raise AssertionError('no eligible current-syntax function body')


def private_edit(text, token):
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if re.match(r'^func \w+', line) and line.rstrip().endswith(':'):
            lines.insert(index + 1, f'    assert {token} > 0\n')
            return ''.join(lines)
    return first_body_edit(text, token)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--comparison', type=Path,
                        help='optional third frozen compiler arm, with its own zlib cache')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--eda', type=Path, default=qualify.EDA)
    parser.add_argument('--lox', type=Path, default=qualify.LOX)
    parser.add_argument('--sizes', type=int, nargs='*', default=[191416, 510436])
    parser.add_argument('--skip-corpora', action='store_true')
    parser.add_argument('--small-rounds', type=int, default=5)
    parser.add_argument('--large-rounds', type=int, default=3)
    parser.add_argument('--candidate-encodings', nargs='+', choices=['zlib', 'none'], default=['zlib', 'none'])
    parser.add_argument('--oracle-env', action='append', default=[], metavar='NAME=VALUE')
    args = parser.parse_args()
    assert args.small_rounds > 0 and args.large_rounds > 0
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    compilers = [('baseline', args.baseline), ('candidate', args.candidate)]
    if args.comparison is not None:
        compilers.append(('comparison', args.comparison))
    report = {'started_utc': datetime.now(timezone.utc).isoformat(),
              'execution_context': {'affinity': sorted(os.sched_getaffinity(0)),
                                    'platform': platform.platform(), 'jobs': 4},
              'compilers': {name: {'path': str(path.resolve()), 'sha256': qualify.digest(path)}
                            for name, path in compilers},
              'method': 'Same source paths; separate compiler/encoding caches and native stores. Warm original once. '
                        'Every measured edit uses a never-before-used token, then restores original. '
                        'No historical edited keys or native outputs are copied. GNU time RSS is maximum individual process RSS, '
                        'not summed concurrent-tree RSS. Cold includes native compilation; populated no-op and first edits are separate.',
              'fixtures': {}, 'records': [], 'summary': {}}
    if args.comparison is not None:
        report['method'] += (' The optional comparison arm uses a separate zlib cache on these same source paths, '
                             'participates in cold/no-op/edit/restore and verdict checks, and is interleaved '
                             'with baseline and candidate in alternating arm order each round.')

    def save():
        (root / 'results.json').write_text(json.dumps(report, indent=2) + '\n')

    workloads = []
    if not args.skip_corpora:
        for name, origin, target, flags, private, helper, third in [
            ('eda', args.eda, 'src', ['--max-frames=30000', '--max-steps=4000000000', '--max-memory=2G'],
             'src/sexpr_parser.my', 'src/support_strs.my', 'src/support_parse.my'),
            ('lox', args.lox, '.', ['--max-steps=100000000'], 'parser.my', 'scanner.my', 'resolver.my')]:
            source = root / name / 'source'
            report['fixtures'][name] = qualify.source_copy(origin, source)
            workloads.append((name, source, target, flags, [private, helper, third], args.small_rounds))
    for size in args.sizes:
        name = f'synthetic-{size}'
        source = root / name / 'source'
        report['fixtures'][name] = generated(source, size)
        workloads.append((name, source, '.', ['--max-frames=1024'],
                          ['m0000.my', 'shared.my', 'm0001.my'], args.large_rounds))
    variants = [('baseline', args.baseline, 'zlib')]
    if args.comparison is not None:
        variants.append(('comparison', args.comparison, 'zlib'))
    variants += [(f'candidate-{encoding}', args.candidate, encoding) for encoding in args.candidate_encodings]
    for name, source, target, flags, edit_paths, rounds in workloads:
        originals = {relative: (source / relative).read_text() for relative in edit_paths}
        measured_keys = {}
        original_keys = {}

        def record(variant, compiler, encoding, phase, sample, force=False, oracle=False):
            label = f'{name}-{variant}-{phase}-{sample}'
            overrides = ['MYLANG_STAGE_CACHE_COMPRESSION=' + encoding]
            if oracle:
                overrides += args.oracle_env
            row = qualify.run(compiler, source, target, root / name / ('oracle-' + variant if oracle else variant),
                              root / 'raw', label, flags, overrides, force)
            row.update(fixture=name, variant=variant, phase=phase, sample=sample, encoding=encoding)
            report['records'].append(row)
            save()
            print(json.dumps({k: row[k] for k in ['fixture', 'variant', 'phase', 'sample', 'wall_s', 'peak_rss_kb', 'counts']}), flush=True)
            return row

        cold_outcomes = None
        for variant, compiler, encoding in variants:
            cold = record(variant, compiler, encoding, 'cold', 0)
            original_keys[variant] = qualify.keys(cold)
            assert not cold['counts'].get('failed', 0), cold['counts']
            assert cold['counts'].get('passed', 0) > 0, cold['counts']
            if cold_outcomes is None:
                cold_outcomes = qualify.normalized(cold)
            assert qualify.normalized(cold) == cold_outcomes, name
            noop = record(variant, compiler, encoding, 'noop', 0)
            assert qualify.normalized(noop) == cold_outcomes, name
            assert not noop['counts'].get('passed', 0), f'{name}: unchanged tests executed'
        for sample in range(rounds):
            for phase in ['private', 'helper', 'three-file']:
                token = 1000000 + sample * 100 + ['private', 'helper', 'three-file'].index(phase)
                selected = edit_paths if phase == 'three-file' else [edit_paths[0 if phase == 'private' else 1]]
                for relative in selected:
                    transform = private_edit if phase == 'private' else first_body_edit
                    text = originals[relative]
                    if name.startswith('synthetic-'):
                        # Positive values keep tests passing while changing actual
                        # reachable instructions, without moving later declarations.
                        text = (text.replace('    return 1', f'    return {token}', 1)
                                if relative == 'shared.my' else
                                text.replace('const marker = 0', f'const marker = {token}', 1))
                    else:
                        text = transform(text, token)
                    (source / relative).write_text(text)
                ordered = variants if sample % 2 == 0 else list(reversed(variants))
                outcomes = None
                candidate_records = {}
                for variant, compiler, encoding in ordered:
                    edited = record(variant, compiler, encoding, phase, sample)
                    assert not edited['counts'].get('failed', 0), edited['counts']
                    assert edited['counts'].get('passed', 0) > 0, (name, phase, 'edit executed no tests')
                    assert any(key is not None and key != original_keys[variant].get(test)
                               for test, key in qualify.keys(edited).items()), (name, phase, 'edit changed no eligible key')
                    signature = tuple(sorted((name, key) for name, key in qualify.keys(edited).items() if key is not None))
                    seen = measured_keys.setdefault((variant, phase), set())
                    assert signature not in seen, (name, phase, variant, 'repeated edited keys; not a first-edit measurement')
                    seen.add(signature)
                    if outcomes is None:
                        outcomes = qualify.normalized(edited)
                    assert qualify.normalized(edited) == outcomes, (name, phase)
                    if variant.startswith('candidate-'):
                        candidate_records[encoding] = edited
                # This forced run checks execution. qualify.py separately checks
                # keys with an independent eager oracle inside shadow invocations;
                # changing planner/environment identity here would change keys.
                oracle_encoding = args.candidate_encodings[0]
                forced = record('candidate-' + oracle_encoding, args.candidate, oracle_encoding, phase + '-forced', sample,
                                force=True, oracle=True)
                assert qualify.normalized(forced) == outcomes, (name, phase)
                assert not forced['counts'].get('cached', 0)
                assert qualify.keys(forced) == qualify.keys(candidate_records[oracle_encoding]), (name, phase, 'canonical key mismatch')
                for relative in selected:
                    (source / relative).write_text(originals[relative])
                for variant, compiler, encoding in variants:
                    restored = record(variant, compiler, encoding, 'restore-' + phase, sample)
                    assert qualify.normalized(restored) == cold_outcomes, (name, phase)
        for variant, _compiler, _encoding in variants:
            for phase in ['private', 'helper', 'three-file']:
                rows = [r for r in report['records'] if (r['fixture'], r['variant'], r['phase']) == (name, variant, phase)]
                report['summary'][f'{name}/{variant}/{phase}'] = {
                    'samples': len(rows), 'median_wall_s': statistics.median(r['wall_s'] for r in rows),
                    'median_peak_rss_kb': statistics.median(r['peak_rss_kb'] for r in rows),
                    'min_wall_s': min(r['wall_s'] for r in rows), 'max_wall_s': max(r['wall_s'] for r in rows)}
        save()
    report['completed_utc'] = datetime.now(timezone.utc).isoformat()
    save()


if __name__ == '__main__':
    main()
