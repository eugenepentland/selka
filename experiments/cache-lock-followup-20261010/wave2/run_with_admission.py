#!/usr/bin/env python3
"""Separate standard build-slot admission waiting from aggregate command time."""
import time
ENTRY_MONOTONIC_NS = time.monotonic_ns()
ENTRY_UNIX_NS = time.time_ns()

import argparse
from datetime import datetime, timezone
import json
import os
import signal
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve()
ROOT = HERE.parents[3]


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def terminate_owned(process):
    """Interrupt only this wrapper's owned session, then bound cleanup."""
    try:
        os.killpg(process.pid, signal.SIGINT)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=5)


def interrupted(signum, frame):
    raise KeyboardInterrupt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--kind', choices=['build', 'gate'], default='gate')
    parser.add_argument('--label', default='batch')
    parser.add_argument('--admitted-exec', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    assert command, 'a command after -- is required'
    output = args.output.resolve()
    if args.admitted_exec:
        admitted = {'monotonic_ns': ENTRY_MONOTONIC_NS, 'unix_ns': ENTRY_UNIX_NS}
        write(output / 'admitted.json', admitted)
        measured = output / 'command.time.json'
        started = time.monotonic_ns()
        with (output / 'command.stdout.log').open('wb') as stdout, (output / 'command.stderr.log').open('wb') as stderr:
            result = subprocess.run(['/usr/bin/time', '-f', '{"peak_rss_kb":%M,"user_s":%U,"system_s":%S,"exit":%x}',
                                     '-o', str(measured), *command], stdout=stdout, stderr=stderr)
        ended = time.monotonic_ns()
        metrics = json.loads(measured.read_text().splitlines()[-1])
        write(output / 'completed.json', {'admitted': admitted, 'command_started_monotonic_ns': started,
                                         'command_ended_monotonic_ns': ended, 'command_ended_unix_ns': time.time_ns(),
                                         'command_wall_s': (ended - started) / 1e9,
                                         'admitted_until_command_end_s': (ended - ENTRY_MONOTONIC_NS) / 1e9,
                                         'metrics': metrics, 'exit': result.returncode})
        return result.returncode
    output.mkdir(parents=True, exist_ok=False)
    submitted = time.monotonic_ns()
    request = {'label': args.label, 'started_utc': datetime.now(timezone.utc).isoformat(),
               'submitted': {'monotonic_ns': submitted, 'unix_ns': time.time_ns()},
               'kind': args.kind, 'command': command, 'cwd': str(Path.cwd()),
               'method': 'Queue is submit to admitted Python entry, including wrapper/interpreter startup. '
                         'Command wall/CPU/max-process RSS excludes admission waiting. Held interval ends at '
                         'command completion, while the slot is still held; final JSON/exit overhead is excluded. '
                         'The standard build-slot thresholds, locks and environment are unchanged.'}
    write(output / 'submitted.json', request)
    wrapped = [str(ROOT / 'scripts/build-slot.sh'), args.kind, sys.executable, str(HERE), '--admitted-exec',
               '--output', str(output), '--kind', args.kind, '--label', args.label, '--', *command]
    with (output / 'admission.stdout.log').open('wb') as stdout, (output / 'admission.stderr.log').open('wb') as stderr:
        result = subprocess.Popen(wrapped, stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            result.wait()
        except BaseException:
            terminate_owned(result)
            raise
    completed_path = output / 'completed.json'
    completion = json.loads(completed_path.read_text()) if completed_path.exists() else None
    evidence = dict(request, wrapper_command=wrapped, wrapper_exit=result.returncode,
                    queue_s=None if completion is None else (completion['admitted']['monotonic_ns'] - submitted) / 1e9,
                    held_s=None if completion is None else completion['admitted_until_command_end_s'],
                    command_wall_s=None if completion is None else completion['command_wall_s'],
                    completion=completion)
    write(output / 'results.json', evidence)
    print(json.dumps({'label': args.label, 'output': str(output), 'queue_s': evidence['queue_s'],
                      'held_s': evidence['held_s'], 'command_wall_s': evidence['command_wall_s'], 'exit': result.returncode}))
    return result.returncode


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, interrupted)
    raise SystemExit(main())
