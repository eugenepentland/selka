# Lox evaluator improvements, 2026-10-02

This historical recipe describes `fd86729e`. Run its build commands in a
checkout at that revision to reproduce the 72-test source exactly. The latest
optimized migration also includes the subsequent
[October 3 checkpoint](../lox-parity-20261003/README.md).

Three parallel source lanes improve the checked Lox evaluator built by the
unchanged audited main compiler. The integrated source is reconstructed by
`docs/audits/d9-stage3d-migrations/apply-lox.sh WORK --optimized`; that entry
now applies `lox-runtime-perf-20261002.patch` after the existing migrations.
The unoptimized value migration is unchanged.

The lanes preserve language checking, snapshot semantics, the Lox collector,
benchmark sizes and expected output:

- `frames.patch` retains each caller's activation data across child calls.
- `stack.patch` fuses numeric stack updates, retaining normal indexed writes.
- `lookup.patch` returns scalar property/method results and specializes table
  reads, including the corresponding tree interpreter paths.

Each standalone lane patch expects the old optimized source at audit commit
`bbefb77f`. Do not apply it again to the new integrated optimized migration.
The canonical joined patch preserves all seven new tests and four provider
fixtures; the integrated port has 72 public tests.

The compiler source remains main `6df58b02554401f9d37564cceffd14277a835ae1`.
Qualification uses the frozen ReleaseFast compiler from the preceding audit,
SHA-256 `45d05b554849bf3c12553549d9138556ba0204f9d59ba3aaa2ecb2327eb39ac4`.
LLVM guests use O3/full LTO; QBE guests use the same compiler and RC policy.
The benchmark reference/input commit remains `4e48a092`.

The preserved integration workspace is `.tmp-lox-improvements/` in
`codex-lox-perf-improvements-20261002`. Its `binaries.json` records executable
paths and the baseline, individual and joined module hashes. Each completed
measurement receipt embeds that manifest and verifies executable/input hashes
after execution. The raw evidence archive and final measurements are linked
in [the integration report](../../docs/audits/lox-perf-improvements-2026-10-02.md).

Build the integrated evaluator from this branch:

```bash
PERF_WORK=/absolute/path/to/fresh-scratch
COMPILER=/absolute/path/to/current-main-releasefast-mylang
mkdir -p "$PERF_WORK/tmp" "$PERF_WORK/bin"
docs/audits/d9-stage3d-migrations/apply-lox.sh "$PERF_WORK/port" --optimized
TMPDIR="$PERF_WORK/tmp" scripts/build-slot.sh build "$COMPILER" build \
  "$PERF_WORK/port/lox/benchmarks/lox/ports/mylang/main.my" --project \
  --backend llvm --llvm-opt 3 --lto --rc-runtime --keep-symbols \
  --cache-dir "$PERF_WORK/cache-llvm" -o "$PERF_WORK/bin/lox-llvm"
TMPDIR="$PERF_WORK/tmp" scripts/build-slot.sh build "$COMPILER" build \
  "$PERF_WORK/port/lox/benchmarks/lox/ports/mylang/main.my" --project \
  --backend qbe --rc-runtime --keep-symbols \
  --cache-dir "$PERF_WORK/cache-qbe" -o "$PERF_WORK/bin/lox-qbe"
```

The frozen control source is preserved in the audit workspace. A fresh
baseline can also be reconstructed from a separate worktree at `bbefb77f`,
using that revision's `apply-lox.sh --optimized`.

Recheck or compare the preserved integration workspace:

```bash
PERF_WORK="$PWD/.tmp-lox-improvements"
python3 experiments/lox-performance-audit-20261002/audit.py check \
  --work "$PERF_WORK" --out "$PERF_WORK/recheck.json" --tier smoke \
  --rounds 1 --stats --arms baseline-llvm,joined-llvm,baseline-qbe,joined-qbe
python3 experiments/lox-performance-audit-20261002/audit.py time \
  --work "$PERF_WORK" --out "$PERF_WORK/retime.json" --rounds 3 \
  --arms baseline-llvm,joined-llvm,baseline-qbe,joined-qbe
python3 experiments/lox-perf-improvements-20261002/analyze.py \
  "$PERF_WORK/retime.json" --baseline baseline-llvm --candidate joined-llvm \
  --metric wall_s
python3 experiments/lox-perf-improvements-20261002/validate.py \
  --work "$PERF_WORK" --baseline baseline-llvm --candidate joined-llvm \
  --out "$PERF_WORK/regressions-recheck.json"
```

`analyze.py` uses median ratios paired within each round, then geometric means
across scripts. `validate.py` checks independently specified output and exact
baseline observations, including collector statistics, on both engines with
Lox collection stress toggled. Native stress requires separately built GC
artifacts and `--native-gc-stress`; RC artifacts refuse that native option.

Use the build-slot wrapper for builds/tests. Run one measurement command at a
time: counter/RSS commands share a scratch report. Timing CPU 2 and sibling 3,
and counter CPU 10 and sibling 11, remain excluded from builds. Instrumented
ownership sites provide diagnostics; they are not timed performance arms.
