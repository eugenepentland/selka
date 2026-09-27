# Private cumulative RC/GC instruction diagnosis

Source revision: `7fc669a7`. Read the corresponding audit report for scope,
proof boundaries and sampling limitations. This is not corpus acceptance.

`gap.json` records three interleaved original n12 runs per mode/backend, exact
output verification, RC counters, manifest checks, commands and hashes.
`gap-analysis.json` records static constructor sizes and separately derived
invocation/store counts. Its `profile_repeat` block is the final PC partition;
the earlier `sample_*` fields are retained scratch observations, not used for
the report's final profile attribution.

The profiling-only source calls the same complete n12 workload 240 times in
one process. Its output was checked against 240 copies of the original output.
GC can collect between iterations; these profiles locate work and do not
replace the original n12 performance controls. Weighted instruction samples,
sampling metadata and disassembly are retained in compressed text.

The helper scripts were copied from the isolated worktree's scratch directory.
Their relative directory is expected to contain `install-gap/bin/mylang` and
`rc-n12.stdout`; the exact original absolute commands are in the JSON files.
Build compilers in Debug through `scripts/build-slot.sh build` with a separate
Zig cache and on-disk TMPDIR. The guest backends are selected without a later
`--qbe` flag, and every manifest is checked before measurement.
