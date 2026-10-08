#!/usr/bin/env python3
"""Independent Python oracles for saved 073e450b native test outcomes."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent / 'goal110-nonnegative-rem-20261004'
LOG = WORK / '.mylang-cache/goal110-nonnegative-rem-review/unit-final-pinned.log'
LOW, HIGH = -(1 << 63), (1 << 63) - 1


def oracle(data):
    kind = data['kind']
    if kind == 'detached_scalar_after_reference':
        return sum((17 + i * 13) % 1009 for i in range(32)) + 18, '', ''
    count, seed = data['count'], data['seed']
    if kind == 'endpoint':
        if count <= 0:
            return 0, '', ''
        if data['max_memory'] is not None:
            return None, '', 'R_MEMORY_BUDGET'
        base = seed + data['offset']
        if not LOW <= base <= HIGH or not LOW <= base + (count - 1) * 13 <= HIGH:
            return None, '', 'R_OVERFLOW'
        return count + base % 1009 + (base + (count - 1) * 13) % 1009, '', ''
    if kind == 'counter_entry':
        base = seed + data['start'] * 13
        return count + base % 1009 + (base + (count - 1) * 13) % 1009, '', ''
    assert kind == 'divisor'
    divisor = data['divisor']
    if divisor == 0:
        return None, '17\n', 'R_DIVISION_BY_ZERO'
    def remainder(value):
        if not data['truncating']:
            return value % divisor
        magnitude = abs(value) // abs(divisor)
        quotient = -magnitude if (value < 0) != (divisor < 0) else magnitude
        return value - quotient * divisor
    return count + remainder(seed) + remainder(seed + (count - 1) * 13), '17\n23\n', ''


def main():
    outcomes = []
    for line in LOG.read_text().splitlines():
        prefix = 'NONNEGATIVE-REMAINDER-OUTCOME '
        if prefix not in line:
            continue
        row = json.loads(line.split(prefix, 1)[1])
        assert row['ordinary'] == row['fast']
        actual = row['fast']
        value, stdout, code = oracle(row['input'])
        assert actual['stdout'] == stdout and actual['trap']['code'] == code
        assert actual['failed'] == bool(code)
        if code:
            assert actual['status'] != 0
        else:
            assert actual['value'] == value and actual['status'] == value % 256
            assert actual['stderr'] == ''
        outcomes.append(row)
    assert len(outcomes) == 32
    output = ROOT / 'benchmarks/runtime/candidates/goal110-remainder-073e450b-20261004-native-review.json'
    assert not output.exists()
    result = dict(status='passed', source_revision='073e450bf4ceaf1295d930434d19c2ea0f21ef21',
                  reviewed_utc=datetime.now(timezone.utc).isoformat(), exact_native_pairs=32,
                  successful_pairs=sum(not row['fast']['failed'] for row in outcomes),
                  failure_pairs=sum(row['fast']['failed'] for row in outcomes),
                  log=str(LOG), log_sha256=hashlib.sha256(LOG.read_bytes()).hexdigest(),
                  script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  limit='Saved complete outcome replay; no new guest execution. Memory refusal oracle checks code while exact provenance/streams match the accounted control.')
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
