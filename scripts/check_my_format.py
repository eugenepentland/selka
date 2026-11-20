#!/usr/bin/env python3
"""Check the live .selka corpus without rewriting archived or diagnostic evidence.

The manifest lists every excluded path with its reason. New .selka files under any
live root are checked automatically; compiler failures are never auto-excluded.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOTS = ('bench', 'benchmarks', 'docs', 'examples', 'selfhost', 'src', 'test', 'tests')
MANIFEST = 'scripts/my_format_exclusions.json'


def select_sources(root):
    entries = json.loads((root / MANIFEST).read_text())
    for path, reason in entries.items():
        if not reason.strip() or not (root / path.rstrip('/')).exists():
            raise ValueError(f'invalid or stale format exclusion: {path}')
    selected, excluded = [], []
    for directory in ROOTS:
        for source in sorted((root / directory).rglob('*.selka')):
            relative = source.relative_to(root).as_posix()
            matches = [p for p in entries if relative == p or (p.endswith('/') and relative.startswith(p))]
            if matches:
                excluded.append((relative, entries[matches[0]]))
            else:
                selected.append(relative)
    return selected, excluded


def check_source(compiler, source, root, env=None):
    """Check one file with `selka fmt FILE --check`: None when it is formatted, else what the compiler printed (or a
    line naming the exit status). `scripts/gate_cheap_checks.py` calls this too, so both run the same check."""
    result = subprocess.run([str(Path(compiler).resolve()), 'fmt', source, '--check'],
                            cwd=root, capture_output=True, text=True, env=env)
    if not result.returncode:
        return None
    if not result.stdout and not result.stderr:
        return f'{source}: fmt exited {result.returncode}\n'
    return result.stdout + result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--list-exclusions', action='store_true')
    args = parser.parse_args()
    try:
        sources, exclusions = select_sources(args.root.resolve())
    except (ValueError, OSError) as error:
        parser.error(str(error))
    if args.list_exclusions:
        for path, reason in exclusions:
            print(f'{path}: {reason}')
    failures = 0
    for source in sources:
        report = check_source(args.compiler, source, args.root)
        if report is not None:
            failures += 1
            print(report, end='', file=sys.stderr)
    print(f'.selka format: {len(sources)} checked, {len(exclusions)} deliberate exclusions, {failures} failures; '
          'experiments/ is historical and outside the live roots')
    return int(failures != 0)


if __name__ == '__main__':
    sys.exit(main())
