# mylang against Zig and Rust: what the gap is made of, and the plan to parity — 2026-09-22

This audit asks the question for the whole language rather than for one
workload: what separates ordinary mylang programs from the same programs in Zig
and Rust, how much of it is the language's own rules and how much is the
implementation, and in what order to remove it. It builds on nine earlier audits
and two implementation waves (§2), adds an 11-program suite written the way each
language's users write it (§3), and prices every candidate cause separately by
rewriting the emitted code, rebuilding and re-timing (§4). §5 covers changes to
the language itself, §6 compiler and runtime changes, and §7 the plan, with what
each wave is measured or projected to deliver.

Compiler under test: the ReleaseFast install built from `acbee603` plus the
merged schematic lanes 2–4 (`.tmp/perf-audit-20260922/install-a3`, the newest
general-purpose compiler; lane 1 changes only the schematic runner). *Lane 5*
means the paused `perf/schematic-5-aggregate-reads` compiler (`24336bf2`), built
for this audit. Evidence, harnesses, raw rounds and every port are under
[`experiments/perf-parity-plan-20260922`](../../experiments/perf-parity-plan-20260922/README.md).
No production source changed.

> **Implemented 2026-09-23.** Every wave below landed on `perf/parity-integration`.
> Measured on one quiet batch, the 13-program suite went from 5.79× to 1.19× Zig
> (QBE 8.40× → 2.41×). See
> [`performance-parity-results-2026-09-23.md`](performance-parity-results-2026-09-23.md),
> which also corrects three claims here: lane 5 slowed `raytrace` by 2–4.5%, the
> arena chunk-list analysis in §4.9, and the frame protocol's remaining price.

## Headline

1. **Written the way their languages' users write them, thirteen programs run at
   5.8× Zig ReleaseFast on the geometric mean** (Rust 1.01×, Zig ReleaseSafe
   1.15×). They range from 1.32× (`mandelbrot`) to 72× (`nbody`), with a median
   of 4.9×. The matched micro-kernels that guided the last week's work are at
   1.36× (Rust 0.99×). Most of what they measured is fixed, and they no longer
   predict how real programs behave.
2. **The worst ratios come from one lowering, not from the language.** Writing
   one element of a managed list is a runtime call behind a republished GC root
   chain. The chain has one 32-byte record per *hidden temporary*: 35 per write
   in `nbody`, 22 in `fannkuch_redux`. That puts `nbody` at 72×, `matmul` at
   41×, `fannkuch_redux` at 16× and `sieve` at 7.1×.
   **The paused lane 5 removes it:** `nbody` → 5.1×, `matmul` → 7.1×,
   `fannkuch_redux` → 1.3×, `sieve` → 1.8×. That is −49% on the geomean, and no
   program is slower beyond noise.
3. **Of the language's own rules, only one has a large price: canonicalizing
   NaN after every float operation.** Its opaque cold call sits inside every
   float loop, so LLVM can neither keep values in registers nor vectorize.
   Removing it alone:
   - `mandelbrot` 1.32× → 1.02×
   - `raytrace` 4.25× → 2.27×
   - class `nbody` 4.13× → 1.82×

   Canonicalizing only where a NaN can be observed (bits, hashes, the host
   boundary) keeps the guarantee, and no program can tell the difference.
   Python's negative indices and the for-loop length re-check cost 1–2% on the
   geomean and should stay.
4. **Checked arithmetic is affordable once its failure path is lowered
   correctly.** Stripping the overflow checks takes `spectral_norm` from 3.65×
   to 1.31×: each check adds a call and an edge into a shared exit, and that
   stops inlining. In an executable the fail helper `longjmp`s and never
   returns, so ending the path in `unreachable` is sound. Traps stay
   byte-identical, and `spectral_norm` falls to 2.14× with every check kept.
   After the full ladder the checks cost 11% on the geomean, close to what Zig
   ReleaseSafe pays for the same checks (1.15×). Keep trapping `+ - *` as the
   default.
5. **The runtime library accounts for the rest**, and so does memory:
   - `text_ops` 6.9×, 10× Zig's memory: a string object per field, and `count`
     and `replace` call `memcmp` at every offset.
   - `knucleotide` 4.9×, 8× Zig's memory: keys hashed byte by byte, two probes
     per update, copied slices.
   - `sort_records` 5.3×, 14× Zig's memory.

   The same programs in the language's own tuned spellings run at 0.72×, 2.8×
   and 1.6×. The language can express the fast version, but its library and its
   obvious spellings don't produce it.
6. **Composed, measured:** the ladder goes 5.8× today → 3.0× with lane 5 → 2.8×
   with `unreachable` failure paths → about 2.3× with the NaN change → 2.2×
   without the frame record (§7 gives the caveats). With every check also stripped it reaches 1.9×. With the
   tuned variants standing in for the library work, the projection is **about
   1.6× with every check on** and 1.4× unchecked.
7. **Applications.** The S-expression parser runs census at 1.73× and render at
   2.21×. Its biggest single item is the root chain (19% of render); the rest
   is memory traffic, and none of the code-generation levers moves it much. The
   schematic renderer is 1.98× Zig, 1.73× with lane 5 and 1.60× with lane 5 in
   an arena (Rust 1.12×).
8. **Bugs found by the ports:** storing into a container inside `with arena()`
   is quadratic, and two `sorted(key=...)` spellings crash the compiler.

**The plan (§7)** runs in five waves:
- **Wave 0:** fix the bugs and the runtime library's algorithms (small,
  parallel).
- **Wave 1:** gate and land lane 5.
- **Wave 2:** lowerings that keep the meaning: `unreachable` failure paths, root
  liveness, helper attributes.
- **Wave 3:** four language changes: NaN canonicalized when observed, fixed-size
  arrays as ordinary mutable values, keyed sorting, and shared `str` slices.
- **Wave 4:** the runtime architecture: return-address frame map, inline
  allocation, collector steady state, a niche `Option`.

Waves 0–3 are small to medium and can run as parallel lanes. Wave 4 is the
long pole, and it is what remains between about 1.6× and the 1.2× target.

## 1. What parity means here

The reference is **Zig ReleaseFast**, which the earlier audits used, so every
ratio is comparable with them. Two comparators have the same safety as mylang's
default build. **Zig ReleaseSafe** keeps overflow and bounds checks. **Rust
release** keeps bounds checks and wraps on overflow; the `rust-checked` arm adds
`-C overflow-checks=on`, which matches mylang's checked `+ - *`. Rust uses
`target-cpu=native`, as Zig and mylang already do.

The target this plan works toward, with every check on by default:

| measure | target |
|---|---|
| geometric mean over the program suite, default `mylang build` | ≤ 1.2× Zig ReleaseFast (≈ Rust release, ≈ Zig ReleaseSafe) |
| worst single program, default build | ≤ 1.5× |
| geometric mean, `--unchecked` | ≤ 1.1× |
| peak memory | ≤ 1.5× Zig on the collecting heap, ≤ 1.2× in an arena |

The programs are written idiomatically in each language: `list[list[float]]`
and record lists in mylang, flat slices and structs in Zig and Rust. Tuned
mylang variants (`_tuned`, `_class`, `_flat`, `_arena`) show what a programmer
can reach without leaving the language. The gap between the idiomatic and tuned
versions is itself a finding, because agents write the idiomatic form.

## 2. What the earlier work already did

Since 18 September, nine audits and two implementation waves have taken the
native build from 30–90× Zig's instruction count on byte loops to roughly
parity on scalar kernels. This audit starts from that record:

