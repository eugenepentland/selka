# Scalar readonly callers of managed borrowed helpers

Status: implemented and measured; see the companion results report. The design
and limits below were reviewed before measurement.
Base: real merge `6edbe2ed` of named-record `14c73780` and readonly-v1 `c62adfb0`.
The matched before compiler is built from that exact merge, without readiness/key
changes. The early optional-activation draft was rejected during root review;
the shared physical preflight below replaces that draft.

## Actual target and current refusal

`sexpr::form(nodes, index, name) -> bool` calls `sexpr::at` twice. `at` returns a
48-byte Node; every managed leaf is anchored by `nodes` or immortal fallback
bits. Saved emission already includes the independently certified
`at_rc_borrow` unit, and the ordinary form body calls that symbol at both sites.
The caller then performs four `native_loan` calls (Node twice, Span and bytes),
plus named-slot owner retain/drop and frame bookkeeping. Other scalar work in
`text.matches` is inlined in this saved body. Removing form's activation-wide
ownership traffic is the target; no dynamic saving is predicted from these
static counts alone.

Root's v1 composition accepts only plain-result dependencies. That refusal is
correct: `qbe_rc_borrow.certificate` currently starts with `frame.get`, which
returns null when readonly emission sets `state.active=false`. Merely accepting
a managed helper in the analyzer would silently choose its canonical owned
symbol while after-op ownership publication is disabled. The result would have
an unjournaled owning token. Exposing the analyzer's internal Answer would also
be unsound: its accepted immortal-only managed and scalar dependency results
are broader than the public alternate-entry admission contract.

## Proposed certificate boundary

Extend readonly-call analysis as a separate version (v2), preserving the v1
closed opcode grammar, scalar/plain root result, parameter nonmutation and all
unique/materializing-box refusals. No runtime or general borrowed-entry grammar
change is needed.

Every direct non-self call is classified by its checked return shape:

* Plain result: independently prove the same closed readonly grammar for the
  complete callee, as v1 does. Its canonical symbol remains the target. Result
  type alone never grants admission; hidden allocations, mutation, callback,
  scopes and unique obligations still refuse the complete root.
* Managed result: require a nonnull **public** `rc_calls.borrowedIn` certificate
  for that exact callee, program, catalog and runtime ABI. Do not reuse internal
  `analyze`, Answer, may-provenance or a caller-expanded proof budget. Validate
  argument count/types, return-layout identity and certificate parameter index.
  Apply bounded transitive authority checks to the returned managed type and
  its actual anchor type, refusing unique/finalized/opaque/callable or unknown
  materialization. Save the complete certificate with exact caller PC and callee
  ID.
* Unique result, host/C/indirect call, unknown consumer or failed public proof:
  decline the entire readonly root and retain ordinary journaled lowering.

The managed query is independent, so it uses exactly the query used by
`appendBorrowedUnits`. Success cannot depend on a caller-only generous budget.
An all-immortal managed helper with no public parameter anchor remains refused,
even if a broader internal analysis could establish that it owns no heap leaf.
This deliberately avoids adding another public return convention.

## Activation anchor proof

All managed data in an admitted raw activation is borrowed from original
activation inputs or immortal data. This is an induction over the existing
closed grammar, not a uniqueness or semantic-copy-bit inference:

1. Parameters start as external caller-anchored values. Parameters cannot be
   assigned, passed mutable, or escaped to host/indirect authority. The parent
   activation remains alive until the scalar result is returned.
2. Raw reads, non-owning local stores, inline record/variant construction and
   approved projections only copy physical bits whose managed leaves inherit
   those activation anchors. Ordinary join paths may select different original
   parameters; all remain alive, so this scalar caller needs no single global
   parameter anchor. Validated bytecode supplies definite initialization; no
   unavailable local may be invented by a new proof transfer.
3. A managed call's public certificate identifies the exact actual operand
   anchoring every result edge. That operand is itself input-anchored by this
   induction. Immortal alternatives are already covered by the public every-
   return certificate. No callee may return storage dependent on its own frame.
4. Scalar arithmetic/branches do not alter anchors. Raw DROP/POP are no-ops;
   raw MOVE is a read because unique/drop-bearing layouts are excluded. A local
   rebind discards borrowed bits only, never releases the external anchor.
5. There is no mutation, region exit, owning publication, callback, unique
   cleanup or unknown call anywhere in the admitted graph. Thus later reads
   remain safe even if the original parameter's last semantic bytecode use has
   passed. The anchor lifetime is the whole activation, not semantic liveness.

