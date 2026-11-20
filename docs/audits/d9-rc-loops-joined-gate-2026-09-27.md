# Combined loop correctness checkpoint

Frozen source `49c6ca07bbba8b35cda4436b831327ac40c8fc87` passes the complete
four-command gate: main 94/94 steps with 2,359 executed tests, QBE 51/51 with
451 tests, native builds 29/29 and formatting 2/2. The Debug install passes
19/19 steps, and separate whole-tree Guardian passes all 88 checks. Compiler
SHA256: `49a8df2d575b65b16d3e7b455a8b0d6a3aa11ac4eccc13ad34dc3eeb8b54ebd5`.

Both forced counted-RC backend sweeps pass **1,013 assertions across 171
programs**, with zero failures, skips, cached results, dropped files or unloaded
files. LLVM uses `--release`, including O3 and full LTO. Source and HEAD stayed
frozen through the serialized build, gate and sweeps. The
[archive](../../experiments/d9-rc-loops-joined-gate-20260927/README.md) binds
the exact compiler, command summaries, terminal statuses and raw receipts.

The source adds dictionary-loop uniqueness `88f4e477` and guarded read-list
versions `be0cba69` to the previous readers/write-path checkpoint. Both joined
through real two-parent merges. The first merged source `05d318dc` failed its
install gate on Guardian `twin-drift`: dictionary and append proofs repeated
the same branch dispatch. `49c6ca07` shares explicit destination traversal in
`ownership_sources.targetsSatisfy` while preserving their different lifetime
and entry-reset predicates. Multi-arm switch and Result-exit assertions cover
the extraction; dictionary and append focused groups pass 15/15 and 14/14.
The first failed build and intermediate change-classification receipt remain
archived. Neither is counted as a successful gate.

This checkpoint establishes combined correctness. The current 30-program
non-Lox performance diagnostic remains separate, and component improvements
do not establish whole-corpus acceptance. Stage 4 still requires the unchanged
43 programs per backend to meet instruction geomean at most 1.0, every row at
most 1.3 and lower median peak RSS against accepted GC. GC remains the default;
main remains unchanged.
