# Named owning record scalar writes

Status: implemented and measured as a separate compiler slice. Focused controls
and the immutable evidence verifier pass; root owns the joined full gate. This continues `RC-PLAIN-RECORD-WRITE-1` after the adjacent
variant-read slice `4f60ff94`. The isolated branch real-merged joined source
`e5d47d20` as `d42d28ad`; prior immutable compilers and receipts are preserved.
This work concerns Stage 4 performance and its correctness conditions only.

## Measured workload and exact opportunity

The unchanged Lox `vm::run` keeps a private 40-byte `ExecFrame` in `%l4`:
three list pointers at offsets 0, 8, and 16, followed by `ip` and `base` at
24 and 32. The preceding adjacent-read candidate still emits two whole-record
loans for each of four scalar update tails:

| Tail start PC | Loan PCs | Source operation |
| --- | --- | --- |
| 46 | 47, 49 | `frame.ip = frame.ip + 1`, VM line 474 |
| 1066 | 1067, 1069 | forward jump, line 546 |
| 1105 | 1106, 1108 | conditional jump, line 550 |
| 1128 | 1129, 1131 | backward jump, line 553 |

These positions come from saved emitted IL, not an unrecorded bytecode dump.
The first operation executes once per VM opcode. The other three execute only
for their Lox opcodes. Each committed update currently performs two three-leaf
loans and the owning storeback preparation: the initial counter prediction is
six H acquire/release pairs and three O acquire/release pairs removed per
successful commit. The separate 1/2/10-update probe now confirms that prediction exactly on both
backends. No allocation or clone reduction is claimed.

There are also 28 field-list loan calls in `vm::run`, arranged as fourteen
two-loan captures. Their dynamic frequency is not established by their static
count. The named-record update is the first target because its principal site
is on every dispatch iteration and its scalar publication can reuse an existing
exact proof. Narrowing the field-list captures would need a separate complete
capture/use and source-mutation proof.

Read-only local evidence is under `.tmp-lox-projection-audit/`:
`current-after-vm-run.il`, `named-record-loan-sites.json`, and
`named-record-reference-calls.json`. The latter is a linear SSA address trace,
not a CFG certificate. It finds 22 direct calls receiving `%l4` across twelve
helpers: `read_constant` once, `read_byte` five times, `read_string` five times,
`read_short` three times, and once each `get_global`, `set_global`,
`get_upvalue`, `set_upvalue`, `get_property`, `set_property`, `make_closure`,
and `define_method`. The source also has the initial `load_frame` definition
and four later `load_frame` rebindings. Therefore a single-definition proof or
a blanket refusal of `ref_local` would miss the actual workload.

The supporting emitted IL uses frozen compiler SHA256
`300a83f5c51bfc5b590c0254940b4534df1e18d79a0b3ac248de047cc6c370d1` from
the adjacent-read archive. The implementation comparisons use the fresh immutable joined control below;
this old supporting emission is not relabeled as the joined compiler. Root's joined `e5d47d20` full N10 results are approximately
27.91 times accepted GC for QBE and 44.81 times for LLVM, still far above the
1.3 cap. Static admission alone establishes no progress against that cap.

## Exact tail, unchanged publication point

Retain the eight instructions already required by `rc_plain_record_write`:

```
LOAD root; STORE capture; LOAD root; STORE capture;
LOAD capture; LOAD scalar_rhs; UPDATE_RECORD one_field; STORE root
```

The scalar RHS has already been fully evaluated and stored immediately before
the tail. Keep the exact stack heights, no external middle entry, no inline
origin, one integer/bool field, dead capture after commit, complete
`captureUses`, and existing `quiet` checks. In particular, all planned COW,
semantic SHARE, capture, scope and actual early-cleanup effects remain vetoes
inside the tail. No arithmetic, call, allocation or region boundary moves.

The two capture stores remain suppressed, the intermediate record operations
only name the root, and the sole memory change remains the original final
`STORE_LOCAL`. A step trap before that instruction must see the prior scalar
value. No owner is acquired, dropped, moved or reflagged on this path. Managed
sibling fields and their arena/PIN/SHARED state remain unchanged.

The existing emitter assumes a caller-storage parameter and loads the pointer
held in `%lroot`. A private inline local instead requires its slot address,
`copy %lroot`. Add an explicit `home` enum to the existing certificate and one
address helper used at all three current root-address sites. This makes six
certificate fields; no State field, ABI change or journal layout change is
needed. Existing caller-storage certificates keep their current behavior.

## Whole-root physical ownership certificate

Semantic `.owned` and a private address are necessary filters, not a proof.
For the new named case require all of the following:

