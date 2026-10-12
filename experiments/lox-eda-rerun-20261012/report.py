#!/usr/bin/env python3
"""Summarize the complete rerun, preserving all censored cells and raw receipts."""
import csv
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OLD = ROOT / 'experiments/lox-eda-zero-rc-20261012/bench'
LABELS = {'mylang-zero-rc': 'Checked ownership', 'mylang-original-rc': 'Original RC',
          'mylang-migrated-rc': 'Migrated RC', 'zig-fast': 'Zig ReleaseFast',
          'zig-safe': 'Zig ReleaseSafe', 'rust': 'Rust', 'go': 'Go'}
CHECKED = 'mylang-zero-rc'
REFS = ('zig-fast', 'zig-safe', 'rust', 'go')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def gm(values):
    return math.exp(statistics.mean(map(math.log, values))) if values else None


def number(value, digits=3):
    return '—' if value is None else f'{value:.{digits}f}'


def main():
    receipts = sorted(p for p in (HERE / 'runtime').glob('*.json')
                      if not p.name.endswith(('.spec.json', '.host-before.json')))
    assert len(receipts) == 138, len(receipts)
    completed = subprocess.run([sys.executable, '-B', str(OLD / 'summarize.py'),
                               '--spec-dir', str(HERE / 'specs'), *map(str, receipts)],
                              check=True, stdout=subprocess.PIPE)
    data = json.loads(completed.stdout)
    assert len(data['cells']) == 60
    # Keep the original aggregator's full identities and sample arrays losslessly.
    (HERE / 'runtime-summary.json.gz').write_bytes(gzip.compress(completed.stdout, mtime=0))
    previous_path = OLD / 'full-final/full-runtime-summary.json'
    previous = json.loads(previous_path.read_text())
    historical = {app: json.loads(gzip.decompress((ROOT / f'experiments/fs-x-20261009/results/{app}-runtime.json.gz').read_bytes()))
                  for app in ('lox', 'eda')}
    maps = {'lox': {'mylang-original-rc': 'mylang:release', 'zig-fast': 'zig:release',
                    'zig-safe': 'zig:release-safe', 'rust': 'rust:release', 'go': 'go:release'},
            'eda': {'mylang-original-rc': 'mylang-final', **{ref: ref for ref in REFS}}}
    policies = {}
    identities = {}
    for path in receipts:
        d = json.loads(path.read_text())
        cell = d['spec']['cell']
        assert policies.setdefault(cell, d['relative_timeout_policy']) == d['relative_timeout_policy']
        for name, identity in d['identities'].items():
            assert identities.setdefault(name, identity) == identity
        snap = d['host_snapshot']
        assert sha(snap['path']) == snap['sha256']
    counters = {}
    for path in sorted((HERE / 'counted').glob('*.coverage.json')):
        d = json.loads(path.read_text())
        assert d['cell'] not in counters
        assert sha(d['raw_summary']) == d['raw_summary_sha256']
        assert sha(d['runtime_receipt']) == d['runtime_receipt_sha256']
        qualification = json.loads(Path(d['qualification_receipt']).read_text())
        assert qualification['measurement_harness_sha256'] == sha(OLD / 'measure.py')
        for name, identity in qualification['identities'].items():
            assert identities.setdefault(name, identity) == identity
        counters[d['cell']] = {'path': str(path), 'sha256': sha(path), 'arms': {}}
        for arm, row in d['arms'].items():
            metrics = row['metrics']
            counters[d['cell']]['arms'][arm] = {'status': row['status'], 'metrics': metrics}
            if metrics is not None:
                assert json.loads(Path(row['counter_path']).read_text()) == row['counters']
                assert metrics['live_bytes_at_exit'] == 0
                if arm == CHECKED:
                    totals, kinds = row['counters']['totals'], row['counters']['kinds']
                    assert all(totals[k] == 0 for k in ('runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks'))
                    assert all(kinds[k]['count'] == 0 for k in ('retain', 'release', 'unique_test'))
    assert set(counters) == set(data['cells'])
    # Validation is run after all timing leases have finished, for runtime and
    # separately instrumented executable/input identities alike.
    for path, identity in identities.items():
        assert sha(path) == identity, ('final input changed', path)
    installation_receipt = json.loads((ROOT / 'experiments/text-gaps-20261012/coordinator/common-002/build-receipt.json').read_text())
    for entry in installation_receipt['installation_files']:
        assert sha(Path(installation_receipt['installation']) / entry['path']) == entry['sha256']
    results = {'compiler_source_commit': '8b7d59eba868775b1b8d7f64c54b07abdd23d470',
               'compiler_sha256': '2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329',
               'harness_commit': '318dae60443faf01b55da1146c1624ab0d7229fa', 'groups': data['groups'], 'cells': {},
               'guest_binary_sha256_by_application': data['binary_sha256_by_application'],
               'runtime_receipts': data['receipts'],
               'previous_oct12_summary_sha256': sha(previous_path),
               'final_identity_validation': {'status': 'passed', 'unique_files': len(identities),
                                             'compiler_installation_files': len(installation_receipt['installation_files'])},
               'counter_coverage': {}, 'historical_comparisons': {},
               'notes': ['Timeout budgets are censoring thresholds, not exact runtimes or median ratios.',
                         'Historical comparisons are observational; CPU/environment and artifact identities differ.',
                         'Managed counters and child process peak RSS measure different quantities.']}
    with (HERE / 'per-cell.csv').open('w', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['cell', 'arm', 'complete', 'wall_median_s', 'wall_min_s', 'wall_max_s',
                         'rss_median_kib', 'rss_min_kib', 'rss_max_kib', 'status',
                         'checked_deadline_s', 'zig_calibration_median_s', 'previous_oct12_wall_s',
                         'previous_oct12_rss_kib', 'historical_oct9_wall_s', 'historical_oct9_rss_kib',
                         'counted_status', 'allocs', 'reallocs', 'cumulative_allocated_bytes',
                         'peak_live_bytes', 'live_bytes_at_exit'])
        for cell, row in sorted(data['cells'].items()):
            app = cell.split('/')[0]
            if app == 'lox':
                _, engine, case = cell.split('/')
                old = historical[app]['summary'][case + '/' + engine]
            else:
                old = historical[app]['per_case'][cell.split('/', 1)[1]]
            results['cells'][cell] = {'relative_timeout_policy': policies[cell], 'arms': {},
                                      'counted': counters[cell]}
            for arm, metric in row['arms'].items():
                wall, rss = metric['wall_samples_summary'] or {}, metric['rss_samples_summary'] or {}
                status = ';'.join(sorted({f['status'] for f in metric['failures']})) or 'ok'
                past = previous['cells'][cell]['arms'][arm]
                oldmetric = old.get(maps[app].get(arm, ''), {})
                oldrss = oldmetric.get('maxrss_kib') if app == 'lox' else (oldmetric['rss_exact_mib'] * 1024 if 'rss_exact_mib' in oldmetric else None)
                count = counters[cell]['arms'].get(arm, {})
                metrics = count.get('metrics') or {}
                writer.writerow([cell, arm, metric['complete'], *[wall.get(k) for k in ('median', 'min', 'max')],
                                 *[rss.get(k) for k in ('median', 'min', 'max')], status,
                                 policies[cell]['budget_seconds'] if arm == CHECKED else None,
                                 policies[cell]['reference_median_seconds'],
                                 (past['wall_samples_summary'] or {}).get('median'),
                                 (past['rss_samples_summary'] or {}).get('median'), oldmetric.get('median_s'), oldrss,
                                 count.get('status', {}).get('status', 'not_instrumented'),
                                 *[metrics.get(k) for k in ('allocs', 'reallocs', 'cumulative_allocated_bytes', 'peak_live_bytes', 'live_bytes_at_exit')]])
                results['cells'][cell]['arms'][arm] = metric
    lines = ['# Lox and EDA: fresh rerun with the 3× Zig cutoff', '',
             'All 60 cases were attempted: 34 EDA designs, 13 Lox tree cases and 13 Lox VM cases. '
             'Completed arms have two warmups, nine alternating runtime samples, three separate child peak-RSS samples, '
             'and verified output oracles. Checked-ownership invocations exceeding three times the five-sample Zig ReleaseFast '
             'calibration median stop immediately; later runtime, RSS and counted runs for that checked case are skipped. '
             'The absolute ceiling is 120 seconds. A cutoff is not a measured median ratio. All missing results stay in the denominator.', '',
             'The compiler, application sources, executable hashes, command lines and workload inputs are recorded in '
             '[README.md](README.md), build receipts and specifications. No compiler or application changes were made for this rerun. '
             'The Zig/Rust/Go executable bytes match the previous run and were freshly executed. '
             'Original RC and migrated RC are same-compiler controls; the checked arm uses the same source as migrated RC.', '',
             'Ratios below are elapsed runtime divided by the comparison arm; lower is better. '
             'A group gets a ratio only when every case in that group completes. No subset is presented as the full benchmark.', '',
             '| Group | Arm | Complete | vs Zig Fast | vs Zig Safe | vs Rust | vs Go | Largest case-median peak RSS (MiB) |',
             '|---|---|---:|---:|---:|---:|---:|---:|']
    for group, g in data['groups'].items():
        rows = {cell: row for cell, row in data['cells'].items() if cell.startswith(group)}
        results['counter_coverage'][group] = {}
        for arm in LABELS:
            complete = g['complete_cells_by_arm'][arm]
            rss = [row['arms'][arm]['rss_samples_summary']['median'] / 1024
                   for row in rows.values() if row['arms'][arm]['complete']]
            lines.append('| ' + ' | '.join([group.rstrip('/'), LABELS[arm], f'{complete}/{g["cells"]}',
                         *[number(g['wall_ratios'][arm][ref]['full_suite_geomean']) for ref in REFS],
                         number(max(rss), 2) if complete == g['cells'] else '—']) + ' |')
            if arm.startswith('mylang-'):
                valid = [counters[cell]['arms'][arm]['metrics'] for cell in rows if counters[cell]['arms'][arm]['metrics'] is not None]
                results['counter_coverage'][group][arm] = {
                    'completed': len(valid), 'total': len(rows),
                    'total_allocation_traffic_bytes_on_completed_cases': sum(v['cumulative_allocated_bytes'] for v in valid) if valid else None,
                    'largest_managed_peak_bytes_on_completed_cases': max((v['peak_live_bytes'] for v in valid), default=None),
                    'all_completed_exit_live_bytes_zero': all(v['live_bytes_at_exit'] == 0 for v in valid) if valid else None}
    lines += ['', 'Completed checked cases are listed individually below; this selected set does not represent the full suite.', '',
              '| Checked case | Median (s) | vs Zig Fast | vs Rust | vs Go | Median peak RSS (MiB) |',
              '|---|---:|---:|---:|---:|---:|']
    for cell, row in sorted(data['cells'].items()):
        value = row['arms'][CHECKED]
        if value['complete']:
            lines.append('| ' + ' | '.join([cell, number(value['wall_samples_summary']['median'], 6),
                         *[number(value['wall_ratio_vs'].get(ref)) for ref in ('zig-fast', 'rust', 'go')],
                         number(value['rss_samples_summary']['median'] / 1024, 2)]) + ' |')
    lines += ['', 'The detailed CSV includes each arm’s runtime range, RSS range, allocation count, reallocation count, '
              'allocation traffic, managed peak, exit-live bytes, and prior Oct12/Oct9 observations. '
              'Missing counted data is unavailable, never zero. Allocation traffic is cumulative; managed peak and RSS '
              'are separate per-process high-water measurements. RSS is GNU time’s child peak RSS, excluding the Python harness. '
              'This rerun does not claim compiler-time or compiler-RSS comparisons; build durations include admission/setup.', '',
              '| Group | Counted arm | Completed | Allocation traffic over completed cases (MiB) | Largest managed peak over completed cases (MiB) |',
              '|---|---|---:|---:|---:|']
    for group, arms in results['counter_coverage'].items():
        for arm, v in arms.items():
            peak = v['largest_managed_peak_bytes_on_completed_cases']
            lines.append(f'| {group.rstrip("/")} | {LABELS[arm]} | {v["completed"]}/{v["total"]} | '
                         f'{number(v["total_allocation_traffic_bytes_on_completed_cases"] / 1048576, 2) if v["completed"] else "—"} | '
                         f'{number(peak / 1048576 if peak is not None else None, 2)} |')
    lines += ['', 'All completed counted guests exit with zero live managed bytes. Completed checked runs also have zero '
              'compiler/runtime/shared retains and releases, share marks and uniqueness tests. '
              'Direct destruction and the Lox application’s own garbage collector remain valid. '
              'Counter rows with different coverage must not be compared as total traffic for the same workload set.', '',
              'For completed checked cases, the same-case memory comparisons are:', '',
              '| Case | Arm | Allocations | Reallocations | Allocation traffic (MiB) | Managed peak (MiB) | Median peak RSS (MiB) |',
              '|---|---|---:|---:|---:|---:|---:|']
    for cell, row in sorted(data['cells'].items()):
        if not row['arms'][CHECKED]['complete']:
            continue
        for arm in (CHECKED, 'mylang-original-rc', 'mylang-migrated-rc'):
            metrics = counters[cell]['arms'][arm]['metrics']
            if metrics is None:
                continue
            rss = (row['arms'][arm]['rss_samples_summary'] or {}).get('median')
            lines.append('| ' + ' | '.join([cell, LABELS[arm], str(metrics['allocs']), str(metrics['reallocs']),
                         number(metrics['cumulative_allocated_bytes'] / 1048576, 2),
                         number(metrics['peak_live_bytes'] / 1048576, 2),
                         number(rss / 1024 if rss is not None else None, 2)]) + ' |')
    lines += ['',
              '| Group | Reference | Oct9 original RC / reference | Prior Oct12 checked / reference | Fresh checked / reference |',
              '|---|---|---:|---:|---:|']
    for group, g in data['groups'].items():
        results['historical_comparisons'][group] = {}
        for ref in REFS:
            ratios = []
            for cell in data['cells']:
                if not cell.startswith(group):
                    continue
                app = cell.split('/')[0]
                if app == 'lox':
                    _, engine, case = cell.split('/')
                    row = historical[app]['summary'][case + '/' + engine]
                else:
                    row = historical[app]['per_case'][cell.split('/', 1)[1]]
                ratios.append(row[maps[app]['mylang-original-rc']]['median_s'] / row[maps[app][ref]]['median_s'])
            oldratio = gm(ratios)
            priorratio = previous['groups'][group]['wall_ratios'][CHECKED][ref]['full_suite_geomean']
            currentratio = g['wall_ratios'][CHECKED][ref]['full_suite_geomean']
            results['historical_comparisons'][group][ref] = {'oct9_original_rc_ratio': oldratio,
                                                          'prior_oct12_checked_ratio': priorratio,
                                                          'fresh_checked_ratio': currentratio}
            lines.append(f'| {group.rstrip("/")} | {LABELS[ref]} | {number(oldratio)} | {number(priorratio)} | {number(currentratio)} |')
    lines += ['', 'Historical numbers are context, not paired speedup evidence. Oct9 used CPU 10 and different artifacts; '
              'Oct12 uses CPU 8. This run pins Go GOMAXPROCS=1, GOGC=100 and GOMEMLIMIT=off, '
              'while the prior full-app run did not record those overrides. Historical Lox RSS used the maximum across '
              'timing rounds; current RSS uses the median of three separate measurements. '
              'The current CPU-time environment can vary between leases despite exclusive cooperating-job admission.', '',
              '| Case | Checked result | Zig calibration median (s) | Checked deadline (s) | Checked median (s), if complete |',
              '|---|---|---:|---:|---:|']
    for cell, row in sorted(data['cells'].items()):
        metric = row['arms'][CHECKED]
        status = 'complete' if metric['complete'] else '; '.join(sorted({f['status'] for f in metric['failures']}))
        policy = policies[cell]
        lines.append(f'| {cell} | {status} | {number(policy["reference_median_seconds"], 6)} | '
                     f'{number(policy["budget_seconds"], 6)} | {number((metric["wall_samples_summary"] or {}).get("median"), 6)} |')
    lines += ['', 'Raw data: [per-cell.csv](per-cell.csv), [results.json](results.json), '
              '[runtime-summary.json.gz](runtime-summary.json.gz), and the runtime/counting receipts. '
              'All runtime input/binary identities and host snapshot hashes were revalidated after measurement. '
              'The timeout harness passed four regression tests covering completion, cutoff, chunk carry-over, '
              'failed reference calibration and descendant-process termination.', '']
    (HERE / 'COMPARISON.md').write_text('\n'.join(lines))
    (HERE / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps({'groups': {g: d['complete_cells_by_arm'] for g, d in data['groups'].items()},
                      'identities_verified': len(identities)}, indent=2))


if __name__ == '__main__':
    main()
