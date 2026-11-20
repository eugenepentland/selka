# Constant managed results need an explicit immortal entry

Status: separate proposal; no immortal implementation or timing. The current
dual-certificate prototype remains unchanged. Its initial compiler is
`51d4fd36a661605d29d8d0d6815eeb43b165a01ada19f56b81f93c1b8982df26`,
based on `83386525` plus the uncommitted borrowed-entry prototype.

## Actual refusal and target coverage

The prototype correctly leaves `sexpr::at_rc_borrow` journaled. Its fallback
calls `text::empty() -> Span`, which returns three integer zeros and the frozen
empty byte literal. `borrowedIn` cannot certify that zero-argument function:
there is no parameter anchor. The private borrow analyzer's immortal answer
is not a public call convention and will not be used as one.

The saved actual schematic emission also identifies
`layout::partPin_rc_borrow`: its two fallback calls are to `text::empty` too.
Both alternates still link an RC frame. `layout::innerPin_rc_borrow` already
has no ownership frame and calls `partPin` and the plain `layout::depth`.
`sexpr::form` is already raw and calls `at`; `text::matches` is inlined there
by existing lowering. Thus this proposal targets two actual missing raw
entries and their existing callers, rather than counting all managed helpers.

Receipts are `.tmp-borrowed-frame/schematic-admission-initial.json`,
`borrowed-entry-call-coverage.json`, `schematic-initial.json` and
`text-empty-initial.ssa`. Source inspection finds one other production
zero-argument schematic constructor, `io::output`; it allocates a list and a
mutable byte buffer and must be refused. No gain is claimed before both
target entries pass the independent physical preflight and actual emission.

## Public authority and initial grammar

Add `ImmortalCertificate { shape_identity, dependency_identity }` and a
separate public `rc_calls.immortalIn` query. It accepts only zero-argument
ordinary guest functions with a counted, copyable result. It does not change
`BorrowCertificate`, invent a parameter, or change canonical `guest()` result
contracts. Unique, finalized, callable, opaque, host, live-view, resource,
recursive-box and mutable collection contents are excluded transitively.

The first grammar is deliberately straight-line and call-free: typed scalar
constant pushes, frozen immutable byte literals, ordinary inline record/array
construction, initialized local bit loads/stores and terminal return. Permit
only the scalar representation wrappers demonstrably present in the lowered
constant body; they keep their existing checks. No branches, switches, loops,
references, fields read from external storage, heap construction, arithmetic,
arena operations, function values, callbacks or semantic value copies. Reject
Result construction/return and all error-trace materialization. No helper
composition or recursion is needed inside this certificate.

Track availability and exact native types on the operand stack and locals.
Only constants enter this state; construction requires every input proved
constant and every counted leaf either a static immutable byte literal or a
zero representation justified by the admitted constructor. Reject incomplete
initialization; do not infer immortality from zeroed scratch or a counted
shape with no observed runtime acquisitions. The final return consumes the
one correctly typed result. All intermediate managed leaves satisfy the same
immortal invariant, including values later discarded.

Initially admit immutable `bytes` literals only, including nonempty controls;
`str` can remain refused. Factor the exact constant-push/literal predicate
used by `qbe_managed.frozenLiteral` into a shared pure helper before relying on
it. The public proof, existing borrow literal analysis and actual emitter use
that predicate; no speculative dynamic constructor fallback is allowed for a
certified literal. Retain the emitter's existing literal symbol/content and
16-byte static header convention.

Use explicit small caps: 128 instructions, 32 locals, operand depth 128 and
256 visited type nodes, with overflow/refusal before allocation. Charge the
linear instruction pass and all operand/constructor-field visits against a
4096 logical-work allowance. Run the same `rc_readonly_plan.certify` native
IR/liveness/ownership/COW preflight with its documented cells/volume limits,
and the return-effect veto. Exact source literals, opcodes, layouts, ABI,
grammar version and physical-preflight policy enter dependency identity.
There are no callee dependencies in this initial certificate.

## Separate symbol and physical lowering

Emit a dedicated `_rc_immortal` Unit only after the public query succeeds.
It has its own symbol and frame-map attribution, following the existing
separate borrowed-Unit mechanism. Canonical `text::empty` stays owned for
ordinary callers, exports and function values; it is never relabeled in place.
Add an explicit immortal result-contract variant and a tagged internal entry
authority (borrowed or immortal), without growing runtime frame/state layouts.

