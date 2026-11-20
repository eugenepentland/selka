# Borrowed-entry callee composition: reviewed design

This records the proposal reviewed before implementation, extending fixed-point
proof `3b867d50`. The completed implementation and measurements are in the
[report](d9-rc-borrowed-composition-2026-09-27.md). The target is schematic `innerPin`: it calls `partPin` twice,
compares scalar fields and scalar `depth` results, and returns one of the two
pins. The loop slice proves `partPin`, but `innerPin` still materializes each
result independently because the proof accepts only immortal-result callees.

## Exact call transfer

Keep the same closed instruction/authority grammar, converged every-return
checks, unique/finalizer refusal and caller lifetime anchor. At a direct call,
independently prove the exact callee body. Check argument count and physical
argument types against its signature before popping them. An anchored callee
result identifies one parameter index; map that index to the corresponding
actual argument's converged `Value.anchor`. The returned physical type remains
the callee's declared type. An immortal actual argument maps to immortal output.
Multiple result branches may join only if they map to the same caller parameter
or immortals. Different caller anchors still refuse, including after a backedge.
Do not use semantic return provenance or COW copy bits as this proof.

For `innerPin`, both `partPin` results map through callee parameter `pins` to the
same `innerPin` parameter. Its scalar comparisons clear provenance. Every return
therefore remains anchored to that one caller parameter. The proof must also
admit pure scalar helper results such as `depth`: run the same strict whole-body
analysis internally for a copyable, non-unique scalar return and require no
managed result edges. Public borrowed-entry certification still requires a
managed parameter anchor, so scalar functions get no new alternate ABI. Unknown,
mutating, recursive, host and indirect callees remain refused; allocating helpers
remain refused even when their outputs are later discarded.

## Emission and lifetime obligations

A raw borrowed body calling an anchored helper must target the helper's separate
borrowed entry. Existing `qbe.emitCall` asks `qbe_rc_borrow.certificate` and chooses
that symbol; borrowed states retain an active RC catalog even though `after`
suppresses publication. Validate that behavior explicitly in emitted IL. Never
accept a composition if the emitter can silently call an owning callee entry for
that managed result. A scalar or proven immortal-only helper may keep its
canonical ABI: it returns no fresh managed token requiring outer cleanup.

All argument anchors stay alive throughout the complete outer borrowed
activation. The strict grammar excludes mutation, callbacks and arena transitions
that could invalidate them. Nested inline results use existing ABI return storage
before the callee stack disappears. The outer caller establishes independent
ownership before dropping its arguments, as today. Canonical, function-value,
provider and exported entry ownership remains unchanged.

## Repeated subproofs and bounds

Naively analyzing `partPin` twice in each fixed-point/hash pass would exceed the
existing 65,536-cell budget despite repeating the same immutable body. Add a
small per-root-query memo of completed callee proofs keyed by exact program
function index; all entries use one unchanged program, catalog and ABI. Cache no
in-progress result, and keep the active instruction-slice recursion guard.
Conservatively refuse after 16 distinct callee bodies, rather than evicting and
making acceptance depend on traversal order. This fits fixed automatic storage
and retains the current depth/state/work budgets; distinct bodies are charged
when analyzed and every caller transfer/join/hash visit remains charged.

A successful independent callee query must also succeed with a fresh full budget,
otherwise proof/emitter symbol selection could disagree. The retained complete
memo, bounded dependency set, no cycles and shared accounting make the callee
query a subset of the accepted caller query. Add a nested repeated-helper test
near the state bound and directly compare standalone callee certification. If a
simple bounded memo cannot establish this property, refuse the composition.

Bump the certificate policy to v6. The final ascending-PC hash includes each
callee's complete transitive proof identity and the resolved parameter mapping;
reuse must never omit dependency hashing. Callee edits that change its anchor,
create fresh results or lose certification invalidate all affected callers and
alternate entries. Warm/cold output and cache restoration must agree.

## Required controls and measurement

Test direct and transitive helper chains, reordered actual arguments, multiple
calls mapped to one caller anchor, immortal alternatives, scalar helpers and
actual inline bits after return. Refuse conflicting caller parameters, a
backedge-introduced different mapped anchor, fresh fallback or discarded fresh
producer, callbacks, unique values and recursive call graphs. Keep state/work/
dependency limits conservative. Verify nested alternate symbols/source maps and
ordinary function-value ownership explicitly.

Run snapshot, caller-arena/escape and trap cleanup controls on GC stress and
counted RC with actual QBE/LLVM. Measure all three unchanged schematic workloads
against the immutable loop-only compiler, using separate counting binaries,
complete SVG output hashes, median-three unscaled instructions and exact balance.
A small accessor test cannot substitute for those workloads. No runtime helper or
allocator change belongs to this slice.
