# A03 C0-supplemental-A04-render census

Compiler commit: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Compiler SHA-256: `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
Ownership request: `opt-in`.

Executed 0 guests; 0 passed output, exit, RC and managed-leak checks.
Observed RC in 0 runs; managed exit leaks in 0 runs.

This supplemental manifest is separate from the original 30 and pinned 81-case matrix; its cases do not change either denominator.

| Configuration/status | Cases |
| --- | ---: |
| release/refused | 1 |

Classification describes storage required by source semantics and concrete optimization opportunities. It does not attribute every allocation to one category.
Formatting/concatenation intermediates are actionable candidates only after an owner demonstrates a semantics-preserving removal.
Explicit copies and independent return storage must retain their documented independence. Growth is legitimate allocation work.
Task infrastructure is covered separately by the expanded task cases and A01's scheduler decomposition.

For every admitted executable, machine-readable results preserve source/binary/LLVM hashes, output, workload and whole-program counters, and LLVM/linked-symbol audit results.
`raw-json.tar.gz` contains the command receipts and complete counted reports. Full native binaries and LLVM remain in the recorded scratch run directory.
Managed peak is never subtracted as traffic and is not process RSS. Native dictionaries, sort scratch, provider buffers, task stacks and allocator overhead lie outside these counters.
Admission receipts record queue wait separately for batched runs; command receipts mark whether wait is excluded. These are not compile-performance measurements. A09 owns runtime/RSS/compile timings.

## Failures and refusals

- `supplemental/a04-render-borrows/release`: refused. `/home/epentland/ai/canopy/mylang-memory-20261012-A03/.tmp/memory-closeout/A03/C0-supplemental-A04-render/raw/supplemental/a04-render-borrows/release/main.my:1:1: error[E_CORE_UNSUPPORTED]: the new core does not support unaudited zero-RC runtime helper myl_core_render_shape_16_21 yet`
