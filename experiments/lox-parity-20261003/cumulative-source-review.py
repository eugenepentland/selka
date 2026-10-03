#!/usr/bin/env python3
"""Read-only independent evidence check; writes only this lane's review JSON."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import re

ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
SWEEP = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-ownership-inline-20261003')
BASE = ROOT / '.tmp-lox-parity/baseline/lox/benchmarks/lox/ports/mylang'
FINAL = ROOT / '.tmp-lox-parity/replay-final-absolute/lox/benchmarks/lox/ports/mylang'
PATCH = ROOT / 'docs/audits/d9-stage3d-migrations/lox-runtime-perf-20261003.patch'
SPEC = ROOT / '.tmp-lox-parity/inputs/pinned-SPEC.md'
WORK = SWEEP / '.tmp-lox-sweep'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


patch_lines = PATCH.read_text().splitlines(keepends=True)
replayed = {}
i = 0
while i < len(patch_lines):
    if not patch_lines[i].startswith('--- '):
        i += 1
        continue
    name = patch_lines[i + 1][4:].strip().split('\t')[0].removeprefix('b/')
    i += 2
    src = (BASE / name).read_text().splitlines(keepends=True)
    out, pos, hunks = [], 0, 0
    while i < len(patch_lines) and not patch_lines[i].startswith('--- '):
        if not patch_lines[i].startswith('@@ '):
            i += 1
            continue
        hunk = re.match(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', patch_lines[i])
        start = int(hunk[1]) - 1
        out.extend(src[pos:start])
        pos, i, hunks = start, i + 1, hunks + 1
        while i < len(patch_lines) and not patch_lines[i].startswith(('@@ ', '--- ')):
            line = patch_lines[i]
            if line.startswith(' '):
                assert src[pos] == line[1:], (name, pos)
                out.append(src[pos])
                pos += 1
            elif line.startswith('-'):
                assert src[pos] == line[1:], (name, pos)
                pos += 1
            elif line.startswith('+'):
                out.append(line[1:])
            else:
                raise AssertionError((name, line))
            i += 1
    out.extend(src[pos:])
    assert ''.join(out).encode() == (FINAL / name).read_bytes(), name
    replayed[name] = hunks

names = {p.relative_to(FINAL).as_posix() for p in FINAL.rglob('*') if p.is_file()}
assert names == {p.relative_to(BASE).as_posix() for p in BASE.rglob('*') if p.is_file()}
changed = sorted(n for n in names if (BASE / n).read_bytes() != (FINAL / n).read_bytes())
assert changed == sorted(replayed)
qualified = WORK / 'qualified'
assert all((qualified / n).read_bytes() == (FINAL / n).read_bytes() for n in names)


def tests(directory):
    return {(n, t) for n in names if n.endswith('.my')
            for t in re.findall(r'public def (test_\w+)\(', (directory / n).read_text())}


before, after = tests(BASE), tests(FINAL)
assert not before - after
providers_before = json.loads((BASE / 'driver_cases.json').read_text())
providers_after = json.loads((FINAL / 'driver_cases.json').read_text())
assert all(providers_after[k] == v for k, v in providers_before.items())
new_driver_tests = {'driver_tests::' + name for module, name in after - before if module == 'driver_tests.my'}
assert set(providers_after) - set(providers_before) == new_driver_tests
assert len({json.dumps(v, sort_keys=True) for v in providers_after.values()}) == 1

unit_path, validation_path = WORK / 'unit-qualified.json', WORK / 'validation.json'
unit, validation = json.loads(unit_path.read_text()), json.loads(validation_path.read_text())
assert unit['verified_after'] and validation['verified_after']
assert sha(unit['compiler']) == unit['compiler_sha256']
assert all(sha(FINAL / n) == h for n, h in unit['source_sha256'].items())
for run in unit['runs']:
    assert run['status'] == 0
    assert sha(run['log']) == run['log_sha256']
    assert '80 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 10 programs' in run['stdout']
    names_in_run = set(re.findall(r'^passed (\w+::test_\w+)$', run['stdout'], re.M))
    assert names_in_run == {module.removesuffix('.my') + '::' + test for module, test in after}
assert len(unit['runs']) == 4
manifest = json.loads((WORK / 'validation-manifest.json').read_text())
assert sha(WORK / 'validation-manifest.json') == validation['manifest_sha256']
assert all(sha(path) == validation['binary_sha256'][arm] for arm, path in manifest['binaries'].items())
keys = [(s['name'], s['tier'], s['engine'], s['arm'], s['lox_gc_stress']) for s in validation['samples']]
assert len(keys) == len(set(keys))
assert all(s['actual'] == s['expected'] for s in validation['samples'])
assert all(sha(s['command'][-1]) == s['source_sha256'] for s in validation['samples'])

result = {
    'reviewer': '/root/frames', 'review_date': '2026-10-03', 'scope': 'cumulative source overlay; read-only; no builds/tests/performance runs',
    'patch': str(PATCH), 'patch_sha256': sha(PATCH), 'spec': str(SPEC), 'spec_sha256': sha(SPEC),
    'baseline': str(BASE), 'final': str(FINAL), 'all_files': len(names), 'in_memory_replay_exact': True,
    'qualified_files_exact': True, 'changed_hunks': replayed,
    'final_sha256': {n: sha(FINAL / n) for n in sorted(names)},
    'before_tests': len(before), 'after_tests': len(after), 'added_tests': sorted(after - before), 'removed_tests': [],
    'added_driver_providers': sorted(new_driver_tests), 'prior_providers_unchanged': True,
    'unit_receipt': str(unit_path), 'unit_receipt_sha256': sha(unit_path), 'unit_verified_after': True,
    'unit_runs': [{k: v for k, v in run.items() if k != 'stdout'} for run in unit['runs']],
    'unit_total_fresh_passes': 320,
    'validation_receipt': str(validation_path), 'validation_receipt_sha256': sha(validation_path),
    'validation_script': str(SWEEP / 'experiments/lox-sweep-scalar-20261003/validate.py'),
    'validation_script_sha256': sha(SWEEP / 'experiments/lox-sweep-scalar-20261003/validate.py'),
    'validation_verified_after': True, 'validation_exact_samples': len(validation['samples']),
    'validation_tier_counts': dict(Counter(s['tier'] for s in validation['samples'])),
    'validation_native_stress_samples': sum(s['native_gc_stress'] for s in validation['samples']),
    'validation_unrun': len(validation['unrun']), 'validation_unrun_names': sorted({s['name'] for s in validation['unrun']}),
    'validation_binary_sha256': validation['binary_sha256'], 'input_and_binary_identities_match_now': True,
    'actionable_findings': [],
    'limitations': ['Manual source review and saved receipt checks, not independent workload execution or a formal proof.',
                    'Native-stressed corpus smoke cells are explicitly unrun: 104 observations; selected native regressions/errors passed.',
                    'Validation controls are positive-joined-flat, while source diff/replay uses fd867 optimized baseline.',
                    'No compiler performance or Rust/Go parity conclusion.']
}
output = Path(__file__).with_name('cumulative-source-review.json')
output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'output': str(output.resolve()), 'sha256': sha(output), 'files': len(names), 'tests': len(after),
                  'unit_passes': 320, 'exact_validation_samples': len(validation['samples']), 'actionable_findings': []}))
