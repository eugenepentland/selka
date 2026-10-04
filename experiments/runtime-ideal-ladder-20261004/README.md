# Ideal ladder pilot: `integer_math`, 2026-10-04

`int_math.c` re-implements kind 0 of `benchmarks/runtime/expanded/compute/main.my` in
versions v1–v10. Each version gives the compiler one more fact or makes one more
representation choice. Every version prints the benchmark's checksum: `561601106` for
`4096 300 7`, and also identical at sizes 64 and 4100.

```bash
zig cc -O3 -o int_math int_math.c                  # native (alderlake), like MyLang LLVM
zig cc -O3 -mcpu=x86_64 -o int_math_base int_math.c   # baseline x86-64, like the Rust arm
taskset -c 10 ./int_math 5 4096 4000 7             # version, size, iterations, seed
```

## Results

The reference binaries were the B0 runner's `compute-rust`, `compute-zig-fast` and a
fresh `--release` build of `compute/main.my`.

**Method and caveats.** Exploratory measurements only, not campaign evidence:
- seven interleaved rounds per version, on CPU 9;
- the host was busy with other lanes, and SMT siblings were sometimes contended;
- compare values within one table only.

| Version | Fact or choice added | Ratio to Rust, large / small | Cycles/elem |
|---|---|---:|---:|
| mylang LLVM (today) | — | 1.87 / 1.80 | 11.4 |
| Rust (fastest arm) | — | 1.00 / 1.00 | 5.8 |
| v1 | Today's semantics without the `kind` dispatch | 1.94 / 1.83 | — |
| v2 | + L2 sticky overflow, immutable list, one bounds check | 2.04 / 2.00 | — |
| v5 | + element range 0..1008 and phase 0..16 (`__builtin_assume`; i64 and floor kept) | 0.31 / 0.32 | 1.75 |
| v5, baseline x86-64 | v5 without AVX2 | 0.51 / 0.44 | — |
| v10 | + u16 storage and u16 arithmetic, written in plain C | — | see note |
| v9 | u16 arithmetic over i64 storage | — | see note |
| v6 | Hand AVX2 intrinsics over i64 storage | 0.08 / 0.10 | 0.48 |
| v7 | Hand AVX2 intrinsics over u16 storage | 0.06 / 0.08 | 0.35 |
| v8 | Work elimination: 17 memoized phase totals | 0.002 / 0.026 | — |

The cycles column comes from one `perf stat -e cpu_core/cycles/u` run at size 4096 with
4000 iterations. A later run on a busier core measured v5 2.06, v6 0.665, v7 0.454,
v9 2.08 and v10 0.872 cycles/elem:
- **v10** is 2.4× better than v5;
- **v9** is no better than v5, because LLVM could not narrow i64 loads into 256-bit
  vectors;
- **v7** is still about 1.9× better than v10.

## Conclusions

1. **The element range is the fact that matters.** It is derivable from the comprehension
   that builds the never-mutated list. With it, checks can be omitted under
   RELEASE-CHECKED-1, floor division equals truncation, and LLVM vectorizes on its own.
2. **L2-style sticky checks and hoisted bounds gave no gain on this kernel.** Predicted
   branches are cheap; what they block is vectorization.
3. **LLVM does not narrow i64 arithmetic by itself.** The front end must emit the
   narrowest proven width, and narrow storage is needed to get 256-bit vectors.
4. **Hand vectorization is about 2× over LLVM's best from C.** It uses `packus` narrowing
   and `vpmaddwd` reductions.
5. **The estimated port-throughput floor is about 0.25 cycles/elem.** Raw assembly beyond
   intrinsics is worth at most about 1.4×.
6. **"Fastest possible" needs a work contract.** v8 is legal but meaningless as a
   benchmark result.

---

# Part 2: the eight other cases (WP-9), 2026-10-04

`float_math`, `list_filter`, `dict_lookup`, `tagged_stack`, `string_split`, `branch_mixed`, the **parse
component** of `json_transform`, and the **dispatch loop** of `lox_eval`. The method is the pilot's: re-implement
exactly the timed work in C, reproduce the benchmark checksum, then add one fact or representation choice per
rung. Everything here is exploratory, on a busy shared host, and not campaign evidence.

## How to read this part

- **Machine.** i7-12700H P-core (Golden Cove: AVX2, FMA, no AVX-512), pinned to CPU 10. Compiler `zig cc -O3`
  with native features (the MyLang LLVM policy), plus `-ffp-contract=off` (mylang's FLOAT-DOMAIN-1 says separate
  operations) and `-fno-strict-aliasing` (the QBE IL carries no TBAA). `build.sh` also builds each case with
  `-mcpu=x86_64` (the Rust policy, no AVX2) as `<case>_base`; hand-AVX2 rungs exist only in the native build.
- **Timing.** `ladder.py time CASE`: one warm-up round plus 7 interleaved rounds, rung order shuffled per round,
  the B0 `rust`, `go`, `zig-safe`, `zig-fast` and `my-llvm` binaries in the same rounds. Tables show the
  median. Wall times on this host wobble 10–20% between runs, so **compare rows within one table only**.
- **Counters.** `ladder.py perf CASE`: `cpu_core/cycles`, `instructions`, `branch-misses` and
  `ld_blocks.store_forward` (user mode), median of 3 runs, one iteration's worth obtained by subtracting a
  1-iteration run. Cycle counts reproduce to a few percent; the exception is branchy hash probing (below).
  The "unit" is stated per case (element, lookup, step, fragment, row, loop iteration).
- **Checksums.** Every rung of every case reproduces the B0 `rust` checksum at both profile sizes and at 7 to
  10 (size, iterations, seed) triples in all, including the edge probes 2/3/17 and seeds 1/42/999983
  (`ladder.py verify CASE`). Hand-written vector kernels that rely on a data bound trap (or fall back) when the
  bound does not hold; the holdout inputs include values outside the fixture's range to exercise those paths.
- **Step 0 is a model.** It is written from the mylang source (`src/native_*.c`, `src/stdlib/json.my`) and from
  the disassembly of the B0 `my-llvm` binaries, then checked against that binary. How close it is:

  | case | step 0 cycles / unit (large) | B0 my-llvm | model / B0 | evidence the shape is right |
  |---|---:|---:|---:|---|
  | float_math | 13.3 (v0, with dispatch) | 11.7 | 114% | B0 makes a `call` per `int(float)`; so does v0 |
  | list_filter | 11.4 | 13.8 | 83% | per-append `plain_ready` call, header stores per element |
  | dict_lookup | 51.1 | 51.4 | 100% | same probe code; branch misses 0.51 vs 0.49 per lookup |
  | tagged_stack | 84.6 | 88.3 | 96% | `ld_blocks.store_forward` 1.83 per step in both |
  | string_split | 141 | 203 | 69% | owned pieces, encode copies, deferred drain |
  | branch_mixed | 5.3 (no dispatch) | 6.9 | 77% | |
  | json parse | 2 855 (whole job) | 13 666 | 21% | **weakest model**: B0 runs 51 k instructions per row, the model 11 k |
  | lox_eval | 666.6 | 665.3 | 100% | `ld_blocks.store_forward` 17.0 vs 15.3 per loop iteration |

  Where the model is below B0, the first rungs understate what the same change would save in the real binary.
- **Categories.** Each fact or choice is classified as (a) derivable by the compiler from today's source and
  rules (including "pure implementation" fixes that need no fact at all), (b) needs a language rule change (the
  rule named, and whether L2/L3 already cover it), (c) needs the programmer to state it (a type, annotation or
  API; a library kernel counts here), (d) true of the fixture only, which is not allowed.
- **WORK ELIM rungs** replace required work with arithmetic (closed forms, memoization, partial evaluation of a
  constant program). They mark where "fastest possible" stops meaning anything and are **excluded from every
  conclusion and ranking**.
