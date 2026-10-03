# Lox performance checkpoint, 2026-10-03

This report describes the 80-test checkpoint at `6e516f65`. The current
optimized migration also includes the subsequent
[callee/table checkpoint](lox-callee-table-checkpoint-2026-10-03.md).
Reproduce this report from its pinned checkout or sealed archive.

The parallel improvements reduce checked LLVM VM wall time **5.77%** and tree
wall time **48.24%** relative to the already optimized October 2 evaluator.
QBE improves **7.25% / 39.57%**. Every individual engine/backend/script median
improves in this three-round comparison. Rust/Go parity remains unmet: LLVM
still takes **2.78× / 2.81× Rust/Go on the VM**, and **4.24× / 4.13× on the tree
interpreter**. The active parity goal continues beyond this checkpoint.

Implementation is integrated on `codex/lox-parity-20261003`. The original dirty
`local-reasoning/integration` checkout and main remain untouched; main is
`6df58b02554401f9d37564cceffd14277a835ae1`. The preceding branch audit found no
existing unmerged Lox runtime win. This checkpoint now provides a measured
source/compiler candidate for main; unrelated old prototypes and improvements
to the reference ports are not performance dependencies.

## Implemented changes

- **Tree state:** separate readonly Program from mutable Runtime/Output and
  pass those through recursive evaluation. This removes repeated owning Runtime
  extraction/writeback. Scalar callee classification avoids unused Obj snapshots.
  Environment writes use indexed updates; argument slots are prepared locally
  before the single original environment allocation.
- **VM:** retain the admitted activation frame, decode operands before stack
  reads, bound operand lifetimes, and read closure arity/upvalue state as scalars.
  The rejected frame-flattening experiment is excluded.
- **Sweep:** read the free tag and scalar object cost directly from the rooted
  object table. The eleven original object-cost expressions, slot freeing order,
  thresholds, COW writes and root publication order remain intact.
- **Compiler:** a checked unsigned guard recognizes exact positive plain-list
  reads and retains the complete original negative-index/cast/add/trap fallback.
  A separate stricter closed record-field certificate passes the rooted inline
  field to a direct inout call, preserving normal leaf COW and callee rebinding.
  It reduces instructions on the older tree source, but the selected flat source
  already removes those carriers: its LLVM and QBE executables are byte-identical
  under positive-only and combined compilers.

The canonical optimized migration applies the new six-file patch after the
October 2 patch. SHA256:
`233332c7b4fd1325f3ec1251406b0b433e87520f5abc4db9cfcc70e79813445b`.
Exact replay matches all **37 port/metadata files**, including **26 modules and
80 public tests**. No inline caches, new opcodes, algorithm changes, unsafe
access, NaN boxing, or safety-check disabling are introduced. The pinned Lox
SPEC and the language value/snapshot semantics remain the contract.

## Matched runtime results

Ratios are medians of candidate/control ratios paired within each round,
followed by geometric means over all thirteen scripts. Percentages are wall
time reductions relative to source `fd86729e` with the frozen main compiler.
These October 3 percentages are incremental; the preceding October 2 gains
must not be added to them.

| Engine | LLVM wall reduction | QBE wall reduction | LLVM/Rust | LLVM/Go | QBE/Rust | QBE/Go |
|---|---:|---:|---:|---:|---:|---:|
| VM | 5.77% | 7.25% | 2.779× | 2.811× | 5.505× | 5.561× |
| Tree | 48.24% | 39.57% | 4.237× | 4.132× | 7.655× | 7.473× |

| Script | VM LLVM reduction | VM QBE reduction | Tree LLVM reduction | Tree QBE reduction |
|---|---:|---:|---:|---:|
| binary_trees | 5.03% | 6.68% | 41.86% | 37.55% |
| closures | 7.29% | 8.42% | 57.24% | 50.56% |
| equality | 5.03% | 11.75% | 69.20% | 46.52% |
| fib | 3.71% | 6.06% | 63.14% | 56.23% |
| instantiation | 12.93% | 9.02% | 31.91% | 29.14% |
| invocation | 2.38% | 1.76% | 28.00% | 24.51% |
| method_call | 1.59% | 5.69% | 43.09% | 36.71% |
| properties | 5.67% | 4.25% | 39.23% | 36.98% |
| string_equality | 3.75% | 10.81% | 64.74% | 44.85% |
| strings | 5.75% | 9.04% | 50.16% | 38.91% |
| trees | 2.07% | 6.82% | 32.47% | 30.15% |
| zoo | 9.02% | 5.83% | 42.11% | 37.28% |
| zoo_batch | 10.03% | 7.68% | 41.77% | 37.06% |

