# Stage 4 readonly callers of managed borrowed helpers

The compiler now removes ownership bookkeeping from closed scalar readers that
call independently certified managed-return helpers. On the three unchanged
schematic workloads, instructions decrease 24% on QBE and 24–28% on LLVM.
Outputs and ownership accounting match. These results remain far above the
Stage 4 limit: 12.07–12.14× accepted GC on QBE and 17.57–18.13× on LLVM, versus
the 1.3× maximum. This isolated change does not establish full-corpus acceptance.

## Proof and lowering

The [reviewed design](d9-rc-readonly-managed-calls-design-2026-09-27.md) extends
readonly composition to managed helpers only through their public standalone
`rc_calls.borrowedIn` certificate. Each managed call records its exact PC,
callee, parameter anchor and complete layout/dependency identity. Emission
resolves this route before `frame.get`, which is intentionally unavailable in a
raw readonly body. Missing or inconsistent routes are invariant failures, never
fallbacks to canonical owning calls. Canonical and function-value managed
return conventions stay owned.

All managed bits remain anchored by original activation inputs or immortals.
Mutation, unique values, opaque or callable authority, owning allocation,
region changes and unknown effects refuse admission. Each plain dependency
passes the same public query independently. All queries share the sixteen
managed-helper bound; each managed query retains the standalone alternate
emitter's original limits. Completed certificates never evict dependencies.

Root review identified an unsafe draft boundary: optional physical refusal after
logical composition could leave a raw caller invoking a journaled plain callee.
The final implementation runs the actual native IR, liveness, ownership and COW
planners before accepting any certificate. Its shared quiet predicate rejects
planned captures, shares, uniqueness, place fills and ownership loop actions.
Early selection preserves v1 ordering. Final verification checks only invariants
already established by this preflight, including empty mutable transfer plans.
A validated pure-bytecode conditional-stack capture provides a permanent
conservative SHARE refusal that propagates through a plain caller.

The preflight has per-function bounds of 1024 instructions and 256 locals. Across
one plain dependency graph, it charges `n*(n+locals)` against 65536 cells and
`n*(n+locals)*(locals+1)` against 4194304 input-volume units. These are matrix
input dimensions, not a claim to count every planner operation. The previous
plain memo/depth and instruction allowances remain. Versioned identities bind
all admission, refusal, route and transitive dependency decisions.

Actual `sexpr::form` additionally required immutable bytes GET_INDEX. Admission
requires `typed.isByteString` and a u8 element; mutable byte_buffer, str,
dictionary and managed-result indexing remain refused. The existing normalized
index and bounds trap precede the scalar byte load. No runtime helper or cleanup
was introduced. All prior v1 nearest/table/resolver helper IL remains identical.

## Matched measurements

The before source is real merge `6edbe2ed77fc0aaa0e06cdc06dd09b33d731923c`, joining
named-record `14c73780` and readonly-v1 `c62adfb0`. It deliberately excludes the
later independent readiness, dictionary-key and loop changes. Both compilers
are Debug:

* Before: `d575a79e33ec9a87272ccc083e0dfd343c89978ed3ffe4fabf64a9bf02f7215d`.
* Candidate: `1beaacb9b76240dd563f5620a5ff391fb835684935671c84da43375c3ac98d54`.

The [archive](../../experiments/d9-rc-readonly-managed-calls-20260927/README.md)
records exact source, compiler/guest hashes, commands, manifests and raw events.
All 36 raw observations report 100% instruction-event running on CPU10. The
accepted-GC values come from the exact archived ownership-joined receipt, not a
new or silently rebased GC measurement. Every full SVG check passes.

| Workload | Backend | Before instructions | After instructions | After/before | After/GC |
| --- | --- | ---: | ---: | ---: | ---: |
| fixture | QBE | 295,716,422 | 225,782,713 | 0.763511 | 12.141852× |
| fixture | LLVM | 217,422,543 | 164,189,123 | 0.755161 | 18.125169× |
| changed-net | QBE | 297,237,811 | 225,401,892 | 0.758322 | 12.115695× |
| changed-net | LLVM | 222,494,652 | 159,407,566 | 0.716456 | 17.588710× |
| changed-value | QBE | 295,767,760 | 224,472,923 | 0.758950 | 12.071936× |
| changed-value | LLVM | 216,995,376 | 159,162,051 | 0.733481 | 17.568752× |

Twelve separate counted workload executions balance O, H and allocations, with
identical counters across backends. Fixture and changed-value O acquisitions
fall 124,879→93,402; H pairs fall 292,743→248,006. Changed-net O falls
124,851→93,402; H falls 292,985→248,296. All retain 156 heap allocations and
retirements plus one clone. No new full N10 Lox measurement or RSS measurement
was run for this slice, as agreed with root.

## Controls and known limitation

Focused readonly tests pass 26/26 (15 named and eleven always-run blocks), covering
public route selection, independent plain descendants, managed-query 16/17
limits, transitive cache identity/certificate loss, conservative physical refusal,
mutable indexing refusal and complete 4816-byte result copies. Root and both
compiler/runtime peers reviewed the proof and concrete lowering without blocker.

Passing runtime receipts comprise 52 guest assertions: aggregate snapshots,
multiple original anchors, reordered parameters, saved results across repeated
calls and loop PCs, caller arenas, immutable byte boundaries and canonical view
backing. RC counters balance on both actual backends. GC-stress binaries for the
two fixtures are byte-identical before and after on each backend. Twenty exact
Debug bounds/step/frame trap executions and four status-97 success controls
preserve before/after diagnostics and cleanup. Cache controls show identical
warm/cold emission through two helper edits, including lost admission, followed
by four balanced native executions.

**The combined managed fixture has a pre-existing LLVM ReleaseFast RC build
failure.** Both before and candidate report that a call site's frame-map
position names another guest function. The unchanged before compiler reproduces
it with a fresh isolated native cache/output. These are failed builds, not
passing controls. The complete fixture passes LLVM Debug before and after;
separate small and 4816-byte result wrappers pass actual LLVM ReleaseFast before
and after, including saved first results across repeated calls. The original
combined sources and every failed/successful receipt remain archived. No
unrelated frame-map repair or expected-result change was made for this slice.

The archive verifier recomputes medians, checks exact outputs/counters/cache
behavior and preserves the failed baseline classification. Its optional live
mode checks immutable local identities. Whole-tree Guardian passes all 88 checks and fmt-check passes. Root owns the
subsequent combined full gate and centralized Guardian feedback. Runtime default, accepted performance
baseline and workload remain unchanged.