- **Holdout rungs** read their data from a file (`ladder.py` writes it with the case's `gen` mode) and keep only
  the facts that survive without the fixture's generators. Where a fixture fact is replaced by a runtime guard
  (min/max pre-pass, program scan), the pre-pass is inside the timed region.
- **Not covered:** `integer_math` (pilot, not re-measured); the fixture's per-element `kind` dispatch is studied
  only in `float_math` (v0 vs v1); Go has no counter column (it was left out of the perf runs). The sparse-key dictionary file gives the same
  checksum as the benchmark, because hits depend only on the query index.

## 1. `float_math` (`float_math.c`)

**Timed work.** For each of `size` elements: `x = values[j]` (immutable `list[int]`, `(seed + 37j) % 1009`),
`int(((float(x)/8 + float(phase)/4) * (float(x)/16 + 1) + 0.5) * 128)`, summed with checked adds, one `% 1000000007`
per pass. Unit: element. Sizes 64 / 4096.

**The fastest arm** is Zig ReleaseFast (4.3 cycles/element); Rust and Zig-safe sit at 6.5–7.0 cycles and Go is within 5% of Rust in time. The Zig-fast
disassembly keeps the `kind` switch inside the element loop as a jump table and does scalar f64 with `vcvttsd2si`:
none of the competitors vectorize this kernel. **Today's mylang** (11.7 cycles) has a `call myl_qbe_float_unary` for
every `int(float)` (`src/qbe_runtime.c:764`: an out-of-line op switch, `trunc`, `isfinite`, two range compares).

| step | x Rust (small / large) | x fastest arm (small / large) | ns/unit (large) | cycles/unit | instr/unit |
|---|---:|---:|---:|---:|---:|
| v0: today incl. in-loop kind dispatch | 1.81 / 1.85 | 2.71 / 2.83 | 3.937 | 13.28 | 51.0 |
| v1: dispatch unswitched: bounds check, runtime-call int(float), checked add | 1.69 / 1.71 | 2.52 / 2.61 | 3.636 | 12.00 | 42.0 |
| v2: + inline checked int(float) | 0.88 / 0.97 | 1.31 / 1.48 | 2.059 | 6.41 | 22.0 |
| v3: + immutable list, one bounds check, sticky checks (L2) | 0.97 / 1.07 | 1.46 / 1.63 | 2.272 | 7.30 | 22.0 |
| v4: + element range: no checks (f64, i64) | 0.44 / 0.50 | 0.66 / 0.76 | 1.055 | 3.42 | 8.2 |
| v13: v4 + result range assume (types stay i64) | 0.45 / 0.52 | 0.67 / 0.79 | 1.104 | 3.42 | 8.2 |
| v5: + i32 conversions (plain C) | 0.22 / 0.20 | 0.33 / 0.30 | 0.424 | 1.38 | 3.5 |
| v6: + u16 storage (plain C) | 0.20 / 0.20 | 0.29 / 0.31 | 0.436 | 1.38 | 3.2 |
| v7: hand AVX2 f64, i64 storage | 0.18 / 0.18 | 0.28 / 0.27 | 0.376 | 1.25 | 3.6 |
| v8: hand AVX2 f64, u16 storage | 0.20 / 0.19 | 0.30 / 0.29 | 0.409 | 1.29 | 3.4 |
| v9: + FMA contraction | 0.15 / 0.15 | 0.23 / 0.23 | 0.323 | 0.94 | 2.9 |
| v10: f32 lanes (precision narrowing) | 0.07 / 0.05 | 0.11 / 0.08 | 0.117 | 0.38 | 1.3 |
| v11: WORK ELIM: integer identity | 0.06 / 0.04 | 0.09 / 0.07 | 0.095 | 0.30 | 0.9 |
| v12: WORK ELIM: closed form | 0.04 / 0.00 | 0.06 / 0.00 | 0.002 | 0.00 | 0.0 |
| v30 holdout: data from file, v3 (no range) | 1.00 / 1.05 | 1.50 / 1.60 | 2.233 | 7.31 | 22.0 |
| v31 holdout: data from file, runtime range guard + AVX2 | 0.20 / 0.20 | 0.29 / 0.31 | 0.425 | 1.24 | 3.5 |
| v3 baseline x86-64 (no AVX2) | 0.99 / 1.07 | 1.49 / 1.64 | 2.284 | 7.75 | 25.0 |
| v4 baseline x86-64 | 0.53 / 0.55 | 0.79 / 0.85 | 1.178 | 3.93 | 10.8 |
| v5 baseline x86-64 | 0.37 / 0.38 | 0.56 / 0.58 | 0.809 | 2.74 | 7.8 |
| v6 baseline x86-64 | 0.35 / 0.39 | 0.52 / 0.60 | 0.835 | 2.70 | 7.8 |
| B0 rust | 1.00 / 1.00 | 1.50 / 1.53 | 2.129 | 6.98 | 26.0 |
| B0 go | 1.02 / 0.96 | 1.53 / 1.47 | 2.044 |  |  |
| B0 zig-safe | 0.96 / 0.95 | 1.43 / 1.45 | 2.014 | 6.51 | 24.0 |
| B0 zig-fast | 0.67 / 0.65 | 1.00 / 1.00 | 1.392 | 4.32 | 20.0 |
| B0 my-llvm | 1.67 / 1.74 | 2.50 / 2.66 | 3.701 | 11.69 | 46.0 |

| rung | fact or choice | cat | cycles effect | needs |
|---|---|:-:|---|---|
| v0→v1 | the loop-invariant `kind` switch is unswitched | a | 1.11× | loop unswitching on a local never reassigned in the loop |
| v1→v2 | `int(float)` lowered inline (`cvttsd2si` + `a >= -2^63 && a < 2^63`) | a | **1.87×** | nothing new: same semantics, same trap; brings mylang to Zig-safe parity (6.4 vs 6.5) |
| v2→v3 | immutable list, one hoisted bounds check, sticky overflow and conversion flags | b (L2 covers it) | **0.88× (slower)** | the flags cost instructions and the loop is not vectorizable anyway; same finding as the pilot |
| v3→v4 | element range [0,1009) and phase [0,17) from the `% 1009` comprehension: `float(x)` exact, the conversion cannot trap, the sum cannot overflow | a | **2.13×** | interval analysis through float expressions; the list is built in `main` and read in the same function |
| v4→v13 | the same ranges given to LLVM as `assume` on `x` **and** on the converted result | a (marker route) | 1.00× | **LLVM does not narrow `sitofp i64` / `fptosi i64` from range information**; this is the evidence that WP-6a markers alone cannot unlock the vector loop |
| v13→v5 | the front end emits the narrow types: `i32` int→f64 and f64→`i32` (`vcvtdq2pd` / `vcvttpd2dq`), u64 accumulation | a (given the range) | **2.47×** | WP-8 style emission of narrow integer ops; then LLVM vectorizes by itself (5× faster than Rust) |
| v5→v6 | list stored as u16 | a | 1.00× | none needed here; the loop is compute-bound |
| v5→v7/v8 | hand AVX2 (4 lanes of f64, no FMA) over LLVM's autovectorization | c | 1.10× | LLVM's vector code is already within 10% |
| v8→v9 | FMA contraction (`fmadd`) | b (FLOAT-DOMAIN-1 says separate operations) | 1.37× | a contraction rule, or an explicit `fma` (c); results are exact for this fixture only |
| v9→v10 | f32 lanes: every intermediate has at most 24 significant bits | a, but a bit-width analysis of float code | 2.5× | contradicts the contract's "f64 for floating calculations"; shown as a bound, **not** in the ranking |
| v11, v12 | integer identity `(x+2p)(x+16)+64`; closed form from Σx, Σx² | WORK ELIM | — | excluded |

Baseline x86-64 build of the key rung: v5 is 2.74 cycles/element without AVX2 vs 1.38 with it, so on this kernel
the single-platform decision (L4) is worth 2×; even without AVX2 the narrowed loop is 2.5× faster than Rust.

**Holdout (`v30`, `v31`).** With the data read from a file there is no range: the best fact-free code (v30 =
v3's form) is Rust speed (7.3 cycles). A runtime guard (one pass over the immutable list proving 0 ≤ x ≤ 40000, so
the arms fit in 32 bits, hoisted out of the pass loop) selects the AVX2 kernel (v31, 1.24 cycles) and keeps
essentially the whole gain. The guard falls back to the exact scalar version when it fails; checksums agree with
the exact reference on files with values up to 3 000 000 (the guard falls back above 40 000) and every version traps alike at 2·10^10.
Category (a): loop versioning on a property of an immutable list, a transform no pass does today.

**Conclusions.** (1) The L1 gate needs **no new fact** here: an inline conversion alone reaches Zig-safe parity.
(2) The range fact is worth 2.1×, but only converts into vector speed when the front end also emits narrow types
(v13). (3) L2's sticky checks do not help. (4) FMA is the only rule change with a visible effect (1.4×), and it
changes results in general.
**Plan.** Supports WP-8 (direct emitter) over WP-6a markers (v13); WP-3 gets no support; L4 supported (2× from AVX2).
A small item not in the plan: lower `int(float)` inline.

## 2. `list_filter` (`list_filter.c`)

**Timed work.** Per batch: `input = [(seed + batch + 13j) % 1009 for j in range(size)]`,
`filtered = [v for v in input if v % 3 == 0]`, `sum((i+1) * filtered[i])`, both lists allocated and released inside
the timing. Unit: input element. Sizes 64 / 4096.

**Fastest arm:** Rust (5.8 cycles/element; `collect` + `filter` + `enumerate().sum()`); Zig-fast 7.5, Zig-safe 10.7.
**Today's mylang** (13.8): from the disassembly, the comprehension stores the list's length and generation on every
element, each append re-reads the header, calls `myl_rc_list_plain_ready` and stores again, `fold` bounds-checks and
overflow-checks every element, and `% 1009`, `% 3` use signed magic divides with floor fix-ups.

| step | x Rust (small / large) | x fastest arm (small / large) | ns/unit (large) | cycles/unit | instr/unit |
|---|---:|---:|---:|---:|---:|
| v1: today: heap lists, header traffic, plain_ready call, checked fold | 1.39 / 1.82 | 1.48 / 1.82 | 3.320 | 11.44 | 58.6 |
| v2: + immutable locals: headers in regs, sticky checks (L2) | 1.27 / 1.80 | 1.35 / 1.80 | 3.284 | 10.93 | 56.0 |
| v3: + typed append (no plain_ready call) | 1.06 / 1.55 | 1.13 / 1.55 | 2.831 | 9.31 | 46.0 |
| v4: + bounded result capacity (one alloc, no growth) | 0.90 / 1.43 | 0.95 / 1.43 | 2.619 | 9.17 | 45.3 |
| v5: + allocation hoisted out of the batch loop | 0.82 / 1.57 | 0.87 / 1.57 | 2.873 | 9.21 | 45.2 |
| v12: + sign fact only: unsigned mod, i64 storage | 0.40 / 0.76 | 0.43 / 0.76 | 1.382 | 4.64 | 19.4 |
| v6: + range x<1009: u32 storage | 0.41 / 0.74 | 0.44 / 0.74 | 1.352 | 4.56 | 18.5 |
| v7: + fuse generator into filter (no input list) | 0.47 / 0.77 | 0.50 / 0.77 | 1.412 | 4.92 | 20.7 |
| v8: + fuse fold (no lists), branchy | 0.47 / 0.81 | 0.50 / 0.81 | 1.480 | 5.17 | 19.3 |
| v9: + branchless select | 0.53 / 0.97 | 0.56 / 0.97 | 1.779 | 6.13 | 26.0 |
| v10: + strength-reduced remainder (induction) | 0.41 / 0.73 | 0.43 / 0.73 | 1.336 | 4.65 | 15.0 |
| v11: hand AVX2 u16, fused, rank by in-register scan | 0.08 / 0.11 | 0.09 / 0.11 | 0.197 | 0.66 | 2.1 |
| v30 holdout: file data, fused scalar, branchy, sticky checks | 0.54 / 0.91 | 0.58 / 0.91 | 1.658 | 5.79 | 27.7 |
| v31 holdout: file data, guard + hoisted r_j + AVX2 | 0.08 / 0.11 | 0.09 / 0.11 | 0.192 | 0.66 | 2.1 |
| v20 holdout reference: today reading file | 1.27 / 1.61 | 1.35 / 1.61 | 2.939 | 9.82 | 55.2 |
| v8 baseline x86-64 | 0.47 / 0.83 | 0.50 / 0.83 | 1.512 | 5.15 | 20.3 |
| v9 baseline x86-64 | 0.56 / 0.97 | 0.59 / 0.97 | 1.774 | 6.12 | 27.0 |
| v10 baseline x86-64 | 0.40 / 0.76 | 0.42 / 0.76 | 1.378 | 4.65 | 15.0 |
| B0 rust | 1.00 / 1.00 | 1.06 / 1.00 | 1.825 | 5.78 | 30.3 |
| B0 go | 1.81 / 1.82 | 1.92 / 1.82 | 3.326 |  |  |
| B0 zig-safe | 1.31 / 1.76 | 1.40 / 1.76 | 3.212 | 10.71 | 59.3 |
| B0 zig-fast | 0.94 / 1.27 | 1.00 / 1.27 | 2.318 | 7.51 | 36.5 |
| B0 my-llvm | 2.46 / 2.27 | 2.62 / 2.27 | 4.148 | 13.76 | 76.7 |

| rung | fact or choice | cat | cycles effect | needs |
|---|---|:-:|---|---|
| v1→v2 | fresh local lists are unaliased: headers in registers; sticky checks (L2) | a / b (L2) | 1.05× | value semantics; L2 adds little |
| v2→v3 | typed append: element type is `int`, so no `plain_ready` call | a | 1.17× | WP-6c typed collection operations |
| v3→v4, v4→v5 | result capacity bounded by `len(source)` (one allocation); both allocations hoisted out of the batch loop | a (L3 permits the over-reservation) | 1.02×, 1.00× | with glibc malloc the allocations are cheap; mylang's RC allocator costs more (the model is at 83% of B0) |
| v5→v12 | the sign fact (`seed ≥ 1`, `batch`, `j ≥ 0`, so floor == unsigned remainder) and one hoisted affine overflow check; `fold`'s multiply unchecked | a | **1.98×** | range/sign analysis through the `args` guard and the loop variables; the dominant step |
| v12→v6 | `x < 1009` known, u32 storage | a | 1.02× | nothing: not needed |
| v6→v7→v8 | fuse the generator into the filter, then `fold` into the loop (no lists at all) | a (L3) | 0.93×, 0.95× | **fusion alone does not pay in scalar code**; it is the precondition for the vector kernel |
| v8→v9 | branch-free select instead of the filter branch | a | 0.85× | the branch is predicted (0.015 mispredicts per element), so a select only adds instructions |
| v8→v10 | induction variable for `(base + 13j) % 1009` (one add, one compare-subtract) | a | 1.11× | modular strength reduction |
| v10→v11 | hand AVX2: u16 lanes, mask by multiply-high, the rank of each kept element by an in-register prefix count, `vpmaddwd` for rank·x | c | **7.0×** | not auto-vectorizable (a scan over a data-dependent mask); needs a library kernel or an idiom |

Baseline x86-64: the best scalar rung is the same code (4.65 cycles); only the hand kernel needs AVX2.

**Holdout.** The input becomes `a_j = seed + 13j` read from a file with `x = (a_j + batch) % 1009` computed in the
timed loop (same checksum). Today's code: 9.8 cycles; best fact-free scalar (v30, fused, sticky checks): 5.8
(1.7×); with a guard that proves `0 ≤ a_j` and that `a_j + iterations` does not overflow, and the loop-invariant
remainder `a_j % 1009` precomputed once per list (array-level LICM), the same AVX2 kernel runs at 0.66 cycles (v31).
Correct on files with random 63-bit values (the guard declines and the exact scalar path runs) and on a file that
overflows at batch 10 (all versions trap identically).

**Conclusions.** The sign/range fact (≈2×) and a vector kernel (7×) matter; allocation, fusion and L2 do not, on
this machine and at this size. A compiler without SIMD idioms stops at 4.6 cycles (0.8× Rust).
The fixture's batch-dependent regeneration makes the holdout depend on hoisting `a_j % 1009`; that transform is not
a "fact" but it is derivable.
**Plan.** Supports WP-6c (typed append 1.17×) and range facts; weakly supports WP-4 (the allocation steps measure
1.0× against glibc); no support for L2 beyond 1.05×.

## 3. `dict_lookup` (`dict_lookup.c`)

**Timed work.** `lookup = {j: values[j]}` for `j < size` is built outside the timing; each batch runs `size` queries
`lookup.get((seed + 17j + batch) % (2·size), 17)` (half hit, half miss) and sums them. Unit: lookup. Sizes 64 / 4096.
B0 `my-llvm` here **predates PY-DICT-4** (the typed integer read, ~20% on LLVM lookup per the dashboard).

**Fastest arm:** Go at 4096 (9.5 ns/lookup in this run) and Zig-fast at 64; Rust 42 cycles, Zig-fast 42.6, Zig-safe
52, mylang 51. I did not read the Go or Zig map implementations. **Today's mylang:** `myl_native_dictionary_read`
→ hint check (`recall`) → `read_walk` → `locate` (rewrites the last-probe record) → `probe_word` over a
64-bit-slot index at load ≤ 5/8, with the key and value in a separate 16-byte entry list; 0.5 branch mispredicts per
lookup, 2 dependent cache lines (128 KB in total, so L1 misses).

| step | x Rust (small / large) | x fastest arm (small / large) | ns/unit (large) | cycles/unit | instr/unit |
|---|---:|---:|---:|---:|---:|
| v1: today: generic read call, hint record, out-param | 0.66 / 1.25 | 1.73 / 1.74 | 16.522 | 51.15 | 139.7 |
| v2: + immutable dict: no hint record, hoisted fields | 0.37 / 0.67 | 0.98 / 0.93 | 8.875 | 28.76 | 76.3 |
| v3: + typed int/int, probe inlined | 0.33 / 0.57 | 0.87 / 0.80 | 7.562 | 25.60 | 58.3 |
| v4: + inline {key,value} slots, load<=1/2, 1-mul hash | 0.25 / 0.26 | 0.65 / 0.36 | 3.451 | 11.22 | 45.5 |
| v10: v4 layout with mylang hash (fold_multiply) | 0.32 / 0.82 | 0.84 / 1.15 | 10.882 | 36.42 | 57.9 |
| v5: + query-key induction (no div, no flags) | 0.15 / 0.14 | 0.39 / 0.19 | 1.852 | 6.21 | 24.5 |
| v6: dense-key direct addressing (runtime flag) | 0.11 / 0.11 | 0.29 / 0.15 | 1.405 | 4.44 | 15.0 |
| v7: hand AVX2 gather over dense, i64 values | 0.07 / 0.04 | 0.17 / 0.06 | 0.547 | 1.71 | 4.0 |
| v7n: hand AVX2 gather, u32 values | 0.04 / 0.02 | 0.10 / 0.02 | 0.237 | 0.75 | 1.2 |
| v8: hand AVX2 4-slot buckets (general keys) | 0.23 / 0.21 | 0.59 / 0.30 | 2.824 | 9.54 | 38.6 |
| v20 holdout ref: today, identity keys from file | 0.70 / 1.26 | 1.84 / 1.76 | 16.750 | 52.83 | 141.7 |
| v21 holdout: + immutable dict, identity keys from file | 0.40 / 0.71 | 1.06 / 0.99 | 9.423 | 30.95 | 78.3 |
| v30 holdout: best scalar table, keys from file | 0.15 / 0.15 | 0.39 / 0.20 | 1.928 | 6.43 | 28.5 |
| v31 holdout: AVX2 buckets, keys from file | 0.24 / 0.23 | 0.64 / 0.32 | 2.993 | 9.67 | 39.6 |
| v5 baseline x86-64 | 0.15 / 0.14 | 0.40 / 0.20 | 1.873 | 6.32 | 25.5 |
| B0 rust | 1.00 / 1.00 | 2.63 / 1.40 | 13.268 | 42.27 | 187.5 |
| B0 go | 0.74 / 0.72 | 1.95 / 1.00 | 9.501 |  |  |
| B0 zig-safe | 0.77 / 1.27 | 2.02 / 1.77 | 16.801 | 52.18 | 162.2 |
| B0 zig-fast | 0.38 / 1.02 | 1.00 / 1.43 | 13.574 | 42.61 | 75.2 |
| B0 my-llvm | 0.76 / 1.27 | 1.98 / 1.77 | 16.808 | 51.35 | 163.3 |

Sparse keys (40-bit ids from a mixer, same checksum as the dense run because hits depend only on the index; cycles per lookup, large):

| step | x Rust (small / large) | x fastest arm (small / large) | ns/unit (large) | cycles/unit | instr/unit |
|---|---:|---:|---:|---:|---:|
| v20 today model, sparse keys from file | 1.00 / 1.00 | 1.00 / 1.00 | 18.448 | 55.00 | 142.9 |
| v21 + immutable dict (no hint), sparse | 0.60 / 0.56 | 0.60 / 0.56 | 10.340 | 31.97 | 79.6 |
| v22 + typed, probe inlined, sparse | 0.56 / 0.76 | 0.56 / 0.76 | 14.056 | 43.88 | 63.4 |
| v30 inline slots + Fibonacci hash, sparse | 0.27 / 0.30 | 0.27 / 0.30 | 5.618 | 17.13 | 37.3 |
| v31 AVX2 4-slot buckets, sparse | 0.33 / 0.18 | 0.33 / 0.18 | 3.376 | 10.37 | 41.2 |

| rung | fact or choice | cat | cycles effect | needs |
|---|---|:-:|---|---|
| v1→v2 | the dictionary is not written in the loop (no `mut` access): the last-probe hint is dead, fields hoisted | a (value semantics; L2 irrelevant) | **1.78×** (sparse 1.72×) | a read-only probe entry point that never writes the hint (WP-5/WP-6c; PY-DICT-4 still writes it) |
| v2→v3 | typed int/int, probe inlined, value in a register | a | 1.12× (sparse 0.73×: noise) | WP-6c; within the layout noise, no reliable gain |
| v3→v4 | `{key,value}` pairs stored in the slot, load ≤ ½, one-multiply Fibonacci hash (entry list kept for iteration order) | a (library) | 2.28× on sequential keys | see the next row |
| v4 vs v10 | the same layout with mylang's own hash (`fold_multiply`, folded to 32 bits) | — | **v10 = 36.4 vs v4 = 11.2** | **hash luck**: a multiplicative hash lays sequential keys out with no collisions; this gain belongs to the fixture's keys, class (d) |
| sparse v22→v30 | same table on pseudo-random keys | a (library) | 43.9 → 17.1 | scalar probing is branch-bound (0.2–0.7 mispredicts per lookup) and **layout sensitive**: 17 or 35 cycles for the same source depending on code placement |
| v4→v5 | the query key `(base + 17j) % m` as an induction variable (add + compare-subtract, no division, no flags) | a | 1.81× | modular strength reduction on a loop-affine index |
| v5→v6 | keys exactly `0..n-1` in insertion order, tracked by one flag at insert: lookup is `k < n ? values[k] : miss` | a (runtime-adaptive representation) | 1.40× | no static fact; helps only dense-key dictionaries |
| v6→v7/v7n | hand AVX2 masked gather (8 lanes), i64 values / u32 values | c | 2.6× / then 2.3× | u32 values need the value range, which lives across a call boundary (`lookup` is a parameter of the batch function) |
| v8, v31 | 4-slot buckets, one 256-bit compare per query, branch-free value select, keys and values in separate arrays | c (library) | sparse **17.1–34.8 → 10.4**, stable | the only variant whose cycle count did not move with code layout |

**Holdout (`v20`, `v21`, `v30`, `v31`, sparse table).** The keys come from a file; the dense-key fast paths are gone.
What survives: dropping the hint (1.7×) and a flat, well-hashed table (3.2× on sparse keys at best); the branch-free
SIMD bucket probe is the robust floor (5.3× over today on sparse keys). A dense dictionary read from a file is still
detected at build time, so v6/v7 keep applying if the keys happen to be `0..n-1`.

**Conclusions.** (1) Most of today's cost is representation and protocol: two dependent cache lines, hint writes on
read-only queries, a hash that spreads keys randomly into a 5/8-full probing table (0.5 mispredicts per lookup).
None of it needs a new language fact; the L1 gate is already met at this size on cycles (51.4 vs 52.2).
(2) The headline ratios of the fixture-fitted rungs (v4–v7) are mostly (d); read the sparse table for what a real
program can expect: roughly 3–5×, from library design, not from the compiler. (3) The dictionary's insertion order
is untouched by every rung (the entry list stays).
**Plan.** Supports WP-5 (one-count: the hint and hold traffic on reads) and WP-6c; contradicts treating the
dashboard's dictionary gap as an LLVM-facts problem; layout noise (WP-1) matters more here than anywhere else.

## 4. `tagged_stack` (`tagged_stack.c`)

**Timed work.** `iterations` steps of: `popped = stack.pop()`, `base = as_integer(stack[0])`, `op = opcodes[cursor]`,
a `match` on the popped union (`Bool`/`Int`) and the opcode choosing `delta` (`n % 5/7/11/13` or a constant),
`new_base = (base + delta + op + 1) % 1000003`, `stack[0] = Value.integer(new_base)`, push `Bool(new_base % 2 == 0)`
or `Int(new_base % 97)`, `cursor = (cursor + 1) % size`. Unit: step (the loop is a latency chain: each step needs
the previous step's `base`). Sizes 64 / 4096; the opcode array is the only difference.

**Fastest arm:** Rust, 27.4 cycles/step (enum in a `Vec`, no stalls). Zig-safe/fast 53–54 and mylang 88.
**What B0 does** (`perf annotate`: 24% of the samples on the store of `stack[0] = Value.integer(...)`, 17% on the
push): the 16-byte union is built in a stack temporary with two narrow stores and then **copied with one 16-byte
vector load**, which cannot be forwarded from two stores: `ld_blocks.store_forward` fires 1.83 times per step
(B0 mylang) and 1.0 per step in the Zig arms (Rust: 0). On top of that: RC uniqueness tests, a
`myl_rc_list_plain_pop_ready` call per pop, a `plain_ready` per push, floor-mod fix-ups, an `idiv` for the cursor.
v1 reproduces the shape and the counter (1.83 stalls per step).

| step | x Rust (small / large) | x fastest arm (small / large) | ns/unit (large) | cycles/unit | instr/unit |
|---|---:|---:|---:|---:|---:|
| v1: today: heap list, RC checks, ready calls, floor mods, idiv cursor | 2.83 / 2.80 | 2.83 / 2.80 | 23.800 | 84.62 | 180.8 |
| v2: + value semantics: local list, header in regs | 2.28 / 2.18 | 2.28 / 2.18 | 18.527 | 65.33 | 90.8 |
| v8: + tagged values built in place (no store-forward stall) | 1.27 / 1.26 | 1.27 / 1.26 | 10.719 | 36.94 | 77.0 |
| v3: + stack scalar-replaced (balanced push/pop) | 1.27 / 1.25 | 1.27 / 1.25 | 10.627 | 36.97 | 77.0 |
| v4: + range facts: unsigned, no overflow checks | 0.89 / 0.87 | 0.89 / 0.87 | 7.389 | 24.11 | 39.5 |
| v5: + % M as cond-subtract, cursor compare-reset | 0.62 / 0.61 | 0.62 / 0.61 | 5.208 | 16.47 | 35.5 |
| v6: + residue tracking (r = base mod 97) | 0.33 / 0.32 | 0.33 / 0.32 | 2.707 | 10.55 | 33.3 |
| v7: + table lookup for r % k | 0.28 / 0.27 | 0.28 / 0.27 | 2.323 | 9.84 | 30.8 |
| v30 holdout: opcodes from file, no range facts | 1.26 / 1.23 | 1.26 / 1.23 | 10.426 | 33.84 | 62.0 |
| v31 holdout: file + runtime guard + v7 | 0.28 / 0.27 | 0.28 / 0.27 | 2.282 | 9.80 | 30.8 |
| v20 holdout reference: today, file | 2.83 / 2.78 | 2.83 / 2.78 | 23.575 | 84.68 | 180.8 |
| v5 baseline x86-64 | 0.61 / 0.59 | 0.61 / 0.59 | 4.975 | 16.50 | 35.5 |
| v7 baseline x86-64 | 0.28 / 0.27 | 0.28 / 0.27 | 2.330 | 9.83 | 30.8 |
| B0 rust | 1.00 / 1.00 | 1.00 / 1.00 | 8.489 | 27.39 | 45.5 |
| B0 go | 1.08 / 1.04 | 1.08 / 1.04 | 8.831 |  |  |
| B0 zig-safe | 1.84 / 1.82 | 1.84 / 1.82 | 15.441 | 53.84 | 119.8 |
| B0 zig-fast | 1.93 / 1.88 | 1.93 / 1.88 | 15.944 | 53.08 | 102.3 |
| B0 my-llvm | 2.91 / 2.85 | 2.91 / 2.85 | 24.231 | 88.32 | 223.3 |

| rung | fact or choice | cat | cycles effect | needs |
|---|---|:-:|---|---|
| v1→v2 | the stack is a unique local: no RC test, no ready calls, no generation counter, header in registers | a (value semantics; WP-5) | 1.30× | one-count reads of unique locals |
| v2→v8 | **tagged values built and read in place** (two scalar stores / loads in the slot, no temporary, no 16-byte copy) | a (pure implementation, no fact) | **1.77×** | a materialization rule for unions/records: construct into the destination, copy by field |
| v8→v3 | the stack is scalar-replaced (length 2 → 1 → 2 each step) | a (balanced push/pop; L3) | 1.00× | no gain once the stall is gone: the chain is arithmetic |
| v3→v4 | ranges: `seed ∈ [1,10^6]` (checked at entry), opcode ∈ [0,4), `cursor < size`: all values non-negative, no overflow check, unsigned remainders | a | **1.53×** | loop-carried range analysis (a value of the form `x % M` is in [0,M)) |
| v4→v5 | `% 1000003` of a sum known to be below 2·1000003 as a conditional subtract; cursor wrap as compare-and-reset | a | **1.46×** | range-based strength reduction of `%` |
| v5→v6 | track `r = base mod 97` beside `base` (the pushed Int is `base % 97`), corrected only at the rare wrap of `base` | a, but a new transformation | **1.56×** | "modular induction": maintain residues of a value updated by adds; I would not plan on it |
| v6→v7 | the remainders `r % k` from a 4×97 table | c | 1.07× | negligible |

Baseline x86-64: v5 and v7 are the same code with or without AVX2 (scalar).

**Holdout.** Opcodes read from a file (not known to be in [0,4)): the fact-free best (v30: scalar-replaced, floor
remainders) runs at 33.8 cycles, 2.5× faster than today but only Rust speed; a one-pass guard over the immutable
opcode list (all in [0,4), seed in range) selects the fast path (v31: 9.8 cycles, identical to v7). The checksums
agree with the exact reference on random opcode files including values up to 2^40 (guard declines).

**Conclusions.** Before any range fact, two **implementation** steps (no RC protocol on a unique local; no
store-forwarding stall) take mylang from 2.9× to 1.3× Rust, i.e. below Zig-safe (36.9 vs 53.8 cycles). The range steps
then reach 0.6× Rust. The stall is a defect the Zig arms share; Rust avoids it.
**Plan.** WP-5 (holds on a unique local), WP-6c (ready calls), and a **new item the plan lacks**: how aggregates and
unions are materialized (1.8× here, 3.0× in `lox_eval`). Supports WP-8: a direct emitter that keeps unions as SSA
pairs removes the stall by construction.

## 5. `string_split` (`string_split.c`, `fuzz_string_split.c`)

**Timed work.** Per step, one of two prebuilt documents (the `size` fragments `["", "alpha", "café", "x", "naïve"][(seed+j)%5]`
joined by `|` or `::`) is split, and the job is `7·len(parts) + Σ score(part)` with `score(text) = utf8 length + Σ utf8 bytes`
(`text.encode()` copies). Unit: fragment. Sizes 64 / 4096 (about 20 KB at the large size).

**Fastest arm:** Rust, 27.7 cycles/fragment (`str::split` is a lazy iterator; nothing is allocated). Zig 62–66, mylang 203.
**What B0 does:** `split` builds a `list[str]` of freshly allocated owned pieces (pieces under 9 octets are copied),
`score` makes a `bytes` copy of each, and everything is released through the RC drain queue; the profile is
`drain_fast`, `rc_storage_alloc`, `octets_find`, `raw_bytes`, `rc_list_new`, `edge_release`. The model reaches 69% of B0
(glibc `malloc` instead of the slab allocator and RC bookkeeping).

| step | x Rust (small / large) | x fastest arm (small / large) | ns/unit (large) | cycles/unit | instr/unit |
|---|---:|---:|---:|---:|---:|
| v1: today: owned pieces, encode copies, RC drain | 4.37 / 5.15 | 4.37 / 5.15 | 46.482 | 141.21 | 661.8 |
| v2: + no RC/malloc: region allocation (L3) | 1.36 / 1.68 | 1.36 / 1.68 | 15.160 | 47.13 | 191.6 |
| v3: + borrowed encode (no copy) | 1.03 / 1.34 | 1.03 / 1.34 | 12.103 | 37.23 | 156.8 |
| v4: + pieces as views (no copy, no per-piece alloc) | 0.92 / 1.15 | 0.92 / 1.15 | 10.395 | 34.41 | 123.9 |
| v5: + fuse split into score (no parts list) | 0.76 / 0.94 | 0.76 / 0.94 | 8.488 | 28.56 | 104.3 |
| v9: + byte-level fusion, per-part sums kept | 0.27 / 0.29 | 0.27 / 0.29 | 2.629 | 8.67 | 57.2 |
| v6: + split-fold identity (no per-part work), scalar | 0.19 / 0.24 | 0.19 / 0.24 | 2.142 | 6.98 | 35.4 |
| v7: hand AVX2 scan (psadbw + cmpeq/popcnt) | 0.03 / 0.02 | 0.03 / 0.02 | 0.167 | 0.53 | 2.6 |
| v8: WORK ELIM: memoize the two documents | 0.01 / 0.00 | 0.01 / 0.00 | 0.008 | 0.00 | 0.0 |
| v30 holdout: documents from file, v5 | 0.73 / 0.98 | 0.73 / 0.98 | 8.867 | 29.34 | 104.8 |
| v31 holdout: documents from file, hand AVX2 | 0.03 / 0.02 | 0.03 / 0.02 | 0.177 | 0.55 | 2.6 |
| v20 holdout reference: today, file | 4.45 / 5.08 | 4.45 / 5.08 | 45.823 | 141.57 | 661.6 |
| v5 baseline x86-64 | 0.74 / 0.95 | 0.74 / 0.95 | 8.536 | 28.56 | 104.3 |
| v9 baseline x86-64 | 0.30 / 0.34 | 0.30 / 0.34 | 3.062 | 10.37 | 57.2 |
| v6 baseline x86-64 | 0.28 / 0.36 | 0.28 / 0.36 | 3.217 | 10.16 | 48.3 |
| B0 rust | 1.00 / 1.00 | 1.00 / 1.00 | 9.023 | 27.69 | 154.2 |
| B0 go | 1.94 / 2.49 | 1.94 / 2.49 | 22.433 |  |  |
| B0 zig-safe | 1.87 / 2.20 | 1.87 / 2.20 | 19.832 | 66.48 | 265.6 |
| B0 zig-fast | 1.72 / 2.07 | 1.72 / 2.07 | 18.654 | 62.09 | 239.4 |
| B0 my-llvm | 6.29 / 7.62 | 6.29 / 7.62 | 68.740 | 203.35 | 1150.1 |

| rung | fact or choice | cat | cycles effect | needs |
|---|---|:-:|---|---|
| v1→v2 | pieces, list and encode buffers never escape `split_job` and are immutable: no refcounts, no drain, bump region reset per job | a (L3) | **3.0×** | non-escaping analysis plus L3 (allocation unobservable); an RC-free region |
| v2→v3 | `encode()` borrowed (a view of the piece's UTF-8) because `score` only reads it | a (L3 + lifetime proof; WP-4 step 6) | 1.27× | the lifetime proof |
| v3→v4 | pieces as `(pointer, length)` views, no copy, no per-piece allocation | a (L3; the 9-octet copy rule only guards retention) | 1.08× | same |
| v4→v5 | the list of parts is consumed once by a reduction: `split` becomes a generator feeding `score` | a | 1.20× | loop fusion / deforestation |
| v5→v9 | one byte-level loop with a tiny matcher (single byte; or the leftmost non-overlapping two-byte separator with one pending character), per-part length and sum accumulated per part | a | **3.3×** | fusion plus specialising the search to the separator length; no per-piece call |
| v9→v6 | "sum over parts of (length + byte sum)" = document total minus the separators' share: only the separator count is needed | **b** (needs a rewrite rule for `split` folded by a sum, or the programmer states it) | 1.24× scalar | knowledge of `split`'s contract; not derivable from the loops |
| v6→v7 | hand AVX2: `vpsadbw` byte sum, `vpcmpeqb` + `popcnt` separator count; for `::` runs of the character pair up as `floor(r/2)` using the carry-propagation odd-run trick, with a zero-padded final block (fuzzed against the scalar scan, 200 000 random strings with long runs) | c (library kernel) | **13×** over the scalar identity | a SIMD substring/byte-class library; 0.53 cycles/fragment |
| v8 | memoize the two documents | WORK ELIM | — | excluded |

Baseline x86-64: v9 8.7 → 10.4 and v6 7.0 → 10.2 cycles without AVX2; v7 needs it.

**Holdout.** The documents come from a file (`gen`), and a `genwide` file (fragments `":::"`, `"a:b"`, `"::::x"`, `"|"`, `"€"`)
exercises runs of three or more, which the vector scan must decide exactly: v20, v30 and v31 agree on it. Fact-free
best without the identity: 29.3 cycles (v5 speed); with the identity and SIMD kernel: 0.55. Nothing in this ladder
used the fixture's fragment alphabet.

**Conclusions.** The top three rungs are allocation and copy removal (3.0× · 1.27× · 1.08× = 4.1×, which is already
below Zig-safe: 37 vs 66 cycles) and fusion (4×); they need L3 and escape/lifetime analysis, no language facts. The two
largest remaining steps (b and c) are not compiler-derivable: the split-fold identity and the SIMD kernel.
**Plan.** Supports WP-4 (L3, borrowed `encode()`, region allocation) strongly, and WP-7 only partly: per-character
cursor lowering is irrelevant here; the cost was allocation, copies and RC, not `str[i]`.

## 6. `branch_mixed` (`branch_mixed.c`)

**Timed work.** Like `integer_math`: per pass, `value = (x+phase)*3+1 if flags[j] else (x+phase)*5+7`, with `flags[j] =
(values[j]*73 + j*19 + seed) % 101 < 50` (about half set) prebuilt. Unit: element. Sizes 64 / 4096.

**Fastest arm:** Rust and Zig-fast (4.8–4.9 cycles/element); Zig-safe 9.3; **mylang 6.9, already below Zig-safe**.
The "mixed" branch is not mispredicted in any arm: v1 shows 0.006 misses per element, Rust 0.0096; the predictor learns
the 4096-element pattern, so this is a throughput problem, not a branch problem.

| step | x Rust (small / large) | x fastest arm (small / large) | ns/unit (large) | cycles/unit | instr/unit |
|---|---:|---:|---:|---:|---:|
| v1: today: bounds checks, branch on flags, checked arms | 1.13 / 1.03 | 1.13 / 1.14 | 1.855 | 5.28 | 22.0 |
| v2: + immutable lists, hoisted bounds, sticky checks (L2) | 0.89 / 0.78 | 0.89 / 0.87 | 1.416 | 4.19 | 20.5 |
| v3: + range facts: no arm checks (branch written as if) | 0.67 / 0.55 | 0.67 / 0.61 | 0.994 | 3.02 | 19.0 |
| v4: + if-conversion written as select | 0.62 / 0.64 | 0.62 / 0.72 | 1.162 | 3.02 | 15.0 |
| v5: + narrow arithmetic (i32), plain C | 0.31 / 0.26 | 0.31 / 0.29 | 0.475 | 1.30 | 3.7 |
| v6: + u16 storage, plain C | 0.28 / 0.24 | 0.28 / 0.27 | 0.431 | 1.29 | 3.4 |
| v8: + chunked u32 accumulation, plain C | 0.17 / 0.13 | 0.17 / 0.14 | 0.235 | 0.62 | 1.6 |
| v7: hand AVX2 u16 blend | 0.09 / 0.07 | 0.09 / 0.07 | 0.118 | 0.30 | 0.8 |
| v2 holdout: file data, L2 form, branchy (no range facts) | 0.88 / 0.91 | 0.88 / 1.02 | 1.652 | 4.19 | 20.5 |
| v30 holdout: file data, no range facts, branch-free sticky | 1.69 / 1.76 | 1.69 / 1.96 | 3.181 | 8.26 | 27.0 |
| v31 holdout: file data, runtime guard + AVX2 i32 | 0.20 / 0.15 | 0.20 / 0.16 | 0.263 | 0.72 | 2.5 |
| v20 holdout reference: today, file | 1.14 / 1.12 | 1.14 / 1.24 | 2.016 | 5.21 | 22.0 |
| v4 baseline x86-64 | 0.67 / 0.59 | 0.67 / 0.66 | 1.074 | 3.01 | 15.0 |
| v6 baseline x86-64 | 0.34 / 0.30 | 0.34 / 0.33 | 0.534 | 1.51 | 8.5 |
| v8 baseline x86-64 | 0.27 / 0.26 | 0.27 / 0.29 | 0.475 | 1.28 | 5.1 |
| B0 rust | 1.00 / 1.00 | 1.00 / 1.11 | 1.807 | 4.78 | 18.0 |
| B0 go | 1.52 / 1.57 | 1.52 / 1.75 | 2.843 |  |  |
| B0 zig-safe | 1.75 / 1.87 | 1.75 / 2.08 | 3.381 | 9.28 | 22.0 |
| B0 zig-fast | 1.01 / 0.90 | 1.01 / 1.00 | 1.623 | 4.88 | 17.0 |
| B0 my-llvm | 1.46 / 1.37 | 1.46 / 1.52 | 2.472 | 6.90 | 34.0 |

| rung | fact or choice | cat | cycles effect | needs |
|---|---|:-:|---|---|
| v1→v2 | immutable lists, bounds checked once, sticky overflow flag | b (L2) / a | 1.26× | L2 gives a modest gain here, because the predicted branch no longer carries checks |
| v2→v3 | element range [0,1009), phase [0,17): neither arm can overflow | a | 1.39× | range analysis from the comprehension |
| v3→v4 | if-conversion to a select (both arms are now pure and cheap) | a | 1.00× | speculation is legal only because the range fact removed the traps; LLVM had already done it (19 → 15 instructions, same cycles) |
| v4→v5 | narrow (i32) arithmetic, plain C: LLVM vectorizes to 8 lanes | a (given the range) | **2.3×** | the front end emits narrow types, as in `float_math` |
| v5→v6 | u16 storage | a | 1.01× | not needed |
| v6→v8 | u32 accumulation in chunks of ≤ 4096 elements, widened to the checked 64-bit sum between chunks | a (needs the range-derived bound on the terms) | **2.1×** | LLVM does not chunk a 64-bit reduction by itself; the bound is what makes the narrow accumulator legal |
| v8→v7 | hand AVX2, 16 u16 lanes, `vpblendvb`, `vpmaddwd` pair sums | c | 2.1× | LLVM's i32 vector code is 2× off a hand u16 kernel |

Baseline x86-64: v8 1.28 vs 0.62 cycles/element with AVX2 (2.1×).

**Holdout.** Values and flags from a file with no range: the best fact-free code is v2's branchy L2 form (4.19 cycles,
Rust speed; the branch-free form with both arms checked into the sticky flag is **slower**, 8.3); a guard proving
`0 ≤ x < 2^26` selects an AVX2 kernel with i32 lanes widened to 64-bit sums (v31, 0.72 cycles, 6× better than the
fact-free code). Correct on files with random values up to 6.7·10^7 (the guard declines above 2^26); at 2^62 every version traps alike.

**Conclusions.** The ladder is the `integer_math` ladder with the branch removed from the story: range facts (1.4×),
narrow width (2.3×), a bounded accumulator (2.1×) and an explicit vector kernel (2.1×). A select is not a lever on a
predictable branch.
**Plan.** Consistent with WP-6a/WP-8 (ranges plus narrow emission); L2 is worth 1.26× here at most; no help from L3.

## 7. `json_transform`, parse component (`json_parse.c`, `json_gen.h`, `json_typed.h`)

**Why parse.** In the B0 `my-llvm` profile (`perf report` mapped to source functions through the QBE manifest) the
`json::` scanner functions (`skip_whitespace` 9%, `read_object`, `read_number`, `read_string`, `skip_digits`,
`read_value`) account for 36% of the samples and the RC allocation / drain / unwind machinery that builds and frees
the tree for roughly another 40%; `write_*` (serialize) is ~2%. The job parses first, so parse plus the tree it builds is
the dominant component. (The `dumps` side is a smaller, simpler study and is left out.)

**Timed work.** `json.loads(text)` of a compact array of `size` rows `{"id","name","amount","active"}` (names such as
`café,"item"12` need `\"` escapes), plus releasing the tree. The transform/serialize/score back end is **one fixed
implementation shared by all rungs** and untimed; the program prints the parse time (rdtsc around the parse and
the release), and `v<1000+n>` prints the whole job so it can be compared with the B0 arms. Unit: row. Sizes 16 / 256.
The `cycles` and `instr` columns below count the **whole job** (perf cannot isolate the component); `ns/unit` is the
parse component only, and `x Rust` compares that component with Rust's whole job, so read it as a bound.

**Fastest arm:** Rust with `serde_json::Value` (1 775 cycles per row for the whole job). **Today's mylang** runs
13 666 cycles and 51 000 instructions per row. **My step 0 reaches only 21% of that** (2 855 cycles, 11 000
instructions) even after adding the retain/release of the `bytes` object around every `scanner.data` read that the
B0 disassembly shows (B0's `skip_whitespace` retains and releases the document around each helper call, with a
16-byte copy of the `Scanner` record). The remaining ~4× is the RC/frame protocol around every `Result`, every `Json`
value moved into a list or dictionary, and the `?` unwinding (`rc_insert_result`, `unwind_many`, `value_retain_many`,
`rcg_*` in the profile). **That part is not modelled, so the ladder below is a lower bound on what the steps would
save in the real binary, and the first rung understates the gap.** From the ns columns: the real parse component is
an estimated 70% of 5 893 ns/row, i.e. ~4 000 ns/row (an estimate from the profile split, not a measurement); step 0 is 1 124.

| step | x Rust (small / large) | x fastest arm (small / large) | ns/unit (large) | cycles/unit | instr/unit |
|---|---:|---:|---:|---:|---:|
| v1: today model: memory scanner, Results in memory, RC tree, per-string buffers | 1.49 / 1.48 | 1.49 / 1.48 | 1124.011 | 2945.37 | 11446.9 |
| v2: + register scanner, unboxed Results (same tree, same allocations) | 1.39 / 1.18 | 1.39 / 1.18 | 894.434 | 2300.78 | 11177.9 |
| v3: + bump region, no RC/drain | 0.50 / 0.49 | 0.50 / 0.49 | 376.396 | 1093.88 | 3963.1 |
| v4: + borrowed document, string views, in-place literals | 0.33 / 0.33 | 0.33 / 0.33 | 253.816 | 1154.07 | 2858.3 |
| v5: + single-pass integers | 0.33 / 0.33 | 0.33 / 0.33 | 250.536 | 846.11 | 3039.4 |
| v6: + flat objects (no hash dictionaries) | 0.19 / 0.19 | 0.19 / 0.19 | 146.372 | 824.61 | 2257.2 |
| v7: + schema-directed: rows straight from the bytes | 0.12 / 0.12 | 0.12 / 0.12 | 93.915 | 446.14 | 2068.7 |
| v8: + demand-driven string decoding | 0.12 / 0.13 | 0.12 / 0.13 | 95.126 | 422.08 | 1860.8 |
| v9: + AVX2 string scan, SWAR integers | 0.13 / 0.13 | 0.13 / 0.13 | 100.404 | 382.56 | 1612.3 |
| v1 (whole job) | 1.59 / 1.60 | 1.59 / 1.60 | 1219.008 | 2855.30 | 11278.3 |
| v7 (whole job) | 0.22 / 0.23 | 0.22 / 0.23 | 171.774 | 469.82 | 1971.0 |
| v9 (whole job) | 0.23 / 0.24 | 0.23 / 0.24 | 185.180 | 431.96 | 1703.9 |
| v30 holdout: pretty/reordered/escaped doc, typed parser | 0.12 / 0.12 | 0.12 / 0.12 | 95.015 | 434.71 | 1912.8 |
| v31 holdout: pretty/reordered/escaped doc, AVX2 parser | 0.13 / 0.13 | 0.13 / 0.13 | 100.581 | 379.52 | 1618.7 |
| v20 holdout reference: today model on that doc | 1.51 / 1.50 | 1.51 / 1.50 | 1139.040 | 2933.31 | 11412.3 |
| v8 baseline x86-64 | 0.12 / 0.12 | 0.12 / 0.12 | 90.583 | 436.12 | 2012.4 |
| B0 rust | 1.00 / 1.00 | 1.00 / 1.00 | 760.925 | 1775.02 | 7542.5 |
| B0 go | 4.40 / 4.58 | 4.40 / 4.58 | 3486.999 |  |  |
| B0 zig-safe | 1.66 / 1.96 | 1.66 / 1.96 | 1494.512 | 2992.93 | 12242.1 |
| B0 zig-fast | 1.19 / 1.56 | 1.19 / 1.56 | 1189.891 | 2277.28 | 8292.1 |
| B0 my-llvm | 7.94 / 7.74 | 7.94 / 7.74 | 5893.257 | 13665.91 | 51149.5 |

| rung | fact or choice | cat | parse-component effect | needs |
|---|---|:-:|---|---|
| (not modelled) | v1 includes the retain/release on `scanner.data` reads; the `Result`/`Json` move traffic is not modelled | a (one-count RC, WP-5) | unknown: the model is 4.8× below B0 in instructions | holds/loans, value semantics for unique values |
| v1→v2 | the unique `mut Scanner` lives in a register; `Result`s return in registers; no retain/release on field reads | a (value semantics, no aliasing) | 1.26× | SROA of an unaliased `mut` record parameter |
| v2→v3 | the tree and all temporaries come from a bump region: no RC, no drain | a (L3) | **2.38×** | non-escaping analysis for the tree plus L3 |
| v3→v4 | borrowed document (no `encode()` copy), string views (no per-string buffer/snapshot/validate/copy), literals compared in place | a (L3 + "a slice of a valid `str` between ASCII quotes is valid UTF-8") | 1.48× | UTF-8 validity as a library invariant (c) unless the checker knows `str` slices at ASCII boundaries stay valid |
| v4→v5 | integers parsed in one pass | a (library) | 1.01× | none |
| v5→v6 | objects as flat entry arrays with a linear duplicate check instead of hash dictionaries | a (representation choice for small objects) | **1.71×** | a small-map representation |
| v6→v7 | schema-directed: rows decoded straight into records `{id,name,amount,active}`; any key order, whitespace, unknown keys skipped by a validating skipper, escapes decoded | **b / c** (typed decode API, or call-site specialization of `loads`) | **1.56×** | the programmer states the schema, or a whole-program specialization |
| v7→v8 | decode a name's escapes only for kept rows | a (demand-driven) | 0.99× | none |
| v8→v9 | AVX2 string scan, SWAR 8-digit integers | c | **0.95× (no gain)** | strings are 4–14 bytes; the cost is per token, not per byte |

From step 0 to v7: **12×** on the parse component (whole job 7×); relative to the real binary the headroom is
larger, but unmeasured.

**Holdout.** The same data reformatted: indented, keys reordered, an extra nested field with an array containing
`null`, `-25` and a string escape, `é` instead of `é`. Every version that reads the file (v20 today model,
v30 typed, v31 typed+SIMD) gives the checksum of the compact document, and v30/v31 cost the same as on the compact
document (95–100 ns/row): the typed parser assumes nothing about layout. Not attempted: a simdjson-style two-stage
structural index (the likely next 2–3×) and floats.

**Conclusions.** The parse component is dominated by allocation and RC protocol on the tree (v2→v4 = 3.5×), object
representation (1.7×), and, last, typed decoding (1.6×). No range fact is involved. A SIMD scan does not pay on short
tokens. The tree-free typed parser is a different API for the same data, not an optimization of `json.loads`.
**Plan.** Supports WP-4 (L3: the tree, borrowed `encode()`) and WP-5 (the missing 4× is hold/loan traffic on
`Result` and `Json` moves); WP-7's cursor lowering is mostly irrelevant here (`bytes`, not `str`, is scanned). A
typed-decode path is a language/library item outside the plan.

## 8. `lox_eval` dispatch loop (`lox_eval.c`)

**Timed work.** Per batch the VM (`execute` in `collections/main.my`) runs a fixed 38-instruction program for
`size` loop iterations (23.5 bytecode operations per loop iteration on average: `i % 2 == 0` chooses
`total = (total*3 + 7) % 1000003` through a call/return, or `(total + i) % 1000003`), with `stack: list[Value]`
(`Value` = union `int | bool`, 16 bytes), `returns: list[int]` and `variables: list[int]` created and released each
batch. Unit: loop iteration. Sizes 16 / 256.

**Fastest arm:** Rust (168 cycles per loop iteration, 789 instructions); Go 1.2×; Zig-safe/fast ~510–520 cycles and
**17 store-forward stalls per loop iteration**; B0 mylang 665 cycles, 2 063 instructions, 15.3 stalls. v1 reproduces
cycles (667), stalls (17.0) and instruction count (2 249).

| step | x Rust (small / large) | x fastest arm (small / large) | ns/unit (large) | cycles/unit | instr/unit |
|---|---:|---:|---:|---:|---:|
| v1: today: RC lists, ready calls, vector-copy stalls, if/elif chain | 3.73 / 3.82 | 3.73 / 3.82 | 243.757 | 666.60 | 2249.1 |
| v2: + value semantics: local lists, headers in regs (stalls remain) | 3.09 / 3.29 | 3.09 / 3.29 | 209.968 | 569.32 | 852.1 |
| v3: + tagged values in place (no store-forward stall) | 1.06 / 1.09 | 1.06 / 1.09 | 69.274 | 187.34 | 758.0 |
| v4: + list storage hoisted out of the batch loop | 1.05 / 1.08 | 1.05 / 1.08 | 69.095 | 190.99 | 710.7 |
| v5: + threaded dispatch (computed goto), pointer pc | 0.74 / 0.75 | 0.74 / 0.75 | 47.889 | 130.11 | 656.2 |
| v6: + stack top cached in registers | 0.77 / 0.81 | 0.77 / 0.81 | 51.780 | 137.53 | 678.2 |
| v8: BOUND: assumes a load-time verifier (no tags/checks) | 0.59 / 0.58 | 0.59 / 0.58 | 37.013 | 103.88 | 208.4 |
| v9: BOUND + 32-bit division bypass for % | 0.55 / 0.58 | 0.55 / 0.58 | 36.802 | 97.76 | 196.4 |
| v7: WORK ELIM: partial evaluation of the fixed program | 0.05 / 0.09 | 0.05 / 0.09 | 5.640 | 14.99 | 14.6 |
| v30 holdout: program from file, threaded | 0.76 / 0.75 | 0.76 / 0.75 | 47.492 | 130.14 | 656.2 |
| v31 holdout: program from file, + stack cache | 0.80 / 0.82 | 0.80 / 0.82 | 52.474 | 136.92 | 678.2 |
| v20 holdout reference: today, program from file | 3.74 / 3.97 | 3.74 / 3.97 | 253.232 | 666.16 | 2249.1 |
| v3 baseline x86-64 | 1.07 / 1.07 | 1.07 / 1.07 | 68.446 | 186.82 | 758.0 |
| v6 baseline x86-64 | 0.72 / 0.72 | 0.72 / 0.72 | 46.181 | 125.18 | 678.2 |
| B0 rust | 1.00 / 1.00 | 1.00 / 1.00 | 63.737 | 167.94 | 789.4 |
| B0 go | 1.14 / 1.23 | 1.14 / 1.23 | 78.714 |  |  |
| B0 zig-safe | 2.92 / 3.03 | 2.92 / 3.03 | 193.175 | 518.47 | 1458.0 |
| B0 zig-fast | 2.86 / 2.96 | 2.86 / 2.96 | 188.673 | 509.57 | 1351.8 |
| B0 my-llvm | 4.04 / 3.82 | 4.04 / 3.82 | 243.380 | 665.30 | 2062.8 |

| rung | fact or choice | cat | cycles effect | needs |
|---|---|:-:|---|---|
| v1→v2 | the three lists are unique locals: no RC tests, ready calls, generation counters, headers in registers | a (value semantics; WP-5) | 1.17× | one-count reads of unique locals |
| v2→v3 | tagged values built and read in place (no 16-byte vector copy through a stack temporary) | a (pure implementation) | **3.04×** | the union materialization rule of `tagged_stack` |
| v3→v4 | list storage hoisted out of the batch loop | a (L3) | 0.98× | none |
| v4→v5 | threaded dispatch: the switch is replicated at the end of each handler (computed goto), pointer `pc` | b / c (language construct or an interpreter-loop pass) | **1.47×** | not derived by LLVM from a `while True: if/elif` chain |
| v5→v6 | stack top cached in registers | c | 0.95× (slower) | the extra `have` bookkeeping outweighs the saved memory traffic |
| v8 | **bound only**: assume a load-time verifier, so no tags, no capacity/underflow/pc checks | not derivable | 1.25× over v5 (3.2× fewer instructions) | shows what the generic checks cost; the VM is latency-bound (stack store → load forwarding, `idiv`), not instruction-bound |
| v9 | v8 plus a 32-bit division bypass for `%` | a | 1.06× | small |
| v7 | partial evaluation of the constant program | WORK ELIM | — | excluded |

Baseline x86-64: v3 and v6 are scalar, no difference.

**Holdout.** The VM reads its program from a file; a second program (`total = (total + i*i) % 1000003`, different ops and
jump targets) gives checksums equal to an independent Python recurrence, and v20/v30/v31 agree on both programs. Nothing
in v1–v6 depends on the built-in program (v7 is the only rung that does). v30 (threaded, from file): 130 cycles per
loop iteration.

**Conclusions.** The first four **implementation** steps take mylang from 3.8× Rust to Rust speed (1.09×) with no new
fact; the stall removal alone is 3×. Threaded dispatch then gets 0.75×. The remaining distance to the machine's
floor for a stack VM (98–104 cycles per iteration at best, ~4 cycles per op) is store forwarding and `idiv`, not
dispatch.
**Plan.** WP-5 (RC on unique locals), the missing union-materialization item, and WP-8 (a direct emitter keeps unions in
registers). L1 is reached by v3 (187 cycles vs Zig-safe 519).

## Cross-case table: fact or choice → cases → gain → category → implied work

Gains are the cycles ratio of the rung that adds the fact, at the large size, from the tables above ("pilot" = the
`integer_math` ladder). Rows marked † include hand-written code; rows marked ‡ are fixture luck or contract-adjacent.

| fact or choice | cases it helps (gain) | range | cat | implied compiler work or language feature |
|---|---|---|:-:|---|
| `int(float)` lowered inline | float_math (1.87×) | 1.9× | a | emit the checked conversion inline; no fact needed. Reaches Zig-safe parity alone |
| Unions / records built and read **in place** (no temporary + 16-byte vector copy; no store-forward stall) | tagged_stack (1.77×), lox_eval (3.04×); Zig-safe/fast carry the same stall | 1.8–3.0× | a | a materialization rule: construct into the destination, copy field-wise, or keep a union as an SSA pair (WP-8). **Not in the plan** |
| No RC / uniqueness / `plain_ready` / hint-write protocol on unique local values and read-only probes | list_filter (1.05–1.17×), tagged_stack (1.30×), lox_eval (1.17×), dict_lookup (1.78×), json parse (1.26× modelled; most of a 4× gap not modelled) | 1.2–1.8× (json: more) | a | one-count RC (WP-5), typed collection ops (WP-6c), read-only probe entry points |
| Non-escaping temporaries from a region / elided; `encode()` borrowed; pieces as views | string_split (3.0× · 1.27× · 1.08×), json parse (2.38× · 1.48×), list_filter (1.0×), lox_eval (1.0×) | 1.0× (a few big lists) to 4× (many small objects) | a (L3) | WP-4 steps 5–6; the removal of the budget matters little by itself, the RC/drain and copy cost is what goes |
| Value range or sign of elements and loop-carried values (from `% m`, `range`, argument guards) | float_math (2.13×), branch_mixed (1.39×), list_filter (1.98×), tagged_stack (1.53×), pilot (3.4×) | 1.4–3.4× | a (local) / b if the list crosses a call | range analysis incl. loop-carried `x % M ∈ [0,M)`; facts that cross a function boundary (dict values, `values` passed to `batch_result`) need interprocedural specialization or a signature fact |
| Narrow integer width **emitted** (i32 / u16), then LLVM vectorizes | float_math (2.47×), branch_mixed (2.3×), pilot (2.4×) | 2.3–2.5× | a (given the range) | the front end must emit narrow types; `llvm.assume` / `!range` does not suffice (float_math v13: 1.00×) |
| Narrow storage (u16 / u32 lists) | float_math, branch_mixed, list_filter (1.0× each); pilot (2.4×) | 1.0× (here) | a | not needed when 32-bit lanes suffice; in the pilot the gain came from 16-bit lane math |
| Bounded narrow accumulator in chunks | branch_mixed (2.1×) | 2.1× | a | derive the chunk length from the term bound; LLVM does not |
| Modular strength reduction (`x % M` of a bounded sum → compare-subtract; affine `(a + b·j) % m` → induction; residues carried beside the value) | tagged_stack (1.46× · 1.56×), dict key (1.81×), list_filter (1.11×), lox division bypass (1.06×) | 1.1–2.3× | a (needs ranges); residue tracking is a new transformation | pattern pass over `%` |
| Loop / comprehension fusion; byte-level specialization of `split`+fold | string_split (1.2× then 3.3×), list_filter (0.93–0.95× scalar) | 0.9–4× | a | deforestation of non-escaping lists; a precondition for vector kernels |
| `split`/fold algebra: Σ over parts = whole − separators | string_split (1.24× scalar) | 1.2× | **b** | a rewrite rule for `split` folded by a sum, or the programmer states it |
| Hand-written SIMD kernels: separator scan with odd-run pairing, prefix-count rank, masked gather, bucketed probe, 16-lane blend † | string_split (13×), list_filter (7×), dict (sparse 1.7× over the best scalar table, 5.3× over today; dense gather 2.3–2.6×), branch_mixed (2.1×), float_math (1.1×) | 1.1–13× | c | a SIMD stdlib (byte scan, hash probe, gather); not compiler-derivable |
| Dictionary layout: read-only probe without hint writes; `{key,value}` in the slot; load ≤ ½; branch-free bucket probe | dict_lookup (1.78×; sparse 3.2× scalar, 5.3× SIMD) | 1.8–5× | a (library) | runtime change in `native_dictionary.c`; insertion order untouched |
| Cheap hash on sequential keys ‡ | dict_lookup (3.3× at the same layout) | 3.3× | **d** | fixture luck (collision-free layout of sequential ints); do not bank it |
| Dense-key flag (keys `0..n-1` in insertion order) | dict_lookup (1.4× scalar; ×2.3–2.6 with gather) | 1.4–3.5× | a (runtime-adaptive) | only for dense-key dictionaries |
| Schema-directed decode into records, flat small objects | json parse (1.56×; flat objects 1.71×) | 1.6–2.7× | b / c | typed JSON decode, or call-site specialization of `loads` |
| Threaded dispatch (replicated indirect jump) | lox_eval (1.47×) | 1.5× | b / c | an interpreter-loop construct or pass; LLVM does not tail-duplicate a shared switch |
| Unswitching the fixture's per-element `kind` dispatch | float_math (1.11×) | 1.1× | a | loop unswitching on a local never reassigned in the loop |
| L2 sticky checks / hoisted bounds | float_math (0.88×), list_filter (1.05×), branch_mixed (1.26×), pilot (≈1.0×) | 0.9–1.3× | b (L2) | confirms the pilot: low value; keep WP-3 behind the others |
| FMA contraction | float_math (1.37×) | 1.4× | b | FLOAT-DOMAIN-1 relaxation or explicit `fma`; changes results in general |
| Runtime guard on an immutable list / program (hoisted out of the outer loop) in place of a fixture range | float_math, list_filter, tagged_stack (hand-kernel speed kept), branch_mixed (0.72 vs 0.30 for the hand kernel), json (the typed parser assumes no layout) | the whole gain in three cases, two thirds (log scale) in branch_mixed | a | loop versioning on a predicate over immutable data, computed once per list; a transform no pass does today |
| Target AVX2 instead of baseline x86-64 | float_math (2.0×), branch_mixed (2.1×); no effect on the scalar or hand-written rungs | 1–2× | L4 | supports L4 |
| Memoization / closed forms / partial evaluation | float_math v11–12, string_split v8, lox v7 | — | WORK ELIM | excluded |

## Ranking of the levers

By total expected impact across the nine cases (sum of log₂ gains over the cases each lever touches, counting the
pilot; hand-written kernels included for completeness), with the effort note that matters for the decision:

1. **Range facts → narrow types emitted → LLVM vectorization** (≈9 doublings over 5 cases: integer_math, float_math,
   branch_mixed, list_filter, tagged_stack; 1.5–13× each). The ceiling lever, and the one the pilot found. Needs a front
   end that carries ranges and emits narrow widths (WP-8); markers on QBE-shaped IR do not do it (v13).
2. **Hand/library SIMD kernels** (≈8 doublings over 4 cases: string_split, list_filter, dict, branch_mixed; 2–13×).
   Large but not compiler-derivable (class c): each is a kernel in the runtime or stdlib.
3. **Allocation and copy removal for non-escaping values, borrowed `encode()`, views** (≈4; string_split, json).
   L3 plus lifetime analysis (WP-4). The effect is on small-object-heavy code, not on large lists.
4. **Union / aggregate materialization** (≈2.4; tagged_stack, lox_eval; 1.8–3.0×) — smallest change, largest ratio per
   line of work, and it is **not in the plan**.
5. **Modular strength reduction** (≈2.3; four cases; needs ranges).
6. **RC / hint / ready-call protocol on unique values** (≈2.1 measured, more in the real binary because the models are
   at 70–100% of B0 and json is at 21%; six cases). WP-5 and WP-6c.
7. **Fusion and specialization of `split`/fold** (≈2; string_split).
8. **Typed decode** (≈1.4; json), **threaded dispatch** (≈0.7; lox), **FMA** (≈0.45), **L2 sticky checks** (≈0.2).

What the L1 gate (≤ 1.10× Zig ReleaseSafe) needs is a different, cheaper set. Reading the ladders against the B0 Zig-safe
cycle counts, the (a)-class implementation rungs alone reach it in float_math (inline conversion: 6.4 vs 6.5),
tagged_stack (rungs 2+8: 36.9 vs 53.8), lox_eval (v3: 187 vs 519), string_split (v2–v3: 37 vs 66.5, scaled for the
model's 69%: 54), list_filter (v3: 9.3 vs 10.7, scaled 11.2: borderline) and dict_lookup / branch_mixed (already at or
below Zig-safe on cycles). json parse is the open one (B0 is 4.6× Zig-safe and the model covers only a fifth of it).
**None of these needs a new language fact; they are RC-protocol, materialization, inline-lowering and allocation
fixes.** The range → narrow → vector chain is what gets from there to Rust and beyond.

## Agreement and disagreement with the pilot

- **Agrees:** the range fact is the one that unlocks vectorization (float_math 2.1× then 2.5×; branch_mixed 1.4×
  then 2.3×; list_filter's sign fact 2.0×). L2-style sticky checks and hoisted bounds give 0.9–1.3×. LLVM does not
  narrow by itself. Hand vectorization beats LLVM's best by 1.1–2.1× where LLVM can autovectorize at all.
- **Qualifies:** the pilot read "narrow storage" as necessary for 256-bit vectors (2.4×). Here u16 storage was 1.0× in
  all three cases that tried it, because 32-bit lanes already vectorize from i64 storage; the pilot's gain came from
  16-bit lane math.
- **Adds, and weakens the idea that the range fact is the whole story:** in six of eight cases the largest single
  step toward the L1 gate is an **implementation** fix that needs no fact: an inline conversion, a union stall, an
  RC/hint protocol, a region. The pilot kernel (one function, one list built in the same function) hides this.
- **Qualifies the fixture facts:** dict values and `values` cross a call boundary in the collections benchmarks, so
  the pilot's local range fact is not derivable there without interprocedural specialization; and the dictionary's best
  ratios come from sequential keys (class d).
- **Holdouts:** a runtime guard on an immutable list (or a program) recovers the whole range+vector gain when the data
  comes from a file in float_math (1.24 vs 1.25 cycles), list_filter (0.66 vs 0.66) and tagged_stack (9.8 vs 9.8), and
  two thirds of it on a log scale in branch_mixed (0.72 vs 0.30); the fact-free alternatives sit at Rust speed or worse.

## The biggest surprises

1. `int(float)` is a runtime call (1.9×).
2. **Store-forwarding stalls** from 16-byte union copies explain 1.8× (tagged_stack) and 3.0× (lox_eval); the counter
   matches B0 within about 10%. Zig has the same defect, Rust does not.
3. `assume` on ranges, including the result's, did not let LLVM narrow (float_math v13).
4. **Hash luck:** the same table layout is 3.3× faster or slower depending on whether the hash spreads sequential keys
   perfectly; real programs should expect the sparse-key numbers.
5. Branchy scalar probing is layout-sensitive (17 vs 35 cycles for the same source after an unrelated rebuild);
   branch-free SIMD probing is not.
6. branch_mixed has no branch problem (0.6% mispredicts); fusion does not pay in scalar `list_filter`; a select makes
   a predicted branch slower.
7. The JSON model could only reach 21% of B0's instruction count even with the observed scanner retain/release added;
   the rest is value-move RC traffic that none of my rungs removes, so the real ladder is steeper than the one measured.

## Limits and what was not done

- Wall-clock numbers are single-host and noisy; cycle counts are the stable column. dict_lookup's scalar probe
  rungs (v1–v5, v10, sparse v22/v30) depend on code placement; the SIMD rungs did not. No confirmation sessions.
- The B0 `my-llvm` dictionary predates PY-DICT-4; `integer_math` was not redone.
- Models, not mylang: step 0 is a C reconstruction (fidelity table above). json parse is the weak one.
- Not built: a simdjson-style two-stage parser, a bytecode verifier for lox_eval (v8/v9 are bounds that assume one), the
  composition table for tagged_stack's finite-state chain (it would be WORK ELIM), a `dumps` study.
- Hand kernels that bound their lanes (sizes ≤ 32 767 for u16 ranks, 32 768 for the u32 accumulators) trap or fall
  back outside the bound; the bounds are in the code comments.

## Files

`ladder.py` (verify / time / perf), `ladder_cases.py` (the rung lists), `build.sh`, `make_tables.py` (regenerates the
tables), `common.h`; kernels `float_math.c`, `list_filter.c`, `dict_lookup.c`, `tagged_stack.c`, `string_split.c`
(+ `fuzz_string_split.c`), `branch_mixed.c`, `json_parse.c` (+ `json_gen.h`, `json_typed.h`), `lox_eval.c`;
`results/<case>.json|.time.txt|.perf.txt` hold the raw output of the runs behind the tables.

```bash
./build.sh                              # native and -mcpu=x86_64 builds into build/
python3 ladder.py verify list_filter    # every rung against the B0 rust checksum at several sizes
python3 ladder.py time list_filter      # 7 interleaved rounds on CPU 10
python3 ladder.py perf list_filter      # cycles, instructions, branch misses, store-forward blocks
python3 make_tables.py list_filter      # the table in the README
```
