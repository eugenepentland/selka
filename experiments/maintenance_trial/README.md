# Fresh-agent maintenance sequence (F24)

This pack is ready for coordinator review and unscored calibration. **No agent
participants have been launched and no language advantage has been measured.**
It adds a small owned-buffer/generic application sequence to the existing study
infrastructure, reusing `application_comparison.storage` for source capture,
identities and verification. It does not replace that project's large comparative
study, isolation launcher or transcript collection.

Use two or more fresh participants with the same model/configuration and allowed
language documentation. Each participant runs the same three tasks in order on
its own application: last-element repair, capped-value feature, then a checked
cross-module summary migration. Preserve that participant's final submission
between stages, including unsuccessful submissions. No participant sees another's
patch, this coordinator directory, reference restorations or private grading data.
Only the current stage's `public/` projection may be provided. The compiler and
language documentation must be explicitly supplied read-only. Filesystem
projection is a context boundary, not an OS sandbox; use the existing isolation
launcher or an equivalent restricted environment for scored sessions.

The baseline allocates a generic owned buffer, fills it through a generic mutable
borrow helper, summarizes it and consumes a result through another module. The
three editable files are model.my, ledger.my and report.my. The independent host
reference computes expected arithmetic without interpreting or copying guest
implementation logic. Grading calls both the summary API and its reporting
consumer, including floor/ceiling equality, extreme values and seeded random
inputs. Structure and error-propagation review remains mandatory: passing these
bounded behavioral cases alone cannot certify preservation of the owner model.

## Frozen protocol

Before launch, review the briefs, public cases, reference fixture results and
private grader with a separate reviewer. Preparation records `prepared-unreviewed`
and `scored_launch_enabled:false`; this adapter does not launch participants.
Record review/calibration decisions separately. A changed brief, budget, compiler
or grader starts a new cohort. Keep fixture seeds out of scored trials.

Per stage: 20 participant tool invocations, 5 edited submissions and 900 seconds.
The coordinator counts every tool invocation and candidate check, retains raw
transcripts/diagnostics, and stops at the first exhausted bound. A public-check
invocation runs all eight public observations but counts as one participant tool
invocation. Tool calls used to edit or inspect source also count. Budget accounting
is explicit coordinator review, not automatically enforced by pack.py. Capture
start/stop timestamps, model settings, token usage when available, each submitted
source hash, check time and whether the immediately following edit fixes the
reported diagnostic. Missing metrics remain unknown. Wall time includes pauses;
report active tool time separately. Keep failed, abandoned and budget outcomes.

## Commands

Run from the repository root. Create private pack directories outside participant
workspaces; give only `stage1/public/` and approved read-only tools/docs to the
participant. Replace labels and paths with actual session identities.

```sh
python3 experiments/maintenance_trial/pack.py prepare /private/trial-a-stage1 \
  --compiler zig-out/bin/mylang --stage 1 --participant fresh-a \
  --model recorded-model-configuration --kind agent
cd /private/trial-a-stage1/public
python3 check.py --compiler /absolute/pinned/mylang --stage 1
```

Record the unchanged seeded failure before editing. After the participant stops,
seal its source with the transcript, even if the candidate is incomplete:

```sh
python3 experiments/maintenance_trial/pack.py seal /private/trial-a-stage1 \
  --reason completed --transcript /private/transcripts/a-stage1.jsonl
python3 experiments/maintenance_trial/pack.py prepare /private/trial-a-stage2 \
  --compiler zig-out/bin/mylang --stage 2 --participant fresh-a \
  --model recorded-model-configuration --kind agent --previous /private/trial-a-stage1
```

Repeat sealing/preparation for stage 3 and for independent participant B. Valid
stopping reasons are completed, budget and abandoned; completed is not a verdict.
The previous seal, participant/model/kind and compiler identity must match.
Only seal.json's snapshot is graded; later participant edits cannot alter it.

After every participant has sealed a stage, create one fresh private seed file
for that stage and grade each submission with the same seed. Keep grading reports
private until the sequence finishes so later stages receive no hidden answers.

```sh
python3 experiments/maintenance_trial/pack.py grade /private/trial-a-stage1 \
  --seed-file /private/grading/stage1-seed.txt
python3 experiments/maintenance_trial/pack.py grade /private/trial-b-stage1 \
  --seed-file /private/grading/stage1-seed.txt
```

Each report records 48 private cases through two call paths, their digest, all
outcomes and the sealed source identity. Compiler and authoring hashes must match
preparation. Regrading completed reports is refused. A timeout or launch failure
is infrastructure failure; retain it and investigate rather than silently
starting a new seed. This small adapter does not provide interrupted-case resume.

## Validate fixtures and report results

```sh
python3 experiments/maintenance_trial/selftest.py --compiler zig-out/bin/mylang
```

Known restorations verify the seeded wrong result and all three passing stages,
288 heldout observations, snapshot isolation and regrade rejection. These are
explicitly `fixture` outcomes and must never appear as agent performance results.
Public checks and hidden grading share only transport/driver generation; their
expected-value implementations are separate.

For each actual participant/stage report final behavioral success, structure and
budget review, first submitted repair success, tool/edited-submission counts,
wall and tool time, source change size, failures and raw evidence locations.
Publish the denominator and every attempt. This repeated same-language sequence
measures feasibility and friction; it cannot establish superiority over Rust,
Zig or other languages without matched tasks and a larger reviewed cohort.
