# S4 integration state

Base: `82c125ddd8eacad35937a6d6cd59c5f11b7ddf3d` (S3 source `d4994214579adb8d1897a40fc65de1462b000939`).
Design merged first at `d449c8f5f`; rows merged second at `d357bbda0`.

S4-0 is qualified on `d357bbda0`: full old gate (3004 tests, 520 QBE tests,
29 QBE build steps, formatting), 277 core tests in 141.91 seconds, uncontended
core rebuild 0.02 seconds, and full debug/release conformance 1518/0/0 with
leak and verify checks. Whole-tree Guardian: 88/88 checks passed.

All 46 rows agree on checksums. The 88/92 timing cells within both gates
and four known S4-V misses are detailed in BASELINE.md. Coverage has all six
corpora, including both pinned ports; synthetic entry stubs are excluded from
real-function totals and explained in BASELINE.md.

S4-R moves the six fixtures to test/core, updates their module headers to match
the new filenames, and keeps all Rust, Zig, Go references and Python oracles.
Post-registration qualification is pending. Wave A, Wave B and S4-X remain pending.
No pushes; no merge into main. `src/core/ir.zig` is frozen.
