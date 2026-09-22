# The cascading-benefit experiment

Does a design that states each domain fact once make later changes cheaper, and
does it pay for itself within a handful of changes? This directory is the
instrument for answering that on a real subsystem: the EDA S-expression reader
already ported to mylang under [`experiments/sexpr-port`](../sexpr-port).

The plan, including the arms, the held-out change pack and the decision rule
fixed before any run, is
[`docs/audits/cascade-experiment-plan-2026-09-19.md`](../../docs/audits/cascade-experiment-plan-2026-09-19.md).
This README says what has been built and how to run it.

## Shape

| path | what it is |
| --- | --- |
| `designs/B/` | the frozen baseline: the port as it stands, with its `DESIGN.md` inventory of the facts it states more than once |
| `designs/P1/` | the representation redesign, designed and frozen: `BRIEF.md` is the designer's input, `DESIGN.md` its account, `evidence/` the gate and the designer session's usage |
| `designs/P2/` | the generalised-reuse control, same arrangement |
| `pack/T1…T7/` | the seven hidden future changes: `request.md` is what a maintainer is given, `verify.json` is the manifest the runner executes |
| `pack/evidence/summary.json` | whether each task fails on `B` and passes on the author's reference solution (raw reports outside the repository) |
| `pack/reference/` | how to reach the reference patches against `B` (authoring evidence, kept outside the repository, never given to any agent) |
| `pack/MANIFEST.sha256` | hashes of the hidden copies under `../mylang-eval/cascade/` |
| `arm_gate.py` | the gate a frozen design must pass: 79 guest tests, 17 Zig goldens, the differential census |
| `run.py` | one maintainer session: working copy, `dsh --profile headless`, verification, session-log usage, diff, run record |
| `design.py` | one designer session: brief in, gated arm out |
| `score.py` | the per-task table, spreads, `R(P)`, the T4/T6 coupling columns and the decision rule; scores a frozen cohort by default (`--cohort`, `--all-runs`) on a selectable token term (`--cost-term v1|v2|total`) |
| `cohorts/original.json` | the frozen cohort: which records belong to the published experiment, with the compiler, runner, prompt, model, environment policy and a content digest per record |
| `maintainer_prompt.md` | the prompt every maintainer session gets |
| `runs/` | run records, three per arm per task, plus one chained run per arm |
| `work/` | the working copies the sessions ran in (kept as evidence, with the compiler caches and the `docs/` copy pruned; not committed) |

The hidden half of the pack — the guest tests, goldens and input fixtures — lives
outside the repository at `../mylang-eval/cascade/<task>/`, with only
`pack/MANIFEST.sha256` checked in, exactly the arrangement
[`docs/velocity-loop.md`](../../docs/velocity-loop.md) uses for its held-out
tasks.

## The change pack

| task | change | probes | source |
| --- | --- | --- | --- |
| T1 | scientific-notation literals on a dotted mantissa parse, print and round-trip | one fix, shared benefit | EDA `a332ed2b` |
| T2 | `in` joins `mm`/`mil` as a dimension unit, normalised to millimetres | policy has a coherent home | EDA `4a124f24` |
| T3 | a measure keeps the spelling it was written with (`10mil` prints `10mil`) | representation extension | EDA `65349595` |
| T4 | printer only: short lists 72 → 80 columns, one trailing newline | presentation stays independent | the proposals' control |
| T5 | a byte-range consumer for the form at an offset, without a second scanner | a span on every node cascades to a new reaction | EDA `0420dc5d` |
| T6 | a KiCad dialect with no `;` comments, both dialects in one program | legitimate divergence without flag proliferation | EDA `paren_span.Comments` |
| T7 | `LexError` carries the column the cursor was on, and the parser uses it | one source of truth for positions | EDA `21c79169` |

Every task is verified by hidden guest tests and, for T1 to T4, byte-exact
goldens. Each task's `verify.json` also re-runs the port's own suite where the
change does not legitimately invalidate a visible expectation (T3 and T4 do, and
their requests say so).

## Running it

One maintainer session end to end:

```sh
python3 experiments/cascade/run.py --arm B --task T1 --n 1
```

The pack's own soundness check — every task must fail on the baseline and pass on
the author's reference:

```sh
python3 experiments/cascade/arm_gate.py experiments/cascade/designs/B
for t in T1 T2 T3 T4 T5 T6 T7; do
  python3 experiments/cascade/run.py --arm B --task "$t" --n 0 --verify-only
done
```

A designer session, once its brief is frozen:

