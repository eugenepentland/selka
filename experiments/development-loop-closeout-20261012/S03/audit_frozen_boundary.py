#!/usr/bin/env python3
"""Read frozen Git objects and prove the final scalar-text migration inventory."""
import hashlib
import json
import re
import subprocess

C0 = 'fbfcaa7a923186a8e773c3760f81c10aa345a432'
C1 = 'a9a3208a4f3edbf17170cfc18d57f5f999af49c3'
IMPORT = re.compile(r'@import\("([^"]+)"\)')
EMBED = re.compile(r'@embedFile\("([^"]+)"\)')
NAMED = re.compile(r'^test "((?:[^"\\]|\\.)*)" \{', re.M)
WRAPPER = re.compile(r'^test \{', re.M)
FILES = ('src/text_scalar_root_test.zig', 'src/number_text.zig',
         'src/number_text_test.zig', 'src/number_grammar.txt',
         'src/format_spec.zig', 'src/format_spec_test.zig', 'src/format_spec_cases.tsv')

def read(revision, path):
    return subprocess.check_output(['git', 'show', revision + ':' + path])

def text(revision, path):
    return read(revision, path).decode()

before = text(C0, 'src/root_test.zig')
after = text(C1, 'src/root_test.zig')
scalar = text(C1, FILES[0])
expected = before.replace('    _ = @import("format_spec_test.zig");\n', '')
expected = expected.replace('test {\n    _ = @import("number_text.zig");\n    _ = @import("number_text_test.zig");\n}\n\n', '')
assert expected == after
assert len(WRAPPER.findall(before)) == len(WRAPPER.findall(after)) + len(WRAPPER.findall(scalar)) == 7
closure = set()
pending = [FILES[0]]
while pending:
    path = pending.pop()
    if path in closure:
        continue
    closure.add(path)
    if not path.endswith('.zig'):
        continue
    body = text(C1, path)
    for name in IMPORT.findall(body):
        assert name == 'std' or name.endswith('.zig'), (path, name)
        if name != 'std':
            pending.append(path.rsplit('/', 1)[0] + '/' + name)
    pending.extend(path.rsplit('/', 1)[0] + '/' + name for name in EMBED.findall(body))
assert closure == set(FILES)
for path in FILES[1:]:
    assert read(C0, path) == read(C1, path), path
names = {}
for path in ('src/number_text_test.zig', 'src/format_spec_test.zig'):
    names[path] = NAMED.findall(text(C0, path))
    assert names[path] == NAMED.findall(text(C1, path))
    line = '    _ = @import("' + path.rsplit('/', 1)[1] + '");\n'
    assert before.count(line) == scalar.count(line) == 1
    assert after.count(line) == 0
assert sum(map(len, names.values())) == 8
base = 'experiments/development-loop-closeout-20261012/coordinator/'
inventory = json.loads(read(C1, base + 'candidate-inventory.json'))
assert len(inventory['groups']) == 46
assert inventory['coverage'] == {'required_actions': 101, 'registered_actions': 101, 'unknown_actions': []}
assert sum(len(group['steps']) for group in inventory['action_metadata']) == 101
[group] = [group for group in inventory['groups'] if group['id'] == 'text_scalar_unit']
assert set(group['inputs']) == closure
assert group['artifacts'] == ['text-scalar-units'] and group['cacheable']
run = text(C1, base + 'scalar-plan.log')
filters = text(C1, base + 'scalar-filter-controls.log')
assert 'guardian/test: PASS — 9 passed' in run
assert '"passed":9,"failed":0,"skipped":0' in run
assert 'guardian/test: PASS — 2 passed' in filters
assert '"filter": "s03-guaranteed-absent-filter", "status": 1, "expected": 1' in filters
report = {
    'schema': 'frozen-text-scalar-boundary-audit-v1', 'C0': C0, 'C1': C1,
    'named_tests': names, 'named_count_before': 8, 'named_count_after': 8,
    'wrapper_counts': {'C0_units': 7, 'C1_units': 6, 'C1_text_scalar': 1},
    'existing_modules_and_oracles_byte_identical': True,
    'broad_root_change_exactly_approved_removal': True,
    'closure': [{'path': path, 'sha256': hashlib.sha256(read(C1, path)).hexdigest()} for path in sorted(closure)],
    'inventory_groups': 46, 'registered_members': 101, 'required_members': 101, 'unknown_members': 0,
    'scalar_group': group,
    'execution_evidence': {'full_root_passed': 9, 'matching_filter_passed': 2, 'absent_filter_expected_exit': 1},
    'evidence_sha256': {base + path: hashlib.sha256(read(C1, base + path)).hexdigest()
                        for path in ('candidate-inventory.json', 'scalar-plan.log', 'scalar-filter-controls.log')},
    'paired_cold_compile_link_rss_acceptance': 'not qualified',
}
print(json.dumps(report, indent=2, sort_keys=True))
