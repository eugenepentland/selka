# D9 compiler RC boundaries and initial red tests — 2026-09-26

This is preparation for the compiler work package, based on the reviewed
[compiler contract](d9-rc-compiler-contract-2026-09-26.md) and
[selector inventory](d9-rc-selector-inventory-2026-09-26.md). No compiler, runtime
or test source is changed. The cases below are proposed tests that must fail
until their RC behavior exists; they have not been executed as RC tests.
Implementation waits for the integration owner's accepted-base and C-header
message. This document does not close the compiler work package.

## File ownership and integration points

The compiler agent owns the proposed new `src/rc_model.zig`, `rc_plan.zig`,
`rc_plan_test.zig` and `qbe_rc.zig`. Split physical storage/shape inference,
verification and borrowed-return certification into focused modules as needed;
use `rc_*` for analysis and `qbe_rc*` for emission. These names are reservations,
not a requirement to create empty files. Proposed guest fixtures live under a
separate `tests/rc/` directory so GC runs cannot count as RC validation; the
integration owner wires its explicit selector into the build/test gate.

Expected narrow edits in existing files are:

| File | Compiler responsibility |
|---|---|
| `qbe.zig` | Plan after final ownership/liveness/COW storage facts; dispatch before/commit/after/edge/failure actions; direct and indirect call handling, local loads/stores and return handoff. Calls are in this file, not a current `qbe_call.zig`. |
| `qbe_frame.zig` | Initialized-token storage, prologue convention, normal/failure cleanup and result publication before frame destruction. Preserve resource drops and trace behavior. |
| `qbe_aggregate.zig`, `qbe_managed.zig` | Construction, overwrite, projection and collection helper ownership events. Keep physical relocation distinct from independent value publication. |
| `qbe_value_copy.zig`, `qbe_cow.zig` | Integrate count actions with existing sharing/uniqueness, tagged detach results and pending scopes; do not independently reimplement runtime pin rules. |
| `qbe_host_lower.zig`, `qbe_c_abi.zig` | Canonical guest return ownership at generated foreign boundaries, coordinated with runtime adapter ownership. |
| `ownership_*`, `qbe_liveness.zig`, `qbe_borrow.zig`, `qbe_moves.zig` | Read existing facts first; edit only if an explicit physical lifetime fact is missing, with separate negative tests. No duplicate weaker liveness solver. |

Root owns CLI/environment, selector, cache/native fragment identity, manifest and
build/install wiring. Nested owns C runtime/header contracts. Arena lowering and
runtime/host adapter overlap require a named owner before edits. Compiler changes
to caller-visible contract facts are specified to root, which owns the hash/cache
serialization patch. `SPEC.md`, root test registration and any shared emitter
integration are serialized rather than edited concurrently.

Avoid adding unbounded fields to existing ratcheted types. New structs below
have at most six conceptual fields. Before adding emitter state, choose a small
owned analysis-state grouping that does not grow existing ratchets or duplicate
plans; no baseline acceptance is authorized by this document.

## Concrete analysis boundaries

All plan data belongs to the function compilation arena. Plans borrow the final
analysis inputs; no process-global token ledger, mutable static function cache,
or runtime address belongs in an analysis result. Numeric IDs identify static
values, storage, bundles, tokens, scopes and guards independently.

`RcInput` has six groups:

| Field | Contents |
|---|---|
| `code` | Physical bytecode program/function and native IR operand type states. |
| `flow` | Final `qbe_liveness.Solution` and `ownership.Analysis` from the shared retained-place fixpoint. |
| `physical` | Native layout/count-shape access and a canonical storage map covering locals, operand positions, return pads, forwarding and `qbe_moves` aliases. |
| `mutation` | Final COW places, scope intervals and uniqueness/loop constraints. |
| `contracts` | Direct function, indirect signature, runtime-helper and host-adapter ownership contracts. |
| `policy` | Resolved runtime ABI/instrumentation and entry/result convention. |

The planner must not infer storage equality merely from `parents` or a `borrowed`
role. Actual slot aliases share one storage ID; distinct slots holding equal
pointers remain distinct possible owner edges. Operand positions are keyed by
program point/value version. Loop headers and joins get canonical identities,
not an ever-growing sequence of simulated iteration tokens.

`ValueState` has five fields: `value`, `ty`, `storage`, `shape`, and `ownership`.
`shape` describes direct physical owning edges, separately from resource drops.
The ownership union is:

- `plain` or `empty`;
- `owned`: a token bundle with initialization guard;
- `borrowed`: anchor value/storage, projection and valid interval;
- `inout`: caller place plus its replace/loan convention;
- `held`: a scope hold identity, allowed only for lifetime obligations, never
  silently promoted to a snapshot owner by a value-copy action.

An inline aggregate has a bundle of direct edges. A recursive box pointer is
one edge even when `needsCopy` is false. A partially initialized aggregate needs
field/tag initialization facts. Guarded owned state represents the fresh branch
of unique-from-borrow; the reused branch retains its anchored borrow. Ordinary
owned/borrowed joins normalize to owned unless that special guarded state is
explicitly represented and verified.

`CallContract` has six groups:

1. Parameter conventions: read loan, caller-storage inout or mutable payload
   loan, with an explicit rule for any consumed runtime argument.
2. Success result: canonical owned, certified borrowed bundle or plain.
3. Failure result: no result owner; exact argument/partial-progress guarantees.
4. Mutation/effect facts relevant to borrowed anchor stability.
5. Optional borrowed-entry certificate: one initial readonly anchor, physical
   result shape and every-return proof. Mixed-fresh `borrow_origin` is insufficient.
6. ABI identity and dependencies for caller-visible fragment invalidation.

