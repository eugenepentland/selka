# D9 Lox global hash before table update, 2026-09-26

`heap.set_global` now reads the name's hash before extracting `rt.globals`.
Previously the intervening `string_hash(rt, name)` observed the runtime after
that extraction, preventing the existing closed field-return proof from moving
the global table through `table.set`. Moving this read removes both emitted
COW transfers in this function: 2 become 0, and QBE IL shrinks from 458 to 399
lines. There is no compiler change.

The source change composes with `b8fdb39e`: corrected property RHS evaluation,
compact frames, scalar instance/class reads, indexed instance writes, and late
closure publication remain present. The patch is regenerated against the
corrected migration base and replays all 28 `.my` and `.json` files exactly.
The source differs from the pre-hoist composition only in `heap.set_global`.

## Evaluation order

`string_hash` reads the string object's stored hash. It does not mutate the
runtime or invoke a Lox callback. The hoist crosses only the local extraction
of the globals table; both versions finish the hash read before `table.set`
can mutate that table. A wrong object kind still asserts “object is not a
string”, and an invalid reference still traps with `R_LIST_BOUNDS` before the
update. Sixteen direct before/after probes cover these failures on QBE and
LLVM, each with native GC stress off and on. Source-line positions change
with the moved expression; the failure category and message are preserved.

## Matched instruction measurements

Both arms use frozen Debug compiler `5bdd99ea`, SHA
`ceb38b6e1fb1a23f20d92580b3cd7f07f635f5752311f27d477f9792e388b7d5`.
Guests use ReleaseFast; LLVM uses optimization level 3 and full LTO. The
mandated `pc.py` harness checks exact output and takes three alternating
instruction samples on CPU 11 at its calibrated sizes. These are source-only
ratios on the same compiler, not comparisons with historical 60b.

| VM case | Hoist / before QBE | Hoist / before LLVM |
| --- | ---: | ---: |
| method_call | 0.944058× | 0.896226× |
| closures | 0.903183× | 0.811133× |
| binary_trees | 0.999281× | 0.998655× |
| fib | 1.000000× | 1.000000× |
| trees | 0.999999× | 0.999998× |

All outputs pass. The method-call and closures improvements are consistent
with eliminating repeated global-table copies; the other cases are effectively
unchanged. [Raw measurements](evidence/d9-lox-global-hash-perf.json) include all
samples, build commands, source/compiler/binary identities, emitted function IL,
and measurement scripts. The older frozen compiler does not include the later
indexed-return proof; its exact same limitation applies to both arms. Final
integration performance requires the joined compiler and full 43-key sweep.

## Correctness validation and known stress failure

Validation uses a private copy of the joined Debug compiler with nested scopes
and the guarded indexed-return proof, SHA
`d733b14aca8b25b0d4fb2d1becda50c98c2ab0f8cfac342e22a204bc58c9d82c`.
Both value semantics and compatibility mode pass all 65 source tests with
normal GC: 130 executed, none cached. The native test runner uses Debug guests.
Standalone guests use ReleaseFast and LLVM O3 full LTO, and pass:

- 104 smoke runs: 13 programs, both engines, both backends and both modes.
- 184 exact VM error-trace comparisons against private historical baseline
  copies: 23 errors, both backends/modes, native GC stress throughout, with
  both Lox GC settings.
- 32 focused global-update observations, all printing `190`, across both
  engines/backends/modes and both native and Lox GC settings.
- 16 direct invalid-hash and bounds observations described above.

An additional full-port Debug-guest native GC-stress run is **not green**:
55 source tests pass and ten parser/resolver tests panic on a null native type
descriptor. The same ten fail with the older frozen `5bdd99ea` compiler.
Unchanged pre-hoist source reproduces all five resolver failures on both that
compiler and the joined compiler. This establishes that the hash hoist did not
introduce those failures; it does not establish whether they predate D9.
The compiler investigation and original-60b comparison are tracked separately.
The successful standalone stress checks above do not replace this failing
Debug-guest coverage.

[Validation evidence](evidence/d9-lox-global-hash-runs.json.gz) preserves exact
outputs, failure logs, commands, identities, replay hashes and scripts. Local
scratch is `d9-lox-frame-return/.tmp-frame-return/`. `build-hoist.py` and
`validate-joined.py` run through `scripts/build-slot.sh build`; the latter's
full-stress test stops on the recorded failure. `test-joined-normal.py` runs
the successful source tests and unchanged stress control. `check-joined-runs.py`
and `probe-hash.py` perform the standalone observations. `compose-hoist.py`
reconstructs and checks the migration patch. The root integration owns the
joined full gate and final performance acceptance; neither is claimed here.
