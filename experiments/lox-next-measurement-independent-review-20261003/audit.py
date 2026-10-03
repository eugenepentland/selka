#!/usr/bin/env python3
"""Read-only independent validation of completed Lox measurements; no guest runs."""
import argparse
import datetime
import hashlib
import itertools
import json
import math
from pathlib import Path
import random
import re
import statistics
import subprocess


READS = {}


def read(path):
    path = Path(path)
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    assert str(path) not in READS or READS[str(path)] == digest, str(path)
    READS[str(path)] = digest
    return data


def sha(path):
    read(path)
    return READS[str(Path(path))]


def load(path):
    return json.loads(read(path))


def same(left, right):
    if isinstance(left, dict):
        assert left.keys() == right.keys(), (left.keys(), right.keys())
        for key in left:
            same(left[key], right[key])
    elif isinstance(left, list):
        assert len(left) == len(right)
        for a, b in zip(left, right):
            same(a, b)
    elif isinstance(left, float):
        assert math.isclose(left, right, rel_tol=1e-12, abs_tol=1e-12), (left, right)
    else:
        assert left == right, (left, right)


def option(argv, name):
    return argv[argv.index(name) + 1]


def sources(source):
    directory = Path(source['path'])
    files = {str(p.relative_to(directory)): sha(p)
             for p in sorted(directory.rglob('*')) if p.is_file()}
    assert len(files) == 37
    assert files == source['all_files']
    modules = {p.name: sha(p) for p in sorted(directory.glob('*.my'))}
    assert len(modules) == 26 and modules == source['hashes']
    identity = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    return {'path': str(directory), 'files_checked': 37, 'modules_checked': 26,
            'all_files_identity_sha256': identity}


def manifest(path):
    doc = load(path)
    for arm, binary in doc['binaries'].items():
        assert sha(binary) == doc['binary_sha256'][arm], arm
    assert sha(doc['compiler']) == doc['compiler_sha256']
    qbe = Path(doc['compiler']).parent / 'qbe'
    qbe_hash = sha(qbe)
    assert qbe_hash == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
    checked = {}
    for name, source in doc['candidate_sources'].items():
        checked[name] = sources(source)
        if 'compiler' in source:
            assert sha(source['compiler']) == source['compiler_sha256']
            assert sha(Path(source['compiler']).parent / 'qbe') == qbe_hash
        if 'build_receipt' in source:
            assert sha(source['build_receipt']) == source['build_receipt_sha256']
    reference = Path(path).parent / 'reference'
    for name, digest in doc['reference_source_hashes'].items():
        assert sha(reference / name) == digest, name
    return doc, {'path': str(path), 'sha256': sha(path),
                 'binaries': doc['binary_sha256'], 'sources': checked,
                 'reference_files': len(doc['reference_source_hashes']),
                 'qbe_sha256': qbe_hash}


def codegen(binary, meta_hash, runtime, runtime_hash, backend):
    metadata_path = Path(str(binary) + '.qbe-manifest.json')
    metadata = load(metadata_path)
    assert sha(metadata_path) == meta_hash
    assert metadata['backend'] == backend
    assert metadata['optimization'] == ('3' if backend == 'llvm' else 'default')
    assert metadata['lto'] == (backend == 'llvm')
    assert not metadata['thin_lto']
    assert metadata['abi'] == 'mylang-qbe-native-v9'
    assert metadata['runtime_object'] == runtime
    assert sha(runtime) == runtime_hash


