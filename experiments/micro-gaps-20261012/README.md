# Four measured performance gaps

Integration branch: `codex/micro-gaps-20261012`.
Base: `399013af36d41b78610e5ede22a9102ec5b17ffe`.
Four Sol 6.1 workers, each using low reasoning effort, ran concurrently in separate sibling worktrees. The dispatch,
file ownership, pinned baseline compiler and shared admission setup are recorded
in `coordinator/dispatch.json` and each worker's `handoff.md`.

All four changes are integrated and the complete verification gate is green.
The fresh paired campaign validates all 91 cells. See [performance results](PERFORMANCE.md),
[all cells as CSV](all-cells.csv), [machine-readable results](report.json), and
[item ledger](ledger.json).

| Target | Runtime change versus frozen checked-ownership baseline | Memory result |
| --- | --- | --- |
| Dictionary key copies | Fixed dictionary counting: 72.5% less time; broader string updates: 5.4–5.9% less | Counting allocations 2,003,014 → 4,014 |
| Word counting | Small: 60.5% less time; large: 75.5% less | Large managed peak 27,384 → 20,464 bytes; allocations 11,100,184 → 127,144 at equal iterations |
| Owned record sorting | Small: 34.4% less time; large: 52.3% less | Managed counters unchanged; adds 1.5/96 KiB native scratch per small/large sort |
| Local encoding copies | Formatting: 40.3–41.4% less time; splitting: 38.2–42.0% less | Formatting allocations approximately halved |

No cell's median slowdown exceeded 5%. The Lox **microbenchmark** was 3.5–4.6%
slower with intervals excluding parity; this remains recorded, with no causal
attribution or additional tuning. Full Lox/EDA application results and foreign
language results belong to the prior campaign and were not relabeled here.
RSS was mostly unchanged and does not resolve the sort scratch allocation.
All 182 counted runs had zero RC events and zero managed bytes live at exit.

This experiment targets dictionary string-key updates, word counting, owned keyed
record sorting and local text-encoding copies. It preserves benchmark sources and
checked ownership. Explicit copies that escape remain independent. Unsupported
ownership shapes remain refusals. This is not a claim that the earlier default
promotion or legacy runtime retirement milestones have been completed.

## Validation and measurement

Workers record focused IR/native tests, managed counters and Guardian checks.
The coordinator integrates the changes and runs the complete registered
verification coordinator on frozen inputs before freezing the measured compiler.
The final gate uses the exact checked-owned component pin/archive selected by the
previous successful gate; `coordinator/component-route.json` records both inputs.
The default historical seed remains unchanged. Its native-link failure on this
host is not repaired by changing immutable seed history.

`coordinator/build_candidate.py` builds all 30 checked runtime/counted micro
artifacts from unchanged sources. It retains build logs and compiler/source/native
hashes, then derives 91 new paired specs from the prior campaign. The copied
`tools/schedule.py` and `tools/measure.py` execute
these specs under exclusive shared timing admission on allowed CPU 8. The two arms
are frozen baseline checked ownership and the integrated candidate. Both run
again on this host, with 2/3 warmup pairs, 9/15 measured pairs and 3 RSS probes per
arm. Counted runs are separate from timing and RSS. Kernel calibration follows
the existing bounded policy; raw limited pilots remain visible. The copied harness
changes pair order to strict alternation and passes the five existing measurement
contract tests. Historical harnesses and reports are unchanged.

`coordinator/report.py` validates independent checksums, all rounds, immutable
artifact hashes, zero RC/uniqueness events and zero managed exit-live bytes. It
reports paired bootstrap intervals, traffic, managed peak and process RSS
separately. Known legacy retain/release native symbols are audited separately.
Raw sorting scratch is native storage and is not part of managed counters.

The prior foreign-language and RC receipts remain unchanged historical context;
they are not substituted for paired controls in this campaign. Compilation logs
include queue wait and are not compiler throughput measurements.

## Integrated verification

Production/test revision: `444465eb82290233c68c68b7f201148a8bf3eae4`.
Compiler SHA256: `ec423f5ff7dba37f5d39489fec12b9c851754c0ad69125fc8aaafe85e31ea44e`.
Baseline compiler SHA256: `8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa`.
The baseline was built at `4034a2fab29e3300b6f70549ce84727d647761db`;
production/compiler sources are identical between that revision and this batch's
base `399013af36d41b78610e5ede22a9102ec5b17ffe`.

Gate 03 passed all 135 steps and all 3,083 executed registered tests. The 26,964
reported skips are shard selection; each registered test belongs to its assigned
shard. All 45 verification actions executed (11 freshness-required, 34 execute;
no action receipt reuse). Compiler/build dependencies may still reuse caches.
The gate includes formatting, cache checks, language tests, components and Guardian.
Guardian passed 88 checks against the configured diff scope, with 38 whole-tree
checks. The final commit hook also checks the whole source tree.

The gate took 475.4 seconds overall, including 454.3 seconds inside gate admission.
These are verification durations, not matched compiler performance samples.
Every file in the frozen 12-file compiler installation matches the successful
gate output; see `coordinator/installation.json` and `coordinator/qualification.json`.
The benchmark sources and runtime/count binaries are separately hashed in
`coordinator/builds.json` and the measurement receipts.

Gate 01 found only whitespace formatting in a new fixture, corrected in the
qualified revision. Gate 02 encountered one unexplained SIGABRT in the ordinary
verified-release language command. The exact command passed afterward, four
private reproductions passed, and the unchanged third full gate passed. Each
language reproduction reported 1,578 passed and one existing unsupported case.
No root cause or specific transient explanation is established. Failed gate logs
and the private diagnosis remain recorded; a later pass is not a claim to have
fixed the abort. Verified test execution does not imply cold compiler caches.

Implementation stopped when the full gate turned green, as requested. The paired
performance campaign records tradeoffs without starting another optimization round.
