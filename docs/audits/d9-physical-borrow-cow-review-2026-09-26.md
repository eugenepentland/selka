# D9 physical return origins and current COW — 2026-09-26

No current GC/COW blocker was found in the reviewed mixed-return cases. The
physical `borrow_origin` bound is useful possible-alias information; it is not
an exact ownership contract. The stronger borrowed-result certificate proposed
in the [RC compiler contract](d9-rc-compiler-contract-2026-09-26.md) remains
necessary before RC lowering can omit result ownership.

This was a read-only review of corrected prerequisite source `f74abcce`, which
includes WP-4pre and the `ref_local` liveness correction. The frozen Debug
compiler SHA-256 was
`22d918399b9a987ce3fe493b71cee1a6cb0a40ff3462b5aef38770f6205c2e0d`.
No compiler or runtime code changed. This report does not certify WP-4 RC or
replace the prerequisite's full gate.

## Mixed fresh and parameter-derived returns

`origins.Origin.merge` unions parameter bits. A fresh alternative contributes
no bits, so a function returning either `[7, 8]` or `source[0]` has physical
`params[0]`. Its logical return remains fresh under value semantics. A fresh
inline record containing `source[0]` and a fresh list also has physical
`params[0]`. Thus the bound does not prove that all returned allocations or
counted edges are reachable from the argument.

The reviewed fresh list-wrapper control, `[source[0], [7, 8]]`, is actually
reported physical `fresh` in this lowering; its parameter-derived child is
shared at the element store. The review does not equate `fresh` with absence of
all physically shared descendants. Each constructor must establish its own
child obligations in a future RC runtime. Neither summary substitutes for a
physical edge ledger.

Current safety follows from separate emission rules:

- **Callee publication remains independent.** `ownership_values` classifies
  each return/constructor copy using that function's actual operands. In the
  conditional probe, the fresh return's copy is elided and the parameter
  element return's copy remains. In the mixed record and list wrapper, the
  parameter-derived field/element store retains its copy; the fresh field moves.
  `qbe_value_copy` marks mutable leaves shared or performs the pin-aware runtime
  transfer. Changing the caller's origin summary does not remove these actions.
- **Later snapshots keep their copy.** `ownership_values` excludes raw aliases
  and borrowed locals from the last-use owner set and iterates that decision.
  `ownership_roles` rejects a readonly borrow when its target is mutated or its
  source tree changes during its lifetime. The probe's `before = item` retains
  an actual copy before `item.append(3)`. An initial call-result assignment may
  have no frontend copy site because its logical result is fresh; its safety
  comes from callee publication, not a fictional extra caller copy.
- **Mutation still checks uniqueness.** `ownership_cow.sites` retains root and
  element checks; only the existing mutable-parameter uniqueness contract and
  proved paths can omit the corresponding check. A possibly borrowed call
  result does not acquire that mutable-parameter contract from its summary.
  Copies already made in the callee continue to force detachment when needed.
- **A fresh call result has its own GC root.** `qbe_cover.readAt` accepts actual
  local loads and element/field reads with an explicit source; it does not
  cover a call result merely because ownership calls that result borrowed.
  `qbe_roots.publishedRoot` therefore publishes a live call-defined local.
  The probe's `read_choice` explanation calls `item` a borrow of parameter 0,
  but emitted IL still roots `%l2` independently across the allocating `noise`
  call. This is essential on the fresh branch.
- **Physical slot aliases require actual storage evidence.** `qbe_moves`
  requires adjacent whole-local load/store shapes and lifetime checks; it does
  not replace a call result with its inferred parameter's slot. `qbe_borrow`
  may reference a call's stable caller-owned return pad, which is still traced
  as a value root. Its unrooted list-element form requires the separate inert
  lifetime proof and does not derive from `borrow_origin`.

An overapproximate dependency can cause extra copies or reject an optimization.
With the present tracing runtime it does not create the missing release/retain
obligation that an RC borrowed-result ABI would create. Future changes to root
coverage, call lowering or physical ownership must retain this distinction.

## Mutable references and ownership

The `ref_local` correction adds a use of the aggregate's existing value; it does
not change definitions, type layout, mutation permission or argument ABI.
Liveness grows back to the preceding definition and keeps the value alive before
its address reaches the operand stack. The existing operand roots then protect
it during later argument evaluation and the call.

This also correctly prevents `ownership_classify.movable`, `ownership_cow` and
`qbe_moves` from treating an earlier read as the last use. A later mutable
reference may observe the old value, so an earlier independent snapshot must
share/clone it rather than silently move it. The random-state alias fixture
exposed exactly this prior false move; its expected independent-value sequence
is being corrected separately.

Longer liveness can make an actual readonly borrow feasible by keeping its
anchor alive. That still passes mutation, storage-shape and stability checks;
it is not an unconditional copy elision. Element borrowing checks the longer
interval for calls/allocation/writes. Physical slot aliases and in-place updates
also consult that interval. The closed field/index edit proofs retain their
explicit observer, source identity, first-use and control-flow restrictions.
No additional compiler ownership defect was found in this review. Independent
mutable-reference snapshot/later-argument controls are recorded in the existing
[history review](d9-mut-reference-history-2026-09-26.md).

## Executed evidence

Eight scratch guests cover both return branches under intervening allocation,
both branches with a subsequent snapshot and mutation, mixed record fields,
fresh nested list wrappers, a dead original argument, and mutation of the
original parent after obtaining the result.

| Backend/guest mode | Explicit native GC stress | Fresh result |
|---|---|---|
| QBE / Debug | `mylang test ... --value-semantics --gc-stress` | 8 passed, 0 cached, 0 failed, 0 skipped |
| LLVM / ReleaseFast, O3, full LTO | same plus `--release` | 8 passed, 0 cached, 0 failed, 0 skipped |

The [compressed raw evidence](evidence/d9-physical-borrow-cow-review.json.gz)
contains the exact source, compiler/source hashes, commands, full outputs,
ownership explanations and selected emitted functions. These are focused
adversarial controls supporting the source review, not an exhaustive proof of
all possible programs. The preliminary bare `--explain-ownership` invocation
was rejected as invalid CLI syntax; the successful invocation used `=OUTPUT`.
