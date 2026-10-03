"""Independent host-only checks of the completed wall phase; no active phases."""
import contextlib
import hashlib
import io
import json
import math
from pathlib import Path
import runpy
import statistics

HERE = Path(__file__).resolve().parent
PRECHECK = HERE / 'precheck.py'
assert hashlib.sha256(PRECHECK.read_bytes()).hexdigest() == '3a0dc456814c7895f13227ec22d19d4eec0ae496b03bd9da39e4f2b4f96bb0ad'
prior = io.StringIO()
with contextlib.redirect_stdout(prior):
    helpers = runpy.run_path(str(PRECHECK))
for name in ['ROOT', 'WORK', 'manifest', 'VERSION', 'sha', 'doc', 'option', 'math_result', 'equal_math', 'names', 'guards']:
    globals()[name] = helpers[name]

paths = [WORK / n for n in ['wall.json', 'wall.command.json', 'wall.log', 'wall-analysis.json']]
before = {str(p): sha(p) for p in paths}
receipt = doc(WORK / 'wall.json')
arms = set(manifest['binaries'])
assert receipt['verified_after'] is True and receipt['manifest'] == manifest
assert receipt['phase'] == 'time' and receipt['tier'] == 'timed'
assert receipt['rounds'] == 3 and receipt['cpu'] == 2
cases = {c['id']: c for c in receipt['cases']}
assert len(cases) == len(receipt['cases']) == 26
assert set(cases) == {engine + '/' + n for engine in ['vm', 'tree'] for n in names}
cells = {(r['case'], r['arm'], r['round']): r for r in receipt['samples']}
assert len(cells) == len(receipt['samples']) == 468
assert set(cells) == {(engine + '/' + n, arm, i) for engine in ['vm', 'tree'] for n in names for arm in arms for i in range(3)}
assert set(receipt['binary_sha256']) == arms
assert all(receipt['binary_sha256'][a] == manifest['binary_sha256'][a] == sha(manifest['binaries'][a]) for a in arms)
bench = WORK / 'reference/benchmarks/lox/bench'
sizes = doc(bench / 'sizes.json')
for c in cases.values():
    assert c['id'] == c['engine'] + '/' + c['name']
    assert c['size'] == sizes[c['name']][c['engine']]
    assert Path(c['script']) == WORK / 'inputs' / (c['name'] + '.' + c['engine'] + '.lox')
    assert Path(c['expected']) == bench / 'expected' / (c['name'] + '.' + c['engine'] + '.out')
    assert sha(c['script']) == c['script_sha256']
    first, rest = (bench / 'scripts' / (c['name'] + '.lox')).read_text().split('\n', 1)
    assert first.startswith('var N = ')
    assert Path(c['script']).read_text() == f"var N = {c['size']};\n" + rest
for r in receipt['samples']:
    assert type(r['status']) is int and r['status'] == 0
    assert r['stderr'] == '' and r['stdout_sha256'] == sha(cases[r['case']]['expected'])
    assert type(r['wall_s']) in [int, float] and math.isfinite(r['wall_s']) and r['wall_s'] > 0
summary = {}
for case in cases:
    summary[case] = {}
    for arm in arms:
        times = [cells[case, arm, i]['wall_s'] for i in range(3)]
        median = statistics.median(times)
        summary[case][arm] = dict(wall_s=median, wall_spread=(max(times)-min(times))/median, samples=3)
assert equal_math(receipt['summary'], summary)
command = doc(WORK / 'wall.command.json')
assert type(command['status']) is int and command['status'] == 0 and command['sources_verified_after'] is True
assert command['source_hashes_before'] == command['source_hashes_after'] == {arm: v['hashes'] for arm, v in manifest['candidate_sources'].items()}
assert command['manifest_sha256'] == sha(WORK / 'binaries.json')
assert command['log_sha256'] == sha(WORK / 'wall.log')
assert command['cwd'] == str(ROOT)
assert command['argv'] == ['/usr/bin/python3', str(ROOT / 'experiments/lox-performance-audit-20261002/audit.py'), 'time', '--work', WORK.name, '--out', WORK.name + '/wall.json', '--arms', 'baseline-llvm,baseline-qbe,candidate-llvm,candidate-qbe,rust,go', '--tier', 'timed', '--rounds', '3', '--cpu', '2']
analysis = doc(WORK / 'wall-analysis.json')
assert analysis['receipt'] == str(WORK / 'wall.json') and analysis['receipt_sha256'] == sha(WORK / 'wall.json')
assert analysis['coverage_verified'] is True and analysis['samples'] == 468
assert analysis['runtime_guard_protocol'] == VERSION and analysis['stable_guards_after'] == 252
assert analysis['metric'] == 'wall_s' and analysis['screen_only'] is False
expected = {}
for backend in ['llvm', 'qbe']:
    for before_arm in ['baseline-' + backend, 'rust', 'go']:
        after_arm = 'candidate-' + backend
        expected[after_arm + '-over-' + before_arm] = math_result(receipt, before_arm, after_arm, 'wall_s')
assert equal_math(analysis['comparisons'], expected)
robustness = {}
for backend in ['llvm', 'qbe']:
    comparison = expected[f'candidate-{backend}-over-baseline-{backend}']
    robustness[backend] = {}
    for engine in ['vm', 'tree']:
        rows = {case: row for case, row in comparison['rows'].items() if case.startswith(engine + '/')}
        per_round = [100 * (1-statistics.geometric_mean([row['paired_ratios'][i] for row in rows.values()])) for i in range(3)]
        ordered = sorted(rows.items(), key=lambda pair: pair[1]['reduction_pct'])
        robustness[backend][engine] = dict(
            aggregate=comparison['engines'][engine],
            faster_median_cases=sum(r['reduction_pct'] > 0 for r in rows.values()),
            slower_median_cases=sum(r['reduction_pct'] < 0 for r in rows.values()),
            per_round_geometric_reduction_pct=per_round,
            median_case_spread_pct=statistics.median(r['spread_pct'] for r in rows.values()),
            least_reduction={ordered[0][0]: ordered[0][1]},
            most_reduction={ordered[-1][0]: ordered[-1][1]},
            observed_slower_cases={k:v for k,v in rows.items() if v['reduction_pct'] < 0})
assert {str(p): sha(p) for p in paths} == before
assert all(sha(path) == digest for path, digest in guards.items())
print(json.dumps(dict(scope='Completed wall468, plus repeated completed-only preparation/smoke/screen precheck',
    completed_rows=728, wall_rows=468, analysis_comparisons=6, analysis_case_rows=156,
    tuple_output_status_diagnostics_workloads_sources_identities_summary_math_verified=True,
    strict_protocol_guards_rehashed=252, inputs_sha256=before, robustness=robustness,
    limits=['Three observational paired rounds; spreads are not confidence intervals.',
            'QBE VM aggregate slowdown and individual regressions retained.',
            'Active full counters are excluded; no final closeout/archive/selection claim.',
            'Raw stdout was checked by guarded launcher; measurement receipts retain hashes and stderr tails.',
            'No guest, compiler, or performance execution by reviewer.']), indent=2))
