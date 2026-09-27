# Proposed exact non-H list capture proof

This is a read-only design after scalar append `3bc671b7`; there are no production
changes. The [exact-binary profiles](../../experiments/d9-rc-plain-append-profile-20260927/README.md)
show both repeated append metadata lookup and a separate hot sieve write block
that tests terminal H roles which are never live at those particular captures.
The profiles are throttled qualitative evidence. The workload's one balanced H
pair and unchanged full-size instruction counts are the stronger accounting facts.

## Why the present refusal is broader than the actual role

`qbe_rc_holds.mayHold` answers a function/type-wide possibility. A later
`for flag in flags` gives the type `list[bool]` terminal H capability everywhere
in that function. `qbe_rc_views.local` then wraps earlier load/store captures in
H-propagation alternatives. Both `qbe_rc_inert_receiver.emptyLocal` and
`qbe_rc_empty_locals.finalize` refuse that whole type, retaining local journal and
receiver scratch storage even where an exact input and writer proof could show
that the capture never owns any token.

The proposal does not change `mayHold`, remove actual iteration holds, or treat a
semantic borrow/name/type as a physical owner fact. It only allows the existing
inert/read-anchor empty-local proof to use a narrower input-role certificate.
The owning source journal, clone checks, source SHARED history, actual iteration
journal, and physical/logical frame admission all remain.

## Physical writer and producer inventory

| Path | Current physical convention | Initial admission |
|---|---|---|
| Frame initialization | All ordinary local guards start zero. Consumed unique parameters own their tokens; read/mut parameters borrow; caller storage names external ownership. | Refuse every parameter and any by-reference/caller-storage source or target. Require canonical active RC emission. |
| Canonical `STORE_LOCAL` into a named local | With no receiver alias/place and no read-anchor binding, `qbe_rc_locals.store` calls `prepareOperand`, retires the previous token, installs a typed entry and copies the pending role. `prepareGuarded` takes only ordinary O; H/LOAN/raw borrow is physically retained into O before its old guard drops. `producedOwner` admits completed O publications only. | Require exactly this lowering path for the source's only static definition; check the actual plan, not its name. |
| Compiler temporary `STORE_LOCAL` | Can preserve H through `views.store`, install LOAN through `preparePrivate`, borrow a receiver/anchor, or install O. | Never assume ordinary from temporary status. Admit only the exact target pair and existing empty-local lifetime/writer proof. |
| `views.entry/acquire/publish/store/move` | These are the terminal flag8 publishers. An actual iteration-owner store acquires H. A view field can publish H to an operand; hidden stores/moves propagate it. | Retain all actual view/iteration paths. The exact certified input has no such producer. Dictionaries, views and projected inputs are initially refused. |
| Raw `LOAD_LOCAL` | Ordinary lowering lends bits with an empty operand guard; view handling may instead acquire an H token if the source's live role is H. | Bypass that wrapper only immediately before the exact certified target store. Prove the source cannot have a live H role first. |
| Semantic `VALUE_COPY` | `history.prepare` publishes O at the original event point; it may clone or mark history and fail. | No intervening copy or read-capture/share action is permitted in the LOAD→STORE pair. Existing source copies elsewhere remain unchanged. |
| `MOVE_LOCAL` / `DROP_LOCAL` | Move can consume O, normalize a loan, or propagate H in a view branch; drop clears a guarded token. | Refuse source/target moves initially. Drops only clear a role, but all existing target lifetime checks still apply. |
| Pattern/contract `switch_variant` and narrowing | Ordinary bindings install a typed owner, contract bindings borrow with guard zero, narrowing can retain private loans and write back. | Refuse any source/target arm binding, including borrowed dispatch and narrowing. Do not infer the role from the payload type. |
| `ref_local`, caller-storage write, mutable argument scopes | Can expose writable storage or install clones through a helper outside an ordinary local store. | Refuse references, caller storage and uncertain authority. The target's existing clone/alias/place writer veto remains authoritative. |
| `unique_local`, loop-entry uniqueness and alias refresh | Can install ordinary O and change pointers; held uniqueness preserves H when that is the input role. | Keep source uniqueness unchanged. Forbid a clone writer or alias/box-owner write to the empty target. Require no source receiver alias/place; temporary-H selection cannot apply to the named canonical source. |
| Closed-field transfer | Publishes an ordinary operand owner and later drops its named target. | No inline record, field projection or transferred source path is admitted by this plain-list pair proof. |
| Calls, host/provider results and aggregate construction | Canonical results are O; borrowed alternates produce raw anchored bits. A later ordinary named store normalizes them. | A helper-return source may be admitted only after the audited canonical named-store publication. No call is inside the capture/use interval unless an existing stronger proof already permits it (the first inert whitelist does not). |
| Borrowed/readonly entry emission | `qbe_rc_borrow.local` bypasses canonical ownership lowering and can write raw bits into locals. | Explicitly refuse `state.readonly` and `contract.result == .borrowed`; no inference from ordinary-looking opcodes. |
| Arena/trap/edge cleanup | Drops guards and ends lifetimes; it does not make a new terminal H role. | Preserve all existing lifetime/arena exclusions. Never remove the actual source/iterator journal or frame linkage. |

`rc_plan.entry` is an entry-state model, not a full role-at-PC analysis: ordinary
local storage initially has `.empty`, not `.owned`. It must not be used as if it
certified all later writes. It is useful here only to exclude a `.borrowed.storage`
source and require that source and target have their own expected storage IDs.

