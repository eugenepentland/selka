# RC helper publication and arena history: read-only audit

Status: an initial evidence snapshot for the semantic-history implementation.
No runtime or compiler source is changed by this audit. It reviews the approved
private API/design at `795c7f6e` against executable source `ce8e5d2f` and a
pre-compaction control at `c3166634`. The
[evidence archive](../../experiments/d9-rc-helper-publication-audit-20260926/README.md)
records completed rows, raw output and exact source. Some backend controls were
still running when this snapshot was committed; they are not counted as passes.

## Established arena counterexample

Inside an arena, create `rows: list[dict[int,int]] = []`, append the fresh literal
`{1:7}`, create `live = rows[0].values()`, then write `rows[0][1] = 13`.
Print the materialized live view and the new dictionary value.

| Mode | QBE | Actual LLVM |
| --- | --- | --- |
| GC | `[13]`, `13` | `[13]`, `13` |
| RC | `[7]`, `13` | `[7]`, `13` |

The corresponding heap case prints `[13]`, `13` in both modes on both backends.
Fresh nested dictionary construction (`outer = {0:{1:7}}`) has the same arena
mismatch on both backends. The append discrepancy also reproduces on the frozen
pre-compaction QBE compiler, so the compact journal did not introduce it.

The bytecode makes the cause particularly narrow: `MAKE_RECORD` for the fresh
child is immediately followed by `BUFFER_append`, with no semantic
`VALUE_COPY store` between them. The GC helper writes the child bits. The RC
helper calls `myl_rc_native_copy`; arena COPY sets the child's common SHARED bit.
The input's temporary owner then disappears, but that mark survives. The later
write detaches a dictionary that GC updates in place, leaving H observers behind.

This proves that borrowed-result LOAN16 alone does not eliminate every arena
physical copy. It does **not** prove exact arena side counts are necessary.
This particular extra owner is temporary: guarded TAKE of a fresh input, or a
history-free physical helper publication after the compiler's actual store event,
could remove the false mark. Semantic borrowed inputs still need their real SHARE
at the original evaluation point.

## Publication inventory

| Boundary | Current physical action | Required distinction |
| --- | --- | --- |
| List append/insert and literal construction | `rc_list_insert_at` reserves, then native COPY, then commits the new logical edge | Fresh moved input has no GC SHARE; duplicated temporary O must not invent one |
| List write and dictionary overwrite | Native REPLACE stages a pin-aware COPY before replacing the old edge | Apply exact store history once; keep refusal atomic |
| Dictionary insertion/literals | `rc_insert_result` uses one COPY-many transaction for key/value and optional returned value | Physical edges and semantic events have different multiplicity; output duplication can be temporary |
| `setdefault`, existing key | `rc_existing_result` copies an owned result even when immediately consumed by `len` | Generic borrowed-result LOAN will not intercept this owned helper result |
| List copy/slice/extend, keyed sorted output | Clone/append physically copies each child | Preserve original pinned child identity until the following CHILDREN or SOURCE_CHILDREN event |
| Dictionary copy/update | Repeated writes acquire or pin-clone children | Same semantic child policy; partial progress must not create uncommitted history |
| Pop/removal with output | Native TAKE may clone a pinned value before removing its logical edge | Transfer ownership once, preserving which semantic event created any snapshot |
| Read capture before a callback | GC `share`; RC `prepareOperand` plus `publish` | Add the actual capture SHARE at this point, independently of physical journaling |

The setdefault arena probe currently shares the fresh nested-construction
trigger, so it is **not** an isolated proof that setdefault creates another
observable divergence. Its owned-result helper path is a source-level audit
finding, pending an independent control.

Current pinned-list controls are useful positive oracles. A callee receives
`target: mut dict[int,int]` and `source: list[dict[int,int]]`, writes the same
scalar value to `target`, and returns `source.copy()` while the child is pinned.
A later live view of the copied child observes its mutation. Both backends and
both modes print `[13]`, `13`, `7`. Slicing has the same QBE result in this
snapshot. A v3 implementation must preserve that outcome: marking an already
physically cloned child during a later semantic CHILDREN pass would leave the
view at `[7]`. The helper's premature pin-aware clone must not erase provenance.

## Immutable boxes and the side-metadata decision

GC transfers an immutable recursive box without marking or traversing its body;
projecting the body shares its immediate mutable children. A nested write calls
`myl_native_cow_clone_box` unconditionally. Current RC `qbe_cow.detachBox` instead
uses generic `rc_unique.field`, and `native_rc_scope.prepare_path` also applies
generic uniqueness to pointer hops. Removing arena box SHARED while retaining
those in-place paths therefore needs a separate proof for lasting physical box
aliases. Restoring unconditional box-body detachment plus the GC child-history
event is an alternative to exact arena O side counts. A sticky alias bit would
avoid some writes but retain false detach history; it is not an exact substitute.

The boxed local/call/list-constructor controls expose a separate existing
correctness issue: with a retained `Some(Node(mapping={1:7}, child=None))`
snapshot, writing the narrowed original's mapping produces QBE GC
`[7], 13, 7`, but RC `[7], 7, 7`. Removing the live view still gives GC `13, 7`
versus RC `7, 7`. It occurs on heap and arena paths, so it does not establish a
need for arena side metadata. The parent owns the receiver write-back diagnosis;
the runtime owner has the exact probes. LLVM and pre-compaction box controls
remain pending in this initial snapshot.

## Failure and byte-buffer boundaries

The generic transfer walker and COPY-many currently write arena SHARED as they
visit leaves; rollback releases acquired edges but does not restore those marks.
A first arena mutable leaf followed by a refused later owner acquisition can
therefore leave history changed despite value/token rollback. The flat COPY
specialization preflights its leaves before marking, so that exact ordering
problem is in the general transaction, not its successful flat path. The v3
transaction must keep semantic marks and any physical alias bookkeeping atomic.
This is a code-path proof; this audit adds no C fault-injection test.

Byte views acquire the **canonical raw backing** directly through owner_acquire,
which does not use the typed arena COPY/SHARED path. Buffer snapshot publication
sets `work.owner` and clears spare capacity only after backing acquisition
succeeds. `buffer_ready` publishes replacement storage only after allocation and
copy succeed. This explicit snapshot backing protocol must remain separate from
semantic header history. No byte-buffer outcome discrepancy is claimed from
this read-only inspection.

One dictionary pinned-copy source triggers a Debug checker assertion before
execution: `clone_during(mut original[0], original)` reaches
`sema_expressions.zig:932`, where temporary-stack consumption exceeds its length.
It fails before either backend/runtime runs and is preserved separately from
runtime outcomes. The parent requested a separate checker fix from the current
integration baseline.
