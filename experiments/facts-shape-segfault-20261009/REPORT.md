# The one-time Debug segfault in `facts.shape`: not reproduced (2026-10-09)

**Who.** An opus-lane agent investigated this in worktree `claude-fix-facts-shape`. The coordinating Claude session wrote this file from the agent's final report. No code changed.

**The crash.** It happened once, in `zig build test` on `claude/fix-row-cow` `beb95a978`, in the step that runs `mylang test tests/ported --release --verify-facts`. The log is `experiments/fix-row-cow-20261009/gates/zig-build-test-beb95a978.log`, around line 260:

```
Segmentation fault at address 0x7976087d6dac
src/core/facts.zig:220:35 in shape: @memset(order, std.math.maxInt(u32));
src/core/fuse_text_split.zig:24:42 in run
...
src/core/test_runner.zig:315:20 in runGroup
```

## What the fault shows

**The memset is inline and the first store faulted.**
- In the Debug binary of `b51a43b76` (now `facts.zig:221`), the memset compiles to a `movl` followed by `rep movsb`, with no call.
- The fault address is not page-aligned, at page offset `0xdac`.
- So the very first store to `order.ptr` faulted, rather than the copy running off the end of a mapping. The arena returned a pointer into a page that was not mapped.

**The count is not the cause.** `visited`, with the same count, was memset successfully just before.

**One thread owns that arena at that point.** It is `test_runner_directory.zig` `Worker.inProcess`'s per-root arena. Its threaded users start after `pipeline.emitted`, and they are joined.

**Remaining explanations:**
- a stray write or a stale pointer into a large mapping that was later reused for the arena's node;
- a rare bug in the Zig dev std's arena or `SafeAllocator`.

Nothing in mylang's code was found to do this.

## Ruled out, with evidence

| hypothesis | evidence |
|---|---|
| stack overflow | The frames on the crash path total about 110 KiB, against a 16 MiB thread stack. `shape` does not recurse. |
| address-space limit or memory pressure | `mylang test` restores an unlimited `RLIMIT_AS` (`src/core/cli.zig` ~206). The suite passes with host limits from 3G down to 10M. The journal has no OOM or MCE entries; earlyoom reported 21.5 of 25.5 GB available at the time. |
| garbage length | `visited` used the same count and succeeded. |
| data race in mylang code | A ThreadSanitizer compiler (temporary `build.zig` switch, since reverted) passed 60 runs with zero reports. About 16 of 20 roots ran in-process on worker threads. |
| std allocators under stress | A shared lock-free arena with 8 threads × 400 rounds, and 24 arenas over one `SafeAllocator` for 8.4 minutes, ran with no fault. |

## Reproduction attempts

All runs: `tests/ported --release --verify-facts` with `MYL_CORE_LEAKCHECK=1`.

| setup | runs | failures |
|---|---:|---:|
| Fresh cache | 200 | 0 |
| `MYLANG_JOBS=16` squeezed onto 2 CPUs | about 86 | 0 |
| Warm cache, two binaries alternated | about 134 | 0 |
| 3 parallel loops plus `tests/value_semantics`, machine load 24–37 | 160 | 0 |
| TSan build | 60 | 0 |

## If it happens again

- **Keep the crashing compiler binary and the log.** Core dumps are not captured: Zig's handler aborts, and `coredumpctl`, gdb and valgrind are not installed.
- **Capture `/proc/PID/maps` at the fault** by enabling core dumps, or by adding a temporary maps dump to the panic handler.

## Found on the way

**A ReleaseSafe build of the compiler hangs on every `mylang test`.**
- It spins in `memory_budget.available`, in `std.Io.Dir.readFile("/proc/meminfo")`: `preadv` returns 0 forever.
- Debug and ReleaseFast builds are fine.
- Filed as a separate task.
