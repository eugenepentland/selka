"""Read-only final policy package, source and acceptance receipt supplement."""
import base64
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
REVIEW = json.loads((HERE / 'review.json').read_bytes())
PRIOR = HERE.parent / 'lox-native-policy-review-20261003'
A = Path(REVIEW['author_worktree'])
S = Path(REVIEW['scratch'])
E = A / 'experiments/lox-native-policy-20261003'


def sha(data):
    return hashlib.sha256(data).hexdigest()


for name, row in REVIEW['inputs'].items():
    data = (HERE / name).read_bytes()
    assert sha(data) == row['sha256'] and Path(row['path']).read_bytes() == data
    committed = subprocess.run(['git', 'show', REVIEW['package_commit'] + ':' +
        str(Path(row['path']).relative_to(A))], cwd=A, capture_output=True, check=True).stdout
    assert committed == data
old_review = json.loads((PRIOR / 'review.json').read_bytes())
old_archive = (PRIOR / 'inputs.json.gz').read_bytes()
assert sha(old_archive) == old_review['inputs_archive_sha256']
original = json.loads(gzip.decompress(old_archive))
assert len(original) == 506
for path, row in original.items():
    data = base64.b64decode(row['base64'], validate=True)
    assert sha(data) == row['sha256'] == old_review['input_paths_sha256'][path]
    assert Path(path).read_bytes() == data
index = json.loads((HERE / 'archive.json').read_bytes())
assert sha((HERE / 'evidence.tar.xz').read_bytes()) == index['archive_sha256']
seen, archived = set(), {}
with tarfile.open(HERE / 'evidence.tar.xz') as stream:
    for member in stream:
        assert member.isfile() and member.name not in seen
        assert not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
        seen.add(member.name)
        data = stream.extractfile(member).read()
        assert sha(data) == index['files'][member.name]
        assert (S / member.name).read_bytes() == data
        if member.name in REVIEW['selected_receipts']:
            archived[member.name] = data
assert seen == set(index['files']) and len(seen) == REVIEW['archive_files']
assert set(archived) == set(REVIEW['selected_receipts'])
for name, expected in index['current_replay_helpers_sha256'].items():
    assert sha((E / name).read_bytes()) == expected
for path, row in original.items():
    if Path(path).is_relative_to(S):
        name = str(Path(path).relative_to(S))
        if name in index['files']:
            assert index['files'][name] == row['sha256']


def doc(name):
    return json.loads(archived[name])


def passed(name):
    results = [json.loads(line) for line in re.findall(r'^guardian/test: RESULT (.+)$',
               archived[name].decode(), re.M)]
    assert all(r['failed'] == 0 and r['skipped'] == 0 for r in results)
    return results


frozen = doc('frozen-source-v2.json')
assert sha(archived['frozen-source-v2.json']) == REVIEW['source_descriptor_sha256']
assert index['source_descriptor_sha256'] == REVIEW['source_descriptor_sha256']
assert len(frozen['core']) == 878 and len(frozen['source37']) == 37
for name, expected in frozen['core'].items():
    assert sha((A / name).read_bytes()) == expected
    assert sha((Path(frozen['core_copy']) / name).read_bytes()) == expected
for name in frozen['changed_from_base']:
    output = subprocess.run(['git', 'show', REVIEW['author_commit'] + ':' + name],
                            cwd=A, capture_output=True, check=True).stdout
    assert sha(output) == frozen['core'][name]
for name in index['current_replay_helpers_sha256']:
    output = subprocess.run(['git', 'show', REVIEW['package_commit'] + ':' +
        str(E.relative_to(A) / name)], cwd=A, capture_output=True, check=True).stdout
    assert output == (E / name).read_bytes()
compiler = doc('compiler-final-v2.json')
assert compiler['compiler_sha256'] == REVIEW['compiler_sha256']
assert compiler['qbe_sha256'] == REVIEW['qbe_sha256']
assert sha(Path(compiler['compiler']).read_bytes()) == REVIEW['compiler_sha256']
assert sha(Path(compiler['qbe']).read_bytes()) == REVIEW['qbe_sha256']
assert index['compiler_descriptor_sha256'] == sha(archived['compiler-final-v2.json'])
qualification = json.loads((HERE / 'qualification.json').read_bytes())
assert qualification['core878'] == frozen['core'] and qualification['source37'] == frozen['source37']
assert qualification['compiler_sha256'] == REVIEW['compiler_sha256']
assert qualification['qbe_sha256'] == REVIEW['qbe_sha256']
assert qualification['archive_sha256'] == index['archive_sha256']
assert qualification['inventory_sha256'] == sha((HERE / 'archive.json').read_bytes())
assert qualification['compiler_patch_sha256'] == sha((HERE / 'compiler.patch').read_bytes())
assert qualification['archive_command_sha256'] == sha((HERE / 'archive-command.command.json').read_bytes())
assert qualification['qualification'] == {
    'public_fresh': 336, 'native_bounded_exact': 1168, 'native_ast_exact': 96,
    'rc_native_stress_refusals': 8, 'native_gc_stress_smoke_omissions': 80,
    'policy_units': 20, 'inherited_native_units': 19, 'unit_12_common_blocks_repeated': True,
    'policy_cli': 5, 'qbe_gate_executed': 515, 'golden_corpus_checked': 231,
    'golden_corpus_explicit_skips': 373, 'guardian_fresh88_status': 0,
    'guardian_qbe_gate_cached_messages': 5, 'provider_execution_claim': False,
    'new_broad_unit_claim': False, 'process_ceiling_seconds': 240}
