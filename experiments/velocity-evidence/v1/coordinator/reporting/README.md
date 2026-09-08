# Coordinator-only historical replay

No participant is launched by this helper. It lives outside the repository and all historical evidence is read-only. Private grading artifacts stay here; do not mount this directory for participants.

`historical.json` pins the latest matching eight raw historical packs, original sealed sessions, summaries, configurations and protocols by file hashes. Original .my application seconds in task order: clearance 89.631711100; input boundary 95.026027434; pin roles 198.711030980; priority 132.638051235; rotation 116.665028302; cycle groups 147.458232963; dependency lags 182.302969622; slack 188.326209699. These are historical observations, not new retest results. The earlier priority cohort is not another observation.

From this directory:

```
python3 -B replay.py status
python3 -B replay.py replay eda-clearance-boundary
python3 -B replay.py replay all
python3 -B replay.py publish --output /home/epentland/ai/canopy/application-trials/velocity-v1/reporting/publication-001
```

Run replay only after the selected session has sealed and its fresh grading summary exists. `all` records unavailable tasks as incomplete attempts and exits nonzero; rerun later. Per-case results resume through the existing grader, which refuses an interrupted execution lacking its receipt. Do not delete that execution to silently rerun; explicit coordinator recovery must preserve it. Inputs pin the helper and harness inventory, so changing either during replay requires a separately versioned procedure, not overriding the receipt.

Publication requires all eight summaries and historical replay receipts, validates seals/source snapshots and grading plan identities, and creates a new output directory. Existing publications are never overwritten. Combined JSON/Markdown omit hidden seeds, case names, case inputs/outputs and source. They retain evidence paths/hashes and separate preparation, task, failed checks, command metrics and acceptance. Current timing reduction is available only when BOTH fresh and historical packs accept current development and the original historical development was accepted. Negative reductions remain visible. A failed-fast session never receives a speedup claim.

Original tool configurations may now be stale; their frozen receipts describe original conditions. Replay uses current frozen tools and configuration, does not re-run old participants, and does not change any development clock. Report source/tool/baseline/build-policy differences through the referenced current and historical protocol/configuration records. Do not infer model turns, relevant navigation, cache hits, or causal improvement from command counts.

Plan follow-through still needed outside this helper: timing-blind source-quality review for each new sealed task; separate owner/generic three-stage sequence with two fresh participants if its harness provides equivalent clocks/receipts; accepted-lag provenance before slack; append-only iteration events and a final validation ledger. No quality claim is generated here. All library/compiler/workflow preparation is outside application time.

Validation: four dependency-stdlib-only tests cover failed-fast suppression, slower accepted observations, immutable resume/rejection, historical hash drift, and refusal to create publication before complete data. `status` verified eight pending tasks without launching applications. No replay or result publication was run during helper preparation.
