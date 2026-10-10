#!/usr/bin/env python3
"""Run the full lint gate on live sources containing a written noalloc contract."""
import argparse
from pathlib import Path
import re
import subprocess

from check_my_format import select_sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    selected, _ = select_sources(root)
    # Stdlib internal names are legal for checking, including files currently
    # excluded by the formatter; their allocation promises still join this gate.
    candidates = set(selected) | {p.relative_to(root).as_posix() for p in (root / 'src/stdlib').glob('*.my')}
    checked = 0
    for relative in sorted(candidates):
        if not re.search(r'\bnoalloc\b', (root / relative).read_text()):
            continue
        result = subprocess.run([args.compiler, 'lint', relative, '--gate'], cwd=root,
                                capture_output=True, text=True)
        if result.returncode:
            print(f'noalloc lint: {relative}: exit {result.returncode}')
            print(result.stdout + result.stderr)
            return result.returncode
        checked += 1
    if checked == 0:
        raise RuntimeError('no allocation-contract sources selected')
    print(f'noalloc lint: {checked} live sources pass lint --gate; no unwaived allocation violations')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
