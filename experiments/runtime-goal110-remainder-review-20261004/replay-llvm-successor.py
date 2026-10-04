#!/usr/bin/env python3
"""Independently replay saved native outcomes for the corrected LLVM policy."""
import hashlib
import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REVIEW = ROOT.parent / 'goal110-nonnegative-rem-20261004/.mylang-cache/goal110-nonnegative-rem-review'
SOURCE = '27de73d302d23a9efaf811d541f1cb723323c434'
LOG = REVIEW / 'unit-llvm-repaired-final.log'
LOG_HASH = '44ffefc93608f715c218a9d6bb759340e6c3174d3373d463a0f2b80490cec412'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    prior = Path(__file__).with_name('replay-native.py')
    spec = importlib.util.spec_from_file_location('prior_oracle', prior)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert digest(LOG) == LOG_HASH
    receipt = json.loads((REVIEW / 'llvm-corrected-source-review.json').read_text())
    assert receipt['source_revision'] == SOURCE
    for path, expected in receipt['file_sha256'].items():
        assert digest(Path(path)) == expected, path
    rows = []
    for line in LOG.read_text().splitlines():
        prefix = 'NONNEGATIVE-REMAINDER-OUTCOME '
        if prefix not in line:
            continue
        row = json.loads(line.split(prefix, 1)[1])
        assert row['ordinary'] == row['fast']
        case = dict(row['input'])
        if case['kind'] == 'llvm_scalar_policy_qbe_execution':
            case['kind'] = 'endpoint'
        value, stdout, trap = module.oracle(case)
        actual = row['fast']
        assert actual['stdout'] == stdout and actual['trap']['code'] == trap
        assert actual['failed'] == bool(trap)
        if trap:
            assert actual['status'] != 0
        else:
            assert actual['value'] == value and actual['status'] == value % 256
            assert actual['stderr'] == ''
        rows.append(row)
    assert len(rows) == 41
    llvm_pairs = sum(row['input']['kind'] == 'llvm_scalar_policy_qbe_execution' for row in rows)
    assert llvm_pairs == 9
    output = ROOT / 'benchmarks/runtime/candidates/goal110-remainder-27de73d3-20261004-native-review.json'
    assert not output.exists()
    result = dict(
        status='passed', source_revision=SOURCE,
        reviewed_utc=datetime.now(timezone.utc).isoformat(),
        exact_native_pairs=41, qbe_policy_qbe_execution_pairs=32,
        llvm_policy_qbe_execution_pairs=llvm_pairs,
        successful_pairs=sum(not row['fast']['failed'] for row in rows),
        failure_pairs=sum(row['fast']['failed'] for row in rows),
        log=str(LOG), log_sha256=digest(LOG),
        oracle_script_sha256=digest(prior), script_sha256=digest(Path(__file__)),
        source_receipt_sha256=digest(REVIEW / 'llvm-corrected-source-review.json'),
        limits=[
            'Saved complete native outcome replay; no new guest execution.',
            'The nine LLVM-policy pairs execute through QBE, not actual LLVM machine code.',
            'Trap code and prior output are independently expected; full trap provenance and streams match the accounted control.',
            'Official successor LLVM qualification remains separate.'
        ])
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
