# Independent compiler review, 2026-10-03

Reviewed source snapshot `ac54b90b226517751962dbab1c969465d490f788`, including
positive-index commit `406c7eebdb36b306b0f4ceb9fac78ef7adeb469d`. The requested
`bd28c8ad` commit contains the separate sweep source experiment; it adds no
compiler implementation. `source-record.json` identifies every inspected
compiler/runtime/test blob. This reviewer authored neither compiler addition.
The review made no compiler/source edits, ran no timing, and did not repeat
qualification already performed by the parent.

**Result:** one positive-index certificate refusal omission needs correction.
The field-inout refinement passes this source review within the stated proof
limits. No runtime miscompile or GC/rooting failure was demonstrated.

## Finding: omitted `try_result` interior edge

`src/qbe_positive_index.zig:47` exempts `start + 9` from the ordinary
`isBranchTarget` refusal, because the canonical normalizer itself jumps there.
The accompanying `extraEntry` scan at line 88 rejects other `jump`,
`jump_if_false`, and `switch_variant` entries to this label, but omits
`try_result.error_target`. That operation is an explicit CFG edge in
`ownership_sources.zig:174`; `qbe.zig:1836` also records it as a branch target.
Consequently a second `try_result` edge to this interior label is not refused by
the advertised no-interior-entry certificate.

The unchanged normalization/read body still exists. Current frontend `?`
error targets normally lead to function propagation blocks, and this reviewer
has no source-generated miscompile. The actionable issue is that the generic
certificate does not establish its stated refusal for every validated branch
kind, rather than evidence of incorrect current Lox output. Add the
`try_result` case, or use the shared branch-target enumeration while allowing
only the canonical `start + 3` jump, and add a synthetic bytecode edge-refusal
regression. Other interior labels already use `isBranchTarget` and refuse this
edge correctly.

## Positive-index proof checked

The certificate admits only the exact eleven-op canonical sequence, the same
captured list receiver in its length/read operations, a temporary signed i64
index, and matching plain operand prefixes. It refuses references/caller
storage, managed/live-view elements, boxed collections, strides below two,
versioned loops, step accounting, pending scopes, COW/fill/share work, loop
entry work, and actual local release sites on every skipped PC.

The unsigned comparison is sufficient: a successfully allocated native list
has `length <= capacity`, and capacity times its descriptor's element size
fits `size_t`. RC storage checks that multiplication in
`native_rc_values.c:419`; tracing allocation checks it in
`native_heap.c:1129`, and reserve paths retain the invariant. For a stride of
at least two in the native word ABI, length is at most `2^63 - 1`. Every
negative i64 bit pattern is at least `2^63` as u64, so it cannot pass the guard.
Byte-sized and zero-sized elements are conservatively excluded. Valid positive
indexes reach the existing `indexPayload`, whose address uses that same
layout stride and backing storage.

Every failed guard reaches the original negative normalization, integer cast,
checked addition and bounds trap. Successful reads cannot allocate or trap
under the admitted layout/invariants. The fast path runs the same
`qbe_rc_ops.after` result protocol, retaining operand ownership/clearing
behavior. It does not remove source-index evaluation or receiver capture, and
leaves accounted builds unchanged. These conclusions depend on validated
frontend bytecode and consistent native descriptors; the certificate is not an
independent validator for malformed IR or manually corrupted headers.

## Field-inout proof checked

`rc_field_transfer.closed` obtains the existing full extraction, alias,
authority and closed-interval proof before `rc_field_inout.qualifies` refines
its mode. The original proof still rejects parent reads/rebinds, live views,
second writable parameters, source-derived observers, pending receiver scopes,
nonquiet extraction/store-back sites, exits, and escaping targets. Scalar
sibling reads allowed by the older proof are additionally refused by the new
plain-instruction interval scan when they require parent projection.

The refinement requires an inline record type with the established record
inout ABI, one target store, one target reference and no other target reads
beyond its exact write-back. The scan covers the entire function, so previous
definitions, later uses, explicit drops/moves, or match bindings cannot make
the ghost target previously initialized or escaping. Repeated execution of
the same certified sequence in an outer loop remains valid.

There is exactly one direct call in the straight interval, with an exact whole
reference to that target as the sole declared mut parameter. Other operands
and return values are plain, address-free types; indirect argument evaluation,
nonplain values, parent-derived inputs, extra calls/references and branches
refuse. The transitive graph walk rejects all reachable indirect, host and
C-ABI calls, rather than only checking the immediate callee. Repeated/recursive
functions are tracked, and the 256-function/65,536-instruction limits fail
closed. Type-authority traversal also rejects callable, resource, handle and
live-view routes; allowed sealed capability bits cannot name guest parent
storage.

`qbe_rc_field_transfer.inoutLocal` supplies the actual source field's address
through the existing parameter ABI and suppresses the temporary extraction
and store-back. The parent field remains initialized, owning and rooted; no
copy is published into the target journal. This avoids double cleanup even
when the callee returns early or traps. Normal call admission, leaf COW,
allocation, parameter rebinding, parent/caller storage replacement, roots,
position markers, and frame teardown still execute. A callee may rebind the
record because caller-storage replacement updates the actual field; retained
snapshots remain independent through ordinary counted edges and COW.

The direct mode requires an active RC state, a target journal slot and an
unborrowed body. Without that physical route, the existing transfer fallback
remains available. GC lowering, semantic copy decisions and source bytecode
are unchanged. The new mode enum preserves closed-versus-dead behavior at all
updated sites (`returns()`); the dead-move runtime guard remains intact.

## Evidence and limits

Existing dedicated tests cover positive/negative/extreme/empty indexes, exact
error details and traces, byte/managed-element and writable-place refusals,
step accounting, receiver replacement and snapshots. Field tests inspect
refusals for parent observations, branches, early caller exits, escaping
values, callbacks and nonplain operands; native tests cover retained snapshots,
detached aliases, callee early return and rebinding, bounds traps, owned/caller
storage, arenas, memory budgets and owner/hold balance. The parent separately
reported final 2,479 root and 515 QBE/driver/host tests passing. Those runs were
not independently executed during this read-only review.

The new tests do not individually cover every artificial CFG edge or proof
workspace saturation. In particular, they do not expose the `try_result`
refusal omission above. No inlining, callback, host-ABI or frame-map safety
attribute changes are involved. Performance selection and the byte-identical
flattened guest observation remain parent measurements, outside this safety
review's claims.
