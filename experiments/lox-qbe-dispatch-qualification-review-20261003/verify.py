"""Read-only dispatch artifact and full-stream receipt checks; no guest runs."""
from collections import Counter
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import subprocess
import tarfile


HERE = Path(__file__).resolve().parent
REVIEW = json.loads((HERE / 'review.json').read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def saved(name):
    return gzip.decompress((HERE / 'inputs' / (name + '.gz')).read_bytes())


def document(name):
    return json.loads(saved(name))


def live(path, expected):
    assert sha(Path(path).read_bytes()) == expected, path


def files(root):
    root = Path(root)
    return {str(p.relative_to(root)): sha(p.read_bytes())
            for p in sorted(root.rglob('*')) if p.is_file()}


def elf(path):
    data = Path(path).read_bytes()
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    assert header[0][:6] == b'\x7fELF\x02\x01'
    programs = [struct.unpack_from('<IIQQQQQQ', data, header[5] + i * header[9])
                for i in range(header[10])]
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, header[6] + i * header[11])
                for i in range(header[12])]
    string_table = sections[header[13]]
    names = data[string_table[4]:string_table[4] + string_table[5]]
    allocated = {}
    for row in sections:
        if row[2] & 2:
            name = names[row[0]:].split(b'\0', 1)[0].decode()
            allocated[name] = dict(type=row[1], flags=row[2], address=row[3],
                                   size=row[5], alignment=row[8],
                                   sha256=None if row[1] == 8 else
                                   sha(data[row[4]:row[4] + row[5]]))
    return (header[1:5], header[7:11], programs, allocated)


def freeze(data):
    assert data['core_source_sha256'] == CORE['files']
    assert data['core_descriptor_sha256'] == REVIEW['inputs']['full-source-v3.json']['sha256']
    assert data['candidate37'] == data['control37'] == SOURCE
    for label, parts in data['compiler_prefixes_sha256'].items():
        for part, items in parts.items():
            assert files(Path(REVIEW['prefixes'][label]) / part) == items
    for path, expected in data['artifacts_sha256'].items():
        live(path, expected)


def built(row, runtime):
    assert row['status'] == 0
    argv = row['argv']
    backend = argv[argv.index('--backend') + 1]
    assert '--' + runtime + '-runtime' in argv
    assert argv[2] == IDENTITY['compiler']
    if backend == 'llvm':
        assert '--qbe' not in argv and '--lto' in argv
        assert argv[argv.index('--llvm-opt') + 1] == '3'
    binary = row['binary']
    live(binary, row['binary_sha256'])
    live(binary + '.qbe-manifest.json', row['manifest_sha256'])
    live(binary + '.qbe-receipt', row['receipt_sha256'])
    live(row['runtime_object'], row['runtime_object_sha256'])
    manifest = json.loads(Path(binary + '.qbe-manifest.json').read_text())
    assert manifest['backend'] == backend
    assert manifest['runtime_object'] == row['runtime_object']
    if backend == 'llvm':
        assert manifest['optimization'] == '3' and manifest['lto'] is True
        assert manifest['thin_lto'] is False
    return backend


for name, item in REVIEW['inputs'].items():
    compressed = (HERE / 'inputs' / (name + '.gz')).read_bytes()
    assert sha(compressed) == item['copy_sha256'], name
    data = gzip.decompress(compressed)
    assert sha(data) == item['sha256'], name
    assert Path(item['path']).read_bytes() == data, name

AUTHOR = Path(REVIEW['author_worktree'])
CORE = document('full-source-v3.json')
assert len(CORE['files']) == 871
for name, expected in CORE['files'].items():
    live(AUTHOR / name, expected)
    live(AUTHOR / '.tmp-lox-qbe-dispatch-20261003/full-source-v3' / name, expected)
archive = subprocess.run(['git', 'archive', CORE['base'], 'src', 'SPEC.md',
                          'build.zig', 'build_qbe_assets.zig', 'build_test_inputs.zig',
                          'build.zig.zon'], cwd=AUTHOR, capture_output=True,
                         check=True).stdout
with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
    baseline = {item.name: sha(stream.extractfile(item).read())
                for item in stream if item.isfile()}
assert {name for name, expected in CORE['files'].items()
        if baseline.get(name) != expected} == set(REVIEW['changed_source'])

