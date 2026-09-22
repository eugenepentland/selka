# Full SVG arena experiment

The [combined language comparison](../../docs/audits/real-arena-regions-2026-09-21.md#rust-go-and-zig-comparison)
adds Rust, Go and the direct Zig port to the final GC/arena builds. All 12
configurations were timed together; the earlier arena-only results below are
retained in `measurements.json`.

This experiment compares the current production schematic guest under tracing GC with a source-identical variant whose `main` body is enclosed by one existing `with arena():` scope. The only SVG guest source difference is recorded in `arena-source.diff`; frozen copies live under `.tmp/svg-arenas-20260921/guest-{gc,arena}`.

`run.py build` creates LLVM O3, O3+LTO, bounded, and bounded+LTO binaries for both sources using one compiler/runtime revision. `run.py qualify` checks all three frozen SVG cases, geometry, GC stress, malformed/index-sensitive inputs, and step/frame budget traps. `run.py evidence` records compiler/runtime/source hashes and emitted arena/GC/frame call sites. `run.py measure` performs 31 seeded, randomized, interleaved fresh-process rounds on CPU 6 against retained EDA NetLisp. **Do not run `measure` until the final L4 runtime is installed and qualified.** Re-run `build`, `qualify`, and `evidence` after any runtime installation so static linking cannot retain an earlier allocator.

Every execution sets `MYLANG_MEMORY_LIMIT=268435456` explicitly for both GC and arena policies. `run.py build` refreshes both guest trees from current production source, asserts only `main.my` differs, and saves both entry sources here. It requires the frozen fixture tree and retained NetLisp binary from `experiments/full-svg-benchmark`; run `python3 experiments/full-svg-benchmark/prepare_fixtures.py` and its NetLisp build procedure first when those assets are absent.

The companion `gc.my`/`arena.my` workload allocates 64 batches of 96 nested lists with 64 integers each and reduces every batch to a scalar. Its arena arm releases each allocation-heavy batch at scope exit. This distinguishes a working bulk-release path from the SVG case, where nearly all model/layout objects naturally remain live until the single render completes. `run.py workload-build`, `workload-qualify`, and eventually `workload-measure` manage this control. `zig_allocation_control.zig` repeats the same shape using explicit per-object frees through Zig's page allocator versus one `ArenaAllocator` per batch; it is an allocation control, not a schematic or language-performance comparator.

After building and qualifying, `python3 build_stats.py` copies and hash-verifies the current runtime sources, adds `heap_stats_runtime.c` instrumentation, builds a private runtime archive, and relinks the exact guest objects; `python3 collect_stats.py` records non-timed GC allocation/collection counts, arena allocations/chunks, charged-byte peaks, and proves `arena_chunks_live == 0` after every fixture and stress run. These probes never alter production runtime sources.

The final timing outputs were produced only after the final runtime installation and qualification. Qualification and timing use private output files and compare full stdout, stderr, issue bytes, and SVG bytes where applicable.

## Final results

The final specialized runtime removes the earlier arena bookkeeping regression. On the fixture, arena/GC ratios are 1.009 for O3, 1.005 for LTO, 1.013 for bounded O3, and 0.995 for bounded LTO; every paired-bootstrap interval includes 1.00. Changed inputs range from 0.980 to 1.024, with only the changed-net unbounded arms showing a small measured slowdown. The allocation-heavy control is different: its arena median is 6.170 ms versus 7.238 ms for GC, ratio 0.852.

The exact non-timed stats use a private copy of current production runtime sources. `build_stats.py` hash-compares every copied runtime translation unit with `src/`, injects observation immediately after each charged allocation and an exact report after guest entry returns, builds a fresh private runtime archive, and relinks unchanged guest objects. It does not modify production. The SVG fixture performs 134 logical allocations in either policy; GC retains 301,000 charged bytes at exit, while the arena uses three chunks, releases all 134 allocations, and leaves zero charged bytes and zero live chunks. The allocation control performs exactly 37,312 allocations in either policy; GC triggers three collections and peaks at 4,318,528 bytes, while the arena peaks at 196,608 bytes and releases all allocations across 128 chunks.

Final reproducible commands, run sequentially after the ReleaseFast install, were:

```text
python3 -B experiments/svg-arenas-20260921/run.py build
python3 -B experiments/svg-arenas-20260921/run.py qualify
python3 -B experiments/svg-arenas-20260921/run.py variants
python3 -B experiments/svg-arenas-20260921/qualify_memory.py
python3 -B experiments/svg-arenas-20260921/run.py evidence
python3 -B experiments/svg-arenas-20260921/run.py workload-build
python3 -B experiments/svg-arenas-20260921/run.py workload-qualify
python3 -B experiments/svg-arenas-20260921/build_stats.py
python3 -B experiments/svg-arenas-20260921/collect_stats.py
python3 -B experiments/svg-arenas-20260921/run.py measure
python3 -B experiments/svg-arenas-20260921/run.py workload-measure
```

## Rust, Go and Zig charts

`native-builds.json` records the existing ports' source/binary hashes, compiler
versions and optimization flags. `native-qualification.json` rechecks all 12
binaries against the three frozen SVG fixtures; the Rust, Go and direct Zig
ports reproduce mylang's exact output. NetLisp remains a separate engine with
different SVG output. No port or production runtime source was changed for this
comparison. The direct Zig port uses `init.gpa` for its pipeline; Rust uses
ordinary owned vectors, Go uses its default GC, and NetLisp uses a process arena.

`native-measurements.json` contains 1,116 checked timings: 12 configurations ×
three cases × 31 measured rounds, plus three warmup rounds. Every configuration
is shuffled into the same run, pinned to CPU 6, with the existing fresh-process
boundary. The 256 MiB managed memory budget applies only to mylang. Go runtime
overrides (`GOGC`, `GOMEMLIMIT`, `GODEBUG`, `GOMAXPROCS`) are cleared so defaults
apply. This is an application comparison: native ports use bulk document I/O,
and allocation, checks and internal optimizations differ between implementations.

The original-circuit inline comparison includes Rust and Go alongside the LTO
GC/arena configurations and both Zig implementations. `charts.py` exports all
12 configurations across all three cases to PNG and SVG under
`docs/audits/figures/full-svg-gc-arena-native-2026-09-21.*`. No older timing or
RSS samples are mixed into these figures.

Reproduce using the retained qualified binaries (build missing ports with
`experiments/full-svg-benchmark/build_native.py` first):

```text
python3 -B experiments/svg-arenas-20260921/run.py native-qualify
python3 -B experiments/svg-arenas-20260921/run.py native-measure
MPLCONFIGDIR=$PWD/.tmp/mplcfg /home/epentland/ai/canopy/rust-workflow/.venv/bin/python experiments/svg-arenas-20260921/charts.py
```
