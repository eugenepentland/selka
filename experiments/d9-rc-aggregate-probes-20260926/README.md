# Executing aggregate ownership probes

`run.py` runs the 12 aggregate regressions in `tests/lang/rc_aggregate_values.my`,
15 unchanged optional-layout/propagation tests, and the real assertion failure in
`trap.my`. Each runs through the counted RC CLI with a Debug compiler and a
ReleaseFast guest. The script checks status, output, one statistics record,
unsaturated counters, complete allocation retirement, and balanced owners/holds.

From the repository root, with private on-disk `TMPDIR` and `ZIG_LOCAL_CACHE_DIR`:

```sh
python3 experiments/d9-rc-aggregate-probes-20260926/run.py --backend qbe --compiler zig-out/bin/mylang --workspace .tmp-aggregate/probes-qbe --output experiments/d9-rc-aggregate-probes-20260926/qbe.json
python3 experiments/d9-rc-aggregate-probes-20260926/run.py --backend llvm --compiler zig-out/bin/mylang --workspace .tmp-aggregate/probes-llvm --output experiments/d9-rc-aggregate-probes-20260926/llvm.json
```

The script admits compiler builds through `scripts/build-slot.sh`. The JSON files
retain exact commands, fixture and compiler hashes, every selected case, process
output, and counters. The optional suite excludes only its arena escape case;
that belongs to the later combined arena compiler integration. The trap must exit
1 with `R_ASSERT`; an abort or a missing/imbalanced statistics record fails.
