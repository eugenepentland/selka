# D9 WP-4: proposed bounded physical retain

This is a separate candidate after flat loans `c0a5904a`. Joined source
`636524b8` was measured against immutable accepted GC on the exact three
schematic inputs and unchanged Lox binary_trees N10. The parent and collections
worker reviewed this proof without blockers; the worker also reviewed the
implementation. [Joined profiles](d9-rc-flat-borrow-joined-2026-09-27.md) support a
bounded experiment but do not predict its overall gain. No semantic transfer, compiler loan,
allocator or public metadata ABI change is proposed.

## Admission and physical operation

Use only an already registered binding whose existing `flat.loanable` flag is
true, a nonzero native size, and disjoint source/destination ranges. The flag
proves at most eight unconditional ordinary O leaves and at most eight inline
levels, counting the root. It rejects raw unique fields, hooks, variants, H
leaves and typed box leaves with a native element (including NULL boxes). That
is deliberately stronger than `flat.count <= 8`: the latter alone does not
prove the existing native unique-content predicate false. Keeping the depth
bound preserves the generic transfer stack's possible allocation refusal.
Cold bindings, zero size, aliases/overlap and every refused shape keep the
original implementation.

`myl_rc_native_retain` is physical acquisition. It preserves every pointer's
identity and marks, including pinned pointers, and does not set arena SHARED.
It can acquire an ordinary owner from an O=0/H>0 payload. It must not call the
pin-aware copy fast path or semantic publication. Unlike native loan, the
generic physical retain does not reject a dynamic opaque pointee descriptor
with a finalizer; this candidate must preserve that distinction. Static raw
unique and typed box restrictions still use the proof above.

Validate the destination region before copying. On an invalid region, zero
every destination byte, then perform the existing final drain and record the
failure. Otherwise copy all bytes (including padding), zero the admitted owner
offsets, and visit leaves in the flat plan's original shape order. For each
nonnull pointer, check its common-header region against the destination region
before calling the unchanged `myl_rc_owner_acquire`. Publish that leaf only
after successful acquisition. Immortal and arena headers use the common header
and existing acquisition helper; no RC prefix is inferred for them.

Do not preflight all counts or regions together. A later count/region refusal
must preserve the acquired prefix, including repeated aliases and exact dynamic
limit counters. Roll back by clearing each admitted destination leaf and calling
the existing no-drain `myl_rc_edge_release` in the same order, zero the whole
destination, and drain once. Successful retain also drains once. Queue callbacks
therefore see the same completed or empty destination, sibling release order and
LIFO death order as the generic path. Publish sticky failure only after that
drain, preserving reentrant callback status precedence. Metadata bindings are
immutable; no binding storage is used after a callback can destroy the heap.

## Required controls

Compare old and new production C behavior with counters enabled: mixed plain
padding and O leaves; null/immortal/arena/pinned leaves; ownerless H lifetimes;
duplicate aliases near the dynamic owner limit; late region/count failures;
invalid destination region; cold metadata and exhausted metadata budget; zero
size and overlap refusal; depth nine/wide/variant/H and unique/finalized native
type negatives. Include a dynamically finalized payload behind an opaque
ordinary pointer as a success control, distinct from the typed unique negative.

Queued finalizers must observe an entirely published successful value or an
entirely zero failed value, may register metadata or reenter retain, and must not
run between prefix release and final whole-value zeroing. Preserve sticky first
failure behavior across that reentry. Check exact bytes, statuses, marks, O/H
counts and acquisition/release/limit counters, not only eventual live objects.
Run the existing loan/history/arena/collection production sanitizer suites and
actual QBE/LLVM guest controls. Keep the candidate only with material matched
improvement on an observed workload; static call-site applicability alone is
not evidence of a runtime benefit.

Expected edit scope is `native_rc_values.c` and a focused production fixture.
The existing flat plan and no-drain owner release suffice, so neither a private
layout nor a public ABI change is needed.
