# Managed payload liveness before mutable aggregate calls — 2026-09-26

Taking a record or fixed array's address now counts as a liveness use. Its
managed fields remain rooted across allocations before the address is formed,
even when its only future use passes it to a `mut` parameter.

The missing `ref_local` case in `qbe_liveness.uses` caused real data loss. In
the migrated Lox parser tests, `printed` constructed a Runtime, then called
`output.capture`, then passed the Runtime to `parser.parse` by address. The
Runtime was omitted from the roots during `output.capture`. GC reclaimed its
lists and reused two of their addresses for output buffers. Publishing the
Runtime again at the parser call was too late: the next collection scanned a
freed header and panicked on its null descriptor.

The fix adds `ref_local` alongside `load_local` and `move_local` in the shared
liveness analysis. It neither kills the old value nor changes the separate
rules that treat a mutable reference as a possible write when proving borrows
safe. The same final liveness solution feeds ownership, moves and GC roots.
Keeping a formerly missed use can conservatively retain a root or reject a
move; it does not relax a lifetime proof.

## Reproduction and historical boundary

The joined compiler `91d1311e`, SHA-256
`d733b14aca8b25b0d4fb2d1becda50c98c2ab0f8cfac342e22a204bc58c9d82c`,
failed `parser_test::test_parse_logical` with explicit native `--gc-stress`
in both semantic modes. The full migrated corpus previously passed 55 of 65
tests under these conditions; all five parser and all five resolver tests
failed. Normal tests and the separately exercised VM trace corpus did not
expose this missing root.

Exact `60b668cf` passes the same logical-parser test on the original class-based
source. It cannot directly compile the migrated source's scalar-only mutable
Scanner record, so that comparison alone does not date the defect. Independent
fixed-array controls do: a `[1]list[int]` used only by a later mutable call
returns a wrong result under native GC stress on exact `60b668cf`, while its
normal run succeeds. Adding an ordinary read after the intervening allocation
also makes it succeed. `ref_local` in `61a52cbc` and root liveness in
`15d72730` were developed on parallel branches. Their integration at
`0804a4cf` omitted the new instruction's liveness use. D9's mutable record
support made the existing omission visible in the migrated parser.

The permanent four-test guest fixture covers a record, a managed fixed array,
a reference reached through a forward branch and a forwarded mutable parameter.
Before the fix, three tests fail and the forwarded-parameter control passes.
A structural emitter test checks that the intervening allocation publishes the
record root in both semantic modes. Independent review also checks original
and corrected fixed-array controls and an unchanged migrated parser test.

## Validation

The frozen corrected compiler is Debug, based on `91d1311e`, SHA-256
`be46540cb7a3bb9f32efd04a394b0044f31339c450ba146f3226f18c43cb80ac`.

- Full serialized gate: 93/93 steps, 2120 main tests; QBE 428/428, build
  29/29 and format 2/2. Guardian's 88 checks pass without ratchet changes.
- Focused structural root suite: 17/17 tests, including the new root assertion
  in both semantic modes.
- Permanent guest regressions: four tests in each mode/backend, 16 fresh
  native-GC-stress passes. The old joined compiler fails three of the four.
- Full migrated Lox corpus: 65 tests in each mode/backend, 260 fresh
  native-GC-stress passes, with no skipped or dropped tests.
- Independent unchanged parser and historical array controls: 16/16 runs
  covering Debug QBE/LLVM, both semantic modes, normal and native GC stress.
- [All 44 legacy IL comparisons](evidence/d9-mut-reference-off-il.json)
  compile and match exact `60b668cf` byte for byte.

[Commands, outputs and compiler/source identities](evidence/d9-mut-reference-liveness-runs.json.gz)
record the focused and corpus checks. The native test CLI uses QBE Debug by
default and LLVM ReleaseFast, optimization level 3 and full LTO through
`--release`; the independent standalone controls additionally exercise Debug
LLVM. Every stress invocation passes the explicit runtime stress control,
rather than assuming the test runner inherits a guest option from its
environment. Independent historical/control evidence is committed separately
as `0e2dbc67`.

This is a correctness repair. Stage-3 performance acceptance must use a joined
compiler containing it and retain the complete 43-workload comparison.
