# Lox callee/table checkpoint, 2026-10-03

This is a historical checkpoint. The selected AST source and completed repeated
results are in [the newer report](lox-ast-carrier-checkpoint-2026-10-03.md).

The next parallel source changes reduce VM wall time **3.41% on LLVM and
3.03% on QBE** relative to the accepted 80-test checkpoint at `6e516f65`.
Tree changes are small: **0.33% / 0.85%**. LLVM still takes approximately
**2.69× Rust/Go on the VM and 4.24× / 4.12× on the tree**. Parity remains unmet.
These are incremental matched comparisons; do not add them to earlier gains.

The implementation remains on `codex/lox-parity-20261003`. Main remains
`6df58b02554401f9d37564cceffd14277a835ae1`; the original dirty integration
checkout is preserved. The earlier branch audit found no pending older Lox
runtime improvement to merge. This branch now contains the qualified source
and prior checked compiler improvements, with unrelated experiments isolated.

## Selected source

The VM classifies callees into plain descriptors before handlers mutate the
Runtime. It preserves receiver/callee publication, initializer/arity ordering,
frame roots and argument retirement. The managed Obj loan in call_value drops
from one to zero; SSA across caller/helper falls from 2,052 to 1,429.

Six production table lookups pass readonly entries/count directly. The new
get_entries body preserves the exact probe loop, count guard, hashes,
tombstones, nil values and checked expressions. The original public get and
mutators remain intact. Original get already had no RC glue; the measured gain
comes from source/ABI shaping, not removing a previously owning table loan.
The whole static read function shrinks from 104 to 72 decoded LLVM instructions
and 196 to 186 QBE instructions, including non-loop error paths.

The canonical optimized migration applies
`lox-runtime-perf-20261003-callee-table.patch` after the earlier patches.
SHA256: `1e75f5164ab1385832145f50aee1c5e11d07dc8a6902747f386e88770445a7db`.
Zero-fuzz replay matches all **37 files**, including 26 modules and **84 public
tests**. Four meaningful regressions cover callee snapshots/error ordering and
aliased table entries across overwrite/delete/growth/collision/nil cases.
The pinned Lox architecture, opcodes, algorithms, roots, GC thresholds and
value/snapshot rules remain the contract. Native helper frame boundaries,
source trap locations and instruction-step consumption can change with source
shaping; the bounded Lox output/error/frame-limit behavior is qualified.

## Matched performance

Each final matrix has **468 observations**: 13 scripts × two engines × six
arms × three rounds. Wall runs use original engine-specific sizes on CPU 2;
counters use calibrated tree sizes on CPU 10. Both matrices verify guest and
input hashes afterward. All 1,872 recorded PMU running rates are 100%.
Ratios are within-round candidate/control medians, followed by geometric
means across the thirteen cases. Positive percentages mean reductions.

| Engine | LLVM wall reduction | QBE wall reduction | LLVM instruction reduction | QBE instruction reduction |
|---|---:|---:|---:|---:|
| vm | 3.41% | 3.03% | 1.91% | 1.85% |
| tree | 0.33% | 0.85% | 0.21% | 0.42% |

| Engine | LLVM/Rust | LLVM/Go | QBE/Rust | QBE/Go |
|---|---:|---:|---:|---:|
| vm | 2.693× | 2.698× | 5.340× | 5.371× |
| tree | 4.237× | 4.120× | 7.623× | 7.413× |

| Script | LLVM VM reduction | QBE VM reduction | LLVM tree reduction | QBE tree reduction |
|---|---:|---:|---:|---:|
| binary_trees | 3.35% | 2.03% | 0.00% | 0.98% |
| closures | 5.06% | 1.91% | -0.49% | 0.78% |
| equality | 0.47% | 0.64% | -0.30% | 0.69% |
| fib | 9.80% | 5.49% | -0.33% | 0.97% |
| instantiation | 2.91% | 4.74% | -0.45% | 2.06% |
| invocation | 2.63% | 4.21% | 0.52% | 0.58% |
| method_call | 3.42% | 2.03% | 1.14% | 0.64% |
| properties | 3.40% | 3.28% | 1.43% | -0.10% |
| string_equality | -0.20% | 1.30% | -0.65% | 0.20% |
| strings | 0.05% | 1.58% | 0.75% | 1.81% |
| trees | 5.86% | 4.95% | 0.02% | 0.70% |
| zoo | 3.48% | 3.44% | 1.42% | 1.04% |
| zoo_batch | 3.62% | 3.62% | 1.18% | 0.77% |