RC = document('static-v3-build.json')
GC = document('native-v4-gc-build.json')
IDENTITY = document('compiler-v3.json')
release = document('release-proof-v3.json')
assert release['status'] == 0 and '-Doptimize=ReleaseFast' in release['argv']
assert release['log_sha256'] == sha(saved('release-proof-v3.log'))
SOURCE = RC['source37_before']
assert len(SOURCE) == 37
assert RC['verified_after'] and GC['verified_after']
assert SOURCE == RC['source37_after'] == RC['root_source37_after']
assert SOURCE == GC['source37'] == GC['source37_before'] == GC['source37_after']
assert GC['root_source37_after'] == SOURCE
assert files(REVIEW['selected_source']) == files(REVIEW['control_source']) == SOURCE
assert IDENTITY['compiler_sha256'] == REVIEW['compiler_sha256']
live(IDENTITY['compiler'], IDENTITY['compiler_sha256'])
live(Path(IDENTITY['compiler']).with_name('qbe'), IDENTITY['qbe_sha256'])
assert IDENTITY['qbe_sha256'] == REVIEW['qbe_sha256']
assert len(RC['builds']) == len(GC['builds']) == 2
assert {built(row, 'rc') for row in RC['builds']} == {'llvm', 'qbe'}
assert {built(row, 'gc') for row in GC['builds']} == {'llvm', 'qbe'}
assert GC['full_freeze_before'] == GC['full_freeze_after']
freeze(GC['full_freeze_after'])

sections = document('llvm-sections-v3.json')
for label in ['control', 'candidate']:
    live(sections[label], sections[label + '_sha256'])
    assert elf(sections[label])[3] == sections[label + '_allocated']
assert elf(sections['control']) == elf(sections['candidate'])
assert sections['allocated_identical'] and sections['differing_sections'] == []

PUBLIC = document('public-qualification-v4.json')
assert PUBLIC['verified_after'] and PUBLIC['fresh_public_passes'] == 336
assert PUBLIC['source_sha256'] == SOURCE
assert PUBLIC['full_freeze_before'] == PUBLIC['full_freeze_after']
freeze(PUBLIC['full_freeze_after'])
names = sorted(p.stem + '::' + name for p in Path(REVIEW['selected_source']).glob('*.my')
               for name in re.findall(r'^public def (test_\w+)\(', p.read_text(), re.M))
assert len(names) == 84 and len(PUBLIC['runs']) == 4
arms = set()
for row in PUBLIC['runs']:
    assert row['status'] == 0
    report = json.loads(Path(row['log']).read_text())
    live(row['log'], row['log_sha256'])
    live(row['stderr'], row['stderr_sha256'])
    assert report['programs'] == 10
    assert report['passed'] == report['executed'] == 84
    assert all(report[key] == 0 for key in ['failed', 'skipped', 'cached', 'dropped', 'unloaded'])
    assert sorted(t['name'] for t in report['tests']) == names
    assert all(t['actual'] is True and t['status'] == 'passed' and t['provider'] == ''
               for t in report['tests'])
    argv = row['argv']
    backend = 'llvm' if '--release' in argv else 'qbe'
    mode = 'gc-stress' if '--gc-stress' in argv else 'rc'
    arms.add((backend, mode))
    assert argv[argv.index('--max-steps') + 1] == '1000000000'
    assert argv[argv.index('--timeout-ms') + 1] == '120000'
    assert '--cases' not in argv and row['ZIG_GLOBAL_CACHE_DIR'] == REVIEW['private_global_cache']
    if backend == 'qbe':
        assert argv[argv.index('--mode') + 1] == 'ReleaseFast'
assert arms == {(backend, mode) for backend in ['llvm', 'qbe'] for mode in ['rc', 'gc-stress']}

NATIVE = document('native/completed.json')
assert NATIVE['verified_after'] and NATIVE['helper_status'] == 0
for key in ['candidate37', 'control37', 'artifacts_sha256', 'complete_freeze']:
    assert NATIVE['before'][key] == NATIVE['after'][key]
assert NATIVE['after']['candidate37'] == NATIVE['after']['control37'] == SOURCE
freeze(NATIVE['after']['complete_freeze'])
for path, expected in NATIVE['after']['artifacts_sha256'].items():
    live(path, expected)
for name, expected in NATIVE['receipt_sha256'].items():
    assert sha(saved('native/' + name)) == expected
for path, expected in NATIVE['input_sha256'].items():
    live(path, expected)
bounded = document('native/observations.json')
focused = document('native/ast-focused-observations.json')
refusals = document('native/rc-native-stress-refusals.json')
bins = document('native/binaries.json')['binaries']
assert bounded['verified_after'] and len(bounded['samples']) == 1168
assert len(focused['samples']) == 96 and len(refusals['pairs']) == 8
assert len(bounded['unrun']) == 80 and bounded['unrun'] == NATIVE['native_smoke_unrun']
assert Counter('native_gc_stress' if r['native_gc_stress'] else
               'rc' if '-rc-' in r['arm'] else 'ordinary_gc'
               for r in bounded['samples']) == NATIVE['mode_counts']
