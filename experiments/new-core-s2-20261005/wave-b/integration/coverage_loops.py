#!/usr/bin/env python3
"""Compare function and checked-loop admission on exactly the same source corpus.

Loops are typed loop instances inside independently accepted functions. Loops in
refused functions are attributed to that function's first refusal, even when the
refusal occurs outside the loop; this is not a standalone loop-fragment checker.
The typed frontend is unchanged in Wave B, so one dump supplies counts for both
compiler versions. Every child status is checked and missing function names fail.
"""
import argparse
import collections
import glob
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]


def admission(core, files):
    done = subprocess.run([str(core), 'coverage', *files], capture_output=True, text=True)
    if done.returncode:
        raise SystemExit(f'coverage failed ({done.returncode}): {done.stderr}')
    outcomes, frontend = {}, []
    for line in done.stdout.splitlines():
        kind, _, rest = line.partition(' ')
        if kind == 'frontend':
            frontend.append(rest)
        elif kind == 'ok':
            name = rest.partition('\t')[0]
            outcomes[name] = None
        elif kind == 'refused':
            reason, _, name = rest.partition('\t')
            if outcomes.get(name, 'absent') is not None:
                outcomes[name] = reason
        else:
            raise SystemExit(f'unrecognized coverage output: {line!r}')
    if not outcomes:
        raise SystemExit('coverage produced no function outcomes')
    return outcomes, frontend


def checked_loops(core, files):
    counts, rejected = {}, []
    for path in files:
        done = subprocess.run([str(core), 'dump-typed', path], capture_output=True, text=True)
        if done.returncode:
            if done.returncode != 1 or not done.stderr:
                raise SystemExit(f'dump-typed crashed/failed: {path}: {done.returncode}: {done.stderr}')
            rejected.append(path)
            continue
        current, count = None, 0
        for line in done.stdout.splitlines():
            found = re.match(r'^fn (.*?) #\d+ params=', line)
            if found:
                if current is not None:
                    if current in counts and counts[current] != count:
                        raise SystemExit(f'inconsistent loop count for {current}')
                    counts[current] = count
                current, count = found.group(1), 0
            elif re.match(r'^\s+loop id=\d+', line):
                count += 1
        if current is not None:
            if current in counts and counts[current] != count:
                raise SystemExit(f'inconsistent loop count for {current}')
            counts[current] = count
    return counts, rejected


def totals(outcomes, loops):
    missing = set(outcomes) - set(loops)
    if missing:
        raise SystemExit(f'coverage names missing from typed loop dump: {sorted(missing)}')
    reasons = collections.defaultdict(lambda: {'functions': 0, 'loops': 0})
    for name, reason in outcomes.items():
        entry = reasons[reason or '(accepted)']
        entry['functions'] += 1
        entry['loops'] += loops[name]
    return dict(reasons)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', required=True, type=Path)
    parser.add_argument('--after', required=True, type=Path)
    parser.add_argument('--scratch', required=True, type=Path)
    parser.add_argument('--json', required=True, type=Path)
    args = parser.parse_args()
    for name in ('before', 'after', 'scratch', 'json'):
        setattr(args, name, getattr(args, name).resolve())
    args.scratch.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('function_coverage', ROOT / 'experiments/new-core-s0-20261005/coverage.py')
    sweep = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sweep)
    corpora = {
        'examples': sweep.with_entry(sorted(glob.glob(str(ROOT / 'examples/**/*.my'), recursive=True)), str(args.scratch / 'examples')),
        'bench/parity': sorted(glob.glob(str(ROOT / 'bench/parity/**/*.my'), recursive=True)),
        'tests/lang': sweep.with_entry(sorted(glob.glob(str(ROOT / 'tests/lang/*.my'))), str(args.scratch / 'lang')),
        'benchmarks/runtime': sorted(glob.glob(str(ROOT / 'benchmarks/runtime/expanded/*/main.my'))),
    }
    report = {'command': shlex.join(sys.argv), 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), 'before_source_commit': '72eaae74', 'loop_definition': __doc__.split('\n\n')[1], 'corpora': {}}
    all_before, all_after = collections.Counter(), collections.Counter()
    for corpus, files in corpora.items():
        before, before_front = admission(args.before, files)
        after, after_front = admission(args.after, files)
        if set(before) != set(after):
            raise SystemExit(f'{corpus}: frontend function corpus changed between compiler versions')
        loops, rejected = checked_loops(args.after, files)
        old, new = totals(before, loops), totals(after, loops)
        report['corpora'][corpus] = {'files': len(files), 'frontend_before': before_front, 'frontend_after': after_front, 'typed_rejected': rejected, 'before': old, 'after': new}
        for reason, count in old.items():
            all_before[(reason, 'functions')] += count['functions']
            all_before[(reason, 'loops')] += count['loops']
        for reason, count in new.items():
            all_after[(reason, 'functions')] += count['functions']
            all_after[(reason, 'loops')] += count['loops']
        print(f'{corpus}: {len(before)} functions, {sum(loops[n] for n in before)} checked loops; before {old.get("(accepted)", {})}; after {new.get("(accepted)", {})}', flush=True)
    reasons = sorted({key[0] for key in all_before} | {key[0] for key in all_after}, key=lambda reason: (reason != '(accepted)', -all_after[(reason, 'functions')], reason))
    print('\n| first refusal | before functions | before loops | after functions | after loops |\n|---|---:|---:|---:|---:|')
    for reason in reasons:
        print(f'| {reason} | {all_before[(reason,"functions")]} | {all_before[(reason,"loops")]} | {all_after[(reason,"functions")]} | {all_after[(reason,"loops")]} |')
    report['totals'] = {reason: {'before_functions': all_before[(reason, 'functions')], 'before_loops': all_before[(reason, 'loops')], 'after_functions': all_after[(reason, 'functions')], 'after_loops': all_after[(reason, 'loops')]} for reason in reasons}
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
