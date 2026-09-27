# Joined byte, dictionary and record-read checkpoint

Frozen source `368f0357` passes the complete correctness gate. It joins
guarded immutable-byte loops `2af700c7`, certified empty dictionary drops
`bca4ac31`, bounded named-record field reads `c1224f30`, and the loop-guard
instruction-context correction `238db806` through real two-parent merges.

The record-read merge preserves the byte-loop admission, readonly verification,
both plan initializers and both test imports. Its grouped record plan is used
by the managed-readonly verifier. The guard fix also initializes the byte-test
mock's PC and dictionary metadata, which the combined source now requires.

| Check | Result |
|---|---|
| Debug compiler install | 19/19 steps |
| Main gate | 94/94 steps; 2,383 executed tests passed |
| QBE gate | 51/51 steps; 455/455 tests passed |
| Native build gate | 29/29 steps |
| Formatting | 2/2 steps |
| Whole-tree Guardian | 88 checks passed |
| Forced counted RC, QBE | 1,035 assertions across 176 programs |
| Forced counted RC, LLVM O3/full LTO | 1,035 assertions across 176 programs |

Both RC sweeps have zero failures, skips, cached verdicts, dropped files or
unloaded files. Source and HEAD stayed frozen during all commands. The main
gate's raw total includes 24,356 shard skips; the executed count above excludes
them. The exit-zero Zig `failed command` footers are preserved in raw logs.

The immutable Debug compiler SHA-256 is
`4545547e80d9b555e4084d4b2fcbac0fcf4be24c1033d160c58857fd7c208dd1`.
The [archive](../../experiments/d9-rc-byte-dict-record-gate-20260927/README.md)
contains exact command summaries, terminal statuses, compiler identity, raw
compressed logs, drivers and a verifier. Run its `verify.py --live` from this
worktree to include the immutable installed compiler in verification.

This is combined correctness evidence. Isolated byte scanning reaches
2.109321× QBE / 1.081241× LLVM against accepted GC; dictionary counting reaches
1.311910× / 1.325051×; Lox binary trees N10 reaches 21.372315× / 34.478071×.
Those comparisons have separate documented bases and are not combined-build
measurements. No new full-corpus acceptance or geomean is claimed. All 43
programs per backend, the 1.0× geomean, every 1.3× row and lower median peak RSS
remain required. GC stays the default; main is unchanged.
