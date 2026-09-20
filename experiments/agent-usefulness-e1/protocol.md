# E1 development protocol (frozen)

Generated from `protocol.json` (e1-protocol-v1, frozen 2026-09-21) by `pilot.py protocol-md`. Edit the JSON, never this file; the harness hashes both and every observation records the hashes.

**Scope.** Development pilots only. Held-out cohorts are not run, no productivity claim is drawn from a development pilot, and a development pilot never changes the frozen pack.

## Compiler and identity

* `identity_file`: pack/tools/identity.json
* `frozen_binary`: pack/tools/bin/mylang
* `fallback_binary`: zig-out/bin/mylang
* `rule`: every arm runs the same frozen compiler; the harness refuses a run whose binary sha256 differs from identity_file, and materialize is the only step that writes the identity file
* `qbe`: pack/tools/bin/qbe (beside the compiler, which is where mylang looks first)

## Model and profile

* `route`: deepseek-official
* `profile`: headless
* `temperature`: None
* `settings_source`: the frozen dsh profile; each run records profile_identity, the sha256 of `dsh --profile headless --dump-config` with DSH_HOME inside the run work directory
* `credential_env`: DEEPSEEK_API_KEY
* `note`: temperature and sampling are whatever the frozen profile carries; they are not overridden per arm, and a run whose profile_identity differs from another run's is reported

## Prompts

Template:

```text
You are working in the project in your current working directory. The compiler `mylang` is on your PATH.

The language documentation is readable at `docs/` and `README.md` in your working directory (read-only symlinks into the repository).

{brief}

{arm_note}

Work only inside your working directory. When you are finished, leave the project in the state you want graded.
```

### Arm `plain`

Use the compiler as you normally would: `mylang check` reports problems and `mylang run` executes the program.

### Arm `focused-context`

Before editing, read the declaration you are changing with `mylang context {entry} --symbol={context_symbol} --format=json`; when a body is an unfinished typed hole, `mylang check {entry} --diagnostics=json` attaches the `typed-hole-obligation` record (bindings, declared type, effect ceiling and `mutates(...)` footprint) to the `E_TYPED_HOLE` diagnostic.

## Tools

Visible:

* mylang on PATH (the counting shim in front of the frozen compiler)
* docs/ and README.md, read-only symlinks into the repository
* the task workspace and everything in it

Never visible:

* src/
* velocity/
* experiments/ (including this pack, its answers and its acceptance checks)
* scripts/
* the hidden probe, the Python oracle and the intended answer of any task

## Cache policy

* `root`: work/<run_id>/cache, created fresh for each run
* `injection`: the shim adds --cache-dir for run, run-project, build and test when the solver did not name one; an event records the effective cache dir
* `acceptance`: the acceptance checker compiles under its own cache outside the candidate tree
* `probes`: cold (fresh cache), warm-unchanged (same cache) and warm-after-edit (one body line changed, same cache) are measured after grading on a copy of the accepted tree

## Budgets

* `wall_seconds_per_task`: 900
* `turn_cap`: 30
* `turn_cap_enforced`: False
* `turn_cap_note`: goal.json fixes the 30-turn cap; `dsh --profile headless` exposes no turn flag, so the enforced budget is the wall-clock ceiling and the observation records the cap as unenforced
* `token_budget`: None
* `token_budget_note`: no token ceiling is enforced and no token estimate is invented; the observation records null unless the solver itself reports usage
* `acceptance_seconds`: 120

## Grading

* `acceptance`: one hidden probe per task is copied into the candidate tree, run once with the frozen compiler, and every printed line is compared with the task's Python oracle; the probe is removed afterwards
* `independent`: the oracle is a second implementation of the task's rule in Python; the checker never runs the workflow the task is about and never reads the candidate's diff
* `unintended_changes`: the checker inventories the candidate tree against the frozen source snapshot and the harness records edits outside the task's allowed paths, additions and removals
* `rubric`:
  * accepted: exit status 0 from the hidden probe and every expected line matched, within the wall budget
  * rejected: the probe failed to build, trapped, exited non-zero, printed a mismatched line or printed trailing lines
  * a run that never started a solver (missing credential, missing tool) is blocked, not rejected, and is reported separately

## Invariants

* one attempt per task per arm; a retry is a new run id, never an overwrite
* the pack, the protocol, the preregistration and the compiler identity are hashed before and after every run; drift invalidates the run
* failed compiler and test invocations, tool-response bytes and phase timings come from the shim's events, not from the transcript
* a development pilot reports observations only; it makes no productivity claim

## Solver templates

```json
{
 "dsh": [
  "dsh",
  "--profile",
  "headless",
  "{prompt}"
 ],
 "script": [
  "sh",
  "{script}"
 ],
 "reference": "builtin: copy answer/files over the workspace, no compiler call",
 "noop": "builtin: change nothing"
}
```
