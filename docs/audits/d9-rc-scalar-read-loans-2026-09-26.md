# RC scalar collection receiver loans

A local load already borrows its value in the RC emitter. The avoidable owner
traffic came from the following compiler-generated receiver store: `len(xs)`
and `xs[index]` captured `xs` as a fresh owning local before reading it.

The new proof admits a single-definition compiler receiver filled directly from
a stable named local or parameter. Its complete live range may contain only
scalar operations/control flow and length or scalar element reads of that
receiver. Negative-index normalization is covered by the existing CFG liveness
solution. Calls, mutations, managed element results, arena transitions,
dictionary/H roles, projected roots, pattern bindings and temporary roots refuse
the optimization. A bounded analysis budget also falls back to ordinary copies.
The source anchor is recorded in `rc_input.Binding.anchor`; the existing physical
planner keeps that owner alive, while the receiver's journal guard stays clear.
No runtime or ownership ABI changed, and no state/plan fields were added.

The standalone scalar workload performs 100 scans of a 100-element list. A
matched comparison changes only this compiler slice, using separately preserved
Debug installations. QBE and actual LLVM O3/LTO both print `495000`:

| Counter | Before | After |
| --- | ---: | ---: |
| Owner acquisitions | 10,101 | 1 |
| Owner releases | 10,103 | 3 |
| Heap allocations / retirements | 2 / 2 | 2 / 2 |
| Uniqueness checks | 100 | 100 |
| Clones and holds | 0 | 0 |

Five new guest regressions cover positive/negative byte/list indexing, empty
loops, mutation during index evaluation, loop reassignment/branches, pending
pins, named snapshots and arena reads. Both backends pass before and after;
post-change counts balance at 76 allocations/retirements, 36 acquisitions,
112 releases and eight holds each way. A bounds trap retires both allocations
with no owner acquisitions after the change; the snapshot fallback still
preserves the value captured before an index callback mutates its source.

The expanded sorting/text/dictionary set passes 50 assertions per backend with
identical balanced counts: 66,827 allocations/retirements, 468,046 acquisitions,
534,873 releases and 88,869 holds in each direction. The matrix n=12 control is
unchanged at one clone and 132 allocations/retirements: its nested managed-row
reads remain outside this initial proof. These are ownership diagnostics, not
a full-corpus timing acceptance result.

Focused scalar compiler tests pass, and the new guest regressions also run
under default GC with explicit stress. Integration owns the combined full gate.
Sources, exact commands, compiler/binary hashes and counts are in
[the experiment](../../experiments/d9-rc-read-loans-20260926/README.md), with the
larger validation set in [compressed evidence](evidence/d9-rc-scalar-read-loans.json.gz).

The callback without an explicit named snapshot exposed a preexisting runtime
mode discrepancy: the preserved before compiler prints `7` in RC but `91` in GC
on both actual backends. The RC before/after counts and result are unchanged by
this optimization. The shared guest regression adds a named snapshot, which
both modes preserve. The original divergent case and exact baseline failures
remain in `callback.my` and `gc-callback-before.json`; correcting that evaluation
contract is a separate correctness task, not claimed as resolved here.