Median paired-ratio spreads are 1.30% LLVM VM, 0.90% LLVM tree, 0.53% QBE VM
and 0.83% QBE tree. Individual spreads reach 16.81% for LLVM VM binary_trees
and 12.66% for LLVM tree zoo. Small tree changes and the 0.20% LLVM VM
string-equality increase do not establish a narrow confidence interval.
Three rounds are a focused Lox evaluation, not the full 43-program compiler
performance gate. The wall series is separate from perf counter wall time.

## Qualification and review

The combined source passes **336 fresh public tests** (84 × QBE/LLVM ×
RC/stressed native GC), with no failed, cached, skipped or missing tests.
It also matches **1,168 complete status/stdout/stderr/Lox-stat observations**:
416 RC, 416 ordinary GC and 336 native GC stress. All sixteen focused programs
and twenty-three historical errors per engine are covered. Eight RC native
stress refusal pairs match status 2; these are refusals, not program passes.
Eighty native-stress benchmark smoke cells are explicitly unrun.

Independent VM, table, composition and measurement reviews find no actionable
issue within the stated scope. All 37 source files, test providers, executable,
compiler/QBE/runtime identities and stored paired calculations are verified.
The public/matrix observations and commands are tracked under
`experiments/lox-vm-callee-20261003`; lane-specific evidence remains separate.

Measurement receipts check complete stdout against the pinned expected bytes
and save its hash. Their historical shared runner saves decoded stderr's last
1,500 characters; full behavior streams are preserved in the separate bounded
qualification matrix. Empty or stats diagnostics are checked in the retained
measurement rows; the measurements do not claim a full raw stderr archive.

## Compiler and next experiments

An independently reviewed positive-write compiler candidate has 26 guarded
sites across fifteen source functions. It preserves original RHS/write/bounds,
COW/root/cleanup code and the negative-index fallback. It passes 3,000 reported
compiler tests, 28 focused proof/lifetime tests and native snapshot/trap tests.
Its exact source84 RC ELFs also pass 416 behavior comparisons; separate GC
ELF cells are explicitly unrun. The one-round screen shows no LLVM instruction
reduction and only 0.22% / 0.26% on QBE. The separate three-round compiler-only
timing matrix has 312 complete observations. LLVM VM/tree increase 0.50% / 0.66%;
QBE VM decreases 0.38% while tree increases 0.94%. Median paired spreads are
6.04% / 11.04% for LLVM and 6.47% / 7.01% for QBE, so this does not establish a
small regression or improvement precisely. It supplies no convincing runtime
win. Candidate `33159179` remains isolated; the canonical compiler retains
the previously accepted changes.

Static follow-up rules out missing LLVM jump-table dispatch and an opaque
runtime LTO barrier. Ordinary uniqueness guards are already inlined. Narrow
checked constant-reader and immutable AST carrier experiments remain separate
from this measured checkpoint until they pass qualification and timing.

## Reproduction

The [fresh-build recipe](../../experiments/lox-callee-table-checkpoint-20261003/README.md)
selects the compiler explicitly, reconstructs both exact sources, and builds
pinned Rust/Go references. It avoids the historical harness's September compiler
default. Rust/Go source and benchmark inputs remain `4e48a09220c2e018eba8c4b1eb3fe1137a3dae73`.
Fresh-build verification reproduces four mylang guests and Rust byte for byte.
Go build metadata varies by workspace; fresh Go is qualified separately and
never replaces the original Go ELF in the reported measurements.

The accepted compiler is `d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040`
with adjacent QBE `99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63`.
The LLVM/QBE selected guests are `a0ec4ffd470b309d70d35cbab69215b778fbdbc2d71d3d8761703da18feca594`
and `2c00b0b84d173010036608940e06a61206f535662284eac02eb289d9dee470d6`.
Exact source maps, all ratios and receipt hashes are in
`experiments/lox-callee-table-checkpoint-20261003/checkpoint.json`.

The whole-tree integration Guardian gate passes 88 checks with no waivers or
accepted snapshots. Python/shell syntax and ordinary/added-source whitespace
checks pass. Guardian feedback is committed separately in the gate's repo.
Feedback commits are `3549ecd` and `511b078` in `guardian-zig`.

The sealed evidence is
`/home/epentland/ai/canopy/evidence/lox-parity-20261003/callee-table`:
3,471 verified payloads, 33 runtime objects, no missing runtime paths.
`MANIFEST.sha256` is `94d85a11474d68c281d6b0e9010046ed5ebc8dd7ded019d43761b5d7c63b7272`.
It records the selected tree at `44cd4307`; subsequent closeout documentation
does not mutate this archive. Later AST/constant experiments are excluded.