Existing planned emitter effects are checked in the shared public certificate
before any caller or dependency is selected: no COW share/read-capture, uniqueness, place fill,
scope begin/end or loop-entry ownership hook may execute. Early RC edge cleanup
already skips borrowed/readonly bodies; retain that explicit invariant.
Unexpected physical effect declines this optional readonly candidate and every
plain caller depending on it. There is no late independent selection fallback.
Pure capture/index calculation may remain only when it cannot publish a token
or address later invalidated storage. Initially rejecting all such hooks is
simpler if the actual form body still admits; inspect its finalized facts.

The existing readonly body's structured self recursion can remain: it produces
only a scalar result and its own parameters are anchored by the suspended parent
activation. Mutual recursion retains v1 refusal. A managed helper's public
certificate separately retains its current recursion refusal.

## Explicit emission routing and representation

Add one cohesive optional readonly certificate to EmissionPlan (five fields on
this matched base, six after this change; the independent append_loops join will
make seven). Store `{identity, calls}`;
a managed route is `{pc, target, certificate}`. State keeps its existing seven
fields and readonly bool. The immutable route array belongs to the emitter's
function arena; no scoped analysis pointer escapes.

`qbe.zig` obtains the complete artifact before selecting readonly emission and
stores it only on success. Selection occurs at v1's early point; final invariant verification runs after
later physical refinements have skipped the inactive body, before allocation. `qbe_rc_borrow.certificate` (or a separate call-route helper used at
the same call-selection site) first checks readonly state directly through
`self.cow.rc`, before calling `frame.get`. At a managed call it must find an
exact PC/target/type-matching saved route and return that concrete certificate.
A missing or inconsistent route is an internal compiler error, never fallback
to the canonical owning symbol. Plain calls remain canonical. Ordinary active
callers and borrowed-entry bodies retain their existing public-query routing.

Do not globally relax frame.get, reenable a hidden journal, or infer symbol
selection from result type. `ops.after` continues to do no ownership work in
the readonly caller; locals/arm payloads retain the existing raw-bit lowering.
Function-value, exported and provider ABIs remain canonical and owned.

Keep the exact existing ABI for the borrowed callee: scalar managed pointers
are register values; ordinary inline records cross by-value in QBE/LLVM and
materialize into caller-owned result storage. Values larger than 4096 bytes use
caller `%auxPC` through the existing indirect result argument. The ordinary
result store must complete before any later call can reuse temporary storage.
Test small inline Node, a pointer result and a >4096-byte managed inline result;
include storing a result then making a second helper call before reading it.
No raw pointer to a callee stack aggregate may survive its return. Existing
separate alternate Unit/frame-map metadata stays authoritative and unchanged.

## Cache and bounded work

Version readonly composition v2 and the supplementary RC caller key. Hash the
root grammar/ABI/signatures/layouts/opcodes in deterministic source order, every
plain dependency identity, and every managed route's call PC, callee stable
name, public parameter/shape/dependency identities. Cache refusal as well as
success. A helper losing its certificate must invalidate the unchanged caller,
restore its journaled body and stop targeting the alternate symbol. The managed
callee's own unit key and alternate selection still use the public standalone
query; a warm fragment must not depend on an alternate absent from selection.

Retain a no-eviction completed memo and fail closed on recursive/in-progress
reuse. Bounds: at most 16 completed plain functions including the root,
plain-analysis depth 16 and 65536 instruction visits as v1; at most 16 distinct
independent managed public queries **globally across the entire root composition,
including its plain descendants**, memoized for repeated call sites. Each of
those keeps its existing 65536 state-cell/524288 work/depth 16/dependency 16 caps.
Document these as composed bounds, not one shared 524288 allowance. Stored call
routes are bounded by the checked root instruction count. No process-global
memo or cross-catalog pointer cache is introduced.

## Runtime ordering and controls

Preserve per-call frame/native-stack/step checks, checked indexing/tag tests,
arithmetic and assert traps at their original PCs. There are no new runtime
operations or failure points. The removed O/H helper drains have no observable
callback work: at an ordinary guest boundary the dead queue is drained, and
finalizer reentry inherits an active drain. The admitted graph cannot enqueue
a new death or execute a callback. Caller anchors remain journaled in the
external owning activation on success and every trap. Arenas belong to that
external activation and cannot close inside the admitted graph.