## Bounded first admission

1. The type is an unboxed list with a plain scalar element, nonzero width 1, 2,
   4 or 8 and no counted/unique child edges. This is intentionally narrower than
   all lists. No dictionary, live view, box, inline aggregate element or projected
   receiver is admitted by this new proof.
2. The target is a nonparameter compiler temporary with one reachable static
   store, no pattern/ref/move writer, no actual iteration-owner use and no by-ref
   or caller storage. Reuse of that same static capture on a loop iteration is
   allowed only through the existing whole-local empty-token induction.
3. The producer is exactly `LOAD_LOCAL source; STORE_LOCAL target`, with matching
   types and stack shape. The store is not a branch target. There is no planned
   read capture, SHARE, semantic copy, field transfer or other publication at
   either instruction, except the existing source uniqueness action whose ordinary
   role is separately accounted for. No intervening instruction is accepted.
4. The source is a nonparameter, non-temporary local with independent canonical
   storage, no receiver alias/place, no read-anchor binding, no ref/move or pattern
   writer, and exactly one static `STORE_LOCAL` through the ordinary path above.
   The first slice refuses any backwards edge whose interval contains that
   definition. This excludes repeated user loop bindings and local rebindings
   even though some could later be proved safe. The definition precedes the
   capture; existing initialization/liveness analysis remains necessary.
5. Every source definition/writer is scanned, including unreachable synthetic
   writers conservatively. A bounded function of at most 4096 instructions and
   the existing total 262144-cell empty-local budget is the starting limit.
   Source checks can share the existing scan allowance; uncertainty refuses.
6. The target must independently pass the existing inert-receiver empty-local or
   anchored-read empty-local proof, including retained parent, exact input,
   liveness, all clone writers, alternate entries and planned copy checks.
   Neither this new role proof nor a single empty guard observation substitutes
   for that whole lifetime proof.

The induction is narrow: the canonical source starts empty and its only admitted
publication is O. Its other permitted changes clear the guard or preserve/install
O through existing uniqueness. It never receives terminal H. The exact source
load therefore produces borrowed bits and no operand token. The target's only
store bypasses H propagation and reaches an already certified raw borrowed
store. All its other admitted operations leave its guard empty. This holds on
repeated loop captures without suppressing any real O, H or LOAN acquisition.

## Proposed hooks and strict failure behavior

A new pure bounded helper answers the exact source/target pair proof. It does
not call `frame.emptyLocal` itself, preventing a proof cycle. The two existing
empty-local admission sites can use it to override only their broad `mayHold`
refusal; all other checks remain. Finalized layout still records only certified
empty locals and preserves strict errors on unexpected publication or scope use.

`qbe_rc_views.local` may return `.unhandled` for the exact load followed by an
already finalized empty target, and for that target store. This lets existing
ordinary raw/anchored receiver lowering run. It must not bypass H logic on any
other load/store of the same type or source. Projected captures and actual
iteration sources retain their full H behavior. No `qbe_rc_locals`, runtime,
`qbe_cow`, canonical ABI, state.active or ownership-frame change is required.

To avoid repeated scans during emission, these two hooks consume the finalized
empty-local fact plus the exact adjacent pair/shape check. The expensive writer
proof runs only in bounded finalization; the general `held` query remains dynamic.
The function's later iterator and all named source entries stay allocated.

## Explicit boundary probes and planned controls

The exact source `for flags in groups: flags[0] = False` is rejected today with
`E_VALUE_BINDING_WRITE`: the binding is an element copy and cannot be mutated
without first assigning a local. That frontend failure is preserved, not treated
as a runtime pass. The legal counterpart `for element in groups: flags = element;
flags[0] = False` has a named store executed on a loop backedge. The first proof
refuses it through the explicit repeated-definition boundary. Its unchanged
runtime behavior and input snapshot must be checked on both backends.

Ordinary read and mut parameters are deliberately refused. Same-type helper
return → named local is a positive only because its actual named publication is
O, not because helper provenance or the source name looks ordinary. A borrowed
alternate using list parameters remains refused even with similar bytecode.
Literal/comprehension → named source → scalar capture is the intended positive.

Permanent controls should cover: a later and earlier same-type iterator; actual
iterator mutation traps and live element visibility; legal named loop copies;
read/mut parameters; helper returns; explicit snapshots and source rebinding;
callback index expressions; pattern/ref/borrowed-entry refusal; a target reused
with H/LOAN before a loop; loop middle-entry and clone-target refusal; heap/arena
and bounds/arithmetic/step trap cleanup. Both actual QBE/LLVM, GC stress and RC
must preserve outputs, exact trap codes and counted O/H/clone/unique traffic.
Structural tests must show only the exact pair loses H branches and that the
actual iteration owner still acquires and drops H. Measure unchanged full-size
sieve, append and fannkuch before/after; do not infer gains from static sites.

The [unchanged-compiler controls](../../experiments/d9-rc-nonheld-design-20260927/README.md)
now pass all four GC-stress/RC × actual QBE/LLVM runs. Both RC programs report
20 allocations/retirements, O 9/29 and 15 H pairs. These establish baseline
behavior and the real lowering; they do not validate an unimplemented proof.
The managed-result helper in this small program did not receive a borrowed
alternate on the frozen compiler. The alternate-entry refusal remains an
explicit required structural test before implementation can be accepted.
