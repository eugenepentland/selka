"""Read-only policy source/artifact/receipt checks. Executes no compiler or guest."""
import base64
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import struct

HERE = Path(__file__).resolve().parent
REVIEW = json.loads((HERE / 'review.json').read_bytes())
A = Path(REVIEW['author_worktree'])
S = Path(REVIEW['scratch'])


def sha(data):
    return hashlib.sha256(data).hexdigest()


packed = (HERE / 'inputs.json.gz').read_bytes()
assert sha(packed) == REVIEW['inputs_archive_sha256']
unpacked = gzip.decompress(packed)
assert sha(unpacked) == REVIEW['inputs_uncompressed_sha256']
INPUTS = json.loads(unpacked)
assert set(INPUTS) == set(REVIEW['input_paths_sha256'])
for path, row in INPUTS.items():
    data = base64.b64decode(row['base64'], validate=True)
    assert sha(data) == row['sha256'] == REVIEW['input_paths_sha256'][path]
    assert len(data) == row['bytes'] and Path(path).read_bytes() == data, path


def raw(path):
    return base64.b64decode(INPUTS[str(path)]['base64'], validate=True)


def doc(path):
    return json.loads(raw(path))


def live(path, expected):
    assert sha(Path(path).read_bytes()) == expected, path


def files(root):
    root = Path(root)
    return {str(p.relative_to(root)): sha(p.read_bytes())
            for p in sorted(root.rglob('*')) if p.is_file()}


def prefixes(data):
    for root, expected in data.items():
        actual = {}
        for part in ['bin', 'lib']:
            actual.update({part + '/' + name: digest
                           for name, digest in files(Path(root) / part).items()})
        assert actual == expected, root


def elf(path):
    data = Path(path).read_bytes()
    h = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    assert h[0][:6] == b'\x7fELF\x02\x01'
    ph = [struct.unpack_from('<IIQQQQQQ', data, h[5] + i * h[9]) for i in range(h[10])]
    sh = [struct.unpack_from('<IIQQQQIIQQ', data, h[6] + i * h[11]) for i in range(h[12])]
    table = sh[h[13]]
    names = data[table[4]:table[4] + table[5]]
    allocated, all_sections = {}, {}
    for r in sh:
        name = names[r[0]:].split(b'\0', 1)[0].decode()
        payload = b'' if r[1] == 8 else data[r[4]:r[4] + r[5]]
        all_sections[name] = (r[1:4], r[5:], payload)
        if r[2] & 2:
            allocated[name] = dict(type=r[1], flags=r[2], address=r[3], size=r[5],
                                   alignment=r[8], sha256=sha(payload))
    return (h[1:5], h[7:11], ph, allocated), all_sections


CORE = doc(S / 'frozen-source-v2.json')
V1 = doc(S / 'frozen-source-complete.json')
assert len(CORE['core']) == len(V1['core']) == 878
assert sha(raw(S / 'frozen-source-v2.json')) == REVIEW['source_descriptor_sha256']
assert {name for name in CORE['core'] if CORE['core'][name] != V1['core'][name]} == {
    'src/main.zig', 'test/native_variant_policy.zig'}
for name, expected in CORE['core'].items():
    live(A / name, expected)
    live(Path(CORE['core_copy']) / name, expected)
for name, expected in V1['core'].items():
    live(S / 'frozen-core' / name, expected)
SOURCE = CORE['source37']
assert len(SOURCE) == 37 and files(CORE['source']) == SOURCE
COMPILER = doc(S / 'compiler-final-v2.json')
assert COMPILER['compiler_sha256'] == REVIEW['compiler_sha256']
assert COMPILER['qbe_sha256'] == REVIEW['qbe_sha256']
live(COMPILER['compiler'], COMPILER['compiler_sha256'])
live(COMPILER['qbe'], COMPILER['qbe_sha256'])
root = str(Path(COMPILER['compiler']).parents[1])
prefixes({root: COMPILER['owned_final_prefix']})
assert COMPILER['no_symlinks']
assert not any(p.is_symlink() for p in Path(root).rglob('*'))
assert COMPILER['complete_source_descriptor_sha256'] == REVIEW['source_descriptor_sha256']
live(S / 'compiler-v2-release.command.json', COMPILER['release_command_sha256'])
assert doc(S / 'compiler-v2-release.command.json')['status'] == 0