| date | change | measured effect | record |
|---|---|---|---|
| 09-18 | runtime audit: byte loops at 30–90× Zig's instruction count; six-wave plan | — | [runtime-performance-2026-09-18](runtime-performance-2026-09-18.md) |
| 09-19 | value roots (`QBE-ROOTS-2`); hot-loop plan; LLVM backend experiment | census −9.6% cycles | [hot-loop-plan-2026-09-19](hot-loop-plan-2026-09-19.md) |
| 09-20 | experimental LLVM O3 arena arm with the runtime levers composed | parser 1.25× / 1.37× (not shipped) | [llvm-arena-parity-gap-2026-09-20](llvm-arena-parity-gap-2026-09-20.md) |
| 09-21 | three cliffs fixed: linear dictionary, whole-array copy per write, arena `calloc` per scope | dict_count 329× → 3.2×, arena churn 16× → 2.2×, SVG −14% | [performance-parity-audit-2026-09-21](performance-parity-audit-2026-09-21.md), [rerun](performance-parity-rerun-2026-09-21.md) |
| 09-21 | roadmap 1: LLVM O3 + LTO is the ReleaseFast default | scalar kernels 2.2–2.4× → 0.9–1.0× | [performance-roadmap](../performance-roadmap.md) §1 |
| 09-21 | roadmap 2 (part): traps leave by `longjmp`, no flag test after calls | the per-call frame record stays | §2 |
| 09-21 | roadmap 3 (part): two-word object header, size-classed segments | alloc_churn 2.65× → 1.85× | §3 |
| 09-21/22 | roadmap 4 and 5: UTF-8 `str`; inline append; in-place buffer and list growth; `memchr` scans; dictionary probe memo | str_build 3.7× → 1.15×, list_append_sum 3.0× → 1.36×, dict_count 2.8× → 1.39× | §4, §5 |
| 09-21/22 | roadmap 6 (part): list element read through its own address; frame fit | list_records 2.16× → 1.34×; peek1024 115 → 1.5 ms | §6, [frame-fit](frame-fit-2026-09-21.md) |
| 09-22 | float NaN canonicalization moved off the finite path (`QBE-FLOAT-CANON-1`) | float_loop 2.76× → 1.00× | §1 |
| 09-22 | schematic audit: default build 1.84× Zig; the shipped runner (QBE + step accounting) 5.8× | — | [schematic-parity-gap](schematic-parity-gap-2026-09-22.md) |
| 09-22 | schematic lanes 1–4 merged on `perf/schematic-integration`: runner on LLVM, `--unchecked`, alias classes, bulk `bytes` I/O | runner guest 7.39× → 2.19×; `--unchecked` −15.8% on the fixture | `schematic-lane-*-2026-09-22.md` on the lane branches |
| 09-22 | lanes 5 (aggregate reads and writes), 6 (output emission) and 8 (invocation cache) paused as work in progress; lane 7 (step batching) not started | not timed | same |

Two things follow. First, the matched micro-kernel suite that drove this work is
now close to parity (§3.2). Most of what it measured is done, so it no longer
predicts how real programs behave. Second, lane 5 was paused with its code
complete but never timed; §4.1 measures it.

## 3. Where mylang stands today

### 3.1 The program suite

Eleven programs, thirteen timed entries (`sort` has three), each in mylang, Zig
and Rust, all printing byte-identical output. They are specified in
[`suite/SUITE.md`](../../experiments/perf-parity-plan-20260922/suite/SUITE.md)
and described with their idioms in the porting notes. Ratios are to Zig
ReleaseFast: medians of per-round paired ratios, lower is better.

| program | Zig ms | zig-safe | rust | rust-checked | my | my-unchecked | best mylang variant | RSS my/Zig |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| binary_trees | 219.0 | 1.15 | 1.84 | 1.88 | 2.17 | 2.06 | arena 1.35 | 11.4 |
| spectral_norm | 150.3 | 1.36 | 0.99 | 1.17 | 3.65 | 1.20 | tuned 1.30 | 1.5 |
| mandelbrot | 123.3 | 1.00 | 1.02 | 1.02 | 1.32 | 1.29 |  | 1.2 |
| raytrace | 89.3 | 1.00 | 0.98 | 1.01 | 4.25 | 2.59 | tuned 2.80 | 1.2 |
| knucleotide | 104.2 | 1.12 | 1.37 | 1.38 | 4.90 | 4.90 | tuned 2.84 | 8.1 |
| text_ops | 26.0 | 0.86 | 1.59 | 1.56 | 6.86 | 6.79 | tuned 0.72 | 10.0 |
| sort_builtin | 205.4 | 1.17 | 0.29 | 0.30 | 1.64 | 1.66 |  | 2.1 |
| sort_quick | 166.0 | 1.18 | 0.96 | 0.97 | 1.89 | 1.53 |  | 1.2 |
| sort_records | 111.7 | 1.17 | 0.40 | 0.40 | 5.32 | 4.95 | sorted 1.62 | 14.1 |
| sieve | 54.1 | 1.36 | 1.02 | 1.18 | 7.14 | 6.16 | tuned 4.09 | 1.1 |
| nbody | 154.3 | 0.96 | 1.11 | 1.16 | 71.72 | 71.42 | class 4.13 | 1.3 |
| fannkuch_redux | 219.1 | 1.24 | 0.97 | 0.97 | 15.81 | 15.17 | tuned 0.83 | 1.3 |
| matmul | 41.1 | 1.58 | 2.21 | 2.78 | 41.33 | 39.34 | tuned 6.65 | 2.0 |
| **geomean** |  | **1.15** | **1.01** | **1.06** | **5.79** | **4.89** |  |  |

The comparators with mylang's safety pay 6–15% for it: Zig ReleaseSafe is
1.15× and Rust with overflow checks 1.06×. The safety mylang keeps is not what
sets its floor. Two Rust cells need context. `sort_builtin` at 0.31× is Rust's
`slice::sort`, which is 3.2× faster than Zig's block sort. `matmul` at 2.21×
keeps a bounds check in Rust's index loop that stops LLVM vectorizing it, while
Zig's loop vectorizes.

The programs fall into three groups:

- **Within 2×:** `mandelbrot` 1.32×, `sort_builtin` 1.64× and `sort_quick`
  1.89×.
- **2–5×, one mechanism each:**
  - `binary_trees` 2.17×: the collector.
  - `spectral_norm` 3.65×: the checks' failure paths.
  - `raytrace` 4.25×: the NaN rule and the frame protocol.
  - `knucleotide` 4.90×: the runtime library.
- **5–72×:** `sort_records`, `text_ops`, `sieve`, `fannkuch_redux`, `matmul` and
  `nbody`. Every one is either a managed-list write in a hot loop (§4.1) or a
  library routine doing per-byte or per-level work (§4.3).

### 3.2 The micro-kernels, now with Rust

| program | Zig ms | zig-safe | rust | rust-checked | my | my-unchecked | best mylang variant | RSS my/Zig |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| intloop | 107.6 | 1.01 | 0.96 | 0.86 | 0.94 | 0.94 |  | 1.2 |
| calls | 128.8 | 1.02 | 0.76 | 0.81 | 0.99 | 1.05 |  | 1.2 |
| fib | 36.4 | 1.93 | 1.08 | 1.82 | 3.25 | 1.11 |  | 1.2 |
| records | 90.0 | 0.93 | 0.84 | 0.78 | 0.93 | 1.07 |  | 1.2 |
| list_append_sum | 47.3 | 1.08 | 1.07 | 1.15 | 1.43 | 1.23 |  | 1.0 |
| list_records | 49.4 | 1.08 | 0.93 | 1.12 | 1.42 | 1.18 | wrapping 1.24 | 1.0 |
| dict_count | 29.3 | 1.36 | 2.14 | 2.15 | 1.60 | 1.57 |  | 1.6 |
| str_build | 41.5 | 1.27 | 1.10 | 1.08 | 1.20 | 1.22 |  | 1.0 |
| alloc_churn | 69.2 | 1.09 | 1.39 | 1.39 | 2.24 | 2.15 | arena 1.77 | 3.2 |
| float_loop | 37.4 | 1.02 | 1.04 | 1.01 | 1.01 | 1.01 |  | 1.2 |
| bytes_scan | 38.5 | 1.28 | 0.38 | 1.50 | 1.19 | 1.36 | wrapping 1.37 | 1.3 |
| **geomean** |  | **1.16** | **0.99** | **1.18** | **1.36** | **1.23** |  |  |

The eleven kernels of the 2026-09-21 suite, now with Rust ports
(`micro-rust/`, identical output). Eight are within 1.45× of Zig and four at or
under parity (`intloop`, `calls`, `records`, `float_loop`). Three stand out:

- `fib` at 3.25×: the frame protocol and checks. `--unchecked` gives 1.11×; Zig
  ReleaseSafe is 1.93× and Rust with overflow checks 1.82× on the same kernel.
- `alloc_churn` at 2.24×: the collector. The arena variant is 1.77×, and Rust's
  per-batch `Vec` 1.39×.
- `dict_count` at 1.60×: faster than Rust's default SipHash map (2.14×) and
  slower than Zig's single-lookup `getOrPut` (0.58×).

