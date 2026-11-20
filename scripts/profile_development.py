#!/usr/bin/env python3
"""Measure cold checks, exact warm verdicts and edited-source checks on an isolated project."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import selectors
import shutil
import statistics
import subprocess
import tempfile
import time


def summary(values):
    ordered = sorted(values)
    return {'samples': values, 'median_ms': statistics.median(values), 'p95_ms': ordered[math.ceil(len(values) * .95) - 1]}


def reply(process, selector, action):
    start = time.monotonic()
    process.stdin.write(action + '\n')
    process.stdin.flush()
    if not selector.select(120):
        raise TimeoutError('compiler check session timed out')
    line = process.stdout.readline()
    if not line:
        raise RuntimeError('compiler check session exited unexpectedly')
    record = json.loads(line)
    if record.get('status') != 0:
        raise RuntimeError('check failed: ' + line)
    return (time.monotonic() - start) * 1000, record


def measure(compiler, project, edit, before, after, repeats):
    cold, warm, changed, observations = [], [], [], []
    original = edit.read_text()
    if before not in original or before == after:
        raise ValueError('edit must replace existing text with different text')
    for _ in range(repeats):
        start = time.monotonic()
        subprocess.run([str(compiler), 'check-project', str(project)], check=True, capture_output=True, timeout=120)
        cold.append((time.monotonic() - start) * 1000)
    with tempfile.TemporaryFile() as errors:
        process = subprocess.Popen([str(compiler), 'check-session', str(project)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=errors, text=True, bufsize=1)
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                _, initial = reply(process, selector, 'check')
                observations.append(initial)
                for _ in range(repeats):
                    elapsed, record = reply(process, selector, 'check')
                    warm.append(elapsed)
                    observations.append(record)
                for index in range(repeats):
                    edit.write_text(original.replace(before, after) if index % 2 == 0 else original)
                    elapsed, record = reply(process, selector, 'check')
                    changed.append(elapsed)
                    observations.append(record)
                reply(process, selector, 'quit')
            process.wait(timeout=10)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdin.close()
            process.stdout.close()
            edit.write_text(original)
    return {'cold_check': summary(cold), 'warm_verdict': summary(warm), 'edited_check': summary(changed), 'observations': observations}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--entry', type=Path, required=True)
    parser.add_argument('--edit-module', required=True)
    parser.add_argument('--before', required=True)
    parser.add_argument('--after', required=True)
    parser.add_argument('--repeats', type=int, default=5)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 2 <= args.repeats <= 100:
        parser.error('repeats must be 2..100')
    entry = args.entry.resolve()
    relative = Path(args.edit_module)
    if relative.is_absolute() or '..' in relative.parts:
        parser.error('edit-module must stay within the copied project')
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='selka-profile-') as temporary:
        project = Path(temporary) / 'project'
        shutil.copytree(entry.parent, project)
        result = measure(compiler, project / entry.name, project / relative, args.before, args.after, args.repeats)
    result.update(version='development-profile-v1', compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                  entry=str(entry), edit_module=str(relative), repeats=args.repeats,
                  scope='local sequential checking only; includes process startup for cold checks; no VM execution or merge timing')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: {name: value for name, value in result[key].items() if name != 'samples'}
                      for key in ('cold_check', 'warm_verdict', 'edited_check')}, indent=2))


if __name__ == '__main__':
    main()
