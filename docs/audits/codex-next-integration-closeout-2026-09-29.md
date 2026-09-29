# Compiler integration closeout, 2026-09-29

This audit follows Phase A of `next-work-plan-2026-09-29.md` in the isolated
`codex/next-closeout-20260929` branch. Original checkouts and paused lane
worktrees were read only. The integration starts at `1a098368`, which adds
the plan and gate script to the RC source at `1f744a3f`.

## A1 evidence

Gate `m16-codex` tests the unchanged source at `1a098368`. Logs and full guest
JSON are in `.tmp-gate/m16-codex/`; performance JSON is in `.tmp-rc-quick/`.
All 27 recorded statuses are zero, and HEAD stayed at `1a098368`.
Checked-in evidence is in `docs/audits/evidence/codex-next-integration-20260929/`.
Guardian passed all 88 checks; feedback is committed in guardian-zig at `54790d9`.

| Check | Result |
|---|---|
| Full Zig test | 96/96 steps; 2,567 executed tests passed (26,278 unselected shard entries) |
| QBE | 51/51 steps; 472/472 tests passed |
| QBE build / format | 29/29 and 2/2 steps |
| Native memory / heap | 23/23 and 10/10 steps |
| Guest sweep | 1,326/1,326 across 207 programs in each of nine modes; identical test-name sets |
| Lox | RC, GC, RC release and GC release each pass 65 directory tests and 13 driver cases |

Guest and Lox checks have zero failures, skipped tests, cached results or dropped
tests. Zig's skipped count comes from shard selection, not omitted guest coverage.

| Dev corpus | m14 QBE | A1 QBE | m14 LLVM | A1 LLVM |
|---|---:|---:|---:|---:|
| RC/GC instruction geomean | 1.074153 | 1.064484 | 1.085282 | 1.069132 |
| Rows at or below 1.3 | 43/43 | 43/43 | 43/43 | 43/43 |

All 86 dev outputs and 86 smoke outputs match accepted GC outputs.
There are no dev instruction regressions greater than 1%. Larger improvements
are recorded in the evidence JSON. The inherited pin and fresh-buffer lanes
explain nbody, sort_quick and bytes_scan; smaller text-heavy movements are
consistent with the inherited ASCII construction/index and dense type-id work.
This last attribution is an inference from the affected code paths, not an
isolated profile. Short Lox smoke rows retain known startup overhead, so smoke
is differential correctness evidence rather than the dev acceptance cap.

## A2 tooling integration

`claude/tool-gaps` at `b1a8db99` merged cleanly at `e2e028ad`; both sides of
the spec and CLI docs were retained. The rebuild passed with 88 Guardian checks.
The complete CLI step passed 264/264 tests (10/10 build steps). RC and GC Lox
project builds passed; each runtime passed 65 directory tests across 10 programs
and 13 driver cases with zero failures, cached results, skips or drops.

The integrated rules are IO-FILE-WRITE-LINEAR-1, CAPABILITY-FIELD-METHOD-1,
CLI-INPUT-REFUSED-1, CLI-CACHE-DIR-1, RUN-FLAGS-1, RUN-FRAME-BUDGET-1 and
PROJECT-LIMITS-1. Their tagged Zig/guest tests and both sides of the documentation
remain present. The project-budget and frame-budget policy remains active in
harness commands. A2 logs are in `.tmp/a2/`; a compact checked-in summary
records the tested compiler hash and actual test results.

The integration script now creates its temporary directory, copies Lox into
gate-owned scratch space, forces fresh Lox execution through the build-slot
limiter, and returns a nonzero status if any recorded step failed or HEAD moved.
Previously the final `echo done` concealed earlier command failures from the
script's exit status, and its Lox commands bypassed admission. Shell syntax and
diff checks pass; the combined A5 gate will exercise the revised script.

## A3 typing and A4 stage 1

A4 is complete at `42bef49d`, with an inherited compiler tip of `a48b62f5`.
Its checked-in audit separates preserved lane gates from fresh continuation
checks: warm fuzz has 98 ok, two GC-stress-only findings and zero RC divergences;
86 dev plus 86 smoke outputs match; every dev row meets the cap and regression
limit; RC and GC Lox each pass 65 directory tests and 13 driver cases.
The required Guardian feedback is committed in guardian-zig at `255b142`.

A4 merged at `cc4efab8`. The affected-test conflict keeps the tooling lane's
small refusal/selection helper but uses stage 1's checked-graph reuse and
one-diff dependency planner. Configuration and policy refusal statuses remain
2 and 3. Both appended CLI suites are present, including `fix_cli_test.zig`.
The new formatter's text allocation helper now roots through the shared
`myl_rc_pointer_leaf` from rc-typeids; its old private `pointer_type` no longer
exists. The final merged rebuild passes 19/19 steps; the affected CLI filter
passes 3/3 tests, and the formatter passes 6/6 under default RC, GC-stress and
release. The merge commit passed all 88 whole-tree Guardian checks.
Initial merge-resolution error-set and stale C-descriptor build failures are
preserved in `.tmp/a4-merge/`, alongside the corrected green results.

A3 is finishing on `codex/next-typing-20260929`. The initial six-case addition
to the existing float-unary runtime helper regressed QBE float rows. Splitting
the narrow conversions into a statically selected helper restores the old
helper and all three affected rows. Final lane counts, source commit and
performance evidence are recorded after its frozen-compiler gate completes.

## A5 and remaining plan

The combined gate and explicit user approval precede any fast-forward of
`main`. Phase B remains open (text surface, per-module builds, runtime
follow-ups and tooling/GC), followed by the four-lane EDA port in Phase C.
B4 independent fixes and B2 reconnaissance may advance before the checkpoint;
their implementation is not part of the Phase A gate unless explicitly listed.
