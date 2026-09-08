# Declaration store harness arm

How the [declaration store](declaration-store.md) experiment's `my-store` arm is
wired into the development-velocity harness: what the arm does, what it records,
what it does not claim, and how to exercise it without a model. The session
protocol itself is in [declaration store session](declaration-store-session.md).

## The arm

A cohort registers two arms, each with a label, a language and an interface:

```sh
python3 -B -m experiments.development_velocity.runner freeze /external/study \
  --cohort development-002 --readiness /external/study/readiness.json \
  --arms '[{"label":"my-files","language":"my","interface":"files"},
           {"label":"my-store","language":"my","interface":"store"}]'
```

`freeze` refuses a store arm unless `scripts/store.py` and
`scripts/store_server.py` exist, copies both into the frozen toolchain with the
rest of the workflow scripts, and records their identities under
`configuration.store_tools`. Every later `registered()` call re-verifies them.

Baselines are frozen per arm label at `<task>/<label>-baseline`, so each arm
carries its own `WORKFLOW.md`: `PARTICIPANT.md` for a files arm and
`PARTICIPANT-STORE.md` for a store arm. Arm labels default to the language names,
so a legacy `my`/`python` cohort keeps its `my-baseline` and `python-baseline`
directories and its identities unchanged. When any arm uses the store, every `.my`
baseline is replaced by its own store rendering before the public pack is added,
so both `.my` arms receive byte-identical, formatter-canonical source and the
protected-file receipts of a rendered submission match the baseline exactly.

`prepare` imports the arm's baseline into `attempt/store.sqlite` as branch `base`
and branches `work` from it, and imports the onboarding starter into
`attempt/practice-store.sqlite` the same way. `begin` starts the task clock as
usual and then removes every `.my` file from `attempt/work`: the store is the only
source channel, and `attempt/work` is coordinator staging that the participant has
no verb to read. The practice store protects nothing, because practice has no
protected files in either arm; the task store protects the `main` and `io`
modules, matching the files arm's protected `main.my` and `io.my`.

Onboarding in a store arm exercises every operation shape before the clock. Its
guide asks for one `add` and one `remove` — add a small helper declaration,
confirm it with `open`, remove it, confirm again — besides the three repairs,
which are `replace` operations. `participant` refuses practice `finish` with
reason `completed` until the onboarding session's own records show a committed
`add` and a committed `remove`, and `practice-ready.json` records the committed
kinds as `batch_operations`. The three repairs, the 21 public cases and the
practice contract are unchanged; the files arm is unaffected.

`participant` selects the gateway by the arm's interface. A store arm accepts
`open`, `context`, `search`, `asset`, `batch`, `probe`, `check`, `output` and
`finish`, and refuses `command`; a files arm keeps `command`, `check`, `finish`
and `output` and refuses the verbs. Both arms also accept `await-handoff`. The
CLI `--tool` choices are the union.

## Single-context handoff

A coordinating session cannot resume a participant's context, so in the pilot the
practice phase and the timed task ran in two contexts. `await-handoff` closes
that: the participant calls it after practice `finish` returns `ready`, and waits
inside its own context while the coordinator begins the attempt.

```text
--tool await-handoff --arguments {}
  -> {"phase": "ready",   "message": "still waiting; call await-handoff again"}
  -> {"phase": "working", "message": <the coordinator's handoff text>}
```

It polls the attempt's session phase every `telemetry.HANDOFF_POLL_SECONDS`
(0.5 s) for up to `telemetry.HANDOFF_WAIT_SECONDS` (540 s), then answers `ready`
so the participant's command does not hit its own timeout; the onboarding prompts
tell the participant to use a 600-second command timeout and to call again. The
response is exactly `phase` and `message`; no `operation_record` is added.

`begin` takes an optional handoff text and stores it at `attempt/handoff.json` as
`{version: 'attempt-handoff-v1', text, sha256}` **before** `session.start_task`,
so the message exists the instant the clock does; `await-handoff` returns exactly
that text, or `telemetry.DEFAULT_HANDOFF` when `begin` was given none, and fails
closed if the stored text no longer matches its digest. The CLI is
`runner begin <root> --task … --pair … --arm … --handoff '<text>'`, and `begin`
returns the text's `handoff_sha256` for the coordinator's receipt.

The call is recorded like every other operation, as a `development-operation-v1`
record under `attempt/telemetry/NNNNNN`. The clock starts at `begin` regardless of
the poll: a poll made while the phase is still `preparing` is recorded with
`phase: "preparing"` and `summarize` keeps only `working` records, so its wall
time is outside the application clock exactly as every practice record is. Only
the poll's return latency, at most one 0.5 s interval, falls inside the clock. A
call made once the phase is already `working` returns immediately and is inside
the clock like any other operation. Any other phase is refused.

