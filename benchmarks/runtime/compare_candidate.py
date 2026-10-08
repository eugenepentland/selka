#!/usr/bin/env python3
"""Compare a full or focused candidate to immutable targets and concurrent references."""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import random
import statistics
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / 'expanded'))
from registry import inventory
from verify import ARMS, verify

TARGETS = HERE / 'audit/evidence.json'
TARGETS_SHA256 = 'ea2435d983d4015e4a0fd40133e689388ccbcead24c2a91188a07db1d6bad0fa'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def bootstrap(values, references, seed, resamples=2000):
    require(bool(values) and len(values) == len(references), 'missing paired rounds')
    rng = random.Random(seed)
    estimates = []
    for _ in range(resamples):
        indexes = [rng.randrange(len(values)) for _ in values]
        estimates.append(statistics.median([values[index] for index in indexes]) /
                         statistics.median([references[index] for index in indexes]))
    estimates.sort()
    return [estimates[int(resamples * .025) - 1], estimates[int(resamples * .975) - 1]]


def target_rows(path=TARGETS):
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == TARGETS_SHA256, 'immutable target evidence SHA256 mismatch')
    document = json.loads(raw)
    rows = {(r['case'], r['size']): r for r in document['measurements']}
    wanted = {(case, size) for case, meta in inventory().items() for size in meta['sizes']}
    require(len(document['measurements']) == 80 and set(rows) == wanted, 'missing or duplicate frozen targets')
    for (case, size), row in rows.items():
        require(row['unit'] == inventory()[case]['unit'] and row['level'] == inventory()[case]['level'], 'frozen target unit drift')
        require(row['reference_arm'] in ARMS and math.isfinite(row['target_ns_per_iteration'])
                and row['target_ns_per_iteration'] > 0, 'invalid frozen target')
    return rows, document['baseline_sha256']


def build_comparison(report, targets, baseline_hash):
    """Only candidate-report rounds are paired. Archived timing samples are never read."""
    require(report['schema'] == 'mylang-runtime-expanded-v2', 'candidate requires recorded v2 identity')
    frozen = report['frozen_reference']
    require(frozen['baseline_sha256'] == baseline_hash, 'wrong frozen reference baseline')
    plans = {(r['case'], r['size']): r for r in report['plans']}
    references = {(r['case'], r['size']): r for r in frozen['plans']}
    require(set(references) == set(plans) and len(references) == len(frozen['plans']), 'reference plan coverage mismatch')
    raw = {}
    supplemental = {}
    for source, output in ((report['samples'], raw), (report['frozen_reference_samples'], supplemental)):
        for row in source:
            key = (row['case'], row['size'], row['arm'])
            rounds = output.setdefault(key, {})
            require(row['round'] not in rounds, 'duplicate paired round')
            rounds[row['round']] = row['kernel_ns']
    comparisons, dashboard = [], []
    for key, plan in plans.items():
        target, reference = targets[key], references[key]
        require(plan['unit'] == target['unit'] and plan['level'] == target['level'], 'candidate/target units differ')
        require(reference['arm'] == target['reference_arm'] and
                reference['target_ns_per_iteration'] == target['target_ns_per_iteration'], 'frozen reference differs from target')
        ref_key = (*key, reference['arm'])
        archive_hash = frozen['original_identity']['binary_paths'][reference['name']]
        require(reference['binary_path'] == archive_hash, 'reference path differs from original receipt')
        supplement = report['binary_hashes'][reference['name']] != reference['binary_sha256']
        selected = supplemental if supplement else raw
        require(set(selected.get(ref_key, {})) == set(range(report['rounds'])), 'missing concurrent frozen-reference rounds')
        ref_values = [selected[ref_key][rnd] for rnd in range(report['rounds'])]
        medians = {}
        for arm in ARMS:
            require(set(raw.get((*key, arm), {})) == set(range(report['rounds'])), 'missing current rounds')
            medians[arm] = statistics.median(raw[(*key, arm)].values()) / plan['iterations']
        minimum = min(medians.values())
        winners = [arm for arm in ARMS if medians[arm] == minimum]
        for arm in ARMS:
            dashboard.append({'case': key[0], 'size': key[1], 'profile': plan['profile'], 'unit': plan['unit'],
                              'arm': arm, 'median_ns_per_iteration': medians[arm], 'current_fastest_arms': winners,
                              'ratio_to_current_fastest': medians[arm] / minimum})
        for arm in ('my-llvm', 'my-qbe'):
            values = [raw[(*key, arm)][rnd] for rnd in range(report['rounds'])]
            ns = medians[arm]
            fixed = ns / target['target_ns_per_iteration']
            paired = ns / (statistics.median(ref_values) / plan['iterations'])
            interval = bootstrap(values, ref_values, f'{key}/{arm}/frozen-reference/bootstrap')
            numerical = 'at_or_below' if fixed <= 1 else 'near_target' if fixed <= 1.05 else 'open'
            concurrent = 'faster_in_this_session' if interval[1] < 1 else 'slower_in_this_session' if interval[0] > 1 else 'inconclusive'
            same_binary = report['binary_hashes'][plan['group'] + '/' + arm] == reference['binary_sha256']
            if same_binary:
                concurrent = 'identical_reference_binary'
            comparisons.append({'case': key[0], 'size': key[1], 'profile': plan['profile'], 'level': plan['level'],
                                'unit': plan['unit'], 'arm': arm, 'iterations': plan['iterations'],
                                'median_ns_per_iteration': ns, 'frozen_target_ns_per_iteration': target['target_ns_per_iteration'],
                                'ratio_to_frozen_target': fixed, 'numerical_target_status': numerical,
                                'frozen_reference_arm': reference['arm'], 'supplemental_reference': supplement,
                                'concurrent_reference_median_ns_per_iteration': statistics.median(ref_values) / plan['iterations'],
                                'ratio_to_concurrent_frozen_reference': paired,
                                'paired_bootstrap_95_interval': interval, 'concurrent_evidence': concurrent,
                                'current_fastest_arms': winners, 'ratio_to_current_fastest': ns / minimum,
                                'calibration': plan['calibration']})
    return {'schema': 'mylang-runtime-candidate-comparison-v1', 'status': 'complete' if len(plans) == 80 else 'focused',
            'candidate_identity': report['identity'], 'measurement_session_id': report['measurement_session_id'],
            'frozen_targets_sha256': TARGETS_SHA256, 'frozen_baseline_sha256': baseline_hash,
            'frozen_targets': list(targets.values()), 'comparisons': comparisons, 'current_dashboard': dashboard,
            'counts_by_arm': {arm: dict(Counter(row['numerical_target_status'] for row in comparisons if row['arm'] == arm))
                             for arm in ('my-llvm', 'my-qbe')},
            'limitations': ['Frozen-target ratios condition on historical medians and have no same-session implication by themselves.',
                            'Paired intervals resample the same round indices, then divide medians; archived rounds are never paired.',
                            'Overlapping intervals are inconclusive. Near target (within 5%) does not meet the numerical goal.',
                            'Faster in this exploratory session is not demonstrated faster: independent confirmation is required.',
                            'Winner selection, multiple comparisons and repeated tuning are not corrected by these intervals.',
                            'Calibration limits and host interference remain material, especially for tiny or eliminated kernels.']}


