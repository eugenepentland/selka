# RC physical loop hoists — 2026-09-26

RC now refines semantic loop hoists after the physical ownership plan is
finalized. The bounded proof accepts scalar-only loop bodies whose managed
reads immediately enter certified receiver loans or an inert mutation path.
It refuses callbacks, arenas, lasting managed publication, named managed stores,
root rebinding, unexpected control entry and unknown operations. The root must
already be live at the loop header. Refusal keeps the original checks.

The rebuilt COW plan must have exactly the same alias and place graph. Existing
hidden-use liveness remains conservatively extended; it is never shortened or
recomputed underneath the RC edge plan. Element hoists apply only to ordinary
lists whose elements are lists of plain values. The entry makes the outer list
unique first, then invokes the typed RC element bridge at its actual region.
Captured receiver stores also recognize a proved entry check, avoiding a second
check per iteration. GC lowering is unchanged by this optimization.

Both compiler arms are Debug builds of the same joined base `305efc45`; the
candidate adds this proof and emitter hooks. Candidate SHA256:
`77943e10658ad9a9abe7e3419bb23ddbc02f051fe531dc7309220f5f00ed3068`.

| Counted probe | Before checks | After checks |
| --- | ---: | ---: |
| 1,000 flat-list writes | 2,004 | 5 |
| 1,000 writes through two shared rows | 3,012 | 16 |
| Four loop/snapshot regression assertions | 235 | 87 |

QBE and actual LLVM O3/full-LTO agree on every counter. All other counters are
unchanged in each pair: the nested probe still has 16 allocations/retirements,
two clones and 1,010 owner acquisitions. The tests include zero iterations,
breaks/continues, repeated shared child pointers, nested loops, callbacks and
snapshots created inside the loop. Broader pending receiver, callback, aggregate,
view, borrow and temporary lifetime tests pass 79 assertions per backend, with
balanced and identical backend counters. The structural selection passes 12
tests and whole-tree Guardian passes 88 checks. Exact commands and identities
are in [raw evidence](evidence/d9-rc-physical-hoists.json.gz).

Median-of-three retired user instructions on CPU 10 also fall for the same
counted probes: flat writes are 0.4369× QBE / 0.5861× LLVM, and nested writes
are 0.5486× QBE / 0.6120× LLVM. Exact binaries, perf commands, raw samples and
all output/count checks are in [timing evidence](evidence/d9-rc-physical-hoists-perf.json.gz).

These are focused traffic and correctness results, not the required 43-program
instruction/RSS acceptance. Root integration owns the full gate. Its newly
exposed GC mutable-parameter rebinding failure also reproduces with the accepted
stage3 compiler and is being corrected separately; this RC-only hoist does not
change that behavior.


Combining this proof with the nested receiver loans in `db5beb67` preserves the
n12 matrix output on both backends. Against the same source at joined `305efc45`,
owner acquisitions fall from 9,343 to 1,831, releases from 9,475 to 1,963, and
uniqueness checks from 5,652 to 482. Both arms retain 132 heap allocations and
retirements, one clone, and no holds. Counted median-of-three user instructions
on CPU 10 fall from 7,769,760 to 2,140,056 on QBE and from 4,954,670 to 1,449,953
on LLVM O3/full-LTO. This source changes only the mandated matrix dimension
from 500 to 12 for diagnosis; it is not the acceptance workload. The candidate
also includes the separately validated mutable-parameter correction, which this
source does not exercise. [Combined raw evidence](evidence/d9-rc-hoists-nested-loans-perf.json.gz)
records exact compiler/binary hashes, commands, output checks and counters.
