# The build loop — 23–24 September 2026

**Asked:** fix the build loop first. Recommendation 1 of the
[development-speed audit](development-speed-2026-09-23.md) says every binary-producing
command must scale with the edit, not the project. Its acceptance rules:

- 50k no-op build ≤ 0.3 s;
- 50k edit → build ≤ 1 s;
- 200k builds under the default memory ceiling, with edit → build ≤ 3 s;
- 50k cold build ≤ 30 s.

This is the first of three gates for the claim that mylang beats Go on large codebases.

**Result.** Every acceptance rule is met on `devspeed/integration` 183251a9.
- mylang now beats Go on `test` after an edit at every tier, and matches Go on `check` at 50k.
- It beats Rust and Zig on build after an edit at 50k and 200k.
- It still trails Go on build after an edit (2.7× at 50k, 5.7× at 200k), on cold build (2.6–3×) and on memory.

## Where it stands

The same generated project exists in all four languages (`gen_scale.py`, structure per
language identical). Steps are timed on the P-cores (`taskset -c 0-11`); each figure is the
minimum of 3 samples, 5 for the 200k mylang and Go rerun. The mylang compiler is a
ReleaseFast build of 183251a9, and `mylang build` is used as a user types it. The *audit*
column is `main` 35fcbc02 on 23 September, `--mode Debug`. All figures are seconds.

**50k tier** (51,043 mylang lines; Go and Rust 70,006, Zig 78,766 for the same program):

| Step | audit | **mylang** | Go | Rust | Zig |
| --- | --- | --- | --- | --- | --- |
| cold build | 509.6 | **5.18** | 1.75 | 3.78 | 0.69 |
| no-op build | 6.28 | **0.050** | 0.028 | 0.012 | 0.677 |
| edit → check | 0.77 | **0.103** | 0.101 | 0.432 | 0.357 |
| edit → build | 6.92 | **0.367** | 0.136 | 0.616 | 0.614 |
| interface → build | 9.81 | **0.429** | 0.151 | 0.665 | 0.678 |
| edit → test | 2.62 | **0.304** | 0.978 | 0.542 | 0.310 |

**200k tier** (204,043 mylang lines; about 280k Go/Rust, 315k Zig). mylang and Go are from
the 5-sample rerun at load 1.9. Rust and Zig come from the first pass, taken at load 5–7
while a differential run occupied the E-cores.

| Step | audit | **mylang** | Go | Rust | Zig |
| --- | --- | --- | --- | --- | --- |
| cold build | out of memory | **21.8** (1.9 GB) | 8.38 (145 MB) | 18.2 (1.5 GB) | 2.14 (432 MB) |
| no-op build | out of memory | **0.198** | 0.064 | 0.017 | 3.36 |
| edit → check | 3.33 | **0.455** | 0.287 | 1.97 | 0.967 |
| edit → build | out of memory | **1.62** | 0.283 | 2.76 | 2.31 |
| interface → build | out of memory | **2.23** | 0.305 | 3.09 | 2.71 |
| edit → test | 21.3 | **1.30** | 4.74 | 2.24 | 0.446 |

**10k tier:**

| Step | audit | mylang | Go | Rust | Zig |
| --- | --- | --- | --- | --- | --- |
| cold build | 35.0 | 0.98 | 0.40 | 1.12 | 0.29 |
| edit → build | 1.13 | 0.098 | 0.099 | 0.153 | 0.297 |
| edit → test | 0.62 | 0.084 | 0.244 | 0.147 | 0.259 |

**A real codebase.** The Lox interpreter port has 4,182 non-blank lines and 9 test
programs (`lox_loop.py`). The edit is a function body in `heap.my`, which the VM, compiler
and tests import. Minimum of 5 samples:

| Step | 5c150f02 (before) | 183251a9 (after) |
| --- | --- | --- |
| cold build | 9.47 | 0.452 |
| no-op build | 0.323 | 0.011 |
| edit → build | 0.370 | 0.098 |
| edit → check | 0.055 | 0.018 |
| cold `test` | 4.71 | 0.930 |
| edit → `test` | 0.115 | 0.065 |

## What landed

Five lanes, each gated by its author and again by the integrator on empty `.mylang-cache`
directories before merging. Each lane has its own report next to this one.

| Lane | What it changed | Report |
| --- | --- | --- |
| defaults-and-docs | QBE is the default backend in every mode; `--release` means LLVM `-O3` + LTO | `devspeed-defaults-and-docs-2026-09-23.md` |
| codegen-throughput | Tools start with `clone(VM\|VFORK)` instead of forking a 900 MB driver twice per function. One QBE run and one assembler run per module batch, in parallel. Per-batch metadata objects. Cold 50k: 527 → 8.5 s | `devspeed-codegen-throughput-2026-09-23.md` |
| build-frontend-reuse | Per-function QBE unit reuse; lean manifests (8.7 MB instead of 152 MB at 50k); replay of unchanged projects; a build receipt that makes a no-op return before parsing; bounded driver memory, which is what made 200k build | `devspeed-build-frontend-reuse-2026-09-23.md` |
| check-at-scale | Per-function check summaries stand in for unchanged bodies: one edit re-checks 2 bodies, not 3,686. Each module is lexed once. Linear effect passes. Transitive dependency keys and touched-shape digests (see below) | `devspeed-check-at-scale-2026-09-24.md` |
| test-loop-scale | Tests run in parallel with the cheap spawn. Test planning is no longer quadratic. A stable snapshot path, so the caches hit. Test facts are scoped to the tests' closure. The harness compiles once | `devspeed-test-loop-scale-2026-09-24.md` |
| build-residue | Only changed functions are lowered and emitted (stand-ins keyed by checked source identity). Relinks go to `zig ld.lld` directly. BLAKE3 object keys. A leased fragment-store sweep. `--drop-debug` now works on project builds | `devspeed-build-residue-2026-09-24.md` |

