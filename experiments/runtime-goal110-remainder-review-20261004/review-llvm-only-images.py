#!/usr/bin/env python3
"""Independently compare successor runtime images and replay saved checks."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-bounded-rem-llvm-20261004'
CACHE = TREE / '.mylang-cache/goal110-bounded-rem-llvm-debug'
spec = importlib.util.spec_from_file_location('elf_review', ROOT /
    'experiments/runtime-goal110-index-review-20261004/review-controls.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
from registry import checksum
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    saved = json.loads((CACHE / 'executable-equivalence.json').read_text())
    seen, rows = set(), []
    for row in saved['rows']:
        key = row['group'], row['backend']
        assert key not in seen
        seen.add(key)
        paths = [Path(row[k + '_path']) for k in ('before', 'after')]
        assert all(sha(path) == row[k + '_sha256'] for path, k in zip(paths, ('before', 'after')))
        before, after = map(module.elf, paths)
        assert before[1][4] == after[1][4]
        assert before[2] == after[2] and before[3] == after[3]
        changed = []
        for segment in before[3]:
            if segment[0] != 1:
                continue
            offset, size = segment[2], segment[5]
            left, right = [elf[0][offset:offset + size] for elf in (before, after)]
            assert len(left) == len(right) == size
            differences = [offset + i for i, pair in enumerate(zip(left, right)) if pair[0] != pair[1]]
            assert set(differences) <= set(range(40, 48))
            assert not differences or (offset == 0 and not segment[1] & 1)
            changed.extend(differences)
        assert changed == row['mapped_header_only_differences']
        rows.append(dict(group=key[0], backend=key[1], allocated_sections=len(before[2]),
                         mapped_header_only_differences=changed,
                         before_sha256=sha(paths[0]), after_sha256=sha(paths[1])))
    assert seen == {(group, backend) for group in ('legacy', 'compute', 'collections', 'text')
                    for backend in ('llvm', 'qbe')}
    path = CACHE / 'runner/manifest.json'
    manifest = json.loads(path.read_text())
    assert manifest['identity']['source_revision'] == 'df09fb4bcb57a58080543cda693554906d90105e'
    holdouts.check_manifest(path, sha(path), manifest)
    counts = {}
    for name in ('qualification.json', 'holdouts.json'):
        doc = json.loads((CACHE / name).read_text())
        assert doc['binary_hashes'] == manifest['binary_hashes'] and doc['manifest_sha256'] == sha(path)
        keys = set()
        for row in doc['checks']:
            key = tuple(row[k] for k in ('case', 'size', 'iterations', 'seed', 'arm'))
            assert key not in keys
            keys.add(key)
            assert row['checksum'] == checksum(*key[:4]) == row['expected_checksum']
            assert row['exit_status'] == 0 and row['clock_protocol_validated']
        counts[name] = len(keys)
    assert counts == {'qualification.json': 720, 'holdouts.json': 516}
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(), rows=rows,
                  checks=counts, manifest_sha256=sha(path), saved_receipt_sha256=sha(CACHE / 'executable-equivalence.json'),
                  script_sha256=sha(__file__), elf_helper_sha256=sha(module.__file__),
                  limitations=['Saved outcomes and read-only ELF parsing; no fresh timing.',
                               'LLVM images equal the measured 5e candidate; QBE images equal G4.',
                               'This candidate does not yet include the integrated index optimization.',
                               'Evidence supports adoption, not integrated goal confirmation.'])
    with Path(sys.argv[1]).open('x') as output:
        output.write(json.dumps(result, indent=2) + '\n')
    print('PASS eight exact runtime images and 1236 saved qualification/holdout outcomes')


if __name__ == '__main__':
    main()