* A named nonparameter local with ordinary local origin, private inline
  noncollection record representation, identity move resolution, its own
  retained journal entry, and no by-reference/caller-storage/place/alias role.
* Canonical active RC emission: neither a borrowed alternate nor a readonly
  raw body. The plan entry begins empty at its own logical storage. Reject
  iteration/held roots and transitive live views, unique resources, finalized
  or opaque/callable authority. Reuse bounded type inspection rather than
  infer safety from the target scalar field alone.
* Enumerate every explicit and implicit writer of this root. Ordinary named
  stores may establish O; certified scalar commits preserve O. Refuse pattern
  binding, MOVE, receiver/place/box writeback, field-transfer interception,
  raw read-loan publication, alternate emission, and unknown publishers.
  Inspect COW unique locals/aliases, unique-field parents, loop entries and
  place/box ownership, as well as bytecode stores. References are handled only
  by the separate consumer proof below.
* Model normal-path `DROP_LOCAL`, arena-end watermark cleanup, and planned
  root releases as clearing the initialized fact. A semantic planned release
  may conservatively clear the fact even if current emission would retain it;
  it must never be silently ignored. The existing physical early-release
  scheduler excludes named inline locals, but that current exclusion is also
  recorded explicitly in the review.

Use a small forward fixed point per candidate root. Each PC contains a set of
possible states: unreachable, empty, O, or empty-or-O. Entry is empty. Normal
ordinary stores set O; cleanup sets empty; accepted calls and scalar commits
preserve the incoming state. Joins union predecessor states. Only converged
singleton O at the tail start admits it. No forward optimistic fact may be
accepted before processing backedges. Refusal, unsupported CFG or exhausted
work budget keeps the existing generic lowering.

Here O means an initialized, cleanup-valid typed owning value. Its fields may
legitimately have zero owning edges; it does not assert that every list pointer
is nonnull or that a heap object's owner count is one.

All candidate scalar commits can be treated as O-preserving during analysis:
both the generic successful store and the proposed field-only commit preserve
an incoming owner. The proof does not depend on an unproved future elision to
make an empty source into an owner. Root journals stay allocated and active;
there is no dynamic owner-count or guard shortcut.

The enforced bounds are function length 4096, at most 16 distinct named roots,
and a shared 262144 work allowance. It charges each inspected instruction,
planned site/unique entry/loop entry/alias/place, field-transfer interception,
reference-window instruction and planned release edge, direct-call parameter
and operand, and propagated CFG successor (including switch arms). The queue
is deduplicated and no partial root result is accepted. Structural authority
inspection retains its separate 256-node bound; existing indexed plan queries
and source/branch metadata queries are not represented as individual visits. The existing tail,
`captureUses` and `quiet` bounds remain separately stated as in the prior
report; do not describe their nested primitive operations as covered by this
new allowance.

## Fully traced mutable references outside the tail

Every `REF_LOCAL root` must be traced from its exact stack position to its
first consuming instruction. The initial slice accepts a straight-line window
of at most 64 instructions, no external entry or control-flow split, and no
replacement/cleanup of the root while the reference is pending. Operations
above that operand must neither consume it nor create an untracked alias.
Require the existing operand-source fact to agree with the exact reference
PC at the consumer; source provenance alone cannot distinguish a load from a
reference.

The first consumer must be a direct ordinary guest `CALL`. Match its stack
base, parameter index and exact root type. Require the parameter to be
explicitly declared mutable and `typed.referenceMut` to select inline
caller-storage. Host/provider/C ABI and indirect calls are refused. A second
reference to the same root in the same call is initially refused. A reference
consumed by STORE (including named-argument spills), VALUE_COPY, field/index
projection, record construction, return, pop, switch, cast, unknown opcode or
any other escape is refused. This restriction covers the observed positional
VM calls without asserting that every legal reference expression is admitted.

The successful-return ownership argument is concrete:

1. `qbe_rc_locals.store` sends named stores through `prepareOperand`, not the
   compiler-private `preparePrivate` loan path. `prepareGuarded` stages an
   owner by taking O or retaining raw/H/LOAN input, and drops the old input
   token only after success. The named destination drops its old value,
   receives the prepared bytes and ordinary typed role, then sets its guard.
2. A declared-mut inline callee receives that initialized caller address.
   Its caller-storage store similarly prepares the complete owning replacement
   before dropping the previous value and blitting the replacement. It does
   not rewrite the caller's journal role or own a second local token for the
   same slot. Returning successfully preserves the caller's initialized O
   obligation, including after rebinding or passing it onward to another typed
   mut-record callee.
