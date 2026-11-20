# RC semantic history and private loan lowering

This compiler slice connects the reviewed ABI3 loan and semantic-history runtime
contracts. It remains experimental: GC is the default, legacy sharing uses GC,
and WP-4 performance and full acceptance remain open.

The original live-view matrix passed 13/13 with tracing GC and 6/13 with ABI2 RC.
A marker-only prototype reached 12/13: a fresh dictionary appended inside an
arena still acquired false sharing history through its physical helper copy.
The completed lowering passes all 13 cases and preserves the original mapping
identity in both mutation orders, nested aggregates, boxes and arenas.

## Physical values and semantic events

Copyable borrowed results and private compiler captures carry LOAN16, a private
inline value whose managed leaves hold lifetime tokens. They neither clone pinned
payloads nor change ordinary ownership or sharing history. Typed pending and
operand journal entries carry the role through guarded publication. Named values,
canonical returns and heap fields acquire ordinary ownership; no loan reaches a
provider or heap ownership slot. Raw unique resources keep their existing linear
cleanup path.

`qbe_rc_history` applies the tracing emitter's actual copy decision at the original
instruction: direct copies, child/source-child events, read captures before a
callback, and mutable-bearing box-body materialization. A real semantic event
commits the runtime's queued marks only after all acquisitions and finite pinned
clones succeed. It consumes a guarded ordinary owner or copies a loan/H input;
the source guard changes only after success.

Collection insertion/overwrite, shallow clone/slice helpers, setdefault results
and aggregate payload initialization use physical retention. They preserve child
identity until the explicit semantic event. Dictionary key/value/output batches
retain atomically; range-key overwrites use the same physical convention. Existing
consuming removal still uses the pin-aware take protocol.

Immutable box writes always detach the body, including arena boxes whose physical
aliases have no per-object owner counter. That detach performs the same child
sharing event as tracing GC. Scoped paths identify immutable box hops separately
from mutable collection leaves. Generated path and frame layouts stay unchanged;
only the private converted runtime projection records the box-hop distinction.
The joined boxed receiver fix republishes its body through physical retention.
Its local owner is canonicalized before the O-or-borrow runtime bridge.

Optional borrowed-return certificates now decline mutable sharing events; their
grammar/cache identity advances to v4. Whole-body readonly proofs also refuse
mutable-bearing box materialization and semantic copies. Immutable accessors and
pure recursive reads retain their existing proof paths. The inline TAKE shortcut
admits only a completed ordinary publication and excludes loans, held views,
borrowed alternate calls and private-local moves with a dynamic role.

## Publication-role audit

An alternating Some/None unwrap exposed a reused match slot whose fallback had
held a loan. The next owning match payload changed its guard but retained LOAN16,
causing a later hold underflow. Match payload publication now resets the typed
entry before setting its owning guard; plain payloads remain omitted from compact
journals. The permanent regression is `rc_semantic_publication`'s repeated unwrap.

The related audit covered every generated `initialized(true)` site. Ordinary
local stores copy the prepared pending role; operand, constructor, try-result and
internal publications reset their typed entries; H and loan publishers set their
exclusive role. The unique-local and rebox runtime bridges can create an owner
from a previously empty slot, so their ordinary branches reset stale role metadata
before calling the bridge. Held uniqueness retains its separate H branch.

## Validation and boundaries

The final frozen Debug compiler identity, commands, exact source hashes and raw
outputs are retained in
[`experiments/d9-rc-semantic-lowering-20260926`](../../experiments/d9-rc-semantic-lowering-20260926).
The final validation totals are recorded in that directory's README. Both actual
backends use their intended flags; LLVM guest tests use `--release`, with no later
`--qbe` override.

The indexed mutable-argument correction is included. Its independent history
oracle prints exactly `[7]`, `13`, `7` in GC-stress and ABI3 RC on both backends:
readonly argument publication first clones the pinned child, then the shallow
copy shares that unpinned child, and the later mutation detaches while the live
view retains the original value. Old ABI2 observations remain archived rather
than defining the corrected result.

The branch also includes the independent GC rebox root fix and the checker
rejection of recursive resource-bearing boxes. An obsolete compiler unit test
that constructed such an illegal type now checks rejection; direct native
unique-finalizer tests remain intact. No full gate or performance acceptance is
claimed by these focused results; integration runs the cumulative gate and guest
corpus before accepting WP-4.
