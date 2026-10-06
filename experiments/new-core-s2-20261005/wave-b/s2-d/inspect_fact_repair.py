#!/usr/bin/env python3
"""Inspect S0/S1 and dictionary row definitions against frozen integrated 090 controls."""
import argparse
import difflib
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
CACHE = ROOT / '.mylang-cache/wave-b/s2-d/fact-repair'
ROWS = ('dict_lookup', 'dict_lookup_str', 'dict_update', 'dict_update_str', 'set_dedup')


def definitions(path):
    return '\n'.join(re.findall(r'^define .*?^\}', path.read_text(), re.M | re.S))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rows', action='store_true')
    args = parser.parse_args()
    if args.rows:
        after = CACHE / 'after-rows'
        after.mkdir(parents=True, exist_ok=True)
        paths = [CACHE / 'before-rows' / f'row_{row}.ll' for row in ROWS]
        for path in paths:
            subprocess.run([str(ROOT / 'zig-out/bin/mylang-core'), 'build',
                            str(ROOT / f'test/core/{path.stem}.my'), '-o', str(after / path.stem),
                            '--release', '--emit-llvm', str(after / path.name),
                            '--cache-dir', str(after / 'cache'), '--link',
                            str(ROOT / 'benchmarks/runtime/ports/native_clock.c')], check=True)
    else:
        paths = sorted((CACHE / 'before-definitions').glob('*.ll'))
        assert len(paths) == 20
        after = ROOT / '.mylang-cache/wave-a/s2-d-fact-repair'
    changed = []
    for path in paths:
        old, new = definitions(path), definitions(after / path.name)
        same = old == new
        if not same:
            changed.append(path.stem)
            (after / f'{path.stem}.repair.diff').write_text(''.join(difflib.unified_diff(
                old.splitlines(True), new.splitlines(True), fromfile='090-integrated', tofile='fact-repair')))
        print(path.stem, 'all function definitions identical to090' if same else 'changed; retained diff requires inspection', flush=True)
    if args.rows:
        print('Rows requiring measurement:', ','.join(changed) or 'none:all five emitted row definitions unchanged')
    assert not changed, changed


if __name__ == '__main__':
    main()
