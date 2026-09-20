# LLVM and runtime fixes — 2026-09-19

Implemented with three Sol agents and integrated against the full repository
suite. LLVM wall time fell **11.7–16.5%** relative to the frozen previous LLVM
binary in the same batch. The updated LLVM arm is **1.14–1.21×** as fast as the
updated QBE arm. Updated QBE wall time fell **2.9–8.1%** from its own baseline.

The **2× Zig goal is not reached**: updated LLVM is 3.40–5.32× Zig with stdout
captured as bytes, and 3.41–5.74× with timed stdout sent to `/dev/null`.

## Matched wall-clock results

Median milliseconds, 31 interleaved rounds, all five arms per round, pinned to
logical CPU 6. Each arm receives the same input and must agree on stdout, stderr
and status. Both old binaries were frozen before implementation. Each newly built
arm uses ReleaseFast guest lowering; the adapter uses LLVM `-O2`. Runtime archive
hashes, compiler/adapter hashes, input hashes, raw samples and round order are in
[the capture evidence](../../experiments/llvm-backend/evidence/fixes-20260919/measure-capture.json).

| Workload | Old QBE | Old LLVM | New QBE | New LLVM | Zig | New LLVM / Zig |
|---|---:|---:|---:|---:|---:|---:|
| Census 927 KB | 9.302 | 8.553 | 8.693 | 7.213 | 2.123 | 3.40× |
| Render 927 KB | 14.431 | 13.466 | 14.019 | 11.892 | 2.770 | 4.29× |
| Census 7.42 MB | 84.368 | 78.363 | 77.552 | 65.417 | 14.213 | 4.60× |
| Render 7.42 MB | 127.518 | 120.296 | 120.902 | 105.796 | 19.877 | 5.32× |

| Workload | LLVM time removed | Old LLVM / new LLVM, paired-round 95% interval | New QBE / new LLVM |
|---|---:|---:|---:|
| Census 927 KB | 15.7% | 1.186× [1.169, 1.199] | 1.205× |
| Render 927 KB | 11.7% | 1.132× [1.119, 1.143] | 1.179× |
| Census 7.42 MB | 16.5% | 1.198× [1.188, 1.213] | 1.185× |
| Render 7.42 MB | 12.1% | 1.137× [1.128, 1.144] | 1.143× |

These are within-batch effects. Do not compare the absolute milliseconds to the
older audit or original experiment to estimate a gain: machine state and the
original Python text-decoding overhead differ. The reference remains the frozen
Zig ReleaseFast benchmark, with byte-for-byte output parity.

A separate 31-round batch redirects timed stdout to `/dev/null`, with output
checked before and after. It supports the same direction and similar magnitude
for the fixes, but makes the large-render Zig ratio less favorable because output
capture accounts for more of Zig's shorter run. These measurements are separate;
no ratio mixes samples between them. [Null-output evidence](../../experiments/llvm-backend/evidence/fixes-20260919/measure-null.json).

| Workload | Old LLVM ms | New LLVM ms | Zig ms | New LLVM / Zig |
|---|---:|---:|---:|---:|
| Census 927 KB | 8.521 | 7.190 | 2.107 | 3.41× |
| Render 927 KB | 13.369 | 11.755 | 2.585 | 4.55× |
| Census 7.42 MB | 78.533 | 65.979 | 14.370 | 4.59× |
| Render 7.42 MB | 119.149 | 105.024 | 18.299 | 5.74× |

## Changes

- **Shared scratch lowering:** 192 of the benchmark's 211 later aggregate scratch
  allocations move into entry. There are now 273 entry aggregate buffers and 19
  later buffers, including the 81 previously in entry. The physical floor probe
  stays beyond QBE's static frame; LLVM uses its actual stack pointer for the
  recognized guard. Frame estimates still include all scratch and outgoing call
  storage. Heap-backed frames retain their existing allocation path.
- **GC tracing:** generated descriptors carry a filtered trace-field table and an
  explicit pointer-free mode. Equality, drop and other structural consumers keep
  the complete field table. Runtime-created zero-initialized descriptors preserve
  their legacy traversal. Native artifact ABI v5 and layout identity v2 invalidate
  cached objects built for the old descriptor structure.
- **LLVM ABI and memory operations:** exact runtime C signatures, typed memset,
  conservative pointer-origin recovery for GEP, correct small aggregate coercion,
  independent by-value argument storage, and `byval`/`sret` for memory arguments
  and results. Register exhaustion rolls a whole aggregate onto the stack,
  including when a hidden result pointer consumes a register. Each static
  aggregate call has one entry result buffer, reused by loop iterations.
