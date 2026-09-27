# Incoming record lifetime for checked scalar-list reads

Status: implemented and validated in the companion implementation report; the
original bounded design and attribution receipts remain preserved. Base is
`c1224f30`, with the immutable corrected Debug compiler and byte-identical N10
executables from the named record-field-read archive. Its prior receipts remain
unchanged. This is a separate branch and no new compiler cache/worktree.

## Exact residual evidence

The current full unchanged N10 medians are 154,804,551,022 QBE instructions and
118,368,631,962 LLVM instructions, respectively 21.372315× and 34.478071× archival
accepted GC. These are the existing c122 identity-linked observations, not new
hardware medians. New fixed-period instruction/LBR profiles on CPU3 preserve
exact output and binary/input hashes. Every sample throttled: 305 QBE and 234
LLVM, with zero lost records. **All sampled attribution is qualitative only.**

The exact `vm::read_byte` loan call sites appear in 23 QBE and 54 LLVM sampled
branch stacks; `vm::run` appears in 36 and 64. These are deduplicated presence
counts, not execution counts or cost percentages. `read_byte` still emits two
native pointer loans and their operand/capture publication and cleanup. Its
source performs a checked `frame.code[frame.ip]` read, then increments `ip`.
The first read uses an incoming mutable ExecFrame, so the named-home certificate
refuses it. `read_short` emits four loans but its expression/return shape may
separately refuse the existing complete STORE-ended interval. This design does
not extend that interval grammar merely to admit it.

The thirteen remaining read pairs in `vm::run` are a different admission problem:
five read `list[CallFrame]` with plain 24-byte results and eight read `list[Value]`
with plain 16-byte variant results. None is a scalar leaf. Some also evaluate a
callback such as `read_byte(mut frame)` after capturing the list. Incoming-home
admission alone therefore cannot remove these pairs. Runtime also has reachable
capability/callable data (`Option[Clock]`), which may fail the retained full-record
safe predicate. Plain inline result copying and a narrower selected-field
reachability proof are explicitly deferred.

A runtime one-pointer loan specialization is an alternative, but would retain
the entry binding lookup, actual payload finalizer lookup, hold admission/status,
drains, journal publication and cleanup. The closed incoming-anchor optimization
removes the whole temporary obligation; the fresh samples support testing that
larger bounded change first. No runtime mutation is proposed.

## Separate physical authority

Do not extend `rc_record_home.owned` or infer ordinary owners from a mutable
parameter address. The new authority is a caller-provided lifetime anchor:

- The root is an actual canonical guest parameter with `callerStorage(root)`,
  the declared mutable inline-record convention and matching current RC contract
  `caller_storage` plus physical entry `inout(parameter=root)`.
- Its physical storage resolves to that parameter, with no private alias/place
  substitution. Arbitrary by-reference roots, providers, externs, readonly and
  borrowed alternates remain refused.
- Retain the existing full record safe-type, nonunique and no-live-view refusal
  for this first slice. The selected member is the ordinary scalar-element list
  already admitted by the named proof. Do not widen result or collection types.

The incoming value may be held by ordinary caller owners, per-leaf private LOAN
holds, a receiver scope protecting a containing value, or an open caller arena.
No one of these implies O>0 or uniqueness. The argument ABI requires initialized
valid input bytes and lifetime authority at the call boundary. The caller is
suspended while the callee executes. The complete closed read interval introduces
no call, mutation, parent rebinding, independent release or arena transition, so
that authority cannot disappear before the scalar is copied out. A bounds/step
trap unwinds it only after the read path has stopped using the borrowed bytes.

The source audit follows `rc_calls.guest`, `rc_plan.initialOwnership`, the
`REF_LOCAL` emitter, actual by-reference/caller-storage address lowering and
`qbe_rc_locals` stores/moves. Caller-storage STORE stages a valid new owner before
dropping old bytes and publishing; it does not make the callee's local guard own
the caller slot. MOVE uses a clear inout guard and retains rather than taking the
caller token; DROP does not drop caller bytes. Forwarded REF_LOCAL passes the
existing storage address. None grants a right to publish/drop a borrowed leaf
inside the optimized interval. Unknown root publishers or untraced pointer paths
must decline admission; normal emitter paths remain unchanged outside it.

Compiler peer review found no valid counterexample under these exact restrictions,
and specifically confirmed H-only/receiver-scope anchors as distinct from O.

## Unchanged interval and queue proof

Reuse the existing <=64-PC complete interval, bounded full capture-writer scan,
forward CFG/internal join and external-entry constraints, empty operand/capture
induction, scalar result snapshot and final actual-emission call veto. Keep all
journal/layout storage and ordinary fallback. The only new certificate fact is
the root's incoming lifetime authority; scalar operation and effect admission do
not expand. Budget all scans and propagate compiler allocator failures.

The root authority is not by itself a drain proof. Ordinary valid guest boundaries
have completed pending destruction; a guest entered by a finalizer inherits an
active outer drain. No admitted operation can enqueue independent work. The old
temporary H releases cannot retire the caller-anchored list, so their omitted
drains are inert under that guest-boundary invariant. Preserve a real queued
sibling/reentrant-finalizer test. Unrelated prequeued idle C calls are not granted
a new entry contract. Removal of unnecessary temporary H-limit admissions is
intentional, as in the named slice; retained owner/hold limits remain mandatory.

## Required controls and measurement

Before timing, show exact read_byte emission and original fallback bodies.
Cover direct and forwarded inout calls, repeated invocations, distinct/aliased
parameters, caller rebinding before entry, H-only leaf authority, caller scopes,
heap and arena-backed inputs, nested arenas and later ordinary scalar writeback.
Refuse ordinary readonly/by-reference roots, unknown/private aliases, extra
capture writers, managed or inline aggregate results, callbacks, mutations,
arena changes and independent emitted cleanup. Keep final emitter speculation
fully isolated.

Native embedding controls must compare actual status/location/output for bounds,
overflow after read, step/logical-frame/physical-stack admission, allocator or
metadata failure where applicable and finalizer reentry with a queued sibling.
Verify scalar snapshot precedes later root mutation/cleanup. A deliberate near-H
limit probe records the removed admission separately from exact trap controls.

Use immutable Debug before/after compilers, actual QBE and LLVM O3/full LTO,
unchanged full N10 median-three on CPU3 and separate ownership counts. Reuse the
accepted-GC archival rows with clear identity, retain all samples, and make no
full Stage 4 acceptance claim. Root owns the independent combined gate, sweeps
and Guardian feedback.
