# S2 Wave A implementation and validation

Wave A contains S2-0, S2-La and S2-Lb. The controlling specification is
`docs/design/new-core-s2.md`, particularly its accepted decisions in §12, and
`docs/audits/new-core-s2-implementation-plan-2026-10-05.md`.

The integration branch is `codex/new-core-s2-integration`, based on `9ee2a484`.
The three implementation agents use GPT-6.1-sol at xhigh in separate locked
worktrees. The pre-existing checkout and its unrelated edits are untouched.

## Baseline

- `test-core`: 147/147 passed; 85.38 seconds wall time.
- New-core compiler build: 2.34 seconds wall time; 1 second compile step.
- Initial old-core installation: 16.55 seconds, including 12 seconds producing
  the bundled runtime. This is initial setup, not a new-core rebuild measurement.
- Coverage: 2,269/3,509 functions accepted; 2,601 proven and 1,841 exact checks
  across 2,167 accepted functions with reported check counts.
- All fourteen S1 rows match reference checksums at both sizes and are below
  Zig ReleaseSafe (CPU 10, seven interleaved rounds).
- Baseline LLVM and binaries for all fourteen S1 rows and six S0 kernels are
  retained in this worktree's `.mylang-cache/wave-a/baseline/`; their hashes
  and build times are in `integration/baseline-code.txt`.

The supporting baseline logs are in `integration/`. Final package commits,
integration checks, and remaining refusals will be recorded here after review.

## Runtime-levers handoff

S2-Lb owns C4's front-end and old-core semantic half: live-place desugaring,
per-path iteration guards, and the D1 language tests. S2-I's new-core half and
the remaining C4 reference-counting removal work belong to later work.

## Scope boundary

This report is for Wave A. Dictionary/text implementation, function-value
source lowering, sorting and fixed-array source lowering remain Wave B work.
It is not the full S2 exit report or the S3–S5 go/stop checkpoint.
