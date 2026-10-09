#!/usr/bin/env python3
"""Build all 46 row pairs using the same migrated sources for both compilers."""
import argparse
import hashlib
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--bin', required=True, type=Path)
    args = parser.parse_args()
    directory = args.bin.resolve()
    if not directory.is_relative_to(ROOT):
        parser.error('--bin must be inside this worktree')
    directory.mkdir(parents=True, exist_ok=True)
    wrappers = []
    for label, compiler in (('base', args.base), ('candidate', args.candidate)):
        wrapper = directory / ('compiler-' + label)
        target = Path(__file__).resolve().parent / 'mylang-rows'
        runtime = ROOT / '.mylang-cache/rp3/runtime' / hashlib.sha256(compiler.read_bytes()).hexdigest()[:16]
        runtime.mkdir(parents=True, exist_ok=True)
        wrapper.write_text('#!/usr/bin/env bash\nset -eu\nexport RP3_ROW_REAL=' +
                           shlex.quote(str(compiler.resolve())) + '\nexport MYLANG_CORE_RUNTIME_CACHE=' +
                           shlex.quote(str(runtime)) + '\nexec ' + shlex.quote(str(target)) + ' "$@"\n')
        wrapper.chmod(0o755)
        wrappers.append(str(wrapper))
    command = [str(ROOT / 'scripts/build-slot.sh'), 'build', sys.executable,
               str(ROOT / 'experiments/new-core-s4-20261006/integration/measure_all46.py'),
               '--build-only', '--mylang', wrappers[0], '--core', wrappers[1], '--bin', str(directory)]
    raise SystemExit(subprocess.call(command, cwd=ROOT))


if __name__ == '__main__':
    main()