3. Declared mutation excludes both borrowed-return alternate bodies and the
   canonical readonly-body elision. Callee admission failure leaves the
   caller-owned slot with the caller. A later trap unwinds that same caller
   journal; no new guard is hidden or disarmed by this optimization.
4. Outside calls are not optimized and may legitimately change the scalar or
   managed children. Their normal typed publication, snapshot, region and
   failure behavior stays intact. The fixed point uses their return contract,
   not an assumption that the callee is pure.

Runtime peer review also checked the apparently destructive alternatives.
`rc_plan.initialOwnership` marks the callee parameter inout, with a clear
callee journal guard. Callee MOVE therefore takes `prepareGuarded`'s copy
branch, retaining a new owner while leaving the caller bytes intact; DROP
only examines the clear callee guard. Frame return/early-return cleanup has
the same exclusion. Legal arena watermarks follow parameters, and arena-end
slot clearing also skips by-reference slots; caller storage only receives the
existing region validation. Forwarding `REF_LOCAL` loads the existing caller
address rather than taking the address of its pointer cell. A further typed
declared-mut inline callee consequently inherits the same invariant.

The closed-field transfer optimization can temporarily zero an owning child
through caller storage. That value remains cleanup-valid, complete successful
storeback restores the child, and a trap retains safe caller unwind. None of
these facts follows just from the caller guard being true; they depend on the
specific canonical store/MOVE/DROP/return/forwarding paths above. Unique
consume-on-entry and unknown body kinds remain refused. Runtime peer review
found no successful path that invalidates caller ownership under this
admission. The compiler peer independently reviewed the concrete proof and
found no blocker; the required reference-window and normalization controls are
retained.

## Aliases, snapshots, traps and callback boundaries

A separate named record snapshot has private scalar bytes. Its shared list
children retain the same owners and SHARED marks; scalar updates of the source
must not alter that snapshot. Ordinary semantic copying outside the exact tail
continues to run. A borrowed alias or path capable of observing the root during
the tail is rejected by physical place checks and the existing live-root alias
veto; a real independent owned snapshot is not treated as an alias.

No tail instruction acquires/releases an edge or executes a callback. The
transitive unique/finalizer/authority refusal also excludes moving a guest
finalizer boundary when omitting the generic sibling copies. Public ownership
helpers drain before ordinary guest execution; finalizer reentry inherits an
active drain. Therefore the interval begins with either no pending callback or
an already active drain and creates no new death obligation. It cannot expose
different uniqueness or resize behavior to a callback inside the interval.

The old inline capture's physical loan may remain guarded beyond its semantic
last use, until reuse or frame cleanup. Removing it is therefore justified by
the entire capture-lifetime proof, not only the eight-PC interval. The root's
three list owners keep current children alive; a later root replacement still
executes its ordinary cleanup. Earlier retirement of a now-dead old capture
cannot call guest code under the transitive finalizer refusal. List holds name
headers, while growth resizes raw backing; immutable text/bytes have no legal
resize authority. No public H view is admitted. These distinctions avoid an
argument based solely on uniqueness ignoring H.

Caller arenas are legal: the local slot still owns its validated current
edges, and the scalar write creates no new region edge. A root declared inside
an arena loses its CFG initialized fact at its closing watermark; it needs a
new canonical definition before another candidate can be admitted. A failed
ordinary replacement or mut call remains on the existing generic path, with
the caller's old/current token guarded for unwind.

## Implementation boundary and required evidence

Keep the proof in a separate helper consumed by `rc_plain_record_write`; reuse
the existing certificate array. Finalize named additions after alternate-body
and physical COW/loop planning, before frame emission. This avoids reading an
uninstalled `self.cow.rc` during state construction. Root's caller-storage
proof remains unchanged. No read-loan, runtime, allocator, uniqueness or
dictionary-key behavior is broadened.

Before timing, require emitted admission of exactly the four target VM tails,
eight fewer ExecFrame native-loan calls, private-slot `copy` addressing, no
unexpected additional owned publications, and unchanged 28 field-list sites.
Inspect all root definitions and reference consumers from the actual checked
instructions when the candidate proof is available; the current IL trace is
supporting evidence, not proof of full admission.

Focused controls should cover a repeated named loop, canonical rebinding before
and after a mut caller-storage call, a callee that replaces all managed fields,
saved record snapshots, caller arenas and an inner arena whose local is later
redefined. Include ordinary GC/RC controls on both actual backends. Structural
negatives cover H/live views, unique/callback authority, borrowed entries,
parameters, byref/place/move roots, pattern publishers, untraced references,
alternate entry/backedge paths that reach a tail empty, and budget refusal.
Keep source mutation during RHS evaluation and a few exact step budgets around
UPDATE/final STORE, plus overflow and selected allocation-failure controls.
Do not repeat a large trap-budget matrix without a concrete unresolved risk.