Guest calls initially all use the canonical owned-result convention. Direct
certified borrowed entries are an additive optimization after owner balance
passes. Indirect calls, exports and foreign adapters keep canonical ownership.
Runtime helpers need explicit producer/read/write/take contracts; they cannot
inherit the guest convention merely because they return the same machine type.

## Plan and emitter handshake

`RcPlan` has six groups: entry actions, instruction actions, CFG edge actions,
failure checkpoints, scope obligations and verifier metadata. `plan(a, input)`
returns a plan; `verify(input, plan)` checks all reachable states before emission.
Unknown optimization facts fall back to owned materialization and conservative
copying, not a prototype-style unsupported-program refusal.

Each instruction action group has before-operation, commit and after-operation
lists. An action names typed source/destination storage and an ownership effect:
receive producer token, pin-aware copy/take, proven relocation, release,
borrow/detach/commit, or scope hold/pin cleanup. A commit point specifies when an
input token is consumed and the destination becomes initialized. Edge actions
name the actual predecessor/successor, including switch/propagation edges, not
only a source instruction number.

A failure checkpoint is **(instruction, lowering substep)**. One bytecode
instruction can call several allocating helpers and initialize several fields;
those calls need different cleanup states. Existing `@failure` branches must
route through a checkpoint cleanup or an equivalent initialized-token bitmap.
The shared final failure block cannot blindly release every syntactic local.
Step/frame guards before execution, allocation failures after a partial result,
and a failed callee have distinct obligations. Preserve the original trap and
trace while cleanup runs.

The emitter consumes actions at named lowering events. It must not parse its
own QBE text to rediscover ownership. Before frame cleanup, transfer the result
out of the frame's owner ledger or materialize it into protected result storage;
then release remaining owners/scopes and restore arenas/resources in the agreed
order. Heap-backed frame retry/re-emission must reset emission state without
changing the immutable plan or issuing duplicate analysis tokens.

The verifier checks owner-token conservation, exactly-once consumption,
initialized-only release, anchor validity, scope balance, loop-header state
agreement and empty failure results. A release is infallible and allocation-free
under the runtime contract. A semantic take may fail when pins require copying.
Keep resource-drop ordering distinct from count decrements.

## First proposed failing tests

Tests assert ownership actions and runtime lifecycle, not just unchanged stdout.
The runtime team must provide isolated counter/failure hooks; do not add a guest
standard-library API merely to expose internals. Each runtime fixture first
asserts the active RC ABI, so a GC fallback cannot satisfy it.

| Priority / fixture | Initial assertion and failure it detects |
|---|---|
| P0 owned producer → local → caller → discard | A fresh runtime producer supplies one owner; receiving/moving it causes no extra retain, and final discard returns that payload's live count to zero. Detects floating adoption, double increment and missing caller release. |
| P0 canonical borrowed-parameter return | A function returning `arg.items` establishes owned result edges; caller can outlive/rebind the argument. Verify the retain/publication and one final release, including immutable bytes and pure box results. Detects using `needsCopy` as an RC predicate. |
| P0 overwrite and self-assignment | Incoming ownership is prepared before old contents release; `x=x`, record field replacement and two fields naming one payload keep the right multiplicity. Detects premature free and deduplication by pointer equality. |
| P0 branch/loop/propagation | Fresh and borrowed arms normalize correctly; zero and multiple iterations balance; early return and `try_result` release abandoned operands. Assert separate edge cleanup, not a global dead-local list. |
| P0 mutable-reference lifetime | Adopt the permanent record/fixed-array/branch/forwarding fixtures plus an allocating later argument and readonly snapshot. No release before the future `ref_local` or its consuming call; independent values remain independent. |
| P0 checkpoint rollback | Fail each helper in a two-field constructor and a call result conversion. Release only initialized owners, preserve source inputs and original trace, and publish no failed result token. |
| P1 conditional child detachment | Closed field and indexed edits reuse a borrowed child without a spurious snapshot retain; when shared, a fresh token commits once or releases on failure. Retain earlier-match/outer-list snapshot negatives. |
| P1 pending receiver | Callback replaces the parent or removes the only owner while a held/pinned receiver is live; result publication clones the finite pinned path and cleanup restores pins before dropping its holds. No stale write or leak. |
| P1 borrowed-entry negatives/positive | Fresh alternative, mixed record fields and fresh wrapper use owned entry. A certified readonly inline accessor can use borrowed entry only while its anchor is stable. Mutating callee return behavior invalidates callers. |

The first structural tests use checked/lowered real snippets, then inspect plan
queries for token source, commit and edge cleanup. Add verifier-negative cases
for double release, missing result ownership, a dead borrow anchor and releasing
an uninitialized conditional token. These exercise invariants independently of
the action producer. Runtime tests repeat on QBE and LLVM and include trap paths;
exact retain/release counts are asserted only where the contract makes them
stable, with live-allocation balance for larger fixtures.

## Required dependencies before source work

Receive the accepted base and final selector API from root, and a versioned C
header specifying: owned-success producer contracts; copy/take commit/failure
behavior; internal relocation; owned versus tagged borrowed uniqueness; scope
journal/hold ownership and unwind ordering; direct-edge descriptors; allocation
failure and lifecycle counters; and how heap/arena/immortal payloads are identified.

Resolve normal/trap cleanup ordering with the arena owner. Receive an exhaustive
runtime-helper contract inventory or an explicit conservative contract for each
helper family before general lowering claims coverage. Runtime helpers that
allocate cannot temporarily return unowned results without an explicit hold.
Freeze certificate serialization with root before emitting the borrowed entry.
None of these dependencies authorizes starting on an unaccepted base.
