# Lox performance checkpoint, 2026-10-03

This directory records the 80-test checkpoint at `6e516f65`. The current
optimized migration includes the subsequent 84-test callee/table checkpoint;
use [its fresh-build recipe](../lox-callee-table-checkpoint-20261003/README.md)
for the current source. Reproduce this directory's measurements from its
pinned checkout or sealed archive.

This experiment continues the evaluator improvements at `fd86729e`. It keeps
both engines and all thirteen scripts in scope, with the Rust/Go source and
inputs pinned to `4e48a092`. LLVM O3/full LTO with checked RC is the primary
target; checked QBE is also measured. Native tracing GC artifacts qualify
correctness separately. The complete Lox architecture/algorithm restrictions
remain in the pinned benchmark SPEC.

This checkpoint's optimized migration applies
`docs/audits/d9-stage3d-migrations/lox-runtime-perf-20261003.patch` after the
October 2 patch. Its SHA256 is
`233332c7b4fd1325f3ec1251406b0b433e87520f5abc4db9cfcc70e79813445b`.
The new patch changes six files and includes all 80 public tests and explicit
driver provider fixtures. Its exact replay matches all 37 port/metadata files.

The source changes separate readonly Program from mutable Runtime/Output,
avoid Runtime extraction/writeback on each tree operation, improve environment
updates and argument construction, shorten VM operand lifetimes, and read
scalar object costs/free tags during sweeping. Indexed writes retain their
normal snapshot/COW and bounds protocol. Object costs, GC thresholds, root
order, slot reuse, opcode set, frame bound, outputs and collector statistics
remain unchanged.

Two separate compiler candidates recognize checked positive indexes and
refine existing closed record-field transfers. Their contracts, refusal
conditions and qualification are in [positive-index-notes.md](positive-index-notes.md)
and [field-inout-notes.md](field-inout-notes.md). The field-inout optimization
benefits the older tree source; flattened source emits the same guest binaries
under positive-only and combined compilers.

The private workspace is `.tmp-lox-parity/` in the integration worktree. Its
`binaries.json` binds every arm to exact executable and source hashes.
`run.py` records argv, logs and source checks before/after execution; the
shared audit runner interleaves shuffled arms, verifies exact output/status,
records every sample and checks executable/input identities afterward.
`analyze.py` refuses incomplete case/arm/round coverage or unexpected
diagnostics and reports medians of paired ratios followed by engine geometric
means. Counter checkpoint inputs use the unchanged calibrated tree sizes;
wall checkpoint inputs use original engine-specific sizes.

Build and compare a fresh port (use absolute scratch paths):

```bash
PERF_WORK=/absolute/path/to/empty-scratch
COMPILER=/absolute/path/to/qualified-releasefast-mylang
mkdir -p "$PERF_WORK/tmp" "$PERF_WORK/bin"
docs/audits/d9-stage3d-migrations/apply-lox.sh "$PERF_WORK/port" --optimized
python3 experiments/lox-parity-20261003/build.py --work "$PERF_WORK" \
  --source "$PERF_WORK/port/lox/benchmarks/lox/ports/mylang" \
  --compiler "$COMPILER" --name candidate
```

For the preceding control, use `apply-lox.sh --optimized` in a separate
checkout at `fd86729e`; applying the new patch twice is invalid. The compiler
control SHA256 is `45d05b554849bf3c12553549d9138556ba0204f9d59ba3aaa2ecb2327eb39ac4`.
Positive-only compiler SHA256 is
`da94c579e03ffaab2e9d43a6d9119b529bbb01dab5085e7a3986a6ecd98912c6`;
combined compiler SHA256 is
`9007d0532fe0ed8e0a17568c2e7e796023ddd59e76137efa0181fefca3685288`.
The final corrected combined compiler SHA256 is
`d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040`.
Its CFG-entry refusal fix and focused 27-test qualification are described in
[positive-index-cfg-fix-notes.md](positive-index-cfg-fix-notes.md). Its final
LLVM/QBE guests are byte-identical to the measured pair.

Recheck the preserved workspace without overwriting any earlier receipt:

```bash
python3 experiments/lox-parity-20261003/run.py check --work .tmp-lox-parity \
  --out .tmp-lox-parity/measurements/new-smoke.json --tier smoke --stats \
  --rounds 1 --arms baseline-llvm,baseline-qbe,final-sweep-llvm,final-sweep-qbe,rust,go
python3 experiments/lox-parity-20261003/run.py time --work .tmp-lox-parity \
  --out .tmp-lox-parity/measurements/new-timing.json --tier timed --rounds 3 \
  --arms baseline-llvm,baseline-qbe,final-sweep-llvm,final-sweep-qbe,rust,go --cpu 2
python3 experiments/lox-parity-20261003/analyze.py \
  .tmp-lox-parity/measurements/new-timing.json --metric wall_s \
  --out .tmp-lox-parity/measurements/new-timing-analysis.json
```

Use one measurement command at a time. CPU 2/sibling 3 is reserved for wall
time; CPU 10/sibling 11 for counters/profiles. Builds/tests use build-slot
admission. Separate compiler/source arms preserve attribution; diagnostic
screening samples do not substitute for the final matched reference matrix.

The preserved alternatives include rejected VM frame flattening, additional
scalar AST projections, table scalar reads, and direct tree call dispatch.
The noinline audit rebuilds the profiled guest byte for byte and finds zero
relevant noinline attributes across 417 LLVM units; it makes no compiler change.
Their raw evidence remains available even when they are not selected.

Native stress uses `MYLANG_OPTIONS='--gc-stress'` or the equivalent test CLI
option. The older VM probe mistakenly used an ignored variable; its receipt
is retained and explicitly invalid for native-stress claims. The corrected
64 observations were actually rerun and passed. Full qualification records
list intentionally unrun native-stress corpus cells rather than counting them
as passes.

Results and remaining Rust/Go gaps are recorded in
[the integration audit](../../docs/audits/lox-perf-parity-checkpoint-2026-10-03.md).
The sealed raw archive is
`/home/epentland/ai/canopy/evidence/lox-parity-20261003/integration`; its
`MANIFEST.sha256` is
`3d217a3ead06112b522d608bc384d2a3a64e91907587a375460bbb76c52db31f`.
This checkpoint does not claim matching Rust/Go or the full compiler
performance gate on every application.