def builds(path, expected_sources, measured_hashes):
    doc = load(path)
    if 'source_sha256' in doc:
        assert doc['source_sha256'] == expected_sources['hashes']
    if 'runtime' in doc:
        assert doc['runtime'] == 'rc'
    if 'source_manifest' in doc:
        assert sha(doc['source_manifest']) == doc['source_manifest_sha256']
    entries = doc.get('builds')
    if entries is None:
        entries = []
        for binary in doc['binaries'].values():
            matching = [c for c in doc['commands'] if option(c['command'], '-o') == binary['path']]
            assert len(matching) == 1
            entries.append({**binary, 'binary': binary['path'], 'binary_sha256': binary['sha256'],
                            'argv': matching[0]['command'], 'status': matching[0]['status']})
    result = []
    for build in entries:
        argv = build['argv']
        if '--rc-runtime' not in argv:
            continue
        assert build['status'] == 0
        assert argv[0].endswith('/scripts/build-slot.sh') and argv[1] == 'build'
        assert '--gc-runtime' not in argv
        assert '--drop-checks' not in argv
        compiler = argv[2]
        assert sha(compiler) == doc['compiler_sha256']
        assert sha(Path(compiler).parent / 'qbe') == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
        if 'source_files' in build:
            assert build['source_files'] == expected_sources['all_files']
            assert build['source_verified_after'] and build['compiler_verified_after']
        binary = build.get('binary', option(argv, '-o'))
        digest = sha(binary)
        assert digest == build['binary_sha256'] and digest in measured_hashes
        backend = option(argv, '--backend')
        if backend == 'llvm':
            assert option(argv, '--llvm-opt') == '3' and '--lto' in argv
        else:
            assert backend == 'qbe' and '--lto' not in argv
        codegen(binary, build['manifest_sha256'], build['runtime_object'],
                build['runtime_object_sha256'], backend)
        result.append({'binary': str(binary), 'sha256': digest, 'backend': backend,
                       'compiler_sha256': doc['compiler_sha256'],
                       'manifest_sha256': build['manifest_sha256'],
                       'runtime_object_sha256': build['runtime_object_sha256']})
    assert len(result) == 2
    return {'receipt': str(path), 'receipt_sha256': sha(path), 'builds': result}


def summary(samples):
    result = {}
    for case in sorted({s['case'] for s in samples}):
        result[case] = {}
        for arm in sorted({s['arm'] for s in samples}):
            rows = [s for s in samples if s['case'] == case and s['arm'] == arm]
            walls = [s['wall_s'] for s in rows]
            median = statistics.median(walls)
            row = {'wall_s': median, 'wall_spread': (max(walls) - min(walls)) / median,
                   'samples': len(rows)}
            for field in ('instructions', 'cycles', 'branches', 'branch-misses'):
                if field in rows[0]:
                    row[field] = statistics.median(s[field] for s in rows)
            if 'instructions' in row:
                row['ipc'] = row['instructions'] / row['cycles']
            result[case][arm] = row
    return result


