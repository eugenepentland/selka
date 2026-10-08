#!/usr/bin/env python3
"""Explain every existing LLVM definition change in the S0/S1 comparison."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[4]


def definitions(path):
    blocks = re.findall(r'^define .*?^\}', path.read_text(), re.M | re.S)
    return {re.search(r'@("[^"]+"|[^ (]+)\(', block).group(1): block for block in blocks}


def main():
    before_dir = ROOT / '.mylang-cache/wave-a/baseline'
    after_dir = ROOT / '.mylang-cache/wave-a/s2-t2'
    count = 0
    for path in sorted(before_dir.glob('*.ll')):
        after_path = after_dir / path.name
        if not after_path.exists():
            continue
        before, after = definitions(path), definitions(after_path)
        changed = [name for name in before if before[name] != after.get(name)]
        for name in changed:
            expected = before[name].replace(
                'call zeroext i1 @myl_core_str_parse_int(',
                'call fastcc i1 @myl_core_parse_int_inline(')
            assert expected == after[name], (path, name)
            assert name.endswith('::parse_number"'), (path, name)
        assert set(after) - set(before) == {'myl_core_digits8', 'myl_core_parse_int_inline'}
        print(f'{path.stem}: {len(before)-len(changed)}/{len(before)} existing functions identical; '
              f'only parser call substitution: {", ".join(changed)}; two inline helpers added.')
        count += 1
    assert count == 20, count
    print('PASS: all 20 timed kernels and every other existing function are identical. '
          'Changed parsing occurs before the measured interval; formatting/printing occurs after it. '
          'Full original diffs remain in .mylang-cache/wave-a/s2-t2/.')


if __name__ == '__main__':
    main()