BUILDS = doc(S / 'builds-v2.json')
assert BUILDS['verified_after'] and BUILDS['source37'] == SOURCE
assert BUILDS['immutable_prefixes_before'] == BUILDS['immutable_prefixes_after']
prefixes(BUILDS['immutable_prefixes_after'])
assert len(BUILDS['runs']) == 4
assert {(r['runtime'], r['backend']) for r in BUILDS['runs']} == {
    (runtime, backend) for runtime in ['rc', 'gc'] for backend in ['llvm', 'qbe']}
for r in BUILDS['runs']:
    assert r['status'] == 0
    argv = r['argv']
    assert argv[2] == COMPILER['compiler'] and '--' + r['runtime'] + '-runtime' in argv
    if r['backend'] == 'llvm':
        assert '--qbe' not in argv and '--lto' in argv
        assert argv[argv.index('--llvm-opt') + 1] == '3'
    else:
        live(argv[argv.index('--qbe') + 1], REVIEW['qbe_sha256'])
    for path, expected in r['artifacts_sha256'].items():
        live(path, expected)
    manifest = doc(r['binary'] + '.qbe-manifest.json')
    assert manifest['backend'] == r['backend']
    assert manifest['runtime_object'] in r['artifacts_sha256']
    if r['backend'] == 'llvm':
        assert manifest['optimization'] == '3' and manifest['lto'] and not manifest['thin_lto']

EQ = doc(S / 'equivalence-v2.json')
assert EQ['verified_after'] and EQ['compiler_sha256'] == REVIEW['compiler_sha256']
assert EQ['immutable_prefixes_before'] == EQ['immutable_prefixes_after']
prefixes(EQ['immutable_prefixes_after'])
assert raw(S / 'llvm-v2-emission.stdout') == raw(S / 'llvm-control-emission.stdout')
emitted = doc(S / 'llvm-v2-emission.stdout')
assert len(emitted['functions']) == 420
assert EQ['llvm_all420']['raw_sha256'] == sha(raw(S / 'llvm-v2-emission.stdout'))
assert all('il' in f for f in emitted['functions'])
for name, r in EQ['comparisons'].items():
    live(r['candidate'], r['rebuilt_sha256'])
    live(r['control'], r['qualified_sha256'])
    left, ls = elf(r['candidate'])
    right, rs = elf(r['control'])
    assert left == right and len(left[3]) == 26
    assert left[3] == r['allocated_sections_exact'] and r['program_layout_exact']
    different = {n for n in ls if ls[n] != rs[n]}
    assert different == set(r['nonallocated_metadata_differences'])
    live(r['control_build_receipt'], r['control_build_receipt_sha256'])
    assert all(n.startswith('.debug') or n in {'.symtab', '.strtab'} for n in different)
assert set(EQ['comparisons']) == {'rc-llvm', 'gc-llvm', 'gc-qbe'}

PUBLIC = doc(S / 'public-v2.json')
assert PUBLIC['verified_after'] and PUBLIC['source37'] == SOURCE
assert PUBLIC['complete_source_descriptor_sha256'] == REVIEW['source_descriptor_sha256']
assert PUBLIC['immutable_prefixes_before'] == PUBLIC['immutable_prefixes_after']
prefixes(PUBLIC['immutable_prefixes_after'])
assert len(PUBLIC['runs']) == 4
for r in PUBLIC['runs']:
    label = 'public-v2-ast-' + r['backend'] + '-' + r['runtime']
    out = raw(S / (label + '.json'))
    err = raw(S / (label + '.stderr'))
    assert sha(out) == r['stdout_sha256'] and sha(err) == r['stderr_sha256']
    result = json.loads(out)
    tests = result['tests']
    assert len(tests) == 84 and sorted(t['name'] for t in tests) == sorted(r['names'])
    assert all(t['status'] == 'passed' and t['actual'] == t['expected'] for t in tests)
    assert r['status'] == 0 and not err
    assert {k: result[k] for k in r['summary']} == r['summary']
    assert r['summary']['passed'] == 84 and r['summary']['cached'] == 0
    assert r['summary']['failed'] == r['summary']['skipped'] == 0
    argv = r['argv']
    assert '--force' in argv and argv[2] == COMPILER['compiler']
    assert argv[argv.index('--max-steps') + 1] == '1000000000'
    assert argv[argv.index('--timeout-ms') + 1] == '120000'
    if r['backend'] == 'qbe':
        assert argv[argv.index('--mode') + 1] == 'Debug'
    else:
        assert '--release' in argv