Median three-round paired-ratio spread is 0.73% LLVM VM, 1.87% LLVM tree,
0.46% QBE VM and 1.42% QBE tree. Tree `strings` spreads reach 14.86% LLVM
and 10.77% QBE, so three rounds do not establish narrow confidence intervals.
The report makes a focused Lox comparison; it does not certify the full
43-program compiler performance gate or other applications.

The completed instruction checkpoint has 468 exact successful observations
with all 1,872 instruction/cycle/branch/branch-miss running percentages at
100%. Instruction reductions versus the preceding optimized source are:

| Engine | LLVM instruction reduction | QBE instruction reduction | LLVM/Rust instructions | LLVM/Go instructions |
|---|---:|---:|---:|---:|
| VM | 3.48% | 6.98% | 2.506× | 2.047× |
| Tree | 35.68% | 39.31% | 4.172× | 3.185× |

Every case reduces instructions on both backends. The remaining instruction
premium supports continued work on emitted runtime operations. Counter sizes
differ from wall-time sizes and counter runs include perf measurement overhead;
counter wall times are not the acceptance time series.

## Remaining gaps

The LLVM VM still takes 4.21× Rust on `binary_trees` and 4.59× on
`instantiation`; tree `instantiation`, `invocation`, `method_call` and
`properties` take 5.50–6.65×. Even LLVM VM `string_equality` remains 1.53×
Rust and 1.26× Go. Both engines and both reference languages stay in the goal.

Seven fresh final LLVM profiles verify exact outputs and executable/input
identities. VM `run` contains 64.87% of fib samples and 97.69% of string-equality
samples; `table::get` contains 22.50% on properties. VM `call_value` is 12.13%
on instantiation. Tree binary_trees spreads its hot work across evaluate
9.37%, push 8.18%, collect 5.72%, execute 5.13% and allocate 4.80%; tree
properties includes table reads 7.37% and generated Obj take 6.53%.

These are locations of samples, including inlined work, rather than isolated
ownership/check/dispatch cost categories. They support the next parallel
experiments on VM callee materialization, table carrier lifetimes and further
checked index lowering. Those experiments are outside this measured checkpoint.

The LLVM noinline hypothesis was tested by a byte-identical guest rebuild:
all 417 emitted units have zero relevant function or call-site `noinline`
attributes. It supplies no compiler improvement. The rejected VM frame
flattening increases instructions 2.69% LLVM / 44.82% QBE. Extra scalar AST
projections slow tree wall time 8.23% / 9.06% relative to flat. Scalar table
reads show no gain; direct tree call dispatch has mixed small timings and
six LLVM regressions. Their source and receipts remain preserved.

## Qualification and independent review

The final source passes **320 fresh port tests**: all 80 under QBE Debug and
LLVM release, each with RC and separately with stressed native GC. It also
passes **696 exact bounded status/stdout/stderr/collector-stat observations**.
The native-stressed focused/error coverage includes 296 observations; 104
native-stressed benchmark corpus cells were explicitly unrun. Test-only
one-billion-step and 120-second allowances cover the established stress tests;
production checks are unchanged.

Earlier joined-flat stages passed 312 port tests and 1,144 bounded matrix
observations, including 328 correctly invoked native GC stress observations,
plus 24 error-after-child-return comparisons. They are earlier-stage evidence,
not additional final-sweep passes. An older VM probe used an ignored stress
variable; its receipt is retained as invalid for native-stress claims. All 64
corrected observations were rerun with `MYLANG_OPTIONS='--gc-stress'` and passed.

Compiler qualification passed 2,479 final root tests and 515 QBE/driver/host
reported tests, plus focused native unaccounted lifecycle and trap tests. A
four-shard intermediate run passed assertions but exceeded the existing RSS
ceiling by about 17 MB; the documented twelve-shard run passed without ceiling
failures, without changing caps. Accounted language tests do not exercise the
positive-index fast path; the dedicated unaccounted native tests do.