Rust leads Zig on `calls` and `records` by 15–25%, because its truncating `%`
skips the floor-division sign fix-up that Zig's `@mod` and mylang's `%` keep.
It also leads on `bytes_scan` (0.38×), because only rustc vectorizes that loop.
In short, the kernel suite is done except for calls and allocation. It no longer
represents what separates mylang programs from Zig and Rust; the program suite
does.

### 3.3 The applications

**S-expression parser** (`experiments/sexpr-port`, 101 functions, the 7.42 MB
`input8.sexp`; 11 interleaved rounds against the in-repo Zig reference, output
byte-identical):

| arm | census | render |
|---|---:|---:|
| Zig ReleaseFast | 16.4 ms | 20.6 ms |
| mylang, today | 1.73× | 2.21× |
| mylang, `--unchecked` | 1.55× | 2.00× |
| mylang, lane 5 | 1.73× | 2.22× |
| lane 5, `--unchecked` | 1.54× | 2.00× |

In a second batch of the same parser (Zig 15.7 / 19.9 ms), the counterfactuals
show where the parser differs from the suite:

| arm | census | render |
|---|---:|---:|
| unmodified rebuild | 1.77× | 2.24× |
| failure paths `unreachable` | 1.66× | 2.15× |
| frame protocol removed | 1.62× | 2.07× |
| every check removed | 1.64× | 2.13× |
| collector off (control for roots) | 1.54× | 2.07× |
| collector off, no root records | 1.47× | 1.67× |
| lane 5 + noreturn + language rules + no frame record | 1.60× | 2.03× |
| lane 5 + everything stripped | 1.56× | 2.02× |

The parser barely responds to lane 5, the NaN rule or the checks. Two things
move it. The root chain is 19% of render, the largest single item. The rest is
what the 2026-09-22 roadmap re-measurement named: libc memory traffic
(`memcpy`, `memset`, `malloc`), the collector's marking, and the render
buffer's growth. The collector work of wave 4 and conservative scanning (6.7)
are the levers for this kind of program. The code-generation waves are not.
These ratios are higher than the roadmap's 1.50× / 1.90× from the same morning.
That run used a different compiler build (`roadmap-5b-buffers`) and the
pre-`mut` source, and this batch shared the machine with the slow batch on
another core. Compare ratios only within one batch.

**Schematic SVG renderer** (`src/schematic/guest`, the audit's three inputs,
31 interleaved rounds, every SVG hash checked; `fixture` shown, the other two
inputs agree within 0.06×):

| arm | ms | × Zig |
|---|---:|---:|
| Zig port | 1.487 | 1.00 |
| Rust port | 1.669 | 1.12 [1.09, 1.19] |
| mylang today (a3, GC) | 2.937 | 1.98 [1.91, 2.08] |
| today, `--unchecked` | 2.523 | 1.70 [1.64, 1.81] |
| today, arena | 2.707 | 1.82 [1.77, 1.93] |
| lane 5 (GC) | 2.573 | 1.73 [1.68, 1.84] |
| lane 5, `--unchecked` | 2.421 | 1.63 [1.59, 1.73] |
| lane 5, arena | 2.375 | 1.60 [1.54, 1.69] |

Lane 5 is worth 13% on the schematic; `--unchecked` on top another 6%. What
remains is the schematic audit's list. Its per-phase numbers are for the
pre-lane-5 build, so they are an ordering, not a split of today's gap:

- SVG text emission (the paused lane 6)
- parsing and model construction
- the 0.14 ms process floor over a static Zig binary

### 3.4 Memory

Peak resident memory, one run per arm (`/usr/bin/time`), as a multiple of Zig's:

| program | Zig MB | Rust × Zig | mylang × Zig | best mylang variant |
|---|---:|---:|---:|---:|
| binary_trees | 4.4 | 2.3 | 11.4 | arena 4.2 |
| spectral_norm | 2.0 | 1.2 | 1.5 | tuned 1.5 |
| mandelbrot | 2.0 | 1.1 | 1.2 |  |
| raytrace | 2.0 | 1.1 | 1.2 | tuned 1.3 |
| knucleotide | 9.4 | 1.7 | 8.1 | tuned 2.9 |
| text_ops | 7.8 | 2.1 | 10.0 | tuned 1.3 |
| sort_builtin | 15.8 | 1.6 | 2.1 |  |
| sort_quick | 15.8 | 1.1 | 1.2 |  |
| sort_records | 15.6 | 1.6 | 14.1 | sorted 3.1 |
| sieve | 19.4 | 1.1 | 1.1 | tuned 1.1 |
| nbody | 2.0 | 1.1 | 1.3 | class 1.2 |
| fannkuch_redux | 2.0 | 1.1 | 1.3 | tuned 1.3 |
| matmul | 6.1 | 1.3 | 2.0 | flat 1.4 |

Most programs sit at 1.1–1.5× Zig, which is the process and runtime floor.
Four allocate many small objects and do not:

- `binary_trees`, 11×. The trigger lets garbage reach three times the live set
  plus 4 MiB, and a node is 48 bytes against Zig's 16.
- `knucleotide`, 8×, and `text_ops`, 10×: one object per slice.
- `sort_records`, 14×: the stdlib merge's copies.

The tuned or arena variants bring each of them back to 1.3–4.2×. The levers
are therefore fewer objects (5.4, 6.10), a smaller optional (6.9) and a trigger
that does not re-mark a long-lived set (6.6). The object header is already two
words.

## 4. What the gap is made of

Each mechanism below was priced by one counterfactual: the release manifest is
emitted (`emit-qbe --drop-debug --drop-step-checks --drop-frame-checks`),
rebuilt unmodified to confirm the binary is byte-identical to a plain `mylang
build` (it was, for every program), then rewritten to remove exactly one rule
or protocol (`rewrite_il.py`) and timed beside the original in the same
interleaved batch. A rewritten binary is a diagnostic: it no longer reports the
failure it stopped checking for. Every arm still printed byte-identical output.

| program | my × Zig | NaN rule | negative index | loop length re-check | all three rules | overflow checks | bounds + iter | all checks | frame protocol | everything | roots (vs nogc) | lane 5 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| binary_trees | 2.17 | -0% | -2% | +0% | +0% | -1% | -1% | -2% | -5% | -7% | -4% | -1% |
| spectral_norm | 3.65 | -8% | +1% | -0% | -6% | -64% | +1% | -68% | -13% | -73% | +6% | +0% |
| mandelbrot | 1.32 | -23% | -1% | +2% | -22% | -1% | -0% | -1% | -1% | -22% | -0% | -1% |
| raytrace | 4.25 | -46% | -3% | -2% | -45% | -5% | +8% | -0% | -35% | -68% | -1% | +2% |
| knucleotide | 4.90 | -1% | +3% | -2% | -0% | -0% | -3% | -3% | -3% | -2% | -8% | +1% |
| text_ops | 6.86 | +0% | +0% | +1% | +0% | +1% | +2% | +1% | +2% | +0% | -8% | +0% |
| sort_builtin | 1.64 | -2% | +3% | -3% | +3% | +2% | +1% | -2% | +3% | +3% | -4% | +3% |
| sort_quick | 1.89 | +0% | -5% | -1% | -7% | -3% | -1% | -17% | -1% | -19% | -19% | -30% |
| sort_records | 5.32 | -0% | -1% | -0% | -1% | -0% | -1% | -3% | -6% | -9% | -7% | -0% |
| sieve | 7.14 | +1% | +1% | +0% | -0% | -8% | -12% | -17% | -4% | -19% | -58% | -75% |
| nbody | 71.72 | -17% | -10% | -0% | -5% | -13% | -12% | +0% | -6% | -17% | -67% | -93% |
| fannkuch_redux | 15.81 | +3% | -14% | +1% | -18% | -14% | -10% | -23% | -15% | -29% | -81% | -92% |
| matmul | 41.33 | -21% | -1% | -2% | -22% | -2% | -12% | -13% | -4% | -16% | -81% | -83% |
| **geomean** |  | **-10%** | **-2%** | **-1%** | **-11%** | **-11%** | **-3%** | **-14%** | **-7%** | **-26%** | **-36%** | **-49%** |

Each cell is the arm's time divided by the same program's unmodified time, both
paired against Zig in one batch. `roots` compares collector-off-without-roots
with collector-off, so memory behaviour is equal in both. `nbody`,
`fannkuch_redux` and `matmul` come from the 5-round batch on CPU 8, and their
baseline is the 16–72× list-write build. A rule's share of *that* baseline
understates what it costs once lane 5 removes the list writes: the NaN rule is
−17% of today's `nbody` but −56% of lane 5's (§4.2). §7's ladder measures the
rules in the order the plan would apply them.

