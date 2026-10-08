#!/usr/bin/env python3
"""Independently replay the two arithmetic candidates' saved timing evidence."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
from compare_candidate import bootstrap
from registry import checksum

ARMS = ('before-llvm', 'before-qbe', 'after-llvm', 'after-qbe')
HASHES = {}


def sha(path):
    path = Path(path)
    if path not in HASHES:
        HASHES[path] = hashlib.sha256(path.read_bytes()).hexdigest()
    return HASHES[path]


def bound(paths):
    for path, digest in paths.items():
        assert sha(path) == digest


def endpoint(plan):
    """Sum each element's modular cycle plus a closed-form wrapping tail."""
    size, count, seed = (plan[k] for k in ('size', 'iterations', 'seed'))
    assert size in (64, 4096) and 1 <= count <= 100000
    assert seed in (-1048576, 42)
    maximum = seed + count - 1 + (size - 1) * 13
    assert maximum == plan['maximum_dividend']
    assert seed > 0 or maximum < 0
    cycles, tail = divmod(count, 1009)
    total = 0
    for j in range(size):
        first = (seed + j * 13) % 1009
        partial = tail * first + tail * (tail - 1) // 2
        partial -= 1009 * max(0, first + tail - 1009)
        total += (j + 1) * (cycles * 1009 * 1008 // 2 + partial)
    return total % 1000000007


def artifacts(doc, tree, supplement):
    if 'bindings' in doc:
        assert sha(tree / '.mylang-cache/goal110-floor-result-range-debug/artifact-bindings.json') == doc['bindings_sha256']
        assert sha(tree / 'experiments/runtime-goal110-floor-result-range-20261004/time-guests.py') == doc['script_sha256']
        assert sha(doc['screen']) == doc['screen_sha256']
        paths = {}
        for label, binding in doc['bindings']['arms'].items():
            assert sha(binding['manifest']) == binding['manifest_sha256']
            manifest = json.loads(Path(binding['manifest']).read_text())
            assert manifest['identity']['source_revision'] == binding['source_revision']
            for backend in ('llvm', 'qbe'):
                paths[label + '-' + backend] = manifest['identity']['binary_paths']['text/my-' + backend]
        expected = doc['binary_hashes']
    elif supplement:
        assert sha(doc['build_receipt']) == doc['build_receipt_sha256']
        build = json.loads(Path(doc['build_receipt']).read_text())
        paths = {arm: row['binary'] for arm, row in build['builds'].items()}
        expected = doc['binary_hashes']
        bound(doc['source_and_helper_sha256'])
    else:
        assert sha(doc['six_arm_screen']) == doc['six_arm_screen_sha256']
        for item in doc['manifests'].values():
            assert sha(item['path']) == item['sha256']
            assert json.loads(Path(item['path']).read_text())['identity'] == item['identity']
        bound(doc['helper_sha256'])
        bound(doc['backend_manifest_sha256'])
        paths, expected = doc['binaries'], doc['binary_hashes_before_after']
    assert set(paths) == set(ARMS)
    for arm, path in paths.items():
        assert sha(path) == expected[arm]
    return paths


def replay(path, tree, supplement=False):
    doc = json.loads(path.read_text())
    assert doc['status'] == 'complete' and doc['cpu'] == 2
    rounds, warmups = doc['rounds'], doc['warmups']
    assert (rounds, warmups) in ((5, 1), (15, 3))
    binaries = artifacts(doc, tree, supplement)
    results, seen, total = [], set(), 0
    for row in doc['rows']:
        plan = row['plan']
        key = plan['case'], plan['profile'], plan['seed']
        assert key not in seen
        seen.add(key)
        expected = endpoint(plan) if supplement else checksum(*[plan[k] for k in ('case', 'size', 'iterations', 'seed')])
        assert expected == plan['expected']
        samples = {(x['round'], x['arm']): x for x in row['samples']}
        assert len(samples) == len(row['samples'])
        assert set(samples) == {(r, arm) for r in range(-warmups, rounds) for arm in ARMS}
        for (_, arm), sample in samples.items():
            assert sample['checksum'] == expected and sample['exit_status'] == 0
            assert sample['kernel_ns'] > 0 and sample['process_wall_ns'] > 0
            if 'stdout' in sample:
                assert sample['status'] == 0 and sample['stderr'] == ''
                assert sample['stdout'] == f"{expected} {sample['kernel_ns']}\n"
                assert sample['command'] == ['taskset', '-c', '2', binaries[arm],
                                             plan['case'], *[str(plan[k]) for k in ('size', 'iterations', 'seed')]]
            total += 1
        values = {arm: [samples[r, arm]['kernel_ns'] / plan['iterations'] for r in range(rounds)] for arm in ARMS}
        medians = {arm: statistics.median(items) for arm, items in values.items()}
        assert medians == row['medians_ns_per_op']
        ratios, intervals = {}, {}
        for backend in ('llvm', 'qbe'):
            ratios[backend] = medians['after-' + backend] / medians['before-' + backend]
            assert ratios[backend] == row['after_before_ratios'][backend]
            seed = str((plan['size'], plan['seed'])) if supplement else '/'.join(key[:2])
            intervals[backend] = bootstrap(values['after-' + backend], values['before-' + backend], seed + '/' + backend)
            if 'paired_bootstrap_95' in row:
                assert intervals[backend] == row['paired_bootstrap_95'][backend]
        results.append(dict(case=key[0], profile=key[1], seed=key[2], ratios=ratios, paired_95=intervals))
    return dict(session=doc['session_id'], raw_path=str(path), raw_sha256=sha(path),
                rounds=rounds, warmups=warmups, outcomes=total, rows=results)


def main():
    text_tree = ROOT.parent / 'goal110-floor-result-range-20261004'
    bias_tree = ROOT.parent / 'goal110-bounded-rem-20261004'
    text_cache = text_tree / '.mylang-cache/goal110-floor-result-range-debug'
    bias_cache = bias_tree / '.mylang-cache/goal110-bounded-rem-debug'
    sessions = dict(annotation_initial=replay(text_cache / 'annotation-g4-pair.json', text_tree),
                    annotation_repeat=replay(text_cache / 'annotation-g4-repeat.json', text_tree),
                    bias_initial=replay(bias_cache / 'paired.json', bias_tree),
                    bias_repeat=replay(bias_cache / 'paired-repeat.json', bias_tree),
                    bias_supplement=replay(bias_cache / 'supplement-timing.json', bias_tree, True))
    assert [s['outcomes'] for s in sessions.values()] == [288, 144, 192, 288, 96]
    assert len({s['session'] for s in sessions.values()}) == 5
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  sessions=sessions, outcomes=1008, live_file_bindings=len(HASHES),
                  script_sha256=sha(__file__), bootstrap_helper_sha256=sha(ROOT / 'benchmarks/runtime/compare_candidate.py'),
                  limitations=['Saved evidence replay; no new guest executions.',
                               'Recomputed intervals reuse the established bootstrap helper; they are per-comparison, not simultaneous.',
                               'Annotation preserves full process streams; bounded-bias timing preserves parsed checksums/status.',
                               'Candidate hosts are Debug, controls ReleaseFast; all guests use normal optimized backends.',
                               'These exploratory comparisons cannot close a goal target.'])
    with Path(sys.argv[1]).open('x') as target:
        target.write(json.dumps(result, indent=2) + '\n')
    print('PASS 1008 outcomes, five independent sessions, live artifacts, oracles, medians and paired intervals')


if __name__ == '__main__':
    main()
