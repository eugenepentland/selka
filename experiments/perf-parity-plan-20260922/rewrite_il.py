#!/usr/bin/env python3
"""Counterfactual rewrites of an emitted mylang manifest: price one language rule at a time.

usage: rewrite_il.py IN.json OUT.json CATEGORY[,CATEGORY...]

A manifest from `mylang emit-qbe PROG.my --drop-debug --drop-step-checks
--drop-frame-checks` rebuilt with `mylang build PROG.my --manifest-file=...`
is byte-identical to a plain `mylang build`, so any difference after a rewrite
is the rewrite. Every rewritten binary is a diagnostic: it cannot report the
failures or keep the guarantees it no longer implements. Output must still be
checked against the reference.

Check categories (a guarded `jnz` whose failure block is only
[`storel N, %position`] `call $FAIL` `jmp @failure` becomes a `jmp` to the
surviving successor; from experiments/schematic-parity-gap-20260922/scripts/strip_il.py):
  overflow   integer add/sub/mul/neg overflow and division traps
  cast       narrowing integer casts
  bounds     list, bytes, fixed-array and text index bounds
  iter       the list-length-unchanged test a `for x in xs` loop makes twice per iteration
  alloc      allocation and capacity refusals, equality depth
Protocol categories:
  frames     frame record link/unlink, stack-floor test, metadata store
  positions  every `storel N, %position`
  trap       sticky `loadl %trap` tests after calls
New in this audit:
  nan        the canonical-NaN branch after every float +,-,*,/ (and the position
             store that only exists to precede it): IEEE results pass through as-is
  roots      every GC root-record push and the root-chain restore (sound only
             with `nogc`: the collector then never runs, so no root is read)
  noreturn   end every `call $myl_qbe_fail_*` path in `hlt` (LLVM `unreachable`) instead of
             `jmp @failure`: in an executable the fail helper longjmps to the entry
             trampoline and never returns, so this is the sound lowering, not a strip
  negidx     Python negative-index normalization (`if i < 0: i += len(xs)`, which the
             frontend emits before a list/text index): the branch is never taken, so a
             negative index fails the unsigned bounds check instead of wrapping around
  nogc       store SIZE_MAX into the heap's next-collection threshold wherever a
             function fetches the heap, so no collection ever runs
"""
import json
import re
import sys

CHECKS = {
    'overflow': {'myl_qbe_fail_overflow_op', 'myl_qbe_int_neg', 'myl_qbe_fail_division'},
    'cast': {'myl_qbe_fail_cast'},
    'bounds': {'myl_qbe_fail_index_bounds', 'myl_qbe_fail_normalized_index_bounds',
               'myl_qbe_fail_array_bounds', 'myl_qbe_fail_text_bounds_detail'},
    'iter': {'myl_qbe_fail_iteration'},
    'alloc': {'myl_qbe_fail_allocation', 'myl_qbe_fail_list_capacity', 'myl_qbe_fail_equality'},
}
# offsetof(myl_native_heap, next_collection) in src/native_heap.h (segments,
# pending, roots, bytes, owned_capacity, pool_owners, pool_slots,
# next_pool_identity, objects_live, allocations, collections, limit, next_collection)
NEXT_COLLECTION_OFFSET = 96


def blocks_of(lines):
    out, current, start = {}, None, 0
    for i, line in enumerate(lines):
        if line.startswith('@'):
            if current is not None:
                out[current] = (start, i)
            current, start = line.strip(), i + 1
    if current is not None:
        out[current] = (start, len(lines))
    return out


def failure_helper(lines, span):
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
    removed, out = 0, []
    for line in lines:
        m = re.match(r' jnz (%\w+), (@\w+), (@\w+)$', line)
        if m:
            _, a, b = m.groups()
            for fail, keep in ((a, b), (b, a)):
                if fail in blocks and failure_helper(lines, blocks[fail]) in helpers:
                    out.append(f' jmp {keep}')
                    removed += 1
                    break
            else:
                out.append(line)
            continue
        out.append(line)
    return '\n'.join(out), removed


