# Cascading-benefit experiment: results

Status: results, 19 September 2026. This is the outcome of the plan in
[cascade-experiment-plan-2026-09-19](cascade-experiment-plan-2026-09-19.md), whose
instrument lives in [`experiments/cascade/`](../../experiments/cascade/README.md).
Everything below is reproduced from the run records by
`python3 experiments/cascade/score.py`.

The question was the two proposals': does a design that states each domain fact
once make later correct changes cheaper, by enough to repay what the design cost
up front? **On this pack, the answer is no.** Neither redesign beat the baseline
by more than run-to-run noise on any task, and neither came close to recovering
its designer's cost. The decision rule was fixed before any run and it fails on
its first two clauses:

| clause | result |
| --- | --- |
| 1. P1 beats B on ≥5 of 7 tasks by more than the spread, losing on none | **fails**: 0 wins, 0 losses — every task's margin sits inside the spread |
| 2. `R(P1) > 0` over the pack | **fails**: `R(P1) = −356,124` tokens |
| 3. P2 does not satisfy clause 1 | holds: P2 also has 0 wins and 0 losses beyond the spread |

So the pack does not merely reward abstraction: the control arm does no better.
What it does not do either is distinguish the arms at all.

## What ran

| | count | notes |
| --- | ---: | --- |
| frozen arms | 3 | `B` (the port), `P1` (representation redesign), `P2` (generalised control) |
| designer sessions | 2 | P1 327,308 tokens; P2 346,226 tokens |
| independent maintainer runs | 63 | 3 per arm per task, every one verified green |
| chained maintainer runs | 9 | T2 → T3 → T7 per arm, each step starting from the previous result |
| transfer probes | 6 | two per arm, ten predictions each |
| discarded runs | 3 | toolchain flakes (`discarded-infrastructure`), all rerun and passed |

**Caveat added after the fact.** Mining the transcripts afterwards showed that
all 80 sessions spent turns on a runner bug: the compiler's local Zig cache is
anchored at its install location, which through the runner's symlink is the
repository — read-only inside the session's sandbox — so every native build
failed once on `ReadOnlyFileSystem` before being worked around. Median 45 such
lines per run, correlating +0.464 with cost overall and +0.262 within a task.
Pinning the local cache inside the working copy removed it, and the same cell
(`B/T2`) then cost 79,332 tokens against 108k–194k before. The arms were compared
under equal conditions, so this is a level shift rather than a bias between
designs, but it is *variance*, and variance is what the first clause of the
decision rule failed on. The result stands as measured; whether it survives a
low-noise instrument is open. See
[findings-2026-09-19-toolchain-noise](../../experiments/cascade/findings-2026-09-19-toolchain-noise.md).

Model and effort are read from every session log, not assumed:
`deepseek-v4-flash` at effort `max` throughout, delegation depth 0 in every
maintainer run, one frozen compiler (`4a9ad0c1…`) for every session. Cost is
input plus output plus reasoning tokens; the 276.5M cache-read tokens are reported
beside it and never added. The whole experiment — 72 maintainer sessions, two
designers and six probes — cost **11,905,691 tokens** on that measure (maintainer
runs 10,446,609, designers 673,534, probes 785,548), which is the number the plan
said would be recorded rather than estimated.

## Cost per task (as published: cost term v1)

