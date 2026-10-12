#!/usr/bin/env python3
"""Validate fresh receipts and report paired per-foreign ratios; never execute guests."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]

def imported(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

measure = imported('text_measure', HERE / 'measure.py')
previous = imported('previous_report', ROOT / 'experiments/micro-ownership-20261012/tools/report.py')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def analyze(path, spec, bootstrap, check_artifacts, artifact_map=None):
    d = json.loads(path.read_text())
    require(d['schema'] == 'text-gap-cell-v1' and d['spec'] == spec, 'receipt/spec mismatch')
    require(d['identities'] == d['identities_after'], 'inputs changed during timing')
    if check_artifacts:
        for p, sha in d['identities'].items():
            if Path(p).exists() and measure.digest(p) == sha:
                continue
            relocated = (artifact_map or {}).get('inputs', {}).get(p)
            require(relocated and relocated['sha256'] == sha and measure.digest(relocated['archived_path']) == sha,
                    'artifact changed without identical explicit archive: ' + p)
    n = d['iterations']
    require(isinstance(n, int) and n > 0, 'invalid iteration count')
    expected = measure.registry.checksum(spec['case'], spec['size'], n, spec['seed'])
    require(expected == d['expected'], 'independent oracle mismatch')
    require(d['cpu'] == 8, 'unexpected measurement CPU')
    require(set(d['summary']) == set(spec['arms']) == set(d['arm_status']), 'arm inventory changed')
    require(set(d['counted']) == set(spec['counted']), 'counted inventory changed')
    for pilot in d['pilots']:
        want = measure.registry.checksum(spec['case'], spec['size'], pilot['iterations'], spec['seed'])
        for sample in pilot['arms']:
            previous.validate_guest(sample, spec, want)
    maps, arms = {}, {}
    for name, entry in spec['arms'].items():
        require(d['identities'][entry['binary']] == entry['sha256'], 'binary pin mismatch')
        require(d['summary'][name]['complete'] and d['arm_status'][name]['status'] == 'ok', 'incomplete arm: ' + name)
        values = {}
        for phase, rounds in (('warmups', range(-3, 0)), ('samples', range(15)), ('rss', range(3))):
            samples = [s for s in d[phase] if s['arm'] == name]
            require(len(samples) == len(rounds) and {s['round'] for s in samples} == set(rounds), 'missing/duplicate rounds')
            for sample in samples:
                previous.validate_guest(sample, spec, expected)
                require(sample['iterations'] == n, 'different per-arm iterations')
                if phase == 'samples':
                    values[sample['round']] = sample['kernel_ns'] / n
                if phase == 'rss':
                    require(sample['peak_rss_kib'] > 0, 'invalid process RSS')
        maps[name] = values
        median = statistics.median(values.values())
        ordered = [values[r] for r in range(15)]
        mad = statistics.median(abs(v - median) for v in values.values())
        arms[name] = dict(median_ns=median, min_ns=min(values.values()), max_ns=max(values.values()),
                          mad_fraction=mad / median,
                          last5_over_first5=statistics.median(ordered[-5:]) / statistics.median(ordered[:5]),
                          rss_kib=d['summary'][name]['peak_rss_kib'], binary_sha256=entry['sha256'],
                          flags=entry['flags'], source_sha256=entry['source_sha256'])
        require(d['summary'][name]['kernel_ns_per_iteration']['median'] == median, 'summary median mismatch')
        if name in d['counted']:
            counted = d['counted'][name]
            previous.validate_guest(counted, spec, expected)
            require(counted['iterations'] == n, 'counted iterations differ')
            require(measure.digest(counted['counter_path']) == counted['counter_sha256'], 'counter hash mismatch')
            metrics = measure.counters(counted['counter_path'])
            require(metrics == counted['metrics'], 'counter metrics mismatch')
            raw = json.loads(Path(counted['counter_path']).read_text())
            require(metrics['live_bytes_at_exit'] == metrics['rc_events'] == metrics['unique_test'] == raw['totals'].get('share_marks', 0) == 0, 'checked ownership invariant failed')
            arms[name]['managed'] = metrics
    # Validate deterministic order independently of guest completion counts.
    names = list(spec['arms'])
    for rnd in range(15):
        actual = [s['arm'] for s in d['samples'] if s['round'] == rnd]
        require(actual == measure.balanced_order(names, rnd, spec['cell'] + '/samples'), 'sample ordering mismatch')
    comparisons = {}
    for checked in [name for name in maps if name.startswith('checked-')]:
        for other in maps:
            if checked == other:
                continue
            key = checked + '/' + other
            comparisons[key] = previous.interval(maps[checked], maps[other], spec['cell'] + '/' + key, bootstrap)
    return dict(case=spec['case'], profile=spec['profile'], size=spec['size'], unit=spec['unit'],
                receipt=str(path), receipt_sha256=measure.digest(path), iterations=n,
                expected_checksum=expected, calibration=d['calibration'], cpu=d['cpu'],
                loadavg_before=d['loadavg_before'], loadavg_after=d['loadavg_after'],
                started_utc=d['started_utc'], finished_utc=d['finished_utc'], arms=arms, comparisons=comparisons,
                noise_flags=[name for name, arm in arms.items() if arm['mad_fraction'] > .05 or abs(arm['last5_over_first5'] - 1) > .1])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('run', type=Path)
    p.add_argument('output', type=Path)
    p.add_argument('--check-artifacts', action='store_true')
    p.add_argument('--artifact-map', type=Path, help='Explicit content-identical archive relocation map; hashes must equal measured pins')
    p.add_argument('--bootstrap', type=int, default=10000)
    p.add_argument('--case', action='append', help='Explicit trial subset; default requires all six cells')
    a = p.parse_args()
    require(not a.output.exists(), 'never overwrite a report')
    artifact_map = json.loads(a.artifact_map.read_text()) if a.artifact_map else None
    cells = []
    for spec_path in sorted((a.run / 'specs').glob('*.json')):
        spec = json.loads(spec_path.read_text())
        if a.case and spec['case'] not in a.case:
            continue
        cells.append(analyze(a.run / 'results' / spec_path.name, spec, a.bootstrap, a.check_artifacts, artifact_map))
    require(len(cells) == 2 * len(set(a.case)) if a.case else len(cells) == 6, 'expected all selected small/large cells')
    report = dict(schema='text-gap-report-v1', cells=cells, reporter_sha256=measure.digest(__file__), artifact_relocations=artifact_map,
                  limitations=['Exploratory single-session paired bootstrap intervals, ratio of medians; matched round indices resampled jointly.',
                               'Managed counters include setup and exclude allocator overhead; foreign managed counters unavailable. Process RSS is separate.',
                               'Representation/library policies differ. MyLang split returns owned results at the API level; optimized immediate consumers can eliminate fragment materialization. Rust/Zig use borrowed slices. Ports remain unchanged.',
                               'Historical ratios are not used; all comparisons use fresh same-round guest runs. No aggregate score.'])
    lines = ['# Fresh text-gap comparison', '', f'All {len(cells)} selected cells passed oracle, identity, round-order, RSS and counted ownership validation.', '',
             'Ratios compare checked elapsed time with the named reference; below one is faster. CIs are paired exploratory 95% bootstrap intervals.', '',
             '| Case/profile | Checked arm | Median µs | / ZigSafe | / ZigFast | / Rust | / Go |',
             '| --- | --- | ---: | --- | --- | --- | --- |']
    for cell in cells:
        for name, arm in cell['arms'].items():
            if not name.startswith('checked-'):
                continue
            columns = []
            for other in ('zig-safe', 'zig-fast', 'rust', 'go'):
                r = cell['comparisons'][name + '/' + other]
                columns.append(f"{r['ratio']:.3f} [{r['ci95'][0]:.3f}, {r['ci95'][1]:.3f}]")
            lines.append(f"| {cell['case']}/{cell['profile']} | {name} | {arm['median_ns']/1000:.3f} | " + ' | '.join(columns) + ' |')
    lines += ['', '| Case/profile | Iterations | Calibration | Fastest pilot ms | Limited | Noise flags |', '| --- | ---: | --- | ---: | --- | --- |']
    for cell in cells:
        c = cell['calibration']
        lines.append(f"| {cell['case']}/{cell['profile']} | {cell['iterations']} | {c['reason']} | {c['fastest_ns']/1e6:.2f} | {c['limited']} | {', '.join(cell['noise_flags']) or 'none'} |")
    lines += ['', 'Noise flags retain all samples: MAD/median >5% or final-five/first-five drift >10%. Raw ranges and per-arm drift are in report.json.', '',
              '| Case/profile | Arm | Process RSS KiB median [range] | Managed peak bytes | Cumulative managed bytes | Managed allocations |',
              '| --- | --- | ---: | ---: | ---: | ---: |']
    for cell in cells:
        for name, arm in cell['arms'].items():
            rss = arm['rss_kib']; m = arm.get('managed', {})
            lines.append(f"| {cell['case']}/{cell['profile']} | {name} | {rss['median']} [{rss['min']}, {rss['max']}] | {m.get('peak_live_bytes', 'unavailable')} | {m.get('cumulative_allocated_bytes', 'unavailable')} | {m.get('allocs', 'unavailable')} |")
    lines += ['', *report['limitations'], '']
    a.output.mkdir(parents=True)
    (a.output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    (a.output / 'REPORT.md').write_text('\n'.join(lines))
    print('validated cells:', len(cells), a.output)


if __name__ == '__main__':
    main()
