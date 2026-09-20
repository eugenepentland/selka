#!/usr/bin/env python3
"""The counting shim: one recorded event per compiler process.

``pilot.py`` puts a small launcher named ``mylang`` first on the solver's
``PATH``; that launcher runs this file, which

1. records the source inventory before the process starts,
2. runs the frozen compiler with the argument list the solver wrote, adding only
   the frozen ``--cache-dir`` when the command accepts one and the solver did not
   supply it (the cache policy is a protocol field, and a cache root inside the
   candidate tree would look like an edit),
3. forwards stdout and stderr byte for byte and exits with the child's status,
4. appends one ``compiler-invocation-v1`` event with the wall time, the response
   bytes, the exit status, the parsed diagnostics and whether the source moved
   while the process ran.

A wrapper cannot make the work look smaller: the event is written after the
process, from the process, and the harness reads only events.

    python3 shim.py --log EVENTS.jsonl --real /path/to/mylang -- ARGS...
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import events  # noqa: E402

# Commands that accept --cache-dir; the shim injects one when it is missing so
# every arm compiles under the same cache policy and outside the source tree.
CACHE_COMMANDS = ('run', 'run-project', 'build', 'test')


def cache_injection(argv: list[str], cache_dir: str) -> list[str]:
    """The argument list with the frozen cache root added when it is accepted.

    Everything after ``--`` belongs to the guest, so the flag goes before it.
    """
    if not cache_dir or events.cache_dir_of(argv):
        return argv
    subcommand = argv[1] if len(argv) > 1 and not argv[1].startswith('-') else ''
    if subcommand not in CACHE_COMMANDS:
        return argv
    flag = f'--cache-dir={cache_dir}'
    if '--' in argv:
        return argv[:argv.index('--')] + [flag] + argv[argv.index('--'):]
    return argv + [flag]


def read_counter(path: Path) -> int:
    """A monotonic counter file, or 0 when it does not exist yet."""
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Split the shim's own options from the wrapped command's arguments.

    The wrapped command is everything after a standalone ``--``. It is split out
    before argparse sees it, because ``argparse.REMAINDER`` swallows the first
    token after the separator (``mylang check main.my`` would be recorded as
    ``mylang main.my``), and a recorded argv that dropped the subcommand is a
    wrong measurement.
    """
    if '--' not in argv:
        raise SystemExit('shim.py: the wrapped command must follow a standalone --')
    split = argv.index('--')
    own, command = argv[:split], argv[split + 1:]
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--log', type=Path, required=True, help='the JSON Lines event log')
    parser.add_argument('--real', type=Path, required=True, help='the frozen compiler binary')
    parser.add_argument('--attempt', required=True, help='the attempt this process belongs to')
    parser.add_argument('--cache-dir', default='', help='cache root to inject')
    args = parser.parse_args(own)
    args.command = command
    return args


def main(argv: list[str] | None = None) -> int:
    """Record one invocation and forward its result unchanged."""
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if not args.command:
        print('shim.py: no command to run', file=sys.stderr)
        return 2
    workspace = Path(os.environ.get('E1_WORKSPACE', os.getcwd()))
    counter_path = args.log.with_suffix('.counter')
    sequence = read_counter(counter_path) + 1
    try:
        counter_path.write_text(str(sequence))
    except OSError:
        pass
    before, _ = events.inventory(workspace)
    forwarded = cache_injection([str(args.real)] + list(args.command), args.cache_dir)
    started = events.now_ns()
    completed = subprocess.run(forwarded, capture_output=True)
    finished = events.now_ns()
    after, _ = events.inventory(workspace)
    stderr_text = completed.stderr.decode(errors='replace')
    diagnostics = events.parse_diagnostics(stderr_text)
    event = events.build_event(
        argv=forwarded, cwd=Path.cwd(), log=args.log,
        compiler_sha256=os.environ.get('E1_COMPILER_SHA256', ''), attempt_id=args.attempt,
        invocation_id=f'{args.attempt}-{sequence:04d}-{os.getpid()}', exit_code=completed.returncode,
        started_ns=started, finished_ns=finished, stdout_bytes=len(completed.stdout),
        stderr_bytes=len(completed.stderr), source_sha256=before, source_stable=before == after,
        stderr=stderr_text, diagnostics=diagnostics)
    events.append_event(args.log, event)
    sys.stdout.buffer.write(completed.stdout)
    sys.stdout.buffer.flush()
    sys.stderr.buffer.write(completed.stderr)
    sys.stderr.buffer.flush()
    return completed.returncode


if __name__ == '__main__':
    sys.exit(main())
