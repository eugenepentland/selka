#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
results = []
for case in ['stm32n6', 'rds3+flat']:
    receipt = HERE.parent / 'followup-002' / ('eda-' + case + '-runtime.json')
    if not receipt.exists():
        results.append({'case': case, 'status': 'no complete receipt; inspect admission log and partial journal'})
        continue
    data = json.loads(receipt.read_text())
    by_arm = {a: {r['round']: r['value'] for r in data['wall_samples'] if r['arm'] == a} for a in data['spec']['arms']}
    rounds = sorted(set(by_arm['mylang-c1']) & set(by_arm['mylang-candidate']))
    ratios = [by_arm['mylang-candidate'][r] / by_arm['mylang-c1'][r] for r in rounds]
    zig_rounds = sorted(set(by_arm['zig-fast']) & set(by_arm['mylang-candidate']))
    zig_ratios = [by_arm['mylang-candidate'][r] / by_arm['zig-fast'][r] for r in zig_rounds]
    medians = {a: statistics.median(v.values()) if v else None for a, v in by_arm.items()}
    results.append({'case': case, 'receipt_sha256': hashlib.sha256(receipt.read_bytes()).hexdigest(),
        'arm_status': data['arm_status'], 'relative_timeout_policy': data['relative_timeout_policy'],
        'completed_rounds_by_arm': {a: sorted(v) for a, v in by_arm.items()},
        'paired_candidate_over_c1_ratios': ratios,
        'median_paired_candidate_over_c1': statistics.median(ratios) if ratios else None,
        'paired_candidate_over_zig_ratios': zig_ratios,
        'median_paired_candidate_over_zig': statistics.median(zig_ratios) if zig_ratios else None,
        'candidate_over_c1_medians': medians['mylang-candidate'] / medians['mylang-c1'] if medians['mylang-c1'] else None,
        'candidate_over_zig_medians': medians['mylang-candidate'] / medians['zig-fast'] if medians['zig-fast'] else None,
        'median_seconds': medians})
(HERE / 'diagnostic-results.json').write_text(json.dumps({'label': 'two-case diagnostic only; no full EDA parity/RSS claim', 'cases': results}, indent=2) + '\n')
