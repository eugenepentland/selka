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

A3 is complete at `1e3a64d4`, with implementation `aac69d9f`. Its audit
records 2,600 selected Zig tests, 479 QBE tests, 1,382 guest tests across
213 programs in each of five modes, eight embed checks under default/GC/release,
and RC/GC Lox builds plus 65 tests and 13 driver cases. Both corpus sizes
match all 86 outputs; every dev row meets the cap and regression limit.
Fuzz has 98 ok, zero invalid, the same report-only stress seeds 19/87 and zero
RC divergences. Guardian feedback is committed at `8037b10`.

The merge keeps A3's constant-policy hint guard and separate narrow-float
runtime helper, A4's binary/chain helpers, and both appended CLI suites.
Float dispatch lives in the shared constant `binaryValues` helper so constant
chains use strict binary64 operations too. Combining the lanes exposed two
expression helpers at cognitive complexity 26/25; private binary-queue and
call-temporary helpers restore the limits with identical behavior.

The reviewer confirmed a cross-feature failure: both ordinary and generic
`half(4) == Some(2) == half(4)` refused `Some(2)` with `E_OPTION_INFERENCE`,
although separate equalities passed. Chains now infer contextual constructors
from each actual adjacent peer type, check shared operands once, and retain
runtime source order and short-circuiting. Four new guest regressions cover
ordinary/generic chains, observed evaluation order and skipped tails, and
folded mixed-float chains. Option equality passes 11/11 and float constants
14/14 under default RC, GC stress and LLVM release, with zero cache/skip/fail.
The rebuilt merge passes 19/19 steps and all 88 Guardian checks. Logs and the
initial complexity failures remain in `.tmp/a3-merge/`; the compact merged
verification is checked in with the other integration evidence.

## A5 combined verification and approval checkpoint

Gate `m17-codex` froze compiler source at
`d8f66585830733e2771fed0eb032dd1406a24797`. The installed and private gate
compilers have SHA-256
`4059a85e3d081f8a73b370e03e7d86cba8eb8a47531bfcdd7c09e6cc109d74b1`.
The evidence commit after this gate changes documentation and receipts only.

All 27 recorded statuses are zero, HEAD stayed fixed and the strict verifier
confirms identical qualified test-name sets in all nine modes. Guardian feedback
is committed in guardian-zig at `8a65ccb`. Raw logs and full guest JSON remain in
`.tmp-gate/m17-codex/`; compact statuses, hashes and all corpus rows are checked in
as `a5-final-verification.json` and `a5-supplement-verification.json`.

| Check | Result |
|---|---|
| Full Zig test | 96/96 steps; 2,655 selected tests passed (27,126 unselected shard entries) |
| QBE | 51/51 steps; 480/480 tests passed |
| QBE build / format | 29/29 and 2/2 steps |
| Native memory / heap | 23/23 and 10/10 steps |
| Guest sweep | 1,438/1,438 across 218 programs in each of nine modes |
| Lox | RC, GC, RC release and GC release each pass 65 directory tests and 13 driver cases |

All guest and Lox results have zero failures, cached results, skipped or dropped
tests; guest sweeps also have zero unloaded sources.

The supplemental 100-seed fuzz run has 98 ok, zero invalid and zero RC
mismatches. GC-stress-only seeds 19 and 87 retain the known scan-plan refusal
(exit 134) and crash (exit 139), respectively. Both generated programs and
the fuzz summary remain in `.tmp/a5/fuzz/`; their hashes are recorded in the
supplement evidence. The independent B4 candidate fixes the four historical
collector repros, but those changes are outside this frozen Phase A source and
are not claimed by this gate.

All four explicit Lox project builds pass (RC and GC, QBE and LLVM release).
The complete docs check has 223 runnable examples and 57 checked examples,
zero mis-tagged or failed examples, and 11 documented intentional skips.
Feature coverage passes for 221 features, 14 standard modules and 176 exports.

| Corpus size | QBE RC/GC geomean | LLVM RC/GC geomean | Output matches | Maximum increase vs A1 |
|---|---:|---:|---:|---:|
| Dev | 1.064485 | 1.069091 | 86/86 | 0.001820% |
| Full | 1.062698 | 1.065301 | 86/86 | 0.001589% |
| Smoke | 1.103401 | 1.137125 | 86/86 | 0.001940% |

Dev and full have all 43 rows per backend at or below 1.3x accepted GC;
no row regresses more than 1% against A1. The GC denominator is unchanged.
All per-row instruction counts and movements are retained in the supplement
receipt. The largest dev decrease is LLVM text_ops at 0.1484%; the remaining
movements are small. Attribution to inherited format/runtime integration and
startup/layout effects is an inference, not an isolated causal profile.
Smoke retains the previously recorded short Lox startup cap misses, so it
checks differential correctness and change limits rather than the dev cap.
Each `quick.py` execution is CPU-pinned. Dev/smoke use the inherited affinity
pool; the additional full run uses the reserved timing pool. Full is a single
measurement, not the historical median-of-three protocol. The additional A1 full
control measures its unchanged frozen binaries against the same accepted GC.
All 58 unique accepted GC binary hashes match their original manifest.

`main` remains at `6d91f95b`; it is an ancestor of this integration and is not
checked out in another worktree. The explicit approval required by WP-A5 is
pending. No original checkout, paused lane worktree or main ref was changed.

Phase B is still open. B1 has a pinned 86,730-case CPython oracle and a source
implementation map; B2 has its RC/interface reconciliation matrix, strict
oracle requirements and 242,445-line nominal-200k fixture. A current-source B3
experiment reproduces the large-list problem: 250 integers build in 5.89s and
1,000 generate 225,256 IL lines before QBE's size refusal. These are shared
machine single observations, not acceptance timings. B4's independent fixes
and combined continuation are reviewed/tested separately. Phase C remains
open and waits for compiler updates; its preparation accounts for 279 named
Zig tests plus the anonymous import-only declaration and records the strict
counterpart checker's false extras for two approved merged modules.