def markdown(result):
    lines = [f"Candidate **{result['candidate_identity']['candidate_id']}**: {result['status']} comparison.", '',
             f"Source `{result['candidate_identity']['source_revision']}`; session `{result['measurement_session_id']}`.", '',
             'All 80 frozen targets are retained in JSON. Each backend/case/size remains a separate target.', '',
             '| Case / size | Backend | ns/iteration | Frozen ratio | Same-session original reference | Paired 95% interval | Current winner | Status |',
             '|---|---|---:|---:|---:|---:|---|---|']
    for row in result['comparisons']:
        low, high = row['paired_bootstrap_95_interval']
        lines.append(f"| {row['case']} / {row['profile']} | {row['arm']} | {row['median_ns_per_iteration']:.4f} | "
                     f"{row['ratio_to_frozen_target']:.3f} | {row['ratio_to_concurrent_frozen_reference']:.3f} "
                     f"({row['frozen_reference_arm']}) | {low:.3f}–{high:.3f} | {', '.join(row['current_fastest_arms'])} | "
                     f"{row['numerical_target_status']}; {row['concurrent_evidence']} |")
    lines += ['', *result['limitations']]
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--check-artifacts', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    protected = [args.candidate.resolve(), TARGETS.resolve(), HERE / 'expanded/results/baseline_main_20261003.json']
    require(output not in protected and output.with_suffix('.md') not in protected, 'output must preserve evidence inputs')
    raw = args.candidate.read_bytes()
    report = json.loads(raw)
    verify(report, artifacts=args.check_artifacts, focused=True)
    targets, baseline_hash = target_rows()
    result = build_comparison(report, targets, baseline_hash)
    result['candidate_report_sha256'] = hashlib.sha256(raw).hexdigest()
    require(args.candidate.read_bytes() == raw, 'candidate input changed while comparing')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
    output.with_suffix('.md').write_text(markdown(result))
    print(f"PASS {result['status']}: {len(result['comparisons'])} candidate comparisons; 80 immutable targets")


if __name__ == '__main__':
    main()
