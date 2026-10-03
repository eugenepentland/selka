"""Independent host-only final counter, strict closeout and sealed object checks."""
import contextlib
import hashlib
import io
import json
import math
import os
from pathlib import Path
import runpy
import statistics

HERE = Path(__file__).resolve().parent
prior = io.StringIO()
with contextlib.redirect_stdout(prior):
    h = runpy.run_path(str(HERE / 'wall-check.py'))
for name in ['ROOT', 'WORK', 'manifest', 'VERSION', 'sha', 'doc', 'option', 'math_result', 'equal_math', 'names', 'guards']:
    globals()[name] = h[name]
ARCHIVE = Path('/home/epentland/ai/canopy/evidence/mylang-lox-compiler-screens-20261003/native-backend-policy')
ARCHIVE_SHA = '431b64aca839ef7514c0f388815cc8d0bf29b0b69dcc4f9b6710af155250b18b'
assert sha(ARCHIVE / 'MANIFEST.json') == ARCHIVE_SHA
saved_archive = doc(ARCHIVE / 'MANIFEST.json')
assert saved_archive['version'] == 'lox-compiler-evidence-v1' and saved_archive['work'] == str(WORK)
assert not saved_archive['performance_selection_inferred'] and not saved_archive['extras_are_successful_measurements']
receipt = doc(WORK / 'counters.json')
assert sha(WORK / 'counters.json') == 'f6a6aeec2eb2d8450102cdae3341d2dcf159c4d9ecc3145a9f0ba869712e9732'
assert receipt['verified_after'] is True and receipt['manifest'] == manifest
assert receipt['phase'] == 'counters' and receipt['tier'] == 'tree' and receipt['rounds'] == 3 and receipt['cpu'] == 10
arms = set(manifest['binaries'])
cases = {c['id']: c for c in receipt['cases']}
cells = {(r['case'], r['arm'], r['round']): r for r in receipt['samples']}
assert len(cases) == len(receipt['cases']) == 26 and set(cases) == {e + '/' + n for e in ['vm', 'tree'] for n in names}
assert len(cells) == len(receipt['samples']) == 468
assert set(cells) == {(e + '/' + n, arm, i) for e in ['vm', 'tree'] for n in names for arm in arms for i in range(3)}
assert receipt['binary_sha256'] == manifest['binary_sha256']
bench = WORK / 'reference/benchmarks/lox/bench'
sizes = doc(bench / 'sizes.json')
for c in cases.values():
    assert c['id'] == c['engine'] + '/' + c['name'] and c['size'] == sizes[c['name']]['tree']
    assert Path(c['script']) == WORK / 'inputs' / (c['name'] + '.tree.lox')
    assert Path(c['expected']) == bench / 'expected' / (c['name'] + '.tree.out')
    assert sha(c['script']) == c['script_sha256']
    first, rest = (bench / 'scripts' / (c['name'] + '.lox')).read_text().split('\n', 1)
    assert first.startswith('var N = ')
    assert Path(c['script']).read_text() == f"var N = {c['size']};\n" + rest
events = ['instructions', 'cycles', 'branches', 'branch-misses']
for r in receipt['samples']:
    assert type(r['status']) is int and r['status'] == 0 and r['stderr'] == ''
    assert r['stdout_sha256'] == sha(cases[r['case']]['expected'])
    assert type(r['wall_s']) in [int, float] and math.isfinite(r['wall_s']) and r['wall_s'] > 0
    for event in events:
        assert type(r[event]) is int and r[event] >= 0 and r[event + '_running_pct'] == 100
summary = {}
for case in cases:
    summary[case] = {}
    for arm in arms:
        rows = [cells[case, arm, i] for i in range(3)]
        times = [r['wall_s'] for r in rows]
        median = statistics.median(times)
        result = dict(wall_s=median, wall_spread=(max(times)-min(times))/median, samples=3)
        result.update({event: statistics.median([r[event] for r in rows]) for event in events})
        result['ipc'] = result['instructions'] / result['cycles']
        summary[case][arm] = result
