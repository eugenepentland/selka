# Frozen S4-P command recipes

Read-only preparation while S4-V's qualification runs. No port source or external
checkout was changed, and no new compiler/port implementation or timing ran.
Use fresh locked owned port worktrees after S4-C and S4-M are integrated.

The Wave 0 compiler source is `a16a324e629c1c68e0180017f6d2faf20364b13d`,
with SHA256 `eb354a1ad3763aa0c3851f6a96eb2bccf2ab0df94a2b983db46bdd0725c34eaf`.
Its executable is
`/home/epentland/.cache/mylang/s4-wave0-20261006/mylang-s4-pin/bin/mylang`.
Keep its baselines and source identities pinned when comparing the new core.

Lox source: `codex/s4-lox-value-semantics` at `f44302d8`. From an owned worktree's
`benchmarks/lox/ports/mylang`, preserve these three invocations (substitute the
compiler executable and private build/test/output paths):

```text
COMPILER build main.my --project -o PRIVATE_OUTPUT --cache-dir PRIVATE_BUILD_CACHE
COMPILER test . --max-steps=100000000 --jobs 1 --cache-dir PRIVATE_TEST_CACHE
COMPILER test driver_tests.my --cases driver_cases.json --max-steps=100000000 --jobs 1 --cache-dir PRIVATE_TEST_CACHE
```

The test total is the sum of both test invocations. Directory discovery also
finds the driver tests; report the second invocation's cached verdicts explicitly.
Cold tests must execute 65 directory tests and 13 explicit provider cases. Preserve
the harness's two engines and normal/gc-stress corpus for the 974 comparisons.
Cold/unchanged/edited build baselines are 7.6569/0.0068/0.1952 seconds; test totals
are 21.9960/0.1451/0.6481 seconds. The one-function edit is `natives.clock_native`:

```text
before:                     return value.Value.number(float(instant.unix_nanoseconds) / 1000000000.0)
after:                      seconds = float(instant.unix_nanoseconds) / 1000000000.0
                            return value.Value.number(seconds)
```

Exact original commands/environments are `experiments/new-core-s4-lox-20261006/baselines.json`
at the frozen port ref. Restore the source bytes in a finally block and compare
all source hashes after the timing edit.

EDA source: `codex/s4-eda-stage1` at `510c2e2`; its functional source is
`276ae3bbfa4130a8448d88534d3059650a6077ea`. The frozen
`experiments/new-core-s4-eda-20261006/old_core_baselines.py` obtains the harness
`Lang("mylang")` build/test commands, with only `--jobs 4` changed to `--jobs 1`
for timing. Preserve the harness configuration, embedded fixtures, map edit anchors
and all output expectations. Check counterpart inventory at 279/279, tests at
310, and golden outputs at 34/34 byte-identical.

EDA cold/unchanged/edited build baselines are 81.1429/0.0165/1.1516 seconds;
tests are 234.5436/1.6549/1.6658 seconds. Edit only `main.parse_args`:

```text
before:     a = Args()
after:      initial_args = Args()
            a = initial_args
```

Cold tests execute 310; unchanged tests reuse 310; the edit executes one and
reuses 309. Restore and check all 121 source hashes afterward. Exact measurements
and expanded command environments are under `stage1-exit/results.json` at the
frozen port ref.

Both timing recipes hold a build slot and then the shared CPU10 flock, exclude
admission time, set affinity to CPU10, and use one test worker. Build/test caches
are separate and initially empty, including frontend/runtime/native/Zig caches.
Use disk-backed private TMPDIR, XDG_CACHE_HOME, ZIG_GLOBAL_CACHE_DIR and
ZIG_LOCAL_CACHE_DIR. Record command, environment, exit status, elapsed time, peak
RSS, compiler/source hashes and per-command executed/cached verdicts. The S4
parallel-build CPU measurements are separate from these serial pinned baselines.
