# D9 compiler RC action and call contract — 2026-09-26

This proposed contract complements the
[RC readiness inventory](d9-rc-readiness-2026-09-26.md),
[scope contract](d9-rc-scope-contract-2026-09-26.md) and
[allocator review](d9-rc-allocator-review-2026-09-26.md). It is design work only.
WP-4 implementation still requires accepted WP-3f and WP-4pre on `main`.
The inspected production analysis includes the `ref_local` liveness fix
`21fafaee`; physical return-origin facts were inspected on WP-4pre `450d151a`.

Use one canonical owned-result ABI, final D9 liveness, and an explicit ledger
of physical ownership. Add borrowed-result entries only when every returned
counted edge is proved borrowed. Existing move/borrow/copy classifications are
inputs to that proof, not a reference-count ledger by themselves.

## Physical state and analysis ordering

The compiler should distinguish these states for each value version:

| State | Meaning and cleanup |
|---|---|
| Plain | No counted edges; scalars and inline aggregates with no counted fields require no RC action. |
| Owned | One token for each direct physical owning edge described by the value's count shape. Repeated pointers in two owning fields represent two edges. Move transfers the token; cleanup releases it once. |
| Borrowed | No owner token. An identified anchor and projection keep the backing alive and stable for the entire use interval. Merely copying inline bytes creates no token. |
| Inout | A borrowed address into caller storage or a mutable collection loan under its existing ABI. The callee may replace owned contents through that address but does not own the parameter slot. |
| Held | A non-sharing lifetime hold belonging to a receiver/borrow scope. It keeps a specific backing alive but is not a value snapshot. |
| Empty/moved | Storage carries no live ownership obligation; cleanup must not interpret stale bytes as an owner. |

An inline aggregate owns a bundle of edges, not an allocation for the aggregate
itself. A copied recursive-box pointer is one edge; cloning its body establishes
the body's direct child edges separately. Derive a physical **count shape**
from native layouts/descriptors, distinguishing managed RC references, raw
backing/metadata, and existing unique resource-drop obligations. Neither
`needsCopy` nor `layout.trace` alone is that classification: immutable bytes
and pure recursive boxes need counts, while a GC-traced resource pointer is
not permission to share or close a unique resource twice.

The plan consumes facts in this order:

1. Physical type lowering and existing address-local selection.
2. `qbe_liveness.solve`, including `ref_local` as a use; current ownership/COW
   planning and `retainPlaces`/`extend` iterate to stability.
3. Final COW places/scopes and physical storage decisions from moves,
   forwarding, caller storage and coverage planning.
4. RC ownership simulation, action planning and verification against those
   facts. Choose borrowed-result calls only when their anchors already meet
   the final lifetime/stability proof. If an optimization adds an implicit
   lifetime, return to the shared fixpoint rather than editing RC rows alone.
5. Emit RC actions and ordinary operations from the same verified plan; apply
   the current loop-versioning/hoisting vetoes to the final mutation plan.

`ownership.Analysis.roles`, `parents`, `transfers`, `moves`, `operands`,
`copies` and `cows` remain useful. Their limits must stay explicit:

- `owned` is a logical role, not proof an increment happened. Earlier match
  bindings and COW-elided payload copies can have that role while physically
  borrowing. Build states from producers, storage and transfers, retaining
  projection/arm provenance where the existing parent chain loses it.
- A last-use whole-value load can transfer a physical owner token. A last-use
  field/element projection cannot automatically take the parent's token:
  either remove that exact edge while consuming the parent safely, or acquire
  the projected value before releasing the parent.
- `value_copy` elision means a COW sharing action was unnecessary. It does not
  prove an RC owner may be omitted. Physical aliases introduced by
  `qbe_moves` must name one storage/token ledger; two independent owning slots
  must not be collapsed just because they contain equal pointers.
- Existing resource lifetime/drop planning remains authoritative for resource
  hooks. RC releases must not duplicate those hooks or change their ordering.

Track value versions at writes, not one permanent ownership bit per local.
For inline construction, either all returned counted fields form one proved
borrow bundle or materialize an owning bundle, moving owned inputs and
acquiring borrowed ones. Partially initialized constructors need initialized
field/tag state so failure releases only completed edges.

## Action table and control-flow edges

The following are semantic operations, not proposed final C symbol spellings.
Runtime names and representation should follow the separately reviewed
owner/hold/pin API contract.