assert equal_math(receipt['summary'], summary)
command = doc(WORK / 'counters.command.json')
assert type(command['status']) is int and command['status'] == 0 and command['sources_verified_after'] is True
assert command['source_hashes_before'] == command['source_hashes_after'] == {a: v['hashes'] for a, v in manifest['candidate_sources'].items()}
assert command['manifest_sha256'] == sha(WORK / 'binaries.json') and command['log_sha256'] == sha(WORK / 'counters.log')
assert command['cwd'] == str(ROOT)
assert command['argv'] == ['/usr/bin/python3', str(ROOT / 'experiments/lox-performance-audit-20261002/audit.py'), 'counters', '--work', WORK.name, '--out', WORK.name + '/counters.json', '--arms', 'baseline-llvm,baseline-qbe,candidate-llvm,candidate-qbe,rust,go', '--tier', 'tree', '--rounds', '3', '--cpu', '10']
counter_results = {}
for metric, name in [('instructions', 'instructions-analysis.json'), ('cycles', 'cycles-analysis.json')]:
    analysis = doc(WORK / name)
    assert analysis['receipt'] == str(WORK / 'counters.json') and analysis['receipt_sha256'] == sha(WORK / 'counters.json')
    assert analysis['coverage_verified'] is True and analysis['samples'] == 468
    assert analysis['stable_guards_after'] == 252 and analysis['runtime_guard_protocol'] == VERSION
    assert analysis['metric'] == metric and analysis['screen_only'] is False
    expected = {}
    for backend in ['llvm', 'qbe']:
        for before in ['baseline-' + backend, 'rust', 'go']:
            after = 'candidate-' + backend
            expected[after + '-over-' + before] = math_result(receipt, before, after, metric)
    assert equal_math(analysis['comparisons'], expected)
    counter_results[metric] = expected


def record(path):
    path = Path(path)
    assert path.is_file()
    return dict(sha256=sha(path), bytes=path.stat().st_size,
                symlink_target=os.readlink(path) if path.is_symlink() else None)


def inventory(roots, direct):
    paths = {Path(p).absolute() for p in direct}
    for root in map(Path, roots):
        root = root.absolute()
        if root.is_file():
            paths.add(root)
            continue
        assert root.is_dir() and not root.is_symlink()
        for parent, dirs, files in os.walk(root, followlinks=False):
            parent = Path(parent)
            retained = []
            for name in dirs:
                if name in ['.zig-cache', 'zig-cache', '__pycache__'] or (parent == root and name.startswith('cache-')) or (name == 'target' and (parent / 'Cargo.toml').is_file()):
                    continue
                assert not (parent / name).is_symlink()
                retained.append(name)
            dirs[:] = retained
            paths.update(parent / name for name in files)
    return {str(path): record(path) for path in sorted(paths)}


report = doc(ROOT / '.tmp-lox-native-policy-screen-check-final.log')
assert report == saved_archive['validated_closeout']
assert report['version'] == 'lox-compiler-closeout-v2' and report['runtime_guard_protocol'] == VERSION
assert report['guards_verified'] == 252 and report['source37_exact'] and report['qualified_RC_ELF_sidecars_exact'] and report['rebuild_ELF_sections_rechecked']
assert report['manifest_sha256'] == sha(WORK / 'binaries.json') and report['runtime_bindings_sha256'] == sha(WORK / 'runtime-bindings.json')
assert not report['performance_selection_inferred']
phase_map = {'smoke': ('smoke', 156), 'screen': ('screen', 104), 'full_wall': ('wall', 468), 'full_counters': ('counters', 468)}
assert set(report['coverage']) == set(phase_map) | {'focused_wall'}
assert report['coverage']['focused_wall'] == dict(present=False, completed_rows=0)
completed = {}
for kind, (name, count) in phase_map.items():
    phase = doc(WORK / (name + '.json'))
    row = report['coverage'][kind]
    assert row['present'] and row['completed_rows'] == len(phase['samples']) == count
    assert row['receipt'] == str(WORK / (name + '.json')) and row['sha256'] == sha(row['receipt'])
    assert row['command_sha256'] == sha(WORK / (name + '.command.json'))
    assert row['phase'] == phase['phase'] and row['tier'] == phase['tier'] and row['rounds'] == phase['rounds'] and not row['partial_matrix_not_selection']
    completed[name] = phase
assert sum(len(r['samples']) for r in completed.values()) == 1196
found_phases = {p.name for p in WORK.glob('*.json') if isinstance(doc(p), dict) and 'phase' in doc(p)}
assert found_phases == {name + '.json' for name in completed}
expected_metrics = []
for name in ['counters', 'screen', 'wall']:
    phase = completed[name]
    for metric in ['wall_s'] if name == 'wall' else ['instructions', 'cycles']:
        comparisons = {}
        for backend in ['llvm', 'qbe']:
            for before in ['baseline-' + backend] + ([] if name == 'screen' else ['rust', 'go']):
                after = 'candidate-' + backend
                comparisons[after + '-over-' + before] = math_result(phase, before, after, metric)
        expected_metrics.append(dict(receipt=str(WORK / (name + '.json')), receipt_sha256=sha(WORK / (name + '.json')), metric=metric,
                                     partial_matrix_not_selection=False, comparisons=comparisons))