Reading down the table: three mechanisms account for nearly all of the large
ratios, and none of them is "safety checks". The checks' visible cost comes
mainly from how their failure paths are lowered (§4.4). Removing the checks
themselves is worth 14% on the thirteen-program geomean.

### 4.1 Writing one element of a managed list

`xs[i] = v` and `xs[i].field = v` are the single largest cost in the suite.
Today each one does three things:

1. **Republishes the frame's GC root chain.** A list write calls
   `myl_native_list_set`. The emitter treats any call to a helper it does not
   know as a safepoint. So before the write it stores one 32-byte root record
   (previous link, address, value, descriptor) for every *traced local and
   operand slot* the frame keeps. After the write it restores the chain head. The
   frontend gives every `xs[...]` expression its own hidden receiver temporary,
   and root liveness keeps all of them live. The chain is therefore as long as
   the number of list expressions in the function, not the number of lists:
   **35 records per write in `nbody`'s `advance`** (all copies of the same
   `bodies` pointer), 22 in `fannkuch_redux`, 19 in `matmul`, 8 in the
   quicksort, and 7 in the sieve. Nothing in `list_set` allocates, so none of it
   is needed.
2. **Copies a record element out and back.** `bodies[i].vx = e` blits the
   whole 56-byte `Body` into scratch, stores the field, and passes the scratch to
   `list_set`, which copies it back. `advance` makes 9 such writes per pair of
   bodies: 27 blits and 9 runtime calls.
3. **Calls a helper that picks the element size at run time.**
   `myl_native_list_set` dispatches on `element->size` through a jump table.

```
# nbody advance: one `bodies[i].vx = bodies[i].vx - dx * bodies[j].mass * mag` (excerpt)
 %v578 =l add %v576, %v577          # &bodies[i]
 blit %v579, %l48, 56               # copy the whole Body out
 ...
 blit %v594, %v595, 56              # into the call's scratch
 storel %v597, %v596                # the one field
 %v604 =l add %heap, 16             # root chain head
 storel %v605, %root0 ...           # 35 root records, 5 stores each
 %v599 =w call $myl_native_list_set(l %v598, l %v601, l %v600)
```

The result is `nbody` at 71.7× Zig, `matmul` at 41.3×, and
`fannkuch_redux` at 15.8×. The programmer's workarounds confirm the
cause. The same `nbody` with `class Body` runs at 4.13×, because a
class field write is a plain store. `fannkuch_redux_tuned.my` uses `[10]int`
fixed arrays, whose `replace` lowers to plain stores (`QBE-ARRAYWRITE-1`), and
runs at 0.83× (with `n` a compile-time constant there, so not perfectly like for like). Removing only the root publication (with the
collector disabled in both arms, so memory behaviour is equal) takes `nbody`
from 69.1× to 22.9×.

**Lane 5 already fixes the write.** `QBE-LISTSET-1` emits the store inline
against the same bounds test; a write that names only `myl_qbe_fail_*` helpers
is not a safepoint, so the root chain goes. `QBE-ELEMREF-2`, `QBE-RETFWD-1`,
`QBE-CALLREF-1` and `QBE-CTORREAD-1` read elements and results where they live.
Measured here for the first time: `nbody` 71.7× → 4.93×,
`fannkuch_redux` 15.8× → 1.27×, `matmul` 41.3× →
7.10×, sieve 7.14× → 1.78×, quicksort 1.89× → 1.32×.
The root inflation itself remains at every *real* safepoint, and §6 fixes that
separately.

### 4.2 Canonicalizing NaN after every float operation

`docs/floating-point.md` promises that "arithmetic NaNs become the canonical
quiet NaN". The emitter keeps that promise at the operation: every float `+ -
* /` is followed by an unordered self-compare and a branch to an out-of-line
call, `myl_qbe_float_canonical`, that returns `0x7ff8000000000000`. The
call is deliberately opaque (a `volatile` read inside a `noinline` helper,
`QBE-FLOAT-CANON-1`) so that LLVM cannot turn it into a select on the critical
path. And because the branch holds a call, the emitter stores the source position
before every float operation. The inner loop of a dot product compiles to:

```
loop:  mov    (%r14),%rcx          # reload xs.len
       cmp    %rcx,%r15 ; jae fail
       mov    (%rdx),%rcx          # reload ys.len
       cmp    %rcx,%r15 ; jae fail
       mov    0x20(%r14),%rcx      # reload xs.storage
       vmovsd (%r12,%rcx),%xmm0
       mov    0x20(%rdx),%rcx      # reload ys.storage
       vmulsd (%r12,%rcx),%xmm0,%xmm0
       movq   $52,0x10(%rsp)       # position store
       vucomisd %xmm0,%xmm0 ; jp nan_1
       vaddsd ...                  # (accumulator through a GPR in the non-LTO unit)
       movq   $59,0x10(%rsp)       # position store
       vucomisd %xmm0,%xmm0 ; jp nan_2
       inc %r15 ; add $8,%r12 ; cmp ; jne loop