def strip_frames(il, mode):
    lines = il.split('\n')
    out = []
    rec = act = pos_slot = skip_until = None
    removed = 0
    for L in lines:
        m = re.match(r' %v(\d+) =l alloc8 32$', L)
        if m and rec is None:
            rec = m.group(1)
        m = re.match(r' %v(\d+) =l add %ctx, 48$', L)
        if m:
            act = m.group(1)
        if rec and (m := re.match(rf' %v(\d+) =l add %v{rec}, 16$', L)):
            pos_slot = m.group(1)
        if 'F' in mode:
            if skip_until:
                if L.startswith(skip_until):
                    skip_until = None
                    out.append(L)
                removed += 1
                continue
            if re.match(r' %v\d+ =l add %ctx, 64$', L):
                skip_until = '@stackadmit'
                removed += 1
                continue
            if act and re.match(rf' %v\d+ =l loadl %v{act}$', L):
                removed += 1; continue
            if act and rec and re.match(rf' storel %v\d+, %v{rec}$', L):
                removed += 1; continue
            if re.match(r' storel extern \$\S+_meta, %v\d+$', L):
                removed += 1; continue
            if pos_slot and L == f' storel 0, %v{pos_slot}':
                removed += 1; continue
            if act and rec and L == f' storel %v{rec}, %v{act}':
                removed += 1; continue
            if act and re.match(rf' storel %v\d+, %v{act}$', L):
                removed += 1; continue
            if rec and re.match(rf' %v\d+ =l loadl %v{rec}$', L):
                removed += 1; continue
        if 'T' in mode:
            if re.match(r' %v\d+ =l loadl %trap$', L):
                removed += 1; continue
            if (m := re.match(r' jnz %v\d+, @failure, @ok(\d+)$', L)):
                out.append(f' jmp @ok{m.group(1)}')
                removed += 1
                continue
        if 'P' in mode and re.match(r' storel \d+, %position$', L):
            removed += 1
            continue
        out.append(L)
    return '\n'.join(out), removed


NAN_JNZ = re.compile(r' jnz (%v\d+), @nan(\d+), @finite(\d+)$')


def strip_nan(il):
    lines = il.split('\n')
    out, removed, positions = [], 0, 0
    for i, line in enumerate(lines):
        m = NAN_JNZ.match(line)
        if m and m.group(2) == m.group(3):
            out.append(f' jmp @finite{m.group(3)}')
            removed += 1
            continue
        if re.match(r' storel \d+, %position$', line):
            # drop a position store whose next control or call event is a NaN branch
            j = i + 1
            only_for_nan = False
            while j < len(lines):
                nxt = lines[j]
                if nxt.startswith('@') or ' call ' in nxt or nxt.startswith(' jmp') or nxt.startswith(' ret'):
                    break
                if NAN_JNZ.match(nxt):
                    only_for_nan = True
                    break
                if nxt.startswith(' jnz'):
                    break
                j += 1
            if only_for_nan:
                positions += 1
                continue
        out.append(line)
    return '\n'.join(out), removed, positions


def strip_roots(il):
    lines = il.split('\n')
    derived = set()          # temps computed as %rootN + k
    heap_top = set()         # temps computed as %heap + 16 (the root chain head)
    out, removed = [], 0
    for L in lines:
        m = re.match(r' (%v\d+) =l add (%root\d+), \d+$', L)
        if m:
            derived.add(m.group(1))
        m = re.match(r' (%v\d+) =l add %heap, 16$', L)
        if m:
            heap_top.add(m.group(1))
        m = re.match(r' storel (\S+), (%\w+)$', L)
        if m:
            value, dest = m.groups()
            if re.fullmatch(r'%root\d+', dest) or dest in derived:
                removed += 1
                continue
            if dest in heap_top and (re.fullmatch(r'%root\d+', value) or value == '%root_mark'):
                removed += 1
                continue
        out.append(L)
    return '\n'.join(out), removed


