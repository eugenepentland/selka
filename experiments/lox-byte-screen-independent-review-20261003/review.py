#!/usr/bin/env python3
"""Read-only reconciliation; does not import the measurement's analyzer or run guests."""
import argparse
import gzip
import hashlib
import itertools
import json
import math
from pathlib import Path
import re
import statistics
import subprocess


def digest_bytes(data):
    return hashlib.sha256(data).hexdigest()


def digest(path):
    return digest_bytes(Path(path).read_bytes())


def read(path):
    return json.loads(Path(path).read_text())


def close(actual, expected):
    assert math.isclose(actual, expected, rel_tol=1e-13, abs_tol=1e-12), (actual, expected)


def source_map(path):
    return {str(p.relative_to(path)): digest(p) for p in sorted(path.rglob('*')) if p.is_file()}


def reconcile_receipt(work, experiment, manifest, name, phase, tier, cpu, rounds, arms):
    raw_path = work / 'measurements' / f'{name}.json'
    raw_bytes = raw_path.read_bytes()
    assert gzip.decompress((experiment / f'{name}.json.gz').read_bytes()) == raw_bytes
    raw = json.loads(raw_bytes)
    assert (raw['phase'], raw['tier'], raw['cpu'], raw['rounds']) == (phase, tier, cpu, rounds)
    assert raw['verified_after'] is True
    assert raw['manifest'] == manifest
    assert raw['binary_sha256'] == {arm: manifest['binary_sha256'][arm] for arm in arms}
    cases = {c['id']: c for c in raw['cases']}
    assert len(cases) == len(raw['cases']) == 26
    names = {c['name'] for c in cases.values()}
    assert len(names) == 13
    assert set(cases) == {f'{engine}/{name}' for engine in ['tree', 'vm'] for name in names}
    reference_names = {p.stem for p in (work / 'reference/benchmarks/lox/bench/scripts').glob('*.lox')}
    assert names == reference_names
    inputs = {}
    for key, case in cases.items():
        assert key == f"{case['engine']}/{case['name']}"
        assert digest(case['script']) == case['script_sha256']
        assert Path(case['expected']).is_file()
        expected_tier = case['engine'] if tier == 'timed' else tier
        assert Path(case['expected']).name == f"{case['name']}.{expected_tier}.out"
        inputs[case['script']] = case['script_sha256']
    observed = {}
    pmu_checks = 0
    stats_by_case = {}
    for row in raw['samples']:
        key = (row['case'], row['arm'], row['round'])
        assert key not in observed, key
        observed[key] = row
        case = cases[row['case']]
        assert row['status'] == 0
        assert row['stdout_sha256'] == digest(case['expected'])
        assert math.isfinite(row['wall_s']) and row['wall_s'] > 0
        if phase == 'check':
            match = re.fullmatch(r'\[stats\] engine=(tree|vm) allocations=(\d+) collections=(\d+) freed=(\d+) live=(\d+)\n', row['stderr'])
            assert match and match[1] == case['engine']
            stats = dict(zip(['allocations', 'collections', 'freed', 'live'], map(int, match.groups()[1:])))
            assert stats == row['collector_stats']
            assert stats['live'] == stats['allocations'] - stats['freed'] >= 0
            if row['case'] in stats_by_case:
                assert stats == stats_by_case[row['case']]
            stats_by_case[row['case']] = stats
        else:
            assert row['stderr'] == ''
        if phase == 'counters':
            for event in ['instructions', 'cycles', 'branches', 'branch-misses']:
                assert isinstance(row[event], int) and row[event] >= 0
                assert row[f'{event}_running_pct'] == 100.0
                pmu_checks += 1
            assert row['instructions'] > 0
    expected_cells = set(itertools.product(cases, arms, range(rounds)))
    assert set(observed) == expected_cells
    command_path = experiment / f'{name}.command.json'
    assert command_path.read_bytes() == (work / 'measurements' / f'{name}.command.json').read_bytes()
    command = read(command_path)
    assert command['status'] == 0 and command['sources_verified_after'] is True
    assert command['manifest_sha256'] == digest(work / 'binaries.json')
    assert command['source_hashes_before'] == command['source_hashes_after']
    assert digest(experiment / f'{name}.log') == command['log_sha256']
    argv = command['argv']
    assert argv[2] == phase and argv[argv.index('--tier') + 1] == tier
    assert int(argv[argv.index('--rounds') + 1]) == rounds
    assert int(argv[argv.index('--cpu') + 1]) == cpu
    assert argv[argv.index('--arms') + 1].split(',') == arms
    assert ('--stats' in argv) == (phase == 'check')
    return raw, observed, {'raw_sha256': digest_bytes(raw_bytes), 'archive_sha256': digest(experiment / f'{name}.json.gz'),
                           'command_sha256': digest(command_path), 'rows': len(observed), 'case_count': len(cases),
                           'arms': arms, 'rounds': rounds, 'cpu': cpu, 'tier': tier, 'pmu_checks': pmu_checks,
                           'materialized_inputs': inputs, 'stats': stats_by_case,
                           'status_output_stderr_verified': True, 'coverage_verified': True}


