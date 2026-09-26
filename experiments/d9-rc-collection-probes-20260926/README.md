# Actual RC collection guest execution

These probes compile and run existing guest test bodies through the experimental
`--rc-runtime=stats` CLI lane. The compiler is Debug; guests use ReleaseFast on
both QBE and LLVM. Each process has a 512 MiB managed-memory ceiling.

`run.py` copies each source into a temporary module and generates a driver that
calls every public test and prints a failure bitmask. The test bodies and effect
annotations remain unchanged. The text-view module is cut before its arena
escape helper: arena escape has a separate integration workstream. The script
checks zero failures, one unsaturated statistics record, complete heap retirement,
and `heap_allocate + owner_acquire == owner_release`. It retains source hashes,
case names, output, counters, and the compiler hash in the JSON evidence.

Build a Debug compiler using the project build slot, then run each backend:

```sh
python3 experiments/d9-rc-collection-probes-20260926/run.py \
  --compiler zig-out/focus/bin/mylang --qbe zig-out/focus/bin/qbe \
  --backend qbe --workspace .tmp/rc-repro-probes \
  --output experiments/d9-rc-collection-probes-20260926/qbe.json
python3 experiments/d9-rc-collection-probes-20260926/run.py \
  --compiler zig-out/focus/bin/mylang --qbe zig-out/focus/bin/qbe \
  --backend llvm --workspace .tmp/rc-repro-probes \
  --output experiments/d9-rc-collection-probes-20260926/llvm.json
```

Set the worktree's `ZIG_LOCAL_CACHE_DIR` and disk `TMPDIR` in the environment as
usual. The script runs every native build through `scripts/build-slot.sh`.

The basic group covers 13 list/dictionary/text/bytes guest cases. The views group
covers six byte-view cases and seven text-view cases, including repeated 1 MiB
receiver churn within the 512 MiB ceiling. The wide group covers 13 Python-byte
cases, eight mutable-byte-buffer cases, and 18 keyed-sort cases. The six-case
regression fixture exercises nested list mutation, dictionary owned results,
allocated sort keys, set pop, identity text conversion, and detached nested views.

These are focused RC execution probes, not the full gate or WP-4 acceptance.
Pinned callback scopes, arena escape, and generic aggregate construction require
their corresponding integration evidence.