def strip_negidx(il):
    """Skip the frontend's `if index < 0: index += len(receiver)` block.

    Shape: `jnz %c, @nextN, @iM` where the source text between `@nextN` and `@iM`
    converts the receiver length with the int cast check (`cugtl ..,
    9223372036854775807`) and the block at `@iM` is followed, within a few lines,
    by an index-bounds failure helper. The jnz becomes `jmp @iM`.
    """
    lines = il.split('\n')
    labels = {l.strip(): i for i, l in enumerate(lines) if l.startswith('@')}
    out, removed = [], 0
    for line in lines:
        m = re.match(r' jnz (%v\d+), (@next\d+), (@i\d+)$', line)
        if m:
            a, b = m.group(2), m.group(3)
            ia, ib = labels.get(a), labels.get(b)
            if ia is not None and ib is not None and ia < ib:
                between = '\n'.join(lines[ia:ib])
                after = '\n'.join(lines[ib:ib + 16])
                if 'cugtl' in between and '9223372036854775807' in between and (
                        'normalized_index_bounds' in after or 'text_bounds' in after or 'index_bounds' in after):
                    out.append(f' jmp {b}')
                    removed += 1
                    continue
        out.append(line)
    return '\n'.join(out), removed


def fail_noreturn(il):
    lines = il.split('\n')
    out, changed = [], 0
    for i, line in enumerate(lines):
        if re.match(r' jmp @(failure|entry_failure)$', line) and i > 0 and re.match(r' call \$myl_qbe_fail_\w+\(', lines[i - 1]):
            out.append(' hlt')
            changed += 1
            continue
        out.append(line)
    return '\n'.join(out), changed


def inject_nogc(il):
    lines = il.split('\n')
    for i, L in enumerate(lines):
        if re.match(r' %heap =l call \$myl_qbe_heap\(l %ctx\)$', L):
            lines.insert(i + 1, f' %nogc_slot =l add %heap, {NEXT_COLLECTION_OFFSET}')
            lines.insert(i + 2, ' storel -1, %nogc_slot')
            return '\n'.join(lines), True
    return il, False


def main():
    src, dst, cats = sys.argv[1], sys.argv[2], [c for c in sys.argv[3].split(',') if c]
    d = json.load(open(src))
    helpers, mode = set(), ''
    for c in cats:
        if c in CHECKS:
            helpers |= CHECKS[c]
        elif c == 'frames':
            mode += 'F'
        elif c == 'positions':
            mode += 'P'
        elif c == 'trap':
            mode += 'T'
        elif c in ('nan', 'roots', 'nogc', 'negidx', 'noreturn'):
            pass
        else:
            raise SystemExit(f'unknown category {c}')
    stats = {'checks': 0, 'frame_lines': 0, 'nan_branches': 0, 'nan_positions': 0, 'root_stores': 0, 'negidx': 0, 'noreturn': 0, 'nogc': False}
    for f in d['functions']:
        il = f['il']
        if helpers:
            il, n = strip_checks(il, helpers)
            stats['checks'] += n
        if 'noreturn' in cats:
            il, n = fail_noreturn(il)
            stats['noreturn'] += n
        if 'negidx' in cats:
            il, n = strip_negidx(il)
            stats['negidx'] += n
        if 'nan' in cats:
            il, n, p = strip_nan(il)
            stats['nan_branches'] += n
            stats['nan_positions'] += p
        if mode:
            il, n = strip_frames(il, mode)
            stats['frame_lines'] += n
        if 'roots' in cats:
            il, n = strip_roots(il)
            stats['root_stores'] += n
        if 'nogc' in cats:
            # every function that fetches the heap disables the trigger, so no
            # collection can run before the first one does
            il, ok = inject_nogc(il)
            stats['nogc'] = stats['nogc'] or ok
        f['il'] = il
    json.dump(d, open(dst, 'w'))
    print(json.dumps({'categories': cats, **stats}))


if __name__ == '__main__':
    main()
