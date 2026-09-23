# Wave 4, lane `perf/frame-return-map` — evidence

Report: [`docs/audits/frame-return-map-2026-09-22.md`](../../../../docs/audits/frame-return-map-2026-09-22.md).
All timings: `bench.py`, CPU 0, loaded machine (other agents building), arms
shuffled per round, wall time. Arms: `my` = this lane's ReleaseFast compiler,
`before` = the base `0804a4cf`, `frk` = base IL with the frame record and
position stores stripped but the floor test kept, `fr` = also the floor test
stripped (the ladder's `-fr` rung on this base), `myfp`/`mynofp` = pricing arms
for the guest frame-pointer attribute.

| file | what |
|---|---|
| `r6-suite.json`, `r6-micro.json`, `parser.json` | final: lane vs base vs `frk`/`fr` (11 rounds suite, 15 micro, 11 parser) |
| `r7-*.json` | the CFI walk (`my`) against the same compiler keeping guest frame pointers (`myfp`), 15 rounds |
| `r1-*.json` | the first build (frame-pointer walk everywhere) vs base and `frk` |
| `experiments/e1-*.json` | `noinline` on every guest function that calls (`frka1`): rejected |
| `experiments/e2-*.json` | the adapter constraints without `noinline` (`frka2`) |
| `experiments/e3-*.json` | frame pointer, tail calls, `nomerge` priced one at a time |
| `experiments/r5-*.json` | frame-pointer build vs `mynofp` (noisy; the gate ran alongside) |
| `traps/` | the byte-for-byte trap corpus: `compare.py BEFORE AFTER CASES --modes ...`, the cases, and both runs (280/280 and 240/240 identical) |
| `paired.py`, `table_r6.py` | paired ratios with bootstrap intervals, the report's table |
| `make_rewrite.py`, `make_adapter_*.py`, `e1_build.sh`, `r6.sh`, `r7.sh`, `buildtime.sh` | how the arms were built (written for this worktree's `.tmp/`) |
