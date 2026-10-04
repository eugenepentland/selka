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