for name, expected in qualification['receipts_sha256'].items():
    assert sha(archived[name]) == expected
assert len(qualification['guests']) == 4
for row in qualification['guests']:
    for path, expected in row['artifacts_sha256'].items():
        assert sha(Path(path).read_bytes()) == expected
patch = subprocess.run(['git', 'diff', '--no-ext-diff', '--unified=0',
    frozen['base'], REVIEW['author_commit'], '--', *sorted(frozen['changed_from_base'])],
    cwd=A, capture_output=True, check=True).stdout
assert patch == (HERE / 'compiler.patch').read_bytes()
assert '--unidiff-zero' in (HERE / 'author-README.md').read_text()
assert json.loads((HERE / 'archive-command.command.json').read_bytes())['status'] == 0
for name in ['inherited-v2-focus.command.json', 'policy-v2-frozen-focus.command.json',
             'qbe-gate-v2.command.json', 'guardian-final-v2.command.json']:
    command = doc(name)
    assert type(command['status']) is int and command['status'] == 0
    assert command['environment']['MYLANG_TIMING_CPUS'] == '2,3,10,11'
    assert '.tmp-lox-native-policy-20261003/' in command['environment']['TMPDIR']
assert [r['passed'] for r in passed('inherited-v2-focus.stderr')] == [19]
assert sorted(r['passed'] for r in passed('policy-v2-frozen-focus.stderr')) == [5, 20]
qbe_results = passed('qbe-gate-v2.stderr')
assert [r['passed'] for r in qbe_results] == [116, 4, 255, 139, 1]
assert sum(r['passed'] for r in qbe_results) == 515
log = archived['qbe-gate-v2.stderr'].decode()
match = re.search(r'golden parity: checked (\d+) \(source (\d+), fixtures (\d+)\), skipped (\d+) \(docs (\d+), unmatched fixtures (\d+), data-only (\d+)\), mismatches (\d+)', log)
assert tuple(map(int, match.groups())) == (231, 175, 56, 373, 27, 345, 1, 0)
assert log.count('guardian: run-all: cached — 0 blocking') == 5
post = doc('gate-postflight-v2.json')
assert post['core878_current'] == frozen['core'] and post['initial_frozen_prefix_matches']
assert post['qbe_executed_results'] == qbe_results and post['qbe_gate_status'] == 0
assert post['golden_checked'] == 231
assert post['golden_corpus_explicit_skips'] == {'docs': 27, 'unmatched_fixtures': 345, 'data_only': 1}
assert post['guardian_cached_zero_blocking_messages'] == 5
assert post['zig_out_owned_no_symlinks']
for name, expected in post['gate_used_tools_current_sha256'].items():
    path = A / name
    assert not path.is_symlink() and sha(path.read_bytes()) == expected
assert post['candidate_prefix_current'] == compiler['owned_final_prefix']
assert post['original_guardian_v2_fresh_checks'] == 88
assert 'not a saved before-map' in post['limits']
assert b'88 check(s) passed' in archived['guardian-v2.stderr']
print(json.dumps(dict(verified=True, original_review_inputs_unchanged=506,
    final_archive_files=len(seen), source_files=878, selected_source_files=37,
    actual_compiler_and_tool_unchanged=True, author_commit=REVIEW['author_commit'],
    package_commit=REVIEW['package_commit'], inherited_focused_results=19,
    policy_focused_results=20, cli_focused_results=5,
    common_mandatory_unit_overlap=12, distinct_total_not_inferred=True,
    qbe_gate_reported_executed_results=515, qbe_gate_roots=5,
    golden_cases_checked=231, golden_corpus_explicit_skips=373, golden_mismatches=0,
    qbe_guardian_cached_zero_blocking_messages=5, prior_author_fresh_guardian_checks=88,
    gate_prefix_postflight_retrospective=True, no_fresh_full_V2_broad_unit_claim=True,
    no_payload_compiler_guest_test_or_perf_execution=True,
    performance_or_selection_claim=False), indent=2))
