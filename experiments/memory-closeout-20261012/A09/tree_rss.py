#!/usr/bin/env python3
"""Sample simultaneous descendant RSS in a separate memory-only execution.

This is not cgroup memory: summing RSS double counts shared pages, and a sampled
peak can miss short-lived processes/allocations. Never use its elapsed time as
the primary uninstrumented runtime/compiler timing result.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def tree(root):
    pending, seen, rows = [root], set(), []
    while pending:
        pid = pending.pop()
        if pid in seen:
            continue
        seen.add(pid)
        proc = Path('/proc') / str(pid)
        try:
            statm = (proc / 'statm').read_text().split()
            rows.append({'pid': pid, 'rss_bytes': int(statm[1]) * os.sysconf('SC_PAGE_SIZE'),
                         'name': (proc / 'comm').read_text().strip()})
            for children in (proc / 'task').glob('*/children'):
                try:
                    pending.extend(map(int, children.read_text().split()))
                except (FileNotFoundError, ProcessLookupError, PermissionError):
                    pass
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--interval-ms', type=float, default=10)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not args.command or args.interval_ms <= 0:
        parser.error('need positive interval and command after --')
    command = args.command[1:] if args.command[0] == '--' else args.command
    if args.output.exists():
        parser.error('refusing to overwrite memory evidence')
    started = time.monotonic_ns()
    child = subprocess.Popen(command)
    samples, peak, peak_rows = [], 0, []
    try:
        while True:
            rows = tree(child.pid)
            total = sum(row['rss_bytes'] for row in rows)
            samples.append({'elapsed_ns': time.monotonic_ns() - started,
                            'processes': len(rows), 'rss_sum_bytes': total})
            if total > peak:
                peak, peak_rows = total, rows
            if child.poll() is not None:
                break
            time.sleep(args.interval_ms / 1000)
    finally:
        if child.poll() is None:
            child.terminate()
            child.wait()
    result = {'command': command, 'status': child.returncode,
              'sample_interval_ms': args.interval_ms, 'peak_sampled_rss_sum_bytes': peak,
              'peak_processes': peak_rows, 'samples': samples,
              'limitations': __doc__.strip(), 'elapsed_is_instrumented': True}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    raise SystemExit(child.returncode)


if __name__ == '__main__':
    main()