Each lane added a test that counts work (bodies re-checked, units lowered, tests rebuilt,
processes started) rather than wall time, so the gains cannot silently regress. One small
integrator commit raised the compile-step memory bound, because the ReleaseFast compiler
now peaks at 3.3 GB (fc742bd4).

## Correctness: a false "all clear", found and fixed

Incremental work is only a speed-up if it gives the same answer as a cold run. Two
differential harnesses test that on random edits of the Lox port.
- **Check:** `check_diff.py` warms a cache on the clean project, applies one or two random edits (rename a field, def or parameter; change a type; drop `mut`; un-public a def; a type error; a no-op line), and compares cached `check` against `--no-cache` byte for byte.
- **Build:** `build_diff.py` builds incrementally and from scratch after compilable edits (literals, operator flips, record field reordering, added functions, no-op lines), then runs both executables on 33 Lox scripts × 2 engines.

**Found.** 9 of 300 check edits differed, all field renames. Reduced to three files, the bug
is this: a function that reaches a record only through another record's field type
(`o.items[0].x`, where `items: list[Inner]`) was not re-checked when `Inner` changed.
- **Effect:** after renaming `Inner.x`, cached `check` passed while a cold check reported `E_UNKNOWN_FIELD`. Before this work, cached `build` also succeeded and linked a program from the stale check.
- **Cause:** `list[Inner]` and the other composite spellings contributed no dependency at all. Record declarations were not fingerprinted by their own text. Recursive types fingerprinted differently depending on keying order. Re-exported names did not resolve.
- **It predates the lanes:** the `fc742bd4` baseline behaves the same.

**Fixed** (check-at-scale c9fde868) with two independent guards:
- **Transitive keys:** declaration fingerprints cover everything reachable from the declaration, cycles included.
- **Touched-shape digests:** every checked body records a digest of each record it actually touched, and is re-checked when one differs.

**After the fix:**

| Harness | Edits | Mismatches |
| --- | --- | --- |
| `check_diff.py`, seed 23, Lox | 300 | 0 |
| `check_diff.py`, seeds 7 and 11, Lox (lane agent) | 300 each | 0 |
| in-repo `zig build test-incremental`, 6 seeds | 2,400 | 0 |
| `build_diff.py`, seeds 5 (partial) and 6, Lox | 209 | 0 (all built; about 13,800 script runs compared, 34 of the edits reordered record fields) |

A bounded version of the check harness is now part of `zig build test`:
`tests/incremental_diff.py` with the fixture in `tests/fixtures/incremental/`.

## Where mylang still trails Go, and what would close it

Go rebuilds a 280k-line program in 0.28 s after an edit and cold-builds it in 8.4 s in
145 MB. The remaining costs, measured by the build-residue and test-loop lanes, ranked by
what they are worth at 200k:

1. **`build` still checks every body** (0.34 s at 200k). `check` already skips unchanged bodies. `build` cannot yet, because the summaries do not carry the types and generic instantiations a body creates, and lowering needs them. The design is in the build-residue report.
2. **The link scales with the program** (0.28 s at 200k). `ld.lld` writes a 130 MB executable and an 8.4 MB manifest sidecar on every relink. Shrinking the executable (what fills 130 MB?) or linking incrementally would help.
3. **Interface edits in the default mode:** interface → build is 2.23 s at 200k in the default mode against 1.58 s with `--mode Debug`, while body edits cost the same in both. Not yet explained.
4. **Whole-program driver bookkeeping** (about 0.12 s at 200k), and a first no-op after a cold build that still does work (0.1–0.4 s).
5. **Cold build:** 2.6× Go at 200k (21.8 s against 8.4 s). Memory is 13×: 1.9 GB against 145 MB. The smaller batches that make edits cheap cost about 6% of cold time.
6. **First `test` after a cold run:** the test library's generated C wrapper is recompiled with `zig cc` each time the affected set changes (0.55 s at 200k).
7. **A build differential in the gate.** The check harness is in `zig build test`; the build harness (`build_diff.py`) is not yet, because it needs a compilable fixture with observable behaviour.

Items 1–2 would bring 200k edit → build to roughly 1 s. Matching Go's 0.3 s needs a
per-module compilation model in which a body edit touches one object and a relink that
does not rewrite the whole executable.

## What this does not show

- **Load:** the machine was shared. Loads are recorded per run in `results/ladder.log` and in each lane report. The 200k Rust and Zig rows were taken at load 5–7.
- **Project shape:** the generated ladder is a chain of modules with identical functions. Real codebases have more coupling, so the Lox rows are the better guide for small projects. No real 100k-line mylang codebase exists yet to measure.
- **Scope:** only the build loop is covered. The other audit recommendations remain paused on their branches: test capabilities, `mylang fix`, expression fidelity, navigation tools, and the velocity harness.

## Reproduction

The scripts and raw results are in `experiments/build-loop-20260924/`:
- `gen_scale.py` and `run_scale.py`; `run_scale.py` reads `MYLANG_BIN`;
- `lox_loop.py`, `check_diff.py` and `build_diff.py`;
- the ladder JSON, the harness logs, and `ladder.log` with loads.

```bash
python3 experiments/build-loop-20260924/gen_scale.py t50k 120 38
MYLANG_BIN=/path/to/mylang python3 experiments/build-loop-20260924/run_scale.py t50k --langs mylang,go,rust,zig
```
