# Consumed RC constructor fields — 2026-09-26

Record and variant constructors now use the existing guarded operand transfer
when initializing a counted field. An ordinary initialized owning token moves;
a borrowed or held operand obtains an independent value. Pin and region handling
remain in the runtime transfer. Unique-resource fields retain their existing
consuming path, and record updates retain their existing replacement operation.

The partially constructed aggregate is already zeroed and journaled. A transfer
failure leaves the source obligation intact. After success the prepared value
moves into the field with no intervening fallible operation, then its pending
guard clears. This removes an unnecessary acquire/release pair for fresh
constructor operands without weakening trap cleanup.

The focused structural test passes 12/12, including the primary aggregate
contract. Actual uncached RC tests pass 58/58 on QBE and 58/58 on LLVM O3/full LTO,
covering aggregate construction, recursive boxes, arenas, capability resources,
held receivers, temporary lifetimes and contracts. Whole-tree Guardian88 passes.
The combined full gate remains an integration responsibility.

Private binary-trees n12 before/after diagnostics use Debug compilers and match
all output bytes. The before source includes ordinary-pointer fast paths and
read-only body borrowing; this isolates the constructor change. Per backend,
owner acquisitions fall from 1,996,163 to 19 and releases from 2,665,223 to
669,079. All 669,060 allocations retire, holds and clones remain zero, and the
33 uniqueness checks are unchanged.

Three interleaved CPU2 instruction medians give after/before ratios 0.829426
on QBE and 0.809678 on LLVM O3/full LTO. This is an additional 17–19% instruction
reduction in the private probe. It is not the full-workload WP-4 performance
criterion. Evidence, commands, compiler/binary identities, raw samples, counts,
source patch, and uncached test verdicts are retained in
`experiments/d9-rc-constructor-takes-20260926/`.