The immutable entry uses early raw activation only after repeating the same
complete public query and matching its supplied certificate. Its local values
are raw physical bits and its result carries no O/H token. A counted native
shape means that ordinary materialization knows how to retain its leaves; it
does not mean this alternate owes a token for static literal leaves. Reject
physical planner disagreement before optional selection; after selection,
verify the same no-place/capture/share/cleanup invariants as raw borrowed
entries. No canonical owned fallback may occur within that raw body.

Preserve step/native-frame/logical-frame checks, source positions, bounds of
any admitted scalar wrapper and existing failure status. Removing an empty
ownership journal does not remove ordinary stack admission or aggregate value
storage. Complete result bits must be copied to the call's stable physical
storage before `%aux` reuse and before heap-frame release: small heap-frame
returns use `%return_storage`, large returns use `%out`. Any actually admitted
large constant shape needs the same controls; exceeding this initial grammar's
caps is an ordinary refusal, not permission to truncate or omit those copies.

There are no finalizers or ownership releases on this entry path. At ordinary
guest boundaries public ownership helpers have already drained pending work;
guest reentry during a finalizer inherits the active drain. The raw entry
therefore introduces neither a new drain boundary nor an unretained dynamic
object. The existing queued-finalizer/step/frame controls remain required.

## Composition and cache identity

Change saved readonly managed routes to tagged authority:
`borrowed(BorrowCertificate)` or `immortal(ImmortalCertificate)`. Save the
exact PC, target and result layout as today. Within raw readonly emission,
resolve that route directly before `frame.get`: choose `_rc_borrow` or
`_rc_immortal` explicitly. A counted call without an exact saved route is an
invariant error, never a canonical owned call. Ordinary emission retains its
existing borrowed/owned selection and need not use immortal alternates.

Keep sixteen distinct managed-target queries across the entire readonly root
composition, shared by both route kinds. Dispatch zero-argument targets to the
public immortal query and targets with parameters to `borrowedIn`, avoiding
two speculative full proofs per target. Each immutable query has exactly the
same standalone bounds as alternate emission. Charge its physical preflight
input cells/volume to the root's shared budget too; a dependency accepted as
part of a successful root must independently pass the standalone query.
Completed immutable certificates may be reused; no in-progress answer or
broader private analyzer result can authorize a route.

`at` and `partPin` keep their existing public parameter-anchored certificates,
which already permit an immortal alternative among their physical returns.
The second, raw-entry proof merely obtains an independently certified route
for `text::empty`; it does not widen their public anchored ABI. The constant
helper's bits join the activation's immortal lifetime, while nonconstant
returns remain anchored by the existing selected input parameter.

Version the raw composition and RC fragment identities. Hash the route kind,
complete shape/dependency certificate, optional admission/refusal, and exact
entry authority. A helper edit from literal bytes to dynamic allocation must
invalidate the immortal unit and every caller's raw proof transitively. GC
cache identity and canonical managed ABI remain unchanged. Preserve a clean
missing-alternate check in the emitted manifest and cold/warm cache tests.

## Controls before measurements

Require actual emission of raw `text::empty_rc_immortal`, raw
`sexpr::at_rc_borrow` and raw `layout::partPin_rc_borrow`; existing canonical
owned entries and `form`/`innerPin` routes must remain valid. Preserve the
initial refusal receipt. Compare all prior-v1 admission controls.

Test empty/nonempty literal results, nested inline constant aggregates, saved
first result across a second call and repeated call PC, caller arenas, and
canonical/function-value controls. Refuse mutable bytes, lists even empty,
host/provider calls, fresh managed boxes, unique/opaque/callable/live-view
fields, parameter-dependent results, recursion, Result/error tracing,
unavailable locals, wrong shape/dependency proof and all caps. Test helper
certificate loss through a plain intermediary with cold/warm caches. Retain
the existing large anchored-result and forced small heap-frame ABI controls,
plus any admitted large immortal result. Use exact step/frame/overflow budgets
at changed boundaries and queued-finalizer reentry; no broad trap sweep.

Only after review and source freeze: unchanged three schematic workloads,
both actual backends, median three instructions at 100% running, exact SVGs,
separate complete counters and accepted-GC ratios. CPU2 remains reserved by
root for these runs. A passing proof or smaller empty frame is not a Stage4
performance acceptance claim.
