#!/usr/bin/env python3
"""Generate isolated LLVM floor-result range experiments, without source edits."""
import argparse
from pathlib import Path

DIVISORS = (1, 2, 3, 1000000007, 9223372036854775807)
LOOP_DIVISORS = (3, 1000000007, 9223372036854775807)
VARIANTS = ('baseline', 'assume', 'select', 'select_assume')


def correction(divisor, variant, dividend):
    lines = [f'  %rem = srem i64 {dividend}, {divisor}',
             '  %nonzero = icmp ne i64 %rem, 0',
             f'  %difference = xor i64 %rem, {divisor}',
             '  %negative = icmp slt i64 %difference, 0',
             '  %condition = and i1 %nonzero, %negative']
    if variant.startswith('select'):
        # Wrapping add: the unselected positive remainder plus a large divisor
        # may overflow. No nsw/nuw is asserted on this instruction.
        lines += [f'  %shifted = add i64 %rem, {divisor}',
                  '  %result = select i1 %condition, i64 %shifted, i64 %rem']
    else:
        lines += ['  %wide = zext i1 %condition to i64',
                  '  %mask = sub i64 0, %wide',
                  f'  %delta = and i64 {divisor}, %mask',
                  '  %result = add i64 %rem, %delta']
    if 'assume' in variant:
        # This applies to the final corrected result, never to raw signed rem.
        lines += [f'  %bounded = icmp ult i64 %result, {divisor}',
                  '  call void @llvm.assume(i1 %bounded)']
    return '\n'.join(lines)


def scalar(divisor, variant):
    return (f'define i64 @scalar_{variant}_d{divisor}(i64 %value) nounwind noinline {{\n'
            'entry:\n' + correction(divisor, variant, '%value') +
            '\n  ret i64 %result\n}\n')


def loop(divisor, variant, shape):
    initial = '%seed' if shape == 'seeded_bool' else '0'
    load = ('  %address = getelementptr i64, ptr %data, i64 %index\n'
            '  %increment = load i64, ptr %address, align 8' if shape == 'signed_updates' else
            '  %address = getelementptr i8, ptr %data, i64 %index\n'
            '  %flag = load i8, ptr %address, align 1\n'
            '  %truth = icmp ne i8 %flag, 0\n'
            '  %increment = zext i1 %truth to i64')
    return f'''define i64 @loop_{shape}_{variant}_d{divisor}(ptr %data, i64 %count, i64 %seed, ptr %status) nounwind noinline {{
entry:
  store i32 0, ptr %status, align 4
  %empty = icmp eq i64 %count, 0
  br i1 %empty, label %empty_exit, label %loop
empty_exit:
  ret i64 {initial}
loop:
  %index = phi i64 [0, %entry], [%next, %success]
  %checksum = phi i64 [{initial}, %entry], [%result, %success]
{load}
  %addition = call {{i64, i1}} @llvm.sadd.with.overflow.i64(i64 %checksum, i64 %increment)
  %sum = extractvalue {{i64, i1}} %addition, 0
  %overflow = extractvalue {{i64, i1}} %addition, 1
  br i1 %overflow, label %failure, label %success
failure:
  store i32 1, ptr %status, align 4
  ret i64 0
success:
{correction(divisor, variant, '%sum')}
  %next = add i64 %index, 1
  %done = icmp eq i64 %next, %count
  br i1 %done, label %exit, label %loop
exit:
  ret i64 %result
}}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    source = ['; Isolated experiment. No production or benchmark changes.\n'
              '; Positive literal divisors; assumptions only after floor correction.\n'
              'declare void @llvm.assume(i1)\n'
              'declare {i64, i1} @llvm.sadd.with.overflow.i64(i64, i64)\n']
    source += [scalar(d, v) for d in DIVISORS for v in VARIANTS]
    source += [loop(d, v, s) for d in LOOP_DIVISORS for s in
               ('zero_bool', 'seeded_bool', 'signed_updates') for v in VARIANTS]
    args.output.write_text('\n'.join(source))
    print('Generated20 scalar+36 loop functions')


if __name__ == '__main__':
    main()
