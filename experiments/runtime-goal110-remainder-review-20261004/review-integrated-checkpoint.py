#!/usr/bin/env python3
"""Replay combined-source checks and report, rather than assume, code identity."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-integrated-20261004'
CACHE = TREE / '.mylang-cache/goal110-integrated-debug'


def imported(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


elf = imported('elf_review', ROOT / 'experiments/runtime-goal110-index-review-20261004/review-controls.py').elf
oracle = imported('bounded_oracle', Path(__file__).with_name('review-bounded-llvm-source.py')).expected
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
from registry import checksum
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    source = '1a3980631e79bc65f048acd063d7250800f01901'
    focused_path = TREE / '.mylang-cache/goal110-integrated-review/focused-checkpoint.json'
    focused = json.loads(focused_path.read_text())
    assert focused['source_revision'] == source
    batches, pairs = {}, 0
    for row in focused['batches']:
        assert row['actual_outer_exit_status'] == 0
        path = Path(row['log_path'])
        assert sha(path) == row['log_sha256']
        log = path.read_text()
        result, = re.findall(r'guardian/test: RESULT (\{[^\n]+\})', log)
        assert json.loads(result) == row['guardian_result']
        assert row['guardian_result']['failed'] == row['guardian_result']['skipped'] == 0
        batches[row['batch']] = row['guardian_result']['passed']
        for line in log.splitlines():
            tag = line.split(' ', 1)[0]
            if tag not in ('APPEND-RANGE-OUTCOME', 'BOUNDED-REMAINDER-OUTCOME'):
                continue
            record = json.loads(line.split(' ', 1)[1])
            actual = record['ordinary']
            assert actual == record['fast']
            value, code = oracle(record)
            assert actual['failed'] == bool(code) and actual['trap']['code'] == code
            if code:
                assert actual['status'] == 1 and actual['trap']['frames']
            else:
                assert actual['value'] == value and actual['status'] == value % 256 and actual['stderr'] == ''
            expected_stdout = '' if tag == 'APPEND-RANGE-OUTCOME' or record.get('kind', '').endswith('by_QBE_GC') else '17\n'
            assert actual['stdout'] == expected_stdout
            pairs += 1
    assert batches == {'remainder': 58, 'index-proof': 22, 'index-native-a': 15, 'index-native-b': 17}
    assert pairs == 49
    path = CACHE / 'runner/manifest.json'
    manifest = json.loads(path.read_text())
    assert manifest['identity']['source_revision'] == source
    holdouts.check_manifest(path, sha(path), manifest)
    counts = {}
    for name in ('qualification.json', 'holdouts.json'):
        doc = json.loads((CACHE / name).read_text())
        assert doc['manifest_sha256'] == sha(path) and doc['binary_hashes'] == manifest['binary_hashes']
        keys = set()
        for row in doc['checks']:
            key = tuple(row[k] for k in ('case', 'size', 'iterations', 'seed', 'arm'))
            assert key not in keys
            keys.add(key)
            assert row['checksum'] == checksum(*key[:4]) == row['expected_checksum']
            assert row['exit_status'] == 0 and row['clock_protocol_validated']
        counts[name] = len(keys)
    assert counts == {'qualification.json': 720, 'holdouts.json': 516}
    comparison_path = CACHE / 'image-comparison.json'
    comparison = json.loads(comparison_path.read_text())
    rows, seen = [], set()
    for row in comparison['rows']:
        key = row['group'], row['backend']
        assert key not in seen
        seen.add(key)
        paths = [Path(row[side + '_path']) for side in ('before', 'after')]
        assert all(sha(path) == row[side + '_sha256'] for side, path in zip(('before', 'after'), paths))
        before, after = map(elf, paths)
        names = sorted(name for name in set(before[2]) | set(after[2]) if before[2].get(name) != after[2].get(name))
        assert names == [section['name'] for section in row['changed_allocated_sections']]
        equal = before[1][4] == after[1][4] and not names and before[3] == after[3]
        if equal:
            for segment in before[3]:
                if segment[0] != 1:
                    continue
                offset, size = segment[2], segment[5]
                left, right = [value[0][offset:offset + size] for value in (before, after)]
                changes = [offset + i for i, pair in enumerate(zip(left, right)) if pair[0] != pair[1]]
                equal = equal and len(left) == len(right) == size and set(changes) <= set(range(40, 48))
                equal = equal and (not changes or (offset == 0 and not segment[1] & 1))
        assert equal == row['runtime_image_equal']
        rows.append(dict(group=key[0], backend=key[1], runtime_image_equal=equal, changed_sections=names))
    assert seen == {(group, backend) for group in ('legacy', 'compute', 'collections', 'text') for backend in ('llvm', 'qbe')}
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(), source_revision=source,
                  focused_batches=batches, saved_native_pairs=pairs, checks=counts, images=rows,
                  manifest_sha256=sha(path), focused_receipt_sha256=sha(focused_path),
                  comparison_sha256=sha(comparison_path), script_sha256=sha(__file__),
                  limitations=['Replay of saved outcomes and static images; no new executions or timing.',
                               'Focused outer statuses are explicitly recorded by the executing agent; misleading Zig failed-command log wording retained.',
                               'Five images match controls; LLVM compute, legacy and collections differ and require investigation/timing.',
                               'Integrated performance remains provisional; no goal confirmation.'])
    # The loop above uses a local path name while checking image bindings.
    result['manifest_sha256'] = sha(CACHE / 'runner/manifest.json')
    with Path(sys.argv[1]).open('x') as output:
        output.write(json.dumps(result, indent=2) + '\n')
    print('PASS four focused batches/49 native pairs, 1236 oracles and eight image comparisons (five equal)')


if __name__ == '__main__':
    main()
