# Read-only scalar-list loop versions

Status: source audit and proposed implementation, not implemented or measured.
This is separate from the completed readiness slice `95121e70` and its
comment-only follow-up `aadf9e80`. WP-4 performance acceptance remains open.

## Exact remaining cost

The unchanged full `list_append_sum` workload appends 16 million integers,
then folds them. The completed readiness experiment's immutable RC compiler
has SHA256 `4763ab94baf190fa99a4e08fc59fc7887110931d8041a0cc48116dbb09efad07`.
Its measured QBE median is 1,334,581,018 instructions; accepted GC is
592,295,027, or 2.253237 times GC. LLVM O3/full LTO is 566,708,819 versus
246,274,722, or 2.301125 times GC. GC is the archival completed row, not a new
interleaved sample. Exact binary identities and disassembly ranges are in
`experiments/d9-rc-append-residual-20260927/`.

| Actual machine path | RC QBE | GC QBE | RC LLVM | GC LLVM |
| --- | ---: | ---: | ---: | ---: |
| Warm append, instructions per element | 39 | 20 | 28 | 13 |
| Successful fold, instructions per element | 44 | 17 | 7 | 19/8 |
| Common loops times 16 million | 1,328,000,000 | 592,000,000 | 560,000,000 | 246,000,000 |

The common paths contain no runtime calls. The difference from the complete
hardware counters is cold growth, setup, finalization and exceptional loop
edges, not unexplained hundreds of millions of descriptor lookups. These are
static path counts, validated against exact measured binaries; they are not
new counterfactual timing results.

RC QBE's fold retains two iteration-length checks, bounds checking, induction
overflow checking, storage reloads and scalar operand stores. Accepted GC
uses the already-existing guarded loop version, retaining accumulator overflow
checking while removing proved redundant checks and caching stable storage.
LLVM removes RC's redundant checks itself but keeps the scalar checked fold;
the accepted GC version exposes the existing checked reduction optimization,
whose successful vector body handles eight elements in nineteen instructions.
No new summation law or relaxed overflow behavior is proposed.

## Why RC currently refuses

`qbe_loop_facts` can already plan this read-only loop. Its range and iteration
facts are shared with GC. The additional `qbe_cow.versionLifetime` gate permits
only a physically proved uniqueness-hoist interval (`qbe_rc_hoist`) or a loop
containing scalar operations alone (`qbe_rc_scalar_version`). A read-only fold
needs no uniqueness check, so it has no hoisted entry; its list reads and
iteration checks fail the scalar-only grammar. Adding an unnecessary uniqueness
operation would be incorrect and is not proposed.

The other major append cost is separate: RC's address-taken `%s0` word remains
visible to opaque helpers elsewhere in the function, leaving scalar stores in
QBE's loops. Removing that escape requires a separate storage/provenance proof;
it is not part of this candidate.

## Proposed bounded admission

Add an independent `qbe_rc_read_version` certificate and a narrow entry guard
hook in the existing `qbe_loop_version`. Reuse existing guarded version emission,
original fallback, frame/trap handling and loop facts. Existing hoist/scalar
version admissions remain unchanged; the new entry guards apply only when the
independent read-only proof is what admits the loop. Do not add ownership
checks to the runtime or alter the public ABI, generic journals, list storage,
count limits or generation rules.

Initial bounds: at most 4096 function instructions, the existing 200-instruction
loop limit, at most eight distinct list owners, and a shared bounded scan budget.
Refusal retains the existing original loop. Admit only scalar integer/bool/unit
operand stacks and private scalar local stores. The only collection operations
are `.length`, `.read` and `.iteration_check` on ordinary nonboxed `list[T]`
with a nonzero plain scalar integer/bool element. No bytes, text, dictionary,
view, unique resource, managed element, pointer projection or inline aggregate
is admitted initially. At least one actual list read is required.

Each owner must have direct private local storage and a retained physical
journal entry: no by-reference/caller-storage slot, place alias, empty-local
certificate, or raw borrowed slot. The new guard reads its initialized bit and
actual exclusive role, accepting only ordinary counted O (2) or terminal H (8).
LOAN16 and every other role go to the unchanged original loop. This guard does
not acquire a token, change history, read a payload prefix, allocate, drain or
fail. A false/empty guard is an optimization refusal, never a language trap.
The descriptor and local address are already fixed by the existing typed local
journal contract; no new descriptor lookup is required.

