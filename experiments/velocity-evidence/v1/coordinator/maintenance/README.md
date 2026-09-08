# Coordinator-only maintenance rerun tooling

This directory prepares two fresh participants, A and B, for the same three
owned-buffer/generic maintenance stages as the 2026-09-07 sequence. It invokes
`experiments/maintenance_trial/pack.py` and `gateway.py` unchanged from the current
repository. No repository harness, frozen velocity cohort.py, or frozen velocity
participant.py is edited. This directory is never mounted into participant
commands; only an invocation-only bridge path is supplied to each fresh agent.

## Freeze and preparation (no clocks)

From any directory:

```sh
/usr/bin/python3 -B /home/epentland/ai/canopy/application-trials/velocity-v1/maintenance/tooling_test.py
/usr/bin/python3 -B /home/epentland/ai/canopy/application-trials/velocity-v1/maintenance/coordinator.py freeze
/usr/bin/python3 -B /home/epentland/ai/canopy/application-trials/velocity-v1/maintenance/coordinator.py prepare \
  --compiler /home/epentland/ai/canopy/application-trials/velocity-v1/toolchain/bin/mylang \
  --model 'COMMON ACTUAL ROOT MODEL/CONFIGURATION LABEL; exact serving ID unavailable if unknown'
```

Run freeze exactly once, before prepare and before any participant call. It
copies the twelve historical language-reference paths from the **current** repo,
plus current borrow syntax, generic containers, and standard-library/collection/
text-data references (17 files total). Only this explicit language-documentation
allowlist is copied: no maintenance sources, solutions, histories or private
oracles are in the documentation projection. The receipt pins every copied file,
the unchanged repository authoring/shared isolation code, and this adapter.

Freeze also creates three private cryptographic seed files, one per stage shared
by A/B, before all clocks. This differs explicitly from the old README's suggested
post-seal seed creation; it follows this rerun's required pre-clock freezing.
The seeds stay under coordinator-only grading/ and never enter public mounts.
Compiler preparation requires the final frozen executable to exist. It creates
only A-stage1 and B-stage1 packs, neither gateway.json nor commands/. Do not run
pack/gateway fixtures against these real participant packs. The local tooling
unit tests use synthetic records and mocked begin/run; they start no clocks.

Retain an independent tooling/brief/documentation review before launching agents.
Pack metadata continues to say prepared-unreviewed/scored_launch_enabled=false;
this is the same unscored same-language calibration protocol, not a superiority
claim. Exact serving IDs and token/cost telemetry remain unknown when unavailable.

## Root launches later

Give two fresh agents participant-prompt.txt with PARTICIPANT replaced solely by
A or B. Do not include this README, coordinator source, historical solutions,
private grades, seeds, or another participant's transcript. The invocation is:

```sh
/usr/bin/python3 -B /home/epentland/ai/canopy/application-trials/velocity-v1/maintenance/participant_bridge.py A check '{}'
/usr/bin/python3 -B /home/epentland/ai/canopy/application-trials/velocity-v1/maintenance/participant_bridge.py A command '{"argv":["/bin/cat","TASK.md","work/ledger.my","work/model.my","work/report.my"]}'
/usr/bin/python3 -B /home/epentland/ai/canopy/application-trials/velocity-v1/maintenance/participant_bridge.py A finish '{}'
```

These are launch-time commands, **not preparation commands**. First accepted
check begins the current clock and records the unchanged check separately.
Read/edit commands cannot start a stage. All real executions are delegated to the
existing isolated gateway. A participant can finish only after a matching,
successful latest check; the old pack.seal alone verifies matching source but
does not require successful checks. The adapter adds this success precondition.
Separate stop controls retain budget/abandoned sources and continue from those
sources, preserving unsuccessful attempts. Sealing prepares only the next stage,
without beginning it. Neither future public packs nor sibling/private directories
are mounted. A/B use separate coordinator locks and can work independently.

No implementation claims whole-agent technical isolation when agents inherit
unrestricted tools: the invocation-only rule still requires transcript review.
Indirect check.py calls through command are prohibited by the participant protocol;
review recorded argv and agent histories for bypasses. Finish/stop and adapter
rejections are retained separately in control/A|B/bridge.jsonl. Historical
command/check metrics remain exactly the gateway counters, including its rejections.

## Private grading and summary

Only after all six stages are sealed:

```sh
/usr/bin/python3 -B /home/epentland/ai/canopy/application-trials/velocity-v1/maintenance/coordinator.py grade
/usr/bin/python3 -B /home/epentland/ai/canopy/application-trials/velocity-v1/maintenance/coordinator.py summary
```

Grade reuses pack.grade unchanged and the already frozen stage seed for both
participants. Existing grades are never overwritten; after an interrupted batch,
use grade --resume to retain completed matching reports and grade only remaining
packs. The underlying per-pack grader still has no interrupted-case resume.
Do not reveal private grade details while either participant has remaining stages.
Summary can also report prepared/started/unfinished rows without dropping them.

The historical timing definition is retained exactly:
`max(executed commands/*/result.json time) - gateway.json started_unix`.
This includes agent reasoning, waits and gateway overhead before the final command
ends; it excludes later time to coordinator seal. Both start-to-last-command and
wall_seconds_at_seal are reported, with their difference as coordinator delay.
Command seconds sum gateway duration_seconds; these include public-check driver,
compiler and VM work and are not isolated compiler timing. Pending commands are
reported without inventing an end time. Initial unchanged failures have their own
receipt and are excluded from failed-edited-submission counts. The denominator is
always the planned six participant-stage outcomes, including budget/abandoned rows.

Independent final review still checks ownership, generic helper/mutable borrowing,
module boundaries, error propagation, no test-specific shortcuts, source continuity,
recorded command bounds, and inherited-tool scope. The 2026-09-07 evidence lives at
`mylang/experiments/maintenance-evidence/20260907`; its observations were retained at
`application-trials/maintenance-20260907/observations.json`. They establish the
historical metric definitions and review method, not answers to provide participants.