Both arms have an onboarding prompt template beside the runner —
`PROMPT-FILES.md` and `PROMPT-STORE.md`, with `COHORT_ROOT`,
`PARTICIPANT_TOKEN` and `REPOSITORY_ROOT` placeholders a coordinator substitutes
— and both instruct the participant to call `await-handoff` with `{}` under a
600-second command timeout after practice `finish` returns `ready`, to repeat
until it answers `working`, and then to follow its message. The practice `finish`
response says the same thing, so the protocol is self-describing.

## `StoreGateway`

`experiments/development_velocity/telemetry.StoreGateway` subclasses
`ObservedGateway`. It opens one `store_server.StoreSession` per dispatch, from the
**frozen** copy of the server, and closes it again, so nothing is held between
participant requests; the branch's rendered snapshot is carried across dispatches
through `<session>/renders.json` and re-adopted with `StoreSession.cached_snapshot`,
so an unchanged branch is never re-rendered.

- **Retention.** Every request and response is written as a
  `development-operation-v1` record under `attempt/telemetry/NNNNNN`, exactly as a
  command is today: phase, request and completion clocks, host samples before and
  after, elapsed and dispatch seconds, the response, and the failure when one is
  raised. `source_before` and `source_after` are the branch's rendered snapshot
  inventory rather than a mounted work tree, so `changed_files`,
  `source_size_changes` and the retained `changed-source` bytes mean the same thing
  they do in the files arm. The session additionally retains every response whole
  under `attempt/store/records/NNNNNN.json`, which is what `output` pages.
- **Phase rules.** The same rules apply: practice uses the practice store and the
  practice gateway, the timed task uses the attempt store, one task is active at a
  time, and a phase that is not `preparing` or `working` has no source.
- **`check`.** The gateway renders the branch through `session.snapshot()`,
  publishes that tree as `attempt/work`, and then runs the existing path:
  `session.submit` captures it as `submissions/NNN/source`,
  `public_verification.run` executes the frozen adapter over the frozen public
  cases, and `session.record_check` records the receipt against that submission.
  Submissions therefore hold the rendered tree, and scope violations, bounded
  feedback, grading and review are unchanged. During practice the same rendering is
  published as `attempt/practice` and checked by the existing preparation gateway.
- **`probe`.** Runs the frozen adapter under the trial limits, in the same isolated
  namespace the public check uses, on a copy of the private snapshot.
- **`finish`.** Takes a final snapshot, publishes it, and seals through
  `session.seal`, downgrading to `budget` when the task clock is spent. A
  `completed` seal still requires that the last check covered the last edit.

## Metrics

`telemetry.summarize(..., interface='store')` fills `profile.store_metrics` from
the retained session records alone, without re-running anything:

| Field | Derivation |
| --- | --- |
| `bytes_returned` | serialized size of each `returned` response, summed |
| `verb_counts` | responses grouped by `verb`, rejections and errors included |
| `context_omitted_total` | omitted **row** counts of `context` responses and their entries; omitted source bytes are not summed into it |
| `if_match_conflicts` | declarations named by the `if-match-mismatch` rejection rows of a rejected `batch`, counted once each: the server reports one conflict twice, for the operation and for the whole batch |
| `batch_rejections` | `batch` responses whose status is `rejected` |

A files arm reports `store_metrics: null`. `report.py` projects these per arm under
`observations.store_session_metrics` and refuses to mix a null arm into a total.

## Confinement

Confinement in the first cohorts equals today's: namespaced commands and
instruction-confined whole-agent access. The store adds completeness of the
operation log, because the interface is the only channel that returns source, but
it does not by itself stop an instruction-violating agent from reading the attempt
directory on the host. Structural enforcement, with the server running as a
separate user and the attempt directory unreadable to the participant, is a
separate hardening step and is not required for the first decision.

## Dry run

`experiments/development_velocity/dry_run.py` is a coordinator driver, not a
participant tool. It freezes a two-arm cohort, prepares every attempt, completes
onboarding practice in both arms with the three known repairs — command edits in
the files arm, one `batch` replacing `main::answer` plus the `add` and `remove`
drill in the store arm — begins each task in the frozen dispatch order with a
handoff message, performs one minimal real interaction per task,
seals, grades and projects. In the store arm that interaction is `open`, one
`context`, one `search`, one `asset` page, one `batch` adding a harmless
declaration to a non-protected module, one `probe` and one `check`; in the files
arm it is one command reading the task document and one check. It never attempts
to solve a task, so every attempt ends `abandoned` and every arm's completion is
zero. The point is that both interfaces execute end to end on all twelve tasks and
that `report.py` still produces a validating projection.

```sh
python3 -B -m experiments.development_velocity.dry_run /external/scratch/store-dryrun
```

The study directory must be outside the repository: `corpus/pack.py` refuses to
write a private pack inside it. Set `TMPDIR` to a disk-backed directory outside
the repository for the same reason. The driver writes
`<cohort>/dry-run-result.json` with its wall time, per-attempt outcomes and the
projected store metrics, and a full projection under `<cohort>/dry-run-report`.
A dry-run cohort is scripted harness evidence; it is never participant data, and
it is never a look in the pre-registered schedule.