NATIVE = doc(S / 'native-v2/completed.json')
assert NATIVE['verified_after'] and NATIVE['before'] == NATIVE['after']
assert NATIVE['after']['source37'] == SOURCE and NATIVE['after']['core878'] == CORE['core']
for path, expected in NATIVE['after']['artifacts_sha256'].items():
    live(path, expected)
for name, expected in NATIVE['receipt_sha256'].items():
    assert sha(raw(S / 'native-v2' / name)) == expected
assert doc(S / 'native-v2.command.json')['status'] == 0
bounded = doc(S / 'native-v2/observations.json')
focused = doc(S / 'native-v2/focused-observations.json')
refusals = doc(S / 'native-v2/rc-native-stress-refusals.json')['comparisons']
bins = doc(S / 'native-v2/binaries.json')['binaries']
assert bounded['verified_after'] and len(bounded['samples']) == 1168
assert len(focused['samples']) == 96 and len(refusals) == 8
assert len(bounded['unrun']) == 80 and bounded['unrun'] == NATIVE['native_smoke_unrun']
assert Counter('native_gc_stress' if r['native_gc_stress'] else
               'rc' if '-rc-' in r['arm'] else 'ordinary_gc'
               for r in bounded['samples']) == NATIVE['mode_counts']
for name, expected in bounded['binary_sha256'].items():
    live(bins[name], expected)


def cell(row):
    return row['name'], row.get('tier'), row['engine'], row['arm'], row['lox_gc_stress']


root_wt = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
vm_wt = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-vm-20261003')
bench = root_wt / '.tmp-lox-parity/reference/benchmarks/lox/bench'
sizes = doc(bench / 'sizes.json')
expected_cases = {}
for path in (bench / 'scripts').glob('*.lox'):
    _, body = raw(path).decode().split('\n', 1)
    text = f"var N = {sizes[path.stem]['smoke']};\n{body}"
    for engine in ['vm', 'tree']:
        expected_cases[path.stem, 'smoke', engine] = text
for c in doc(vm_wt / 'experiments/lox-vm-callee-20261003/regressions.json'):
    for engine in ['vm', 'tree']:
        expected_cases[c['name'], 'regression', engine] = c['source']
for engine, name in [('tree', 'd9-lox-env-reads-runs.json.gz'),
                     ('vm', 'd9-lox-class-method-runs.json.gz')]:
    traces = json.loads(gzip.decompress(raw(root_wt / 'docs/audits/evidence' / name)))['traces']
    for trace in traces:
        expected_cases.setdefault((trace['name'], 'error', engine), trace['source'])
assert len(expected_cases) == 104
arms = {key for key in bins if not key.startswith('control-')}
expected_cells = {(name, tier, engine, arm, stress)
                  for name, tier, engine in expected_cases for arm in arms for stress in [False, True]}
actual = set(map(cell, bounded['samples']))
omitted = set(map(cell, bounded['unrun']))
assert len(actual) == 1168 and len(omitted) == 80 and actual.isdisjoint(omitted)
assert actual | omitted == expected_cells
assert all(r['tier'] == 'smoke' and r['native_gc_stress'] and r['unrun_reason'] for r in bounded['unrun'])
for r in bounded['samples'] + focused['samples']:
    assert r['actual'] == r['expected'], r['name']
    argv = r.get('command', r.get('argv'))
    assert argv[0] == bins[r['arm']] and '--stats' in argv
    assert ('--gc-stress' in argv) == r['lox_gc_stress']
    assert r['native_gc_stress'] == ('-gc-' in r['arm'])
    assert sha(raw(argv[-1])) == r['source_sha256']
    if 'tier' in r:
        text = expected_cases[r['name'], r['tier'], r['engine']]
        assert sha(text.encode()) == r['source_sha256']
focus_cases = doc(vm_wt / 'experiments/lox-tree-ast-carrier-20261003/regressions.json')
assert len(focus_cases) == 4
assert set(map(cell, focused['samples'])) == {
    (c['name'], None, engine, arm, stress) for c in focus_cases
    for engine in ['vm', 'tree'] for arm in arms for stress in [False, True]}
for r in focused['samples']:
    c = next(c for c in focus_cases if c['name'] == r['name'])
    assert sha(c['source'].encode()) == r['source_sha256']
    assert r['actual']['status'] == c['status'] and r['actual']['stdout'] == c['stdout']
    assert r['environment'] == ({'MYLANG_OPTIONS': '--gc-stress'} if r['native_gc_stress'] else {})
