# Mutable-reference root liveness: provenance and independent review

The missing `ref_local` liveness use predates D9's copy-scratch and variant
payload optimizations. The independent controls below date the defect to the
integration of fixed-array references with selective GC roots. D9's migrated
Lox records exposed that existing omission.

## Historical boundary

Root liveness was introduced on its own branch in `15d72730`
(2026-09-22 21:13:45 UTC). Fixed-array `mut` parameters introduced `ref_local`
on a parallel branch in `61a52cbc` (21:24:01 UTC). Neither commit contains the
other. Integration merged root liveness at `21c8c63f` (22:14:49 UTC), then
fixed arrays at `0804a4cf` (22:14:57 UTC). The latter tree contains both
features but `qbe_liveness.uses` still recognizes only `load_local` and
`move_local` in that case. This is a source-history finding; those intermediate
commits were not rebuilt during this audit.

`51dba1bd` subsequently extended reference passing to plain records under
value semantics. `18d66f92` (also applied as `d305a5df`) enabled explicit
mutable-record writeback in both modes. Neither is the origin of the
fixed-array liveness omission.

Two native controls confirm the earlier defect:

| Frozen compiler | Source and mode | Explicit native GC stress |
| --- | --- | --- |
| Exact `60b668cf`, SHA `48427e9ac1c01b74e60d1b4c098c8fc149a6b5fef3c07e110c7fb4ba16cbb545` | `[1]list[int]` used only by a later mutable call | Wrong result: expected true, got false |
| `9f42e5a9`, SHA `76a141ef6bfb0d9f94759a49a8608d561186c661c172d1288e68d49aeb6b9790` | Migrated `parser_test::test_parse_logical`, value semantics on | Abort: member access through null `myl_native_type` |
| Same `9f42e5a9` | Same migrated test, value semantics off | Compile rejection of scalar mutable Scanner; no runtime result |

The successful compilation and runtime failure in the second row precede
`adcbb4ca`'s scratch/alias initialization changes and `f8dad8e8`'s variant
payload changes. The third row must not be interpreted as a runtime control.
The independent fixed-array normal/stress comparisons and corrected parser
retests are recorded by the fix owner and its second reviewer.

## Independent fix review

The reviewed production change adds `ref_local` to the shared liveness use
set. This grows live-in/live-out sets before the reference and leaves
definition kills and control-flow edges unchanged. It also corrects ownership
decisions: `ownership_cow` and `ownership_classify` require no later live use
before treating a read as a last-use move. A future mutable reference must
prevent that move.

`qbe_moves`, `qbe_borrow`, and `ownership_roles` already treat `ref_local` as
a possible write or mutation. The fix does not relax those checks. Once the
address is on the operand stack, `qbe_roots` traces the aggregate at that
address, including during allocation by a later call argument. Forwarded
mutable parameters are traced through the caller's storage.

One distinct adversarial check combines an earlier snapshot, an intervening
allocation, a mutable reference to the original, and an allocating later
argument. It verifies that appending through the reference preserves the
snapshot. With frozen corrected Debug compiler SHA
`be46540cb7a3bb9f32efd04a394b0044f31339c450ba146f3226f18c43cb80ac`,
the test passes on QBE Debug and LLVM ReleaseFast (optimization 3, full LTO),
both with value semantics and explicit `--gc-stress`. No ownership, move, or
borrow safety concern was found in this review.

## Reproduction and evidence

Commands, full compiler hashes, source hashes, probe sources, and output are
preserved in [the evidence JSON](evidence/d9-mut-reference-history.json).
The private scratch directory is
`mylang-worktrees/d9-lox-stress-history/.tmp-history/`:

```sh
scripts/build-slot.sh build python3 .tmp-history/check-9f.py
scripts/build-slot.sh build python3 .tmp-history/check-fixed.py
```

The historical parser script runs only `test_parse_logical`; the corrected
script runs only the independent snapshot/reference check. Both pass the
native test CLI's explicit `--gc-stress` flag and use private caches. Setting
`MYLANG_OPTIONS=--gc-stress` alone is not equivalent for `mylang test`.

This audit changes no compiler or accepted Lox source. The fix owner runs the
full gate, complete stressed Lox corpus, and joined legacy-IL comparison.