| Event | Required action |
|---|---|
| Fresh runtime result | On success receive one already-owned result; record its token without incrementing. On failure the output owns nothing and the runtime has undone its partial construction. |
| Independent value publication from a borrow | Pin-aware value copy establishes owned destination edges. It may allocate to preserve a pending receiver's snapshot semantics. |
| Last-use semantic publication of an owner | Pin-aware value take transfers ownership when permitted, but copies the finite pinned path when required. It is not necessarily allocation-free. |
| Proven physical relocation | Transfer token/storage without a snapshot, count change or allocation. This internal operation requires a proof such as backing growth or compiler slot forwarding; source-level `move` alone is insufficient. |
| Overwrite of an owned slot | Prepare the incoming ownership first, publish it, invalidate the source token if transferred, then release the old contents. This ordering handles self-assignment and shared child pointers. |
| Read of a field/element | Borrow with a valid anchor; stabilize to an owned value before escape or an invalidating write. The descriptor and container backing must also survive the read. |
| In-place mutation | Use the existing uniqueness proof and the correct owned/borrowed receiver interface; preserve scope pins and source evaluation order. |
| Last use/discard | Release an owned token once after its final use, not when an alias local merely dies. Dropping a borrow has no owner-count effect. |
| Scope entry/exit | Acquire a separate hold journal; on exit unlink the active scope, restore pins in reverse nesting order, then release its holds and journal storage. |

Derive edge releases from the ownership state after the instruction, not by
blindly subtracting `live_in` rows. For each successor, account for tokens
transferred into its live slots/operands, a heap slot or the function result;
release remaining initialized owners after their last use. A borrowed value's
anchor must remain protected until that borrow ends. A scope journal has its
own obligation even when no ordinary local is live.

At a join, predecessor states must agree on ownership obligations. If one arm
owns and another borrows, normally materialize ownership on the borrowed edge
before merging; differing borrow anchors normally require the same conservative
normalization. Do not release a token at a branch merely because it is dead
on another branch. A switch arm may borrow/copy/move its payload and must
account for the scrutinee exactly once. `try_result` transfers the error payload
on its propagation edge and releases other owned operands/locals there.

Loop backedges must reproduce the header's ownership state. Rebinding in each
iteration releases the prior value once, and zero-iteration paths cannot
release an uninitialized slot. Hoisted uniqueness retains the current proof
that no intervening call, share, place write or restructuring invalidates it.

Runtime traps use a separate cleanup state from normal `Result` values. A
callee failure must not make an uninitialized result appear owned. Every
recoverable failure path unwinds initialized temporary owners and active
scopes, preserves native error/trace frames and follows resource/arena cleanup
ordering. Do not remove those frames when removing GC root publication.

### Closed field/index edits need writable borrow states

The stage-3 field-return and indexed-return proofs can keep an extracted child
as a writable borrow of its parent edge, without adding a snapshot owner.
Require the existing first-use/no-observer/closed-control-flow/unchanged-place
proof plus physical lifetime provenance. Keep the earlier-match and outer-list
snapshot negative cases conservative.

Two uniqueness interfaces are necessary:

- **Unique from owned:** consumes/replaces the caller's owner token on success;
  failure leaves it valid under the helper's rollback contract.
- **Unique from borrowed place:** leaves the parent's owning edge intact.
  Reuse returns the same borrowed payload; detachment returns a fresh owned
  payload. The compiler tracks that newly created token conditionally. At
  commit, transfer a detached token into the proved destination and release
  the old edge; an unchanged borrowed edge needs no count churn. On failure,
  release only a created token, leaving the parent obligation intact.

The conditional token is a guarded initialization state, not an unconditional
owner inferred from the temporary's `owned` role. If the proof cannot identify
the destination edge and lifetime, acquire an ordinary independent value
instead. Never use a consuming uniqueness helper on a child still owned by an
unchanged parent. This distinction is necessary to preserve marker and
instance-table edits without either premature release or artificial sharing.

## Guest call and result ABI

Read-only parameters are borrowed for the call. Keep their actual anchors
alive through argument evaluation, the call and result establishment. If a
callee rebinds its private parameter local, its new value becomes a local
owner; it does not release the borrowed caller value. Existing source mutation
and overlap checks remain unchanged.

`mut` records and fixed arrays use caller storage via `ref_local`; operations
that replace their contents transfer/release the corresponding caller-owned
edges. The callee never releases that slot at function exit. Mutable managed
collections retain their current payload-loan ABI: caller preparation makes
them unique and pins them, and passing a payload pointer does not silently
become permission to rebind the caller's pointer. Model legal local rebinding
and caller-storage replacement according to `callerStorage` and the existing
lowering, rather than assigning one convention to every `mut` parameter.

