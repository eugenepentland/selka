"""Retain every diagnostic pair and compute a reproducible paired ratio CI."""
from pathlib import Path
import hashlib, json, random, statistics

HERE = Path(__file__).resolve().parent
def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def percentile(values, fraction):
    values = sorted(values)
    position = (len(values) - 1) * fraction
    low = int(position)
    high = min(low + 1, len(values) - 1)
    return values[low] + (values[high] - values[low]) * (position - low)

summary = {'label': 'P3 scalar-run diagnostic against frozen C2; not final integrated parity',
           'zig_note': 'Zig is a fresh deadline calibration/oracle, not nine paired Zig timings',
           'ci_method': '95% percentile paired bootstrap of candidate median / baseline median, 100000 resamples, seed 20261013',
           'cases': {}}
for case in ['rds3+flat', 'cyclops-digital-pcb']:
    pairs, statuses, receipts, warmups = {}, [], [], []
    first = None
    for index in range(3):
        path = HERE / f'{case}.lease{index}.json'
        doc = json.loads(path.read_text())
        if first is None:
            first = doc
        statuses.append(doc['arm_status'])
        receipts.append({'path': str(path), 'sha256': sha(path)})
        for sample in doc['wall_samples']:
            assert sample['arm'] in ['baseline', 'candidate']
            row = pairs.setdefault(sample['round'], {})
            assert sample['arm'] not in row
            row[sample['arm']] = sample['value']
        journal = path.with_suffix(path.suffix + '.progress.jsonl')
        for line in journal.read_text().splitlines():
            row = json.loads(line)
            if row['kind'] in ['warmup', 'calibration_warmup']:
                warmups.append(row)
    result = {'arm_statuses': statuses, 'receipts': receipts, 'pairs': pairs,
              'warmups': warmups, 'calibration': first['relative_timeout_policy']}
    if not all(status['status'] == 'ok' for doc in statuses for status in doc.values()):
        result['status'] = 'failure or censor retained; no completed-sample performance claim'
    else:
        assert sorted(pairs) == list(range(9))
        assert all(set(row) == {'baseline', 'candidate'} for row in pairs.values())
        baseline = [pairs[i]['baseline'] for i in range(9)]
        candidate = [pairs[i]['candidate'] for i in range(9)]
        rng = random.Random(20261013)
        draws = []
        for _ in range(100000):
            indexes = [rng.randrange(9) for _ in range(9)]
            draws.append(statistics.median(candidate[i] for i in indexes) / statistics.median(baseline[i] for i in indexes))
        result.update({'status': 'all nine pairs completed',
                       'baseline_seconds': {'samples': baseline, 'median': statistics.median(baseline), 'min': min(baseline), 'max': max(baseline)},
                       'candidate_seconds': {'samples': candidate, 'median': statistics.median(candidate), 'min': min(candidate), 'max': max(candidate)},
                       'candidate_over_baseline': statistics.median(candidate) / statistics.median(baseline),
                       'candidate_over_baseline_95pct_ci': [percentile(draws, .025), percentile(draws, .975)]})
    summary['cases'][case] = result
(HERE / 'timing-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
