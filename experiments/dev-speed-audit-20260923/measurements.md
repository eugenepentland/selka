# Direct measurements, 2026-09-23 (this machine: i7-12700H, 20 threads, 30 GB RAM)

## Guest binaries from a Debug vs a ReleaseFast compiler (same source, 7cd9fb9a / 8a289c96)

| program | Debug compiler build | ReleaseFast compiler build | binaries identical |
|---|---:|---:|---|
| sieve | 1519 ms | 1374 ms | yes |
| nbody | 2443 ms | 1403 ms | yes |
| text_ops | 6220 ms | 4690 ms | yes |
| matmul | 1642 ms | 1585 ms | yes |
| binary_trees | 1684 ms | 1542 ms | yes |

## Building the compiler (clean Zig cache, -j2, ReleaseFast, quiet machine)

- default install (mylang, qbe, board-trial, schematic-svg, mylang-io): 418 s
- `-Dcompiler-only=true` (mylang, qbe): 166 s
- Debug `zig build`, incremental, as agents ran it: 15 s average over 96 runs

## Guest test suite (`mylang test tests/lang`, 106 programs, 569 tests, quiet machine)

| | cold cache | warm cache |
|---|---:|---:|
| plain | 26 s | 4 s |
| `--gc-stress` | 39 s | 1 s |

## Full gate on a clean cache (coordinator's integrate.sh), per step

| gate | `zig build test` | `test-qbe` | other steps |
|---|---:|---:|---:|
| cobuild (quiet) | 202 s | 48 s | 4 s |
| mem2 | 205 s | 47 s | 6 s |
| bugs | 228 s | 53 s | 8 s |
| vecblock | 237 s | 56 s | 4 s |

Whole merge-and-gate runs over the night (24): mean 12 min, range 3–22 min (43 min for
one run that chained two merges); the quiet ones at the end took 3–4 min.

## Commit hook (`guardian-check all . --gate`)

1.3 s cold, about 50 ms cached.

## Largest files agents read repeatedly (lines)

src/sema.zig 6874 · src/qbe.zig 3048 · experiments/llvm-backend/llvm_emit.py 2101 ·
src/native_heap.c 1269 · SPEC.md 1112 · src/qbe_managed.zig 1083 · src/bytecode.zig 805.
386 Zig files under src/, 128,735 lines.

## Rework signals mined from agent transcripts

- Guardian check failures: change-classification 24, line-length 15, spec 10,
  bool-ops-per-condition 8, repeated-string-literal 8, error-path-test 7,
  cognitive-complexity 5, nesting-depth 5, formatting 4, others 6.
- 48 results mention the memory ceiling (OOM / MemoryMax); 17 `/tmp` DiskQuota failures;
  17 Zig compile errors.
- 80 explicit `zig build … -Doptimize=ReleaseFast` invocations across 16 agents (max 16 in
  one lane), 201 release-build/install commands in all counting wrapper scripts.
