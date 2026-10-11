"""Retain completed B5 qualification and all earlier failure logs."""
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

root = Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang')
work = Path('/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots')
cache = Path('/home/epentland/.cache/mylang/zig-local-cache-selka-selfhost-pilots/o')
out = root / 'docs/audits/evidence/selka-body-variants-20261011'
gate = (work / 'b5-full-gate-fresh.log').read_text()
assert 'Build Summary: 131/131 steps succeeded' in gate
assert 'memory usage peaked' not in gate
assert 'body_check gate: 199 pure tests per mode; complete qualification passed' in gate
assert '388 workflows, 1552 comparisons' in gate
assert '388 workflows, 776 comparisons' in gate
release = json.loads((work / 'b5-release-host-fresh.json').read_text())
assert release['workflows'] == 388 and release['comparisons'] == 776
assert release['failed'] == release['skipped'] == 0
assert release['forged_reply_checks'] == 66
out.mkdir(parents=True, exist_ok=False)

def copy(source, target):
    destination = out / target
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)

for p in sorted(work.glob('b5-*.log')):
    (out / (p.name + '.gz')).write_bytes(gzip.compress(p.read_bytes(), mtime=0))
for p in sorted(work.glob('b5-*-prune.json')):
    copy(p, p.name)
for source, name in [
    ('b5-artifacts.json', 'artifacts.json'),
    ('b5-release-host-fresh.json', 'release-host-qualification.json'),
    ('b5-release-host-qualification.json', 'release-host-before-fresh-exchange.json'),
    ('b5-installed-smoke/results.json', 'installed-smoke.json'),
    ('b5-frozen-replay.json', 'development-replay.json'),
    ('b5-installed-smoke.py', 'installed-smoke.py'),
    ('b5-edit-rebuild-repro.py', 'rebuild-2g.py'),
    ('b5-edit-rebuild-4g.py', 'rebuild-4g.py'),
    ('variant-performance/b5-matched.json', 'b5-matched.json'),
    ('variant-performance/b5-sweep.json', 'b5-sweep.json'),
    ('variant-performance/sweep.py', 'sweep.py'),
    ('variant-performance/isolated.py', 'isolated.py'),
    ('variant-performance/b5-timing.log', 'b5-timing.log'),
]:
    copy(work / source, name)
for name in ('b5-edit-rebuild-repro', 'b5-edit-rebuild-4g'):
    for p in sorted((work / name).iterdir()):
        if p.is_file():
            copy(p, f'{name}/{p.name}')
for p in sorted((work / 'variant-performance').glob('build-slot-*.log')):
    copy(p, p.name)

reports = {}
for mode, comparisons in [('normal', 1552), ('release', 776)]:
    matches = []
    for p in cache.glob(f'*/body-check-qualification/{mode}.json'):
        value = json.loads(p.read_text())
        if value.get('packages', {}).get('body-check', {}).get('schema') == 5:
            matches.append(p)
    assert matches, mode
    path = max(matches, key=lambda p: p.stat().st_mtime)
    value = json.loads(path.read_text())
    assert value['workflows'] == 388 and value['comparisons'] == comparisons
    assert value['failed'] == value['skipped'] == 0
    assert value['forged_reply_checks'] == 66
    assert value['packages'] == release['packages']
    copy(path, f'gate-{mode}.json')
    reports[mode] = str(path)

fixture_path = root / 'selfhost/tests/fixtures/body_check/manifest.json'
fixtures = json.loads(fixture_path.read_text())
copy(fixture_path, 'fixture-manifest.json')
pure = {}
for p in sorted((root / 'selfhost/components/body_check').glob('*tests.my')):
    names = re.findall(r'^public func (test_[A-Za-z0-9_]+)\(', p.read_text(), re.M)
    if names:
        pure[str(p.relative_to(root))] = names
assert sum(map(len, pure.values())) == 199
results = [json.loads(row) for row in re.findall(r'^guardian/test: RESULT (.+)$', gate, re.M)]
assert results and all(row['failed'] == 0 for row in results)
summary = {
    'qualification_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'gate_summary': re.findall(r'^Build Summary: .+$', gate, re.M),
    'guardian_verdicts': results,
    'guardian_totals': {key: sum(row[key] for row in results) for key in ('passed', 'failed', 'skipped')},
    'qualification_reports': reports,
    'fixtures': len(fixtures),
    'fixture_statuses': dict(Counter(row['status'] for row in fixtures.values())),
    'runtime_fixtures': sum('result' in row for row in fixtures.values()),
    'typed_core_fixtures': sum(bool(row.get('typed')) and not row.get('library') for row in fixtures.values()),
    'pure_test_roots': pure,
}
(out / 'gate-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
copy(Path(__file__), 'archive-b5.py')
paths = sorted(p for p in out.rglob('*') if p.is_file())
(out / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(out)}\n' for p in paths))
print(json.dumps({key: value for key, value in summary.items() if key not in ('guardian_verdicts', 'pure_test_roots')}, indent=2))
print(f'Retained {len(paths)} files plus SHA256SUMS in {out}')
