#!/usr/bin/env python3
"""Summarize the fixed 60-case corpus without converting censored runs to samples."""
import csv
import gzip
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OLD = ROOT / 'experiments/lox-eda-zero-rc-20261012/bench'
CHECKED = ('mylang-zero-rc', 'mylang-before')
REFERENCES = ('zig-fast', 'zig-safe', 'rust', 'go')
LABELS = {'mylang-zero-rc': 'Improved checked source', 'mylang-before': 'Previous checked source',
          'mylang-original-rc': 'Original RC control', 'mylang-migrated-rc': 'Improved source / RC',
          'zig-fast': 'Zig ReleaseFast', 'zig-safe': 'Zig ReleaseSafe', 'rust': 'Rust', 'go': 'Go'}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fmt(value, digits=3):
    return '—' if value is None else f'{value:.{digits}f}'


def compilation(compiler_sha256):
    summaries = {}
    for application in ('lox', 'eda'):
        pairs = []
        for number in range(3):
            path = HERE / 'compilation' / application / str(number) / 'results.json'
            receipt = json.loads(path.read_text())
            assert receipt['application'] == application and receipt['pair'] == number
            assert receipt['compiler_sha256'] == compiler_sha256
            rows = {(row['arm'], row['cache_state']): row for row in receipt['samples']}
            expected = {(arm, state) for arm in ('before', 'after')
                        for state in ('cold-guest-cache', 'warm-guest-cache')}
            assert set(rows) == expected and len(receipt['samples']) == len(expected)
            pairs.append(rows)
        summaries[application] = {}
        for state in ('cold-guest-cache', 'warm-guest-cache'):
            before = [pair['before', state]['elapsed_seconds'] for pair in pairs]
            after = [pair['after', state]['elapsed_seconds'] for pair in pairs]
            rss_before = [pair['before', state]['gnu_time_maxrss_kib'] for pair in pairs]
            rss_after = [pair['after', state]['gnu_time_maxrss_kib'] for pair in pairs]
            summaries[application][state] = {
                'before_seconds': before, 'after_seconds': after,
                'before_median_seconds': statistics.median(before),
                'after_median_seconds': statistics.median(after),
                'paired_ratio_geomean': statistics.geometric_mean(a / b for a, b in zip(after, before)),
                'before_gnu_time_maxrss_kib': rss_before, 'after_gnu_time_maxrss_kib': rss_after}
    return summaries


