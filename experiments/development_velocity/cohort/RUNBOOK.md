# Running a matched files/store cohort with a different participant model

This runbook reproduces `application-trials/declaration-store-dev-20260908`
(cohort `development-001`) so results from another coordinating agent or
participant model can be compared. Everything here is coordinator-side. The
protocol is unchanged from the plan in `docs/experiments/declaration-store.md`
section 4; only the study name, the model identity and the operator differ.

Immutable inputs: the twelve corpus tasks, the two arms `my-files` and
`my-store`, one pair, the practice packs, the participant prompt templates
`PROMPT-FILES.md` and `PROMPT-STORE.md`, and the handoff texts in
`coordinate.py`. Do not edit any of them for a comparison run; a changed input
is a new variant, not a comparable cohort.

## 0. Prerequisites

- Repository checkout at the commit recorded in the reference study's
  `readiness.json` (`binaries` and `registration.json` `harness` hashes must
  match; `runner.registered` refuses a cohort whose harness files changed).
- Build **ReleaseFast** binaries and install them; Debug binaries inflate every
  check and probe by roughly 100x and invalidate timing comparisons:

  ```sh
  cd /home/epentland/ai/canopy/mylang
  /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig build -Doptimize=ReleaseFast
  export TMPDIR=/home/epentland/ai/canopy/mylang-scratch/tmp   # disk-backed; /tmp fills
  python3 -B tests/store_server.py --compiler zig-out/bin/mylang --runner zig-out/bin/mylang-io
  python3 -B tests/store_roundtrip.py --compiler zig-out/bin/mylang
  ```

- Do not run `zig build` (Debug) again while a cohort is active; it reinstalls
  Debug binaries into `zig-out/bin`.
- The coordinating agent must be able to launch **fresh participant contexts**
  that have shell access but share nothing with the coordinator: no prior
  conversation, no coordinator files, no other participants' work. One
  participant per attempt, never reused. If the platform cannot resume a
  participant context after practice, the single-context protocol below still
  works because the participant waits inside the bridge with `await-handoff`.

## 1. Create the study

```python
import sys; sys.path.insert(0, '/home/epentland/ai/canopy/mylang')
from pathlib import Path
from experiments.application_comparison import iteration_log
from experiments.application_comparison.storage import path_identity, write_json
from experiments.development_velocity import runner
STUDY = Path('/home/epentland/ai/canopy/application-trials/declaration-store-<operator>-<date>')
ref = Path('/home/epentland/ai/canopy/application-trials/declaration-store-dev-20260908')
iteration_log.create(STUDY, {
  'study': 'declaration store versus files interface, same language', 'phase': 'development', 'look': 0,
  'arms': {'comparator': 'my-files', 'candidate': 'my-store'},
  'protocol': 'single context per attempt via await-handoff; twelve tasks, one pair, both arms, randomized dispatch within pair',
  'model_identity': None, 'model': '<participant model and agent runtime, e.g. astra ...>', 'tokens': None,
  'predecessor': {'kind': 'file', **{k: v for k, v in path_identity(ref / 'events.jsonl').items() if k in ('path', 'sha256')}},
  'speed_margin': 1.0, 'started_utc': runner.utc()})
```

Readiness reuses the reference study's proofs plus the current binaries:

```python
import json
old = json.load(open(ref / 'readiness.json'))
proofs = [path_identity(p['path']) for p in old['proofs']]
write_json(STUDY / 'readiness.json', {
  'runtime_verified': True, 'library_verified': True, 'starters_verified': True, 'cases_reviewed': True,
  'tasks': list(runner.catalog.IDS), 'proofs': proofs, 'status': 'ready-for-freeze',
  'note': 'ReleaseFast binaries; comparison run of the reference protocol with a different participant model',
  'binaries': {n: path_identity('/home/epentland/ai/canopy/mylang/zig-out/bin/' + n)['sha256'] for n in ('mylang', 'mylang-io')},
  'prepared_at': runner.utc()})
arms = [{'label': 'my-files', 'language': 'my', 'interface': 'files'},
        {'label': 'my-store', 'language': 'my', 'interface': 'store'}]
frozen = runner.freeze(STUDY, 'development-001', STUDY / 'readiness.json', pairs=1, arms=arms)
```

`freeze` writes the registration, copies the tools, renders canonical
baselines and produces the randomized `dispatch_order` (24 entries). Record the
registration hash in the journal with `iteration_log.append`.

## 2. Run the 24 attempts, strictly one at a time, in dispatch order

`C="python3 -B /home/epentland/ai/canopy/mylang/experiments/development_velocity/cohort/coordinate.py --study $STUDY --cohort development-001 --prefix <op>"`

For `N` in 1..24:

1. `$C prepare N` prints `agent_name` and `initial_message`. It creates the
   attempt, imports the store for a store arm, and writes the public prompt
   under `$STUDY/public-prompts/`.
2. Start the watcher in the background: `$C watch N`. It waits for
   `practice-ready.json`, then binds the context and calls `begin` with the
   arm's handoff text, which starts the clock. It exits on its own.
3. Launch a **fresh** participant agent whose entire first message is exactly
   the `initial_message` from step 1. Nothing else. The participant completes
   practice, calls `await-handoff` until it returns `working`, completes the
   task, and seals with `finish`.
4. When the participant reports, `$C status N` must show `phase: sealed`.
   Then `$C grade N` runs private grading. Only then start `N+1`.

Rules the runner enforces and the coordinator must respect: never prepare or
grade while an attempt is `working`; never restart or re-prompt a participant
(an unfinished attempt is sealed by the budget or abandoned, and stays in the
denominator); never read a participant's transcript into the coordinator's
decisions; never edit timings, sessions or gateway records. Record anything
unusual as an `iteration_log.append` event before continuing.

## 3. Timing-blind source reviews

After all 24 are graded, for each task:

1. `$C packet TASK` copies both sealed sources to
   `$STUDY/review-packets/TASK/<arm>/` and writes `request.json`.
2. Launch a fresh reviewer agent with only `request.json`'s path. It reads each
   source directory's `.trial-public/QUALITY.md` and `TASK.md`, reviews without
   any timing or grading information, and writes `review.json` at the
   `output` path as a list with one entry per arm:

   ```json
   [{"version": "development-source-review-v1", "arm": "my-files",
     "source_sha256": "<from request.json>", "decision": "approve",
     "findings": [{"severity": "nit", "location": "app.my app::run", "evidence": "...", "impact": "..."}]}]
   ```

   `decision` is `approve`, `approve_with_nits` or `reject` per `QUALITY.md`.
3. `$C ingest TASK` validates the hashes and writes each attempt's
   `source-review.json`.

## 4. Report

```sh
cd /home/epentland/ai/canopy/mylang
python3 -B -m experiments.development_velocity.report $STUDY/development-001 --inventory
python3 -B -m experiments.development_velocity.report $STUDY/development-001 --output $STUDY/reports/development-001
```

The report directory holds `analysis-input.json`, `summary.json` and
`report.md` with the capped-cost ratio candidate over comparator, the
bootstrap upper bound, completion rates, per-family results and the store
metrics. Compare against the reference study's report on the same paths.
Publish to a new directory; never overwrite.

## Comparing with the reference cohort

Both cohorts share tasks, arms, packs, budgets, clocks and analysis. What
differs is the participant model and the operator. Report the two ratios side
by side with their upper bounds; do not pool attempts across cohorts, and do
not compute a cross-cohort ratio as if it were matched.
