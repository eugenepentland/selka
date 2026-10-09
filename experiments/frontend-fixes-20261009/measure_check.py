#!/usr/bin/env python3
"""Measure identical warm EDA checks after an allocation-bounded body edit.

Use a private copy of the frozen migrated EDA sources. This never edits the
reference snapshot. Times are shared-machine observations; work counters are
reported separately. Compiler/cache identities are not shared between arms.
"""
import argparse
import hashlib
import json
import statistics
import subprocess
import time
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check(compiler, root, cache):
    command = [str(compiler), 'check-project', str(root / 'mylang/src/main.my'),
               '--cache-dir=' + str(cache), '--timings=json']
    start = time.perf_counter_ns()
    result = subprocess.run(command, cwd=root, capture_output=True, text=True)
    elapsed = time.perf_counter_ns() - start
    if result.returncode:
        raise RuntimeError(result.stderr)
    reports = []
    for line in result.stderr.splitlines():
        try:
            reports.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return {'elapsed_ns': elapsed, 'status': result.returncode, 'reports': reports,
            'stdout_sha256': hashlib.sha256(result.stdout.encode()).hexdigest(),
            'stderr_sha256': hashlib.sha256(result.stderr.encode()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--samples', type=int, default=5)
    args = parser.parse_args()
    compiler, root, cache = args.compiler.resolve(), args.project.resolve(), args.cache.resolve()
    source = root / 'mylang/src/support_strs.my'
    original = source.read_text()
    old = 'public func is_digit(c: int) -> bool noalloc:\n    return c >= 48 and c <= 57'
    new = 'public func is_digit(c: int) -> bool noalloc:\n    return c >= 0x30 and c <= 0x39'
    assert old in original and new not in original
    assert not cache.exists(), 'each arm needs its own fresh cache'
    rows = []
    try:
        for sample in range(args.samples):
            store = cache / str(sample)
            source.write_text(original)
            seed = check(compiler, root, store)
            source.write_text(original.replace(old, new))
            edited = check(compiler, root, store)
            # A second unrelated lexical change must be able to use refreshed summaries.
            source.write_text(original.replace(old, new).replace('return c >= 65 and c <= 90',
                                                                 'return c >= 0x41 and c <= 0x5a'))
            later = check(compiler, root, store)
            rows.append({'seed': seed, 'bounded_edit': edited, 'unrelated_edit': later})
    finally:
        source.write_text(original)
    report = {'compiler': str(compiler), 'compiler_sha256': digest(compiler),
              'source_sha256': digest(source), 'fixture': 'EDA is_digit decimal-to-hex body edit',
              'note': 'Private frozen-source copy with noalloc added to scalar is_digit; shared-machine elapsed observations.',
              'samples': rows, 'median_bounded_edit_ns': statistics.median(x['bounded_edit']['elapsed_ns'] for x in rows),
              'median_unrelated_edit_ns': statistics.median(x['unrelated_edit']['elapsed_ns'] for x in rows)}
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print({key: value for key, value in report.items() if key != 'samples'})


if __name__ == '__main__':
    main()