Before any measurement, require actual form admission and exact _rc_borrow
routing in emitted QBE and LLVM manifests, no ownership helpers/journal in the
raw caller, and an emitted independent alternate for each selected target.
Keep canonical/function-value controls owning. Test parameter-reordered managed
helpers, mixed immortal alternatives, multiple original anchors selected by
branches/loops, saved first result across a second helper call, snapshots and
caller arenas. Refuse fresh/mixed managed returns, missing anchors, mutation,
forwarded mut references, host/indirect/callback authority, owning box
materialization, unique payloads and exhausted/mutually recursive proof graphs.
Near each proof bound, independently query every selected managed callee and
check emitted symbols; test cold/warm cache plus transitive helper edits and
certificate loss. A small exact bounds/step/frame/overflow budget set is enough.
Only after review, implementation and those controls would matched exact
schematic output/counters/instructions be measured against the immutable
post-v1 control. No timing or acceptance claim belongs to this design.

## Shared planner preflight and final invariants

Root review found that late per-function quiet refusal was insufficient for
plain helper composition: a caller could select raw emission while its callee
fell back to an owned body. `rc_readonly_plan.certify(catalog, functions,
function, budget)` now runs before public certificate memoization. It invokes
production `native_ir.analyze`, `qbe_liveness.solve`, `ownership.analyze` and
`cow_plan.plan`, with identical records/functions and
`shares = !value_semantics.enabled()`. Pinning is exactly
`native.layout(local.ty).drop`, matching `Emitter.planOwnership`.

Accepted preflight has no surviving places, capture/share/check/fill or loop
ownership actions. Thus `retainPlaces` cannot add implicit liveness and
`prepareScopes` cannot publish begin/active captures. No COW checks also means
RC dehoisting has no effect. Early readonly selection prevents late RC loop,
named-write, dictionary-tail and journal refinements. Final verification checks
the common quiet predicate, capture metadata and empty field-transfer,
plain-write and dictionary-tail certificates. Field transfers need caller
storage and UPDATE writeback; plain writes need UPDATE and dictionary tails
need collection writes. Those are absent from the closed grammar.

A validated pure-bytecode negative keeps a conditional list value on its
operand stack. The general ownership planner loses exact provenance at the
join and conservatively inserts a hidden capture SHARE. Logical grammar alone
accepts it; shared physical preflight refuses both this leaf and its plain
caller. Ordinary source lowering of the conditional through locals remains
admitted. A valid conservative refusal therefore stays optional, rather than
becoming an internal error.

A single Budget is shared across all plain dependency preflights in the root
memo. Each preflight has at most 1024 instructions and 256 locals. It charges
`n * (n + locals)` against 65536 total matrix cells and
`n * (n + locals) * (locals + 1)` against 4194304 total analysis-volume units.
These deterministic input-volume allowances do not count individual inner
planner operations; existing bounded planner fixed points still apply. Every
successful dependency has an input-volume subset of the successful root, so
standalone selection cannot fail solely because its caller had more budget.
All changes, admission and refusal are bound by readonly v2 and RC caller-cache
v2 identities. The 16 managed public queries remain globally shared as above.

## Immutable octet read refinement

Actual form emission exposed an existing v1 grammar restriction: inlined
`text.matches` uses GET_INDEX bytes, but v1 allowed only inline-array indexing.
The reviewed refinement permits managed indexing only when
`typed.isByteString(record)` and its buffer element is u8. Mutable byte_buffer,
str, dictionary and managed-result accesses remain refused.

The existing emitter path is aggregate arrayAccess, managed emitIndex's
ordinary indexed branch, normalizedIndex, then inlineIndexRead. It loads length,
normalizes signed indices, retains the same bounds/detail trap, computes the
backing address and loads one scalar byte. Success allocates nothing, releases
nothing and calls no helper. Original activation anchors protect byte payloads;
no new runtime path or return convention is introduced.

## Review checkpoint

Root and both peers reviewed the explicit managed-route design. Root separately
reviewed shared production-planner preflight, early selection and final invariant
verification with no blocker. Focused tests now include optional conservative
SHARE refusal propagated through a plain caller. Actual emissions, complete
result storage, cache invalidation and paired runtime controls were checked
before timing. The companion results report preserves a pre-existing combined
LLVM wrapper build failure separately from successful split and Debug controls.
No Stage 4 acceptance claim is implied.