assert equal_math(report['computed_metrics'], expected_metrics)
analysis_names = ['cycles-analysis.json', 'instructions-analysis.json', 'screen-cycles.json', 'screen-instructions.json', 'wall-analysis.json']
expected_analyses = []
for name in analysis_names:
    path = WORK / name
    a = doc(path)
    expected_analyses.append(dict(path=str(path), sha256=sha(path), receipt=a['receipt'], metric=a['metric'],
        partial_matrix_not_selection=False, math_verified=True, comparisons=a['comparisons']))
assert equal_math(report['analyses'], expected_analyses)
assert report['validated_inventory'] == inventory([WORK], guards)
tools = [str(p) for p in (ROOT / 'experiments/lox-compiler-runtime-protocol-20261003').glob('*.py')]
tools.append(str(ROOT / 'experiments/lox-compiler-runtime-protocol-20261003/README.md'))
assert saved_archive['files'] == inventory([WORK, *saved_archive['extra_roots']], [*guards, *tools])
assert len(saved_archive['files']) == 375 and len(saved_archive['objects']) == 276
assert set(saved_archive['objects']) == {r['sha256'] for r in saved_archive['files'].values()}
assert {p.name for p in ARCHIVE.iterdir()} == {'MANIFEST.json', 'objects'}
seen = set()
for p in (ARCHIVE / 'objects').rglob('*'):
    assert not p.is_symlink()
    if p.is_dir():
        continue
    assert p.is_file() and p.name not in seen and len(p.name) == 64 and set(p.name) <= set('0123456789abcdef')
    assert p.relative_to(ARCHIVE / 'objects').parts == (p.name[:2], p.name)
    seen.add(p.name)
    assert sha(p) == p.name and p.stat().st_size == saved_archive['objects'][p.name]['bytes']
assert seen == set(saved_archive['objects'])
assert all(r['bytes'] == saved_archive['objects'][r['sha256']]['bytes'] for r in saved_archive['files'].values())
for name, originals in [('original', True), ('portable', False)]:
    v = doc(ROOT / ('.tmp-lox-native-policy-evidence-' + name + '-verify.json'))
    assert v['archive'] == str(ARCHIVE) and v['manifest_sha256'] == ARCHIVE_SHA
    assert v['objects_verified'] == 276 and v['original_paths_recorded'] == 375 and v['original_identities_checked'] is originals
    assert not v['performance_selection_inferred']
initial = ROOT / '.tmp-lox-native-policy-screen-check-initial.log'
assert 'measurement command has no completed receipt' in initial.read_text() and 'wall.command.json' in initial.read_text()
old_protocol = ROOT / '.tmp-lox-runtime-protocol-review-verify.log'
assert 'AssertionError' in old_protocol.read_text()
assert str(initial) in saved_archive['files'] and str(old_protocol) in saved_archive['files']
assert sha(ARCHIVE / 'MANIFEST.json') == ARCHIVE_SHA
assert all(sha(path) == digest for path, digest in guards.items())
print(json.dumps(dict(verified=True, completed_coverage={name: len(r['samples']) for name, r in completed.items()},
    completed_total=sum(len(r['samples']) for r in completed.values()),
    full_counter_PMU_events_at100=468*4, screen_plus_full_PMU_events_at100=(104+468)*4,
    full_counter_analyses_verified=12, full_counter_analysis_case_rows_verified=312,
    exact_source37=True, prospective_prepare_inputs=1038, exact_guard_inventory=252, actual_runtime_roles=6,
    whole_measured_qualified_RC_ELFs_sidecars_exact=True, rebuilt_allocated_sections_exact=True,
    computed_counter_metrics={metric:{key:value['engines'] for key,value in comparisons.items()} for metric,comparisons in counter_results.items()},
    strict_closeout_matches_archive=True, independent_archive_inventory_originals_objects_verified=True,
    archive=str(ARCHIVE), archive_manifest_sha256=ARCHIVE_SHA, archive_originals=375, archive_objects=276,
    initial_unfinished_wall_refusal_retained=True, historical_original35_final37_package_refusal_retained=True,
    limits=['Raw performance stdout is represented by hashes; stderr is a retained tail.',
            'Smoke collector stats were checked equal across all six arms; no guest or native stress perf claim.',
            'Rebuilt ELFs are reproduction evidence; measured whole files are the exact authored qualified RC guests.',
            'Compilation core878/prefix16 wrapper guards cover preparation; native qualification has its separately reviewed prospective/retrospective limits.',
            'Three paired wall/counter rounds and spreads do not establish statistical confidence or absence of regressions.',
            'QBE tree gain accompanies slower QBE VM observations; no selection/main-merge/parity inference.',
            'Extras and failed historical attempts do not add successful measurement coverage.'],
    no_compiler_guest_or_performance_execution=True), indent=2))