def measurement(path, current_manifest):
    doc = load(path)
    command_path = path.with_suffix('.command.json')
    command = load(command_path)
    argv = command['argv']
    assert command['status'] == 0 and command['sources_verified_after']
    assert command['source_hashes_before'] == command['source_hashes_after']
    assert command['source_hashes_before'] == {k: v['hashes'] for k, v in current_manifest['candidate_sources'].items()}
    assert command['manifest_sha256'] == sha(path.parent.parent / 'binaries.json')
    assert sha(path.with_suffix('.log')) == command['log_sha256']
    assert doc['manifest'] == current_manifest
    assert doc['verified_after'] and doc['finished_utc']
    arms = option(argv, '--arms').split(',')
    engines = option(argv, '--engines').split(',')
    assert engines == ['vm', 'tree']
    assert '--cases' not in argv
    assert len(arms) == len(set(arms))
    assert int(option(argv, '--rounds')) == doc['rounds']
    assert option(argv, '--tier') == doc['tier']
    assert int(option(argv, '--cpu')) == doc['cpu']
    assert argv[2] == doc['phase']
    assert doc['binary_sha256'] == {a: current_manifest['binary_sha256'][a] for a in arms}
    reference = path.parent.parent / 'reference/benchmarks/lox/bench'
    sizes = load(reference / 'sizes.json')
    scripts = sorted((reference / 'scripts').glob('*.lox'))
    assert len(scripts) == 13
    expected_ids = [f'{e}/{p.stem}' for e in engines for p in scripts]
    assert [c['id'] for c in doc['cases']] == expected_ids
    expected_hashes = {}
    for case in doc['cases']:
        key = case['engine'] if doc['tier'] == 'timed' else doc['tier']
        assert case['size'] == sizes[case['name']][key]
        first, rest = read(reference / 'scripts' / (case['name'] + '.lox')).decode().split('\n', 1)
        assert first.startswith('var N = ')
        assert read(case['script']) == f"var N = {case['size']};\n{rest}".encode()
        assert sha(case['script']) == case['script_sha256']
        assert Path(case['expected']) == reference / 'expected' / (case['name'] + '.' + key + '.out')
        expected_hashes[case['id']] = sha(case['expected'])
    actual = [(s['case'], s['arm'], s['round']) for s in doc['samples']]
    expected = set(itertools.product(expected_ids, arms, range(doc['rounds'])))
    assert len(actual) == len(expected) and set(actual) == expected
    rng = random.Random(20261002)
    ordering = []
    for round_index in range(doc['rounds']):
        for case in expected_ids:
            order = list(arms)
            rng.shuffle(order)
            ordering.extend((case, a, round_index) for a in order)
    assert actual == ordering
    assert len(doc['quiet_waits']) == 26 * doc['rounds']
    assert all(max(w['busy'].values()) < .25 for w in doc['quiet_waits'])
    pmu = 0
    statistics_rows = 0
    stats_by_case = {}
    for sample in doc['samples']:
        assert sample['status'] == 0 and sample['wall_s'] > 0
        assert sample['stdout_sha256'] == expected_hashes[sample['case']]
        assert sample['stderr'].isascii() and len(sample['stderr']) < 1500
        if '--stats' in argv:
            pattern = r'\[stats\] engine=(vm|tree) allocations=(\d+) collections=(\d+) freed=(\d+) live=(\d+)\n'
            found = re.fullmatch(pattern, sample['stderr'])
            assert found and found[1] == sample['case'].split('/')[0]
            stats = dict(zip(('allocations', 'collections', 'freed', 'live'), map(int, found.groups()[1:])))
            assert sample['collector_stats'] == stats
            if sample['case'] in stats_by_case:
                assert stats_by_case[sample['case']] == stats
            stats_by_case[sample['case']] = stats
            statistics_rows += 1
        else:
            assert sample['stderr'] == ''
        if doc['phase'] == 'counters':
            for event in ('instructions', 'cycles', 'branches', 'branch-misses'):
                assert isinstance(sample[event], int) and sample[event] >= 0
                assert sample[event + '_running_pct'] == 100.0
                pmu += 1
    same(summary(doc['samples']), doc['summary'])
    lines = read(path.with_suffix('.log')).decode().splitlines()
    assert len(lines) == 26 * doc['rounds']
    assert all(line.startswith(doc['phase'] + ' round ') for line in lines)
    return doc, {'path': str(path), 'sha256': sha(path), 'command_sha256': sha(command_path),
                 'log_sha256': command['log_sha256'], 'phase': doc['phase'], 'tier': doc['tier'],
                 'cpu': doc['cpu'], 'rounds': doc['rounds'], 'arms': arms, 'cases': 26,
                 'expected_samples': len(expected), 'actual_samples': len(actual),
                 'unique_complete_coverage': True, 'correct_output_hash_samples': len(actual),
                 'complete_ascii_stderr_samples': len(actual), 'exact_statistics_samples': statistics_rows,
                 'all_pmu_rates_100_count': pmu, 'summary_and_randomized_order_verified': True}


def compare(doc, control, candidate, metric):
    by_key = {(s['case'], s['arm'], s['round']): s for s in doc['samples']}
    rows = {}
    for case in sorted(c['id'] for c in doc['cases']):
        ratios = [by_key[case, candidate, r][metric] / by_key[case, control, r][metric]
                  for r in range(doc['rounds'])]
        median = statistics.median(ratios)
        rows[case] = {'candidate_over_baseline': median, 'reduction_pct': 100 * (1 - median),
                      'paired_ratios': ratios, 'spread_pct': 100 * (max(ratios) - min(ratios)) / median}
    engines = {}
    for engine in ['vm', 'tree']:
        values = [r['candidate_over_baseline'] for c, r in rows.items() if c.startswith(engine + '/')]
        assert len(values) == 13
        gm = math.exp(math.fsum(math.log(v) for v in values) / len(values))
        engines[engine] = {'cases': 13, 'candidate_over_baseline': gm, 'reduction_pct': 100 * (1 - gm)}
    return {'baseline': control, 'candidate': candidate, 'metric': metric, 'rows': rows, 'engines': engines}


