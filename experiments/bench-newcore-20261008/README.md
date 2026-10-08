# Benchmarks rerun on the new core, 2026-10-08

All three runs used one ReleaseFast compiler built from `main` 5a6b501d (`~/.cache/mylang/bench-newcore-5a6b501d/bin/mylang`) and the same Zig, Rust and Go versions as the September runs. Runtime timing was pinned to CPU 10 under `cpu10.lock`; build timing ran serialized under `bench-compile.lock` through `scripts/build-slot.sh`.

| run | result | report |
|---|---|---|
| Parity suite (27 programs) | **Done.** Geomean 1.22× Zig ReleaseFast (old core 1.18×). Median 1.07× (old 1.17×). nbody (8.97×) and str_build (4.21×) regressed. | `parity/REPORT.md` |
| EDA stage 1, all four languages | **Done.** Runtime: 1.82× Zig ReleaseFast, 1.65× Rust, 0.67× Go. Check after an edit is the fastest of the four; tests after an edit are the slowest. | `eda/REPORT.md` |
| Lox interpreter | **Blocked.** Appending to a list field of a `mut` record parameter copies the list, so the interpreter is quadratic. No numbers were taken. | `lox/REPORT.md` |
