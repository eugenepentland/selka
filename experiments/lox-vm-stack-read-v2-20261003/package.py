#!/usr/bin/env python3
"""Seal completed V2 source/qualification/static evidence; does not run guests."""
from pathlib import Path
import collections, difflib, gzip, hashlib, json, re

lane = Path(__file__).resolve().parents[2]
dest = Path(__file__).resolve().parent
work = lane/'.tmp-lox-vm-stack-read-v2-20261003'
v1 = lane/'.tmp-lox-vm-stack-read-20261003'
root = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
sha = lambda f: hashlib.sha256(Path(f).read_bytes()).hexdigest()
files = lambda p: {str(f.relative_to(p)): sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
maps = {'control': files(v1/'control'), 'v1-qualified': files(v1/'equal-qualified'), 'inline-qualified': files(work/'inline-qualified')}
assert all(len(m) == 37 for m in maps.values())
assert maps['control'] == json.loads((root/'.tmp-lox-round3/binaries.json').read_text())['candidate_sources']['ast']['all_files']
changed = [n for n in maps['control'] if maps['control'][n] != maps['inline-qualified'][n]]
assert changed == ['driver_cases.json', 'driver_tests.my', 'vm.my']
assert [n for n in maps['v1-qualified'] if maps['v1-qualified'][n] != maps['inline-qualified'][n]] == ['vm.my']
patch = ''.join(''.join(difflib.unified_diff((v1/'control'/n).read_text().splitlines(True), (work/'inline-qualified'/n).read_text().splitlines(True), fromfile='a/'+n, tofile='b/'+n)) for n in changed)
(dest/'readonly-stack-equality-inline.patch').write_text(patch)
(dest/'source-hashes.json').write_text(json.dumps({'base_commit': '37df3ffbfab1f2ea4f269c769eb5b013c5270be3', 'v1_commit': 'f4d3fbcced87816210732a200aa765366a0ff8cf', 'source': {'control': str(v1/'control'), 'v1-qualified': str(v1/'equal-qualified'), 'inline-qualified': str(work/'inline-qualified')}, 'source_sha256': maps, 'changed_from_control': changed, 'changed_from_v1': ['vm.my'], 'patch_sha256': sha(dest/'readonly-stack-equality-inline.patch')}, indent=2)+'\n')
value = (work/'inline-qualified/value.my').read_text()
start = value.index('    match a:\n', value.index('public def values_equal('))
end = value.index('\n\n\n# The shortest', start)
body = value[start:end].replace('match a:', 'match left_value:').replace('match b:', 'match right_value:').replace('case Value.', 'case value.Value.')
vm = (work/'inline-qualified/vm.my').read_text()
assert vm[vm.index('    match left_value:', vm.index('def equal_stack(')):vm.index('\n\n\n# Each invocation', vm.index('def equal_stack('))] == body
build = json.loads((work/'builds.json').read_text())
tests = json.loads((work/'public-qualification.json').read_text())
native = json.loads((work/'native-validation.json').read_text())
assert build['verified_after'] and tests['verified_after'] and native['verified_after']
assert build['source_sha256'] == tests['source_sha256'] == native['source_sha256'] == maps['inline-qualified']
assert len(native['samples']) == 348 and all(r['passed'] and r['actual'] == r['expected'] for r in native['samples'])
counts = collections.Counter((r['backend'], r['runtime'], r['native_gc_stress'], r['lox_gc_stress']) for r in native['samples'])
assert len(counts) == 12 and set(counts.values()) == {29}
for row in tests['runs']:
    assert row['status'] == 0 and row['summaries'] == ['86 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 10 programs']
    assert sha(row['log']) == row['log_sha256']
    for name in ['test_run_readonly_stack_equality_tags_and_order', 'test_run_readonly_stack_equality_preserves_snapshots']:
        assert 'passed driver_tests::'+name in Path(row['log']).read_text()
for row in build['runs']:
    assert row['status'] == 0
    for key in ['binary', 'manifest', 'receipt', 'runtime_object']:
        assert sha(row[key]) == row[key+'_sha256']
    assert ('--gc-runtime' in row['argv']) == (row['runtime'] == 'gc')
    assert '--drop-step-checks' not in row['argv'] and '--drop-frame-checks' not in row['argv']
assert {k: sha(p) for k, p in native['binaries'].items()} == native['binary_sha256']

static = {}
for backend in ['llvm', 'qbe']:
    static[backend] = {}
    for name in ['run', 'equal_stack']:
        path = work/(backend+'-'+name+'.asm')
        text = path.read_text()
        static[backend][name] = {'instructions': len([line for line in text.splitlines() if re.match(r'\s*[0-9a-f]+:\s+', line)]), 'calls': re.findall(r'call\s+[^\n]*<([^>]+)>', text), 'assembly': str(path), 'assembly_sha256': sha(path)}
assert static['llvm']['run']['instructions'] == 5549 and not static['llvm']['equal_stack']['instructions']
assert static['qbe']['run']['instructions'] == 8373 and static['qbe']['equal_stack']['instructions'] == 219
assert len(static['qbe']['equal_stack']['calls']) == 8 and all(n.startswith('myl_qbe_fail_') for n in static['qbe']['equal_stack']['calls'])
initial = json.loads((work/'emission-receipt.json').read_text())
assert initial['status'] == 1 and 'E_UNKNOWN_SYMBOL' in (work/'emission.stderr').read_text()
assert initial['source_sha256'] == files(work/'namespace-rejected')
fixed = json.loads((work/'emission-fixed-receipt.json').read_text())
assert fixed['status'] == 0 and fixed['source_sha256'] == maps['inline-qualified']
units = {f['name']: f for f in json.loads((work/'emission-fixed.json').read_text())['functions']}
helper = units['vm::equal_stack']
assert helper['test_dependencies']['dependencies'] == []
static['diagnostic_IL'] = {'stdout_sha256': sha(work/'emission-fixed.json'), 'helper_lines': len(helper['il'].splitlines()), 'helper_blits': helper['il'].count(' blit '), 'helper_calls': re.findall(r'call (\$[^\s(]+)', helper['il']), 'limits': 'Dropped frame/step accounting only in diagnostic IL, never actual qualification guests.'}
paths = json.loads((work/'qbe-static-success-paths.json').read_text())
replay = json.loads((work/'static-replay.json').read_text())
assert paths['rows'] == replay['rows'] and [r['delta'] for r in paths['rows']] == [-4]*4
static['same_valid_tag_static_paths'] = {r['same_tag']: {'v1': r['v1_count'], 'v2': r['v2_count']} for r in paths['rows']}
(dest/'static-evidence.json').write_text(json.dumps(static, indent=2)+'\n')

payload = {}
names = ['builds.json', 'public-qualification.json', 'native-validation.json', 'initial-source.json', 'corrected-source.json', 'emission-receipt.json', 'emission-fixed-receipt.json', 'emission.stderr', 'emission-fixed.stderr', 'qbe-static-success-paths.json', 'static-replay.json', 'build.log', 'public-test.log', 'native-validation.log', 'run.ssa', 'equal_stack.ssa', 'qbe-v1-values_equal.asm']
names += [backend+'-'+name+'.asm' for backend in ['llvm', 'qbe'] for name in ['run', 'equal_stack']]
names += [Path(r['log']).name for r in tests['runs']]
names += [Path(r[k]).name for r in build['runs'] for k in ['stdout', 'stderr']]
extra = {'v1-helper.asm': v1/'qbe-vm-equal_stack.asm', 'namespace-rejected-vm.my': work/'namespace-rejected/vm.my'}
for name, path in [(n, work/n) for n in names] + list(extra.items()):
    data = path.read_bytes()
    packed = name if name.endswith('.json') and name != 'native-validation.json' else name+'.gz'
    if packed == name:
        (dest/packed).write_bytes(data)
    else:
        with (dest/packed).open('wb') as out:
            with gzip.GzipFile(fileobj=out, mode='wb', mtime=0, filename='') as z:
                z.write(data)
    payload[packed] = {'original': str(path), 'sha256': sha(path), 'packed_sha256': sha(dest/packed)}
v1_screen = root/'experiments/lox-hotpath-screen-20261003/equality-v1.json'
(dest/'v1-central-screen.json').write_bytes(v1_screen.read_bytes())
(dest/'qualification.json').write_text(json.dumps({'complete': True, 'source_sha256': maps['inline-qualified'], 'compiler_sha256': build['compiler_sha256'], 'qbe_sha256': build['qbe_sha256'], 'public_tests': 344, 'native_exact_comparisons': 348, 'distinct_complete_checks': 692, 'native_matrix_counts': {str(k): v for k, v in sorted(counts.items())}, 'historical_unqualified_emit_status': 1, 'historical_unqualified_emit_not_added_to_passes': True, 'v1_frozen_commit': 'f4d3fbcced87816210732a200aa765366a0ff8cf', 'v1_central_screen': {'original': str(v1_screen), 'sha256': sha(v1_screen)}, 'payload': payload, 'performance_runs_by_lane': 0, 'selected': False}, indent=2)+'\n')
print('Packaged V2: all37 source hashes,344 public tests,348 native exact comparisons; no perf claim.')