for name, expected in bounded['binary_sha256'].items():
    live(bins[name], expected)


def cell(row):
    return row['name'], row.get('tier'), row['engine'], row['arm'], row['lox_gc_stress']


expected_cases = {}
bench = Path(REVIEW['bench'])
sizes = json.loads((bench / 'sizes.json').read_text())
for path in (bench / 'scripts').glob('*.lox'):
    _, body = path.read_text().split('\n', 1)
    text = f"var N = {sizes[path.stem]['smoke']};\n{body}"
    for engine in ['vm', 'tree']:
        expected_cases[path.stem, 'smoke', engine] = text
for case in json.loads(Path(REVIEW['cases']).read_text()):
    for engine in ['vm', 'tree']:
        expected_cases[case['name'], 'regression', engine] = case['source']
for engine, name in [('tree', 'd9-lox-env-reads-runs.json.gz'),
                     ('vm', 'd9-lox-class-method-runs.json.gz')]:
    traces = json.loads(gzip.decompress(Path(REVIEW['historical_errors'][name]).read_bytes()))['traces']
    for trace in traces:
        expected_cases.setdefault((trace['name'], 'error', engine), trace['source'])
assert len(expected_cases) == 104
candidate_arms = {key for key in bins if not key.startswith('control-')}
expected_cells = {(name, tier, engine, arm, stress)
                  for name, tier, engine in expected_cases
                  for arm in candidate_arms for stress in [False, True]}
actual = set(map(cell, bounded['samples']))
omitted = set(map(cell, bounded['unrun']))
assert len(actual) == 1168 and len(omitted) == 80 and actual.isdisjoint(omitted)
assert actual | omitted == expected_cells
assert all(row['tier'] == 'smoke' and row['native_gc_stress'] and row['unrun_reason']
           for row in bounded['unrun'])
for row in bounded['samples'] + focused['samples']:
    assert row['actual'] == row['expected'], row['name']
    argv = row.get('command', row.get('argv'))
    assert argv[0] == bins[row['arm']] and '--stats' in argv
    assert ('--gc-stress' in argv) == row['lox_gc_stress']
    assert row['native_gc_stress'] == ('-gc-' in row['arm'])
    live(argv[-1], row['source_sha256'])
    if 'tier' in row:
        text = expected_cases[row['name'], row['tier'], row['engine']]
        assert sha(text.encode()) == row['source_sha256']
focus_cases = json.loads(Path(REVIEW['focused_cases']).read_text())
assert len(focus_cases) == 4
for row in focused['samples']:
    case = next(c for c in focus_cases if c['name'] == row['name'])
    assert sha(case['source'].encode()) == row['source_sha256']
    assert row['actual']['status'] == case['status']
    assert row['actual']['stdout'] == case['stdout']
    if 'stderr_prefix_by_engine' in case:
        assert row['actual']['stderr'].startswith(case['stderr_prefix_by_engine'][row['engine']])
assert set(map(cell, focused['samples'])) == {(case['name'], None, engine, arm, stress)
    for case in focus_cases for engine in ['vm', 'tree']
    for arm in candidate_arms for stress in [False, True]}
for row in refusals['pairs']:
    assert row['actual'] == row['expected'] == {
        'status': 2, 'stdout': '', 'stderr':
        'mylang: --gc-stress needs a program built with --gc-runtime; this one uses reference counting\n'}
    assert row['environment'] == {'MYLANG_OPTIONS': '--gc-stress'}
assert {(r['backend'], r['engine'], r['lox_gc_stress']) for r in refusals['pairs']} == {
    (backend, engine, stress) for backend in ['llvm', 'qbe']
    for engine in ['vm', 'tree'] for stress in [False, True]}
registry = document('helper-registry-postflight-v4.json')
helpers = document('helper-source-final.json')
assert registry['expected'] == registry['actual'] == helpers
assert registry['native_completion_sha256'] == sha(saved('native/completed.json'))
for name, expected in helpers.items():
    live(AUTHOR / '.tmp-lox-qbe-dispatch-20261003' / name, expected)
for key in ['validate-v4.py', 'freeze.py', 'helper-source-final.json']:
    path = str(AUTHOR / '.tmp-lox-qbe-dispatch-20261003' / key)
    assert path in NATIVE['before']['artifacts_sha256']
print(json.dumps(dict(verified=True, core_source_files=871, source_files=37,
                     actual_guest_flavors=4, llvm_rc_allocated_sections=26,
                     llvm_rc_headers_and_program_layout_equal=True,
                     public_fresh=336, native_exact=1168, ast_focused_exact=96,
                     checked_refusals=8, native_stress_omissions=80,
                     performance_or_selection_claim=False), indent=2))