def recompute(raw, cells, published, metric):
    families = {}
    expected_pairs = [('octets-llvm', 'baseline-llvm'), ('octets-qbe', 'baseline-qbe')]
    if metric == 'wall_s':
        expected_pairs += [(candidate, control) for candidate in ['octets-llvm', 'octets-qbe'] for control in ['rust', 'go']]
    assert set(published['comparisons']) == {f'{a}-over-{b}' for a, b in expected_pairs}
    assert published['receipt_sha256'] == digest(published['receipt'])
    assert published['samples'] == len(raw['samples']) and published['coverage_verified'] is True
    assert published['metric'] == metric and published['screen_only'] == (metric == 'instructions')
    for candidate, control in expected_pairs:
        name = f'{candidate}-over-{control}'
        expected = published['comparisons'][name]
        assert (expected['candidate'], expected['baseline'], expected['metric']) == (candidate, control, metric)
        rows = {}
        for case in sorted(c['id'] for c in raw['cases']):
            ratios = [cells[(case, candidate, r)][metric] / cells[(case, control, r)][metric] for r in range(raw['rounds'])]
            median = statistics.median(ratios)
            spread = (max(ratios) - min(ratios)) / median * 100
            rows[case] = {'candidate_over_control': median, 'change_pct': (median - 1) * 100,
                          'paired_ratios': ratios, 'spread_pct': spread}
            item = expected['rows'][case]
            close(median, item['candidate_over_baseline'])
            close((1 - median) * 100, item['reduction_pct'])
            close(spread, item['spread_pct'])
            assert ratios == item['paired_ratios']
        assert set(rows) == set(expected['rows'])
        engines = {}
        for engine in ['tree', 'vm']:
            selected = {k: v for k, v in rows.items() if k.startswith(engine + '/')}
            assert len(selected) == 13
            geomean = math.exp(math.fsum(math.log(v['candidate_over_control']) for v in selected.values()) / 13)
            close(geomean, expected['engines'][engine]['candidate_over_baseline'])
            assert expected['engines'][engine]['cases'] == 13
            close((1 - geomean) * 100, expected['engines'][engine]['reduction_pct'])
            engines[engine] = {'candidate_over_control': geomean, 'change_pct': (geomean - 1) * 100,
                               'cases_faster': sum(v['candidate_over_control'] < 1 for v in selected.values()),
                               'median_spread_pct': statistics.median(v['spread_pct'] for v in selected.values()),
                               'maximum_spread_pct': max(v['spread_pct'] for v in selected.values()),
                               'regressions': [k for k, v in selected.items() if v['candidate_over_control'] > 1]}
        families[name] = {'metric': metric, 'engines': engines, 'cases': rows}
    return families


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--author', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    root, author = args.root, args.author
    work = root / '.tmp-lox-byte-screen-ready'
    experiment = root / 'experiments/lox-byte-source-screen-20261003'
    guards = read(work / 'guards.json')
    assert len(guards) == 152
    for path, sha in guards.items():
        assert digest(path) == sha, path
    checkpoint = read(experiment / 'checkpoint.json')
    initial_payload = {name: digest(experiment / name) for name in checkpoint['payload_sha256']}
    assert initial_payload == checkpoint['payload_sha256']
    manifest = read(work / 'binaries.json')
    assert digest(experiment / 'binaries.json') == digest(work / 'binaries.json') == checkpoint['original_manifest_sha256']
    prepared = read(work / 'prepared.json')
    author_sources = read(author / 'experiments/lox-vm-bytecode-20261003/sources.json')
    author_qualification_path = author / 'experiments/lox-vm-bytecode-20261003/qualification.json'
    author_qualification = read(author_qualification_path)
    historical_qualification = author_qualification['variants']['octets-shape-v3']
    assert historical_qualification['public_fresh'] == 352
    assert historical_qualification['native_bounded'] == 1192
    assert historical_qualification['operand255_pairs'] == 12
    assert historical_qualification['argument_limit_pairs'] == 192
    assert historical_qualification['rc_native_stress_refusal_pairs'] == 8
    expected_sources = {'baseline': author_sources['control37'], 'octets': author_sources['octets-shape-v3']['source37']}
    for arm, descriptor in manifest['candidate_sources'].items():
        actual = source_map(Path(descriptor['path']))
        assert len(actual) == 37 and actual == descriptor['all_files'] == expected_sources[arm]
        assert descriptor['hashes'] == {k: v for k, v in actual.items() if k.endswith('.my')}
        assert len(descriptor['hashes']) == 26
        assert prepared['sources'][arm] == descriptor
    interpreter = expected_sources['baseline']['interpreter.my']
    assert interpreter == expected_sources['octets']['interpreter.my'] == '60009d57779858c501cbd0f1a94a1a1177afeeff0f62822f9a12acb1cf074c7e'
    assert manifest['candidate_source_variant'] == 'octets-shape-v3'
    assert manifest['candidate_author_commit'] == 'beaaf97c7397beafb0988f5ed73dde0bf4813ebb'
    assert manifest['compiler_sha256'] == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
    assert manifest['qbe_sha256'] == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
    for key in ['compiler', 'qbe']:
        assert digest(manifest[key]) == manifest[f'{key}_sha256'] == prepared[f'{key}_sha256']
    for key, sha in prepared['reference_bench_files'].items():
        assert digest(work / 'reference' / key) == sha
    assert len(prepared['reference_bench_files']) == 53
    for key, sha in prepared['helper_sha256'].items():
        assert digest(root / key) == sha
    assert len(manifest['binaries']) == 6
    for arm, path in manifest['binaries'].items():
        assert digest(path) == manifest['binary_sha256'][arm]
    for arm, sha in prepared['inherited_hashes'].items():
        assert manifest['binary_sha256'][arm] == sha
    build = read(manifest['build_receipt'])
    assert digest(manifest['build_receipt']) == manifest['build_receipt_sha256'] == digest(experiment / 'octets-build.json')
    assert build['compiler_sha256'] == manifest['compiler_sha256'] and build['runtime'] == 'rc'
    assert build['source_sha256'] == manifest['candidate_sources']['octets']['hashes']
    sidecars = {}
    for arm in ['baseline-llvm', 'baseline-qbe', 'octets-llvm', 'octets-qbe']:
        binary = Path(manifest['binaries'][arm])
        sidecar_path = Path(str(binary) + '.qbe-manifest.json')
        sidecar = read(sidecar_path)
        backend = arm.rsplit('-', 1)[1]
        assert sidecar['backend'] == backend
        assert (sidecar['optimization'], sidecar['lto']) == (('3', True) if backend == 'llvm' else ('default', False))
        runtime = sidecar['runtime_object']
        assert str(sidecar_path) in guards and runtime in guards
        inherited = arm.startswith('baseline-')
        assert ('.tmp-lox-next/' in runtime) == inherited
        receipt_path = Path(str(binary) + '.qbe-receipt')
        assert receipt_path.exists() == (not inherited)
        if receipt_path.exists():
            assert str(receipt_path) in guards
        sidecars[arm] = {'manifest_sha256': digest(sidecar_path), 'runtime_object': runtime,
                         'runtime_sha256': digest(runtime), 'inherited_absolute_paths': inherited,
                         'private_receipt_present': receipt_path.exists()}
    assert len(build['builds']) == 2
    for item in build['builds']:
        backend = item['codegen']['backend']
        arm = f'octets-{backend}'
        assert item['status'] == 0
        argv = item['argv']
        assert argv[1] == 'build' and argv[2] == manifest['compiler']
        assert all(flag in argv for flag in ['--project', '--rc-runtime', '--keep-symbols', '--cache-dir'])
        assert argv[argv.index('--backend') + 1] == backend
        if backend == 'llvm':
            assert '--lto' in argv and argv[argv.index('--llvm-opt') + 1] == '3'
        assert item['binary_sha256'] == manifest['binary_sha256'][arm] == prepared['author_v3_binary_sha256'][arm]
        assert item['manifest_sha256'] == sidecars[arm]['manifest_sha256']
        assert item['runtime_object_sha256'] == sidecars[arm]['runtime_sha256']
        author_binary = author / '.tmp-lox-vm-bytecode-20261003' / f'octets-shape-v3-{backend}'
        assert digest(author_binary) == item['binary_sha256']
    phases = {}
    loaded = {}
    six_arms = ['baseline-llvm', 'baseline-qbe', 'octets-llvm', 'octets-qbe', 'rust', 'go']
    for name, phase, tier, cpu, rounds, arms in [('smoke', 'check', 'smoke', 0, 1, six_arms),
                                               ('instruction-screen', 'counters', 'tree', 10, 1, six_arms[:4]),
                                               ('wall', 'time', 'timed', 2, 3, six_arms)]:
        raw, cells, details = reconcile_receipt(work, experiment, manifest, name, phase, tier, cpu, rounds, arms)
        command = read(experiment / f'{name}.command.json')
        for key, descriptor in manifest['candidate_sources'].items():
            assert command['source_hashes_before'][key] == descriptor['hashes']
        loaded[name] = (raw, cells)
        phases[name] = details
    assert [phases[k]['rows'] for k in ['smoke', 'instruction-screen', 'wall']] == [156, 104, 468]
    assert sum(d['rows'] for d in phases.values()) == 728
    assert phases['instruction-screen']['pmu_checks'] == 416
    results = {metric: recompute(*loaded[name], read(experiment / f'{analysis}.json'), metric)
               for metric, name, analysis in [('instructions', 'instruction-screen', 'instruction-analysis'), ('wall_s', 'wall', 'wall-analysis')]}
    summary = read(experiment / 'wall-summary.json')
    for family, value in results['wall_s'].items():
        for engine, item in value['engines'].items():
            expected = summary[family][engine]
            close(item['candidate_over_control'], expected['ratio'])
            close(-item['change_pct'], expected['reduction_pct'])
            close(item['median_spread_pct'], expected['median_spread_pct'])
            assert item['cases_faster'] == expected['cases_faster']
    closeout = read(experiment / 'wall-closeout.json')
    assert (experiment / 'wall-closeout.json').read_bytes() == (work / 'wall-closeout.json').read_bytes()
    assert closeout['complete'] is True and closeout['analysis_status'] == 0 and closeout['all_inputs_unchanged'] is True
    assert closeout['guarded_inputs'] == 152 and closeout['wall_rows'] == 468
    assert closeout['guards_sha256'] == digest(work / 'guards.json') == digest(experiment / 'guards.json')
    assert closeout['raw_sha256'] == phases['wall']['raw_sha256'] == 'b2f8ec5e44d819b074bd3019eed5d06e304f1eec861639c23a4072f29acdeadc'
    assert closeout['analysis_sha256'] == digest(experiment / 'wall-analysis.json')
    assert closeout['command_sha256'] == phases['wall']['command_sha256']
    assert closeout['worker_sha256'] == digest(experiment / 'finish-wall-worker.py') == digest(work / 'finish-wall.py')
    assert checkpoint['full_wall_complete'] is True and checkpoint['counter_screen_only'] is True
    assert checkpoint['selected'] is False and checkpoint['main_merged'] is False
    assert checkpoint['complete_smoke_rows'] == 156 and checkpoint['complete_diagnostic_counter_rows'] == 104
    assert checkpoint['complete_wall_rows'] == checkpoint['wall_expected_unique_cells'] == 468
    assert checkpoint['all_pmu_rates_equal_100'] == 416
    assert checkpoint['wall_closeout_sha256'] == digest(experiment / 'wall-closeout.json')
    after_screen = read(experiment / 'guard-after-screen.json')
    assert after_screen['all_unchanged'] is True and after_screen['unchanged_inputs'] == 152
    assert after_screen['smoke_rows'] == 156 and after_screen['instruction_rows'] == 104
    assert after_screen['pmu_running_percentages_100'] == 416
    historical_bytes = subprocess.check_output(['git', '-C', str(root), 'show', '12a401b1:experiments/lox-byte-source-screen-20261003/checkpoint.json'])
    assert historical_bytes == (experiment / 'historical-diagnostic-checkpoint.json').read_bytes()
    historical = json.loads(historical_bytes)
    assert historical['full_wall_complete'] is False and historical['selected'] is False
    for name, sha in historical['payload_sha256'].items():
        if name == 'README.md':
            old = subprocess.check_output(['git', '-C', str(root), 'show', '12a401b1:experiments/lox-byte-source-screen-20261003/README.md'])
            assert digest_bytes(old) == sha
        else:
            assert digest(experiment / name) == sha
    assert checkpoint['guardian']['status'] == 0 and checkpoint['guardian']['passed'] == 88
    assert checkpoint['guardian']['log_sha256'] == digest(experiment / 'guardian-screen.log')
    for path, sha in guards.items():
        assert digest(path) == sha
    assert initial_payload == {name: digest(experiment / name) for name in initial_payload}
    for details in phases.values():
        for path, sha in details['materialized_inputs'].items():
            assert digest(path) == sha
    result = {'reviewer': 'frames', 'root': str(root), 'reviewed_checkpoint_sha256': digest(experiment / 'checkpoint.json'),
              'reviewed_readme_sha256': digest(experiment / 'README.md'), 'manifest_sha256': digest(work / 'binaries.json'),
              'binary_sha256': manifest['binary_sha256'], 'compiler_sha256': manifest['compiler_sha256'],
              'qbe_sha256': manifest['qbe_sha256'], 'source_maps': expected_sources, 'sidecars': sidecars,
              'guarded_inputs_unchanged': 152, 'original_unique_rows': 728, 'measurement_phases': phases,
              'independent_comparison_families': 8, 'comparisons': results,
              'closeout_sha256': digest(experiment / 'wall-closeout.json'),
              'historical_checkpoint_sha256': digest_bytes(historical_bytes), 'historical_snapshot_is_additional_run': False,
              'distinct_author_qualification': {'qualification_sha256': digest(author_qualification_path),
                                               'public_accounted_executions': 352, 'native_program_pairs': 1396,
                                               'rc_refusal_pairs': 8, 'not_additional_measurement_rows': True},
              'all_before_after_identities_unchanged': True, 'all_published_numbers_reproduced': True,
              'scope': ['Source-only corrected octets-shape-v3 against pre-AST source84, frozen d14/QBE99ad.',
                        'AST composition is outside all measured manifests; baseline and candidate share the older interpreter.',
                        'Counters are one-round diagnostics on tree-sized workloads; wall uses engine-specific sizes for three rounds.',
                        'Output verification is receipt stdout SHA against frozen expected bytes; receipt stderr/stats are complete.',
                        'Native/public behavior qualification is separate, not additional measurement observations.',
                        'Inherited baseline manifests/runtime archives retain original paths; copied baseline qbe-receipts are absent.',
                        'No root analyzer imported or executed; no guests, tests, builds or performance runs.'],
              'finding': 'No actionable reconciliation defect. The small wall movements do not support promotion or parity.'}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'original_rows': 728, 'pmu_checks_100': 416, 'guards_unchanged': 152,
                      'comparison_families': 8, 'published_numbers_reproduced': True,
                      'review_sha256': digest(args.out)}, sort_keys=True))


if __name__ == '__main__':
    main()