nan_1: call myl_qbe_float_canonical  # rejoins the loop
```

The branches cost little by themselves when the loop is latency-bound. The
damage is secondary. The cold call rejoins the loop, so LLVM must assume it can
write any memory. It then cannot keep list headers or class fields in registers,
cannot vectorize, and cannot if-convert. Removing only this rule gives
`mandelbrot` 1.32× → 1.02×, `raytrace` 4.25× → 2.27×, and the
class `nbody` 4.13× → 1.82×. The lane-5 record `nbody` goes from
4.93× to 2.17×. The rule is observable only through a NaN's bits,
so §5.1 proposes keeping the guarantee while moving the canonicalization to the
places where bits can be observed.

### 4.3 The runtime library's algorithms

Four programs are slow for reasons no code-generation change reaches.
`--unchecked` and every counterfactual leave them within noise:

- **`text_ops` (6.86× Zig).** A per-line/per-field `str` object is allocated for every `split`
  result; allocation plus collection is 41% of samples. `str.count` and
  `str.replace` test for a match at *every byte offset* with a `memcmp` call
  (`occurrences` and the replace loop in `src/native_text_methods.c`), while
  `find` already uses `memmem`. The same work written with one `byte_buffer`
  and in-place scans (`text_ops_tuned.my`) runs at 0.72×: the language
  can already express the fast version, but the obvious one is slow.
- **`knucleotide` (4.90× Zig).** Profile: text hashing 17%, dictionary probing 17%,
  key comparison 16%, allocation and collection of the slice keys 22%. Every
  slice `seq[i:i+k]` is a fresh copied `str` whose hash is computed once, byte
  by byte (FNV-1a). An integer key is also hashed byte by byte (8 FNV rounds plus
  an avalanche), and the get-then-set spelling probes twice for non-`str` keys.
  Packing the k-mer into an `int` (`knucleotide_tuned.my`) runs at 2.84×.
  About a third of the gap is slice allocation and two thirds is the dictionary.
- **Sorting.** `list.sort()` is a generic bottom-up merge in C. It has no
  small-run pass, compares through a size/order switch, and moves through
  `copy_element`. `sort_builtin` is 1.64× against Zig's block sort and
  Rust's `slice::sort` at 0.29×. `sort.sort_by_key`, in
  `src/stdlib/sort.my`, copies both halves and a fresh output list at every
  level of recursion: `sort_records` is 5.32× Zig, with a 225 MB peak for
  16 MB of data. The prelude's `sorted(key=...)` does the same job at
  1.62×.

### 4.4 Checked arithmetic costs through its failure path, not its test

With only the integer overflow checks stripped, `spectral_norm` drops from
3.65× to 1.31× (the counterfactual batch). At first sight that makes checked `+` the most expensive rule in
the suite. It is not. The test is a xor/and/compare and a predicted branch.
What costs is where the failing branch goes: a call to `myl_qbe_fail_*`, then
`jmp @failure`, a shared exit block that unlinks the frame record and returns 0.
Every check therefore adds a call and an edge into a common exit. That inflates
every function past LLVM's inlining threshold (in `spectral_norm` the hot
`a(i, j)` stays a real call) and joins all failure paths, which hides the
no-overflow fact from scalar evolution.

In an executable the fail helper never returns. The entry trampoline arms
`ctx->unwind`, and `fail()` in `src/qbe_runtime.c` builds the trace and
`longjmp`s. So ending the path in `unreachable` (QBE's `hlt`) instead of `jmp
@failure` is sound. It was checked, not just argued: an overflow three frames
deep and an out-of-range list write (`probes/trap_overflow.my`,
`probes/trap_index.my`) produce byte-identical stderr under the rewrite: code,
message, `in f at file:line` trace and structured `MYLANG-TRAP` record. The exit
status is also the same.

The rewrite keeps every check.

- **`spectral_norm`:** 3.63× → 2.14× in the ladder batch (§7's `lad-nr` column). Head to head on
  another P-core: 589 → 342 ms.
- **Thirteen-program geomean:** 5.77× → 5.33× (−8%).
- **`fib`:** nothing on a P-core (3.25× → 3.48× in the batch; 112.4 vs 113.1 ms
  head to head), though it is 23% faster on an E-core. `fib`'s cost is the
  frame protocol (§4.5).

Checks cost the comparators on `fib` too. Zig ReleaseSafe runs at 1.93× and
Rust with overflow checks at 1.82×: a check that may panic stops LLVM from
turning the double recursion into a loop. mylang with every check and the frame
protocol removed runs at 1.08×.

### 4.5 The frame protocol

Every call links a 32-byte record into `ctx->active_frame` (a load and three or
four stores), stores its metadata pointer, and unlinks it on return. A function
that calls also compares its frame against a stack floor on entry. An inlined
callee still links its own record. The record escapes through `ctx`, so no
function is ever `readonly` to LLVM. Priced per program: −7% on the thirteen-program geomean, −35% on `raytrace`, −13% on `spectral_norm`, −8% on the parser, and within noise on the library-bound programs.
It matters most for small functions returning records (`raytrace`
4.25× → 2.75×) and for pure call trees (`fib` 3.40× → 1.93×, with lane 5, `unreachable` failure paths and the language rules already applied). Roadmap item 2's
return-address map removes it. Its first attempt, a depth-indexed slot array, was
measured slower and reverted.

### 4.6 The collector: allocation, marking, roots

`binary_trees` is 2.17× Zig (Rust's `Box` port 1.84×). Its profile is
32% `myl_native_heap_alloc_at`, 20% `trace` and 19% `heap_collect`: 71% of
samples in the allocator and collector. Allocation is an out-of-line call that
validates the descriptor's alignment, checks four overflow and budget
conditions, looks up the size class, and then pops a free slot. The trigger
(three times the live bytes plus 4 MiB) makes every collection re-mark the
131,071-node long-lived tree, which never dies. Each node is also larger than it needs to be:
`Option[Node]` is a 16-byte `{tag, pointer}` value where Rust and Zig use a
nullable 8-byte pointer. So a node is 16 bytes of header plus 32 of payload,
against 16 in Zig. The arena variant runs at 1.35× Zig; removing its root
publication takes it to 1.18×. Peak memory is 11× Zig's.

### 4.7 Negative indices and the loop length re-check

Two more Python rules have no Zig or Rust counterpart:

- **Negative indices.** The frontend emits `if i < 0: i += len(xs)` (with a
  cast check and a checked add) before every list and text index. LLVM removes
  it when the index is an ascending induction variable from zero. It survives
  in quicksort's `j` and in `fannkuch_redux`'s `perm[k - i]`. Priced alone:
  −2% on the geomean, at most −14% on today's `fannkuch_redux` and −3% once lane 5 is in (§5.6).
- **The for-loop length re-check.** `for x in xs` snapshots `len(xs)` and
  compares the live length against it twice per iteration, trapping
  `R_LIST_ITERATION_MUTATION` if the list changed size. Priced alone:
  −1% on the geomean, at most −3% (§5.6).

### 4.8 Smaller items found on the way

- Every record-returning function zeroes its 24-byte result scratch with a
  `memset` call on entry (`%empty` in the emitted IL). Eight such calls survive
  LTO in `raytrace`.
- Float temporaries live in integer (`l`) slots with `cast`s, so a phi merges
  in the GPR domain and a non-LTO unit round-trips its accumulator through
  `vmovq` on the loop-carried chain.
- The frontend's hidden receiver temporaries also cost stores even where no
  root is published. Each `xs[...]` copies the list pointer into its own slot.
- `mylang check` writes a `.mylang-cache/` into the working directory.

### 4.9 Bugs the ports found

- **Quadratic stores inside `with arena()`.** Appending 1M then 2M strings to
  a list inside an arena takes 0.30 s then 1.15 s. The region barrier's
  `myl_native_arena_region` walks the arena's chunk list on every store, and
  each arena object adds a chunk-list entry. An arena-wrapped `knucleotide` is
  2.5× *slower* than the collecting heap. Repro: `suite/repro/arena_store_quadratic.my`.
- **Two `sorted(key=...)` crashes** (`host failure: InternalError` after a
  clean `check`). One is an identity key function. The other is any second
  callback value of the key's type elsewhere in the program. Repros:
  `suite/repro/agent_b_bug_sorted_key_*.my`.

## 5. Changes to the language itself

You asked whether the language should change. The measurements separate rules
that cost only because of how they are lowered, which should keep their meaning
while the lowering is fixed, from rules whose meaning is the cost. Only the second
kind justifies a language change, and there are fewer of them than the raw
ratios suggest.

### 5.1 Canonicalize NaN when it is observed, not when it is produced — **change**

*Today:* every float `+ - * /` result that is a NaN is replaced by the canonical
quiet NaN, at the operation (§4.2).
*Cost:* `mandelbrot` −23%, `raytrace` −46%, class `nbody` −56% (4.13× → 1.82×), lane-5 `nbody` −56% (4.93× → 2.17×), and −10% on the thirteen-program geomean. This is the largest cost in the suite that belongs to a
language rule. It blocks every loop optimization, not just the one compare.
*Peers:* Zig, Rust, C, Go and Swift propagate IEEE NaNs unchanged. Java
canonicalizes only in `Float.floatToIntBits`. WebAssembly's deterministic
profile canonicalizes at the points where bits become observable.
*Proposed rule:* a NaN's payload and sign are never observable. Every operation
that exposes a float's bits sees the canonical quiet NaN `0x7ff8000000000000`:
the `f64_*` bit-pattern intrinsics, a float written through the host, wire or
codec boundary, and any hash of a float. Text formatting already prints `nan`
whatever the payload. Ordinary arithmetic and comparisons propagate NaNs as
IEEE does. Programs cannot tell the difference, and cross-platform determinism is
unchanged, because a NaN is canonicalized before anything could see that x86 and
ARM produced different payloads.
*Change:* delete the branch in `qbe_scalar.floatBinary`. Add one
canonicalization at each observation site, all of them non-hot. Reword
`docs/floating-point.md`'s "Arithmetic NaNs become the canonical quiet NaN" to
"a NaN you can observe is the canonical quiet NaN". Small.

### 5.2 Keep checked `+ - *` as the default — **no change; fix the lowering**

*Today:* integer `+ - *` trap on overflow in every build; `wrapping_*` and
`saturating_*` choose other behaviour per operation; `--unchecked` drops every
check for a release build.
*Cost as lowered today:* −11% on the thirteen-program geomean, dominated by
`spectral_norm` (−64%).
*Cost once failure paths end in `unreachable`* (§4.4, sound in executables):
the lowering fix alone takes `spectral_norm` from 3.63× to 2.14× and the
geomean down 8%. What the checks still cost after that is the gap between the
last two ladder rungs (§7): 2.18× → 1.93× on the geomean (−11%). `spectral_norm`
is still −38% (1.65× → 1.02×), because its hot quantity `(i + j) * (i + j + 1)`
is checked even though `i, j < n`. That is about what the peers pay for the same
safety: Zig ReleaseSafe is 1.15× on the geomean and 1.36× on `spectral_norm`.
Range facts from `range()` induction variables would remove the residue there.
*Peers:* Swift traps like mylang does. Rust traps in debug and wraps in release.
Zig traps in ReleaseSafe and leaves overflow undefined in ReleaseFast.
*Decision:* keep trapping everywhere. Rust's split makes a program's result
depend on its build mode. Once the failure path is lowered correctly, the
residual cost matches what Zig pays for the same checks, and an overflow trap is
exactly the bug report an agent can act on.
`--unchecked` stays the explicit release opt-out; its measured effect is in §3.

### 5.3 Make fixed-size arrays ordinary mutable values — **change**

*Today:* `[N]T` is the fastest container in the language: a value with no
header, and `replace` writes in place. `fannkuch_redux_tuned.my` on `[10]int`
runs at 0.83× (with `n` a compile-time constant there, so not perfectly like for like), against 15.8× for the list version. But
`a[i] = v` is rejected (`E_LIST_TYPE`), so is `mut [N]T` as a parameter (the
message itself lists arrays as mutable), and so are indexed field writes and
`for` loops over an array (`E_COLLECTION_METHOD`). The fast form therefore reads
`a = replace(a, i, v)`, which no agent writes first.
*Proposed rule:* `a[i] = v` on an `[N]T` local or `mut` parameter is the
in-place write that `replace` already lowers to. `a[i].f = v` writes one
field. `for x in a` iterates. Value semantics are unchanged: assignment still
copies.
*Why it matters for speed:* when a program's sizes are known, the fastest
representation should also be the obvious spelling. Lane 5 makes lists fast
enough that this is about predictability as much as the last factor.

### 5.4 Share `str` slices instead of copying them — **change the representation, not the surface**

*Today:* `s[a:b]`, `split`, `splitlines` and `strip` allocate and copy a new
`str`. In `knucleotide` that is a third of the time and most of the 8× peak
memory. In `text_ops` it is the 200,000 line and 600,000 field objects behind
41% of samples in allocation and collection.
*Proposed rule:* none visible. `str` is immutable, so a slice can point into
its parent's payload, as in Go and in Java before 7u6. To bound retention, a
slice copies when it is small relative to a large parent: this is the one
policy choice, and Java's history is the warning. Hashing, equality and
printing already work on octet ranges.
*Size:* medium. The text header gains an owner pointer, the collector traces
it, and the arena escape copier learns the new shape.

### 5.5 Keyed sorting — **change the standard surface**

*Today:* `list.sort()` takes no `key=` or `reverse=`. `sort.sort_by_key` and
`sorted(key=)` accept only an `int` key, so there are no `str` or tuple keys.
The stdlib path is the slow one: `sort_records` runs at 5.32× Zig, the prelude
path at 1.62×, and a hand-packed `int` key through `list.sort()` at
Zig parity.
*Proposed:* Python's `list.sort(key=..., reverse=...)` and `sorted(...)` with
any orderable key: `int`, `float`, `str`, tuples of those. `sort.sort_by_key`
becomes a thin forwarder. The runtime specializes the comparison by key type
(§6.10).

### 5.6 Negative indices and the loop length re-check — **no change**

Both rules are Python's, and neither Zig nor Rust has them, so both were priced.
Skipping the negative-index normalization everywhere changes the
thirteen-program geomean by −2%. The largest effects are −14% on today's
`fannkuch_redux` and −5% on `sort_quick`. On the lane-5 compiler, all three
language-rule rewrites together move `fannkuch_redux` only from 1.18× to
1.14×. Dropping the loop length re-check changes the geomean by −1%, at most
−3%. The
batch's noise is about ±3%. LLVM already removes both wherever the index is an
ascending induction variable or the loop body cannot write the list. Changing
either rule would make `xs[-1]` or mutation during iteration behave unlike
Python, for a cost measured in single percent. Keep both. The residue the
compiler can still recover: `range()` loops give index-range facts, and the
`mut` markers mean a loop body that passes no list of that type as `mut` and
calls no mutating method on one cannot change the list's length.

### 5.7 Smaller surface items that push agents toward slow spellings

None of these changes speed by itself. Each made a porting agent write a slower
or noisier form, and the diagnostics said something misleading:

- `[x] * n` list repetition: `E_TYPE: expected list[bool], found int` instead of
  "not supported".
- Float and aggregate module constants (`E_CONSTANT_TYPE`,
  `E_CONSTANT_NAME`), so constants become zero-argument functions.
- `xs[i], xs[j] = xs[j], xs[i]` is `E_SYNTAX`.
- Tuple patterns in comprehensions (`[x + y for x, y in zip(a, b)]`) are
  `E_SYNTAX`.
- A nested `_` loop variable is `E_SHADOWING`.
- A lambda cannot fill a generic callback parameter (`E_LAMBDA_CONTEXT`, whose
  hint names the situation it is already in).
- `>>` gives `E_EXPRESSION` without pointing to `shift_right`.
- Option narrowing does not apply to field paths (`node.left`).

### 5.8 What should not change

- **Records as values.** Every record cost in the suite was lowering, and lane
  5 removes it. Zig, Rust, Go and Swift all have value structs.
- **A collecting heap by default.** The collector's cost in `binary_trees` is
  implementation (§6.5–6.7), and `with arena()` is already within 1.35× Zig of
  Zig. The GC port is 1.18× Rust's `Box` port.
- **Bounds checks.** Rust keeps them. Stripping every index check is worth
  3% on the geomean, 12% at most (`sieve`, `matmul`).
- **Python's floor `//` and `%`.** Against Rust's truncating `%` this costs a
  three-instruction sign fix-up where LLVM cannot prove the dividend is
  non-negative: about 13% on the `calls` and `records` kernels, per the Rust
  ports' notes. It is part of behaving like Python, and it is cheap wherever the
  sign is known.

