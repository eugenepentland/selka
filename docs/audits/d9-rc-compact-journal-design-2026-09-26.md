# Compact RC journal positions: implementation design

Status: implemented and focused-validated; see the
[implementation report](d9-rc-compact-journal-2026-09-26.md).
Base: integration `814813c8`, joined by real merge `87849c52`. This is a
bounded unchanged-ABI experiment; it is not a WP-4 performance acceptance claim.
The preceding metadata-template candidate was rejected and archived at
[`experiments/d9-rc-journal-template-20260926`](../../experiments/d9-rc-journal-template-20260926/README.md).

## Representation and eligibility

Keep the runtime-independent `rc_plan.Plan` unchanged. Replace the emitter
state's `locals` field with a cohesive emission plan containing the semantic
local plan and an immutable journal layout. State remains seven fields. The
wrapper has two fields; the layout needs one prefix-count slice. Do not encode
eligibility in payload size or unrelated flags, and do not waive Guardian.

Logical order remains all locals, all operand positions, pending work, internal
construction. Build `prefix[0] = 0`; each retained logical position increments
the next prefix by one. A position exists exactly when
`prefix[i + 1] > prefix[i]`; its physical index is `prefix[i]`. The final prefix
is the runtime entry count. This preserves reverse cleanup order and gives an
exact local-prefix arena watermark without a runtime lookup or ABI change.

A local is omitted only when its precomputed shape has neither counted edges
nor unique cleanup. Borrowed counted parameters, mutable aliases, read loans,
held view/iterator slots and all unique resources remain eligible. Operand
eligibility unions every reachable physical type at that position, including
managed types appearing after producers or at joins; entry-time unit is not a
proof. H roles are retained because their collection/view types are counted.
Pending and internal construction entries always remain. Operand payload
buffers remain allocated in the first experiment, avoiding a second proof about
physical scalar staging, aggregate addresses, or scratch reuse.

## Addressing and watermarks

All public lowering calls continue to name logical indices. One frame helper
translates an index and refuses an omitted slot with InternalError. In
particular, a missing guard must never alias the next retained position.
Explicitly harmless operations such as dropping a statically plain slot and
clearing its already-empty guard may be defined as no-ops. Publishing a live
guard or metadata to an omitted slot is an internal error.

`frame.pending()` remains a logical index. Metadata/guard addressing translates
it, including the internal `pending + 1` slot. Prologue entry loops skip omitted
locals/operands, use unchanged physical addresses for retained slots, and size
memset, stack/frame allocation and runtime frame count from the final prefix.
Dynamic by-reference local addresses are still loaded from their bindings;
internal construction may still change its payload address. Stable operand and
work entries retain the existing descriptor/role-before-guard publication rule.

`qbe_arena.emitEnd` passes `prefix[min(watermark, local_count)]` to
`myl_qbe_rc_arena_prepare`. Every retained local declared inside the block and
every retained operand/work entry then remains in the same cleanup suffix.
Local validation/zeroing loops continue to use source local indices. Runtime
scope restoration and frame cleanup need no change.

## Audited call sites and edits

* `qbe_rc_frame`: allocation/byte accounting, prologue, guard, entry, stableEntry,
  typedEntry, drop, pending bounds, total count and explicit prefix query.
* `qbe_rc_views.entry`, `qbe_rc_holds.branch`,
  `qbe_rc_values.holdRuntime`: replace raw entry-byte offset arithmetic with the
  shared frame address helper. These are the raw offset users outside frame.
* `qbe_arena.emitEnd`: translate its local-prefix watermark as above.
* `qbe_rc_values`, `qbe_rc_aggregate`, `qbe_rc_locals`, `qbe_rc_unique`,
  `qbe_rc_admission`, `qbe_rc_ops`, `qbe_rc_return`, `qbe_rc_narrowing`, and
  `qbe_rc_edges`: retain logical indices; audit plain no-op requests versus
  owning guard requests. Constructor internal staging and H role restoration
  remain intact.
* Update semantic plan access paths and focused mock emitter initializers for
  the wrapper. Avoid changing canonical ownership semantics or release plans.

## Validation and measurement

Structural tests must cover a plain prefix/gap/suffix, a reused operand changing
from scalar to O and H, unique cleanup, borrowed managed parameters, dynamic
by-reference addresses, and nested arena watermarks. Require an assertion that
asking for an omitted guard fails rather than addressing another entry.
Inspect actual emitted entry count and addresses for recursive binary trees.

Build a frozen before Debug compiler and preserve its binaries. Run actual QBE
and LLVM guest correctness and counted traffic for recursion, constructors,
views/iteration identity, callbacks, arenas/escape, unique resources, calls and
failure unwinding. Replay focused traps including missing-file and bounds errors.
Use identical binary-tree source/arguments, output validation and interleaved
retired-instruction samples for both backends. Counted traffic must remain
identical. Record stack/journal byte changes and compiler/binary hashes. Expand
to parent full gates and native trap replay only after the focused slice passes.
Archive/discard if the experiment does not produce a useful cross-backend gain.
