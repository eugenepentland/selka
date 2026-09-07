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
The command gateway enforces these bounds and logs every request, accepted
command, before/after source snapshot, raw output, duration and exit status.
A public-check invocation counts as one tool invocation. A changed source checked
through its check operation counts as an edited submission, including failures.
Read/edit commands count as tool invocations. Indirect public checks through run
are protocol violations because they do not register submissions. The first
exhausted bound stops further commands. Completed agent seals must match the last checked
source. Budget and abandoned seals retain the final recorded source even when
unchecked, with final_checked=false and the previous check receipt recorded
separately. Pending commands or source changes outside the gateway still block
sealing. Rejected requests remain recorded. Model token counts remain unknown.

Use [the exact launch prompt and gateway commands](LAUNCH.md). The wrapper reuses
the existing Linux namespace executor, mounting only the public projection and
read-only approved tools/docs. Review inherited-tool bypasses; this does not
claim whole-agent isolation when the participant retains unrestricted tools.
Keep failed, abandoned and budget outcomes. Commands have an additional 60-second
wall limit and 2 MiB output bound; command durations exclude gateway setup/hash
work, while the stage deadline includes that overhead and time between commands.


## Commands

Run from the repository root. Create private pack directories outside participant
workspaces; give only `stage1/public/` and approved read-only tools/docs to the
participant. Replace labels and paths with actual session identities.

```sh
python3 experiments/maintenance_trial/pack.py prepare /private/trial-a-stage1 \
  --compiler zig-out/bin/mylang --stage 1 --participant fresh-a \
  --model recorded-model-configuration --kind agent
cd /private/trial-a-stage1/public
# Use gateway.py begin/check/run as shown in LAUNCH.md; no direct tool access.
```

Record the unchanged seeded failure before editing. After the participant stops,
seal its source with the transcript, even if the candidate is incomplete:

```sh
python3 experiments/maintenance_trial/pack.py seal /private/trial-a-stage1 \
  --reason completed
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

Each report records 48 private cases through the reporting API and each individual summary field, their digest, all
outcomes and the sealed source identity. Compiler and authoring hashes must match
preparation. Regrading completed reports is refused. A timeout or launch failure
is infrastructure failure; retain it and investigate rather than silently
starting a new seed. This small adapter does not provide interrupted-case resume.

## Validate fixtures and report results

```sh
python3 experiments/maintenance_trial/selftest.py --compiler zig-out/bin/mylang
python3 experiments/maintenance_trial/gateway_test.py --compiler zig-out/bin/mylang
```

Known restorations verify the seeded wrong result and all three passing stages,
480 heldout observations, snapshot isolation and regrade rejection. These are
explicitly `fixture` outcomes and must never appear as agent performance results.
Compensating-field fixtures prove that incorrect summary fields cannot pass by preserving the combined report score. Public projections contain only current-stage transport, fields and expected public outputs. The private oracle is independent of the guest implementation.

For each actual participant/stage report final behavioral success, structure and
budget review, first submitted repair success, tool/edited-submission counts,
wall and tool time, source change size, failures and raw evidence locations.
Publish the denominator and every attempt. This repeated same-language sequence
measures feasibility and friction; it cannot establish superiority over Rust,
Zig or other languages without matched tasks and a larger reviewed cohort.
