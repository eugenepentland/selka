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

# Wave 4, lane `perf/checked-arith-intrinsics` — evidence

Report: [`docs/audits/checked-arith-intrinsics-2026-09-23.md`](../../../../docs/audits/checked-arith-intrinsics-2026-09-23.md).
`bench.py`, CPU 0, loaded machine, wall time. Arms: `my` = the base compiler
with this lane's adapter, `before` = the base `625420ce` with the stock adapter
(prebuilt into the work directory), `my-unchecked`, `zig-fast`, `zig-safe`.

| file | what |
|---|---|
| `checkedadd-r1-{suite,micro}.json`, `checkedadd-r2-{suite,micro}.json` | two 11-round runs (r1 with the gate running alongside) |
| `checkedadd-r3-micro.json` | `dict_count`, `records`, `list_records`, `fib` re-measured, 21 rounds |
| `checkedadd-fib-placement.json` | `fib` built from six source paths (three code placements), lane/base per placement |
| `checkedadd-placement-suite.json` | five programs at two placements, lane/base |
| `checkedadd-census.txt`, `checked_census.py` | every overflow check in the fast-protocol IL, classified by shape and by what the adapter does with it |
| `checkedadd_table.py` | the report's tables |
| `checkedadd-measure.sh`, `checkedadd-placement.sh` | how the runs and the placement builds were made (paths are the lane worktree's `.tmp/`) |
| `traps-checked/` | the trap corpus, base against lane (`compare.log`: 195/195 identical, run with `../traps/compare.py`), and the width × op boundary program (`boundaries.{my,py,log}`: 56/56 identical across base LLVM, lane LLVM and QBE) |