for r in refusals:
    assert r['actual'] == r['expected'] == {
        'status': 2, 'stdout': '', 'stderr':
        'mylang: --gc-stress needs a program built with --gc-runtime; this one uses reference counting\n'}
    assert r['environment'] == {'MYLANG_OPTIONS': '--gc-stress'}
assert {(r['backend'], r['engine'], r['lox_gc_stress']) for r in refusals} == {
    (backend, engine, stress) for backend in ['llvm', 'qbe']
    for engine in ['vm', 'tree'] for stress in [False, True]}

COMPAT = doc(S / 'selected-boundaries-verified-v2/qualification.json')
assert COMPAT['verified_after'] and COMPAT['core878'] == CORE['core'] and COMPAT['source37'] == SOURCE
assert COMPAT['immutable_prefixes_before'] == COMPAT['immutable_prefixes_after']
prefixes(COMPAT['immutable_prefixes_after'])
work = S / 'selected-boundaries-verified-v2'
rows = COMPAT['observations']
assert len(rows) == 40 and len(COMPAT['comparisons']) == 28
normalized = {}
for r in rows:
    label = r['label']
    assert r['status'] == 0
    runtime = label.split('-', 1)[0]
    command = 'emit-project-qbe' if '-emit-project-qbe-' in label else 'native-test-compile'
    count = label.split(command + '-', 1)[1].split('-', 1)[0]
    mode = label.split(command + '-' + count + '-', 1)[1]
    assert r['environment']['MYLANG_COW_COUNTING'] == count
    assert r['environment']['MYLANG_RUNTIME'] == ('rc-v5' if runtime == 'rc' else 'gc-v1')
    assert r['argv'][2] == r['producer'] and r['argv'][3] == command
    live(r['producer'], COMPAT['compilers_sha256'][r['producer']])
    assert ('--native-variants=original' in r['argv']) == (mode == 'explicit-original')
    if command == 'native-test-compile':
        assert '--rc-runtime' not in r['argv'] and '--gc-runtime' not in r['argv']
    if mode in ['control-drop', 'candidate-drop']:
        assert {'--drop-debug', '--drop-step-checks', '--drop-frame-checks'} <= set(r['argv'])
    stdout, stderr = raw(work / (label + '.stdout')), raw(work / (label + '.stderr'))
    assert sha(stdout) == r['stdout_sha256'] and sha(stderr) == r['stderr_sha256']
    assert not [line for line in stderr.splitlines() if not line.startswith(b'build-slot:')]
    data = raw(r['manifest']) if 'manifest' in r else stdout
    assert sha(data) == r['manifest_sha256']
    d = json.loads(data)
    if 'manifest' in r:
        replies = [json.loads(line) for line in stdout.splitlines()]
        assert len(replies) == 2 and all(reply['status'] == 0 for reply in replies)
    if d.get('store'):
        store = Path(d['store'])
        for f in d['functions']:
            for key in ['il_digest', 'meta_digest']:
                path = str(store / f[key])
                assert sha(raw(path)) == COMPAT['fragment_files_sha256'][path]
            f['il'] = raw(store / f['il_digest']).decode()
            f['resolved_meta_file_bytes'] = raw(store / f['meta_digest']).decode()
        d['store'] = '__PHYSICAL_FRAGMENT_STORE__'
    blob = json.dumps(d, sort_keys=True).encode()
    assert sha(blob) == r['normalized_manifest_sha256']
    assert {f['name']: sha(json.dumps(f, sort_keys=True).encode()) for f in d['functions']} == r['functions']
    assert sum(f['il'].count('call $myl_native_cow_tally') for f in d['functions']) == r['cow_tally_calls']
    normalized[label] = blob
expected_labels = set()
current_labels, historical_mismatches = set(), set()
for runtime in ['rc', 'gc']:
    for command in ['emit-project-qbe', 'native-test-compile']:
        for counting in [0, 1]:
            prefix = f'{runtime}-{command}-{counting}'
            modes = ['control', 'default', 'explicit-original', 'historical-v1']
            if command == 'emit-project-qbe':
                modes += ['control-drop', 'candidate-drop']
                assert normalized[prefix + '-control-drop'] == normalized[prefix + '-control']
                assert normalized[prefix + '-candidate-drop'] == normalized[prefix + '-control']
                current_labels.add(prefix + '-drop')
            expected_labels.update(prefix + '-' + mode for mode in modes)
            for mode in ['default', 'explicit-original']:
                assert normalized[prefix + '-' + mode] == normalized[prefix + '-control']
                current_labels.add(prefix + '-' + mode)
            if normalized[prefix + '-historical-v1'] != normalized[prefix + '-control']:
                historical_mismatches.add(prefix)
