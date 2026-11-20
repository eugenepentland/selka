# Proposed plain-field publication in an owning inline record

This is a read-only diagnosis and proposed compiler slice after borrowed callee
composition `b2a251c3`. It changes neither the Lox benchmark nor runtime uniqueness.
Root and compiler peer review accepted this design before the prototype began.
The compiler peer additionally requires refusing implicit COW/read-capture,
history and cleanup plans throughout the tail, not only explicit opcode effects.

## Observed cost and exact source

The immutable joined compiler is source `636524b81562e30285b15e297078fac24ffccb58`,
SHA-256 `32e272cf75968d2fe913f636739d4b11d83701448e515f057dfa87f1ed8cba46`.
The runtime worker's exact unchanged Lox binary_trees N10 measurement reports
851,383,851,938 QBE and 711,894,883,325 LLVM retired instructions, respectively
117.54 and 207.36 times accepted GC. Counters balance but include 736,227,500 H
pairs. Its full-execution qualitative samples put `walk`/`visit`/unique checking
and descriptor lookup among the dominant costs. Host throttling makes those
samples attribution evidence rather than an acceptance timing source; no new
sampling is needed for this diagnosis.

The exact `vm::run` IL contains 94 native loan sites. Source metadata maps all
36 sites for the 208-byte `heap.Runtime` to 18 plain counter assignments:
`stack_top` on vm.my lines 481, 484, 487, 490, 492, 496, 504, 521, 527, 542,
571, 580, 582, 587, 589, 591 and 597; `frame_count` on line 585. Each assignment
has two whole-record loan sites. They are not immediate managed-field reads:
plain `rt.stack_top` reads already use direct scalar loads.

For `rt.stack_top = rt.stack_top + 1` at line 481, checked RHS arithmetic completes
first and is stored in a plain local. Two following compiler capture stores each
loan the entire Runtime into the same temporary. UPDATE_RECORD then physically
retains the whole captured record, updates offset 128, publishes an owning
aggregate, and the caller-storage store drops/replaces all 208 original bytes.
The source root keeps its original owning edges throughout the captures. Thus
this path performs broad child traffic despite changing no managed edge.

The archived source/IL identity and the 36 site rows are under
`.tmp-lox-projection-audit/` in the isolated collection tree. Their immutable
upstream evidence is the runtime worker's
`.tmp-mut-argument/joined-flat-measure/` directory, including the production
manifests and source-identity receipt. An eventual implementation archive must
copy the exact evidence and stable paths before this scratch location is retired.
Static site counts alone do not quantify the dynamic fraction removable.

## Existing proofs and the missing boundary

`qbe_aggregate.fieldWriteAt` proves a GC-only fixed-array element update followed
by exact record/store-back. It admits only plain owning records or managed cells,
so it is not directly applicable to an inline record with managed siblings.
The plain Body RC update optimization avoids generic transfer only when the
entire record is uncounted. Runtime has eleven list-pointer leaves plus a variant.

`rc_field_transfer` certifies moving a managed direct field out of a caller-owned
record through a mutation and unconditional store-back. It records exact source,
field, target, extraction and commit locations, checks CFG entries and refuses
live aliases/authority that could observe a temporary hole. The proposed scalar
write uses the same exact source/store-back discipline, but never moves an edge
or empties the record. It should not reuse the semantic copy bits or pretend the
whole captured temporary owns the source's children.

## Bounded first admission

Recognize only a fully completed plain scalar RHS followed by an exact closed
capture/update/store-back tail. Start with one direct field and a caller-storage
`mut` parameter holding an initialized, writable, inline ordinary record. Exclude
C ABI/host function bodies, managed cells/boxes/collections, raw unique contents,
live-view fields, and any root whose resolved physical storage differs from the
certified source. Later support for ordinary owning locals is a separate extension.

The proposed eight-instruction tail is: load the root; store a compiler temporary;
load the same root; store the same temporary; load that temporary; load the plain
RHS local; UPDATE_RECORD of exactly one plain scalar field; store the result back
to the same root. A reduced compiler dump confirms exactly these eight instructions, preceded
by the scalar RHS store. The first slice rejects even an extra plain VALUE_COPY.
The actual vm::run metadata has 1,701 instruction positions; eighteen full scans
charge 30,618 cells within the stated bounds.