Only after those controls pass, request a timing CPU and freeze source/compiler.
Use matched N4/N5 counters to validate the predicted per-commit traffic and
then unchanged full N10 median-three instructions on actual QBE and LLVM.
Preserve exact output, balanced O/H/allocation receipts and raw event running
fractions. Guest RSS acceptance belongs to root's joined-corpus measurement;
wrapper RSS is not guest evidence. The 1.3 performance cap and immutable
accepted-GC denominators remain unchanged.

## Completed implementation and immutable results

The candidate Debug compiler SHA256 is
`b8d91d1731b47d60d6d11ee17b1c400db5655860a0c305ae833324f0aa029f28`,
from real-merge base `d42d28ad` plus the archived patch. The before compiler is
joined `c90c84be` (only a unit-fixture manifest change beyond `e5d47d20`), SHA256
`1f3bca2c62180a58fcc54782f9414a2b272e8447f996096a6883dc330774e3c7`.
No runtime, allocator, frame layout or guest workload changes are in the slice.
The original immutable installations and prior experiment receipts are retained.

Final cached emitted IL admits all four target VM tails: plain scalar markers
rise from 18 to 22, ExecFrame loans fall from eight to zero, and total VM loans
fall from 58 to 50. Every other loan descriptor count is unchanged. One other
named scalar tail is admitted in `compiler::init_compiler`, which changes the
new function's scalar name after publishing an independent record snapshot.
The permanent published-record/RHS-rebinding test covers that pattern; its
traffic is included in all whole-program measurements, not attributed solely
to VM dispatch.

The 64 before/after standalone assertions cover normal GC-stress and RC on
actual QBE and LLVM, including complete RHS evaluation, saved record/child
snapshots, forwarded mut MOVE/return, replacement of managed fields and arena
cleanup/redefinition. All pass. The 48 boundary executions comprise 40 expected
step, allocation and overflow traps plus eight successful controls; output,
trap class and cleanup match the frozen before compiler. The allocation test
first used unsupported list multiplication: its rejected source/log are
archived as a harness syntax mistake, and completed step receipts were retained
when replacing it with a legal comprehension. No failed compiler control was
removed or reclassified as passing.

The two focused test filters each pass 15 tests, including the same eleven
mandatory unnamed tests. Structural controls retain empty/backedge joins,
budget refusal, planned release while a reference is pending, root rebind/drop,
duplicate arguments, spill/unknown consumers, H/callback refusal, and the final
store step check. Whole-tree Guardian passes all 88 checks. Its earlier API
hygiene and overlong-literal findings and their correction are archived. The
root integration agent owns the next complete four-command gate and broad
backend sweeps; these focused results do not substitute for that gate.

Matched unchanged N10 median-three instruction counts, CPU10, 100% event running:

| Backend | Before | After | After/before | After / accepted GC |
| --- | ---: | ---: | ---: | ---: |
| QBE | 201,889,710,484 | 172,146,477,978 | 0.852676 | 23.766529 |
| LLVM | 153,810,086,277 | 130,950,442,682 | 0.851377 | 38.142791 |

Reduced N4/N5 after/before ratios are QBE 0.867325/0.864299 and LLVM
0.864452/0.859662. Full output is exact on every run. Both backends have the
same counted results: O acquires 81,463,495 → 44,407,747; H pairs
264,505,085 → 190,393,589. O releases balance allocations, and H balances.
All 4,350,608 allocations retire; clone shells remain 1,095,889 and uniqueness
checks remain 20,836,904. The reductions are exactly 37,055,748 O pairs and
74,111,496 H pairs. The independent microprobe confirms three O/six H pairs per
scalar commit, including at one update; it does not infer that all full-program
savings come from the one dispatch site.

The exact accepted-bin denominators are 7,243,231,888 QBE and 3,433,163,639 LLVM,
with the original samples copied into the archive. These are distinct from the
slightly different older whole-corpus sample set. The accepted baseline remains
immutable. The candidate still exceeds the 1.3 cap by approximately 18.3-fold
and 29.3-fold respectively, so this is material progress, not Stage4 acceptance.
No direct guest RSS claim is made: the saved outer time(perf) maximum is labeled
wrapper-only, and root will measure direct guest RSS on the joined corpus.

Evidence is under `experiments/d9-rc-named-record-write-20260927/`. Its verifier
checks source/artifact hashes, actual backend manifests, exact output, traps,
counter balance, emitted admission, and every raw perf event. Runtime/clone
profiling and narrowing the remaining field-list captures are follow-on work;
this slice does not widen its proof to those cases.
