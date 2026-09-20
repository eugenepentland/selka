# Runtime and LLVM fixes: verification evidence

The original experiment evidence in the parent directory is unchanged. This
folder records the follow-up implementation and its matched before/after batch.

The report is [LLVM and runtime fixes](../../../../docs/audits/llvm-runtime-fixes-2026-09-19.md).

- `traps-final.json`: 504 comparisons with actual frame/step accounting and GC
  stress. The verifier additionally requires recursion to reach `R_FRAME_LIMIT`
  or `R_STEP_LIMIT`, and rejects accounting-refusal diagnostics.
- `traps-rejected-missing-frame-accounting.json`: **discarded preliminary gate**.
  Its zero differential mismatches were misleading: both backends refused frame
  budgets. Do not count this file as successful frame-limit validation.
- `goldens.json`: benchmark golden, malformed/Unicode input, and bounded GC-stress
  comparisons against the frozen pre-change QBE binary.
- `measure-capture.json`, `measure-null.json`: separate 31-round matched batches.
- `comparison-summary.json`: derived speedups and paired-round intervals.
- `manifest.json.gz`, `allocation-placement.json`: final emitted closure and the
  before/after placement counts.
- `build-identity.json`: compiler, adapter and key implementation hashes.
- `byvalue-interop.json`: all four QBE/LLVM caller/callee combinations preserve
  the caller's aggregate when the callee mutates its independent copy.
- `repository-tests.txt`, `adapter-tests.txt`, `port-tests.txt`, `units.txt`,
  `native-heap-*.txt`: successful validation output.

Wall measurements retain raw samples and round order. Captured output is bytes;
there is no Python text decoding in the timed path. Instruction and cycle events
count user mode, including the C runtime and libc. The null-output measurement is
separate and checks captured output before and after its timed runs.
