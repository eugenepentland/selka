"""Final additive package verification; no payload execution or writes."""
import base64
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
REVIEW = json.loads((HERE / 'review.json').read_bytes())
PRIOR = HERE.parent / 'lox-compiler-runtime-protocol-review-20261003'
A = Path(REVIEW['author_worktree'])


def sha(data):
    return hashlib.sha256(data).hexdigest()


for name, row in REVIEW['inputs'].items():
    data = (HERE / name).read_bytes()
    assert sha(data) == row['sha256'] and Path(row['path']).read_bytes() == data
before = json.loads(gzip.decompress((PRIOR / 'receipts.json.gz').read_bytes()))['files']
packed = (HERE / 'receipts.json.gz').read_bytes()
after = json.loads(gzip.decompress(packed))['files']
index = json.loads((HERE / 'archive-manifest.json').read_bytes())
assert sha(packed) == index['archive_sha256']
assert len(before) == 35 and len(after) == 37 and set(after) == set(index['files'])
assert set(after) - set(before) == set(REVIEW['new_payloads'])
assert all(after[name] == value for name, value in before.items())
BYTES = {name: base64.b64decode(data, validate=True) for name, data in after.items()}
for name, data in BYTES.items():
    assert sha(data) == index['files'][name]['sha256'] and len(data) == index['files'][name]['bytes']
frozen = json.loads(BYTES['raw/frozen-source-v1.json'])
assert sha(BYTES['raw/frozen-source-v1.json']) == REVIEW['source_descriptor_sha256']
for name, expected in frozen['files'].items():
    data = BYTES['source/' + name]
    assert sha(data) == expected
    assert (Path(frozen['source_root']) / name).read_bytes() == data
    assert (Path(frozen['frozen_root']) / name).read_bytes() == data
    committed = subprocess.run(['git', 'show', REVIEW['author_commit'] + ':' +
        str(Path(frozen['source_root']).relative_to(A) / name)], cwd=A, capture_output=True, check=True).stdout
    assert committed == data
base = json.loads(BYTES['source/protocol-base.json'])
for name, row in base['files'].items():
    assert sha(Path(row['original_path']).read_bytes()) == row['sha256']
    assert sha(BYTES['source/base/' + name]) == row['sha256']
for name, row in base['reused'].items():
    assert sha(Path(row['original_path']).read_bytes()) == row['sha256']
    assert sha(BYTES['source/base/reused/' + name]) == row['sha256']
old_qual = json.loads((PRIOR / 'qualification.json').read_bytes())
qual = json.loads((HERE / 'qualification.json').read_bytes())
old_qual.pop('independent_review')
new_qual = dict(qual)
new_qual.pop('independent_review')
new_qual.pop('legacy_alias_current_identity_receipt_sha256')
assert old_qual == new_qual
assert qual['independent_review']['commit'] == REVIEW['prior_review_commit']
assert BYTES['raw/independent-review.json'] == (PRIOR / 'review.json').read_bytes()
assert qual['independent_review']['review_sha256'] == sha(BYTES['raw/independent-review.json'])
assert qual['legacy_alias_current_identity_receipt_sha256'] == sha(BYTES['raw/legacy-alias-runtime-scope.json'])
assert 'line 23' in (HERE / 'historical-root-verification-failure.log').read_text()
assert 'AssertionError' in (HERE / 'historical-root-verification-failure.log').read_text()

scope = json.loads(BYTES['raw/legacy-alias-runtime-scope.json'])
guards = json.loads((HERE / 'legacy-guards.json').read_bytes())
manifest = json.loads((HERE / 'legacy-binaries.json').read_bytes())
builds = json.loads((HERE / 'legacy-rebuilt-build.json').read_bytes())
assert len(guards) == scope['guards'] == 223
assert sha((HERE / 'legacy-guards.json').read_bytes()) == scope['guards_sha256']
assert sha((HERE / 'legacy-binaries.json').read_bytes()) == scope['binaries_sha256']
assert sha((HERE / 'legacy-rebuilt-build.json').read_bytes()) == scope['build_record_sha256']
for path, expected in guards.items():
    assert sha(Path(path).read_bytes()) == expected
for arm, row in scope['measured'].items():
    assert row['ELF'] == manifest['binaries'][arm]
    assert row['ELF_sha256'] == manifest['binary_sha256'][arm] == guards[row['ELF']]
    if arm in ['rust', 'go']:
        continue
    meta_path = row['ELF'] + '.qbe-manifest.json'
    meta = json.loads(Path(meta_path).read_bytes())
    assert sha(Path(meta_path).read_bytes()) == guards[meta_path]
    assert sha(Path(row['ELF'] + '.qbe-receipt').read_bytes()) == guards[row['ELF'] + '.qbe-receipt']
    assert meta['runtime_object'] == row['runtime']
    assert sha(Path(row['runtime']).read_bytes()) == row['runtime_sha256'] == guards[row['runtime']]
assert len(scope['missing_reproduction_runtime_bindings']) == 2
assert {r['runtime_object'] for r in builds['builds']} == {
    r['runtime'] for r in scope['missing_reproduction_runtime_bindings']}
for row in scope['missing_reproduction_runtime_bindings']:
    assert row['runtime'] not in guards and row['guarded_in_legacy_trial'] is False
    assert sha(Path(row['runtime']).read_bytes()) == row['sha256']
print(json.dumps(dict(verified=True, author_commit=REVIEW['author_commit'],
    prior35_payloads_unchanged=True, final_package_payloads=37, added_payloads=2,
    source_files_unchanged=25, originals_unchanged=12, legacy_guards_unchanged=223,
    current_reconciliation_measured_guests=6, unguarded_historical_reproduction_archives=2,
    historical_live_package_refusal_preserved=True, author_host_tests_remain_synthetic=30,
    author_guardian_checks=88, no_payload_or_perf_execution=True,
    no_retrospective_trial_pass=True, performance_or_selection_claim=False), indent=2))