Median cost over the three verified runs; `solved/scored` was 3/3 in every cell.
These are the numbers as first published. The token term they use was later found
to double-count reasoning tokens — see [Corrections](#corrections-after-review) —
and the corrected table is there. The published table is kept because it is what
the cohort manifest can reproduce byte for byte.

| task | B | P1 | P2 |
| --- | ---: | ---: | ---: |
| T1 exponents | 162,803 | 154,163 | 167,026 |
| T2 inches | 117,702 | 130,156 | 159,370 |
| T3 measure spelling | 188,531 | 174,094 | 205,991 |
| T4 printer width | 116,760 | 116,451 | 121,350 |
| T5 form bounds | 112,418 | 145,218 | 127,031 |
| T6 KiCad dialect | 153,563 | 131,908 | 150,809 |
| T7 error column | 101,345 | 129,948 | 104,628 |
| **pack gain over B** | — | **−28,816** | **−83,083** |
| **upfront (designer)** | 0 | 327,308 | 346,226 |
| **R = gain − upfront** | 0 | **−356,124** | **−429,309** |

Run-to-run spread, max minus min over the three runs:

| task | B | P1 | P2 |
| --- | ---: | ---: | ---: |
| T1 | 55,171 | 61,384 | 36,033 |
| T2 | 85,037 | 27,378 | 11,350 |
| T3 | 6,003 | 18,631 | 29,896 |
| T4 | 62,591 | 74,995 | 60,015 |
| T5 | 20,066 | 39,489 | 8,376 |
| T6 | 28,735 | 22,387 | 18,667 |
| T7 | 46,542 | 44,921 | 72,531 |

The largest single margin in the whole pack is T5's −32,800 against a spread of
39,489 on the same cell. The one comparison that looks clean in P1's favour is
T3 (+14,437 against an 18,631 spread) — and it is still inside it.

## Chained runs

One chain per arm, T2 → T3 → T7, each step starting from the previous result:

| arm | T2 | T3 | T7 | total |
| --- | ---: | ---: | ---: | ---: |
| B | 145,281 | 223,359 | 112,895 | 481,535 |
| P1 | 131,664 | 182,855 | 99,190 | **413,709** |
| P2 | 145,238 | 205,624 | 131,678 | 482,540 |

P1's chain is 67,826 tokens (14%) cheaper than the baseline's, and cheaper at
every one of the three steps — the direction the proposals predict. It is one
chain per arm, so it has no spread to compare against, and even the full 67,826
does not approach P1's 327,308 upfront cost. This is a lead worth following, not
a result.

## What the metric actually measured

Correlations with session cost, recomputed after the review on the corrected
token term (v2) and the 63 independent runs — overall, and inside each task
(Spearman on within-task ranks, which is the comparison that is not confounded by
one task simply being larger):

| signal | overall | within task |
| --- | ---: | ---: |
| tool calls / steps | +0.70 | +0.57 |
| tool results showing a failure | +0.70 | +0.55 |
| bytes returned by `read` | +0.63 | +0.31 |
| seconds in compiler calls | +0.57 | +0.30 |
| files changed | +0.55 | +0.08 |
| lines added + removed | +0.15 | −0.12 |
| blast radius of the change (pre-change graph) | +0.33 | −0.22 |

Cost tracks how much the session *did*, not how much the change *was*. The floor
makes that concrete: three P1/T7 runs changed nothing at all — the redesign
already carried the column — and still cost 149,690, 129,948 and 104,769 tokens
(v1; 121,977 / 109,179 / 85,354 corrected) to read the request, check the design
and report, with an empty diff in every case. (An earlier version of this
paragraph quoted three other numbers; they were the global minimum of the run set
and B/T7, not these records. See [Corrections](#corrections-after-review).)

The phase split recorded since the review says the same thing directly rather
than by inference: on B/T7 the session spent 49,755 tokens reading, 8,907
editing and 43,277 verifying; on P1's no-op T7, 66,722 / 1,453 / 53,802. The
median task costs about 115,000 tokens on the corrected term. Reading and
verification are real maintainability costs and stay in the total — but they are
the bulk of it, and a design can only remove the editing part.

That is the finding under the finding: at three runs per cell, with an
assessment floor of ~90k tokens and a spread of 20k–85k, the instrument cannot
resolve the effect it was built to measure. The pack is sound — every task is
solvable in one session, every cell verified, and the one task a design had
already solved (P1/T7) is visibly free of *work* while still costing a session —
but the *metric* is dominated by a term that has nothing to do with the design.

## Coupling

- T4 (presentation stays independent): every arm touched a test file as well as
  the printer — `tests/printer_test.my` on `B` and `P1`, plus
  `tests/style_test.my` on `P2`. The change never stayed inside the printer.
- T6 (legitimate divergence without flag proliferation): **zero** new boolean
  parameters in any arm. The pinned `Dialect` API and the maintainers' own
  choices both avoided flags; the control's generalisation did not need them
  either.

## Transfer probes

Two probes per arm, ten predictions each:

| arm | correct | bytes read |
| --- | ---: | ---: |
| B | 17/20 (8, 9) | 88,025 |
| P1 | 16/20 (8, 8) | 90,981 |
| P2 | 18/20 (8, 10) | **174,664** |

The misses are stable across arms and runs: `1.0mm` printed as `1mm`, and a
four-deep nesting that goes multi-line because the width estimate gives up past
depth three — both printer-owned facts, which is what the probe withholds. So the
probe measured the printer's privacy, not the design's centralisation. The score
is noise (one P2 run got all ten); what is not noise is the price of the
contract. The generalised control's contract cost twice as much to read as the
baseline's for the same predictive power, and P1's did not get cheaper either.

## What follows

Per the plan's §3.6, a negative result means no language feature is built on the
proposals' strength. Nothing in `velocity/LOOP-PROMPT.md` or the velocity loop's
lane A changes on this evidence. Concretely:

1. **The metric is the thing to fix first.** Total session tokens is mostly
   assessment. A metric closer to the proposals' claim would hold the assessment
   fixed: bytes read before the first edit, seconds from the request to the first
   edit, or the cost of the *edit* phase alone (the records already carry the
   first three; `tool_seconds` and `first_green_ms` are in every run record).
   *Tested:* the research note's own alternative — MacCormack-style propagation
   cost over a design structure matrix — was measured against this run set and
   also fails: it does not predict change cost (within a task the blast radius
   correlates −0.139 with it, while session steps correlate +0.515), and at the
   arm level it ranks the control design best on a margin no larger than the
   arbitrary choices in building the graph. See
   [elegance-metrics/findings-2026-09-19](../../experiments/elegance-metrics/findings-2026-09-19.md).
2. **Variance has to come down or runs go up.** At the observed spreads, ruling
   out the effect would need roughly an order of magnitude more runs per cell, or
   a prompt and turn cap that make two sessions of the same cell more alike.
3. **The pack is reusable as is.** All 63 cells are solvable, the hidden
   verification is independent (Zig goldens and hidden tests, never agreement
   between arms), and the one design that anticipated a task shows up exactly
   where it should. A revised metric can be run against the same pack.
4. **The cascade lead is the chained sequence.** If anything is followed up, it
   is P1's 14% chain advantage, with more chains per arm so it has a spread.

## Corrections after review

An independent review
([research-testing-review-2026-09-19](research-testing-review-2026-09-19.md))
reproduced several measurement defects in the instrument. All are repaired; the
verdict above is unchanged, and the corrected figures are below.

**Token accounting.** The provider maps
`inputTokens = prompt_tokens - cached_tokens` and `outputTokens = completion_tokens`,
and reports `reasoningTokens` as a *detail of* `completion_tokens`. Reasoning is
therefore already inside output, and `totalTokens == inputTokens + outputTokens +
cacheReadTokens` call for call (verified on 38 consecutive calls, 38/38). The
published term added reasoning to output a second time, inflating every cost by
the reasoning share — 19.7% on one `B/T2` run, 33% on P1's designer session,
27% on P2's. Three terms are now recorded and selectable: `v1` (as published,
reproducible), `v2` (input + output, default) and `total` (the provider's own
total, cache reads included).

Corrected medians (v2) and the corrected decision inputs:

| task | B | P1 | P2 |
| --- | ---: | ---: | ---: |
| T1 | 126,782 | 113,403 | 135,994 |
| T2 | 94,480 | 110,111 | 124,919 |
| T3 | 149,289 | 141,560 | 161,914 |
| T4 | 93,296 | 97,184 | 94,284 |
| T5 | 87,412 | 117,347 | 100,050 |
| T6 | 126,333 | 104,264 | 114,196 |
| T7 | 86,458 | 109,179 | 89,446 |
| **pack gain over B** | — | **−28,998** | **−56,753** |
| **upfront (designer)** | 0 | 219,362 | 254,244 |
| **R** | 0 | **−248,360** | **−310,997** |

Rule 1 still fails (0 wins, 0 losses beyond the spread), rule 2 still fails
(`R < 0`), rule 3 still holds, and the decision is still not justified.

**Separated green signals.** `first_green_ms` had recognised any passing test
run — including the baseline run the maintainer prompt requires first, which
understated time-to-solution. Session records now carry `baseline_green_ms`,
`first_green_ms` (the first green *after* the first edit), `edits`,
`check_events` with phase and outcome, and a phase split of both time and tokens:
read (session start to first edit), edit (first edit to first candidate green) and
verify (after). On B/T7 that split is 49,755 read / 8,907 edit / 43,277 verify
tokens; on P1's no-op T7 it is 66,722 / 1,453 / 53,802. The change itself is a
small fraction of every session, measured directly rather than inferred from one
no-op run.

**Frozen cohort.** `experiments/cascade/cohorts/original.json` names the 72
records of this experiment, the compiler hash, the runner, the prompt, the model
and effort, the environment policy and a digest of each record's *measurement
content*. The scorer defaults to that cohort, so a follow-up run (`B/T2/4`, the
cache-fixed run) is reported as outside it rather than mixed in. The published v1
totals reproduce exactly:

```sh
python3 experiments/cascade/score.py --cost-term v1
# pack gain -28816, R = -356124  (P1)   pack gain -83083, R = -429309  (P2)
```

**Chain identity.** Chained runs are keyed by repetition, step and attempt
(`chain-r1-s2-a1`), so repeating a chain can no longer overwrite the evidence it
is meant to replicate; the nine existing chain records were migrated to those
keys. Replaced records are preserved rather than lost.

**Pinned gates.** `arm_gate.py` now requires an exact guest-test count
(`--expect-tests 79` for B and P1, `127` for P2) and the full golden manifest, and
refuses to certify an unpinned gate. All three arms were re-gated under the pinned
gate and pass.

## Reproduce

```sh
python3 experiments/cascade/score.py --json experiments/cascade/score.json \
    --pairs experiments/cascade/pairs.jsonl
```

`score.json` holds every table above plus the per-run detail; `pairs.jsonl` is
the paired preference data the proposals describe — one row per (task, run) with
the baseline and treatment costs side by side. The raw run records are under
`experiments/cascade/runs/`, the designer evidence under
`experiments/cascade/designs/*/evidence/`, and the probe records under
`experiments/cascade/probes/`.
