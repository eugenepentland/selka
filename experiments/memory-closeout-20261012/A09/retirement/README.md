# Counter retirement preparation — unapplied

The coordinator reserved `src/core/count_test.zig` and `src/core/count_runtime.zig`
to A09. `count-runtime-retirement.patch` removes exactly the five instrumentation
insertions whose underlying RC helpers/publication assignment A02 removes in its
runtime retirement patch. `git apply --check` passes against the current source;
this is a prepared patch, not a completed or qualified retirement.

Apply only after C2 qualifies and the coordinator dispatches Stage 4, together
with A02's runtime changes. Applying either side alone intentionally fails the
anchored counting-runtime contract. Allocation, direct destruction/free, list and
buffer growth, reallocation, explicit copies, peak managed bytes, normal exit
and trap exit hooks remain.

| Removed anchor | Why it disappears |
| --- | --- |
| `count_retain` | The guest runtime no longer increments a memory reference count. |
| `count_release` | Destruction is direct; no memory reference count decrement. |
| `myl_core_retain_slow` | No shared/saturating retain slow path. |
| `count_release_shared` | No atomic shared-memory ownership count. |
| `child->count = count \| MYL_SHARED` | No shared ownership publication walk. |

The existing exact-unique-anchor test must still pass after integration. Counted
fixture tests must preserve exact output, trap status/diagnostic, explicit-copy
bytes, record-copy source attribution, growth and allocation/free accounting.
Old RC counts must not be relabeled as checked-ownership expectations. The new
explicit-copy fixture's values are measured separately in ordinary and zero-RC
modes before replacing the old oracle.

Counter-schema fields such as `runtime_retains` and historical JSON parser
fixtures are telemetry compatibility, not a guest memory reference count. Keeping
zero-valued telemetry columns does not preserve RC operations; no deletion of the
schema is proposed here. The `cost --counters` parser's synthetic historical
RC-bearing document is a read-only report compatibility test, not guest execution
or an RC selector. Final structural audits must classify this distinction.

Core IR still names direct destruction `release`; checked emission selects
`myl_core_drop_owned` without inspecting a reference count. The telemetry kind
`release_unique` likewise records direct destruction and remains positively
asserted. Only the legacy `release` telemetry kind and runtime RC event fields
must be zero. The list-oracle review's earlier blanket ban on textual `release`
was incorrect and has been corrected; the first failed test log is retained.

Further count-test migration is staged separately from these five runtime hooks:
current `.snapshot()`/single-owner compatibility coverage will give way to
independent explicit-copy storage checks; experimental selectors disappear only
when the coordinator applies the rollout/retirement changes. No runtime policy,
source denominator or safety assertion is dropped to make an oracle pass.

`count-test-retirement.patch` is also unapplied. It replaces the legacy positive
snapshot-sharing cost comparison with explicit child independence at the same
40-row size, preserving `2 3` output and adding an independent child-value check
through mutation of the original. Support5 debug/release measurements are pinned
in `independent-copy-support5.json.gz`: 41 list copies / 960 copy bytes, 91 balanced
allocations/frees, zero runtime RC and zero exit-live managed bytes. The outer
list copy is now included by the corrected recursive-copy hook; these totals
must not be relabeled as the previous sharing fixture's results.

The patch removes experimental selectors from this test file and gives the new
independence test all five ordinary pipelines. It also makes the small uncounted
`twice` fixture's independent return explicit. Actual default-command execution
of the patch is still pending C2/Stage4; the current evidence used the opt-in flag.
The existing negative `.snapshot()` ownership test is retained by its owner.

The audited `docs/tooling/counters.md` keeps the current explicit opt-in selector.
`counters-doc-c2.patch` changes examples to ordinary commands only after qualified
default promotion; `counters-doc-c3.patch` subsequently documents actual retired
selector diagnostics. Both remain unapplied. `counters-doc-rollout.json` pins
source-contract hashes and sequential patch checks. The current cost summary
aggregates direct drops into its historical releases field; the documentation
explicitly directs RC audits to raw v1 kinds and runtime/shared fields instead.

`ce-lists-default.patch` is also unapplied until C2. It removes only CLI selector
arguments, preserving all five mode variants, source/IR/LLVM ownership checks,
outputs, leak checks and exact traps. Its manifest records the preimage hash.
