#!/usr/bin/env python3
"""Counterfactual IL rewrite over an `emit-project-qbe` manifest: remove classes of safety checks.

usage: strip_il.py in.json out.json CATEGORY[,CATEGORY...]
categories:
  overflow  -> myl_qbe_fail_overflow_op, myl_qbe_int_neg (neg overflow), myl_qbe_fail_division
  cast      -> myl_qbe_fail_cast
  bounds    -> myl_qbe_fail_index_bounds, myl_qbe_fail_normalized_index_bounds, myl_qbe_fail_array_bounds, myl_qbe_fail_text_bounds_detail
  alloc     -> myl_qbe_fail_allocation, myl_qbe_fail_list_capacity, myl_qbe_fail_iteration, myl_qbe_fail_equality
  frames    -> frame record link/unlink, stack-floor check, metadata store (patch_frames.py mode F)
  positions -> `storel N, %position` stores (mode P)
  trap      -> sticky `loadl %trap` tests after calls (mode T)
A guarded check is a `jnz %c, @X, @Y` where one target block is exactly
[optional `storel N, %position`] `call $FAIL(...)` `jmp @failure|@entry_failure`; the jnz becomes `jmp @other`.
Diagnostic only: a stripped program cannot report the removed failures.
"""
import json, re, sys

CATEGORIES = {
    'overflow': {'myl_qbe_fail_overflow_op', 'myl_qbe_int_neg', 'myl_qbe_fail_division'},
    'cast': {'myl_qbe_fail_cast'},
    'bounds': {'myl_qbe_fail_index_bounds', 'myl_qbe_fail_normalized_index_bounds', 'myl_qbe_fail_array_bounds', 'myl_qbe_fail_text_bounds_detail'},
    'alloc': {'myl_qbe_fail_allocation', 'myl_qbe_fail_list_capacity', 'myl_qbe_fail_iteration', 'myl_qbe_fail_equality'},
}


def blocks_of(lines):
    """Map label -> (start_index, end_index_exclusive) over the IL line list."""
    out = {}
    current = None
    start = 0
    for i, line in enumerate(lines):
        if line.startswith('@'):
            if current is not None:
                out[current] = (start, i)
            current = line.strip()
            start = i + 1
    if current is not None:
        out[current] = (start, len(lines))
    return out


def failure_helper(lines, span):
    """If the block is a pure failure block, return the helper it calls."""
    body = [l for l in lines[span[0]:span[1]] if l.strip()]
    if len(body) < 2 or len(body) > 3:
        return None
    if len(body) == 3 and not re.match(r' storel \d+, %position$', body[0]):
        return None
    m = re.match(r' call \$(\w+)\(', body[-2])
    if not m or not re.match(r' jmp @(failure|entry_failure)$', body[-1]):
        return None
    return m.group(1)


def strip_checks(il, helpers):
    lines = il.split('\n')
    blocks = blocks_of(lines)
    removed = 0
    out = []
    for line in lines:
        m = re.match(r' jnz (%\w+), (@\w+), (@\w+)$', line)
        if m:
            _, a, b = m.groups()
            for fail, keep in ((a, b), (b, a)):
                if fail in blocks:
                    helper = failure_helper(lines, blocks[fail])
                    if helper in helpers:
                        out.append(f' jmp {keep}')
                        removed += 1
                        break
            else:
                out.append(line)
            continue
        out.append(line)
    return '\n'.join(out), removed


def strip_frames(il, mode):
    lines = il.split('\n'); out = []
    rec = act = pos_slot = None; skip_until = None; removed = 0
    for L in lines:
        m = re.match(r' %v(\d+) =l alloc8 32$', L)
        if m and rec is None: rec = m.group(1)
        m = re.match(r' %v(\d+) =l add %ctx, 48$', L)
        if m: act = m.group(1)
        if rec and (m := re.match(rf' %v(\d+) =l add %v{rec}, 16$', L)): pos_slot = m.group(1)
        if 'F' in mode:
            if skip_until:
                if L.startswith(skip_until): skip_until = None; out.append(L)
                removed += 1; continue
            if re.match(r' %v\d+ =l add %ctx, 64$', L):
                skip_until = '@stackadmit'; removed += 1; continue
            if act and re.match(rf' %v\d+ =l loadl %v{act}$', L): removed += 1; continue
            if act and rec and re.match(rf' storel %v\d+, %v{rec}$', L): removed += 1; continue
            if re.match(r' storel extern \$\S+_meta, %v\d+$', L): removed += 1; continue
            if pos_slot and L == f' storel 0, %v{pos_slot}': removed += 1; continue
            if act and rec and L == f' storel %v{rec}, %v{act}': removed += 1; continue
            if act and re.match(rf' storel %v\d+, %v{act}$', L): removed += 1; continue
            if rec and re.match(rf' %v\d+ =l loadl %v{rec}$', L): removed += 1; continue
        if 'T' in mode:
            if re.match(r' %v\d+ =l loadl %trap$', L): removed += 1; continue
            if (m := re.match(r' jnz %v\d+, @failure, @ok(\d+)$', L)): out.append(f' jmp @ok{m.group(1)}'); removed += 1; continue
        if 'P' in mode and re.match(r' storel \d+, %position$', L): removed += 1; continue
        out.append(L)
    return '\n'.join(out), removed


def main():
    src, dst, cats = sys.argv[1], sys.argv[2], sys.argv[3].split(',')
    d = json.load(open(src))
    helpers = set()
    mode = ''
    for c in cats:
        if c in CATEGORIES: helpers |= CATEGORIES[c]
        elif c == 'frames': mode += 'F'
        elif c == 'positions': mode += 'P'
        elif c == 'trap': mode += 'T'
        else: raise SystemExit(f'unknown category {c}')
    total = {'checks': 0, 'frame_lines': 0}
    for f in d['functions']:
        il = f['il']
        if helpers:
            il, n = strip_checks(il, helpers); total['checks'] += n
        if mode:
            il, n = strip_frames(il, mode); total['frame_lines'] += n
        f['il'] = il
    json.dump(d, open(dst, 'w'))
    print(f"{','.join(cats)}: guarded checks removed {total['checks']}, frame/position lines removed {total['frame_lines']}")


if __name__ == '__main__':
    main()
