#!/usr/bin/env python3
"""Replay archived bounded-equality streams and bindings without timing work."""
import gzip
import hashlib
import json
import statistics
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent / 'goal110-equality-bounded-20261004'
ARCHIVE = WORK / 'experiments/runtime-goal110-equality-bounded-20261004'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    evidence_path = ARCHIVE / 'native-screen-evidence.json'
    evidence = json.loads(evidence_path.read_text())
    for binding in evidence['raw_bindings']:
        compressed = (ARCHIVE / binding['archive']).read_bytes()
        raw = gzip.decompress(compressed)
        assert sha(compressed) == binding['gzip_sha256']
        assert sha(raw) == binding['raw_sha256']
        assert len(compressed) == binding['gzip_bytes'] and len(raw) == binding['raw_bytes']
        assert Path(binding['source_path']).read_bytes() == raw
    for name, expected in evidence['bound_inputs'].items():
        assert sha((ARCHIVE / name).read_bytes()) == expected, name
    native = json.loads((ARCHIVE / 'native-checks-receipt.json').read_text())
    assert native['status'] == 'passed' and native['exit_status'] == 0
    for name, expected in native['files'].items():
        assert sha((WORK / name).read_bytes()) == expected, name
    assert sha((ARCHIVE / 'native-checks.log').read_bytes()) == native['log_sha256']
    raw = json.loads(gzip.decompress((ARCHIVE / 'native-distributions.json.gz').read_bytes()))
    analysis = json.loads(gzip.decompress((ARCHIVE / 'native-analysis.json.gz').read_bytes()))
    assert raw['status'] == 'complete' and raw['rounds'] == 5 and raw['warmups'] == 1
    assert raw['source_revision'] == evidence['source_pin']
    assert raw['session_id'] == analysis['session_id'] == evidence['native_session_id']
    assert raw['binary_hashes_before'] == raw['binary_hashes_after']
    for arm, name in raw['binaries'].items():
        assert sha(Path(name).read_bytes()) == raw['binary_hashes_before'][arm]
    counts = Counter()
    rows, elapsed = [], []
    for row in raw['rows']:
        identity = (row['length'], row['distribution'], row['views'], row['unicode'])
        rows.append(identity)
        assert [s['round'] for s in row['samples']] == list(range(-1, 5))
        for sample in row['pilots'] + row['samples']:
            count = sample.get('iterations', row['iterations'])
            stage = 'pilots' if 'iterations' in sample else 'warmups' if sample['round'] < 0 else 'measured'
            if stage != 'pilots':
                assert len(sample['arm_order']) == 2 and set(sample['arm_order']) == {'before', 'after'}
            assert set(sample['results']) == {'before', 'after'}
            for arm, result in sample['results'].items():
                expected = count if row['distribution'] == 'equal' else 0
                assert result['exit_status'] == 0 and result['stderr'] == ''
                assert result['checksum'] == result['expected_checksum'] == expected
                assert result['stdout'] == f"{expected} {result['elapsed_ns']}\n"
                assert result['elapsed_ns'] > 0 and result['ns_per_call'] == result['elapsed_ns'] / count
                mode = ('equal', 'first', 'middle', 'last').index(row['distribution'])
                assert result['command'] == ['taskset', '-c', '2', raw['binaries'][arm],
                    str(row['length']), str(mode), str(int(row['views'])), str(int(row['unicode'])), str(count)]
                counts[stage] += 1
                if stage == 'measured':
                    elapsed.append(result['elapsed_ns'])
        medians = {arm: statistics.median(s['results'][arm]['ns_per_call'] for s in row['samples'] if s['round'] >= 0)
                   for arm in ('before', 'after')}
        assert medians == row['medians_ns_per_call']
        assert row['after_before_ratio'] == medians['after'] / medians['before']
    expected_rows = {(n, m, v, u) for n in (17, 32, 33, 64)
                     for m in ('equal', 'first', 'middle', 'last') for v in (False, True) for u in (False, True)}
    expected_rows |= {(n, m, v, u) for n in (65, 128, 256, 4096)
                      for m in ('equal', 'middle') for v, u in ((False, False), (True, True))}
    assert len(rows) == 80 and set(rows) == expected_rows
    assert counts == {'pilots': 322, 'warmups': 160, 'measured': 800}
    assert counts == analysis['checks']
    result = dict(status='passed', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  source_revision=raw['source_revision'], session_id=raw['session_id'],
                  verified_processes=dict(counts), raw_archive_bindings=len(evidence['raw_bindings']),
                  helper_bindings=len(evidence['bound_inputs']), native_source_bindings=len(native['files']),
                  below_30ms_samples=sum(t < 30000000 for t in elapsed), minimum_sample_ns=min(elapsed),
                  evidence_sha256=sha(evidence_path.read_bytes()), script_sha256=sha(Path(__file__).read_bytes()),
                  limitations=['Standalone helper evidence, not generated guests or goal acceptance.',
                               'Saved stream and median replay; no fresh execution and no independent interval recalculation.',
                               'The 128-byte control regression still needs an independent repeat.'])
    output = ROOT / 'benchmarks/runtime/candidates/goal110-bounded-3dcbe723-20261004-native-review.json'
    assert not output.exists()
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
