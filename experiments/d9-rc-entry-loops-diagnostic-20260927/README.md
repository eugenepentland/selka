# Combined 31-program diagnostic

Frozen source is `4e5c0cd638e55b86ef0d99112872e02ae41dbe89`. This set contains
the unchanged 27 parity workloads, three complete schematic SVG workloads,
and Lox VM binary-trees at its unchanged N10 size. The other twelve Lox
workloads are excluded. Results cannot establish final 43-program acceptance.

The Debug compiler is the immutable `install-entry-loops` prefix recorded in
`identity.json`. The driver requires integration's ready marker and exact hash
receipt before building or measuring. All accepted GC executables are reused
and hashed; no baseline compiler, source, binary or previous receipt changes.

Run `python3 run.py build`, then `python3 run.py measure`. The phases are
separate so source/compiler identity can be reviewed before timing. Heavy
builds use two workers behind the shared build-slot gate, isolated native cache
and TMPDIR. Measurements are serial on CPU11. Instructions and peak RSS each
use three independent executions per side; instrumented ownership counts use
separate binaries. Actual LLVM manifests require O3 and full LTO. Workloads,
exact output/SVG checks and expected files come from the unchanged mandated
harness, which is hashed as an input.

`python3 verify.py` checks the completed compressed receipts without rerunning
benchmarks. `--live` also hashes the original installed compilers, sources and
native executables. To inspect an active run use `--results` with its absolute
`results.json` path. Verification intentionally requires completion; partial
progress is not silently promoted to evidence.

The report provides a 31-program summary and a separate 30-program summary
comparable to the earlier joined diagnostic. Historical RC results used CPU2;
those medians are identified separately from the new paired CPU11 GC/RC
measurements. Each current row reports its remaining reduction to the 1.3×
limit. Raw instruction events must show exactly 100% running.
