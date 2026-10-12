# A03: fresh allocation and RC census

This directory owns a fresh adapter and a pinned 81-case manifest. Qualification
is pending a fresh C0 installation, then the integrated candidate. Historical
numbers are inputs to the case list and output oracles, not new measurements.

The manifest preserves all 30 original census IDs and separate original/migrated
source hashes, all 48 historical final-matrix samples, ten migrated library
fixtures, two source parallel-map samples at 1/2/8 workers, all 18 JSON lookup
construction/hit/miss cases, both record-copy/transfer variants, and the nested
owned-JSON sample. Five modes yield 405 builds and 655 counted guest executions.
The original 30 sources also receive separate source-admission checks. Their
diagnostics do not silently replace the migrated workload results.

`census.py` writes only below the requested fresh output directory. Unlike the
historical harnesses, it never publishes back into old experiment directories.
Each compiler invocation acquires the shared build slot. Do **not** wrap this
harness in another admission command. It catches individual refusals/failures,
keeps them in the denominator, and proceeds with independent cases. Resuming
requires identical compiler, toolchain, harness, manifest, and ownership mode.

```sh
source /home/epentland/.config/mylang/dev-env.sh
python3 -B experiments/memory-closeout-20261012/A03/census.py \
  --compiler /path/to/full/installation/bin/mylang \
  --compiler-commit FULL_SHA --zig "$ZIG" \
  --output .tmp/memory-closeout/A03/C0
```

Use `--ownership default` only after the coordinator promotes the default.
`--family historical-48`, `--case census/01_scalar`, and `--modes release` allow
focused checks without changing the complete manifest or its denominator.
Counter evidence is instrumented correctness/allocation evidence, not guest
performance. A09 owns uninstrumented runtime/RSS/compile measurements.

Every admitted run records exact output, exit status, whole-program memory,
workload memory (excluding `<outside>`), RC counters, direct frees and leak
status. Every executable records its hash and an LLVM/symbol audit. Runtime
layout/preprocessor proof remains A07's responsibility. Managed allocation bytes
omit native dictionary metadata, sort scratch, provider buffers, task stacks and
allocator overhead. Peak live bytes are not allocation traffic or RSS, and no
peak subtraction is performed. Counter columns for emitted and runtime RC can
overlap and are never summed.

The adapter imports only the historical read-only counter summarizer and audit
functions. Historical `measure.py`, `qualify.py`, and batch `capture` functions
were inspected and deliberately not invoked: they write reports alongside
themselves even when an alternate output directory is supplied.
