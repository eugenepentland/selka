#!/usr/bin/env python3
"""Prove the builder-only view refusal repair leaves all measured row code unchanged."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[4]
CACHE = ROOT / '.mylang-cache/wave-b/s2-d'
TARGET = CACHE / 'row-code-identity'
ROWS = ('dict_lookup', 'dict_lookup_str', 'dict_update', 'dict_update_str', 'set_dedup')


def main():
    TARGET.mkdir(parents=True, exist_ok=True)
    clean = True
    for row in ROWS:
        before = CACHE / 'rows-final' / f'row_{row}_new'
        after = TARGET / f'row_{row}_new'
        subprocess.run([str(ROOT / 'zig-out/bin/mylang-core'), 'build',
                        str(ROOT / f'test/core/row_{row}.my'), '-o', str(after),
                        '--release', '--emit-llvm', str(TARGET / f'{row}.ll'),
                        '--cache-dir', str(TARGET / 'cache'),
                        '--link', str(ROOT / 'benchmarks/runtime/ports/native_clock.c')], check=True)
        for label, binary in (('before', before), ('after', after)):
            subprocess.run(['objcopy', '--only-section=.text', '-O', 'binary',
                            str(binary), str(TARGET / f'{row}-{label}.text')], check=True)
        same = (TARGET / f'{row}-before.text').read_bytes() == (TARGET / f'{row}-after.text').read_bytes()
        clean &= same
        print(row, 'identical .text; measured row remains valid' if same else 'changed .text; remeasure required', flush=True)
    return 0 if clean else 1


if __name__ == '__main__':
    raise SystemExit(main())
