"""Read-only frozen proof/oracle receipt bindings; no native execution."""
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
review = json.loads((HERE / 'review.json').read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def saved(name):
    return gzip.decompress((HERE / 'inputs' / (name + '.gz')).read_bytes())


for name, row in review['inputs'].items():
    compressed = (HERE / 'inputs' / (name + '.gz')).read_bytes()
    data = gzip.decompress(compressed)
    assert sha(compressed) == row['copy_sha256'] and sha(data) == row['sha256']
    assert Path(row['path']).read_bytes() == data
proofs = [json.loads(saved('proof-' + v + '.json')) for v in ['v1', 'v2']]
for v, proof in zip(['v1', 'v2'], proofs):
    assert len(proof['files']) == 6
    for name, expected in proof['files'].items():
        assert sha(saved('proof-' + v + '/' + name)) == expected
assert {name for name in proofs[0]['files']
        if proofs[0]['files'][name] != proofs[1]['files'][name]} == {'SPEC.md'}
for name, expected in proofs[1]['files'].items():
    assert sha((Path(review['author_worktree']) / name).read_bytes()) == expected
assert proofs[0]['files']['src/qbe_build_scratch_cells.zig'] == \
    '5773ba0ddd4740163c755e37a8f47bcb8ebfe253b8982f9ab7e8f6b05a2656fe'
for name in review['inputs']:
    if name.startswith('context/'):
        original = subprocess.run(['git', 'show', proofs[0]['base'] + ':' + name[8:]],
                                  cwd=review['author_worktree'], capture_output=True,
                                  check=True).stdout
        assert original == saved(name)
focused = json.loads(saved('focused-v1-owned-tool.json'))
assert focused['status'] == 0
assert focused['tests'] == dict(named=5, mandatory=12, passed=17, failed=0, skipped=0)
assert focused['source_files_before'] == focused['source_files_after'] == proofs[0]['files']
assert focused['proof_sha256'] == sha(saved('proof-v1.json'))
assert focused['log_sha256'] == sha(saved('focused-v1-owned-tool.log'))
assert focused['native_oracle_inputs'] == 13 and focused['native_output_words_each_arm'] == 4
assert focused['historical_prefix_failure_excluded'] is True
assert focused['native_QBE_before'] == proofs[0]['native_QBE']
assert focused['native_QBE_after'] == proofs[0]['native_QBE']['sha256']
assert sha(Path(proofs[0]['native_QBE']['path']).read_bytes()) == focused['native_QBE_after']
print(json.dumps(dict(verified=True, proof_versions=2, frozen_files_each=6,
                     production_and_test_bytes_identical_between_versions=True,
                     focused_passed=17, native_oracle_inputs=13,
                     guest_or_performance_commands_run=False), indent=2))
