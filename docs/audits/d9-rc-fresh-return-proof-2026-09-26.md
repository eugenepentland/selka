# D9 WP-4: certified fresh return and empty normal cleanup

Recorded 2026-09-27; the artifact directory retains the experiment's start date.

This slice builds on `ecccc02c` and reuses the closed fresh-constructor certificate
from `7c78c511`. It changes only return lowering and tests. It does not change the
runtime ABI, journal layout, allocation path, generic return path or the trap
unwinder. Measurements are isolated diagnostics, not WP-4 acceptance.

## Remaining work in the old return

Even after the constructor had completed and owned its result, `make` prepared
that value again for return. The depth-12 tree's 16-byte Node passed through two
pointer/header tests, a generic take fallback, a blit to `rcwork`, source zeroing,
pending descriptor/role/guard stores and the normal four-entry cleanup scan.
The ordinary count traffic was already zero on those handoffs.

The certified path materializes the aggregate in the existing disjoint return
work buffer, clears its original operand guard, unlinks the RC frame, preserves
ordinary frame accounting and returns through the unchanged ABI. Scalar pointer
results are already materialized in the loaded SSA value. The source bytes do
not need zeroing after their sole guard has been disarmed: no scanner observes
inactive RC slots and the frame is about to leave. Generic preparation remains
as the fallback after an explicit ordinary-live-token check.

## Bounded proof

The existing certificate admits only scalar parameters and locals, scalar
operations, ordinary record/variant constructors, closed self recursion and
forward branches whose edges have empty operand stacks. It refuses all physical
copies, including immutable-box copies; all non-move transfers; managed locals;
unknown and indirect calls; captures; semantic SHARE events; loans; holds; unique
resources; arena transitions; host/C ABI entries; heap-backed frames; and new
opcodes outside its whitelist. Its instruction/type walks are bounded.

An additional return check limits the result to 256 bytes and explicitly refuses
`largeResult`. The current hidden-output-storage threshold is greater than 4096
bytes, so the latter is redundant today, but retaining the query keeps the proof
coupled to future ABI decisions. Wide returns keep their old caller-output and
heap-frame handling.

The one-live-result property follows by induction over the admitted operations:

| Operation | Ownership fact at its completed boundary |
| --- | --- |
| Scalar constants, arithmetic and scalar local access | They carry no ownership token. |
| Record/variant constructor | Each field transfer consumes its source or starts from a clear borrowed guard; `constructed` publishes the completed operand and `commitRuntime` clears the internal construction guard. Pending field work has already been consumed. |
| Self call | Inputs are scalar. By induction its successful canonical result is ordinary owned; the caller's existing result publication clears pending storage and guards the one output. |
| Branch or jump | A branch consumes only a boolean and all edges have empty stacks. There are no managed locals in which an obligation could hide. |
| Return | Its stack has exactly one value. The dynamic ordinary-live check validates its physical role before taking the new path. |

Consequently the normal cleanup has no other owner to release and no callback
to execute. The pending and internal guards are clear. Scope/capture operations
are outside the grammar, so the frame's scope checkpoint is unchanged; the
existing `myl_qbe_rc_frame_leave` still validates that checkpoint and unlinks the
frame. Caller scopes remain intact.

Every allocation uses the inherited current region. The function cannot change
that region and its self callees obey the same rule, including when the caller
is already inside an arena. Thus returning the same token does not require an
escape clone or relax a region barrier. The caller's later stores and explicit
arena escape still use their existing checks and transfers.

The complete journal remains registered through every fallible operation. The
return bytes are materialized before source guard handoff; subsequent leave
operations neither allocate nor invoke user callbacks. Allocation refusal,
checked arithmetic failure, instruction limits and frame admission still run the
ordinary trap cleanup. The native stack estimate, physical stack-floor check and
logical step/frame accounting are unchanged. This optimization applies only to
the successful return suffix.

Independent review confirmed constructor/self-call clearing and empty branch
edges. The review prompted an explicit hidden-output ABI refusal, even though
the existing size cap already excludes that ABI. Its addition leaves emitted
guest code unchanged; separate identity receipts verify this against the measured
candidate.

## Isolated result

The control is the immutable Debug compiler for `ecccc02c`, SHA-256
`49372ab04bd2c1408398f7be97e8b7ec2abbca0a6d0f9872226f322cb8bea3a1`.
The original measured candidate is
`ff3a276610ffa11822365e19cd85ca2f01227f0606939fef843ec1119357dea1`.
The final compiler after the defensive ABI query is
`b85651cda9d29c1e7fb210c081316b285040e2b278ff7588841ded2e5dabdcc7`.
All four native benchmark ELFs (two backends, production and counting) are
byte-identical between the measured and final compilers. Five emitted program
JSON controls are also identical.

Actual native depth-12 binary trees, CPU 2, alternating order, median three:

| Backend | Before retired instructions | After | After / before |
| --- | ---: | ---: | ---: |
| QBE | 524,563,274 | 479,070,024 | 0.913274 |
| LLVM O3, full LTO | 296,063,165 | 263,616,293 | 0.890406 |

Output and every counter match: allocations/retirements 669,060/669,060,
ordinary acquire/release 19/669,079, no holds, no clones, no arena allocations
and 33 uniqueness checks. This remains substantially above the accepted GC
diagnostic baseline; the exact-corpus performance gate remains the acceptance
criterion. This isolated compiler does not include the parent's later cumulative
runtime cache or nbody loan optimizations.

## Validation and evidence

The code-generation tests require the optimized suffix to retain the ABI blit
and frame leave while omitting normal cleanup, take and memset. They require
the complete fallback and trap journal to remain, and reject aliases, managed
local provenance, unknown calls and wide owned returns. The wide case still
admits fresh field transfer, isolating the return-size refusal.

Standalone before/after controls cover recursive aggregate and nullable returns,
explicit escape from a caller-owned arena, generic managed-local/callee paths,
GC stress and counted RC on both actual backends. Refusal probes cover allocation
budget, arithmetic, logical frame limit, step limit and the physical stack floor
with no logical frame option. Counts must balance and match in each pair.

The focused RC unit suite passes 122/122. Actual guest tests pass 36 assertions
on each backend. The standalone matrix passes all 36 process rows: 16 successful
GC/RC fixture runs and 20 located refusal runs, with identical before/after
counts. The final Guardian run passes all 88 checks without ratchet changes.

All raw commands, identities, samples, output, counters, emitted bodies and
validation results are under `experiments/d9-rc-fresh-return-20260926/`. The parent
runs the serialized full integration gate; this branch runs focused validation.
