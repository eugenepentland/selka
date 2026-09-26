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
