# Fixed-point physical borrowed returns

The optional physical return certificate now proves bounded loops. Schematic
`partPin` can return a caller-owned pin or an inline fallback containing only
immortal bytes. Its previous forward-only certificate refused the search loop,
so direct calls always used its owned entry. This slice emits a separate borrowed
entry for the complete proved body, while canonical, indirect and exported calls
keep their owned ABI.

The unchanged three schematic inputs use a further 2–3% fewer retired instructions
than the preceding plain-field slice. This remains an isolated RC improvement;
it does not satisfy the complete WP-4 performance acceptance gate.

## Proof and bounds

The implementation follows the separately reviewed
[design](d9-rc-borrowed-loops-design-2026-09-27.md). `rc_borrow_flow` owns a queue
with one position and queued flag per instruction, and one mutable incoming
state per reachable instruction. The transfer function reuses one scratch state.
No per-iteration state array is allocated.

At a join, stack heights and physical types must agree. A value is either
parameter-anchored or contains only immortal/plain bits. Distinct parameter
anchors refuse certification. An immortal origin may become one parameter
anchor. An unavailable local is a separate fact; once unavailable at a join,
it cannot regain availability from another predecessor. An explicit local store
can still define a new outgoing value.

Any changed incoming fact requeues its instruction. **No return is accepted
before the queue converges.** The final scan checks every reachable physical
return against its converged state and requires exactly one declared result,
with the same parameter anchor or immortal-only edges. The regression in which
an earlier return sees parameter A on the first traversal but parameter B after
a backedge refuses certification.

The prior opcode, ownership and authority grammar is unchanged. Mutating calls,
parameter replacement, arena transitions, unknown/indirect calls, fresh heap
construction, unique contents and semantic copies remain refused, even if a
later path discards their results. Direct helper calls must independently prove
immortal-only results. Transitive parameter-anchored helpers remain outside this
slice. Checked indexing, arithmetic, steps, frames and source metadata remain.
Inline return bits still use the existing ABI return storage.

The existing maximum of 16 active proof functions and 65,536 abstract state cells
is retained. A separate root-query budget of 524,288 abstract cells charges each
transfer, join and final hashing visit by the conservative whole-state width.
Repeated helper queries share both budgets. Exhaustion declines this optional
optimization; real allocator failures propagate. The certificate policy is v5.
Only the final ascending-PC scan contributes to the accepted dependency hash,
including the same ABI, type layouts, operations and helper identities. Queue
order and repeated visits cannot alter an accepted cache identity.

The compiler agent independently reviewed the draft and found no blocker in
scratch/incoming separation, monotone joins, bounded queue capacity, deferred
return acceptance or deterministic hashing. No runtime or emission hook changed.

## Matched exact schematic result

The immutable predecessor is `6ce92814`, compiler SHA-256
`dedb995e15316f70b472faa4d80c7d3dd1ce35c1ddc552feaef567811acd2cc5`.
The candidate Debug compiler is
`54f19f6b7d0229727d21e8474dadba7a2aaacc4366568223105e614210765518`.
The final green installation is byte-identical to the measured installation.

The driver uses the unchanged source/provider, project inputs and `pc.py`
build/run/check commands. LLVM explicitly selects `--backend llvm --llvm-opt 3
--lto`. Each normal binary runs three times on CPU 3 with unscaled
`cpu_core/instructions/u`; all 36 observations report 100% event running time.
Every normal/counting check and measured execution verifies the complete SVG
hash. Separate counted binaries report identical counters between backends.

| Backend | Exact workload | Before instructions | After instructions | After / before |
| --- | --- | ---: | ---: | ---: |
| QBE | fixture | 961,907,293 | 932,171,061 | 0.96909 |
| QBE | changed-net | 959,872,272 | 935,224,863 | 0.97432 |
| QBE | changed-value | 959,854,250 | 934,700,794 | 0.97379 |
| LLVM | fixture | 792,849,778 | 773,875,979 | 0.97607 |
| LLVM | changed-net | 795,039,120 | 778,051,996 | 0.97863 |
| LLVM | changed-value | 793,941,040 | 774,274,911 | 0.97523 |

Fixture/value H pairs fall from 361,686 to 343,278; changed-net falls from
361,928 to 343,520. O counts are unchanged: fixture/value 168,193 acquisitions
and 168,349 releases, changed-net 168,165 and 168,321. All runs have 156 heap
allocations/retirements and one clone, with no refusal or saturation. All count
balances hold. Uniqueness remains 16,776 (changed-net 16,806).

`partPin_rc_borrow` contains no native loan, retain or take call. Its canonical
entry is unchanged. `innerPin` still materializes independent results through
the existing direct-borrowed caller contract; its two calls now add two loan and
two retain sites. This explains the modest isolated reduction and leaves
caller materialization as a separate future proof problem.

## Validation and evidence

The focused `RC-BORROW` suite passes 26/26: 15 named tests plus 11 common unnamed
blocks. It includes the backedge anchor conflict, unavailable joins, bounded
refusal, recursive helpers, mixed freshness, exact metadata and canonical entry,
and warm/cold caller cache loss/restoration. Five standalone assertions pass in
GC stress and counted RC on both actual backends. They cover first/late/missing/
empty search, parent replacement, caller snapshots, arena escape, indirect calls
and the alternate-anchor negative. RC totals agree: 47 heap allocations and
retirements, O20+47=67, H27 pairs and 14 arena objects.

Bounds, step and frame controls run inside a caller arena on both backends and
both runtimes, retaining their preceding output marker and balanced RC cleanup.
The first step-control attempt supplied the limit only to `build`, which enables
accounting but does not set a standalone process's runtime limit. Its raw output
is preserved separately as an invalid control; the corrected runner supplies
`MYLANG_OPTIONS` and checks the intended trap. No expected runtime result changed.

The Debug build passes Guardian's 88 checks, Zig formatting and diff checks.
Guardian caught missing graph cleanup/docs and incorrect new guest spec tags;
these were fixed without changing a baseline. The integration parent owns the
joined full gate and complete corpus runs. Commands, source delta, IL, identities,
raw counters and the independent verifier are in the
[archive](../../experiments/d9-rc-borrowed-loops-20260927/README.md).
