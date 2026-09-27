# Stage 4 plain scalar publication in an owning record

**Open Stage4 correctness requirement:** an additional arena record-child
snapshot control fails on both GC and RC, on both actual backends, in immutable
integration `468bd8e5` (compiler SHA `082edf36…`) and this candidate. All eight
receipts are preserved below; this performance commit does not fix or waive that
preexisting defect. A previous passing gate is not a completeness claim.

The bounded compiler certificate removes all 36 broad Runtime loans from the
18 scalar counter updates in unchanged Lox `vm::run`. The root record keeps its
existing managed edges; only the final STORE_LOCAL writes the scalar field.
Runtime ownership, uniqueness, descriptors, allocator and benchmark inputs are
unchanged. This is an isolated performance slice, not Stage 4 acceptance.

The [reviewed design](d9-rc-plain-record-write-design-2026-09-27.md) records the
physical lifetime and effect proof. Root and the compiler peer reviewed both the
design and implementation. The compiler peer confirmed the edge-release veto is
a conservative superset of actual early release eligibility.

## Exact admission and lowering

`rc_plain_record_write` records root, capture, scalar value, field and start PC.
It requires an initialized caller-storage `mut` ordinary inline record, an exact
eight-instruction capture/update/store-back tail, and a complete prior RHS store.
The destination is a direct integer or bool field. Managed cells, collections,
unique contents, live views, non-caller roots, physical aliases and indirect
storage decline. The tail has exact stack heights, no interior CFG entry or
inlined origin, and no planned COW, SHARE, capture, loop-entry or owning cleanup.
Live aliases of the root decline. The temporary has no other definition, use,
reference, move, pattern binding, receiver publication or implicit COW writer.
This proves its journal guard remains empty through every loop iteration.

The two capture stores create no token. Its sole load names the stable caller
record, and UPDATE_RECORD leaves the record unchanged. At the original final
STORE_LOCAL, lowering loads the complete scalar and writes its existing native
width. All managed siblings, pins, semantic history and owning addresses remain
unchanged. The existing instruction step checks stay in place. The public runtime
drain boundary is not weakened: this interval releases no edge and invokes no
callback, so it creates no new queued-finalizer obligation.

The proof rejects functions above 4,096 instructions. Its 262,144-cell allowance
charges whole-function capture-use scans, not every analysis operation: fixed
tail, COW/writer, release-edge and alias checks add bounded metadata scans. Actual
`vm::run` has 1,701 instructions; its 18 capture scans charge 30,618 cells.
EmissionPlan gains one cohesive certificate slice and stays at four fields;
State and the runtime ABI do not grow. General lowering handles every refusal.

## Frozen comparison

The base worktree commit is `51b59806a9a50d35644b9616253cc7ea9ef01d8a`, a real
merge whose code equals integration `468bd8e536b0e088ff71291cb9a3c92db8ebf448`.
The accepted GC baseline is untouched. The matched control compiler is the
Debug integration `install-append-compose-scalar/bin/mylang`, SHA-256
`082edf36c3b1370debeccb4bdcbf3069fbf7829ad1852e8a7d0d5d7f2a34c67e`.
The candidate Debug compiler is `d9-rc-lox-probe-astra/.tmp-plain-record/install-final/bin/mylang`,
SHA-256 `ca907dc060c537aa9c527cbedab0494ad04c35828a14266a4a54e0ba6e345d52`.
The archive preserves its exact source overlay and compiler/binary identities.
The preliminary and final installations have identical compiler hashes.

All 25 Lox source files copied into the isolated measurement directory match the
accepted workload byte for byte. N4/N5 are existing reduced diagnostic scripts;
full N10 uses the mandated script unchanged. Builds use actual QBE or LLVM O3
with full LTO, and each manifest verifies its backend. Measurements use CPU 3,
three uncounted repetitions and separate counted executions. Every raw
instruction receipt must report 100% event running time. Full N10 repetitions
alternate before/after; all outputs are checked byte for byte.

| Input | Backend | Before instructions | After instructions | After / before |
| --- | --- | ---: | ---: | ---: |
| N4 diagnostic | QBE | 3,555,126,471 | 1,299,606,422 | 0.365558 |
| N5 diagnostic | QBE | 6,935,992,957 | 2,445,734,125 | 0.352615 |
| N4 diagnostic | LLVM | 2,962,097,354 | 1,033,968,148 | 0.349066 |
| N5 diagnostic | LLVM | 5,790,399,957 | 1,951,614,655 | 0.337043 |
| N10 unchanged | QBE | 852,905,470,678 | 291,712,358,892 | 0.342022 |
| N10 unchanged | LLVM | 712,152,855,974 | 229,803,500,032 | 0.322688 |

The counted results agree across actual backends. All allocations retire, every
O acquire plus initial allocation is released, and H acquisitions/releases match.
The counters below distinguish physical traffic from semantic snapshot behavior;
the `clone_shell` counter is not asserted to describe every collection allocation.