The canonical guest entry returns an **owned result** on success. Every counted
result edge has one obligation that transfers to the caller. A return may move
an owned value or acquire a borrowed one, using pin-aware publication. Scalar
results simply have no counted edges. Returned inline bytes go into the usual
caller result storage; no returned address may name a dead callee scratch slot.
On a trap, result ownership is empty and the caller checks the trap before
using or releasing it. A normal `Err`/`None` remains a normal tagged result.

Indirect calls, exported guest functions, host adapters and unresolved call
targets use this canonical result convention. A caller must not treat that
result as borrowed merely because its analysis found parameter provenance.

### What WP-4pre proves, and the additional borrowed-entry proof

`borrow_origin` is an upper bound on which parameters a result may retain.
It is not proof that the result consists entirely of borrowed storage. In
`origins.Origin.merge`, a fresh origin has no parameter bits; joining fresh
with parameter 0 still produces `params[0]`. Consequently these examples all
need further analysis:

- One return branch gives an element of a parameter, another gives a freshly
  allocated list. The summary can still be `params[0]`.
- A fresh inline record contains one parameter-derived byte string and one
  freshly allocated collection.
- A newly allocated box/list wrapper contains parameter-derived children.
  The wrapper allocation itself still needs an owner.

Recommend a second, internal **borrowed-result entry** only for certified
callees. Its parameter/result machine layout can match the canonical entry,
but it has a distinct symbol and ownership contract. Initially restrict it to
one read-only parameter anchor, matching the current ownership source model.
Prove on every reachable normal return that each counted result edge is
borrowed from that parameter's still-valid reachable storage or is immortal;
no fresh owned result edge, local lifetime, unknown source, invalidated view or
uncertified recursive call may escape. An inline wrapper with only such
fields is allowed; an independently allocated wrapper is not.

The borrowed entry returns no owner token and emits no matching return retain.
Its caller invokes it only when the chosen actual argument remains alive and
stable for the entire result lifetime, including later argument evaluation,
callbacks, pending places, slot replacement and arena boundaries. Otherwise
the caller uses the canonical owned entry. If a borrowed result subsequently
needs an independent lifetime, acquire it before its anchor can be invalidated.
Do not repair the mismatch by dropping an owned callee result's release.

Both entries must agree on observable values, error behavior and diagnostics.
Function values always name the canonical entry. Certifying small accessors
first avoids duplicating large bodies without measured benefit. An owned
wrapper around a certified borrowed entry is possible only if its pin-aware
acquisition, failure cleanup and trace identity remain correct. No hidden
runtime return-mode argument is required by this proposal.

Keep logical `return_origin` unchanged. Add an explicit result contract and
borrow certificate to native fact/hash/explanation surfaces; include the ABI
version, result count shape, parameter anchor and certificate dependency in
caller/callee fragment identities. Callee edits that introduce a fresh result
must invalidate old borrowed-call objects and remove the old entry safely.
Unknown or multiple-parameter provenance uses the owned ABI initially.

## Runtime and foreign boundary conventions

Fresh runtime producers return exactly one owned result on success. Receiving
it transfers that obligation without an extra retain or recursive E2b-style
adoption walk. Constructors establish direct child edges as they initialize
them; failure unwinds the initialized subset and returns an empty output.
Give every helper an explicit argument/result contract:

| Helper family | Initial convention |
|---|---|
| Allocation, clone, text conversion | Borrow inputs; owned success result; partial-construction rollback on failure. |
| Element/dictionary reads | Borrowed result tied to receiver/backing, unless the helper contract explicitly creates a new owned wrapper. |
| Append/insert/write | Receiver is a mutable loan; borrowed input is copied or an owned input is taken under a declared commit rule. Caller knows exactly when it relinquishes an input token. |
| Pop/take/remove returning a value | Return an owned value. Pin-aware take may copy a pending receiver path even when removing its only ordinary owner. |
| Clear/truncate/overwrite | Release precisely removed live logical edges; preserve returned or overlapping inputs before releasing old contents. |
| `setdefault`/bulk update | Spell out inserted, existing-key, discarded-default, partial-progress and failure states; do not infer them from a generic write opcode. |
| Raw backing growth | Relocate existing logical edges without duplicating counts; never scan capacity as initialized length. Addressed held storage cannot move, but new backing can replace it while the captured storage remains held. |