def analysis(path, doc):
    recorded = load(path)
    recomputed = {}
    for key, comparison in recorded['comparisons'].items():
        computed = compare(doc, comparison['baseline'], comparison['candidate'], comparison['metric'])
        same(computed, comparison)
        recomputed[key] = computed['engines']
    assert recorded['samples'] == len(doc['samples'])
    return {'path': str(path), 'sha256': sha(path), 'all_rows_and_engine_arithmetic_verified': True,
            'comparisons': recomputed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists(), 'receipt must be new; preserve previous observations'
    root = args.root.resolve()
    nextwork = root / '.tmp-lox-next'
    writework = root / '.tmp-lox-write-screen'
    next_manifest, next_report = manifest(nextwork / 'binaries.json')
    write_manifest, write_report = manifest(writework / 'binaries.json')
    assert len(next_manifest['binaries']) == len(write_manifest['binaries']) == 10
    build_reports = []
    measured = set(next_manifest['binary_sha256'].values()) | set(write_manifest['binary_sha256'].values())
    for label, source in next_manifest['candidate_sources'].items():
        receipt = source.get('build_receipt', str(root / '.tmp-lox-parity/carrier-final-sweep-build.json'))
        build_reports.append(builds(Path(receipt), source, measured))
    for label in ['write-baseline', 'write-combined']:
        source = write_manifest['candidate_sources'][label]
        build_reports.append(builds(Path(source['build_receipt']), source, measured))
    metadata_hashes = {b['sha256']: b['manifest_sha256'] for r in build_reports for b in r['builds']}
    metadata_copies = []
    for doc in [next_manifest, write_manifest]:
        for arm, binary in doc['binaries'].items():
            if arm in ['rust', 'go']:
                continue
            sidecar = Path(str(binary) + '.qbe-manifest.json')
            if sidecar.exists():
                assert sha(sidecar) == metadata_hashes[doc['binary_sha256'][arm]]
                state = 'copied/original metadata hash matches build receipt'
            else:
                assert doc is write_manifest and arm in ['baseline-llvm', 'baseline-qbe', 'combined-llvm', 'combined-qbe']
                assert doc['binary_sha256'][arm] == next_manifest['binary_sha256'][arm]
                state = 'control copy has no sidecar; identical binary uses checked original build metadata'
            metadata_copies.append({'binary': str(binary), 'metadata': state})
    lowering = root.parent / 'codex-lox-parity-lowering-20261003'
    replay_path = lowering / 'experiments/lox-parity-20261003/positive-index-cfg-fix-guest-replay.json'
    replay = load(replay_path)
    assert replay['verified_after'] and replay['all_guests_byte_identical']
    assert replay['compiler_sha256'] == next_manifest['compiler_sha256']
    assert replay['source_sha256'] == next_manifest['candidate_sources']['baseline']['all_files']
    assert sha(replay['control_receipt']) == replay['control_receipt_sha256']
    for build in replay['builds']:
        assert build['status'] == 0 and build['byte_identical_to_measured_control']
        assert sha(build['log']) == build['log_sha256']
        assert sha(build['binary']) == build['binary_sha256'] == sha(build['measured_control_binary'])
        assert build['binary_sha256'] in measured
    docs = {}
    reports = []
    required = [(nextwork, 'source-screen-smoke'), (nextwork, 'source-screen-counters'),
                (nextwork, 'combined-timing'), (writework, 'write-screen-smoke')]
    pending = []
    for name in ['write-screen-counters', 'write-screen-timing', 'write-combined-timing', 'write-combined-counters']:
        path = writework / 'measurements' / (name + '.json')
        if path.exists():
            current = json.loads(path.read_bytes())
            if current.get('verified_after'):
                required.append((writework, name))
            else:
                pending.append({'path': str(path), 'state': 'partial, excluded from pass coverage',
                                'observed_samples': len(current['samples'])})
        else:
            pending.append({'path': str(path), 'state': 'unrun or absent, no pass claimed'})
    for work, name in required:
        doc, result = measurement(work / 'measurements' / (name + '.json'),
                                  next_manifest if work == nextwork else write_manifest)
        docs[name] = doc
        reports.append(result)
    analyses = [analysis(nextwork / 'measurements/combined-wall-analysis.json', docs['combined-timing']),
                analysis(nextwork / 'measurements/source-screen-analysis.json', docs['source-screen-counters'])]
    write_analysis = writework / 'measurements/write-screen-analysis.json'
    if write_analysis.exists() and 'write-screen-counters' in docs:
        analyses.append(analysis(write_analysis, docs['write-screen-counters']))
    validation = load(nextwork / 'measurements/source-screen-smoke-validation.json')
    assert validation['receipt_sha256'] == sha(nextwork / 'measurements/source-screen-smoke.json')
    assert validation['samples'] == 208 and validation['unique_coverage']
    assert validation['exact_output_status_diagnostics_collector_statistics_match']
    failed_path = writework / 'measurements/smoke.command.json'
    failed = load(failed_path)
    assert failed['status'] == 2 and failed['argv'][2] == 'smoke'
    assert failed['sources_verified_after'] and failed['source_hashes_before'] == failed['source_hashes_after']
    assert failed['manifest_sha256'] == sha(writework / 'binaries.json')
    assert sha(failed_path.with_suffix('').with_suffix('.log')) == failed['log_sha256']
    assert not (writework / 'measurements/smoke.json').exists()
    helper_reports = []
    for name in ['experiments/lox-parity-20261003/build.py', 'experiments/lox-parity-20261003/run.py',
                 'experiments/lox-parity-20261003/analyze.py', 'experiments/lox-performance-audit-20261002/audit.py',
                 'experiments/lox-perf-improvements-20261002/analyze.py']:
        data = read(root / name)
        checkpoint = subprocess.check_output(['git', '-C', str(root), 'show', '6e516f65:' + name])
        assert data == checkpoint
        helper_reports.append({'path': str(root / name), 'sha256': sha(root / name), 'checkpoint_unchanged': True})
    for path, digest in list(READS.items()):
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, ('changed during review', path)
    result = {'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'outcome': 'completed measurements pass provenance, coverage and arithmetic checks with stated limits',
              'root_worktree': str(root), 'manifests': [next_report, write_report],
              'guest_builds': build_reports, 'metadata_copies': metadata_copies,
              'baseline_replay': {'path': str(replay_path), 'sha256': sha(replay_path),
                                  'historical_build_compiler_sha256': '9007d0532fe0ed8e0a17568c2e7e796023ddd59e76137efa0181fefca3685288',
                                  'fixed_compiler_sha256': replay['compiler_sha256'],
                                  'both_guest_binaries_byte_identical': True},
              'completed_measurements': reports, 'analyses': analyses, 'pending_or_unrun': pending,
              'failed_original_smoke': {'path': str(failed_path), 'sha256': sha(failed_path),
                                        'process_status': 2, 'measurement_json_absent': True,
                                        'reason': 'invalid phase smoke; corrected check phase uses a new filename'},
              'helpers': helper_reports, 'stable_read_input_count': len(READS),
              'stable_read_inputs_identity_sha256': hashlib.sha256(json.dumps(READS, sort_keys=True).encode()).hexdigest(),
              'source_or_artifact_mutations': 0, 'guest_executions': 0, 'perf_executions': 0,
              'limitations': [
                  'Audit verifies preserved command/log statuses and sample data; it does not independently rerun guests or measurements.',
                  'Runner checks raw stdout equality then retains only its hash. Expected-output hashes match every retained sample.',
                  'Runner retains at most 1500 decoded stderr characters. Every accepted sample here is complete ASCII text shorter than the limit (empty or the exact stats line), but raw stream archives are not retained.',
                  'Counter raw CSV is reused per sample. All four recorded rates are 100%; there is no independent raw CSV for every row.',
                  'Smoke covers the eight requested source/compiler arms; Rust and Go are deliberately absent there. Timed source comparison covers both references.',
                  'One-round screening counters are diagnostic. Three-round paired wall ratios retain spread and are not statistical significance certificates.',
                  'Partial/absent new phases are excluded and require a later separate receipt; historical observations are never rewritten.'
              ]}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'out': str(args.out), 'sha256': hashlib.sha256(args.out.read_bytes()).hexdigest(),
                      'completed_samples': sum(r['actual_samples'] for r in reports),
                      'pending': pending}, indent=2))


if __name__ == '__main__':
    main()
