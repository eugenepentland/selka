# E1 development pilots — readout

Date: 2026-09-21. Scope: the development half of E1. **These are harness pilots,
not a productivity comparison.** The solvers that ran are a scripted stand-in and
a no-op; the model-driven arm is blocked. Nothing here is pooled with, or
predictive of, a held-out cohort, and no arm is declared better.

## What ran

Four attempts, each a fresh workspace and a fresh object cache, all against the
same frozen compiler (`sha256 43c6ab3b1a80b53f…`, `compiler_sha256
149e9d6c39a15a11…`, `pack/tools/identity.json`):

| # | Task | Arm | Solver | Outcome |
| --- | --- | --- | --- | --- |
| 1 | dev-context-01 | focused-context | `script:` reference workflow | **accepted** |
| 2 | dev-maintenance-01 | plain | `script:` reference workflow | **accepted** |
| 3 | dev-maintenance-01 | plain | `noop` (changes nothing) | **rejected** |
| 4 | dev-maintenance-01 | plain | `dsh` (model) | **blocked** |

The scripted solver is `harness/solvers/reference_workflow.sh`: it runs
`mylang check`, optionally reads `mylang context`, applies the frozen intended
answer, and runs the program again. It is a stand-in for a session, not a model
session, and its observations say `"model_driven": false`.

## The numbers, as recorded

| Observation | 1 (context, focused-context) | 2 (maintenance, plain) | 3 (noop) |
| --- | --- | --- | --- |
| Acceptance | pass, 7/7 oracle lines | pass, 23/23 oracle lines | fail, 12 mismatched lines |
| Wall time to accepted completion | 3.34 s | 3.56 s | — (never accepted) |
| Solver wall | 1.77 s | 1.72 s | 0.00 s |
| Grading wall | 1.67 s | 1.68 s | 1.65 s |
| Compiler invocations | 3 (check, context, run) | 2 (check, run) | 0 |
| Failed invocations | 1 (`check`, `E_TYPED_HOLE`) | 0 | 0 |
| Phases (invocations / failed) | checking 1/1, reading context 1/0, compiling and running 1/0 | checking 1/0, compiling and running 1/0 | — |
| Tool-response bytes | 2252 stdout + 446 stderr | 70 + 0 | 0 + 0 |
| Sum of process time | 1.62 s | 1.58 s | 0.00 s |
| Cold build | 1.481 s, reuse 0.0 | 1.596 s, reuse 0.0 | — |
| Warm unchanged | 0.114 s, reuse 1.0 | 0.123 s, reuse 1.0 | — |
| Warm after one body edit | 0.231 s, reuse 0.5 | 0.225 s, reuse 0.833 | — |
| Unintended changes | none | none | none |
| Tokens | null (not reported) | null | null |

The sums of process time are *not* wall time: they are the sum over compiler
processes, and a solver that ran two commands at once would make them exceed its
wall clock. Both runs were serial.

## What the pilots show

* **The harness runs end to end.** One command prepares the workspace, runs the
  solver with the counting shim on its PATH, grades with the task's own
  acceptance checker, and writes one observation document. The raw event log is
  kept beside it.
* **The acceptance checks discriminate.** `pilot.py selftest` grades every task
  twice with the frozen compiler: the frozen source is rejected, the intended
  answer is accepted. Pilot 3 is the same fact through the full pipeline — a
  solver that changes nothing is rejected with 12 mismatched lines.
* **The observations have the shape the plan asks for.** Independent behavioural
  acceptance, unintended changes, wall time to accepted completion with the
  unsuccessful attempts separated, tool-response bytes, failed invocations,
  phase timings, and cold/warm/reuse counters are all in
  `evidence/runs/*.json`; the readout above is a projection of those documents.
* **The treatment arm's tool works on a red project, and is measured.** In pilot
  1, `mylang context main.my --symbol=ranking::rank_in_place --format=json`
  answered `status: "partial"`, `analysis.status: "declaration-only"`
  (`bodies did not check; declarations and diagnostics only`) while the typed
  hole was unfilled — 2240 bytes of `agent-context-v1` on stdout, exit 0. The
  shim recorded it as a *successful* invocation that echoed the project's
  `E_TYPED_HOLE`; classifying that echo as a failure would have overstated the
  failed-invocation count, which is why `events.classify` reads the process
  status first.

## What did not run, and exactly why

**The model-driven arm is blocked, not skipped.** `dsh --profile headless` needs
`DEEPSEEK_API_KEY` in the launching environment. It is not set here, and the
harness deliberately does not read `~/.dsh/.credentials.yaml`, because copying or
using the user's credential store is not something a measurement harness should
decide on its own. The verbatim attempt is
[`dsh-blocked-2026-09-21.txt`](dsh-blocked-2026-09-21.txt):

```
$ DSH_HOME=… dsh --profile headless "Reply with exactly the single word: PING"
dsh: MISSING_CREDENTIAL: llm-deepseek: no API key for provider route "deepseek-official";
store DEEPSEEK_API_KEY through the credentials service (the web Models page writes it),
or export DEEPSEEK_API_KEY in the launching environment
```

Pilot 4 records the same blocker through the harness (`status: "blocked"`,
`blocked_reason` naming the missing variable, exit 3). `DSH_HOME` must also point
inside the workspace: the default `~/.dsh` is read-only to this sandbox and
`dsh` fails to compose its profile there. The harness already does that, and it
records `profile_identity` — the sha256 of `dsh --profile headless --dump-config`
— which was identical across all four runs (`40ff1723bb5b03ef…`), so the frozen
profile is at least pinned and comparable.

To run a model pilot, one command is enough once the variable is exported:

```bash
cd experiments/agent-usefulness-e1
export DEEPSEEK_API_KEY=…
python3 harness/pilot.py run --task dev-maintenance-01 --arm plain
```

## Consequences for the preregistration

The development pilots were not sized to estimate variance, and they cannot:
with two accepted scripted runs and one blocked arm there is no headroom
measurement, no discordant pair, and no human-or-model variance at all. The
preregistration therefore still holds an **unset** held-out sample size, to be
registered in a commit that touches nothing else before the first held-out run —
as [`preregistration.json`](../preregistration.json) says. Nothing in this
readout may be quoted as evidence that either arm is faster or more correct.

## Incidental findings worth keeping

* `mylang build … --report` writes the `qbe-build-v1` JSON report to **stdout**,
  although `mylang check --help` says stderr. The harness scans both and records
  which stream carried it (`report_stream`).
* `mylang context` answers `partial` while a project carries a typed hole; a
  workflow that needs the callee's body must fill the hole first.
* The build `--report` numbers used for the warm/reuse counters are
  `compiled_functions`, `reused_functions`, `frontend_seconds`, `codegen_seconds`,
  `link_seconds`; `reuse_fraction` is derived here, not reported by the compiler.
