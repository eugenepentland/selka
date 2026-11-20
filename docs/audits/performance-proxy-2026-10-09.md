# Performance proxy implementation — 2026-10-09

Branch: `codex/performance-proxy`, based on completed P1 `a79413c3f`.
The approved design is now integrated into the compiler as `mylang juice`.
The original `scripts/juice` remains a developer reference; usage and measurement contracts are in
[the tool guide](../tooling/juice.md).

Status: implemented and qualified. Nothing was pushed or merged into main.

## Delivered behavior

- Generic native builds and a mylang adapter, with immutable baseline/candidate
  captures, content-keyed build reuse, matching executable/input/output paths,
  explicit completed-work units and correctness oracles.
- `perf` user instruction counting with explicit hybrid-CPU PMU selection;
  Callgrind and Cachegrind reference collectors, self-cost attribution and
  selected-function regions. Counter validity and repeat spread are checked.
- Source/function explanations from mylang semantic counters, native profiles
  and static code inventories. Changed hook contracts suppress semantic deltas;
  unavailable requested allocation bytes are not inferred from usable sizes.
- Static-only analysis with optional previous-analysis differences; no
  application execution, PMU dependency or invented static juice score.
- Quick/larger scenario validation and optional held-out calibration. No
  production runtime model is claimed validated. The default index is work,
  not elapsed time or concurrency speedup.
- A CLI, documented TOML contract, native/mylang examples, regression-gate
  option, test target and affected-test integration.

## Initial standalone qualification

All **15 real-collector qualification checks passed**. Baseline is 100; numbers
below are instruction-work indices, rounded to three decimals.

| Controlled change | Quick | Larger | Interpretation |
|---|---:|---:|---|
| Identical native build | 100.000 | 100.000 | Stable control |
| Identical native build, two competing processes on the same CPU | 100.000 | 100.000 | Other CPU work does not enter the task's count |
| Replace naive bit counting with builtin implementation | 14.450 | 14.339 | Application improvement detected |
| Disable backend optimization (`-O2` to `-O0`) | 145.527 | 145.567 | Backend regression detected |
| Add redundant copies | 224.192 | 225.319 | Additional runtime work detected |
| Add atomic updates | 102.884 | 102.912 | Instruction increase and atomic-event increase both reported |
| Remove unnecessary mylang list materialization | 84.327 | 83.728 | Improvement with allocation/site explanations |
| Pre-P1 compiler to P1 compiler, same mylang source | 100.622 | 100.075 | Backend work measured; counter contract and link changes flagged |

Disabling vectorization on a separate reduction fixture produced **212.034**.
The software-counting repeated-build control was also unchanged. Region
collection, native source attribution and both native/mylang quick-versus-larger
agreement checks passed. The first, smaller native scenario was correctly
rejected: its improvement ratio disagreed with the larger case by 5.4% because
startup dominated the faster short case. Increasing repetitions with the same
data shape brought the proxy within the configured 3% agreement tolerance.

The final captures took **0.23–4.60 seconds each**, including guest compilation
when needed and repeated collection, using already-built compilers. Those are
development-loop observations on this shared host, excluding build-slot wait
and compiler construction. They are not guaranteed budgets for arbitrary apps.

These small P1 examples do not re-certify the original P1 corpus or replace its
elapsed-time waiver. They demonstrate the backend sensitivity missing from the
old allocation/copy proxy, including an explicit counter-semantics boundary.

Retained evidence:

- [Qualification checks and capture durations](../../experiments/performance-proxy-2026-10-09/qualification.json).
- [Full comparison reports](../../experiments/performance-proxy-2026-10-09/reports/).
- [Rejected initial short scenario](../../experiments/performance-proxy-2026-10-09/initial-short-scenario-rejected.json).
- [371 archived capture/raw-profile/fixture files](../../experiments/performance-proxy-2026-10-09/captures.tar.xz),
  62,412 bytes; each archived member was checked against its original bytes.
- [Evidence hashes and implementation identities](../../experiments/performance-proxy-2026-10-09/manifest.json).
- [Implementation decisions](../../experiments/performance-proxy-2026-10-09/DECISIONS.md).

To review an archived comparison, extract `captures.tar.xz` into a scratch
directory and pass the corresponding `cache/<project>/records/<label>/record.json`
paths to `mylang juice compare`. Raw evidence hashes are checked again. Absolute
execution paths inside records describe the original measurement context; they
need not exist to inspect the records.

## Initial repository verification

- 38 proxy integrity/calibration/runner tests; 13 affected-selection tests.
- Full `zig build test --summary all` passed: 90/90 build steps. The initial
  cold gate executed 2,144 Zig tests; sharding accounts for its skipped count.