```sh
python3 experiments/cascade/design.py --arm P1
```

The full sweep the plan budgets — three independent runs per arm per task, then
one chained run per arm — four sessions at a time:

```sh
cd experiments/cascade
for arm in B P1 P2; do for task in T1 T2 T3 T4 T5 T6 T7; do for n in 1 2 3; do
  echo "$arm $task $n"
done; done; done | xargs -P 4 -n 3 sh -c 'cd /home/epentland/ai/canopy/mylang && python3 experiments/cascade/run.py --arm "$0" --task "$1" --n "$2"'
for arm in B P1 P2; do
  python3 run.py --arm "$arm" --chain T2,T3,T7 --n 1
done
```

Scoring, after the runs:

```sh
python3 experiments/cascade/score.py
```

## What has been verified so far

- `designs/B` passes the gate: 79 guest tests, 17/17 Zig goldens, the census
  agreeing with the independent Python reader on all six fixtures including the
  two ~185 kB EDA boards (`designs/B/evidence/gate.json`).
- Each of the seven tasks fails on `B` and passes on its reference solution
  (`pack/evidence/summary.json`). The reference patches are the smallest change
  that satisfies each request; they exist to prove the task is solvable and to
  generate the goldens — not as a model answer for the maintainers, who never see
  them.
- Every task also fails on `P1` and `P2` *before* any maintainer session, with one
  exception worth stating: `P1` already passes T7, because the representation
  redesign removed the parser's duplicated position walk, which is exactly what
  T7 asks a maintainer to do. That is the cascade the experiment is looking for,
  and it is recorded rather than hidden.
- Both designs are frozen and pass the gate. P1 (representation) centralises the
  suffix table, moves number decoding into the lexer and drops the parser's
  second position walk; it keeps all 79 tests unchanged and its designer session
  cost 327,308 tokens over 1,204 s (`designs/P1/evidence/designer.json`). P2
  (generalisation) turns the dialect, the character classes, the number policy
  and the print style into values and callbacks, keeps the 79 tests and adds 48
  of its own; its session cost 346,226 tokens over 1,242 s. A design that adds
  tests to its own arm is still gated by the original 79 plus the 17 goldens,
  which is what the gate report records.
- Run against the pack unmodified, P1 already satisfies T7: that redesign
  removed the parser's second position derivation, which is exactly what T7 asks
  for. T1–T6 still fail on P1, so they remain real changes; the same check on P2
  is in `pack/evidence/`.
- One real maintainer session has run end to end (`runs/B/T7/1.json`): the
  baseline arm, task T7. It passed the hidden verification, took 355 s wall, 45
  steps and 117,006 tokens of input + output + reasoning (2,780,160 cache-read
  tokens reported beside it), on `deepseek-v4-flash` at effort `max`, with
  delegation depth 0. The change touched five files: `sexpr/tokenizer.my`,
  `sexpr/parser.my`, two test files and the arm's README.
- That run also recorded the first friction observation: inside the headless
  session's workspace-write sandbox the compiler wants a cache directory outside
  the working copy, so the agent had to point `ZIG_GLOBAL_CACHE_DIR` and
  `--cache-dir` at the copy before its tests would build. Later sessions inherit
  the same environment, so the runner is the place to fix it if the friction
  turns out to cost turns.

## What one run records

`runs/<arm>/<task>/<n>.json` carries, from the harness session log keyed by the
working copy's path: the model and reasoning effort seen on every call, input,
output, reasoning and cache-read tokens, turns and steps, tool calls with the
seconds each tool held the session (so compiler and test waits are separate from
editing), bytes returned by `read` calls, tool results that showed a failure
before the first green, the delegation depth, the diff against the frozen arm
(files, added and removed lines, new boolean parameters), the classified
interface change from `mylang api-diff` with the declarations added and removed
against the frozen arm, and the verification manifest's per-step verdict. A run is discarded rather than scored when it shows
delegation (`discarded-delegation`), when no log with usage exists for its
working copy (`discarded-no-log`), or when its verification died in the toolchain
(`discarded-infrastructure`, from a `host failure` / `NativeToolFailed` marker in
the command output — that says nothing about the change, so the cell is rerun).
Two cells were discarded that way and both passed on the rerun; the discarded
records are kept beside their replacements as `<n>.discarded-infrastructure.json`.

## Measurement repairs

An independent review
([research-testing-review-2026-09-19](../../docs/audits/research-testing-review-2026-09-19.md))
reproduced a set of instrument defects; all are repaired and each has a
regression where one is testable:

