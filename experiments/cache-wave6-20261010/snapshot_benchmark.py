#!/usr/bin/env python3
"""Paired whole-snapshot measurements; run on an isolated reserved CPU."""
import argparse
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import resource
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from verification_snapshot import DigestSession, Snapshot


def worker(args):
    session = DigestSession() if args.worker == 'session' else None
    started = time.perf_counter()
    with ExitStack() as stack:
        snapshots = [stack.enter_context(Snapshot(ROOT, [], [args.input], digest_session=session))
                     for _ in range(4)]
        assert all(snapshot.unchanged() for snapshot in snapshots)
        identities = [snapshot.identity for snapshot in snapshots]
        work = {name: sum(snapshot.statistics[name] for snapshot in snapshots)
                for name in snapshots[0].statistics}
    print(json.dumps(dict(arm=args.worker, seconds=time.perf_counter() - started,
                         max_rss_kib=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
                         identity=hashlib.sha256(json.dumps(identities, sort_keys=True).encode()).hexdigest(),
                         work=work)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--worker', choices=('uncached', 'session'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    args.input = args.input.absolute()
    if args.worker:
        worker(args)
        return
    rows = []
    for index in range(5):
        order = ('uncached', 'session') if index % 2 == 0 else ('session', 'uncached')
        for arm in order:
            raw = subprocess.check_output([sys.executable, __file__, '--input', str(args.input), '--worker', arm])
            rows.append(json.loads(raw))
    assert len({row['identity'] for row in rows}) == 1
    for row in rows:
        assert row['work']['files_hashed'] == (1 if row['arm'] == 'session' else 4)
        assert row['work']['digest_reuses'] == (3 if row['arm'] == 'session' else 0)
    result = dict(version=1, input=str(args.input), snapshots_per_invocation=4,
                  success=True, rows=rows, summaries={arm: {
                      'median_seconds': statistics.median(row['seconds'] for row in rows if row['arm'] == arm),
                      'median_max_rss_kib': statistics.median(row['max_rss_kib'] for row in rows if row['arm'] == arm)}
                      for arm in ('uncached', 'session')})
    text = json.dumps(result, indent=2, sort_keys=True) + '\n'
    if args.output:
        args.output.write_text(text)
    print(text, end='')


if __name__ == '__main__':
    main()
