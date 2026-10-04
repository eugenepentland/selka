#!/usr/bin/env python3
"""Replay actual LLVM boundary and full-width biased-remainder evidence."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-bounded-rem-20261004'
CACHE = TREE / '.mylang-cache/goal110-bounded-rem-debug'
spec = importlib.util.spec_from_file_location('previous_review', Path(__file__).with_name('review-actual-llvm.py'))
previous = importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    counts = dict(base_success=0, base_failure=0, wide_bias=0, exact_magnitude=0)
    reports = {}
    for name in ('actual-llvm-semantics.json', 'actual-llvm-width.json'):
        path = CACHE / name
        data = json.loads(path.read_text())
        assert data['status'] == 'complete'
        assert data['source_revision'] == '5e97db47f08f667d97419abafd098df263a2aec3'
        assert sha(data['manifest']) == data['manifest_sha256']
        manifest = json.loads(Path(data['manifest']).read_text())
        assert manifest['identity'] == data['manifest_identity']
        for source, digest in data['source_and_helper_sha256'].items():
            assert sha(source) == digest
        groups = {'base': data} if 'outcomes' in data else data['variants']
        if 'variants' in data:
            assert data['magnitude'] == 15 * (1 << 59)
            assert data['wide_divisor'] == 4700000000000000000
            assert data['wide_bias'] == 9400000000000000000
        for kind, group in groups.items():
            if kind != 'base':
                assert sha(group['source']) == group['source_sha256']
            for build in group['builds'].values():
                assert build['exit_status'] == 0
                assert sha(build['binary']) == build['binary_sha256']
                assert sha(build['backend_manifest']) == build['backend_manifest_sha256']
                meta = json.loads(Path(build['backend_manifest']).read_text())
                assert meta['backend'] == 'llvm' and str(meta['optimization']) == '3'
                assert meta['lto'] and not meta['thin_lto']
            for row in group['outcomes']:
                case = row['input']
                actual = row['unaccounted']['run']
                assert actual == row['accounted']['run']
                if kind == 'base':
                    value, code = previous.expected(case)
                elif kind == 'wide_bias':
                    value, code = case['seed'] % 4700000000000000000, ''
                else:
                    assert kind == 'exact_magnitude'
                    assert case['dividend'] == case['seed'] * 15
                    assert abs(case['dividend']) == data['magnitude']
                    value, code = 32 + 2 * (case['dividend'] % 1009), ''
                assert actual['stdout'] == '17\n' and actual['failed'] == bool(code)
                assert actual['trap']['code'] == code
                if code:
                    assert actual['status'] == 1 and actual['raw_stdout'] == '17\n'
                    assert len(actual['trap']['frames']) == 2
                else:
                    assert actual['value'] == value and actual['status'] == value % 256
                    assert actual['raw_stdout'] == f'17\n{value}\n' and actual['stderr'] == ''
                for arm in ('accounted', 'unaccounted'):
                    assert row[arm]['argv'][3:] == [group['builds'][arm]['binary'], *[str(case[k]) for k in ('count', 'seed', 'offset')]]
                    assert row[arm]['environment_overrides']['MYLANG_MEMORY_LIMIT'] == str(case.get('memory_limit', 134217728))
                counts[('base_failure' if code else 'base_success') if kind == 'base' else kind] += 1
        reports[name] = sha(path)
    assert counts == dict(base_success=8, base_failure=4, wide_bias=4, exact_magnitude=2)
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  actual_llvm_pairs=18, executions=36, counts=counts, reports=reports,
                  script_sha256=sha(__file__), reused_oracle_sha256=sha(Path(__file__).with_name('review-actual-llvm.py')),
                  limitations=['Saved exact process replay; no new executions or timing.',
                               'ReleaseFast LLVM-O3/fullLTO guests built by a pinned Debug host.',
                               'Memory-refusal oracle is specific to the recorded one-MiB fixture.'])
    with Path(sys.argv[1]).open('x') as target:
        target.write(json.dumps(result, indent=2) + '\n')
    print('PASS 18 actual LLVM pairs, including unsigned high-bit bias and both exact magnitude endpoints')


if __name__ == '__main__':
    main()