def main():
    receipts = sorted(p for p in (HERE / 'runtime').glob('*.json')
                      if not p.name.endswith(('.spec.json', '.host-before.json', '.host-after.json')))
    assert len(receipts) == 138, len(receipts)
    aggregate = subprocess.check_output([sys.executable, '-B', str(OLD / 'summarize.py'),
                                        '--spec-dir', str(HERE / 'specs'), *map(str, receipts)])
    data = json.loads(aggregate)
    assert len(data['cells']) == 60
    identities, policies = {}, {}
    for path in receipts:
        receipt = json.loads(path.read_text())
        cell = receipt['spec']['cell']
        assert policies.setdefault(cell, receipt['relative_timeout_policy']) == receipt['relative_timeout_policy']
        assert set(receipt['relative_timeout_arms']) == set(CHECKED)
        for name, identity in receipt['identities'].items():
            assert identities.setdefault(name, identity) == identity
        host = receipt['host_snapshot']
        assert sha(host['path']) == host['sha256']
        host_after = receipt['host_snapshot_after']
        assert sha(host_after['path']) == host_after['sha256']
    counters = {}
    for path in sorted((HERE / 'counted').glob('*.coverage.json')):
        coverage = json.loads(path.read_text())
        assert coverage['cell'] not in counters
        assert sha(coverage['raw_summary']) == coverage['raw_summary_sha256']
        assert sha(coverage['runtime_receipt']) == coverage['runtime_receipt_sha256']
        if coverage['qualification_receipt'] is not None:
            raw_receipt = json.loads(Path(coverage['qualification_receipt']).read_text())
            for name, identity in raw_receipt['identities'].items():
                assert identities.setdefault(name, identity) == identity
        else:
            assert coverage['executed'] is False
            assert all(row['status']['status'] == 'skipped_runtime_failure' for row in coverage['arms'].values())
        rows = {}
        for name, row in coverage['arms'].items():
            metric = row['metrics']
            if metric is not None:
                assert metric['live_bytes_at_exit'] == 0
                assert json.loads(Path(row['counter_path']).read_text()) == row['counters']
                if name in CHECKED:
                    totals, kinds = row['counters']['totals'], row['counters']['kinds']
                    assert all(totals[k] == 0 for k in (
                        'runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks', 'share_bytes'))
                    assert all(kinds[k]['count'] == 0 for k in ('retain', 'release', 'unique_test'))
            rows[name] = {'status': row['status'], 'metrics': metric}
        counters[coverage['cell']] = {'path': str(path), 'sha256': sha(path), 'arms': rows}
    assert set(counters) == set(data['cells'])
    for name, identity in identities.items():
        assert sha(name) == identity, name
    compiler = json.loads((ROOT / 'experiments/text-gaps-20261012/coordinator/common-002/build-receipt.json').read_text())
    assert sha(compiler['compiler']) == compiler['compiler_sha256']
    for entry in compiler['installation_files']:
        assert sha(Path(compiler['installation']) / entry['path']) == entry['sha256']
    results = {'compiler_source_commit': compiler['source_commit'], 'compiler_sha256': compiler['compiler_sha256'],
               'source_change_note': 'Application source refactors on one unchanged compiler; not a compiler-only speedup.',
               'groups': data['groups'], 'cells': {}, 'counter_coverage': {},
               'binaries': data['binary_sha256_by_application'], 'receipts': data['receipts'],
               'final_input_identities_verified': len(identities)}
    results['compilation'] = compilation(compiler['compiler_sha256'])
    (HERE / 'runtime-summary.json.gz').write_bytes(gzip.compress(aggregate, mtime=0))
    with (HERE / 'per-cell.csv').open('w', newline='') as stream:
        writer = csv.writer(stream)
        fields = ('allocs', 'reallocs', 'cumulative_allocated_bytes', 'peak_live_bytes', 'live_bytes_at_exit')
        writer.writerow(['cell', 'arm', 'complete', 'status', 'wall_median_s', 'wall_min_s', 'wall_max_s',
                         'rss_median_kib', 'rss_min_kib', 'rss_max_kib', 'checked_deadline_s', 'counted_status', *fields])
        for cell, row in sorted(data['cells'].items()):
            results['cells'][cell] = {'relative_timeout_policy': policies[cell], 'arms': row['arms'], 'counted': counters[cell]}
            for name, arm in sorted(row['arms'].items()):
                wall, rss = arm['wall_samples_summary'] or {}, arm['rss_samples_summary'] or {}
                count = counters[cell]['arms'].get(name, {})
                metric = count.get('metrics') or {}
                status = ';'.join(sorted({f['status'] for f in arm['failures']})) or 'ok'
                writer.writerow([cell, name, arm['complete'], status,
                    *[wall.get(k) for k in ('median', 'min', 'max')], *[rss.get(k) for k in ('median', 'min', 'max')],
                    policies[cell]['budget_seconds'] if name in CHECKED else None,
                    count.get('status', {}).get('status', 'not_instrumented'), *[metric.get(k) for k in fields]])
    lines = ['# Five application improvements: measured comparison', '',
        'All 60 frozen inputs remain in the denominator: 13 tree, 13 VM and 34 EDA. '
        'The compiler and foreign executable bytes are unchanged; candidate application sources changed. '
        'Completed cases have two warmups, nine alternating wall samples, three separate child peak-RSS samples, '
        'and complete output checks. Both checked sources stop at 3× the fresh five-sample Zig Fast calibration median '
        '(absolute ceiling 120 s). A cutoff has no exact runtime ratio; remaining runtime/RSS/counters are skipped.', '',
        'Ratios are runtime divided by the reference, lower is better. Full-group ratios require every case to complete. '
        'Raw samples, statuses and hashes are in runtime-summary.json.gz, per-cell.csv and results.json.', '',
        '| Group | Arm | Complete | vs previous checked | vs Zig Fast | vs Zig Safe | vs Rust | vs Go |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for group, summary in data['groups'].items():
        results['counter_coverage'][group] = {}
        for name in ('mylang-zero-rc', 'mylang-before', 'mylang-original-rc', 'mylang-migrated-rc'):
            ratios = summary['wall_ratios'][name]
            lines.append('| ' + ' | '.join([group.rstrip('/'), LABELS[name],
                f"{summary['complete_cells_by_arm'][name]}/{summary['cells']}",
                *[fmt(ratios[ref]['full_suite_geomean']) for ref in ('mylang-before', *REFERENCES)]]) + ' |')
            metrics = [counters[cell]['arms'][name]['metrics'] for cell in data['cells']
                       if cell.startswith(group) and counters[cell]['arms'][name]['metrics'] is not None]
            results['counter_coverage'][group][name] = {
                'completed': len(metrics), 'total': summary['cells'],
                'allocation_traffic_bytes_on_completed_cases': sum(m['cumulative_allocated_bytes'] for m in metrics) if metrics else None,
                'largest_per_case_peak_live_bytes': max((m['peak_live_bytes'] for m in metrics), default=None)}
    lines += ['', '| Completed candidate case | Median seconds | vs previous checked | vs Zig Fast | vs Rust | vs Go | Peak RSS MiB |',
              '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for cell, row in sorted(data['cells'].items()):
        arm = row['arms']['mylang-zero-rc']
        if arm['complete']:
            lines.append('| ' + ' | '.join([cell, fmt(arm['wall_samples_summary']['median'], 6),
                *[fmt(arm['wall_ratio_vs'].get(ref)) for ref in ('mylang-before', 'zig-fast', 'rust', 'go')],
                fmt(arm['rss_samples_summary']['median'] / 1024, 2)]) + ' |')
    lines += ['', '| Guest compilation | Cache | Before median s | After median s | After / before paired ratio |',
              '| --- | --- | ---: | ---: | ---: |']
    for application, modes in results['compilation'].items():
        for state, row in modes.items():
            lines.append('| ' + ' | '.join([application, state,
                fmt(row['before_median_seconds']), fmt(row['after_median_seconds']),
                fmt(row['paired_ratio_geomean'])]) + ' |')
    lines += ['', 'Compilation uses three alternating before/after pairs, each with a fresh private guest cache '
        'followed by warm replay. Admission wait is excluded; OS and shared host-tool caches are not flushed. '
        'GNU-time build RSS is retained per observation but is not an aggregate concurrent process-tree peak.', '',
        'Allocation traffic is cumulative; managed peak and GNU-time child peak RSS are separate high-water '
        'observations. Instrumented elapsed time is excluded from runtime ratios. Counter totals with different case coverage '
        'are not comparable corpus totals. All completed checked counters have zero RC/uniqueness events and zero managed '
        'exit-live bytes. Direct destruction and Lox’s own object GC remain valid. Qualification build logs include admission; '
        'only the separate compilation table supplies paired compiler-time measurements. Host snapshots before and after '
        'each timing chunk record possible contention, without proving the absence of interference during samples. '
        'The prior rerun and older historical comparisons retain their original identities.']
    (HERE / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    (HERE / 'COMPARISON.md').write_text('\n'.join(lines) + '\n')
    print('Validated 60 cases, 138 runtime receipts, all counter coverage and', len(identities), 'input identities.')


if __name__ == '__main__':
    main()