Require empty operand stack at the first root load, exact stack shapes throughout,
no branch target after entry, only fallthrough instructions in the entire tail,
and no aliasing or observation of the compiler capture except those exact loads.
The capture is a compiler temporary, not a user binding, is dead after commit,
and every definition/use is admitted by this same proof. Its guard must be
provably empty at tail entry, including previous loop iterations; refuse a
reused owning/H/LOAN temporary rather than silently discarding its obligation.
The plain RHS local is already initialized, cannot overlap the root or capture,
and has no ownership/finalizer/callable/host-reference obligation. Its complete
value is read before the only destination write. Restrict the first slice to one
integer/bool scalar field and nonzero known native width.

No call, allocation, scope/arena transition, bounds operation, arithmetic, cleanup,
semantic SHARE, unique check, or other effect may occur inside the tail. The RHS
may have arbitrary earlier behavior: all of it must still execute and complete
before this proof begins. Any RHS trap leaves the owning root unchanged. Incoming
alias/snapshot handling remains the existing call ABI's obligation: the mut slot
is the writable destination, and an independent saved record snapshot has distinct
inline bytes. The proof must verify that this is callerStorage rather than merely
assuming every by-reference pointer is writable. Managed child snapshots remain
untouched because every child edge retains its existing token and address.

Bound candidate capture-use scans to functions with at most 4096 instructions
and a cumulative allowance of 262,144 instruction cells. This allowance charges
the whole-function capture-use scan only: fixed eight-instruction tail checks,
COW-plan/writer, edge-release and local-alias scans are additional work bounded
by the finalized function metadata and number of admitted candidates. It is not
a claim that every analysis operation is charged to 262,144. Record exact
root/capture/value/field/start/update/commit facts in a cohesive certificate. A
failed optional proof uses unchanged general lowering. No State field or ABI
growth is needed; choose one emission-side plan collection or bounded per-PC
queries after reviewing the existing seven-field limits.

## Publication and cleanup algorithm

The certified capture operations carry no independent owner or hold. Do not copy
record bytes into a normal owning local and then merely clear its guard. Either
use exact per-instruction emission hooks for the proved tail, or reuse a verified
no-token receiver representation whose physical address rules fit inline records.
Preserve every bytecode location, step/frame check and trap mapping. The proof's
emission must consume the expected stack shapes while suppressing generic managed
capture, UPDATE_RECORD ownership publication and final whole-record replacement.

Keep the record unchanged through the update instruction if a later step-limit
check can still fail before STORE_LOCAL. At the original final STORE_LOCAL commit,
read the complete plain RHS and write only the certified field in the caller's
owning record. The scalar store is infallible, uses the existing native width,
and changes no pointer, SHARED/PIN mark, O/H count, region, arena barrier, or
unique finalizer ordering. Scratch tokens and captures stay uninitialized for
cleanup, including trap exits. There is no new temporary cleanup owner to abandon.
The root continues to own every managed sibling throughout success and failure.

The runtime boundary in `native_rc.h` requires public ownership operations to
drain before ordinary guest reentry. Guest code reentered from an active finalizer
inherits `dead.active`, making nested drains no-ops. Edge adapters cannot enter
guest code. Therefore a proven non-owning scalar tail creates no death-queue
obligation and removing its otherwise-empty helper drains does not move a queued
callback. This invariant was confirmed by the runtime owner; retain a regression
for finalizer reentry and preserve the existing public boundary rather than
inferring queue emptiness from owner counts.

## Permanent controls and measurement

Add structural proof/codegen controls for exact caller storage, missing/extra
capture, external CFG entry, branch or callback inside the tail, initialized or
reused owned/H temporary, managed/unique/live-view fields, boxes, indirect alias
storage, wrong final target, and an escaping aggregate result. Preserve a control
where two back-to-back scalar writes create no artificial owner between them.
Verify the generated fast tail contains only the final scalar field store and
keeps all relevant runtime checks outside it.

Guest controls must keep saved record snapshots and child collection snapshots
independent, handle nested calls using the same mut parameter, test a RHS that
mutates or observes the source before returning, and preserve checked-arithmetic,
step and frame traps before publication. Include callers inside arenas, managed
siblings pinned by a pending receiver, false/narrow scalar widths, and normal
cleanup plus trap cleanup with balanced counters on GC stress and counted RC,
actual QBE and LLVM. Unique/H/box negatives continue through the general path.
If step accounting places a check between update and commit, target that boundary
explicitly rather than only trapping in the RHS.

First measure unchanged diagnostic N4/N5 with exact outputs and counter deltas;
then run full mandated Lox N10 unchanged when feasible. Separate this compiler
change from the pending small-record runtime retain candidate so attribution is
clear. Compare current joined source with a matched immutable predecessor and
retain all source/compiler/binary identities. Do not extrapolate static36 sites
or reduced-script ratios into complete-corpus acceptance.