## 6. Compiler and runtime changes (no change in meaning)

Ranked by measured effect over size. Each names what it removes and the
evidence behind it.

| # | change | removes | evidence | size |
|---|---|---|---|---|
| 6.1 | **Land lane 5** (`QBE-LISTSET-1`, `-ELEMREF-2`, `-RETFWD-1`, `-CALLREF-1`, `-CTORREAD-1`) | list writes as runtime calls behind a root chain; record copies out and back | §4.1: `nbody` 71.7× → 5.06×, `matmul` 41.3× → 7.10×, `fannkuch_redux` 15.8× → 1.30×, `sieve` 7.19× → 1.79×, `sort_quick` 1.87× → 1.31×, schematic 1.98× → 1.73×; −49% on the geomean, nothing slower beyond ±3% | code done, needs gate + timing |
| 6.2 | **Failure paths end in `unreachable`** in executables; the sticky path stays for libraries and the direct C entry points | the call-plus-shared-exit that blocks inlining and hides no-overflow facts | §4.4: `spectral_norm` 3.63× → 2.14×, geomean −7%, `fib` unchanged on a P-core | small: emitter policy + the adapter's parser accepting `hlt` |
| 6.3 | **Root liveness**: a hidden receiver temporary dies after its use; publish only values live across the safepoint | 7–35 root records per safepoint where one is live | collector off, with and without root records: −36% on the geomean; `fannkuch_redux` −81%, `matmul` −81%, `nbody` −67%, `sieve` −58%, `sort_quick` −19%, parser render −19% | small–medium |
| 6.4 | **Precise attributes on runtime helper declarations**: `noreturn cold` on `myl_qbe_fail_*`, `memory(inaccessiblemem)` or narrower on the helpers that touch no guest memory; after 6.2 and 6.8, `memory(argmem: read)` on guest functions whose signature says they cannot write (no `mut`, no effects, no allocation) | cold helper calls that force list-header reloads in every loop around them | lane 3 found the same limit: "no aliasing fact can change it: the loop body contains the grow call" | small, then medium |
| 6.5 | **Inline allocation fast path** for types known at compile time: bump or pop in the size class, write the two header words | `myl_native_heap_alloc_at`'s validation, budget and class lookup per object | `binary_trees`: 32% of samples | medium |
| 6.6 | **Collector steady state**: do not re-mark a long-lived set on every cycle (sticky mark bits or a young generation; lazy sweep) | `trace` + `heap_collect` = 39% of `binary_trees` | profile §4.6 | large |
| 6.7 | **Conservative stack scanning** instead of the shadow-stack root chain: the collector scans the guest stack and registers and maps words to objects through the segment table | every root record in generated code and in the C runtime | collector off, with and without root records: −36% on the geomean; `fannkuch_redux` −81%, `matmul` −81%, `nbody` −67%, `sieve` −58%, `sort_quick` −19%, parser render −19% | large; 6.3 captures much of it first |
| 6.8 | **Frame protocol → return-address map** (roadmap item 2): positions recovered from return addresses only when a trap fires | a 32-byte record link per call, the metadata store, position stores | −7% on the thirteen-program geomean, −35% on `raytrace`, −13% on `spectral_norm`, −8% on the parser, and within noise on the library-bound programs | large |
| 6.9 | **Niche `Option`**: `Option[T]` of a reference type is a nullable pointer | 8 of every 16 bytes of an optional reference; `binary_trees` nodes 48 → 32 bytes | §4.6 | medium |
| 6.10 | **Runtime library algorithms**: `count`/`replace`/`split` by `memchr`/`memmem`; scalar keys hashed with one multiply-xorshift and text 8 octets at a time; one probe for get-then-set for every key type; hash tags in the index so probing skips entry loads; `list.sort` specialized per element type with run detection; `sort_by_key` forwarding to the fast keyed sort; arena region lookup by header depth instead of a chunk walk | §4.3, §4.9 | `text_ops`, `knucleotide`, `sort_*`, the arena bug | small each |
| 6.11 | Small lowering fixes: no `memset` of record-result scratch; float temporaries in `d` slots; one position store per NaN branch instead of per float op (moot after 5.1) | §4.8 | a few % where they occur | small |
| 6.12 | Fix the two `sorted(key=...)` crashes | §4.9 | — | small |