Independent source review confirms exact cumulative replay, mutation/root/error
ordering, bounded frame behavior and all saved final-source receipts. Independent
compiler review found a missing `try_result.error_target` interior-entry refusal
in the positive-index proof; no source-generated runtime miscompile was shown.
The correction uses shared branch-edge enumeration, adds a synthetic edge
refusal regression, and passes independent review plus 27 focused proof/native
lifecycle tests. Its rebuilt guests are byte-identical to the measured pair;
all 37 source files and compiler/QBE/control hashes are post-verified. The
small refusal correction did not rerun the earlier broad compiler suite.
Field-inout review found no actionable issue within its validated bytecode,
native ABI and existing alias-certificate limits.

The integration whole-tree Guardian gate passes all 88 checks with no waivers
or accepted snapshot changes. Python syntax, shell syntax and added-source
whitespace checks pass.

Independent measurement review verifies exact coverage, source/input/executable
hashes, output/status, all stored paired analyses, pinned reference objects and
canonical replay. Final wall time consists of **468 successful executions**:
13 scripts × two engines × six arms × three rounds. Instructions use a
separate matrix at unchanged calibrated tree sizes. Timings use original
engine-specific sizes. CPU 2/sibling 3 are reserved for wall time; CPU 10/sibling
11 for counters/profiles. Build-slot admission excludes all four CPUs. The
host remains the existing i7-12700H/powersave configuration.

## Reproduction and identities

See [reproduction commands](../../experiments/lox-parity-20261003/README.md)
and the compiler proof notes there. The raw manifest binds exact source,
compiler and guest hashes; each final run records argv/logs and source checks
before/after, then the audit runner rechecks inputs and executable hashes.
Rust/Go sources and all inputs remain
`4e48a09220c2e018eba8c4b1eb3fe1137a3dae73`. Unmerged faster reference branches
are not silently substituted.

| Artifact | SHA256 |
|---|---|
| Baseline compiler | `45d05b554849bf3c12553549d9138556ba0204f9d59ba3aaa2ecb2327eb39ac4` |
| Positive-only measured compiler | `da94c579e03ffaab2e9d43a6d9119b529bbb01dab5085e7a3986a6ecd98912c6` |
| Combined measured compiler | `9007d0532fe0ed8e0a17568c2e7e796023ddd59e76137efa0181fefca3685288` |
| Corrected combined compiler | `d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040` |
| Final LLVM guest | `29a48f65df32df53d80a51a70e4d072d8c85eb77953606a2bbbc71b4ba892764` |
| Final QBE guest | `6217e8fb5308702efcbdfdf2128ffd98cda8bafafc75e183d9130c0b1b402300` |
| Rust guest | `4d869a184a5f1a666113d30ad93a27ac703f39bb56c28e69e0bf739375d03dab` |
| Go guest | `dda2184ecbe1398769096fb284ccf451054e1ce6ff9d92797cdcd153135ca7e3` |

The independent measurement review covers 3,138 observations, all 5,272 PMU
running percentages in 1,318 counter observations, and all 38 saved paired
comparisons. Earliest screening invocations have retrospective argv records
and audit identity checks; uniform outer logs and source-before/after receipts
apply to the final matched checkpoint. The sealed archive is recorded below.


Evidence is sealed outside Git at `/home/epentland/ai/canopy/evidence/lox-parity-20261003/integration`. Its **6,162 payloads**
include all raw samples/profiles, correctness and gate logs, exact source/inputs,
measured and validation guests, frozen compilers, complete compiler/Guardian
source archives, independent reviews and rejected variants. Twenty referenced
runtime objects are included by digest; no referenced runtime path is missing.
The preceding October 2 baseline link/qualification archive remains separately
sealed and is identified in the index.

`MANIFEST.sha256` is
`3d217a3ead06112b522d608bc384d2a3a64e91907587a375460bbb76c52db31f`. Every payload was rehashed after sealing. This archive
excludes later VM/table/positive-write experiments; those need their own
qualification and measurement.
