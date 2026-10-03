#!/usr/bin/env python3
"""Read-only source, receipt and native disassembly audit. Never executes a guest."""
import argparse
from collections import Counter
import hashlib
import gzip
import io
import json
from pathlib import Path
import re
import struct
import subprocess
import tarfile

BASE = Path('/home/epentland/ai/canopy/mylang-worktrees')
FRAMES = BASE / 'codex-lox-vm-dispatch-20261003'
ROOT = BASE / 'codex-lox-parity-20261003'
EXPERIMENT = FRAMES / 'experiments/lox-vm-constant-20261003'
COMMIT = '58fe1925533ad46e3a8e60af6a9b9632510ee979'
PIN = '4e48a09220c2e018eba8c4b1eb3fe1137a3dae73'
COMPILER = 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
QBE = '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
seen = {}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def read(path):
    path = Path(path)
    data = path.read_bytes()
    value = digest(data)
    assert seen.get(str(path), value) == value, ('changed during review', path)
    seen[str(path)] = value
    return data

def checked(path, expected):
    data = read(path)
    assert digest(data) == expected, (str(path), digest(data), expected)
    return data

def load(path):
    return json.loads(read(path))

def sources(path, expected=None):
    path = Path(path)
    result = {str(p.relative_to(path)): digest(read(p)) for p in sorted(path.rglob('*')) if p.is_file()}
    assert len(result) == 37
    if expected is not None:
        assert result == expected, path
    return result

def tests(path):
    names = set()
    for p in sorted(Path(path).glob('*.my')):
        if p.name.endswith('_test.my') or p.name == 'driver_tests.my':
            names.update(p.stem + '::' + x for x in re.findall(r'^public def (test_\w+)\(', read(p).decode(), re.M))
    return names

