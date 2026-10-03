"""Read-only scratch-alias artifact and full-stream receipt checks; no guest runs."""
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
                                   sha256=sha(b'') if row[1] == 8 else
                                   sha(data[row[4]:row[4] + row[5]]))
    return (header[1:5], header[7:11], programs, allocated)


def section_bytes(path):
    data = Path(path).read_bytes()
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    rows = [struct.unpack_from('<IIQQQQIIQQ', data, header[6] + i * header[11])
            for i in range(header[12])]
    table = rows[header[13]]
    names = data[table[4]:table[4] + table[5]]
    return {names[r[0]:].split(b'\0', 1)[0].decode():
            (r[1:4], r[5:], b'' if r[1] == 8 else data[r[4]:r[4] + r[5]])
            for r in rows}


def replay(data):
    assert data[:8] == b'MYLREPL2'
    offset = 40
    size = struct.unpack_from('<Q', data, offset)[0]
    offset += 8
    warnings = data[offset:offset + size]
    offset += size
    size = struct.unpack_from('<Q', data, offset)[0]
    offset += 8
    return warnings, json.loads(data[offset:offset + size])


def frontend():
    inputs = json.loads((HERE / 'frontend-inputs.json').read_text())
    manifests = []
    for label in ['candidate', 'control']:
        item = inputs[label]
        compressed = (HERE / 'inputs' / (label + '-frontend-replay.gz')).read_bytes()
        assert sha(compressed) == item['copy_sha256']
        data = gzip.decompress(compressed)
        assert sha(data) == item['sha256']
        assert Path(item['path']).read_bytes() == data
        manifests.append(replay(data))
    assert manifests[0][0] == manifests[1][0]
    left, right = (row[1] for row in manifests)
    stores = [row.pop('store') for row in [left, right]]
    assert left == right and len(left['functions']) == 420
    compressed = (HERE / 'inputs/frontend-units.json.gz').read_bytes()
    assert sha(compressed) == inputs['units']['copy_sha256']
    data = gzip.decompress(compressed)
    assert sha(data) == inputs['units']['sha256']
    copies = json.loads(data)
    assert len(copies) == 420
    for row in left['functions']:
        texts = [row['il']] if 'il' in row else [
            (Path(store) / row['il_digest']).read_text() for store in stores]
        assert all(text == texts[0] for text in texts)
        assert copies[row['symbol']] == {
            'name': row['name'], 'il': texts[0], 'sha256': sha(texts[0].encode())}
    cached = [files(store) for store in stores]
    assert cached[0] == cached[1] and len(cached[0]) == 820
    check = document('frontend-byte-check.json')
    for path, expected in check['source_input_hashes'].items():
        live(path, expected)
    assert document('frontend.json')['all420_equal']


def freeze(data):
    assert data['core_source_sha256'] == CORE['core']
    assert data['core_descriptor_sha256'] == REVIEW['inputs']['frozen-source-final.json']['sha256']
    assert data['candidate37'] == data['control37'] == SOURCE
    for label, parts in data['compiler_prefixes_sha256'].items():
        for part, items in parts.items():
            assert files(Path(REVIEW['prefixes'][label]) / part) == items
    assert data['helpers'] == {'descriptor_sha256': REVIEW['inputs']['helper-source.json']['sha256'],
                               'files_sha256': document('helper-source.json')['files']}
    for path, expected in data['artifacts_sha256'].items():
        live(path, expected)


def built(row, runtime):
    assert row['status'] == 0
    argv = row['argv']
    backend = argv[argv.index('--backend') + 1]
    assert '--' + runtime + '-runtime' in argv
    assert argv[2] == IDENTITY['compiler']
    if backend == 'qbe':
        live(argv[argv.index('--qbe') + 1], REVIEW['qbe_sha256'])
    if backend == 'llvm':
        assert '--qbe' not in argv and '--lto' in argv
        assert argv[argv.index('--llvm-opt') + 1] == '3'
    binary = row.get('binary', argv[argv.index('-o') + 1])
    live(binary, row['binary_sha256'])
    live(binary + '.qbe-manifest.json', row['manifest_sha256'])
    if 'receipt_sha256' in row:
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
CORE = document('frozen-source-final.json')
assert len(CORE['core']) == 871
for name, expected in CORE['core'].items():
    live(AUTHOR / name, expected)
    live(Path(REVIEW['qualification_root']) / 'frozen-core' / name, expected)
archive = subprocess.run(['git', 'archive', CORE['base'], 'src', 'SPEC.md',
                          'build.zig', 'build_qbe_assets.zig', 'build_test_inputs.zig',
                          'build.zig.zon'], cwd=AUTHOR, capture_output=True,
                         check=True).stdout
