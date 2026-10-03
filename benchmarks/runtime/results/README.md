The first runtime baseline compares **main `6df58b02554401f9d37564cceffd14277a835ae1`**
with Rust, Go, and Zig on an Intel Core i7-12700H. Sol 6.1 agents implemented the
ports and runner and executed the measurements. The compiler and runtime source
remain identical to that main revision; the benchmark suite was frozen at
`1d053a1422d455a38bf18ebdbcfc32dcfa02aae7` before the run.

Median kernel **ns per operation**, lower is better, for the large profiles:

| Workload | MyLang LLVM | MyLang QBE | Rust | Go | Zig Safe | Zig Fast |
|---|---:|---:|---:|---:|---:|---:|
| Record reads, 4096 records | 5.74 | 11.91 | 3.86 | 4.66 | 5.30 | 4.85 |
| Tagged stack, 4096 opcodes | 25.06 | 32.00 | 5.71 | 6.01 | 10.66 | 10.66 |
| Unique mutation, 1024 elements | 5.39 | 30.39 | 3.44 | 3.96 | 4.27 | 4.36 |
| Shared snapshot + mutation, 1024 elements | 277.99 | 335.77 | 83.94 | 732.20 | 188.48 | 145.86 |

Each operation follows the [fixed contract](../CONTRACT.md). Snapshot creation,
preservation, observation, and release are inside the shared-mutation timer.
All ports preserve the same logical values using their native facilities:
MyLang COW/RC, Rust vector cloning, Go slice copying with normal GC, and Zig
allocator duplication. Setup and result formatting are outside kernel timing.

The strongest priorities are the tagged stack on both MyLang backends and
unique mutation on QBE. Paired median time relative to Go is 4.170× for LLVM's
large tagged stack (95% interval 4.158–4.181), 5.311× for QBE's tagged stack
(5.289–5.339), and 7.686× for QBE's unique mutation (7.378–7.837). These are
useful targets for generated-code inspection and profiling; this run does not
establish the specific lowering or runtime mechanism responsible.

Shared snapshots change the ranking with size. At 64 elements, LLVM and QBE
take 2.139× and 3.025× Go's time; at 1024 elements they take 0.377× and 0.457×,
respectively. Rust and both Zig configurations still beat MyLang on the large
case. This result compares complete snapshot behavior, including allocation
and collection; attributing the crossover solely to the compiler or GC would
require further profiling. Ratios are medians of paired rounds and can differ
from division of the separately reported time medians.

The run contains **720 samples**: four cases × two sizes × six configurations ×
15 rounds, plus 144 warmups, 72 edge correctness probes, 47 calibration sets,
and 48 separate peak-RSS probes. Every guest result passed checksum and output
validation. The independent verifier recomputed coverage, expected values,
summary arithmetic, and bootstrap intervals, and checked source/tool/runtime/
binary hashes against the current artifacts. No timed samples were discarded.

CPU 2 was pinned; sibling CPU 3 averaged 0.74% busy during the measured phase.
No benchmark builds overlapped sampling. The machine used `intel_pstate` with
the `powersave` governor, so frequencies were not fixed. The recorded 400 MHz
end-of-run frequency is an idle observation, not the operating benchmark
frequency. Sibling load is an average and does not prove exclusive CPU access.

Four profiles (both record-read and both unique-mutation sizes) reached the
10-million-iteration cap before the fastest arm reached the 50 ms target.
Their final pilot fastest times were approximately 29–40 ms, and the raw report
marks these limits. Unique-mutation samples have noticeable spread; LLVM's
large shared snapshot has a 449 ns/op maximum versus its 278 ns/op median.
Bootstrap intervals describe the sampled paired medians and do not cover
every source of system drift or establish performance on other machines.

Build policies are optimized defaults, with different safety and CPU-target
policies. MyLang uses ReleaseFast with normal checks/RC; LLVM uses O3 and LTO,
and QBE uses its normal optimization pipeline. Rust uses `-O`, Go normal
`go build` with `GOAMD64=v1`, and Zig ReleaseSafe/ReleaseFast. MyLang LLVM and
Zig inherit host features, while Rust's default target and Go v1 are generic.
Go uses `GOMAXPROCS=1`, `GOGC=100`, and `GOMEMLIMIT=off`. Tool versions, exact
commands, environment, target-feature probe, and binary identities are retained
in the JSON. This is an initial baseline for three runtime families, not a
language-wide performance ranking or a comparison with matched instruction sets.

Evidence and reproduction:

- [All small/large results and paired intervals](baseline_main_20261003.md)
- [Raw measurements, build logs, and identities](baseline_main_20261003.json)
- [Validation and provenance receipt](validation.json), with compressed build
  and regression logs under [validation](validation/)
- [Runner usage](../README.md) and [independent verifier](../verify_report.py)

The main compiler build passed, `zig build test --summary all -j2` passed all
115 steps (2826 tests passed; 28726 shard-filtered skips), `test-qbe` passed
514 tests, and `test-qbe-build` and `fmt-check` passed. The suite's ten unit
tests passed. The code commits passed Guardian's whole-tree 88-check gate
without waivers or baseline changes. Full logs keep expected negative-test
diagnostics separate from command exit status and final build summaries.

The measured command, after compiling and qualifying the frozen artifacts, was:

```sh
python3 benchmarks/runtime/runner.py --skip-build --rounds 15 --warmups 3 --output benchmarks/runtime/results/baseline_main_20261003.json
python3 benchmarks/runtime/verify_report.py benchmarks/runtime/results/baseline_main_20261003.json --check-artifacts
```

To reproduce from a fresh checkout, build the pinned main compiler as recorded
in `validation.json`, then omit `--skip-build` on the first runner invocation.