def virtual_patch(files, patch):
    lines = patch.decode().splitlines(keepends=True)
    result = dict(files)
    i = 0
    while i < len(lines):
        assert lines[i].startswith('--- a/')
        name = lines[i][6:].rstrip('\n')
        assert lines[i + 1] == '+++ b/' + name + '\n'
        old = files[name].decode().splitlines(keepends=True)
        new = []
        cursor = 0
        i += 2
        while i < len(lines) and lines[i].startswith('@@ '):
            hunk = re.fullmatch(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@.*\n', lines[i])
            assert hunk
            old_start, old_count, new_start, new_count = [int(x) if x is not None else 1 for x in hunk.groups()]
            start = old_start - 1
            assert start >= cursor
            new += old[cursor:start]
            cursor = start
            assert len(new) == new_start - 1
            i += 1
            old_used = new_used = 0
            while i < len(lines) and not lines[i].startswith(('@@ ', '--- a/')):
                kind, body = lines[i][0], lines[i][1:]
                assert kind in ' +-'
                if kind in ' -':
                    assert old[cursor] == body, (name, cursor)
                    cursor += 1
                    old_used += 1
                if kind in ' +':
                    new.append(body)
                    new_used += 1
                i += 1
            assert (old_used, new_used) == (old_count, new_count)
        new += old[cursor:]
        result[name] = ''.join(new).encode()
    return result

def instructions(text):
    return re.findall(r'^\s*([0-9a-f]+):\s+([a-z][\w.]*)\b(.*)$', text, re.M)

def disassemble(binary, symbol):
    argv = ['objdump', '-d', '--no-show-raw-insn', '--disassemble=' + symbol, str(binary)]
    return subprocess.check_output(argv, text=True), argv

def elf_table(binary, address, count):
    data = read(binary)
    assert data[:6] == b'\x7fELF\x02\x01'
    phoff = struct.unpack_from('<Q', data, 32)[0]
    entsize, num = struct.unpack_from('<HH', data, 54)
    for i in range(num):
        p = struct.unpack_from('<IIQQQQQQ', data, phoff + i * entsize)
        typ, _, off, vaddr, _, filesz, _, _ = p
        if typ == 1 and vaddr <= address and address + count * 8 <= vaddr + filesz:
            return struct.unpack_from('<' + 'Q' * count, data, off + address - vaddr)
    raise AssertionError('table not mapped')

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
assert not a.out.exists(), 'receipt output must be new'
tracked = subprocess.check_output(['git', '-C', str(FRAMES), 'ls-tree', '-r', '--name-only', COMMIT, '--', str(EXPERIMENT.relative_to(FRAMES))], text=True).splitlines()
assert len(tracked) == 17
for name in tracked:
    blob = subprocess.check_output(['git', '-C', str(FRAMES), 'show', COMMIT + ':' + name])
    assert read(FRAMES / name) == blob, name
q = load(EXPERIMENT / 'qualification.json')
b = load(EXPERIMENT / 'build.json')
s = load(EXPERIMENT / 'static-review.json')
c = load(EXPERIMENT / 'checks.json')
for name, key in [('qualification.json', 'qualification_sha256'), ('build.json', 'build_sha256'), ('static-review.json', 'static_review_sha256'), ('guardian.log', 'guardian_log_sha256'), ('constant-readonly.patch', 'patch_sha256')]:
    checked(EXPERIMENT / name, c[key])
assert c['guardian_status'] == c['patch_replay_status'] == 0
assert c['patch_replay_files'] == 37
for receipt in [q, b, s['constant-readonly_build']]:
    assert receipt['verified_after']
    assert receipt['compiler_sha256'] == COMPILER and receipt['qbe_sha256'] == QBE
    checked(receipt['compiler'], COMPILER)
    checked(Path(receipt['compiler']).with_name('qbe'), QBE)
assert s['constant-readonly_build'] == b and s['qualification'] == q
assert s['qualification_total'] == 340 and s['static_only'] and not s['timings_run_by_lane']
control = Path(s['source_control'])
candidate = Path(q['source'])
assert control == ROOT / '.tmp-lox-next/combined'
assert candidate == FRAMES / '.tmp-lox-vm-dispatch-20261003/constant-readonly-qualified'
assert candidate == Path(s['selected_source'])
control_hashes = sources(control, s['source_control_sha256'])
candidate_hashes = sources(candidate, q['source_sha256'])
assert candidate_hashes == s['selected_source_sha256']
build_hashes = sources(b['source'], b['source_sha256'])
changed = sorted(k for k in control_hashes if control_hashes[k] != candidate_hashes[k])
assert changed == s['changed_files'] == ['driver_cases.json', 'driver_tests.my', 'vm.my']
assert sorted(k for k in build_hashes if build_hashes[k] != candidate_hashes[k]) == ['driver_cases.json', 'driver_tests.my']
files = {k: read(control / k) for k in control_hashes}
replay = virtual_patch(files, checked(EXPERIMENT / 'constant-readonly.patch', s['patch_sha256']))
assert {k: digest(v) for k, v in replay.items()} == candidate_hashes
assert read(candidate / 'driver_tests.my').startswith(read(control / 'driver_tests.my'))
old_cases, new_cases = load(control / 'driver_cases.json'), load(candidate / 'driver_cases.json')
added_name = 'driver_tests::test_run_constant_operand_last_byte'
assert set(new_cases) - set(old_cases) == {added_name}
assert all(new_cases[k] == v for k, v in old_cases.items())
assert new_cases[added_name] in old_cases.values()
old_names, new_names = tests(control), tests(candidate)
assert len(old_names) == 84 and len(new_names) == 85 and new_names - old_names == {added_name}
legacy = ROOT / '.tmp-lox-next/baseline'
legacy_hashes = sources(legacy)
legacy_names = tests(legacy)
assert len(legacy_names) == 80 and legacy_names <= old_names
runs = []
assert len(q['runs']) == 4
for row in q['runs']:
    log = checked(row['log'], row['log_sha256']).decode()
    names = re.findall(r'^passed (\S+)$', log, re.M)
    assert len(names) == len(set(names)) == 85 and set(names) == new_names
    summary = '85 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 10 programs'
    assert row['status'] == 0 and row['summaries'] == [summary]
    assert log.splitlines() == ['passed ' + n for n in names] + [summary]
    backend = 'llvm' if '--release' in row['argv'] else 'qbe'
    runtime = 'native-gc-stress' if '--gc-stress' in row['argv'] else 'rc'
    assert ('--rc-runtime' in row['argv']) == (runtime == 'rc')
    assert row['argv'][0:4] == [str(FRAMES / 'scripts/build-slot.sh'), 'build', q['compiler'], 'test']
    assert row['argv'][4] == str(candidate)
    assert row['argv'][row['argv'].index('--max-steps') + 1] == '1000000000'
    assert '--cases' not in row['argv'] and not (candidate / 'driver_tests.cases.json').exists()
    cache = Path(row['argv'][row['argv'].index('--cache-dir') + 1])
    added_case_receipts = []
    for result_file in sorted((cache / 'results').glob('*.json')):
        wrapper = json.loads(result_file.read_bytes())
        if not isinstance(wrapper.get('payload'), str):
            continue
        payload = json.loads(wrapper['payload'])
        if payload.get('name') == added_name:
            checked(result_file, digest(result_file.read_bytes()))
            assert digest(wrapper['payload'].encode()) == wrapper['sha256']
            assert payload['status'] == 'passed' and payload['actual'] is True
            assert payload['expected'] is True and payload['provider'] == ''
            added_case_receipts.append({'path': str(result_file), 'sha256': digest(result_file.read_bytes()), 'provider': payload['provider'], 'steps': payload['steps']})
    assert len(added_case_receipts) == 1
    runs.append({'backend': backend, 'runtime': runtime, 'passes': 85, 'test_names': sorted(names), 'argv': row['argv'], 'log_sha256': row['log_sha256'], 'status': row['status'], 'added_case_result': added_case_receipts[0]})
assert {(r['backend'], r['runtime']) for r in runs} == {(x, y) for x in ['llvm', 'qbe'] for y in ['rc', 'native-gc-stress']}
for row in b['runs']:
    assert row['status'] == 0
    checked(row['stdout'], row['stdout_sha256'])
    checked(row['stderr'], row['stderr_sha256'])
    if 'binary' in row:
        checked(row['binary'], row['binary_sha256'])
emission = load(b['runs'][2]['stdout'])
functions = {f['name']: f for f in emission['functions']}
helper = functions['vm::constant_at']
assert helper['symbol'] == s['constant-readonly_static']['helper']['symbol']
assert helper['il'] == read(EXPERIMENT / 'evidence/constant-readonly-helper.ssa').decode()
call_counts = dict(Counter(re.findall(r'\bcall \$(\w+)\(', helper['il'])))
assert len(helper['il'].splitlines()) == s['constant-readonly_static']['helper']['lines'] == 129
assert call_counts == s['constant-readonly_static']['helper']['calls']
assert all(k == 'memset' or k.startswith('myl_qbe_fail_') for k in call_counts)
asm_counts = {}
for path, receipt in s['assembly_files'].items():
    asm = checked(path, receipt['sha256']).decode()
    assert len(asm.encode()) == receipt['bytes']
    name = Path(path).name
    if 'vm-run' not in name:
        continue
    selected = name.startswith('constant-readonly')
    backend = 'llvm' if '-llvm.' in name else 'qbe'
    binary = next(r['binary'] for r in b['runs'] if r.get('binary', '').endswith('-' + backend)) if selected else str(ROOT / '.tmp-lox-next/bin' / ('combined-' + backend))
    regenerated, argv = disassemble(binary, functions['vm::run']['symbol'])
    ins = instructions(asm)
    assert ins == instructions(regenerated), ('assembly does not match current ELF', path)
    stats = {'decoded_instructions': len(ins), 'calls': sum(op == 'call' for _, op, _ in ins), 'read_constant_calls': sum(op == 'call' and functions['vm::read_constant']['symbol'] in args for _, op, args in ins)}
    expected = s['constant-readonly_static'][backend] if selected else s['control_static']['control-' + backend]
    assert all(stats[k] == expected[k] for k in stats)
    if not selected:
        stats['unique_field_calls'] = sum(op == 'call' and 'myl_qbe_rc_unique_field' in args for _, op, args in ins)
        assert stats['unique_field_calls'] == expected['unique_field_calls']
    if backend == 'qbe':
        assert not any(op == 'jmp' and '*' in args for _, op, args in ins)
    asm_counts[('selected-' if selected else 'control-') + backend] = dict(stats, objdump_argv=argv, binary_sha256=digest(read(binary)), asm_sha256=receipt['sha256'])
tables = []
for name in ['control-dispatch-table.json', 'readonly-dispatch-table.json']:
    table = load(EXPERIMENT / 'evidence' / name)
    checked(table['binary'], table['binary_sha256'])
    values = elf_table(table['binary'], int(table['table_address'], 16), 37)
    assert {str(i): hex(v) for i, v in enumerate(values)} == table['entries']
    assembly = next(path for path in s['assembly_files'] if ('control-vm-run-llvm' if name.startswith('control') else 'constant-readonly-vm-run-llvm') in path)
    ins = instructions(read(assembly).decode())
    index = next(i for i, (_, op, args) in enumerate(ins) if op == 'jmp' and '*' + table['table_address'] in args)
    assert ins[index - 2][1:] == ('cmp', '    $0x24,%rbx')
    assert ins[index - 1][1] == 'ja'
    tables.append({'binary_sha256': table['binary_sha256'], 'table_address': table['table_address'], 'entry_count': len(values), 'preceding_unsigned_range_check': 36})
archive = load(EXPERIMENT / 'evidence/runtime-archive-review.json')
assert archive == s['runtime_archive']
checked(archive['archive'], archive['archive_sha256'])
manifest = load(ROOT / '.tmp-lox-next/bin/combined-llvm.qbe-manifest.json')
assert manifest['runtime_object'] == archive['archive'] and manifest['lto'] and manifest['optimization'] == '3'
member = subprocess.check_output(['ar', 'p', archive['archive'], archive['member']])
assert digest(member) == archive['member_sha256'] and member[:4].hex() == archive['member_magic_hex'] == '4243c0de'
assert len(member) == archive['member_bytes'] == 42284
assert len(subprocess.check_output(['ar', 't', archive['archive']], text=True).splitlines()) == archive['members'] == 36
rejected_static = {}
for label, expected_key in [('constant-inline', None), ('constant-byte', 'constant-byte_static'), ('constant-slot', 'constant-slot_static')]:
    historical = s[label + '_build']
    sources(historical['source'], historical['source_sha256'])
    assert historical['compiler_sha256'] == COMPILER and historical['qbe_sha256'] == QBE
    for backend in ['llvm', 'qbe']:
        row = next(r for r in historical['runs'] if r.get('binary', '').endswith('-' + backend))
        checked(row['binary'], row['binary_sha256'])
        assert row['status'] == 0
        asm, _ = disassemble(row['binary'], functions['vm::run']['symbol'])
        ins = instructions(asm)
        actual = {'decoded_instructions': len(ins), 'calls': sum(op == 'call' for _, op, _ in ins), 'read_constant_calls': sum(op == 'call' and functions['vm::read_constant']['symbol'] in args for _, op, args in ins)}
        expected = s[expected_key][backend] if expected_key else s['control_static']['constant-' + backend]
        assert all(actual[k] == expected[k] for k in actual)
        rejected_static[label + '-' + backend] = actual

# Followup validates the actual native RC/GC ELFs, independently of public tests.
native_commit = '0fd93cf35db135872ea2dcc1a248d43e71229429'
native_exp = FRAMES / 'experiments/lox-vm-constant-native-20261003'
native_files = subprocess.check_output(['git', '-C', str(FRAMES), 'ls-tree', '-r', '--name-only', native_commit, '--', str(native_exp.relative_to(FRAMES))], text=True).splitlines()
assert len(native_files) == 15
for name in native_files:
    assert read(FRAMES / name) == subprocess.check_output(['git', '-C', str(FRAMES), 'show', native_commit + ':' + name])
validation = load(native_exp / 'validation.json')
native_checks = load(native_exp / 'checks.json')
checked(native_exp / 'validation.json', native_checks['validation_sha256'])
checked(native_exp / 'guardian.log', native_checks['guardian_log_sha256'])
assert native_checks['guardian_status'] == 0 and native_checks['verified_after']
native_receipts = {}
for name, meta in validation['artifacts'].items():
    data = checked(native_exp / name, meta.get('compressed_sha256', meta.get('sha256')))
    if name.endswith('.gz'):
        raw = gzip.decompress(data)
        assert digest(raw) == meta['raw_sha256']
        assert checked(meta['raw_source'], meta['raw_sha256']) == raw
        native_receipts[name] = json.loads(raw)
    else:
        checked(meta['source'], meta['sha256'])
        if name.endswith('.json'):
            native_receipts[name] = json.loads(data)
complete = native_receipts['completed.json.gz']
observations = native_receipts['observations.json.gz']
gc_builds = native_receipts['gc-builds.json']
config = native_receipts['binaries.json']
command = native_receipts['command.json']
assert complete['verified_after'] and complete['helper_status'] == 0
assert complete['after'] == {k: complete['before'][k] for k in ['candidate37', 'control37', 'artifacts_sha256']}
assert complete['before']['candidate37'] == validation['candidate37_sha256'] == build_hashes
assert complete['before']['control37'] == validation['control37_sha256'] == control_hashes
assert validation['candidate_commit'] == COMMIT and validation['verified_after']
assert validation['source'] == b['source'] and validation['control_source'] == str(control)
assert validation['all_sources_and_artifacts_unchanged'] and validation['generated_input_hashes_verified_after']
for path, expected in complete['before']['artifacts_sha256'].items():
    checked(path, expected)
assert not set(command['affinity']) & {2, 3, 10, 11}
assert command['affinity'] == validation['runner_affinity'] == complete['before']['runner_affinity']
assert '--resume' not in command['argv']
assert gc_builds['source37'] == build_hashes and gc_builds['source'] == b['source'] and gc_builds['verified_after']
assert gc_builds['compiler_sha256'] == COMPILER and gc_builds['qbe_sha256'] == QBE
for row in gc_builds['runs']:
    assert row['status'] == 0 and '--gc-runtime' in row['argv']
    for key in ['log', 'binary', 'manifest', 'runtime_object']:
        checked(row[key], row[key + '_sha256'])
    checked(row['binary'] + '.qbe-receipt', row['receipt_sha256'])
    runtime_manifest = load(row['manifest'])
    assert runtime_manifest['runtime_object'] == row['runtime_object']
    if row['binary'].endswith('-llvm'):
        assert '--llvm-opt' in row['argv'] and '--lto' in row['argv']
        assert runtime_manifest['optimization'] == '3' and runtime_manifest['lto']
assert observations['manifest_sha256'] == digest(read(native_exp / 'binaries.json'))
assert observations['verified_after']
bin_hashes = {name: digest(read(path)) for name, path in config['binaries'].items()}
assert bin_hashes == observations['binary_sha256'] == validation['actual_binary_sha256']
assert bin_hashes['constant-rc-llvm'] == asm_counts['selected-llvm']['binary_sha256']
assert bin_hashes['constant-rc-qbe'] == asm_counts['selected-qbe']['binary_sha256']
bench = Path(command['argv'][command['argv'].index('--bench') + 1])
work = Path(command['argv'][command['argv'].index('--work') + 1])
focus = Path(command['argv'][command['argv'].index('--cases') + 1])
git_archive = subprocess.check_output(['git', '-C', str(ROOT), 'archive', PIN, '--', 'benchmarks/lox/bench', 'benchmarks/lox/SPEC.md'])
with tarfile.open(fileobj=io.BytesIO(git_archive), mode='r:') as tar:
    pinned = {member.name: tar.extractfile(member).read() for member in tar.getmembers() if member.isfile()}
for path in sorted(bench.rglob('*')):
    if path.is_file():
        assert read(path) == pinned['benchmarks/lox/bench/' + str(path.relative_to(bench))]
assert read(ROOT / '.tmp-lox-parity/inputs/pinned-SPEC.md') == pinned['benchmarks/lox/SPEC.md']
cases = {}
sizes = load(bench / 'sizes.json')
for source in sorted((bench / 'scripts').glob('*.lox')):
    _, body = read(source).decode().split('\n', 1)
    content = f"var N = {sizes[source.stem]['smoke']};\n{body}"
    output = read(bench / 'expected' / (source.stem + '.smoke.out')).decode()
    for engine in ['tree', 'vm']:
        cases[source.stem, 'smoke', engine] = {'source': content, 'status': 0, 'stdout': output}
for row in load(focus):
    for engine in ['tree', 'vm']:
        cases[row['name'], 'regression', engine] = {'source': row['source'], 'status': 0, 'stdout': row['stdout']}
for engine, name in [('tree', 'd9-lox-env-reads-runs.json.gz'), ('vm', 'd9-lox-class-method-runs.json.gz')]:
    traces = json.loads(gzip.decompress(read(ROOT / 'docs/audits/evidence' / name)))['traces']
    by_name = {}
    for row in traces:
        by_name.setdefault(row['name'], row)
    assert len(by_name) == 23
    for name, row in by_name.items():
        cases[name, 'error', engine] = dict(row['expected'], source=row['source'])
assert len(cases) == 104
assert Counter(k[1] for k in cases) == {'smoke': 26, 'regression': 32, 'error': 46}
arms = set(config['binaries']) - {'control-llvm', 'control-qbe'}
assert len(arms) == 6
expected_identities = {(n, t, e, arm, stress) for n, t, e in cases for arm in arms for stress in [False, True]}
identity = lambda row: (row['name'], row['tier'], row['engine'], row['arm'], row['lox_gc_stress'])
samples, omitted = observations['samples'], observations['unrun']
sample_ids, omitted_ids = {identity(r) for r in samples}, {identity(r) for r in omitted}
assert len(samples) == len(sample_ids) == 1168
assert len(omitted) == len(omitted_ids) == 80
assert sample_ids.isdisjoint(omitted_ids) and sample_ids | omitted_ids == expected_identities
assert complete['native_smoke_unrun'] == omitted
selected_native = {'closures', 'instantiation', 'properties'}
assert set(observations['native_smoke_cases']) == selected_native
expected_omissions = {key for key in expected_identities if key[1] == 'smoke' and key[0] not in selected_native and '-gc-' in key[3]}
assert omitted_ids == expected_omissions
controls = {}
for row in samples + omitted:
    case = cases[row['name'], row['tier'], row['engine']]
    path = work / 'validation-inputs' / f"{row['name']}.{row['engine']}.{row['tier']}.lox"
    assert read(path).decode() == case['source']
    assert digest(read(path)) == row['source_sha256']
    assert row['native_gc_stress'] == ('-gc-' in row['arm'])
    if 'actual' not in row:
        assert row['unrun_reason']
        continue
    assert row['actual'] == row['expected']
    expected = row['expected']
    assert expected['status'] == case['status'] and expected['stdout'] == case['stdout']
    if row['tier'] == 'error':
        assert expected['stderr'].startswith(case['stderr'])
    key = (row['name'], row['tier'], row['engine'], row['arm'].rsplit('-', 1)[1], row['lox_gc_stress'])
    assert controls.get(key, expected) == expected
    controls[key] = expected
    argv = [config['binaries'][row['arm']], '--engine=' + row['engine'], '--stats']
    if row['lox_gc_stress']:
        argv.append('--gc-stress')
    assert row['command'] == argv + [str(path)]
mode_counts = dict(Counter('native_gc_stress' if r['native_gc_stress'] else 'rc' if '-rc-' in r['arm'] else 'ordinary_gc' for r in samples))
assert mode_counts == validation['mode_counts'] == complete['mode_counts'] == {'rc': 416, 'ordinary_gc': 416, 'native_gc_stress': 336}
boundary = native_receipts['constant-255-boundary.json.gz']['samples']
assert len(boundary) == 12
assert {(r['arm'], r['lox_gc_stress']) for r in boundary} == {(arm, stress) for arm in arms for stress in [False, True]}
boundary_text = ''.join(f'print {i};' for i in range(256))
boundary_stdout = ''.join(f'{i}\n' for i in range(256))
for row in boundary:
    assert row['actual'] == row['expected'] and row['expected']['status'] == 0 and row['expected']['stdout'] == boundary_stdout
    assert row['native_gc_stress'] == ('-gc-' in row['arm'])
    assert row['argv'][0] == config['binaries'][row['arm']]
    assert row['control_argv'][0] == config['binaries']['control-' + row['backend']]
    assert row['argv'][1:] == row['control_argv'][1:]
    assert row['argv'][1:3] == ['--engine=vm', '--stats']
    assert ('--gc-stress' in row['argv']) == row['lox_gc_stress']
    assert read(row['argv'][-1]).decode() == boundary_text
    assert digest(read(row['argv'][-1])) == row['source_sha256']
refusals = native_receipts['rc-native-stress-refusals.json.gz']['pairs']
assert len(refusals) == 8
assert {(r['backend'], r['engine'], r['lox_gc_stress']) for r in refusals} == {(b, e, s) for b in ['llvm', 'qbe'] for e in ['tree', 'vm'] for s in [False, True]}
for row in refusals:
    assert row['actual'] == row['expected'] and row['actual']['status'] == 2 and row['actual']['stdout'] == ''
    assert '--gc-runtime' in row['actual']['stderr']
    assert row['environment'] == {'MYLANG_OPTIONS': '--gc-stress'}
    assert row['argv'][0] == config['binaries']['constant-rc-' + row['backend']]
    assert row['control_argv'][0] == config['binaries']['control-' + row['backend']]
    assert row['argv'][1:] == row['control_argv'][1:]
    assert row['argv'][1:3] == ['--engine=' + row['engine'], '--stats']
    assert ('--gc-stress' in row['argv']) == row['lox_gc_stress']
native_review = {'reviewed_commit': native_commit, 'comparison_count': len(samples), 'mode_counts': mode_counts, 'operand_boundary_comparisons': len(boundary), 'checked_refusal_pairs': len(refusals), 'explicit_omissions': len(omitted), 'actual_binary_sha256': bin_hashes, 'all104_cases_and1248_identities_verified': True, 'all_status_stdout_full_stderr_stats_pairs_equal': True, 'all_recorded_source_artifact_input_hashes_verified': True, 'pinned_bench_and_SPEC_verified_against_git': PIN, 'source_metadata_scope': 'Native ELFs use the production-equivalent pre-fixture37 source; public85 source differs only in driver tests/provider metadata.', 'verified_after': True}
for path, before in seen.items():
    assert digest(Path(path).read_bytes()) == before, ('changed after review', path)
receipt = {'reviewed_commit': COMMIT, 'pinned_reference': PIN, 'source': str(candidate), 'control_source': str(control), 'source_sha256': candidate_hashes, 'control_source_sha256': control_hashes, 'changed_files': changed, 'patch_replay': '37 exact files in memory', 'compiler_sha256': COMPILER, 'qbe_sha256': QBE, 'qualification_passes': sum(r['passes'] for r in runs), 'qualification_runs': runs, 'retained_test_names': {'legacy80': len(legacy_names), 'control84': len(old_names), 'selected85': len(new_names)}, 'static_vm_run': asm_counts, 'helper': {'il_lines': 129, 'calls': call_counts, 'sha256': digest(helper['il'].encode()), 'diagnostic_accounting': 'emit-project-qbe --drop-step-checks --drop-frame-checks'}, 'llvm_dispatch_tables': tables, 'linked_runtime': archive, 'reviewed_inputs_sha256': dict(sorted(seen.items())), 'verified_after': True, 'guest_executions_by_reviewer': 0, 'measurements_by_reviewer': 0, 'native_unaccounted_behavior_reviewed': False, 'source_findings': [], 'limits': ['Fresh 340 public passes are accounted test-library configurations; later native unaccounted RC/GC ELF matrix is a separate lane receipt, not reviewed here.', 'Malformed-bytecode native helper PC attribution and tight source step/native-frame quota thresholds can differ. Same checked read/IP increment/pool read/stack write order, published Lox IP, and Lox 64-frame guard remain.', 'Only numeric constants are generated by the added index255 case; retained root/closure/string regressions provide object-constant coverage.', 'The driver_cases.json Clock fixture is structurally retained/appended, but these directory commands do not load it: all four added-case results have provider="". No provider-backed execution is claimed.', 'Static whole-function instruction/call counts include cold code and duplicated inlining. No performance acceptance or speed claim.']}
a.out.parent.mkdir(parents=True, exist_ok=True)
receipt['native_followup'] = native_review
receipt['native_unaccounted_behavior_reviewed'] = True
receipt['rejected_variant_static_counts'] = rejected_static
receipt['limits'][0] = 'Fresh 340 public passes are accounted test-library configurations. The distinct native followup qualifies actual RC/GC ELFs with 1168 comparisons plus12 operand-boundary pairs and8 checked refusals; its80 omitted native-stress smoke cells are not passes.'
a.out.write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({k: receipt[k] for k in ['reviewed_commit', 'changed_files', 'qualification_passes', 'retained_test_names', 'static_vm_run', 'verified_after', 'source_findings']}))
