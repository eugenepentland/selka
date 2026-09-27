# D9 WP-4: scalar field replacement without a pending token

This isolated slice starts from cumulative `89e79524`, real-merged as `178dd0e7`.
It changes only `qbe_rc_aggregate.replace`. The runtime, journal ABI, allocation,
receiver preparation and compiler ownership plans are unchanged.

## Opportunity and bounded proof

A plain scalar field previously loaded into `rcwork`, published a typed pending
entry with flags zero and guard one, blitted its bytes into the field and cleared
the pending guard. Neither the old field nor the replacement had a destructor or
counted edge. Nevertheless every update emitted address/type/flag/guard stores.
The exact nbody `advance` function contains nine such static float replacements.
Emission receipts confirm nine live publications become zero while all 164 native
call sites remain. The QBE body decreases from 102,902 to 98,970 bytes. LLVM
inlines `advance` into `main` in both binaries; the archived native disassembly
therefore records that caller, rather than claiming a separate function survived.

The new arm requires all of the following existing native facts:

- The field type has neither counted edges nor unique-drop obligations.
- The emitter represents the complete field in one scalar register.
- The validated field layout has nonzero size.

It then uses the same `readValue` and `writeValue` primitives as the existing plain
initializer. The source is fully loaded before the destination is written, so
both exact alias and overlapping source/destination bytes are safe. These
primitives retain signed/narrow integer loads, boolean width, float bits and
scalar-domain representation. The change does not replace the type/layout
validation or domain construction checks.

Pending ownership is clear at entry: base preparation consumes its pending value
before exposing the update storage, and each preceding replacement clears its
pending guard. A direct plain base never publishes pending ownership. The new
arm leaves that guard clear, so its stale inactive descriptor is immaterial.
Successive plain and managed fields retain this invariant. No callback,
allocation, fallible helper or ownership release separates the scalar load and
store. The previous zero-edge arm also had no runtime call or drain to preserve.

The caller still prepares or detaches the parent before entering `replace`.
Indexed bounds checks, captured receiver scopes and all RHS evaluation remain
in the same order. A callback that replaces or grows the receiver finishes before
the new field value is stored. Ordinary input cleanup and result publication
continue in the existing `finish` path.

Managed pointer scalars and H-containing values fail the counted check. Raw
unique resources fail the unique-drop check. Inline aggregates and zero-sized
fields retain the exact previous staging path. This admission does not depend on
semantic mutability, the absence of SHARE, or the current pending descriptor.

## Controls and validation

The immutable Debug control compiler is
`d9-rc-integration/.tmp-rc/install-argv-return/bin/mylang`, SHA-256
`bcdf4c7dde9385a1d4b7306a35a5178fdbb04fecb55487a7759993b1574e1dae`.
The candidate is `d9-rc-mut-argument-astra/.tmp-mut-argument/scalar-candidate/bin/mylang`,
SHA-256 `4b52074edede1d094873e91632851651311f147725a55270fc2582513c0f0e5a`.

Focused code-generation tests check that float/bool/narrow-integer field updates
emit no live pending token, retain width-specific stores and retain the indexed
bounds failure path. Another test verifies that plain aggregate and zero-sized
field replacements still emit their two pending publications. Existing managed
field refusal tests remain green. Runtime fixtures cover scalar domains, snapshots,
self assignment, mixed plain/managed/aggregate fields, callback replacement and
an older receiver updated inside an arena. Before/after GC-stress and counted RC
runs compare both actual backends. Bounds and arithmetic failures compare located
errors and balanced ownership traffic after earlier successful field updates.

The complete focused RC unit suite passes 131/131. Actual guest tests pass
33 assertions per backend. All 16 standalone before/after rows pass: eight
GC-stress/RC successes and eight located bounds/arithmetic failures, with exact
count parity. The final whole-tree Guardian run passes all 88 checks.

## Exact-workload measurement

The input is the unmodified `bench/parity/suite/nbody.my`, including all 5,000,000
steps. Native binaries use actual QBE and LLVM O3/full LTO, built by the immutable
Debug compiler pair. CPU 2 samples alternate before/after order and report the
median of three retired-instruction counts. Full outputs, identities, manifests,
commands and individual samples are archived with the experiment.

| Backend | Before instructions | After | Ratio |
| --- | ---: | ---: | ---: |
| QBE | 71,840,259,213 | 67,495,258,572 | 0.939519 |
| LLVM O3/full LTO | 21,595,250,400 | 16,580,249,575 | 0.767773 |

The full output matches exactly on both backends: `-169075163\n-169083133\n`.
Every counter matches exactly: two heap allocations and retirements, ordinary
acquire/release 1/3, hold acquire/release 10,000,005 each, 10,000,007 uniqueness
checks, no clones and no arena allocations. This is one isolated change, not a
claim that WP-4's matched corpus performance gate has been met.

Evidence is in `experiments/d9-rc-scalar-replace-20260927/`. The initial Guardian
run correctly rejected a duplicate primary spec tag and a five-operation boolean
condition; using a spec-case and two bounded conditions resolved both without
changing any ratchet. A first validation driver used the unsupported spaced
`run --cache-dir PATH` spelling; the corrected `--cache-dir=PATH` receipts are
kept separately from that CLI refusal.
