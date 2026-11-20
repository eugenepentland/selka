# Bounded borrowed-entry loops: design for review

This is a design, not an implemented extension. The current every-return
certificate deliberately refuses backedges. That excludes schematic `partPin`,
whose loop searches caller-owned pins and returns either one pin or an inline
record containing only immortal empty byte strings. The canonical entry and
all function-value/provider calls must continue returning owned values.

## Fixed-point state

Reuse the existing exact opcode and authority grammar. Do not admit mutation,
parameter replacement, arena transitions, unknown/host/indirect calls, owned
heap construction or semantic publication merely because a later path discards
its result: a raw borrowed body has no way to retire that hidden obligation.
Direct helpers remain restricted to independently proved immortal factories in
the first loop slice. Transitive anchored calls, such as `innerPin` calling
`partPin`, require a separate change.

Distinguish three facts explicitly:

- An unreachable instruction has no incoming state.
- An unavailable local has no value at that join. It is distinct from an
  initialized plain/immortal value whose `anchor` is null.
- An available value has a fixed physical type and either one parameter anchor
  or an immortal/plain origin.

A bounded worklist propagates incoming stack and local states. A join requires
identical stack height and physical types. Different non-null parameter anchors
refuse certification. An immortal origin joined with a parameter origin takes
that parameter anchor. A local unavailable on either reachable predecessor
remains unavailable at that join; a later predecessor cannot optimistically
restore its availability. A subsequent explicit store can of course define the
local in the transfer function. On any changed incoming fact, enqueue that
instruction again. A per-instruction queued flag bounds queue storage.

These facts form a finite descending-information lattice. Loops may carry an
origin from immortal to one anchor, or lose local availability, but cannot
oscillate between different valid anchors. A conflict refuses the optimization.
The compiler must process the entire reachable CFG to a fixed point before
accepting **any** return. Then inspect every reachable physical `ret` against
its final incoming state: exactly one result of the declared physical type,
all managed edges belonging to the same parameter or immortals, with all
returns agreeing on that anchor. No return, missing initialization, malformed
fallthrough or conflicting anchor declines the optional certificate.

The caller's parameter lifetime remains the physical anchor for the complete
borrowed activation. The existing no-mutation/no-effect grammar keeps it stable
through repeated loop entries. Inline returned bits must still be copied into
the normal ABI return storage before the callee's stack disappears; the existing
alternate-entry lowering remains authoritative here.

## Work and cache bounds

Retain the active-call recursion guard and maximum depth 16. Bound state cells,
queue storage and total transfer/join work across the complete root proof and
its helper queries, using checked arithmetic before allocation. Reuse incoming
states and scratch rather than allocating a fresh copy per repeated visit.
Exhausting a proof budget declines certification, not legal RC compilation.
The exact numerical work cap will be fixed with measured `partPin` state width;
there is no permission to remove the existing bound to force admission.

Increment the physical certificate policy version. Compute dependency hashing
only after convergence, in deterministic ascending reachable-PC order, including
ABI, parameter/result layouts, exact instructions and independently proven helper
identities. Worklist scheduling order must not change a cache key. Warm/cold
and helper-edit/certificate-loss tests must continue to invalidate callers and
alternate units correctly.

## Required tests and measurements

A positive search-loop accessor must return a caller element or immortal-only
fallback, with exact output and balanced cleanup on both backends. Include
empty, first-hit, later-hit, no-hit and nested-plain projection cases, caller
snapshots and arenas, and bounds/step/frame failure controls.

The decisive negative starts a loop-carried return local at parameter A, then
writes parameter B on a backedge, with a return reached only on a later loop
iteration. A forward-only observation of A must not authorize that return.
Also reject unavailable locals at a join, conflicting live anchors, mixed fresh
fallbacks, callback/mutating calls, unique resources and unsupported operations.
Retain canonical/function-value ownership checks and exact alternate metadata
attribution. Stress bounded refusal with large CFGs and recursive helper graphs.

Measure the unchanged three schematic inputs against the frozen predecessor,
with separate counted and uncounted binaries, complete SVG hashes and both
actual backends. Do not substitute an accessor microbenchmark for those inputs.

The compiler agent reviewed this design and agreed with the distinct unavailable
fact, conservative joins, deferred return acceptance, strict grammar and sorted
post-convergence identity. The integration parent independently required the
loop-carried different-parameter negative. Implementation remains a separate,
reviewable slice after the immediate-field optimization.
