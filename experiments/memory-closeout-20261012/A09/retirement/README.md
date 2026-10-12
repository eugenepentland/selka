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

Further count-test migration is staged separately from these five runtime hooks:
current `.snapshot()`/single-owner compatibility coverage will give way to
independent explicit-copy storage checks; experimental selectors disappear only
when the coordinator applies the rollout/retirement changes. No runtime policy,
source denominator or safety assertion is dropped to make an oracle pass.