This dynamic O/H guard deliberately avoids inferring a live token from an
ordinary-looking type, a nominal local role, or a unique source definition.
The token remains in its original journal and is cleaned up by the original
normal/trap paths. In particular, `qbe_rc_views.local` acquires the hidden
iteration H before dropping the input operand, then publishes that H into the
iteration local. A fresh temporary iterable can therefore be O0/H1, and must
remain alive across the version. An arena H has no numeric counter but the same
journal guard and the arena stays open throughout this interval.

## No hidden mutation or cleanup

The source grammar alone is insufficient. At every reachable body PC reject:

- Calls, allocation, mutation, list write/append, region transitions, reference
  creation, root load/store/move/drop, semantic sharing and managed operands.
- COW unique/field checks, capture/fill events, shares/read-captures, active or
  starting receiver scopes, and any loop-entry check inside the interval.
- Field-transfer/projection commitments and every actually emitted local
  release, using `qbe_rc_edges.releasesAt` rather than nominal liveness alone.
- Independent alternate entries or unsupported inline origins.

The root cannot be replaced, dropped, moved or expose a new address inside the
interval. A stable O/H token keeps the header alive; the absence of mutations,
callbacks, cleanup and arena close keeps its length and backing unchanged.
External aliases cannot execute concurrently in the serial WP-4 runtime.
An already-active finalizer may enter this guest, but no allowed body operation
can resume that suspended drain; the same original journal remains linked.

As a second check, reject a generated fast copy naming any non-failure call,
including runtime release helpers. The existing generic `copyAllocates` veto is
not by itself a no-callback proof: its old pure set includes owned-drop. The
new candidate must use its stronger closed grammar and emitted-call veto. Cold
`myl_qbe_fail_*` paths retain their original source PCs and journal unwind.

## Entry, fallback and failure order

Insert the nonmutating actual-token guards before the existing range guards at
`@i<head>`, and branch to `@oi<head>` on refusal. External forward or backward
entries enter the ordinary head label and recheck anchors and all range facts.
Only an internal fast backedge targets `@fi<head>`; an original backedge targets
`@oi<head>`. Existing `qbe_loop_facts.entered` rejects external jumps into the
interior. Keep a structural test of actual `labelPrefix` routing, including a
backward external entry and nested loops.

Zero-trip loops may read initialized journal metadata but execute no new
payload operation, allocation or failure. Step-accounted code remains entirely
unversioned. Existing span/bounds/overflow guards still decide whether the fast
copy is legal. A failed guard executes the original loop with its original
iteration, error message, trap location and cleanup. Accumulator overflow and
other unproved arithmetic stay checked in the fast copy; the existing LLVM
checked-reduction fallback remains authoritative.

Dictionary loop-entry uniqueness is a separate proof. This certificate does
not infer anything from a dictionary entry or broaden `permitsVersion`.
The dictionary worker is independently restricting that query to list entries;
its late dictionary certificate leaves `loop_plan` untouched. Exact hunk
ownership is coordinated: this proposed slice owns only the new module,
`qbe_cow.versionLifetime`, and the narrow loop-version entry/emission veto hooks.

## Required controls and measurements

Positive: named O list reads, hidden H iteration over a fresh temporary with no
remaining O, empty and short loops, mixed scalar widths, multiple stable lists,
and inherited parent/inner arena cases. Guard refusal: unset journal, LOAN16,
caller-storage/private-borrow roots and missing physical slots. Mutation, callback,
managed elements, unique/H-view types, root rebinding and an unrelated emitted
release must keep the complete old lowering.

Exercise original and fast paths with negative/out-of-range indexes, early
arithmetic overflow and successful checked sums, zero iterations, step/frame
limits, and a callback after the loop which observes correct owner/hold lifetime.
Check actual O/H acquisition/refusal and arena teardown before/after, retaining
all input constructor failure locations. Add explicit external-backward-head
routing, no-guard-bypass and heap-frame storage controls. No journal is removed.

Measure full unchanged append and sieve plus representative non-target workloads
with immutable matched Debug compilers, actual QBE and LLVM O3/full LTO,
median-three unscaled instructions and separate exact counters/outputs. Accepted
GC comparisons remain mandatory references. The static attribution motivates
this candidate; it does not predict a guaranteed hardware gain or satisfy the
full43-program acceptance gate.
