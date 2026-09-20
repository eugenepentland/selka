#!/usr/bin/env python3
"""Independent behavioural acceptance for dev-context-01 (rank_in_place).

The checker does not run the workflow the task is about and does not read the
candidate's diff. It copies a hidden probe into the candidate tree, runs it once
with the frozen compiler, and compares every printed line with
``reference.py``, which computes the expected order with Python's own stable
sort. The probe reads the result through the caller's own binding, so a helper
that sorts a copy instead of mutating the list fails even though a fresh sorted
list would be correct.

Exit status: 0 the candidate passed, 1 the candidate failed, 2 the checker could
not run (missing compiler, project or probe).

    python3 check.py --project DIR --frozen DIR --compiler PATH [--json]
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import reference  # noqa: E402  (the oracle sits beside the checker)

TASK = 'dev-context-01'
PROBE_NAME = 'acceptance_probe.my'
INVENTORY_SUFFIX = '.my'
INVENTORY_EXCLUDED = ('.mylang-cache', '.cache-acceptance')


def inventory(root: Path) -> dict[str, str]:
    """SHA-256 per ``.my`` file, by path relative to the root."""
    entries: dict[str, str] = {}
    for path in sorted(root.rglob(f'*{INVENTORY_SUFFIX}')):
        relative = path.relative_to(root).as_posix()
        if any(part in relative for part in INVENTORY_EXCLUDED):
            continue
        entries[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return entries


def differences(frozen: dict[str, str], candidate: dict[str, str]) -> dict[str, list[str]]:
    """Changed, added and removed files between the frozen tree and the candidate."""
    changed = sorted(name for name in frozen if name in candidate and frozen[name] != candidate[name])
    added = sorted(name for name in candidate if name not in frozen)
    removed = sorted(name for name in frozen if name not in candidate)
    return {'changed': changed, 'added': added, 'removed': removed}


def classify_changes(changes: dict[str, list[str]], allowed: list[str]) -> dict:
    """Split the tree diff into edits the task permits and edits it does not.

    An ``allowed`` entry is a path or an fnmatch glob.
    """
    permitted = [name for name in changes['changed']
                 if any(fnmatch.fnmatch(name, pattern) for pattern in allowed)]
    outside = [name for name in changes['changed'] if name not in permitted]
    return {
        'permitted_edits': permitted,
        'unintended': {'changed_outside_allowed': outside, 'added': changes['added'],
                       'removed': changes['removed']},
    }


def run_probe(compiler: Path, project: Path, cache_dir: Path, timeout: float) -> dict:
    """Run the hidden probe once and capture everything the verdict needs."""
    probe = project / PROBE_NAME
    shutil.copyfile(HERE / 'probe.my', probe)
    # No --print-result: stdout must hold the probe's own lines only, and the
    # exit status already reports whether main ran to completion.
    argv = [str(compiler), 'run', PROBE_NAME, f'--cache-dir={cache_dir}']
    started = time.monotonic()
    try:
        completed = subprocess.run(argv, cwd=project, capture_output=True, text=True,
                                   timeout=timeout)
        result = {'status': completed.returncode, 'stdout': completed.stdout,
                  'stderr': completed.stderr, 'timed_out': False}
    except subprocess.TimeoutExpired as expired:
        result = {'status': None, 'stdout': expired.stdout or '', 'stderr': expired.stderr or '',
                  'timed_out': True}
    except OSError as error:
        result = {'status': None, 'stdout': '', 'stderr': f'{compiler}: {error}', 'timed_out': False}
    result['seconds'] = round(time.monotonic() - started, 3)
    result['argv'] = argv
    probe.unlink(missing_ok=True)
    return result


def compare(expected: list[str], observed: list[str]) -> dict:
    """Line-by-line agreement, with the first mismatch named."""
    rows = []
    for index, wanted in enumerate(expected):
        seen = observed[index] if index < len(observed) else None
        rows.append({'line': index + 1, 'expected': wanted, 'observed': seen,
                     'agrees': wanted == seen})
    extra = observed[len(expected):]
    return {
        'cases': rows,
        'lines_expected': len(expected),
        'lines_observed': len(observed),
        'mismatches': [row for row in rows if not row['agrees']],
        'unexpected_trailing_lines': extra,
        'passed': not any(not row['agrees'] for row in rows) and not extra,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Command-line contract for the acceptance checker."""
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--project', type=Path, required=True,
                        help='the candidate tree to grade')
    parser.add_argument('--frozen', type=Path,
                        help='the frozen source tree, for the unintended-change inventory')
    parser.add_argument('--compiler', type=Path, required=True, help='the frozen compiler')
    parser.add_argument('--allowed', default='ranking.my',
                        help='comma-separated paths the task permits editing')
    parser.add_argument('--cache-dir', type=Path,
                        help='object cache root (default: outside the candidate tree)')
    parser.add_argument('--timeout', type=float, default=120.0,
                        help='wall-clock ceiling for the probe, in seconds')
    parser.add_argument('--json', action='store_true', help='print the verdict as JSON')
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Grade one candidate tree and report the behavioural verdict."""
    args = parse_args(sys.argv[1:] if argv is None else argv)
    project = args.project.resolve()
    compiler = args.compiler.resolve()
    if not (project / 'main.my').exists() or not (project / 'ranking.my').exists():
        print(json.dumps({'passed': False, 'error': f'main.my or ranking.my missing under {project}'}))
        return 2
    if not compiler.exists():
        print(json.dumps({'passed': False, 'error': f'no compiler at {compiler}'}))
        return 2
    cache_dir = args.cache_dir or (project.parent / '.cache-acceptance')
    observed = run_probe(compiler, project, cache_dir.resolve(), args.timeout)
    verdict = compare(reference.expected_lines(), observed['stdout'].splitlines())
    changes = differences(inventory(args.frozen.resolve()), inventory(project)) \
        if args.frozen else {'changed': [], 'added': [], 'removed': []}
    allowed = [name.strip() for name in args.allowed.split(',') if name.strip()]
    document = {
        'version': 'e1-acceptance-v1',
        'task': TASK,
        'passed': bool(verdict['passed'] and observed['status'] == 0),
        'command': ' '.join(observed['argv']),
        'run': {'status': observed['status'], 'seconds': observed['seconds'],
                'timed_out': observed['timed_out'],
                'stdout': observed['stdout'], 'stderr_tail': observed['stderr'][-2000:]},
        'comparison': verdict,
        'changes': changes,
        'changes_classified': classify_changes(changes, allowed),
    }
    if args.json:
        print(json.dumps(document, indent=1))
    else:
        print(f"{TASK} acceptance: {'PASS' if document['passed'] else 'FAIL'}"
              f" ({verdict['lines_observed']}/{verdict['lines_expected']} lines)")
        for row in verdict['mismatches']:
            print(f"  line {row['line']}: expected {row['expected']!r} observed {row['observed']!r}")
        for line in verdict['unexpected_trailing_lines']:
            print(f'  trailing: {line!r}')
        unintended = document['changes_classified']['unintended']
        for name, files in unintended.items():
            if files:
                print(f'  unintended {name}: {", ".join(files)}')
    return 0 if document['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