## 7. The plan

Five waves. Waves 0–2 and wave 3's first item are small or already written and
can run as parallel agent lanes. Wave 4 is the long pole. Every wave's
acceptance is a ratio from this suite, measured in one interleaved batch against
the Zig port, with byte-identical output.

### What each wave buys, measured by composition

The ladder below builds each program with one more wave applied, cumulatively,
using the same counterfactual rewrites as §4 on top of the lane-5 compiler. It
is **measured**, not added up. Items that cannot be expressed as a rewrite (the
library algorithms, `str` views, fixed-array spelling, collector work, the
`Option` niche) are not in it. For those, the tuned variants in §3 give the
achievable number.

| program | today | today + noreturn | lane 5 | lane 5 + noreturn | + language rules | + no frame record | unchecked bound | Rust | Zig safe |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| binary_trees | 2.01 | 1.98 | 2.03 | 2.01 | 1.99 | 1.89 | 1.92 | 1.75 | 1.07 |
| spectral_norm | 3.63 | 2.14 | 3.68 | 2.00 | 1.76 | 1.65 | 1.02 | 1.02 | 1.36 |
| mandelbrot | 1.32 | 1.32 | 1.31 | 1.32 | 1.02 | 1.02 | 1.03 | 1.02 | 1.00 |
| raytrace | 4.68 | 4.29 | 4.89 | 4.55 | 2.19 | 1.55 | 1.41 | 0.98 | 1.05 |
| knucleotide | 4.95 | 4.91 | 4.94 | 4.90 | 4.90 | 4.90 | 4.85 | 1.67 | 1.15 |
| text_ops | 6.51 | 6.87 | 6.77 | 6.93 | 6.98 | 6.88 | 7.00 | 1.59 | 0.85 |
| sort_builtin | 1.60 | 1.68 | 1.61 | 1.67 | 1.69 | 1.60 | 1.62 | 0.31 | 1.17 |
| sort_quick | 1.87 | 1.70 | 1.31 | 1.28 | 1.13 | 1.12 | 0.99 | 0.95 | 1.18 |
| sort_records | 5.33 | 5.38 | 5.28 | 5.41 | 5.31 | 4.95 | 4.74 | 0.40 | 1.18 |
| sieve | 7.19 | 6.91 | 1.79 | 1.82 | 1.90 | 1.65 | 1.38 | 1.02 | 1.34 |
| nbody | 71.72 | 61.38 | 5.06 | 5.13 | 2.39 | 2.33 | 1.87 | 1.11 | 0.96 |
| fannkuch_redux | 15.81 | 13.13 | 1.30 | 1.18 | 1.14 | 1.14 | 0.95 | 0.97 | 1.24 |
| matmul | 41.33 | 40.70 | 7.10 | 6.00 | 3.90 | 3.80 | 2.88 | 2.21 | 1.58 |
| **geomean** | **5.77** | **5.33** | **2.98** | **2.79** | **2.31** | **2.18** | **1.93** | **1.02** | **1.15** |

Read along a row. The programs bound by code generation close most of their
gap:

| program | today | after the ladder |
|---|---:|---:|
| `nbody` | 71.7× | 2.33× |
| `matmul` | 41.3× | 3.80× |
| `fannkuch_redux` | 15.8× | 1.14× |
| `sieve` | 7.19× | 1.65× |
| `raytrace` | 4.68× | 1.55× |
| `spectral_norm` | 3.63× | 1.65× |
| `sort_quick` | 1.87× | 1.12× |
| `mandelbrot` | 1.32× | 1.02× |

`knucleotide`, `text_ops`, `sort_builtin` and `sort_records` do not move,
because their cost is the runtime library. `binary_trees` moves only from
2.01× to 1.89×, because its cost is the collector.

On the thirteen-program geomean the steps are:

- lane 5: 5.77× → 2.98×, the largest single step
- failure paths ending in `unreachable`: 2.98× → 2.79×
- the language rules: 2.79× → 2.31×
- no frame record: 2.31× → 2.18×

Stripping every remaining check as well gives 1.93×. Cells that move the wrong
way (`text_ops` and `sort_records`, up to +6%) are noise on short runs: none of
the rewrites touches their hot code.

Three caveats about the table:

- The first ten rows are one batch (CPU 6, 7 rounds). `nbody`, `fannkuch_redux`
  and `matmul` are the slow batch (CPU 8, 5 rounds).
- The language rung removes the two Python rules §5.6 *keeps* as well as the NaN
  rule. They are worth about 3% together on the geomean (§4), so the plan as
  written lands about 3% above that column: near 2.25×.
- The columns are counterfactual binaries, not a built compiler. Each wave's
  acceptance is to reproduce its column without rewriting.

### Wave 0 — correctness and the runtime library (small, independent)

1. The two `sorted(key=...)` crashes and the quadratic arena store (6.12, the
   arena half of 6.10).
2. Text scanning by `memchr`/`memmem` in `count`, `replace` and `split`.
3. Dictionary: word-at-a-time hashing for scalar and text keys, one probe for
   get-then-set for every key type, hash tags in the index.
4. Sorting: `list.sort` specialized per element type with run detection;
   `sort_by_key` forwarding to the keyed path.

*Acceptance:*

- `count` and `replace` within 1.5× of Zig's `std.mem` on a 4 MB text, and
  `text_ops` ≤ 5×. Its per-field objects remain until 5.4, which brings it to
  ≤ 1.3×.
- `knucleotide` ≤ 3×, and ≤ 1.5× after 5.4.
- `sort_builtin` ≤ 1.0× Zig's block sort.
- `sort_records` ≤ 1.5×.
- An arena-wrapped `knucleotide` no slower than the collecting one.

### Wave 1 — land the paused lanes

1. **Lane 5** (6.1). Its code is complete and Guardian-green. It needs the full
   gate on a clean cache, the merge into `perf/schematic-integration`, and the
   timing it never got. This audit supplies the timing (§4.1).
2. Lanes 6 (output emission) and 8 (invocation cache) for the schematic tool,
   and lane 7 (step batching) for bounded runs. These matter to the tool, not to
   this suite.

*Acceptance:* the `lad-l5` column: `nbody` 5.06×, `fannkuch_redux`
1.30×, `sieve` 1.79×, `matmul` 7.10×, with no program slower
than today.

### Wave 2 — lowering that keeps the meaning

1. Failure paths end in `unreachable` in executables (6.2).
2. Root liveness for hidden receiver temporaries (6.3).
3. Helper attributes (6.4, first half); no `memset` of result scratch; float
   temporaries in `d` slots (6.11).

*Acceptance:* the `lad-l5-nr` column without rewriting (`spectral_norm` 2.00×,
geomean 2.79×), traps byte-identical to today's, and each safepoint publishing
roots only for values live across it. The checks' remaining cost on the geomean
should be ≤ 10% (8% measured, §5.2).

### Wave 3 — the language changes

1. NaN canonicalized when observed (5.1). *Acceptance:* the `lad-l5-nr-lang`
   column, e.g. `mandelbrot` 1.02×, `nbody` 2.39×, `raytrace`
   2.19×.
2. Fixed-size arrays as ordinary mutable values (5.3).
3. Keyed sorting in the standard surface (5.5).
4. Shared `str` slices (5.4). *Acceptance:* `knucleotide` ≤ 1.5×, `text_ops`
   ≤ 1.3×, peak memory ≤ 2× Zig.
5. No change to negative indexing or the loop length re-check (§5.6). Making their residue free is ordinary lowering work (range facts, `mut` markers) that fits wave 2.

Each language item needs its `SPEC.md` bullets, the `docs/` page
(`floating-point.md`, `records-and-unions.md`, `text.md`, `standard-library.md`)
and `features.json` entries, per the documentation gate.

