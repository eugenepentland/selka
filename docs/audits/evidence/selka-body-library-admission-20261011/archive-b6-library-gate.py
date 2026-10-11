"""Retain a completed B6 gate attempt without converting failures into passes."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang')
WORK = Path('/home/epentland/ai/canopy/.selka-agent-cache/bootstrap-20261011/tmp')
CACHE = Path('/home/epentland/.cache/mylang/zig-local-cache-selka-selfhost-pilots/o')
OUT = ROOT/'docs/audits/evidence/selka-body-library-admission-20261011'
HOST = '106c74ea88a9c8817a1320e5cd0cd951bfe8f030dc5336bc6dc5afd7c4ee2138'
BODY = 'f9b441269f2c56807e978d3eaaca2af005d4ab9de61bb834c53ee38945fa8703'


def retain(source, name):
    target = OUT/name
    assert not target.exists(), target
    data = source.read_bytes()
    target.write_bytes(gzip.compress(data, mtime=0) if name.endswith('.gz') else data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('attempt')
    parser.add_argument('--exit-status', type=int, required=True)
    args = parser.parse_args()
    log = WORK/(args.attempt+'-full-gate.log')
    text = log.read_text()
    summaries = re.findall(r'^Build Summary: .+$', text, re.M)
    assert len(summaries) == 1, 'gate has not completed'
    assert ('failed' in summaries[0]) == (args.exit_status != 0)
    assert 'body_check gate:' in text and 'complete qualification passed' in text
    retain(log, log.name+'.gz')
    guardian = [json.loads(row) for row in re.findall(r'^guardian/test: RESULT (.+)$', text, re.M)]
    assert guardian and all(row['failed'] == row['skipped'] == 0 for row in guardian)
    receipts = {}
    for lane, comparisons in [('normal', 1772), ('release', 886)]:
        candidates = []
        for path in CACHE.glob('*/body-check-qualification/'+lane+'.json'):
            value = json.loads(path.read_text())
            if value.get('host_sha256') == HOST and value.get('comparisons') == comparisons:
                candidates.append((path, value))
        assert candidates, lane
        path, value = max(candidates, key=lambda pair: pair[0].stat().st_mtime_ns)
        assert value['workflows'] == 443 and value['failed'] == value['skipped'] == 0
        assert value['packages']['body-check']['sha256'] == BODY
        assert value['forged_reply_checks'] == 92
        assert value['warm_deployment_checks'] == 30 and value['live_session_checks'] == 4
        retain(path, args.attempt+'-'+lane+'.json.gz')
        receipts[lane] = str(path)
    pure = {}
    for path in sorted((ROOT/'selfhost/components/body_check').glob('*tests.my')):
        names = re.findall(r'^public func (test_[A-Za-z0-9_]+)\(', path.read_text(), re.M)
        if names:
            pure[str(path.relative_to(ROOT))] = names
    fixtures = json.loads((ROOT/'selfhost/tests/fixtures/body_check/manifest.json').read_text())
    summary = {
        'attempt': args.attempt,
        'exit_status': args.exit_status,
        'full_gate_passed': args.exit_status == 0,
        'source_head_at_archive': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'summary': summaries[0],
        'guardian_verdicts': guardian,
        'guardian_totals': {k: sum(row[k] for row in guardian) for k in ('passed', 'failed', 'skipped')},
        'main_reports': receipts,
        'pure_test_roots': pure,
        'pure_tests_per_mode': sum(map(len, pure.values())),
        'fixtures': len(fixtures),
        'fixture_statuses': dict(Counter(row['status'] for row in fixtures.values())),
    }
    target = OUT/(args.attempt+'-gate-summary.json')
    assert not target.exists()
    target.write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps({k: v for k, v in summary.items() if k not in ('guardian_verdicts', 'pure_test_roots')}, indent=2))


if __name__ == '__main__':
    main()