Container headers own live logical elements/keys/values; raw backing blocks
own storage bytes. A held retired backing is not a second owner of every
element. Dictionary entry descriptors embedded in a header must survive all
readers/destruction work that uses them. Byte views count their canonical
backing owner, never an interior `storage` pointer as though it had a header.
A byte view's `work.owner` names that owner; a buffer's duplicate `work.owner`
alias/marker must not create another owning edge. These distinctions must come
from the runtime contract, not a generic scan of pointer-looking fields.

Raw foreign pointers do not automatically follow the guest ABI. Generated
host/C-ABI adapters must convert or copy borrowed/static data, transfer an
explicit owned foreign result, and balance cleanup on provider errors before
exposing the canonical guest owned result. Keep resources/grants under their
existing authority and unique-drop rules. Stamp runtime mode and ownership ABI
into linked provider artifacts; do not share managed pointers across the
legacy GC and value RC heaps implicitly.

## Reference and scope lifetime integration

The `ref_local` use keeps its anchor alive before its address is placed on the
operand stack; the operand reference then keeps it valid through later argument
evaluation and the call. RC must preserve both intervals. An address borrow is
not an owner increment, but also not permission to release its anchor at the
last ordinary load. The permanent mutable-reference GC regressions remain
required RC lifetime tests.

Adopt the owner/hold/pin draft's separate counters: ordinary owners affect
snapshot uniqueness, holds affect lifetime only, and destruction requires both
to reach zero. A pinned receiver can have zero owners after a callback replaces
its parent while its scope hold keeps it alive. Snapshot publication, including
semantic take, copies the finite pinned path. Proof-only relocation does not.
Scope exit restores the journal's pin states before releasing holds; partial
preparation rolls back only its own pins/holds and initialized allocations.

Arena holds cannot extend freed chunks. Unwind scopes targeting a dying region
before its bulk teardown, while preserving older-region/heap receivers held
across younger callbacks. Arena-owned heap edges release at overwrite or
teardown; escape establishes output ownership and rolls back partial clones.
Resource hooks, scope cleanup and arena teardown need one documented ordering
on normal exits and traps, not three independent destructors for the same edge.

## Initial serial interface and tests

The serial contract change should define the following compiler interfaces as
small grouped types; these names are proposals, not new files in this change:

- `RcInput`: code/layout context, final liveness, ownership facts, places/scopes,
  physical storage map and call/runtime contracts.
- `ValueState`: plain, owned token, anchored borrow, inout, held scope and empty
  state. Token validity includes initialized/conditional state and value version.
- `RcPlan`: entry actions, instruction actions, edge actions, failure cleanup,
  scope obligations and verifier metadata.
- `CallContract`: borrowed/inout parameter conventions, canonical owned result,
  optional certified borrowed entry, runtime mode and ABI/certificate identity.
- `plan(allocator, input)` produces actions; `verify(input, plan)` checks every
  reachable edge's ownership balance and borrow validity before emission.
  Lowering consumes that plan rather than rediscovering ownership from IL text.

Freeze these interfaces with the C owner/hold/pin and allocator contracts before
parallel runtime/emitter/arena work. Required early tests are:

1. Record/fixed-array `ref_local` after allocation, through branches, forwarding
   and an allocating later argument; readonly snapshots remain independent.
2. Branch/loop ownership balance, zero iterations, conditional construction,
   `try_result`, switch payloads, early return and failures at each allocation.
3. `borrow_origin=params[0]` with a fresh alternative, mixed fields or fresh
   wrapper: all must retain the canonical owned result. A schematic-style
   inline accessor with only borrowed byte fields gets the certified entry.
4. Callee edits from borrowed to fresh and back, generic/indirect calls, warm
   caches, linked artifacts, and owned/borrowed entry value/error equivalence.
5. Field/index edit reuse and detach, prior match aliases, outer snapshots,
   conditional token cleanup and pin-aware pop/take during receiver callbacks.
6. Owners zero/holds positive, nested pin restoration, receiver replacement,
   backing growth, dictionary descriptor lifetime and arena unwind/escape.
7. Immutable bytes and million-deep boxes, shared DAG duplicate edges,
   owned host results, borrowed foreign data and exactly-once resource cleanup.

Counters and explanation output should report actual retained/released edges,
borrowed-result calls, conditional ownership and scope holds. WP-4pre's static
schematic improvement must become fewer dynamic RC operations with balanced
ownership. Production acceptance still requires full correctness and the
separate WP-4 instruction/RSS gate against the accepted stage-3 GC baseline.
