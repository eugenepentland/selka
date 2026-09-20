# E1 — evaluate complete work (development half)

E1 is the package that evaluates *complete work*: a solver session receives a
task, changes a real project, and is graded on the project's behaviour rather
than on its diff. This directory is the development half: a frozen task pack, a
frozen protocol and preregistration, a pilot harness, and the readout of the
pilots actually run. **No held-out cohort has been run and no productivity claim
is drawn here.**

Status, 2026-09-21:

* The pack carries **two development tasks** — one maintenance task
  (`dev-maintenance-01`) and one incomplete-implementation task
  (`dev-context-01`) — with briefs, frozen source snapshots, intended answers
  held separately, and independent behavioural acceptance checks.
* The harness runs a task in one command and records the observations the plan
  requires. `pilot.py selftest` shows the acceptance checks discriminate: both
  reject the frozen source and accept the intended answer.
* Development pilots ran end to end with a scripted (non-model) solver and a
  no-op solver. The model-driven arm is **blocked**: `dsh --profile headless`
  needs `DEEPSEEK_API_KEY` in the launching environment, and the harness will not
  read the user's credential store. The blocker and its verbatim output are in
  [`evidence/dsh-blocked-2026-09-21.txt`](evidence/dsh-blocked-2026-09-21.txt);
  the readout is [`evidence/dev-pilots.md`](evidence/dev-pilots.md).

## Layout

```
protocol.json           frozen protocol (prompts, arms, tools, cache policy, budgets, rubric)
protocol.md             rendered from protocol.json by `pilot.py protocol-md`
preregistration.json    sample size, decision thresholds, what counts as inconclusive
pack/tasks/<task>/      brief.md, source/, answer/ (held), acceptance/ (held)
pack/tools/identity.json  the frozen compiler identity (bin/ is materialized, gitignored)
pack/manifest.json      one hash per frozen document, tasks included
harness/pilot.py        prepare, run, grade, record — one command per attempt
harness/events.py       the compiler-invocation-v1 event schema and aggregation
harness/shim.py         the counting shim in front of the frozen compiler
harness/solvers/        a scripted stand-in solver (not a model)
evidence/runs/*.json    one observation per attempt
```

## Commands

```bash
cd experiments/agent-usefulness-e1
python3 harness/pilot.py materialize     # freeze zig-out/bin/{mylang,qbe,mylang-io}
python3 harness/pilot.py freeze          # write pack/manifest.json
python3 harness/pilot.py verify          # refuse pack, harness or tool drift
python3 harness/pilot.py selftest        # source rejected, answer accepted
python3 harness/pilot.py list            # the frozen tasks and arms

# one development attempt (defaults to the protocol's `dsh` solver)
python3 harness/pilot.py run --task dev-maintenance-01 --arm plain
python3 harness/pilot.py run --task dev-context-01 --arm focused-context \
    --solver script:$PWD/harness/solvers/reference_workflow.sh
python3 harness/pilot.py run --task dev-maintenance-01 --arm plain --solver noop
```

Exit status: `0` accepted, `1` rejected, `2` setup error, `3` blocked (the solver
could not start). A retry is a new run id; an observation is never overwritten.

## The two arms

Both arms receive the same brief, source, compiler, cache policy, tools and
budget. The only difference is the note appended to the prompt:

| arm | what the note adds |
| --- | --- |
| `plain` | use `mylang check` and `mylang run` as usual |
| `focused-context` | read the declaration first with `mylang context … --symbol=… --format=json`, and read the `typed-hole-obligation` record attached to `E_TYPED_HOLE` when a body is unfinished |

The prompt is composed from `protocol.json`; it contains no absolute path, so
two runs of the same task and arm have the same prompt hash and differ from each
other in nothing but the run's own directory (which the observation records
separately).

## What a run records

`evidence/runs/<run_id>.json` (`e1-observation-v1`) carries: the task and arm
identities, the exact prompt and its hash, the protocol / preregistration /
manifest / tool-identity / compiler / docs hashes, the solver's own command and
outcome, the harness timings, the grading verdict from the task's acceptance
checker (per-line mismatches included), the unintended-change inventory, the
compiler-invocation events aggregated by phase with failed counts and
tool-response bytes, the cold / warm-unchanged / warm-after-edit build probes
with reuse counters, the token fields (null — the solver command does not report
usage and no estimate is invented), and the budgets.

The measurement is the shim's events, not the transcript: every compiler process
on the solver's PATH is recorded once, before and after the source inventory, so
a wrapper cannot make the work look smaller.
