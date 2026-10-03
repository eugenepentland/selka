# Checked Lox callee/table checkpoint

The selected source adds plain VM callee descriptors and readonly table-entry
arguments to the accepted 80-test checkpoint. It contains 84 public tests.
The [report](../../docs/audits/lox-callee-table-checkpoint-2026-10-03.md)
records matched wall/counter results, qualification and remaining Rust/Go gaps.
`sources.json` pins all 37 files of both the control and selected source.

Prepare a new workspace using an explicitly selected ReleaseFast compiler:

```bash
LOX_WORK=/absolute/path/to/new-workspace
LOX_COMPILER=/absolute/path/to/qualified-releasefast/bin/mylang
python3 experiments/lox-callee-table-checkpoint-20261003/prepare.py \
  --work "$LOX_WORK" --compiler "$LOX_COMPILER"
```

`prepare.py` reconstructs the current optimized migration and reverses only
the new callee/table patch to obtain the exact 80-test control. It refuses an
existing workspace and checks all 37 source files before/after builds. It
builds both sources with checked RC, LLVM O3/full LTO and checked QBE, then
builds Rust/Go from `4e48a09220c2e018eba8c4b1eb3fe1137a3dae73`. The compiler,
adjacent QBE, guest/runtime objects, source, toolchain identities and commands
are recorded. Reference tool overrides are `--cargo`/`--go` or the historical
`LOX_BENCH_CARGO`/`LOX_BENCH_GO` variables. Go VCS metadata is disabled for
reproduction; the published results retain their original frozen Go ELF.

The original benchmark harness defaults to a September compiler pin. This
recipe supplies the compiler explicitly and applies the qualified source;
running that historical default does not reproduce these results.

Run one timing/counter command at a time, using new receipt names:

```bash
python3 experiments/lox-parity-20261003/run.py check --work "$LOX_WORK" \
  --out "$LOX_WORK/smoke.json" --tier smoke --stats --rounds 1 \
  --arms baseline-llvm,baseline-qbe,combined-llvm,combined-qbe,rust,go --cpu 10
python3 experiments/lox-parity-20261003/run.py time --work "$LOX_WORK" \
  --out "$LOX_WORK/wall.json" --tier timed --rounds 3 --engines vm,tree \
  --arms baseline-llvm,baseline-qbe,combined-llvm,combined-qbe,rust,go --cpu 2
python3 experiments/lox-parity-20261003/analyze.py "$LOX_WORK/wall.json" \
  --candidate combined --metric wall_s --out "$LOX_WORK/wall-analysis.json"
python3 experiments/lox-parity-20261003/run.py counters --work "$LOX_WORK" \
  --out "$LOX_WORK/counters.json" --tier tree --rounds 3 --engines vm,tree \
  --arms baseline-llvm,baseline-qbe,combined-llvm,combined-qbe,rust,go --cpu 10
python3 experiments/lox-parity-20261003/analyze.py "$LOX_WORK/counters.json" \
  --candidate combined --metric instructions --out "$LOX_WORK/counter-analysis.json"
```

CPU 2/sibling 3 are reserved for wall time and 10/sibling 11 for counters;
build-slot admission excludes all four. Counter sizes use the calibrated tree
tier on both engines; wall sizes use the original engine-specific tier. A
three-round result remains a focused Lox comparison, with paired-ratio spreads
reported, rather than certification of the full compiler performance gate.

The source patch SHA256 is
`1e75f5164ab1385832145f50aee1c5e11d07dc8a6902747f386e88770445a7db`.
The measured compiler is the fixed combined compiler
`d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040`,
with adjacent QBE
`99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63`.
Raw root evidence is under `.tmp-lox-next`; compiler-only experiments use the
separate `.tmp-lox-write-screen` manifest. Their one-round instruction screen
is diagnostic and does not replace the final source matrix.
