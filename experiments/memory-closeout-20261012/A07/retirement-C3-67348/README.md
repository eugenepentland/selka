# A07 Core retirement draft — unapplied and unqualified

This is a deletion patch against integration commit
`67348fc8ca14578af999c056891d3d318d311e12`. It is **not milestone 3**. No active
compiler source was changed while preparing it. The coordinator must rebase it
over the final qualified default and apply the coordinated C3 changes together.

`retirement.patch` changes 16 files, with 230 added and 1,154 removed lines.
`abi-schema.patch` is an overlapping subset for ABI review, not a second patch to
apply after the full patch. `manifest.json` records input/output hashes and the
full patch hash. The patch applies to a private index loaded from the exact base;
all prepared Zig files pass pinned `zig fmt --check`. Typechecking, registered
tests, native tests and final qualification have **not** run on this draft.

## Fixed ABI contract

`guest_abi.Abi` is `enum(u32) { checked_owned_v1 = 0x4f574e31 }`, with
`guest_abi.current = .checked_owned_v1` and
`guest_abi.identity = "mylang-checked-owned-v1"`.

`ir.Module` and `build.Input` replace `single_owner`, `zero_rc`, and the module's
`shared_lists` table with fixed `abi` provenance. The tag is not a selector.
Persisted records must require ABI without an initializer; A08 owns those format
changes. A linked bundle must validate every input, without OR-combining modes.

The shared LLVM renderer puts `; mylang-checked-owned-v1\n` first in every whole,
split, helper-seed and entry module. A08's native admission independently checks
each text and receipt. Header layout remains the already qualified owned layout:
kind at 0, padding at 4, length at 8, capacity at 16, layout at 24, size 32.

## Executable paths removed

- The earlier list-only checker API, shared snapshot families and mode switches.
  `single_owner.check` and `validate` become the full mandatory checker;
  `checkMode` and `validateMode` disappear. Public `buildRootsCached` checks once
  before lowering or cache consumption; the independent coverage sweep checks
  once too. Checker scratch is released with backing allocators.
- Runtime uniqueness-web proofs, hoisted count tests, tested update branches,
  and `is_unique` generation in ownership lowering. Static independent storage
  materialization remains where an update needs it; it never shares children.
- Emitter retain/release arithmetic, count loads/stores, slow count calls,
  count TBAA/range metadata, the legacy inline free body and encode aliasing.
- Legacy generated release callback descriptors. Current interpreted references
  and guards remain for iterative direct destruction.
- Legacy tuple projection cleanup, optional runtime-helper auditing, keyed-sort
  selection, resource-scope selection, dictionary setdefault ownership joins and
  list-only explicit-copy lowering alternatives.
- The post-emission string-rewrite adapters that used to convert legacy header
  templates and strip RC declarations. Templates must now be authored owned.

## Required behavior preserved

Direct drops, null/undef guards, active union guards, recursive box-shell cleanup,
provider lifetime pins, borrowed selections, complete tuple staging, prepared
mutable paths, explicit recursive copies, task synchronization and ordinary
heap allocation remain. `core_owned_copy.c` is unchanged. The direct cleanup
operation is still named `release` in IR; that name does not implement a count.

The internal `retain` and `is_unique` tags remain diagnostic inputs for malformed
or unsupported graphs. Final verification and emission reject both. Ownership
may form temporary retain obligations and cancel local pairs; any surviving
obligation refuses execution. There is no emitted retain primitive or RC fallback.
The historical `tested` statistic remains zero. `release_unique` telemetry still
counts direct destruction, not RC events.

## Atomic dependencies and remaining work

- A08: snapshot/lowering/optimizer/native envelopes, required ABI receipts,
  all-unit marker checks, and versioned cache/native identities.
- A10/coordinator: command selectors, eager diagnostic source checks, default
  and packaging changes, and all public/internal callers of removed APIs.
- Coordinator/A09: authored count-free `emit_count.fast_paths`; remove stale
  retain/release/free-block declarations and legacy free wrapper. Keep allocation,
  copy, growth and direct-destruction counters. This draft no longer strips those
  declarations after rendering.
- A01/A02/A04/A05: runtime implementation deletion patches. Current owned
  descriptors/direct child traversal must agree with the emitter. No old runtime
  selector may survive merely because this patch no longer passes one.
- Rebase the new A04 borrowed text/optional selection utility and lowerer,
  A05 borrowed-provider constructor, root consuming-use hardening, and A02 fold
  accumulator before applying. They were pending after this draft's pinned base.
  Their boolean mode guards must become unconditional checked behavior while
  keeping logical/physical marker validation and both-owner loans.
- Migrate active tests that construct old Module/Input booleans or assert old
  shared-family/count behavior. Preserve historical immutable comparisons and
  all supported source oracles. Keep deliberate malformed-IR tests as explicit
  refusal tests; do not turn unsupported sharing into successful execution.

After atomic application, run the complete registered verification and Guardian
requirements, the affected five-mode matrices, old/missing/foreign/mixed artifact
refusals, source negative diagnostics, LLVM/runtime/symbol/layout audits, native
cleanup and package qualification. Fresh C3 runtime, allocation, RSS and compile
evidence must name the resulting compiler. This draft cannot substitute for any
of those checks or for the still-required C2 qualification.