with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
    baseline = {item.name: sha(stream.extractfile(item).read())
                for item in stream if item.isfile()}
assert {name for name, expected in CORE['core'].items()
        if baseline.get(name) != expected} == set(REVIEW['changed_source'])

RC = document('static-v2-build.json')
RC_COMMAND = document('static-v2-command.json')
GC = document('gc-build.json')
IDENTITY = {'compiler': CORE['compiler_final']['path']}
SOURCE = CORE['source37']
assert len(SOURCE) == 37
assert len(RC['source_sha256']) == 26
assert RC['source_sha256'] == {name: expected for name, expected in SOURCE.items() if name.endswith('.my')}
assert RC_COMMAND['status'] == 0 and RC_COMMAND['verified_after']
assert RC_COMMAND['before'] == RC_COMMAND['after']
assert RC_COMMAND['after']['core'] == CORE['core']
assert RC_COMMAND['after']['source37'] == SOURCE
assert RC_COMMAND['after']['compiler_prefix'] == CORE['compiler_prefix']
assert RC_COMMAND['after']['freeze_sha256'] == REVIEW['source_descriptor_sha256']
live(RC_COMMAND['argv'][2], RC_COMMAND['after']['builder_sha256'])
assert RC_COMMAND['log_sha256'] == sha(saved('static-v2-command.log'))
assert RC['compiler_sha256'] == REVIEW['compiler_sha256']
assert RC['qbe_sha256'] == REVIEW['qbe_sha256']
live(RC['compiler'], RC['compiler_sha256'])
live(RC['qbe'], RC['qbe_sha256'])
assert not Path(RC['compiler']).is_symlink() and not Path(RC['qbe']).is_symlink()
assert files(REVIEW['selected_source']) == files(REVIEW['control_source']) == SOURCE
assert len(RC['builds']) == len(GC['builds']) == 2
assert {built(row, 'rc') for row in RC['builds']} == {'llvm', 'qbe'}
assert {built(row, 'gc') for row in GC['builds']} == {'llvm', 'qbe'}
assert GC['verified_after'] and GC['before'] == GC['after']
freeze(GC['after'])
freeze(GC['produced_artifacts'])
sections = document('llvm-equivalence-v2.json')
candidate = next(row for row in RC['builds'] if '--backend' in row['argv'] and row['argv'][row['argv'].index('--backend') + 1] == 'llvm')
candidate_path = candidate['argv'][candidate['argv'].index('-o') + 1]
control_path = REVIEW['control_llvm_binary']
live(candidate_path, sections['rebuilt_sha256'])
live(control_path, sections['qualified_sha256'])
assert elf(candidate_path) == elf(control_path)
assert len(elf(candidate_path)[3]) == 26
assert sections['program_layout_exact']
assert elf(candidate_path)[3] == elf(control_path)[3] == sections['allocated_sections_exact']
assert all(row.startswith('.debug') or row in ['.symtab', '.strtab']
           for row in sections['nonallocated_metadata_differences'])
candidate_sections, control_sections = (section_bytes(path)
                                       for path in [candidate_path, control_path])
assert candidate_sections.keys() == control_sections.keys()
differences = {name for name in candidate_sections
               if candidate_sections[name] != control_sections[name]}
assert differences == set(sections['nonallocated_metadata_differences'])
frontend()
PUBLIC = document('public.json')
assert PUBLIC['verified_after'] and PUBLIC['fresh_public_passes'] == 336
assert PUBLIC['before'] == PUBLIC['after']
freeze(PUBLIC['after'])
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
    assert '--cases' not in argv and row['environment']['ZIG_GLOBAL_CACHE_DIR'] == REVIEW['private_global_cache']
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
helpers = document('helper-source.json')
for name, expected in helpers['files'].items():
    live(Path(REVIEW['qualification_root']) / name, expected)
launcher = document('native-launch.json')
assert launcher['status'] == 0
live(Path(REVIEW['qualification_root']) / 'run-check.py', launcher['helper_sha256'])
assert 'build-slot.sh' in launcher['argv'][0] and launcher['argv'][1] == 'build'
assert launcher['environment']['ZIG_GLOBAL_CACHE_DIR'] == REVIEW['private_global_cache']
assert launcher['log_sha256'] == sha(saved('native-launch.log'))
print(json.dumps(dict(verified=True, core_source_files=871, source_files=37,
                     frontend_units_and_metadata_exact=420,
                     frontend_cached_IL_files_equal=820,
                     actual_guest_flavors=4, llvm_rc_allocated_sections=26,
                     llvm_rc_headers_and_program_layout_equal=True,
                     public_fresh=336, native_exact=1168, ast_focused_exact=96,
                     checked_refusals=8, native_stress_omissions=80,
                     performance_or_selection_claim=False), indent=2))
