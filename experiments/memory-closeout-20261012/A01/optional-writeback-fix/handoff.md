# Owned optional field writeback

Base: `50ac68c1f695f5f2cc461b55c44a99e5e59a2a90`, branch
`codex/memory-closeout-20261012-A01-optional`. Proposed commit: the commit
containing this handoff. This is a scoped fix, not final C1/C2/C3 qualification.

Owned files changed: `src/core/single_owner.zig`, `src/core/build.zig`, new
`src/core/optional_writeback.zig` and `src/core/a01_optional_writeback_test.zig`.
The coordinator authored the exact test import in `src/core/root_test.zig`.
No typed schema, source syntax, runtime ABI, COW path or generic variant move
rule changed. Return the temporary Core file reservations to the coordinator
or A07 after integration. A05's independent callTarget change does not overlap.

## Behavior and ownership proof

An owning mutable `Option<Node>` can update its scalar or managed record fields
after an `is not None` guard. Previously the generated `Some(update(payload))`
was treated as a move of a borrowed payload. The checker now recognizes only
the exact same-owner reconstruction: matching optional type and Some tag,
hidden mutable receiver, exact defensive narrowing block, available writable
root, and an already-staged RHS. Nested record fields are bounded to 64 steps.

Core independently checks the receiver place's root, single payload step, tag
and current version. It emits the existing `union_take` after RHS evaluation
and the final presence refresh, then uses that transferred payload for the
record update and reconstructed Some. Ownership classifies `union_take` as
consuming its operand. The existing recursive box emitter loads the payload
into independent storage and frees only the old box shell. The final SSA
assignment installs the new union, so the old owner has no second destruction.
Unboxed optional payloads use the same complete transfer without shell storage.

Ordinary mode bypasses the new transfer path and retains its previous behavior.
Arbitrary borrowed payload reconstruction, other owners/tags, and overlapping
RHS mutation remain rejected. No implicit copy was introduced.

## Validation

The final registered group passed **4/4**. Its native fixture passes release,
unoptimized debug, verified release, optimized debug, and release without facts;
each run checks expected results, all RC counters zero, exit-live managed bytes
zero, LLVM cleanliness and absence of legacy native symbols. The ordinary
pre-retirement native control also passes but is not counted as zero-RC evidence.

Coverage includes recursive managed siblings, independent whole copies, nested
record field writes, scalar augmented writes, repeated string/list replacement,
loop break, replacing the whole optional, mutable parameters, continued reads
after reconstruction, None paths, early return, error return and a failing
explicitly staged `try`. Four source refusal controls and seven malformed
metadata controls preserve the narrow boundary.

The separate raw verified-release run of `main.my` reports **453 allocations,
453 frees, 31,968 cumulative allocation bytes, zero reallocations, 2,752 peak
live managed bytes, and zero exit-live bytes**. Runtime and emitted RC counters
are all zero; 229 direct cleanup sites execute. These are whole-program managed
measurements, not RSS or a before/after saving. It prints `optional-writeback 42`.
The IR records payload transfers and the linked symbol audit is clean.

The exact original A03 reducers `owned-option.my` and `copied-option.my` now
admit; the scalar-only control still admits. Their source hashes are recorded
unchanged. Original Support7 refusal evidence remains in A03 and the earlier
A01 `optional-field-writeback` diagnosis.

Compiler SHA256: `a08f3b4cc64a50934dbd9e8811f878823aa63822c2997a28bb11e064fd0de693`.
The host compiler was built in Debug mode; guest mode selection is independent.
`identity.json` records source hashes, command, admission tickets, and every
attempt, including setup and draft-fixture failures. `raw/native-v2/` contains final raw results; earlier raw files remain prior-artifact evidence. `raw/` includes the logs,
counter JSON, LLVM, IR and symbol output. `qualify.py` preserves the original
reducers and writes only this run's new evidence paths.

## Remaining boundary and integration

Passing a narrowed optional as `mut` back to a parameter of the optional type
remains unsupported (`narrowed-mut.my`). Checked mode refuses with
`E_SINGLE_OWNER_BORROW`; the initial ordinary control refused with
`E_CORE_UNSUPPORTED` for a mut argument that is not a place. This fix does not
silently broaden that separate contract. Direct root mutation on the RHS of a
field assignment remains `E_MUTATION_OVERLAP`; `try` stays at its supported
statement boundary. Those are explicit negative controls, not passed positives.

The coordinator should rerun the unchanged A03 full recursive-values migration
and generated property with the next integrated compiler. The complete global
gate and common compiler requalification remain coordinator-owned. A SPEC
wording request for the existing `NEW-CORE-ZERO-RC-CONTAINERS-1` clause was sent;
only the coordinator may apply that shared edit. No publication is authorized.
