# Coordinator closeout

Branch: `codex/micro-gaps-20261012`. Base:
`399013af36d41b78610e5ede22a9102ec5b17ffe`.
Qualified production/test revision:
`444465eb82290233c68c68b7f201148a8bf3eae4`.
Later closeout commits contain only experiment tools, reports and evidence.
No publication or merge into another branch was performed.

Four concurrent Sol 6.1 low workers implemented the reserved dictionary, words,
sorting and encoding assignments. Their handoffs retain focused positive,
negative, bounds, cleanup and five-mode evidence. The coordinator integrated
shared pass dispatch, trusted helper declarations, IR/span handling and test
registration. See the item ledger for integrated commits and remaining observations.

The final full verification command is preserved in `gate-03/request.json`.
It ran `scripts/verify_cache.py` directly, using pinned Zig and the previously
qualified owned component pin/archive. Result: 135/135 steps, 3,083 executed
registered tests, 45 executed verification actions, stable inputs, status zero.
All 12 installation files were checked against the successful gate output.
The measured compiler SHA256 is
`ec423f5ff7dba37f5d39489fec12b9c851754c0ad69125fc8aaafe85e31ea44e`.
Baseline/compiler/source/binary hashes and exact guest build commands are in
`dispatch.json`, `installation.json`, `builds.json` and the per-cell specs/receipts.

Reproduction, after sourcing `/home/epentland/.config/mylang/dev-env.sh`:

```sh
python3 -B experiments/micro-gaps-20261012/tools/test_measure.py
python3 -B experiments/micro-gaps-20261012/tools/schedule.py experiments/micro-gaps-20261012/specs-parity NEW_PARITY_OUTPUT --cpu 8
python3 -B experiments/micro-gaps-20261012/tools/schedule.py experiments/micro-gaps-20261012/specs-expanded NEW_EXPANDED_OUTPUT --cpu 8
python3 -B experiments/micro-gaps-20261012/coordinator/report.py
```

Each schedule takes exclusive shared timing admission per cell. The report command
validates the recorded `results/` paths; use a new experiment root and update its
paths when collecting a new campaign. Never overwrite existing receipts. A new
machine must rebuild binaries and retain source identities; current absolute
artifact paths describe this host. Compiler installation includes bin/libexec/tools.

All 91 cells passed independent oracles, artifact checks and round completeness.
Evidence includes 2,598 timing samples, 524 warmups, 546 RSS probes and 182 separate
counted runs. Every counted run had zero RC, uniqueness, share-mark and managed
exit-live counters. Sixty native runtime/count artifacts passed known RC-symbol
audits. Raw evidence, ranges, paired intervals, calibration limitations, cumulative
traffic, managed peak and RSS remain separate. Compilation throughput was not
remeasured; queued build durations are not presented as compile-performance data.

Gate 01's fixture whitespace failure was fixed before qualification. Gate 02's
single unexplained language-command SIGABRT remains documented. Five subsequent
direct/private executions and unchanged gate 03 passed. No root cause was claimed.
Default historical-seed provisioning remains outside this batch; the successful
gate uses the prior qualified owned pin/archive without changing immutable seeds.
No zero-RC default or legacy-RC retirement milestone is claimed here.

Performance: the four intended workloads improve, with an explicit native scratch
cost for sorting. The Lox microbenchmark is 3.5–4.6% slower; no median regression
exceeds 5%. Full Lox/EDA applications and foreign references were not remeasured
in this batch. The user requested implementation stop at green verification and
performance differences be recorded; further optimization is left for that decision.

No outstanding shared-file request remains for these four changes. No Guardian
feedback entry was written. The final evidence commit uses the normal whole-tree
Guardian pre-commit hook; its successful result is recorded in the final response.