### Wave 4 — the runtime architecture

1. Frame protocol → return-address map (6.8, roadmap item 2). *Acceptance:* the
   `lad-l5-nr-lang-fr` column; `fib` ≤ 1.3×; `raytrace` 1.55×.
2. Inline allocation fast path (6.5) and niche `Option` (6.9). *Acceptance:*
   `binary_trees` ≤ 1.5× on the collecting heap and ≤ 1.15× in an arena.
3. Collector steady state (6.6), then conservative stack scanning (6.7) if 6.3
   has not already removed the root chain's cost. *Acceptance:* peak RSS ≤ 1.5×
   Zig across the suite; `binary_trees` trace + collect ≤ 15% of samples.
4. With 6.8 in, pure guest functions are `readonly` to LLVM (6.4, second half).

### Wave 5 — keep it measured

- Commit this suite and its harness as the standing performance benchmark,
  beside the micro-kernels, the parser and the schematic, with an opt-in `zig
  build bench-parity` step and ratio thresholds per program rather than
  absolute times.
- Enable hardware counters (`kernel.perf_event_paranoid ≤ 1`) so instruction
  and cycle counts can back the wall-time ratios; every audit since 18 September
  has been limited to wall time and SIGPROF samples.
- Re-measure after each wave on a quiet machine, and never compare across
  batches.

### Projection, stated as such

The ladder stops at 2.18× (1.93× unchecked) because four programs are bound
by the library. For those, the tuned variants measure what the same work costs
when it avoids the slow library paths: `text_ops` 0.72×, `knucleotide` 2.84×,
and `sort_records` through `sorted(key=)` 1.62×. Substituting them into the
ladder's last checked column gives a geomean of about **1.6× with every check
on**, and about **1.4× unchecked**. That is a projection from measured proxies,
not a measurement of a built compiler.

It still leaves five programs above 1.5×:

- `matmul` 3.8×: nested lists still do not vectorize.
- `knucleotide` 2.8×.
- `nbody` 2.3×.
- `binary_trees` 1.9×.
- `sort_builtin` 1.6×.

Closing those to the ≤ 1.2× target is the wave-4 collector and allocation work.
It also needs the parts of wave 0 that no proxy measures: a sort faster than
Zig's block sort (Rust's is 3.2× faster) and a dictionary at the speed of Zig's
`getOrPut`. Finally, float loops must vectorize, which needs the NaN change, the
header hoisting of 6.4 and the bounds check lifted out of the loop.

### As agent lanes

The waves split into independent branches that touch disjoint files. That is how
the earlier roadmap and schematic lanes ran: each on its own branch from one
base, each gated separately before an integration merge.

| lane | wave | branch | touches | done when |
|---|---|---|---|---|
| text scans | 0 | `perf/lib-text-scan` | `src/native_text_methods.c`, `native_text.c` | `count`/`replace`/`split` over 4 MB within 1.5× of Zig's `std.mem` equivalents; `text_ops` ≤ 5× |
| dictionary | 0 | `perf/lib-dict-hash` | `src/native_dictionary.c` | `knucleotide` ≤ 3×, `knucleotide_tuned` ≤ 1.5×, `dict_count` ≤ 1.2× |
| sorting | 0 | `perf/lib-sort` | `native_collections.c`, `src/stdlib/sort.my` | `sort_builtin` ≤ 1.0× Zig, `sort_records` ≤ 1.5×, peak ≤ 2× |
| bugs | 0 | `fix/arena-region-lookup`, `fix/sorted-key-crash` | `native_regions.c`/`native_arena.c`; the key-callback lowering | the three repros pass |
| lane 5 | 1 | `perf/schematic-5-aggregate-reads` | already written | full gate green; the `lad-l5` column reproduces |
| failure paths | 2 | `perf/noreturn-fail-paths` | `src/qbe*.zig` emit policy, the adapter's parser, `llvm_emit` declarations | the `lad-nr`/`lad-l5-nr` columns reproduce without rewriting |
| root liveness | 2 | `perf/root-liveness` | the bytecode frontend's hidden temporaries, `src/qbe.zig` safepoint roots | root records per safepoint = live traced values |
| NaN | 3 | `lang/nan-when-observed` | `src/qbe_scalar.zig`, the `f64_*` intrinsics, host/wire encoders, `docs/floating-point.md`, `SPEC.md` | the `lad-l5-nr-lang` column reproduces; canonical-NaN tests move to the observation points |
| fixed arrays | 3 | `lang/fixed-array-writes` | checker, bytecode, `qbe_aggregate.zig`, `docs/records-and-unions.md` | `a[i] = v`, `a[i].f = v`, `mut [N]T`, `for x in a` on `fannkuch_redux` |
| keyed sort | 3 | `lang/keyed-sort` | prelude, `docs/standard-library.md` | `list.sort(key=, reverse=)`, non-`int` keys |
| string views | 3 | `perf/str-views` | `native_text.c`, the collector, `native_regions.c` | `knucleotide` ≤ 1.5×, `text_ops` ≤ 1.3× |
| frame map | 4 | `perf/frame-return-map` | frame protocol, trap trace, `--max-frames` | the `lad-l5-nr-lang-fr` column reproduces with trap traces intact |
| allocation | 4 | `perf/inline-alloc`, `perf/option-niche` | `src/qbe_managed.zig`, `native_heap.c`, value layout | `binary_trees` ≤ 1.5× |
| collector | 4 | `perf/gc-steady-state` | `native_heap.c` | `binary_trees` trace + collect ≤ 15% of samples; RSS ≤ 1.5× Zig |

## 8. Method and limits

- **Ports.** Four agents wrote the suite and the Rust micro-kernel ports from
  `suite/SUITE.md`, which fixes the algorithm, sizes, float operation order and
  output format. Every port prints byte-identical stdout, checked on every timed
  run and against independent CPython transcriptions of the spec. No binary
  contains a fused multiply-add. The ports are idiomatic by instruction: no
  SIMD, threads, `unsafe` or crates. Where the idiomatic Zig or Rust differs
  materially from mylang's data layout (flat matrices, slices as dictionary
  keys, `Box` against a tracing heap), the difference is the comparison, and
  `suite/NOTES-agent-*.md` records it per program.
- **Builds.** mylang: `mylang build` default (ReleaseFast, LLVM O3 + LTO,
  native CPU), `--unchecked` for the unchecked arm. Zig 0.17.0-dev.1683:
  `-O ReleaseFast` and `-O ReleaseSafe`. Rust 1.98.1: `-C opt-level=3 -C
  codegen-units=1 -C target-cpu=native -C panic=abort`, plus `-C
  overflow-checks=on` for the checked arm. Zig and Rust share LLVM 22.1.8 with
  mylang's adapter toolchain.
- **Timing.** `bench.py`: fresh processes pinned to one P-core (CPU 6 for the
  fast programs, CPU 8 for `nbody`/`fannkuch_redux`/`matmul`), stdout to
  `/dev/null`, arms shuffled inside every round, 2 warm-ups then 7 rounds (5 for
  the slow batch), medians of per-round paired ratios with 95% bootstrap
  intervals, wall and child CPU time both recorded. The two batches ran
  concurrently on different physical cores, and other sessions' processes
  (load average 2–4) shared the machine. The interleaving keeps each ratio fair
  to both arms, but absolute milliseconds are not comparable across batches or
  with earlier audits.
- **Counterfactuals** edit the emitted manifest and rebuild through
  `--manifest-file`. The unmodified rebuild was byte-identical to a plain build
  for every program. A rewritten binary cannot report what it no longer checks.
  The `roots` rewrite is sound only with the collector disabled, so it is priced
  against a collector-disabled control (`cf-nogc`), never against the ordinary
  build. The noreturn rewrite needs QBE's `hlt`, which the stock adapter's parser
  refuses although its emitter lowers it; a one-branch patch
  (`adapter-hlt.patch`) was applied, and with it every unmodified build stayed
  byte-identical.
- **Profiles** are SIGPROF self-PC samples (hardware counters are disabled:
  `perf_event_paranoid=4`) of non-LTO `--keep-symbols` builds, so runtime
  functions keep their names. Shares are of CPU time, not cycles.
- **Not covered.** Multi-threaded code (the language has none), I/O-bound
  programs, compile time (the schematic tool's ~1 s per invocation is compile
  time, which lane 8 targets), and memory-limited behaviour beyond peak RSS.
