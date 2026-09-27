# Scalar-loop readiness reuse, 2026-09-27

This is a production compiler candidate, separate from the deliberately unsafe
constant-query diagnostic in `../d9-rc-scalar-readiness-audit-20260927/`.
It reuses a successful unchanged runtime query only inside a bounded closed
scalar loop. Each slow append clears the accounted flag before calling the
original helper. Capacity and generation are checked on every append.

The full report and proof are in
`docs/audits/d9-rc-scalar-readiness-reuse-2026-09-27.md` and
`docs/audits/d9-rc-scalar-readiness-plan-2026-09-27.md`.

## Identity and execution

Before source: `fbcd7978` (joined `4fd7bd63` plus the diagnostic/design archive).
The clean baseline worktree is `d9-rc-readiness-before-astra`. Both compilers are
Debug installs built through `scripts/build-slot.sh`, with independent private
Zig caches and disk scratch. Exact executable hashes are in `identity.json`.
The candidate's seven production files are hashed there; `source.patch.gz` contains
the complete compiler/test/SPEC delta. The native runtime implementation is
unchanged during these measurements.

Full mandated append, sieve and allocation-churn inputs, all three schematic
cases and unchanged N10 Lox binary_trees use actual QBE and LLVM O3/full LTO.
The QBE/LLVM selection is checked in every build manifest. Production
instruction measurements are alternating median-three executions on CPU3;
counting binaries run separately. All 84 raw instruction observations report
100% event running. Exact stdout and schematic SVG/empty issue output are checked
by the driver. All 28 counted observations retain exact before/after counters.
The archived GC references are from completed rows of the original accepted-GC
corpus experiment, **not** freshly interleaved GC samples.

## Checks

`verify.py --live` recomputes medians, verifies raw event running, exact paired
counters/output, 26 embedding pairs, 48 RC guest assertions and 24 default-GC stress
assertions, and checks current compiler/binary/input hashes. Without `--live`, it
checks the self-contained archive. The control build manifest has 32 binaries:
three schematic cases share one guest binary per compiler/backend/mode.

The heap-backed fixture has one 8-byte private flag, increasing the existing
conservative 2× frame reservation from 787584 to 787600 bytes. Its first local moves
by 8 bytes; the physical flag never overlaps a journal/operand/receiver slot.

`embedding.c` calls generated libraries through the real runtime, with a wrapper
around the production allocation hook. It checks:

1. Guest reentry while a finalizer has queued a sibling: the sibling stays deferred.
2. Backing growth after cached room appends queues a finalizer, which observes
   length 8 before append publication and registers new metadata.
3. Generation exhaustion and custom allocation refusal after earlier room spans.
4. A heap-backed generated frame, zero iterations and an indexed-write fallback.
5. Byte refusal before the first allocation and during growth; step refusal before
   the first append and after earlier appends; physical floor and logical depth.

Trap code, consumed logical steps, visible observations and counters match both
compilers on both backends. The indexed-write source conservatively remains
unadmitted because its capture/COW hooks fail the new proof; it is a fallback
control, not claimed fast-path coverage. The positive emitted fixtures include
integer widths, float bits, boolean comprehension, repeated dynamic lifetimes,
growth and a fresh receiver inherited from the caller's arena.

Focused tests pass 14 (three named and 11 common blocks). Their structural checks
exercise actual `qbe_cow.Lower.enters`, emitted CE/reset/internal-backedge routing,
lazy query placement, pre-slow invalidation, caller/callback/snapshot/managed
refusal and heap-frame addressing. Whole-tree Guardian 88 passes. Root owns the
full integration gate and feedback log.

## Negative/development evidence

`development/` and logs retain the failed initial harness assumptions: reducing
a live heap ceiling to its current byte charge can still succeed after allocator
trimming; forcing a small leaf's physical floor does not exercise the floor
check that it legitimately omits. Final controls tighten the growth ceiling to 1
and apply the floor refusal to the wide heap-frame function. No runtime change
was made to satisfy these probes. Initial Lox command misuse (`emit-qbe --project`)
is preserved; the corrected command is `emit-project-qbe`. Initial emission
comparison expected no Lox changes; actual code changes only
`object::new_closure` out of 405 functions, so full N10 was measured and remains
neutral. Final proof/tests are unchanged by these harness corrections.

No acceptance threshold, default runtime, ABI, count limit, frame safety margin,
benchmark source/input or Guardian ratchet changed. Scalar gains are material;
remaining GC instruction gaps still fail Stage 4 acceptance.
