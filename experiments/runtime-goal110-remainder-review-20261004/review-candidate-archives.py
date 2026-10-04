#!/usr/bin/env python3
"""Check copied candidate archives and independently replay matched observations."""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
from registry import checksum


def digest(data):
    return hashlib.sha256(data).hexdigest()


def saved(path):
    return json.loads(gzip.decompress(path.read_bytes()))


def text_bindings(directory):
    count, metadata = 0, 0
    for name in ('evidence.json', 'repeat-evidence.json'):
        doc = json.loads((directory / name).read_text())
        assert doc['source_revision'] == '3dcbe723da4036fb7d69046e77e9f8cd16d7512f'
        for item in doc['raw_bindings']:
            packed = (directory / item['archive']).read_bytes()
            raw = gzip.decompress(packed)
            assert digest(packed) == item['gzip_sha256']
            assert len(packed) == item['gzip_bytes']
            assert digest(raw) == item['raw_sha256'] and len(raw) == item['raw_bytes']
            assert Path(item['source_path']).read_bytes() == raw
            count += 1
        bindings = doc.get('script_bindings', {})
        bindings.update({item['path']: item['sha256'] for item in doc.get('metadata_bindings', [])})
        for path, expected in bindings.items():
            assert digest((directory / path).read_bytes()) == expected
            metadata += 1
    return {'raw_bindings': count, 'metadata_bindings_including_repeats': metadata}


def remainder_bindings(directory):
    doc = json.loads((directory / 'archive-index.json').read_text())
    assert doc['source_revision'] == '27de73d302d23a9efaf811d541f1cb723323c434'
    assert doc['status'] == 'unintegrated_negative_input_cost_blocker'
    for path, item in doc['archives'].items():
        packed = (directory / path).read_bytes()
        raw = gzip.decompress(packed)
        assert digest(packed) == item['archive_sha256']
        assert digest(raw) == item['uncompressed_sha256'] and len(raw) == item['uncompressed_bytes']
        assert Path(item['origin']).read_bytes() == raw
    return {'raw_bindings': len(doc['archives'])}


def supplement_checksum(plan):
    # Sum complete residue cycles and the remaining arithmetic progression.
    # This is independent of the agent's batch-by-batch period oracle.
    d = 1009
    cycles, remainder = divmod(plan['iterations'], d)
    total = 0
    for index in range(plan['size']):
        start = (plan['seed'] + 13 * index) % d
        tail = remainder * start + remainder * (remainder - 1) // 2
        tail -= d * max(0, start + remainder - d)
        total += (index + 1) * (cycles * d * (d - 1) // 2 + tail)
    return total % 1000000007


def paired(path, supplementary=False):
    doc = saved(path)
    assert doc['status'] == 'complete'
    rounds, warmups = doc['rounds'], doc['warmups']
    arms = ('before-llvm', 'after-llvm', 'before-qbe', 'after-qbe')
    results, count, seen = [], 0, set()
    for row in doc['rows']:
        plan = row['plan']
        key = (plan['case'], plan['profile'], plan['seed'])
        assert key not in seen
        seen.add(key)
        expected = (supplement_checksum(plan) if supplementary else
                    checksum(plan['case'], plan['size'], plan['iterations'], plan['seed']))
        assert expected == plan['expected']
        samples = {(sample['round'], sample['arm']): sample for sample in row['samples']}
        assert len(samples) == len(row['samples'])
        assert set(samples) == {(index, arm) for index in range(-warmups, rounds) for arm in arms}
        for sample in samples.values():
            assert sample['checksum'] == expected and sample['exit_status'] == 0
            assert sample['kernel_ns'] > 0 and sample['process_wall_ns'] > 0
            count += 1
        medians = {arm: statistics.median(samples[index, arm]['kernel_ns'] / plan['iterations']
                                         for index in range(rounds)) for arm in arms}
        assert medians == row['medians_ns_per_op']
        ratios = {backend: medians['after-' + backend] / medians['before-' + backend]
                  for backend in ('llvm', 'qbe')}
        assert ratios == row['after_before_ratios']
        results.append({'case': key[0], 'profile': key[1], 'seed': key[2], 'after_before': ratios})
    if 'binaries' in doc:
        for arm, binary in doc['binaries'].items():
            assert digest(Path(binary).read_bytes()) == doc['binary_hashes_before_after'][arm]
    if supplementary:
        build_path = Path(doc['build_receipt'])
        assert digest(build_path.read_bytes()) == doc['build_receipt_sha256']
        build = json.loads(build_path.read_text())
        for arm, item in build['builds'].items():
            assert digest(Path(item['binary']).read_bytes()) == doc['binary_hashes'][arm]
        assert len(seen) == 4
    return {'raw_sha256': digest(gzip.decompress(path.read_bytes())),
            'session_id': doc['session_id'], 'checked_outcomes': count, 'rows': results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    text = ROOT / 'experiments/runtime-goal110-equality-bounded-20261004'
    remainder = ROOT / 'experiments/runtime-goal110-nonnegative-rem-20261004'
    report = {'status': 'pass', 'reviewed_utc': datetime.now(timezone.utc).isoformat(),
              'integrated_source_unchanged': '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2',
              'text_archive': text_bindings(text), 'remainder_archive': remainder_bindings(remainder),
              'text_initial': paired(text / 'bounded-g4-before-after.json.gz'),
              'text_repeat': paired(text / 'bounded-g4-repeat.json.gz'),
              'remainder_frozen': paired(remainder / 'raw/paired.json.gz'),
              'remainder_signed': paired(remainder / 'raw/supplement-timing.json.gz', True),
              'limitations': ['Exploratory candidate evidence; neither candidate is integrated.',
                              'This replay independently checks oracles, medians and live guest bytes; it does not independently recompute confidence intervals.',
                              'Most timing reports retain parsed process outcomes, not complete raw process streams.',
                              'This archive review does not change goal confirmations.'],
              'script_sha256': digest(Path(__file__).read_bytes())}
    assert [report[key]['checked_outcomes'] for key in ('text_initial', 'text_repeat', 'remainder_frozen', 'remainder_signed')] == [288, 144, 192, 96]
    with args.output.open('x') as target:
        target.write(json.dumps(report, indent=2) + '\n')
    print('PASS 140 raw bindings; 22 metadata bindings including repeats; 720 independently replayed paired outcomes')


if __name__ == '__main__':
    main()
