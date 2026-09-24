# The LLVM backend in Zig — 24 September 2026

Branch `devspeed/llvm-zig`, from `main` `fd36abc2`, with `devspeed/integration`
merged twice (`126a2b84` as `e32fd56c`, then `ae5c9fd0` with scale-limits as
`8a4cd746`). Head and gate: see [Gate](#gate).

## Summary

- **No Python builds, compiles or uses mylang any more, `--release` included.**
  The QBE-IL → LLVM-IR translator that was `experiments/llvm-backend/qbe_llvm.py`
  (with `llvm_emit.py`, `runtime_signatures.py`, `amd64_sysv.py` and
  `sticky_loops.py`) is now `src/qbe_build_llvm*.zig`, run in process on worker
  threads. `zig build` installs no `.py`, the compiler resolves no adapter, and
  `--llvm-adapter` and `MYLANG_LLVM_ADAPTER` are gone. With no `python3` on
  `PATH`, `mylang build --release`, the executable it writes and
  `mylang run --release` work (`USE-WITHOUT-PYTHON-1`, and by hand on a
  ReleaseFast install below).
- **Byte-identical output.** Every unit the release path builds for
  `tests/lang`, `bench/parity`, the Lox port (program and tests) and the
  10,000-line ladder — 2,906 units — gets the same IR from the Zig translator as
  from the retired adapter, under three `PYTHONHASHSEED` values; the adapter's
  own 114-case unit-test corpus is a Zig test; and all 71 bench-parity mylang
  binaries are byte-identical to the ones `main` `fd36abc2` builds with the
  Python adapter. Runtime performance is therefore unchanged by construction.
  There was no unavoidable difference to justify.
- **Build time.** A cold `--release` build of the 50,000-line ladder went from
  326 s to 91 s, and an edit → build from 115 s to 61 s. The 200,000-line
  ladder, which did not finish in 30 minutes on `main`, builds in 398 s cold at
  7.1 GB. What is left is full LTO: one merged module optimized on one thread,
  62 s of the 50k build and 265 s of the 200k one.
- **ThinLTO** is added as `--lto=thin` (`LLVM-THINLTO-1`): 50k cold 68 s,
  edit → build 38 s; 200k cold 207 s at 3.5 GB, edit → build 132 s. It is 1.7%
  (checked) and 3.1% (unchecked) slower in the bench-parity geometric mean and
  up to 26% slower on single programs, so **`--release` keeps full LTO**. The 200k target (≤ 5 min) is met
  with ThinLTO only; the 50k target (≤ 60 s cold) is met by neither on this
  loaded machine (91 s full, 68 s thin).
- Making ThinLTO correct turned up a latent frame-map hazard that full LTO
  shares: LLVM can fold copies of a callee inlined at different call sites into
  one block whose call site is lost. The ThinLTO link turns the two folding
  passes off; full LTO is unchanged and has not hit it on any corpus program
  (see [Risks](#risks-and-follow-ups)).

## 1. What was built

| file | lines | what it holds |
| --- | ---: | --- |
| `src/qbe_build_llvm_il.zig` | 1,119 | IL parser (Python `int(x, 0)` and float `repr` rules kept), per-function preparation, type inference |
| `src/qbe_build_llvm_classes.zig` | 794 | memory classes (frame/foreign/object/element), overflow-formula matching, the frame map's probes and MD5 GUIDs, Cooper–Harvey–Kennedy dominators |
| `src/qbe_build_llvm_emit.zig` | 885 | the emitter: slots, constants, scoped alias metadata, AMD64 SysV aggregate ABI, call-site declarations |
| `src/qbe_build_llvm_lower.zig` | 666 | module, globals, declarations and per-instruction lowering |
| `src/qbe_build_llvm_sticky.zig` | 1,372 | loop versioning of reductions and sticky overflow checks (`LLVM-STICKY-REDUCTION-1`) |
| `src/qbe_build_llvm_runtime.zig` | 407 | the runtime helper registry: curated table, generated shapes, headers and Zig `@export`s of the bundled runtime |
| `src/qbe_build_llvm.zig` | 104 | public surface: `translate`, `header`, `referencedSymbols`, the translator identity and switches |
| `src/qbe_build_llvm_compile.zig` | 437 | the build: closure signatures, worker pool, one `clang -cc1` per unit, failures in unit order, `MYLANG_LLVM_DUMP` |
| `src/qbe_build_llvm_thin.zig` | 213 | the ThinLTO link |
| `src/qbe_build_llvm_test.zig` | 199 | golden corpus, refusal, registry, literal and command-line tests |

How a build uses it (`LLVM-ZIG-1`):

1. The units that missed the object cache are the only ones read. Before any
   worker starts, the build reads the header of each miss and of every unit a
   miss names by `$symbol`, so a call site declares its callee from the
   callee's own header whatever order the workers finish in. This replaces the
   adapter's per-build `--signatures-only` pass and signature sidecar.
2. Worker threads, as many as the cores and free memory allow, take units off a
   shared index. Each translates its unit in its own arena, writes the module to
   a private scratch directory and runs one `zig clang -cc1 …` taken once per
   build from `zig cc -###` for the same flags. Under LTO clang writes the
   bitcode object; without LTO it writes assembly that is annotated for the
   frame map and assembled. The first failure stops new work; every failure is
   reported in unit order after all workers stop.
3. Each object is keyed by the unit text, the driver identity (which covers
   `src/qbe_build*.zig`, so the translator's source) and the translator
   identity `mylang-llvm-translator-v1`, suffixed with every switch that is off
   (`MYLANG_QBE_LLVM_ALIAS`, `_ELEMENT_GEP`, `_STICKY` = `0`).
4. The link is unchanged for full LTO: `ld.lld --lto-emit-asm` to one assembly
   file, annotated, assembled and linked natively with libunwind. Since the
   scale-limits merge the `ld.lld` command and the final link both go through
   response files.

**Batching clang.** One `-cc1` process compiles one module, and each unit must
stay its own object for the per-function cache, so units cannot share a clang
start without merging modules first (Zig bundles no `llvm-link`). The start is
also small: an empty module costs 8 ms against 39 ms for an average 10k-ladder
unit at `-flto -O3` (one core, load 12), so batching could save at most about
3 s of a cold 50k build.

## 2. Equivalence evidence

`experiments/llvm-zig-20260924/equivalence.py` replays a build's
`MYLANG_LLVM_DUMP` (each unit's IL, the Zig translator's IR and the closure
signatures it read) through the retired adapter's `translate_text`, with the
same signatures, target policy and runtime tree, and requires identical text.
The dumps came from the final Debug compiler (`8a4cd746`'s tree) building every
file of `tests/lang` with `mylang test --release`, every bench-parity program
with `build --release`, the Lox port's program and tests, and the 10k ladder:

| corpus | builds | units | identical |
| --- | ---: | ---: | ---: |
| `tests/lang` | 196 | 1,148 | 1,148 |
| `bench/parity` (suite, lib, micro, with variants) | 44 | 198 | 198 |
| Lox port, `main.my --project` | 1 | 376 | 376 |
| Lox port, `mylang test .` | 1 | 258 | 258 |
| 10k ladder (`gen_scale.py t10k 25 36`) | 1 | 926 | 926 |
| **total**, `PYTHONHASHSEED` = 0, 1 and 20260924 | | **2,906** | **2,906** |

Three more checks:

- `test/fixtures/llvm-translate/adapter-corpus.json` holds every translation
  the adapter's own `test_adapter.py` performs (114 cases, 108 with IR and 6
  refusals, harvested by `harvest_fixtures.py` and packed by
  `pack_fixtures.py`). The Zig test `the in-process translator reproduces the
  retired Python adapter's IR for its whole golden corpus` (`LLVM-ZIG-1`)
  replays all of them in the normal gate, with no Python.
- `bench_parity.py same-binaries --other <fd36abc2 ReleaseFast install>`:
  **71 of 71 mylang binaries identical** between `main`'s compiler (Python
  adapter) and this branch's. Earlier in the lane the 10k ladder's `--release`
  executable was also byte-identical old vs new.
- Without LTO (`--backend llvm --llvm-opt 3`), `binary_trees`, `nbody`,
  `knucleotide`, `dict_count` and `scan_split` build byte-identical executables
  with both compilers. This path was broken on the branch until `a34068c9`: for
  `-S`, Zig's `-###` listing names `/dev/null` as the output, so the probe found
  nothing to substitute and every non-LTO LLVM build failed. No corpus build
  used it; `test-native-boundary` (the legacy `--qbe qbe_llvm.py` spelling)
  would have caught it in the gate.

## 3. Build time and memory

ReleaseFast compilers: `fd36abc2` (before, Python adapter) and `bc114035`
(after; its full-LTO path is the same code as the head's). Every build runs
under `taskset -c 0-11` in its own cgroup scope. Wall seconds of the whole
`mylang build`; memory is the scope's peak (the largest single process in
brackets). The machine was shared with other lanes; the 1-minute load average
at the start of each build is given. Harnesses: `scale.sh`, `lox_measure.py`
(a wrapper of `experiments/devspeed-defaults-20260923/lox_edit_build.py`),
`tm.py`; they live in the lane's scratch directory and are described here.

**Lox port** (4,182 lines, 376 functions), `bench.json`'s four edits, three
rounds each, median (min–max):

| arm | cold | leaf body edit | hub body edit | comment edit | new public function | peak process |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| before, `--release` | 14.8 | 2.91 (2.80–4.08) | 2.94 (2.87–4.14) | 2.96 (2.92–3.04) | 3.98 (3.92–4.04) | 170 MB |
| after, `--release` | 4.0 | 2.51 (2.43–3.11) | 2.91 (2.50–3.27) | 2.81 (2.63–2.95) | 3.46 (3.20–3.50) | 173 MB |
| after, `--lto=thin` | 2.5 | 1.68 (1.61–1.71) | 1.62 (1.55–2.12) | 1.52 (1.35–1.73) | 2.07 (2.04–2.16) | 153 MB |

Load 5.5 → 4.0 (before) and 3.6 → 10.7 (after). A Lox edit was already cheap
before: the object cache meant one Python start per changed unit, and the LTO
link (2.7 s) is most of both columns.

**Ladders** (`gen_scale.py`; edit = the `# EDIT_BODY` constant in the middle
module, as in the development-speed audit):

| tier | arm | cold | frontend / codegen / link | edit → build | peak memory | load |
| --- | --- | ---: | --- | ---: | ---: | --- |
| 50k (4,681 fns) | before, `--release` | 326 s | 3.8 / 265.7 / 56.6 | 115 s | 2.3 GB (1.7) | 16.5, 6.4 |
| 50k | after, `--release` | **91 s** | 3.6 / 25.3 / 62.4 | **61 s** | 1.9 GB (1.6) | 10.7, 8.0 |
| 50k | after, `--lto=thin` | 68 s | 3.6 / 20.7 / 43.2 | 38 s | 1.1 GB (0.6) | 8.5, 22.6 |
| 200k (18,721 fns) | before, `--release` | > 1,800 s (coordinator) | | | 578 MB when killed | 2–6 |
| 200k | after, `--release` | **398 s** | 20.8 / 111.4 / 264.9 | **256 s** | 7.1 GB (6.5) | 21.9, 5.7 |
| 200k | after, `--lto=thin` | **207 s** | 16.3 / 71.7 / 119.2 | 132 s | 3.5 GB (1.9) | 11.2, 12.1 |

The audit's earlier 50k figures (cold 369 s, edit → build 95 s) are the same
order as this run's "before" row; the edit → build here is slower because the
old path re-ran the adapter's `--signatures-only` pass over the whole closure
on every build (58 s of the 115 s).

Against the targets:

| target | result |
| --- | --- |
| 50k `--release` cold ≤ 60 s | **not met**: 91 s (full LTO), 68 s (ThinLTO) at load 9–11 |
| 200k finishes under default memory ceilings in ≤ 5 min | **met with `--lto=thin`** (207 s, 3.5 GB); full LTO finishes under the ceilings but takes 398 s |
| no bench-parity regression | **met**: all 71 binaries byte-identical |

Where the remaining time goes, and why it stops there:

- **Full LTO's optimizer is serial.** At 10k the `ld.lld` step alone is 15.2 s,
  and codegen partitions (`--lto-partitions=12`) only take it to 13.4 s: most
  of it is optimizing the one merged module on one thread, and it grows with
  the program (62 s at 50k, 265 s at 200k) and is paid again after any edit.
  The 200k merged module peaks at 6.5 GB in LLD, within the compiler's 8 GiB
  ceiling that its tools inherit, but not by much.
- **Per-unit compiles** are 25 s of the 50k build and 111 s of the 200k build
  (loaded): about 39 ms of `-O3` pre-link pipeline and bitcode per unit, of
  which 8 ms is the process start. The in-process translation itself is a small
  part (the 50k codegen phase dropped from 266 s to 25 s).
- **The frontend** is 3.6 s at 50k and 16–21 s at 200k.

## 4. Full LTO against ThinLTO

`--lto=thin` (`LLVM-THINLTO-1`, `src/qbe_build_llvm_thin.zig`): every guest
unit and the runtime archive (new flavor `llvm-thinlto`, keyed apart from
full-LTO bitcode) are ThinLTO bitcode. The frame map needs each module's final
assembly, so LLD runs with `--lto-emit-asm --thinlto-jobs=N` and writes one
assembly file per module beside that module's input path; every input is
therefore linked under a symlink alias in the link's own scratch directory,
never beside a shared cached object. The files are annotated and assembled on
worker threads with the bundled `-cc1as` and linked natively. Three things were
needed for the frame map to hold:

1. A guest callee imported from another module and inlined names its probe
   GUID, but only its own module emits the descriptor; the annotator now takes
   every unit's name by GUID (`probeGuid`, LLVM's `Function::getGUID`: the
   first 8 bytes of the name's MD5).
2. The generated entry and metadata C stay machine code under ThinLTO. As
   bitcode, the entry imported guest functions into a module without
   pseudo-probe descriptors, where LLVM drops call positions ("Pseudo-probe
   ignored"), and the `_meta` records became local to the metadata module
   while every other module's table names them.
3. The Lox port's build failed its frame map: a print wrapper inlined at three
   sites carried an inlined runtime helper (`fwrite`, `fflush`), and LLVM folded
   the three copies into one block whose inline site is `@ CALLER:0`. Turning
   off either SimplifyCFG's sinking of common instructions or tail merging
   avoids it; the link turns off both (`-sink-common-insts=false`,
   `-enable-tail-merge=false`). The 254 Lox corpus scripts then give identical
   stdout, stderr and status from the full- and thin-LTO interpreters, and the
   integration trap tests (inlined callee, callback, runtime helper, recursion)
   now also build with ThinLTO and require the same traces.

**Runtime** (bench-parity, ratio to Zig ReleaseFast, same rounds, full and
thin arms interleaved):

Run 2 is the shipped link (no sinking, no tail merging); run 1 was before those two
switches. Both runs time all 27 programs on CPU 2 at load 10–12, seven rounds each.

| benchmark | full / Zig | thin / Zig | thin ÷ full | unchecked thin ÷ full | thin ÷ full, run 1 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `knucleotide` | 1.525 | 1.924 | 1.262 | 1.213 | 1.181 |
| `dict_count` | 1.078 | 1.224 | 1.135 | 1.164 | 1.125 |
| `sort_quick` | 1.208 | 1.294 | 1.072 | 1.040 | 1.055 |
| `fannkuch_redux` | 1.096 | 1.170 | 1.068 | 1.117 | 1.088 |
| `sort_records` | 0.273 | 0.284 | 1.041 | 1.034 | 1.024 |
| `list_append_sum` | 1.158 | 1.204 | 1.039 | 1.093 | 1.001 |
| `fib` | 2.139 | 2.206 | 1.031 | 1.310 | 0.957 |
| `matmul` | 0.677 | 0.693 | 1.024 | 1.026 | 1.018 |
| `records` | 0.931 | 0.950 | 1.020 | 1.011 | 1.004 |
| `str_build` | 1.176 | 1.196 | 1.017 | 1.007 | 1.007 |
| `intloop` | 0.937 | 0.951 | 1.014 | 0.997 | 1.003 |
| `list_records` | 1.321 | 1.336 | 1.012 | 0.974 | 1.026 |
| `alloc_churn` | 1.896 | 1.912 | 1.009 | 1.005 | 0.998 |
| `scan_count` | 0.658 | 0.664 | 1.008 | 1.011 | 1.010 |
| `float_loop` | 1.005 | 1.008 | 1.004 | 1.003 | 1.004 |
| `scan_split` | 3.148 | 3.147 | 1.000 | 1.017 | 0.996 |
| `scan_replace` | 0.338 | 0.336 | 0.996 | 0.983 | 0.997 |
| `raytrace` | 1.380 | 1.366 | 0.990 | 0.966 | 0.982 |
| `sieve` | 0.998 | 0.987 | 0.989 | 0.968 | 1.041 |
| `sort_builtin` | 0.515 | 0.507 | 0.985 | 1.003 | 0.984 |
| `bytes_scan` | 0.378 | 0.372 | 0.982 | 1.019 | 0.992 |
| `mandelbrot` | 1.037 | 1.015 | 0.979 | 0.968 | 1.000 |
| `spectral_norm` | 1.000 | 0.978 | 0.978 | 0.982 | 1.009 |
| `binary_trees` | 0.498 | 0.483 | 0.970 | 1.014 | 0.998 |
| `nbody` | 1.584 | 1.533 | 0.968 | 0.966 | 0.969 |
| `calls` | 0.999 | 0.964 | 0.965 | 1.001 | 0.973 |
| `text_ops` | 3.795 | 3.594 | 0.947 | 1.017 | 1.005 |

Geometric mean of thin ÷ full: **1.017** (checked) and **1.031** (unchecked) in run 2,
1.016 and 1.019 in run 1. The full-LTO arms of run 2 are the thresholded bench-parity
arms of this branch, and they passed all 54 thresholds.

Import-limit tuning did not close the gap: `-import-instr-limit=1000` took
`knucleotide` from +19.8% to +10.9% and `dict_count` from +15.7% to +11.1%
(9 rounds, CPU 2), and 5000 did no better. Each guest function is its own
module, so ThinLTO sees one function plus what it imports, where full LTO
inlines and specializes runtime helpers across the whole program.

**Decision.** `--release` stays full LTO: ThinLTO costs 1.7–3.1% in the
geometric mean and single programs lose up to 26% (`knucleotide`), 16%
(`dict_count`) and 12% (`fannkuch_redux`); the flags that keep call sites apart
cost little on top (run 1 against run 2). ThinLTO is the option for a large
program whose release build full LTO makes too slow or too large (200k: 207 s
and 3.5 GB against 398 s and 7.1 GB).

LLD's ThinLTO cache would make an edit → build compile one module instead of
all of them, but with `--lto-emit-asm` a cache hit writes an **empty** assembly
file (measured at 10k: the second link took 0.8 s and all 926 files were
empty), so it is not used.

## 5. Where the Python went

| item | before | after |
| --- | --- | --- |
| `experiments/llvm-backend/{qbe_llvm,llvm_emit,runtime_signatures,amd64_sysv,sticky_loops}.py` | installed to `lib/mylang-llvm/`, run once per unit by `--release` | **kept in place** as the equivalence oracle (README status note); not installed, not resolved, not run by any build |
| `build.zig` | installed the five files; passed `--llvm-adapter` to `emit-runtime`; `MYLANG_LLVM_ADAPTER` to test steps | none of it; `emit-runtime` always publishes all five runtime flavors |
| `--llvm-adapter PATH`, `MYLANG_LLVM_ADAPTER` | adapter override | removed; `MYLANG_LLVM_ADAPTER` is ignored (`BUILD-BACKEND-5`) |
| `--qbe …/qbe_llvm.py` | ran the adapter as the QBE tool | selects the built-in backend at `MYLANG_QBE_LLVM_OPT` (default `-O2`) without reading the file |
| `src/host_native.zig`, `src/schematic/runner.zig`, `src/native_test_environment.zig` | named or pinned the adapter and `PYTHON*` variables | name the translator switches instead |
| tests naming `adapter.py` (`qbe_build_backend.zig`'s fake adapter script, `host_native.zig`'s policy strings) | an adapter to resolve or forward | a fake `zig` that answers `-###`; `BUILD-BACKEND-2`/`-5` assert no adapter is resolved or forwarded |
| `zig build test-llvm-adapter` | the adapter's unit tests | unchanged: it tests the oracle, in the gate |
| `native_boundary_matrix.py` | ran the adapter through `--qbe` | the same argument now selects the built-in backend |
| `scripts/affected_tests.py` | exported `MYLANG_LLVM_ADAPTER`; its "LLVM smoke" built with a bare `--mode ReleaseFast` (QBE since 2026-09-23) | exports nothing; the smoke builds with `--release` and also runs for `src/qbe_build_llvm*.zig` edits |

Also updated: `docs/tooling/native-build.md` (backends, the translator,
switches and `MYLANG_LLVM_DUMP`, concurrent code generation, runtime flavors,
a new ThinLTO section), `docs/tooling/runtime-budgets.md`, `README.md`,
`CLAUDE.md`, `SPEC.md` (`LLVM-ZIG-1`, `LLVM-THINLTO-1`, `BUILD-BACKEND-2/3/5`,
`USE-WITHOUT-PYTHON-1`).

## Acceptance

On the ReleaseFast install of `bc114035` (`zig build -Doptimize=ReleaseFast
-Dcompiler-only=true --prefix …`):

```text
python3 on the test PATH: none
installed .py files: 0            (lib/ holds only mylang-runtime/)
build --release: "backend":"llvm","optimization":"3","lto":true,"thin_lto":false}
build status=0
total: 285                        (the executable, under the same PATH)
total: 285                        (mylang run --release)
trap.my:2:12: error[R_LIST_BOUNDS]: native execution failed (index 5, length 2)
  in pick at trap.my:2:12
  in main at trap.my:6:12
run --release (trap) status=1
```

(`env -i PATH=<empty dir> HOME TMPDIR ZIG_GLOBAL_CACHE_DIR`, `--zig` given.)
`USE-WITHOUT-PYTHON-1` in `test/integration.zig` now runs `build --release`,
its executable and `run --release` under an empty `PATH` in every gate.

## Gate

GATE_RESULTS

## Risks and follow-ups

- **Folded call sites under full LTO.** The hazard ThinLTO hit (item 3 of §4)
  exists in the full-LTO pipeline too: an inlined runtime helper's calls are
  not `nomerge`, so copies from different guest call sites can be folded. The
  annotator refuses such a build (it never reports a wrong trace), and no
  corpus program has hit it under full LTO. Turning the two passes off for full
  LTO would change `--release` binaries and needs its own bench-parity run.
- **Incremental ThinLTO.** Distributed ThinLTO (`--thinlto-index-only`, one
  `clang -fthinlto-index=` per module, cached by the module, its imports and its
  index) would make an edit → build recompile only the modules whose imports
  changed. The runtime archive's members would need extracting, since a
  backend compile cannot open `archive.a(member.o)`.
- **Full LTO memory.** The 200k merged module peaks at 6.5 GB in LLD against
  the 8 GiB ceiling the compiler hands its tools; a program a little larger
  than 200k lines will need ThinLTO.
- **The 50k cold target** needs full LTO's optimizer off the critical path;
  neither partitioned codegen (12% of the link at 10k) nor batching clang starts
  (≈ 3 s at 50k) gets there.
