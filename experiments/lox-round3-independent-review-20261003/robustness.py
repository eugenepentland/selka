#!/usr/bin/env python3
"""Read complete frozen walls; sensitivity diagnostics are not confidence intervals."""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path
import statistics
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent.parent / 'lox-next-measurement-independent-review-20261003'))
import audit


def gm(values):
    return math.exp(math.fsum(math.log(v) for v in values) / len(values))


def reduction(values):
    return 100 * (1 - gm(values))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    assert not args.out.exists()
    work = args.root.resolve() / '.tmp-lox-round3/measurements'
    doc = audit.load(work / 'source-timing.json')
    assert doc['verified_after'] and doc['phase'] == 'time' and doc['rounds'] == 3
    assert len(doc['samples']) == 780
    recorded = audit.load(work / 'source-wall-analysis.json')
    arithmetic = audit.analysis(work / 'source-wall-analysis.json', doc)
    assert len(arithmetic['comparisons']) == 18 and recorded['receipt_sha256'] == audit.sha(work / 'source-timing.json')
    result = {}
    for name, comparison in recorded['comparisons'].items():
        if '-over-baseline-' not in name:
            continue
        result[name] = {}
        for engine in ['vm', 'tree']:
            rows = {case: row for case, row in comparison['rows'].items() if case.startswith(engine + '/')}
            assert len(rows) == 13
            values = list(rows.values())
            rounds = [reduction([r['paired_ratios'][i] for r in values]) for i in range(3)]
            round_wins = [sum(r['paired_ratios'][i] < 1 for r in values) for i in range(3)]
            omit_round = [reduction([statistics.median([r['paired_ratios'][i] for i in range(3) if i != omit])
                                     for r in values]) for omit in range(3)]
            omit_case = [reduction([r['candidate_over_baseline'] for i, r in enumerate(values) if i != omit])
                         for omit in range(13)]
            result[name][engine] = {'reported_case_median_gm_reduction_pct': comparison['engines'][engine]['reduction_pct'],
                                   'cases_faster': sum(r['candidate_over_baseline'] < 1 for r in values),
                                   'cases_equal': sum(r['candidate_over_baseline'] == 1 for r in values),
                                   'cases_slower': sum(r['candidate_over_baseline'] > 1 for r in values),
                                   'median_per_case_paired_spread_pct': statistics.median(r['spread_pct'] for r in values),
                                   'maximum_per_case_paired_spread_pct': max(r['spread_pct'] for r in values),
                                   'per_round_all13_gm_reduction_pct': rounds, 'per_round_cases_faster': round_wins,
                                   'leave_one_round_out_case_median_gm_reduction_pct': omit_round,
                                   'leave_one_case_out_case_median_gm_reduction_pct_range': [min(omit_case), max(omit_case)],
                                   'slower_case_exceptions': {case: {'reduction_pct': r['reduction_pct'], 'paired_spread_pct': r['spread_pct']}
                                                             for case, r in rows.items() if r['candidate_over_baseline'] > 1}}
    for path, digest in list(audit.READS.items()):
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
    receipt = {'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'scope': 'independent arithmetic and descriptive sensitivity of complete780 walls; no new runs or statistical significance claim',
               'wall_sha256': audit.sha(work / 'source-timing.json'), 'analysis_sha256': audit.sha(work / 'source-wall-analysis.json'),
               'all18_comparisons_arithmetic_verified': True, 'baseline_comparison_diagnostics': result,
               'limits': ['Reported values are GM of case medians of paired ratios, not medians of round GMs.',
                          'A two-round median uses the arithmetic mean of its two paired ratios; omission diagnostics therefore have a different estimator from three-round medians.',
                          'Omission ranges are descriptive robustness checks, not confidence intervals, p-values or independent replication.',
                          'Instruction-flat AST VM wall movement and broad VM spreads warn against attributing every wall delta to a source mechanism.',
                          'Full counter results and semantic reviews remain separate acceptance evidence.'],
               'guest_test_or_perf_executions': 0, 'root_mutations': 0}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'out': str(args.out), 'sha256': hashlib.sha256(args.out.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
