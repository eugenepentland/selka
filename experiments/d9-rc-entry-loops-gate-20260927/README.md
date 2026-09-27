# Joined entry and loop correctness gate

Frozen source `4e5c0cd6` combines incoming record-field reads `fb4a19a9`,
raw borrowed/immortal helper entries `0aaf0ddb`, and fast-loop operand
isolation `ee6e44e3`, on the preceding `368f0357` correctness checkpoint.
All three slices joined through real two-parent merges. The combined source
preserves the grouped record plans, readonly verification and final loop
operand rewrite after ordinary lowering.

The Debug install succeeds (19/19 steps). All four required gate commands
pass: main 94/94 steps with 2,404 executed tests; QBE 51/51 with 458 tests;
native build 29/29; formatting 2/2. Whole-tree Guardian passes all 88 checks.
Both forced counted RC sweeps pass 1,049 assertions across 179 programs,
with zero failures, skips, cached verdicts, dropped files or unloaded files.
LLVM uses --release, which selects LLVM O3 and full LTO. Tracked source and
HEAD remained frozen throughout the gate and both sweeps.

An earlier install attempt failed because a partial cleanup of the root's
inactive Zig object cache left hash metadata referencing deleted files.
The remaining inactive cache was cleared and the install and complete gate
then passed on the same source. The failed install log, status and explanation
are retained separately. This was a cache-management error, not a compiler
source failure. Exit-zero Zig failed-command footers in successful logs are
also retained; terminal statuses and final summaries determine the result.

Identity, exact summaries, raw compressed logs, terminal statuses, drivers
and artifact hashes are archived here. The collector is a one-shot script
for the frozen source; it does not run tests. The verifier checks archived
receipts and optionally the live immutable compiler.

This establishes combined correctness, not performance acceptance. Isolated
slice measurements use their own documented bases. A fresh 31-program
diagnostic is in progress; the unchanged full 43 programs per backend and
all instruction/RSS requirements remain mandatory. GC remains the default;
main and the pending devspeed branch are unchanged.
