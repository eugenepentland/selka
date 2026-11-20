#!/usr/bin/env python3
"""Type-check the standalone programs no test group builds with `selka check`.

Five trees hold programs that only this sweep compiles: the parity suite and
runtime benchmarks (`bench`, `benchmarks`), the user-facing `examples`, the
embedded standard library (`src/stdlib`) and the Selka components
(`selfhost/components`). A syntax or checker change could break any of them
unseen. The sweep takes about six seconds. Every `.selka` file under the roots is
checked and there is no exclusion list, so a program that stops checking fails
the gate and is either repaired or moved out of these roots. New files are
picked up automatically.
"""
import argparse
from pathlib import Path
import subprocess
import sys

ROOTS = ('bench', 'benchmarks', 'examples', 'src/stdlib', 'selfhost/components')


def sources(root):
    """Every program under the swept roots, as a root-relative POSIX path."""
    found = []
    for directory in ROOTS:
        found.extend(path.relative_to(root).as_posix() for path in sorted((root / directory).rglob('*.selka')))
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()
    compiler = str(Path(args.compiler).resolve())
    programs = sources(root)
    if not programs:
        print('program check: no .selka programs under ' + ', '.join(ROOTS), file=sys.stderr)
        return 1
    failures = 0
    for program in programs:
        result = subprocess.run([compiler, 'check', program], cwd=root, capture_output=True, text=True)
        if result.returncode:
            failures += 1
            print(f'{program}: selka check exited {result.returncode}', file=sys.stderr)
            print(result.stdout + result.stderr, end='', file=sys.stderr)
    print(f'program check: {len(programs)} programs, {failures} failures')
    return int(failures != 0)


if __name__ == '__main__':
    sys.exit(main())
