# Experimental RC semantic lowering evidence

Frozen compiler: `825db00e5526581784ef1ef452af1c73e29f5b3314cedc6fc5b782312293fdfa`,
Debug. The JSON identity records its immutable installed path and merge base.
It emits ABI3 artifacts; GC remains the default.

Final checks:

- 157/157 RC guest assertions across 22 files on QBE and 157/157 on actual LLVM.
- Three unaccounted standalone fixtures: all 23 booleans true in GC stress and RC
  on both backends (12 executions). Every counted run balances heap allocations
  and retirement, ordinary ownership, and holds; backend counts match exactly.
- Corrected indexed-argument history and its independent oracle both print
  `[7]\n13\n7\n` in all four runtime/backend combinations (eight executions).
- 107/107 focused RC compiler units and 19/19 COW units.
- All 23 native-memory suites under ASan + UBSan, including 27 semantic-history,
  seven loan, 12 held-edge, ten arena, 21 core and 31 collection scenarios.
- Debug install, formatting and whole-tree Guardian88 pass.

The standalone history matrix uses 151 heap allocations/retirements, 14 ordinary
acquisitions/165 releases and 165 hold pairs. The five added publication probes
use 40 allocations/retirements, 13 acquisitions/53 releases and 47 hold pairs.
The five boxed-writeback cases use 35 allocations/retirements,
27 acquisitions/62 releases and 32 hold pairs. Arena allocations are counted
separately in the raw records and close before reporting.

The `prototype-*` receipts preserve the 12/13 intermediate result before physical
helper retention. `pre-role-fix.json.gz` preserves the optional-text failure
found in broader tests; `loan-role-trace.log.gz` records the stale loan cleanup.
`role-fix.json.gz` includes its corrected GC/RC/backend matrix. The final `guests`
and `standalone` records name the final frozen compiler. Historical results are
not included in final pass totals.

Replay the focused guests or unaccounted fixture matrix from this checkout:

```sh
python3 experiments/d9-rc-semantic-lowering-20260926/guest-driver.py \
  --compiler /path/to/mylang --output /path/to/guest-evidence
python3 experiments/d9-rc-semantic-lowering-20260926/standalone-driver.py \
  --compiler /path/to/mylang --output /path/to/standalone-evidence
```

`--release` selects actual LLVM for guest tests; there is no later `--qbe`
override. Native checks used `MYLANG_TEST_ASAN=1 MYLANG_JOBS=3` with the permanent
`python3 scripts/test_native_memory.py` driver. Full integration gates, the whole
native guest corpus and performance acceptance remain the parent's next steps.