| defect | repair |
| --- | --- |
| The scorer mixed a cache-fixed follow-up run into the published cohort | `cohorts/original.json` freezes the 72 records with a content digest; the scorer defaults to it and reports anything outside. `--cost-term v1` reproduces the published totals exactly |
| Chains were keyed by step only, so repeating one overwrote its evidence | Chains are keyed by repetition, step and attempt (`chain-r1-s2-a1`); replaced records are preserved |
| The published cost term added reasoning to output, which the provider already includes there | v1 kept for reproduction, `v2` (input + output) is the default, `total` includes cache reads; raw fields are retained |
| `first_green_ms` counted the baseline run the prompt requires | Records now separate `baseline_green_ms` from the first green after the first edit, and split time and tokens into read / edit / verify phases |
| The gate accepted any positive test count | `arm_gate.py --expect-tests N` is required to certify (79 for B and P1, 127 for P2); all three arms were re-gated |
| Propagation: stale index cache, one ablation identical to another, deleted modules invisible, self-counting diagonal, pooled ranks across unequal tasks | All five repaired with a `--selftest` (12 checks) in `experiments/elegance-metrics/propagation.py` |

## Reading the numbers

Two things to keep in mind when the results are read, both recorded here before
the sweep finishes:

- A task's verification re-runs the arm's own suite. P2 added 48 tests of its
  own, so a change there must clear 127 tests rather than 79. That is a property
  of the design — a design that pins more behaviour carries more obligations —
  but it is a property of the *arm*, not of the change request, and the scoring
  report says so.
- A task that a design already satisfies still costs a session: the maintainer
  has to read the request and check the design. P1's T7 run is the evidence
  (empty diff, 149,690 tokens). The metric measures verified change cost, so an
  anticipated change is cheap but not free.

The optional gateway isolation from the plan (`experiments/maintenance_trial/`)
is not used: the plan says to consider it once the unisolated runs show the pack
is sound, and the runs so far are sound — every task is solvable by a maintainer
in one session and every arm's runs verify.

## Outcome

The experiment is complete: 63 independent maintainer runs (3 per arm per task,
all verified), 9 chained runs (T2 → T3 → T7 per arm), 3 transfer probes, 2
designer sessions. **The redesigns did not pay.** Neither beat the baseline by
more than the run-to-run spread on any task, the pack gains are negative
(`P1` −28,816, `P2` −83,083 tokens), and neither recovered its designer's upfront
cost (`R(P1) = −356,124`). The decision rule fails on its first two clauses and
holds on its third. The full write-up, including what the metric actually
measured and what to change before any conclusion, is
[`docs/audits/cascade-experiment-results-2026-09-19.md`](../../docs/audits/cascade-experiment-results-2026-09-19.md).

## Progress

Plan revised 19 September 2026; instrument built, both designer sessions run and
the maintainer sweep finished the same day.

- Designs: `B`, `P1`, `P2` frozen, each with its gate report and, for the two
  redesigns, the designer session's usage.
- Runs: every cell has its three verified runs; `score.py` reports `passed/runs`
  per cell and three runs were discarded as toolchain flakes and rerun.
- The first two-run comparison already shows what the plan warned about: on T1
  the within-arm spread (55k on `B`, 61k on `P1`) is larger than the difference
  between arms, and on T2 `B`'s spread (85k) dwarfs its margin. Rule 1 compares
  the margin against exactly that spread, so the pack will say "within spread"
  rather than inventing a winner.
- The transfer probes ran twice per arm. The scores are noise (`B` 17/20, `P1`
  16/20, `P2` 18/20) and the misses are stable: `1.0mm` printed as `1mm`, and a
  four-deep nesting that prints multi-line because the printer's width estimate
  gives up past depth three — both printer-owned facts, which is what the probe
  withholds. What differs is the price of the contract: 88,025 bytes read for
  `B`, 90,981 for `P1`, 174,664 for `P2` (`probes/*/*.json`).
- `P1` already satisfied T7, and its maintainer run says what that is worth: the
  session changed nothing at all (empty diff, no interface change) and still cost
  149,690 tokens against `B`'s 120,892, because the request still has to be read
  and the design checked. Anticipating a change saves the change, not the
  assessment.
- The coupling columns are counted per changed file and after the compiler's own
  cache is pruned, so they measure the change rather than the toolchain's
  droppings. No maintainer run so far has added a boolean parameter, and on T4
  both arms edited `tests/printer_test.my` as well as the printer.

No claim in the plan has been tested: one run per cell gives no spread, and the
decision rule compares a margin against the spread.