- All 88 Guardian checks passed in the repository's configured diff scope.
- `zig build fmt-check`, input-coverage checks and `git diff --check` passed.
- Native `perf`, Callgrind 3.26 and Cachegrind 3.26 exercised end to end. The
  mylang runs used frozen P1 `c26c95de7` and pre-P1 main `35df839be` compilers.

The initial standalone implementation changed no compiler/front-end/Core IR/runtime source. Full gate logs and the
qualification command output are retained with the evidence package.

One intervening recheck failed when the shared workspace filesystem filled
(`No space left on device` from native compilation). Generated caches from the
completed P1 task were reclaimed and this gate's TMPDIR moved to the home
filesystem. The subsequent full gate passed; the failed log is retained as
`final-full.log.xz`, and the successful recovery as `recovered-full.log.xz`.
The required Guardian feedback was committed separately as `43de8e9`.

## Limits

The tool cannot infer representative late phases automatically; applications
with expensive setup need a saved-input harness. Collection is pinned to one
CPU and workload commands must complete their work before exiting. Instruction
counts do not measure waiting, contention, parallel latency or cache stalls.
Mylang semantic counters are before LLVM optimization, and source metadata can
be incomplete. The software collectors can reject unsupported machine code.

Calibration machinery is tested, including disjoint holdouts and abstention,
but the synthetic fitter tests are not runtime prediction evidence. Real time
estimates require independent, matched, sufficiently stable timing evidence and
remain scoped to the validated workload families and measurement context.

## Native compiler integration

All six commands (`doctor`, `analyze`, `record`, `compare`, `validate`, `calibrate`)
now execute native Zig code inside the installed compiler. Help advertises the
command. No Python interpreter, checkout, or companion script is used at runtime.
The mylang adapter defaults to the running compiler and retains the explicit
`--compiler` override for backend comparisons. Existing source/IR/runtime
semantics were not changed.

Host process/collector/inventory services are separate from the shared contract,
profile, comparison and calibration modules. The
[portability design](../tooling/juice-portability.md) covers future Linux ARM64,
macOS and Windows adapters, a separate LLVM instrumentation work domain and
per-target baselines. Those adapters are deliberately future work.

Native acceptance evidence:

- The final full gate passed **91/91 steps**, with **2,150 Zig tests executed**
  (19,874 shard skips). All 88 Guardian checks and `fmt-check` passed.
- Six native Zig tests cover invalid counts, compressed profiles, normalization,
  contracts, process deadlines, immutable failure records and independent SHA-256
  vectors across streaming-buffer boundaries. Eleven native CLI tests cover
  installation relocation with an empty `PATH`, reporting/calibration parity,
  cache invalidation, artifact hashes, output checks and incomplete captures.
  The original 38 Python reference tests remain in the full gate.
- **11 existing qualification comparisons** were replayed through native Juice,
  reusing their archived evidence. Instruction ratios, repeat envelopes,
  directions, assessments and available semantic totals matched. The original
  broad performance corpus was not rerun.
- **Seven native collector checks passed**: perf repeated-build control, an
  application improvement, Callgrind, Cachegrind, mylang semantic counters,
  static cost and default self-compiler selection. Native instruction indices
  were **100.000** for the unchanged control, **14.450** for bit-counting improvement
  and **84.327** for removing mylang list materialization. No timing model was fitted.
- Native smoke captures ran while the full gate used this shared machine.
  Observed capture durations were **0.51–3.49 seconds**, except the first mylang
  capture/build/static analysis at **20.59 seconds**. Its edited candidate took
  **2.53 seconds**. These include setup/builds and two samples, exclude the outer
  build-slot wait, and are diagnostic observations rather than runtime predictions.

The port's verification caught and fixed procfs zero-length reads, final partial
SHA-256 buffers, and Cachegrind's literal `(below main)` function name. Build keys
use the compiler's existing embedded source/toolchain/optimization identity to
avoid repeatedly hashing the large Debug host. External compiler and evidence
artifacts retain executable/file SHA-256 identities. Native identity serialization
and supported TOML/normalization forms are explicit in the tool guide; unsupported
forms fail instead of silently changing a contract.

The [native evidence directory](../../experiments/performance-proxy-2026-10-09/native/)
contains independent artifact hashes, archived raw profiles/captures, comparison
reports, the reproducible smoke driver and compressed final gate logs. Build and
guest caches were moved only for this worktree to the home filesystem after the
workspace disk again ran low. The source branch remains `codex/performance-proxy`;
main was not merged or modified, and nothing was pushed.
