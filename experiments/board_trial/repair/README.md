# Recorded repair experiment

This coordinator harness prepares five repair tasks in each of two languages,
retains checked submissions and diagnostics, and grades frozen submissions with
fresh cases after editing stops. It is tooling for the experiment; **no actual
agent repair results have been collected**. The self-tests restore known answers
and label their records `fixture`.

## Tasks and scope

| Task | Deliberate regression | Expected initial evidence |
| --- | --- | --- |
| identity | A component lookup uses the net catalog while retaining its component ID. | Nominal type error in both implementations. |
| units | Millimetres are returned directly from a micrometre conversion. | Nominal return-type error in both implementations. |
| state | The through-via preflight arm is missing. | Exhaustiveness error in both implementations. |
| admission | Track and via net exemptions are omitted. | Wrong reports or callback counts against the development oracle. |
| boundary | A footprint touching the board's left edge is classified outside. | Wrong reports against the development oracle. |

Four tasks use the bounded board validator and its fixed 87 development cases.
The units task uses the existing guest conversion helper and a small equivalent
Zig helper, with eight development integers. It is a conversion experiment, not
a board-unit protocol migration. The state task reproduces a missing-handler
regression; full schema evolution with a genuinely new feature family remains
separate work. All arithmetic inputs stay within the declared signed bounds.

For a pair, use separate fresh participants, the same model/configuration and
attempt budget, and comparable context. Give each participant only its work/
folder and returned development diagnostics. That folder contains the editable
file, read-only same-language dependencies, the task and the contract. Do not
provide the seed generator, correct baseline, opposite implementation or previous
participants' patches. Record configuration differences and protocol deviations
instead of silently treating runs as equivalent.

The directories isolate edits and preserve evidence. They are **not an OS
sandbox**: participants must follow the context restrictions. Fresh held-out
inputs do not exist until both submissions are sealed. The coordinator and
handwritten host wrappers remain trusted. Review patches for erased nominal
types, changed contracts, duplicated rules or other workarounds; behavioral
agreement alone does not establish that those restrictions were preserved.

## Coordinator workflow

Build the checked compiler first. For example, prepare a guest task outside the
repository, with real participant/model labels when conducting an actual study:

```sh
python3 experiments/board_trial/repair/study.py prepare /tmp/repair-guest-identity \
  --language guest --task identity --kind agent \
  --participant participant-a --model session-model-description \
  --compiler zig-out/bin/mylang --zig /home/epentland/.local/bin/zig
python3 experiments/board_trial/repair/study.py check /tmp/repair-guest-identity
python3 experiments/board_trial/repair/study.py begin /tmp/repair-guest-identity
```

The first check must record the unchanged seeded failure before participant
editing begins. A check exits 1 when the candidate fails; its JSON still records
the complete outcome. The begin command marks the start of the participant
session. Prepare and begin the corresponding Zig task with a different
participant, the same task/model/configuration and `--language zig`.

Pass work/TASK.md and the initial diagnostic to the participant. After each
candidate edit, run the check command printed in TASK.md. Every invocation gets
a new directory; repeated checks of unchanged source count as checks but not
edited submissions. There are at most five edited submissions and twenty checks.
Out-of-scope edits and missing/changed context are retained as failed boundary
submissions before code execution. Symlink targets are recorded without copying
their external contents. Edits between checks are not separately observable;
participants must check after each candidate and disclose any unrecorded checks.

When each participant stops, seal the latest recorded submission, including a
failed or unfinished repair:

```sh
python3 experiments/board_trial/repair/study.py seal /tmp/repair-guest-identity --reason completed
python3 experiments/board_trial/repair/study.py seal /tmp/repair-zig-identity --reason budget
python3 experiments/board_trial/repair/study.py grade /tmp/repair-guest-identity \
  --peer /tmp/repair-zig-identity
```

`completed` is the participant's stopping reason, not a correctness verdict.
`budget` and `abandoned` retain failures. Unchecked final edits cannot be sealed;
restore the last recorded candidate if no further check is available. Checks
stop after sealing. Later edits to work/ cannot affect the captured submission.

Paired grading verifies task, model label, tools, source snapshots and budgets,
then generates the same 128 fresh board cases or 64 fresh conversion inputs for
both languages. Both sides must be sealed first. A grading plan is recorded
before execution; an interrupted grading pass resumes with the same seed and
retains incomplete execution directories. Individual grading without --peer is
available but explicitly unpaired. Completed grading cannot be run again with a
new seed. A leftover coordinator lock or unfinished check requires investigation;
never infer that a process stopped merely from file age or overwrite its records.

## Evidence and interpretation

The coordinator retains:

- Baseline commit, worktree-dirty flag, frozen compiler/trial source hashes,
  harness hashes, executable hashes and participant/model labels.
- Each candidate's source snapshot, changes from the previous submission, changed
  files, exact command arguments, stdout/stderr, exit/timeout status and elapsed
  command/check times. Raw streams remain complete; the returned diagnostic
  preview is bounded to 64 KiB per stream. Only the first three development
  mismatches appear in the returned preview; the complete list is retained.
- Sealing reason/time, fresh case seed and case digest, every submission's
  independent outcome, check/edit counts and first-edited/final correctness.

The report deliberately makes no comparative reliability claim. Read command
status before treating a failed checking phase as a source diagnostic: timeouts
and tool-launch errors are infrastructure outcomes. Participant start/seal
timestamps measure wall time including pauses and coordination, not active
reasoning time. The guest units task invokes the CLI for each input, while the
Zig units task builds one test executable; board checks rebuild a common host
harness. These paths have unequal overhead, so raw timings are not a language
performance comparison. Missing labels or transcripts are unknown evidence, not zeros.
First-edited-submission correctness is not automatically next-diagnostic repair
success; classify the actual preceding diagnostic and patch first.

Publish actual attempts, failed and abandoned outcomes, patch review and these
limitations before drawing conclusions. Five deliberately seeded tasks are a
small convenience sample, not proof about broad agent reliability or full EDA
projects. Repeated trials and a real application pilot remain useful next steps.
Native guest compilation is outside this experiment; guest code runs on the VM.

## Harness acceptance

`zig build test-repair-study --summary all` runs the focused Guardian-gated
acceptance. The same self-tests are included in the default interpreter suite.
For a direct run against an already built compiler:

```sh
python3 experiments/board_trial/repair/selftest.py \
  --compiler zig-out/bin/mylang --zig /home/epentland/.local/bin/zig
```

Known restorations verify all ten seeded failures, development acceptance and
fresh grading. Additional tests cover restricted edits, sealing, source snapshot
changes, budgets, frozen compiler changes, paired case identity, grading recovery
and reproducible case generation. These fixture runs must never be reported as
measured agent repair attempts.
