# Joined byte, dictionary and record-read correctness gate

Frozen source `368f0357` combines guarded immutable-byte loops `2af700c7`,
certified empty dictionary drops `bca4ac31`, bounded named-record field reads
`c1224f30`, and loop-guard instruction-context correction `238db806`.
Each slice joined through a real two-parent merge. The record-read merge
preserves both refinements and initializers, uses the grouped record plan in
the readonly verifier, and retains both test imports and the byte-loop proof.

The Debug install succeeds (19/19 steps). All four required gate commands
pass: main 94/94 steps with 2,383 executed tests; QBE 51/51 with 455 tests;
native build 29/29; formatting 2/2. Whole-tree Guardian passes all 88 checks.
Both forced counted RC sweeps pass 1,035 assertions across 176 programs,
with zero failures, skips, cached verdicts, dropped files or unloaded files.
LLVM uses --release, which selects LLVM O3 and full LTO. Tracked source and
HEAD remained frozen throughout the gate and both sweeps.

Identity, exact summaries, raw compressed logs, terminal statuses, drivers
and artifact hashes are archived here. Exit-zero Zig failed-command footers
are retained; terminal statuses and final summaries determine the result.
The collector is a one-shot script for the frozen source; it does not run
tests. The verifier checks archived receipts and optionally the live compiler.

This establishes combined correctness, not performance acceptance. The
separate byte/dictionary/Lox comparisons use their documented isolated bases.
No new combined 30- or 43-program performance claim is made. GC remains the
default; main and the pending devspeed branch are unchanged.
