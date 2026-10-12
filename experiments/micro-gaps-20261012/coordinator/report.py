#!/usr/bin/env python3
"""Validate the paired gap campaign, preserving raw timing and memory metrics."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[3]
NEW = ROOT / 'experiments/micro-gaps-20261012'
OLD = ROOT / 'experiments/micro-ownership-20261012'
BASE, CAND = 'baseline-zero-rc', 'mylang-zero-rc'


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


helpers = module('micro_report_helpers', OLD / 'tools/report.py')
registry = module('micro_registry', ROOT / 'benchmarks/runtime/expanded/registry.py')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def main():
    rows = []
    identities = {}
    symbols = {}
    counts = {'samples': 0, 'warmups': 0, 'rss': 0, 'counted': 0}
    for suite in ('parity', 'expanded'):
        for path in sorted((NEW / ('specs-' + suite)).glob('*.json')):
            spec = read(path)
            receipt = NEW / 'results' / suite / path.name
            data = read(receipt)
            assert data['spec'] == spec and data['identities'] == data['identities_after']
            for p, h in data['identities'].items():
                if p in identities:
                    assert identities[p] == h
                else:
                    assert sha(p) == h, p
                    identities[p] = h
            n = data['iterations']
            expected = registry.checksum(spec['case'], spec['size'], n, spec['seed']) if suite == 'expanded' else spec['expected_stdout']
            assert data['expected'] == expected
            assert set(data['arm_status']) == set(data['counted']) == {BASE, CAND}
            times, arms = {}, {}
            for arm in (BASE, CAND):
                assert data['arm_status'][arm]['status'] == 'ok'
                assert data['summary'][arm]['complete']
                parts = {}
                for phase, expected_rounds in [('samples', range(spec['rounds'])), ('warmups', range(-spec['warmups'], 0)), ('rss', range(spec['rss_rounds']))]:
                    values = [v for v in data[phase] if v['arm'] == arm]
                    assert len(values) == len(expected_rounds)
                    assert {v['round'] for v in values} == set(expected_rounds)
                    for value in values:
                        helpers.validate_guest(value, spec, expected)
                        assert value['iterations'] == n
                    parts[phase] = values
                    counts[phase] += len(values)
                times[arm] = {v['round']: v['kernel_ns'] / n if suite == 'expanded' else v['process_wall_ns'] for v in parts['samples']}
                counted = data['counted'][arm]
                helpers.validate_guest(counted, spec, expected)
                assert counted['iterations'] == n and sha(counted['counter_path']) == counted['counter_sha256']
                raw = read(counted['counter_path'])
                computed = helpers.metrics(raw)
                assert computed == counted['metrics']
                assert computed['rc_events'] == computed['unique_test'] == computed['live_bytes_at_exit'] == raw['totals'].get('share_marks', 0) == 0
                counts['counted'] += 1
                arms[arm] = {'median_ns': statistics.median(times[arm].values()),
                             'range_ns': [min(times[arm].values()), max(times[arm].values())],
                             'rss_kib': statistics.median(v['peak_rss_kib'] for v in parts['rss']),
                             'metrics': computed, 'counter_totals': raw['totals']}
                for field in ('arms', 'counted'):
                    entry = spec[field][arm]
                    assert data['identities'][entry['binary']] == entry['sha256']
                    if entry['binary'] not in symbols:
                        output = subprocess.check_output(['nm', '--defined-only', entry['binary']], text=True)
                        found = sorted(set(re.findall(r'\bmyl_core_(?:retain|release)\w*\b', output)))
                        assert output.strip() and not found
                        symbols[entry['binary']] = {'sha256': entry['sha256'], 'known_core_rc_symbols': found}
            for pilot in data['pilots']:
                wanted = registry.checksum(spec['case'], spec['size'], pilot['iterations'], spec['seed'])
                for value in pilot['arms']:
                    helpers.validate_guest(value, spec, wanted)
            rows.append({'cell': spec['cell'], 'baseline_cell': spec['baseline_cell'],
                         'case': spec['case'], 'suite': suite, 'profile': spec.get('profile'),
                         'iterations': n, 'unit': spec['unit'], 'arms': arms,
                         'candidate_over_baseline': helpers.interval(times[CAND], times[BASE], spec['cell'], 5000),
                         'receipt': str(receipt), 'receipt_sha256': sha(receipt),
                         'calibration': data.get('calibration')})
    assert len(rows) == 91
    report = {'cells': rows, 'counts': counts, 'artifacts': identities, 'symbols': symbols,
              'baseline': 'Frozen checked-owned guests from compiler8e58720c; rerun paired on current host.',
              'candidate': read(NEW / 'coordinator/builds.json'),
              'notes': ['Paired ratio of medians, deterministic5000-resample95% interval.',
                        'RSS is separate uninstrumented process high-water RSS; managed peak excludes raw sorting scratch.',
                        'Counted results are whole-program totals for equal iterations within each pair; no peak subtraction.',
                        'Prior foreign/RC results remain historical context, not paired controls in this campaign.']}
    (NEW / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    priority = {'dict_count', 'dict_update_str', 'dict_lookup_str', 'word_count', 'sort_records', 'int_format', 'string_split'}
    lines = ['# Four performance gaps: paired qualification', '',
             'Candidate/baseline below1 means faster. Both arms use checked ownership and unchanged sources. Raw samples, counters and source/compiler hashes are retained in report.json and results/.', '',
             '| Case | Size | Candidate/C0 [95% interval] | Allocations C0 → candidate | RSS KiB C0 → candidate |',
             '| --- | --- | --- | --- | --- |']
    for row in rows:
        if row['case'] not in priority:
            continue
        a, b, ratio = row['arms'][BASE], row['arms'][CAND], row['candidate_over_baseline']
        lines.append(f"| {row['case']} | {row['profile'] or 'fixed'} | {ratio['ratio']:.3f} [{ratio['ci95'][0]:.3f}, {ratio['ci95'][1]:.3f}] | {a['metrics']['allocs']:,} → {b['metrics']['allocs']:,} | {a['rss_kib']:,} → {b['rss_kib']:,} |")
    lines += ['', 'Counts use the calibrated iteration count for that row; compare only within a row. Sorting scratch uses native malloc and is absent from managed allocation counters. The full report retains traffic, managed peak, exit-live, RSS and time separately.', '',
              f"Validated91 cells, {counts['samples']} timing samples, {counts['warmups']} warmups, {counts['rss']} RSS probes and {counts['counted']} counter runs. All counted runs have zero RC events and zero live managed bytes at exit.", '',
              '## Review triggers', '']
    for row in rows:
        ratio = row['candidate_over_baseline']
        if ratio['ratio'] > 1.05:
            lines.append(f"- {row['baseline_cell']}: {ratio['ratio']:.3f}× [{ratio['ci95'][0]:.3f}, {ratio['ci95'][1]:.3f}]; requires review before claiming regression-free performance.")
    (NEW / 'PERFORMANCE.md').write_text('\n'.join(lines) + '\n')
    print('PASS', len(rows), 'cells;', counts)


if __name__ == '__main__':
    main()
