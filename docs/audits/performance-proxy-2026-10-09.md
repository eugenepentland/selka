# Performance proxy implementation — 2026-10-09

Branch: `codex/performance-proxy`, based on completed P1 `a79413c3f`.
The approved design is implemented as the standalone developer command
`python3 scripts/juice`; usage and measurement contracts are in
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

## Evidence

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
paths to `scripts/juice compare`. Raw evidence hashes are checked again. Absolute
execution paths inside records describe the original measurement context; they
need not exist to inspect the records.

## Repository verification

- 38 proxy integrity/calibration/runner tests; 13 affected-selection tests.
- Full `zig build test --summary all` passed: 90/90 build steps. The initial
  cold gate executed 2,144 Zig tests; sharding accounts for its skipped count.
- All 88 Guardian checks passed in the repository's configured diff scope.
- `zig build fmt-check`, input-coverage checks and `git diff --check` passed.
- Native `perf`, Callgrind 3.26 and Cachegrind 3.26 exercised end to end. The
  mylang runs used frozen P1 `c26c95de7` and pre-P1 main `35df839be` compilers.

No compiler/front-end/Core IR/runtime source was changed. Full gate logs and the
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
