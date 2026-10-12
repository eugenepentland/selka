#!/usr/bin/env python3
"""Validate exploratory short screens, without promoting them to final evidence."""
import argparse
import importlib.util
import json
from pathlib import Path
import statistics

HERE = Path(__file__).resolve().parent
s = importlib.util.spec_from_file_location('screen_measure', HERE / 'measure_screen.py')
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('run', type=Path)
p.add_argument('output', type=Path)
a = p.parse_args()
assert not a.output.exists(), 'never overwrite screen summary'
rows = []
for path in sorted((a.run / 'results').glob('*.json')):
    d = json.loads(path.read_text()); spec = d['spec']
    assert d['schema'] == 'text-gap-screen-v1' and spec['screening']
    assert (spec['warmups'], spec['rounds'], spec['rss_rounds']) == (1, 5, 0)
    assert d['identities'] == d['identities_after']
    for source, sha in d['identities'].items():
        assert m.digest(source) == sha, source
    assert d['iterations'] == spec['screen_iterations']
    expected = m.registry.checksum(spec['case'], spec['size'], d['iterations'], spec['seed'])
    assert d['expected'] == expected and d['rss'] == [] and d['counted'] == {}
    names = list(spec['arms']); values = {}
    for name in names:
        assert d['summary'][name]['complete']
        for phase, rounds in (('warmups', {-1}), ('samples', set(range(5)))):
            samples = [v for v in d[phase] if v['arm'] == name]
            assert {v['round'] for v in samples} == rounds and len(samples) == len(rounds)
            for v in samples:
                assert m.validate(v, expected, 'kernel')['status'] == 'ok'
        values[name] = [v['kernel_ns'] / d['iterations'] for v in d['samples'] if v['arm'] == name]
    for rnd in range(5):
        assert [v['arm'] for v in d['samples'] if v['round'] == rnd] == m.balanced_order(names, rnd, spec['cell'] + '/samples')
    medians = {k: statistics.median(v) for k, v in values.items()}
    rows.append(dict(case=spec['case'], profile=spec['profile'], iterations=d['iterations'], medians_ns=medians,
                     candidate_ratios={k: medians['checked-candidate'] / v for k, v in medians.items() if k != 'checked-candidate'},
                     raw_ranges_ns={k: [min(v), max(v)] for k, v in values.items()}, receipt_sha256=m.digest(path)))
assert len(rows) == 2
payload = dict(schema='text-gap-screen-summary-v1', rows=rows,
               limitation='Exploratory5round paired screen only,1warmup,3arms,noRSS/count phase. No final target claim or pooling with15round final evidence.')
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(payload, indent=2) + '\n')
print(json.dumps(rows, indent=2))
