# S4 caching spike, 2026-10-06

Evidence for `docs/audits/new-core-s4-plan-2026-10-06.md` §3. Branch
`claude/new-core-s4-design`, from S3's Wave B base `8918de74`. Results and their
reading are in the plan; this file says how to rerun them.

| File | What |
|---|---|
| `gen_program.py` | Synthetic multi-file projects: `gen_program.py N DIR [--edit K] [--grow K] [--helper K]` |
| `phases.py`, `phases.json`, `phases.out` | §3.1: check, LLVM `-O0`/`-O3`, link, and the core's own work by subtraction (the own-work column in the plan comes from `strace -f -e execve` instead, because the subtraction is noisy) |
| `split_ll.py` | Splits one emitted `.ll` into per-file codegen units; `--normalize` renumbers constants, metadata and trap sites per unit |
| `units.py compile N…`, `units-compile.json`, `units-compile.out` | §3.2: per-unit compile times, link, run, output comparison |
| `units.py ripple N K`, `units-ripple.json` | §3.3: units changed by three kinds of edit, raw and normalized |
| `focused-*.log`, `test-core.log` | Tests of the `CATALOG-INTERN-1` front-end fix |
| `build-*.log` | The ReleaseFast compilers the spike used |

Rerun (from this directory; binaries under `.mylang-cache/s4/`, built with
`scripts/build-slot.sh build -- zig build core -Doptimize=ReleaseFast --prefix
.mylang-cache/s4/rf`):

```bash
python3 phases.py 120 1200 4800
python3 units.py compile 1200 4800
python3 units.py ripple 1200 650
```

Timed commands are pinned with `taskset -c 10`; `zig cc` runs get a fresh local
cache, and the global cache (libc, compiler-rt) stays warm. The 4800-module project
needs `phases.py` first (it generates `syn4800`).