| Counter | N5 before | N5 after | N10 before | N10 after |
| --- | ---: | ---: | ---: | ---: |
| O acquire | 2,547,995 | 709,094 | 311,200,831 | 81,463,495 |
| O release | 2,734,238 | 747,402 | 334,107,440 | 85,814,103 |
| H pairs | 5,971,799 | 2,293,997 | 736,227,500 | 276,752,828 |
| Allocate / retire | 186,243 | 38,308 | 22,906,609 | 4,350,608 |
| Clone shells | 9,755 | 9,755 | 1,095,889 | 1,095,889 |
| Uniqueness checks | 183,857 | 183,857 | 20,836,904 | 20,836,904 |

The frozen `vm::run` IL changes from 94 native loan sites to 58, with exactly
18 certified stores. The eliminated 36 sites are all the 208-byte Runtime loans.
The narrow list/record loan sites remain. This removes broad temporary ownership
as well as traversal; it does not make runtime uniqueness ignore an owner.

## Correctness controls and publication boundary

Focused structural tests pass 15/15 (four named cases and eleven common blocks).
They retain checked overflow, prove the final commit follows its step check,
and refuse owned copies, managed updates, unique or held contents, a different
store-back root, an external branch entering the tail, and a capture used before
its certified definition. Five permanent guest assertions run standalone on
GC stress and counted RC on both actual backends: saved record/child snapshots,
RHS observation and mutation, loop reuse, false/bool width, caller arenas,
same-call snapshots, and a managed child pinned by a pending receiver. All twenty
assertions pass, with RC counts 33 allocate/retire, O17/50 and H19 pairs.

Sixteen further executions preserve overflow, allocation-budget, frame-budget
and step-budget traps in an arena caller with a heap child and saved snapshot.
They print the same pre-trap output, report the expected trap and balance counts.
The counted allocation refusal retires both heap allocations and releases all
three extra O acquisitions; its sixteen arena allocations remain arena-managed.

A separate C harness directly calls the generated internal `mut` ABI with a
host-owned inline record, null managed child and observable scalar/sibling bits.
It uses budgets 17–20 around UPDATE_RECORD PC17 and STORE_LOCAL PC18. On both
backends the immutable control and candidate match **within each runtime**:

| Budget | GC scalar after trap | RC scalar after trap | Untouched sibling |
| --- | ---: | ---: | ---: |
| 17 | 41 | 41 | 91 |
| 18 | 42 | 41 | 91 |
| 19 | 42 | 42 | 91 |
| 20 | 42 | 42 | 91 |

Thus the candidate preserves the original RC publication boundary, including a
trap after UPDATE_RECORD but before STORE_LOCAL. GC's preexisting in-place update
is visible one instruction earlier through this internal host probe. The probe
bypasses the public scalar embedding argument contract; it is not a claim that a
public trapped call exposes this host-owned record. Normal guest observations
and public trap codes remain unchanged. The first probe receipt, which assumed
identical GC/RC timing and failed that assumption, is preserved separately.

Debug install Guardian88, standalone whole-tree Guardian88, formatter,
`git diff --check` and documentation coverage are recorded in the archive. A
mistaken `guardian-check commit` invocation passed its first check phase and
started a full test phase; only that exact process tree was stopped before
any auto-commit. Its interrupted receipt is preserved and is not a gate verdict.
Root owns the full joined gate; no candidate acceptance claim relies on that run.

## Separate arena snapshot defect found by an added control

A sixth, stricter arena-owned-child control did **not** pass. The exact original
source and all eight before/after × GC/RC × actual QBE/LLVM diagnostic receipts
are archived. After `saved = state` inside an arena, appending to `state.values`
also changes `saved.values` from `[12]` to `[12, 14]`. Scalar snapshot bits remain
independent. Both immutable468 and this candidate produce the same wrong list
output on both runtimes/backends; the RC counts balance. A one-field record
without the scalar calls also reproduces it, so this optimization is not causal.

This is a preexisting arena value-semantics defect, not an accepted expected
result or a passing control. The original five permanent assertions remain green;
the extra failing control is retained separately in the experiment for a dedicated
correctness commit and permanent regression. Root requested that separation to
preserve attribution of these frozen performance binaries. Stage4 acceptance
remains pending this defect and the other combined correctness/performance gates.

## Evidence

[The archive](../../experiments/d9-rc-plain-record-write-20260927/README.md)
contains compressed raw measurements, all build manifests, exact source and
output controls, before/after VM IL, trap/step drivers and validation receipts.
Run `python3 experiments/d9-rc-plain-record-write-20260927/verify.py` to validate
its identities, outputs, counters, publication observations and all 36 hardware
instruction samples. Complete-corpus acceptance, peak RSS and joined performance
remain root's separate gates.
