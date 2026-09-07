# Pilot task authoring

These six task briefs define concrete matched maintenance work for the 36-session
pilot (six blocks × three languages × two fresh attempts). They are **drafts**,
not launch-ready tasks or results. They use the v1 small application baselines,
whose independent contract/idiom review remains pending;
subsequent medium/large workloads must grow real product behavior separately.

Each brief is language-neutral. Independent grading cases and task-pack receipts
must be built and reviewed before launch. For regression tasks, introduce exactly
the named defect in each language, prove that valid public/hidden boundary cases
expose it, and keep the semantic regression equivalent. Do not fabricate an
unrelated defect to make one implementation easier or harder to repair. Publish
only the brief, allowed documentation and public tests to participants; seeds,
expected hidden results and oracle code stay in coordinator-only task packs.

Feature/contract tasks start from the unchanged v1 application. Existing valid
behavior remains required unless the brief explicitly changes it. New fields must
be parsed and validated in application code; no bridge or compiler changes during
an attempt. Normal agent language tools remain available according to the study arm.

Before freezing: review ambiguity, independent-oracle validity, equivalent seeded
changes, passing references, failure-triggering cases, input limits and difficulty.
Unscored calibration may replace/revise tasks; after scored launch a changed task
starts a separate cohort. Pilot briefs/answers must not enter the main study.

`catalog.json` is schedule input plus authoring status. It is not evidence that
oracles, seeded variants, review or calibration are finished. No cohort is frozen
or launched simply by materializing a balanced schedule from these descriptors.

Coordinator expectations now exist in `planner_pilot_oracle.py` and
`eda_pilot_oracle.py` in the parent directory. `seeded_regressions.py` constructs
the two repair variants for all three languages from an explicitly supplied
baseline receipt. It copies sources, requires exactly one matching mutation site,
and returns private before/after receipts without modifying the original baseline.
Those construction recipes are not participant tools or scored trial results.
`test_seeded_regressions.py` executes all six variants in isolation, requires the
exact intended wrong boundary result with successful process exits, restores the
original source bytes and verifies passing output. The executions share identical
input and tool adapters; the repaired source must match the original baseline receipt.
Zig uses ReleaseSafe here;
this construction test does not substitute for the pending main-arm Guardian gate.

`pilot_cases.py` now generates public examples and private grading requests for
all six tasks. Hidden coverage includes generated original/extended behavior,
malformed transport, UTF-8 byte limits, larger cyclic groups and large-coordinate
clearance with equivalent-unit pairs. The authoring code and tests are public;
fixture seeds must never become scoring seeds. The independently authored
[feature references](../references/README.md) now pass all public/private draft-pack
checks. Full contract coverage review and calibration remain required.

Create a private draft pack outside participant workspaces using a seed file:

```sh
python3 -m experiments.application_comparison.task_pack create \
  --task planner-priority --seed-file /private/pilot-seed.txt \
  --directory /private/planner-priority-pack
python3 -m experiments.application_comparison.task_pack verify \
  --directory /private/planner-priority-pack
python3 -m experiments.application_comparison.task_pack provision-public \
  --directory /private/planner-priority-pack --destination /participant/task-docs
```

The last command copies only `brief.md` and public `cases.json`. The full pack
contains private seeds/answers and must never be mounted for participants or
committed to a participant repository. Pack hashes record contents and authoring
code identities; they do not authenticate the author or prove independent review.
Creation refuses to overwrite an existing pack. All packs remain `draft-unreviewed`
with scored launch disabled. `pack_grading.grade_fixture` exercises every private
case through three-way grading, retains each failure and resumes completed cases;
it rejects agent sessions and never turns these fixtures into comparison results.
