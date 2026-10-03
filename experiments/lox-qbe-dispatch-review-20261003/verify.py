"""Read-only verification of this frozen dispatch proof review; no guest runs."""
import gzip
import hashlib
import json
from pathlib import Path
import re


HERE = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify():
    review = json.loads((HERE / 'review.json').read_text())
    data = {}
    for name, item in review['inputs'].items():
        saved = (HERE / item['copy']).read_bytes()
        assert sha(saved) == item['copy_sha256'], name
        original = gzip.decompress(saved)
        assert sha(original) == item['sha256'], name
        assert Path(item['path']).read_bytes() == original, name
        data[name] = original
    descriptor = json.loads(data['proof-v3.json'])
    previous = json.loads(data['proof-v2.json'])
    for name, expected in descriptor['files'].items():
        assert sha(data['proof-v3/' + name]) == expected, name
        assert sha((Path(review['author_worktree']) / name).read_bytes()) == expected, name
        if name != 'src/qbe_build_scratch_chain_test.zig':
            assert previous['files'][name] == expected, name
    for name, marker in [
        ('focused-proof-v3', 'RESULT {"passed":20,"failed":0,"skipped":0}'),
        ('guardian-proof-v3', 'run-all: 88 check(s) passed'),
        ('standalone-qbe-v3', ''),
    ]:
        command = json.loads(data[name + '.json'])
        assert command['status'] == 0, name
        log = data[name + '.log']
        assert sha(log) == command['log_sha256'], name
        assert marker in log.decode(), name
    original = data['original-vm-run.ssa'].decode()
    candidate = data['dispatch-v3.ssa'].decode()
    marker = ' # QBE-SCRATCH-CHAIN-1 original comparison leaves retained\n'
    start = candidate.index(marker)
    finish = candidate.rindex('}')
    new = candidate[start:finish]
    assert len(re.findall(r'^@qbe_dispatch_', new, re.M)) == 30
    assert len(re.findall(r' =w csltl ', new)) == 30
    assert len(re.findall(r' =l loadl ', new)) == 2
    restored = candidate[:start] + candidate[finish:]
    feasibility = json.loads(data['feasibility.json'])
    assert len(feasibility['chains']) == 2
    for index, chain in enumerate(feasibility['chains']):
        assert len(chain['nodes']) == 16
        assert chain['values'] == sorted(set(chain['values']))
        old = '@' + chain['head']
        replacement = f'@qbe_dispatch_{index}_0_16'
        assert restored.count(replacement) == 1
        line = chain['original_entry'][0][2] - 1
        assert original.splitlines()[line].endswith(', ' + old)
        assert restored.splitlines()[line].endswith(', ' + replacement)
        restored = restored.replace(replacement, old)
    assert restored == original
    report = {
        'scope': 'read-only frozen proof and author command evidence; no compiler, guest, or performance execution',
        'input_count': len(data),
        'all_original_and_saved_bytes_match': True,
        'production_v2_v3_identical': True,
        'author_focused_passed': 20,
        'author_guardian_passed': 88,
        'standalone_qbe_status': 0,
        'original_vm_run_restored_exactly_after_two_edge_rewrites_and_classifier_removal': True,
        'performance_or_selection_claim': False,
    }
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    verify()
