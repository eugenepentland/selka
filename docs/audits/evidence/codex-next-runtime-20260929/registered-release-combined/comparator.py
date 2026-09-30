"""Record every preliminary row against approved and fresh A5 controls."""
import hashlib
import json
from pathlib import Path
import sys

root = Path.cwd()
tag = sys.argv[1]
dest = root / '.tmp' / tag
quick = root / '.tmp-rc-quick'
read = lambda p: json.loads(p.read_text())
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
identity = read(dest / 'identity.json')
assert sha(dest / 'compiler/bin/mylang') == identity['compiler_sha256']
assert sha(dest / 'compiler/bin/qbe') == identity['qbe_sha256']
builder = read(quick / 'bin' / tag / 'compiler.json')
assert builder['sha256'] == identity['compiler_sha256']
gc = read(root / '.tmp/a5/accepted-gc-verification.json')
assert sha(quick / 'gc-builds.json') == gc['manifest_sha256']
for name, expected in gc['binary_sha256'].items():
    assert sha(quick / 'bin/gc' / name) == expected, name
fresh_identity = read(root / '.tmp/phase-b-fresh-a5-pinned-control/identity.json')
for name, expected in fresh_identity['binaries'].items():
    assert sha(quick / 'bin/m17-codex' / name) == expected, name
assert sha(quick / 'gc-cache.json') == 'd2580b2f6327db8f1a30006074be7871f0b0545cb2fe1ea149b3539aceb650de'
result = {'identity': identity, 'sizes': {}, 'acceptance_policy':
          'Approved A5: dev/full instruction limits and caps; smoke differential outputs with movements reported and no new cap misses.'}
paths = [dest / 'identity.json', dest / 'install.log', dest / 'corpus-build.log']
for size in ('dev', 'smoke', 'full'):
    candidate = read(quick / f'results-{tag}-{size}.json')
    approved = read(quick / f'results-m17-codex-{size}.json')
    fresh = read(root / '.tmp/phase-b-fresh-a5-pinned-control' / f'results-{size}.json')
    original = read(quick / f'results-m16-codex-{size}.json')
    def keyed(data):
        rows = {(r['id'], r['arm']): r for r in data['rows']}
        assert len(rows) == len(data['rows']) == 86 and not data['failures']
        return rows
    c, a, f, o = map(keyed, (candidate, approved, fresh, original))
    assert c.keys() == a.keys() == f.keys() == o.keys()
    rows = []
    for key, row in c.items():
        assert row['gc'] == a[key]['gc'] == f[key]['gc'] == o[key]['gc']
        move = (row['rc'] / a[key]['rc'] - 1) * 100
        live = (row['rc'] / f[key]['rc'] - 1) * 100
        new_cap = row['ratio'] > 1.3 and (size != 'smoke' or a[key]['ratio'] <= 1.3)
        rows.append(dict(row, approved_a5_rc=a[key]['rc'], fresh_a5_rc=f[key]['rc'],
                         regression_percent=move, fresh_control_regression_percent=live,
                         fails_regression=move > 1 or live > 1, fails_cap=new_cap))
    failed = [r for r in rows if r['fails_regression']]
    caps = [r for r in rows if r['fails_cap']]
    result['sizes'][size] = {'performance_acceptance_required': size != 'smoke',
                             'summary': candidate['summary'], 'matching_outputs': 86,
                             'regressions_over_1_percent': failed, 'cap_failures': caps,
                             'rows': rows}
    paths += [dest / f'measure-{size}.log', quick / f'results-{tag}-{size}.json']
    print(size, 'outputs86/86', 'regressions', len(failed), 'cap-failures', len(caps))
    for r in failed:
        print(' ', r['id'], r['arm'], f"{r['regression_percent']:+.6f}%")
result['acceptance'] = 'rejected' if any(
    (s['performance_acceptance_required'] and s['regressions_over_1_percent']) or s['cap_failures']
    for s in result['sizes'].values()
) else 'preliminary performance checks pass; final integration gate still required'
result['candidate_binaries_sha256'] = {
    p.name: sha(p) for p in sorted((quick / 'bin' / tag).iterdir())
    if p.is_file() and p.suffix in ('.qbe', '.llvm')
}
assert len(result['candidate_binaries_sha256']) == 58
(dest / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
receipt = {'identity': identity, 'acceptance': result['acceptance'],
           'coverage': {size: 86 for size in result['sizes']},
           'measurement_cpus': '2,3,10,11', 'observations_per_row': 1,
           'sha256': {str(p.relative_to(root)): sha(p) for p in paths + [dest / 'comparison.json']}}
(dest / 'measurement-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
