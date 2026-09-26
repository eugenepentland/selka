# RC arena ownership probes

`run.py` builds and executes arena, pending-receiver, and real trap groups with
the selected backend and RC counting enabled. Every process must balance heap
allocations/retirements, owner tokens and holds. It also checks the expected
trap diagnostic. The compiler must be a Debug build.

```sh
python3 experiments/d9-rc-arena-probes-20260926/run.py \
  --backend qbe --compiler zig-out/bin/mylang \
  --workspace /path/to/private/probe-workspace --output /path/to/qbe.json
```

Repeat with `--backend llvm`. Guest builds use `scripts/build-slot.sh` and an
isolated cache under the supplied workspace. `qbe.json` and `llvm.json` preserve
the completed execution evidence for implementation `ab3bf7f1`.

Capability producer follow-up: `capabilities.py` uses the same Debug compiler
and counting ReleaseFast guests to run eight repetitions of the three original
capability leak cases, then invalid UTF-8 on the second line of `readlines()`.
QBE records 360 allocations/retirements for success and 3/3 for the trap.
`capability_budget.c` directly exercises environment-name construction with 33
heap budgets. Strict C plus ASan/UBSan passes 17 refusals (4 after partial
construction) and 16 successes, each with no live objects or temporary roots.
Compile it with `MYL_NATIVE_RC=1`, `MYL_NATIVE_RC_COUNTING=1`, function/data sections
and linker garbage collection, linking qbe_providers.c, qbe_stand_ins.c and the
production native runtime sources. Its small runtime error mocks keep refusal
returns observable without longjmp.