- **Budget correctness:** `emit-qbe` and `emit-project-qbe` now retain frame
  accounting unless explicitly dropped. Previously they depended on a run-only
  flag that the build emission command could not accept, so even Debug binaries
  refused requested frame budgets. A CLI regression covers explicit ReleaseFast
  accounting and Debug's default.
- **Validation:** failed builds no longer count as agreement; three historical
  invalid trap fixtures have valid replacements. The verifier enables budgets at
  compile time and requires actual frame/step traps, including under GC stress.
  Measurements keep raw rounds, capture bytes without Python text decoding, and
  fingerprint imported adapter files and optimizer settings in their cache root.

Implementation: [QBE lowering](../../src/qbe.zig),
[descriptor generation](../../src/native_descriptors.zig),
[collector](../../src/native_heap.c), [budget emission](../../src/main.zig),
[LLVM emitter](../../experiments/llvm-backend/llvm_emit.py),
[ABI classification](../../experiments/llvm-backend/amd64_sysv.py),
[runtime declarations](../../experiments/llvm-backend/runtime_signatures.py).

## Correctness boundaries found during integration

Unrestricted entry hoisting caused a network resource-cleanup crash. Opaque
runtime/provider buffers therefore retain their original later allocation. QBE
slot coalescing was ruled out; the exact optimization/escape defect is not yet
isolated. This is a conservative boundary on the optimization.

Semantic zero-length arrays also need later scratch even though their native
layout reserves a byte and scratch reserves at least a word. Entry placement
interacted with zero-byte blits and crashed a generic array fixture. The baseline
compiler passed that fixture; the new regression checks the exceptional placement
and the full language suite now passes. Nonempty traced aggregates remain eligible
for entry placement.

The LLVM adapter still supports the emitted AMD64 integer/byte-aggregate subset,
not arbitrary QBE aggregate layouts or other targets. Unknown runtime helpers fail
translation until their C signatures are registered. QBE remains the default.

## Validation

- `zig build test --summary all`: **60/60 steps**, **1,347 selected Zig tests**;
  sharding accounts for the runner's skipped count. This also passed **214 language
  tests under GC stress** and **42 standard-library tests**.
- Guardian: **88/88 checks**, with the configured diff-scoped per-file checks and
  whole-tree checks. No waivers or baseline changes.
- Native collector C harness: Debug and ReleaseFast pass with assertions enabled;
  the agent also ran ASan/UBSan. The new `test-native-heap` step is part of normal
  `test` and `test-qbe` and can run without installing the compiler.
- LLVM adapter: **10 tests**, including C/LLVM by-value witnesses,
  aggregate sizes/alignment, register rollback with hidden sret, mutable-temp
  provenance/guard decoys, and a **200,000-iteration** aggregate-return loop.
- Four separately linked QBE/LLVM caller/callee combinations all return **11**
  in the by-value mutation witness (the old LLVM adapter returned 99).
- **66/66** final benchmark units translate and assemble.
- **79/79** schematic-port tests under LLVM and GC stress. Individual entry runs
  also verified the directory runner's summary, which had hidden compiler failures
  during an earlier attempt; failing diagnostic output was not accepted as a pass.
- **504/504** trap comparisons, with actual budget enforcement and GC stress.
- **270/270** golden, malformed/Unicode-input and GC-stress comparisons against the
  frozen QBE oracle. Stress runs are limited to fixtures below 2,000 bytes.
- Formatting and `git diff --check` pass.

[Verification logs and build identity](../../experiments/llvm-backend/evidence/fixes-20260919/README.md)
include the discarded preliminary frame-budget comparison for transparency. Its
agreement-by-refusal result is explicitly excluded from the successful gate.

## Counter evidence and remaining work

Median user-mode counters from ten separate interleaved rounds; millions of
instructions/cycles. They include the runtime and libc, and exclude the Python
parent. Wall timing comes from runs without the perf wrapper.

| Workload | LLVM instructions, old → new (M) | LLVM cycles, old → new (M) |
|---|---:|---:|
| Census 927 KB | 76.09 → 65.59 | 25.29 → 20.09 |
| Render 927 KB | 126.02 → 109.55 | 40.74 → 34.76 |
| Census 7.42 MB | 662.08 → 556.78 | 253.65 → 202.94 |
| Render 7.42 MB | 1061.68 → 908.58 | 389.58 → 336.87 |

The implementation improves useful work and wall time, but does not establish
which individual change supplied each fraction of the combined gain. It also does
not justify extrapolating another backend switch to the 2× target. The remaining
large-input work identified by the audit is text representation and allocation:
source spans/views during tokenization, less per-character string construction,
and a byte builder for rendering. Those representation changes remain future work.
