# Collection receiver captures across callbacks

The scalar-loan negative test exposed a correctness difference already present
in the preserved compiler: reading `values[change(mut values)]` from `[7, 8]`,
where `change` clears the list, appends `91` and returns zero, produced `91` in
GC and `7` in RC. Both actual backends agreed within each mode. The original
before evidence remains in
[`gc-callback-before.json`](../../experiments/d9-rc-read-loans-20260926/gc-callback-before.json).

Value semantics preserves independently evaluated collection values, and the
existing ownership analysis classified the compiler's receiver capture as a
copy. GC skipped that copy because lowering and the old sharing hook treated
all compiler temporaries as writing places. The planner now shares a temporary
read capture when the analysis requires a copy, while excluding the writing
place graph, including aliases passed onward to mutating calls. A pinned
capture takes the existing shallow-copy path.

A direct dictionary index keeps its receiver on the operand stack. Both modes
previously left that operand unprotected across a key callback. The planner now
captures it before key evaluation can mutate the source: GC shares/copies it;
RC publishes an owned operand through the existing journal. A dictionary lookup
that selects a pending writing path keeps its existing identity protocol.
This covers scalar and managed read results, and fields reached through a
record. The language guide and `COW-READ-RECEIVER-1` state the read rule explicitly.

Pinned cases revealed three older GC branches using a raw bit-60 mask as a
QBE `jnz` condition. `jnz` examines a word, so those conditions discarded the
pin bit. The receiver sharing check, nested pin restoration and inline value
copy fallback now compare their masks with zero before branching. A temporary
runtime print probe confirmed the wrong branch; the runtime source was restored
and this change contains no runtime edits. Existing RC holds/uniqueness/scope
branches use word guards or normalized status/comparison results.

Ten new assertions pass under GC stress and counted RC on both QBE and actual
LLVM O3/LTO. The RC executions have identical balanced counts: 80 heap
allocations/retirements, 32 owner acquisitions, 112 releases and 54 holds each
way. The broader receiver/view set passes 50 assertions in each of the four modes;
RC balances at 7,368 allocations/retirements with 5,518 owner acquisitions and
12,886 releases. All 32 focused COW unit tests pass. Exact results are recorded in
[the experiment](../../experiments/d9-read-callbacks-20260926/README.md).
This is a correctness fix; the earlier isolated scalar-loan traffic comparison
remains unchanged and makes no timing acceptance claim.