assert set(normalized) == expected_labels and len(current_labels) == 20
assert len({r['label'] for r in COMPAT['comparisons']}) == 28
assert sha(raw(work / 'policy_program.my')) == COMPAT['source_sha256']
assert historical_mismatches == {'gc-emit-project-qbe-1', 'gc-native-test-compile-1'}
for r in COMPAT['comparisons']:
    label = r['label']
    if r.get('historical_only'):
        prefix = label.removesuffix('-historical-v1')
        assert r['full_il_and_metadata_equal'] == (prefix not in historical_mismatches)
    else:
        assert label in current_labels and r['full_il_and_metadata_equal']
witness = COMPAT['whole_project_counting_witness']
assert witness['status'] == 0 and witness['environment'] == {'MYLANG_COW_COUNTING': '1'}
whole_stdout = raw(work / 'whole-project-counting.stdout')
assert sha(whole_stdout) == witness['stdout_sha256']
assert sha(raw(work / 'whole-project-counting.stderr')) == witness['stderr_sha256']
assert sum(f['il'].count('call $myl_native_cow_tally') for f in json.loads(whole_stdout)['functions']) == witness['cow_tally_calls'] == 5

PRODUCER = doc(S / 'producer-check-final-v2/qualification.json')
assert PRODUCER['verified_after'] and len(PRODUCER['runs']) == 12
assert PRODUCER['immutable_prefixes_before'] == PRODUCER['immutable_prefixes_after']
prefixes(PRODUCER['immutable_prefixes_after'])
assert {(r['name'], r['round']) for r in PRODUCER['runs']} == {
    (kind + '-' + backend, round_) for kind in ['self', 'foreign']
    for backend in ['qbe', 'llvm', 'legacy'] for round_ in [0, 1]}
for r in PRODUCER['runs']:
    assert r['status'] == 0
    live(r['binary'], r['binary_sha256'])
    assert r['expected_policy'] == ('qbe-v2' if r['name'] == 'self-qbe' else 'original')
    assert bool(r['marked_artifacts']) == (r['expected_policy'] == 'qbe-v2')
    raw(r['stdout'])
    raw(r['stderr'])
for name in ['foreign-qbe', 'foreign-llvm', 'foreign-legacy']:
    calls = PRODUCER['foreign_argv_' + name]
    assert len(calls) == 2 and all(not any('native-variants' in arg for arg in argv) for argv in calls)

POST = doc(S / 'postflight-v2.json')
assert POST['verified_current'] and POST['core878'] == CORE['core'] and POST['source37'] == SOURCE
prefixes(POST['immutable_prefixes_current'])
for path, expected in POST['current_helpers_sha256'].items():
    assert sha(raw(path)) == expected
for name, expected in POST['receipts_sha256'].items():
    assert sha(raw(S / name)) == expected
for name in ['policy-v2-frozen-focus.command.json', 'guardian-v2.command.json']:
    assert doc(S / name)['status'] == 0
assert b'88 check(s) passed' in raw(S / 'guardian-v2.stderr')
assert b'"passed":20,"failed":0,"skipped":0' in raw(S / 'policy-v2-frozen-focus.stderr')
assert b'"passed":5,"failed":0,"skipped":0' in raw(S / 'policy-v2-frozen-focus.stderr')

print(json.dumps(dict(verified=True, compiler_source_files=878, selected_source_files=37,
    frozen_v1_to_v2_changed_files=2, actual_guest_flavors=4, llvm_frontend_records_exact=420,
    allocated_equivalence_pairs=3, allocated_sections_per_pair=26, public_fresh=336,
    native_exact=1168, ast_focused_exact=96, checked_refusals=8, native_stress_omissions=80,
    compatibility_commands=40, current_full_il_metadata_comparisons=20,
    historical_v1_comparisons=8, historical_v1_counting_mismatches=2,
    whole_counting_witness_calls=5, actual_producer_cold_warm_commands=12,
    final_focused_units=20, final_focused_cli=5, author_guardian_checks=88,
    native_full_prefix_saved_maps=False, retrospective_current_prefix_binding=True,
    no_compiler_or_guest_executed=True, performance_or_selection_claim=False), indent=2))
