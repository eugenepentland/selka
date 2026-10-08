#!/usr/bin/env python3
"""Check saved actual-LLVM boundary outcomes independently of the test driver."""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent / 'goal110-nonnegative-rem-llvm-rf-20261004'
REPORT = WORK / '.mylang-cache/goal110-nonnegative-rem-llvm-rf/actual-llvm-semantics.json'
LOW, HIGH = -(1 << 63), (1 << 63) - 1


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def expected(case):
    count, first = case['count'], case['seed'] + case['offset']
    if count <= 0:
        return 0, ''
    if case.get('memory_limit') == 1048576:
        return None, 'R_MEMORY_BUDGET'
    last = first + (count - 1) * 13
    if not LOW <= first <= HIGH or not LOW <= last <= HIGH:
        return None, 'R_OVERFLOW'
    return count + first % 1009 + last % 1009, ''


def main():
    data = json.loads(REPORT.read_text())
    assert data['status'] == 'complete'
    assert data['source_revision'] == '27de73d302d23a9efaf811d541f1cb723323c434'
    assert digest(data['manifest']) == data['manifest_sha256']
    for path, wanted in data['source_and_helper_sha256'].items():
        assert digest(path) == wanted, path
    for build in data['builds'].values():
        assert build['exit_status'] == 0
        assert digest(build['binary']) == build['binary_sha256']
        assert digest(build['backend_manifest']) == build['backend_manifest_sha256']
        backend = json.loads(Path(build['backend_manifest']).read_text())
        assert backend['backend'] == 'llvm' and backend['lto'] and not backend['thin_lto']
        assert str(backend['optimization']) == '3'
    rows = data['outcomes']
    assert len(rows) == 9 and len({r['input']['name'] for r in rows}) == 9
    successes = failures = 0
    for row in rows:
        case = row['input']
        actual = row['unaccounted']['run']
        assert actual == row['accounted']['run']
        value, code = expected(case)
        assert actual['stdout'] == '17\n'
        assert actual['trap']['code'] == code and actual['failed'] == bool(code)
        if code:
            failures += 1
            assert actual['status'] == 1 and len(actual['trap']['frames']) == 2
            assert actual['raw_stdout'] == '17\n'
        else:
            successes += 1
            assert actual['value'] == value and actual['status'] == value % 256
            assert actual['raw_stdout'] == f'17\n{value}\n' and actual['stderr'] == ''
        for arm in ('accounted', 'unaccounted'):
            run = row[arm]
            assert run['argv'][3] == data['builds'][arm]['binary']
            assert run['argv'][4:] == [str(case[k]) for k in ('count', 'seed', 'offset')]
            assert run['environment_overrides']['MYLANG_MEMORY_LIMIT'] == str(case.get('memory_limit', 134217728))
    assert successes == 5 and failures == 4
    output = ROOT / 'benchmarks/runtime/candidates/goal110-remainder-27de73d3-20261004-actual-llvm-review.json'
    assert not output.exists()
    result = dict(status='passed', source_revision=data['source_revision'],
                  reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  actual_llvm_pairs=9, executions=18, successes=successes, failures=failures,
                  report=str(REPORT), report_sha256=digest(REPORT),
                  script_sha256=digest(Path(__file__)),
                  limits=['Saved full-process replay; no new executions.',
                          'Successful values, trap codes, prior output and statuses independently expected; full trap detail and frames match the accounted control.',
                          'Memory refusal expectation checks the explicit 1 MiB fixture, not a general allocation-budget model.'])
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
