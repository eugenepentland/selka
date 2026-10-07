# S4 exit report — 2026-10-07

**Status.** S4's final source is `a6e07b67` on `claude/s4-p`, and the S4-X bar is
green on it. The new core now builds and tests whole projects: modules and interfaces,
incremental per-module debug builds, whole-program release builds, `mylang-core test`
on projects, and both exit programs (the Lox port and the EDA Stage 1 slice) at 100%
coverage with every test passing. Nothing was pushed or merged into `main`. The old
core stays the default compiler. S4 stops here for the user's go/stop on S5.

**Exit, against the old core.** Every build and test time of both programs is at or
below the old core's except one: the Lox port's fully cold build, with a fresh Zig cache
and a fresh mylang store, takes 8.11 s against 7.66 s (1.06×). Nearly all of it is
one-time machine setup (see *Remaining limits*); a new project on a machine that has
built before takes 0.95 s. Every §6 dev-loop target is met, every `tests/lang` file is at
0 mismatches except the retired arena tests, and the S4-X bar is green.

## Final receipts

| Check | Result | Evidence |
|---|---|---|
| Core tests (64 shards) | **405/405** in 33.5 s on `a6e07b67`; longest shard 15.7 s | `x-merge-03/test-core.log` |
| Conformance with leak and fact verification | Debug and release each **1518 match, 0 mismatch, 0 unsupported**, 77 s, on `a6e07b67` | `x-merge-03/full-conformance.log` |
| Full old-core gate | `test` (869 s), `test-qbe` (76 s), `test-qbe-build` (4.6 s) and `fmt-check` green on `af0bf538`; later commits touch only `src/core/` and `SPEC.md`, and Guardian's whole-tree run passed on each | `x-old-gate-01/` |
| Strict 9 kinds × 200 fuzz matrix | **1,800 sources accepted, 25,800 native comparisons, 0 mismatches**, 0 refused, 0 build failures; old core against new debug, release and verify builds (stdout, status, traps, leaks, facts) on `af0bf538` | `x-matrix-01/matrix.json` |
| All 46 rows, CPU 10, 7 rounds | **92/92 cells within 1.10× the old core and within 1.10× Zig ReleaseSafe.** Worst against the old core: `packet_decode`/64 at 1.047. Worst against Zig: `int_parse`/64 at 1.090. Geometric means: 0.35× the old core, 0.39× Zig. | `x-all46-01.json`, [`rows.md`](rows.md) |
| Coverage, six corpora | `tests/lang` 3168/3168, Lox port 462/462, EDA Stage 1 1756/1756, `bench/parity` 123/123, runtime benchmarks 140/141, examples 202/207. The 6 not accepted are bodyless `extern` and Host declarations, as in S3. | `x-coverage-01/summary.json` |
| Exclusions | **118 retired arena tests** only. S3's 9 S4 exclusions (`migrated/propagation`, user modules) now run and pass 9/9 in both modes inside the 1518. | `x-exclusions-01.json` |
| `--verify-cache` over both ports | Lox 19 debug units and 1 release unit, EDA 66 debug units and 1 release unit: every reused object byte-identical to a fresh compile | `x-verify-cache-01.txt` |
| Lox and EDA test suites | Lox 65 directory tests and 13 driver-case tests; EDA 310 tests and 34/34 byte-identical golden outputs, debug and release | `x-ports-03.log`, `experiments/new-core-s4-eda-newcore-20261007/` |

## Build and test times against the old core

The old core's baselines and protocols are S4-L's and S4-D's (plan §4): CPU 10, one test
worker, the Lox protocol with fresh caches including Zig's, EDA with a fresh store.
New-core numbers are from a ReleaseFast build of `a6e07b67` on a quiet machine
(`x-ports-03.json`, script `measure_ports.py`). Lox tests are the directory run plus the
driver-case run, as in the baselines.

| Program | Measure | Old core | New core | New / old |
|---|---|---:|---:|---:|
| Lox port | build cold | 7.66 s | 8.11 s | **1.06** |
| | build unchanged | 0.0068 s | 0.0021 s | 0.30 |
| | build after a one-function edit | 0.195 s | 0.143 s | 0.73 |
| | tests cold | 22.0 s | 4.58 s | 0.21 |
| | tests unchanged | 0.145 s | 0.063 s | 0.43 |
| | tests after the edit | 0.648 s | 0.643 s | 0.99 |
| EDA Stage 1 | build cold | 81.1 s | 7.29 s | 0.09 |
| | build unchanged | 0.0165 s | 0.0034 s | 0.21 |
| | build after a one-function edit | 1.15 s | 0.66 s | 0.57 |
| | tests cold | 234.5 s | 26.4 s | 0.11 |
| | tests unchanged | 1.65 s | 0.345 s | 0.21 |
| | tests after the edit | 1.67 s | 0.576 s | 0.35 |

**Before S4-X's fixes** (`af0bf538`, `x-ports-01.json`) the Lox port missed three cells:
a cold build of 22.1 s, and tests after the edit at 3.22 s (directory 1.72 s, driver
cases 1.51 s). S4-X's three changes (below) brought them to 8.11 s and 0.643 s; EDA's cold
build went from 20.4 s to 7.29 s with them.

## Dev-loop targets (§6)

| Measure | Target | Result | Evidence |
|---|---|---|---|
| Debug rebuild after a one-function edit, 48k lines | ≤ 2 s | **0.96 s** (one unit recompiled, 2 processes) | S4-C lane, `experiments/new-core-s4-c-20261007/debug-48k.json` |
| Unchanged rebuild, any size, debug or release | no `zig cc` process | **0 processes**: 5 ms at 48k and 13 ms at 192k (debug), 4 ms and 10 ms (release); Lox 2 ms, EDA 3 ms | same directory; `x-ports-03.json` |
| Check after a one-function edit, 96k lines | ≤ 0.45 s | **0.221 s** (median of 3 edits; cold 0.61 s), CPU 10 | `x-check-01.json`, `measure_check.py` |
| Release rebuild after a one-function edit, 48k lines | reported | 67.6 s: whole-program `-O3` under S4-1a | `release-48k.json` |
| Cold release build, 192k lines | reported | 275 s, one unit | `release-192k.json` |

Cold debug builds, for reference: 1.71 s at 48k lines and 6.7 s at 192k on the build
CPUs.

## What S4-X changed

S4-X found three things slowing the edit loop and fixed them (`d89bc16f`, `a6e07b67`):

1. **A cached test still emitted LLVM.** To look up a test's receipt, the runner built
   the test's program and rendered every unit's LLVM text only to hash it. The Lox
   driver tests spent 1.5–1.9 s finding 13 receipts cached. The key now hashes the
   test's Core IR before passes, with every span resolved to the file, line and column
   emission reads (`NEW-CORE-S4-TEST-6`). Passes and emission are pure functions of
   those, so the key covers what it did, and an edit that only moves code in other
   files keeps it. The IR `classify` already builds is reused rather than built twice.
2. **Receipts hashed the whole environment.** A shell's `_` or `OLDPWD`, or running
   tests under `time`, reran every test. Receipts now key only the variables that can
   change an outcome, as the old core does (`NEW-CORE-S4-TEST-5`). Tests receive only
   `Stream` parameters, so they cannot read the environment.
3. **A debug link built Zig's UBSan runtime.** `zig cc -O0` links it by default; with a
   fresh Zig cache that cost about 10 s (a cold link went from 13.7 s to 3.9 s). Core
   units are LLVM text and the runtime is built at `-O2`, so nothing calls it. Debug
   links without `--link` C sources now pass `-fno-sanitize=undefined`
   (`NEW-CORE-S4-LINK-1`); release links and `--link` builds are unchanged.

Earlier in S4-X: release builds became one whole-program unit (S4-1a, `b35eb846`), the
runtime objects moved to a per-user store, the toolchain identity stopped rescanning
every library file (`d6d3318c`), and `test-core` went from 615 s to 34 s.

## Remaining limits

1. **Lox's fully cold build is 1.06× the old core (8.11 s against 7.66 s).** On CPU 10:
   - about 3.2 s is Zig building glibc 2.31 stubs and compiler-rt in a fresh Zig cache,
     once per machine and toolchain;
   - about 3.9 s is the core runtime object (one 6k-line C file at `-O2`) and the number
     tool, once per user;
   - the project itself takes 0.95 s (19 units, front end, link).

   Splitting the runtime into separately compiled files would not help this protocol,
   which runs on one CPU. Making the runtime cheaper to compile is the lever if this
   cell must pass.
2. **Driver-case tests after an edit: 0.245 s against the old core's 0.040 s.** The Lox
   tests column still passes because the directory run is faster (0.397 s against
   0.608 s). A cached test's key still needs that test's lowered IR; the old core keys
   tests on the checker's function fingerprints and skips lowering. Keying receipts on
   check-level fingerprints is the follow-up. The file manifest also cannot replay when a
   module that a provider replaces changes, because the original module is still checked
   for provider compatibility.
3. **A release rebuild after an edit recompiles the whole program** (67.6 s at 48k
   lines), as decided for S4-1a. Debug builds are the edit loop.
4. **Which runs cover which commit.** The full old gate, the fuzz matrix, the 46 rows
   and coverage ran on `af0bf538`. The two S4-X commits change only test-receipt keys and
   the debug link flag, inside `src/core/` and `SPEC.md`. Core tests and full conformance,
   with leak and verify, ran again on `a6e07b67`, and Guardian's whole-tree run passed on
   each commit.
5. **Capabilities in collections:** `[N]Stream` arrays and lists of capabilities are
   still refused. Record fields and payloads work.
6. **`/tmp` quota:** test processes use the C runtime's `tmpfile()`. When the per-user
   `/tmp` quota is full they exit 70, and builds fail with `WriteFailed`. Keep `TMPDIR`
   and caches on disk.

## Package commits (`claude/s4-p`, first parent)

| Package | Commit |
|---|---|
| S4-0 design and plan; S4-R runtime contracts, all 46 rows registered | `d449c8f5`, `d357bbda`, `25803a39` |
| S4-V values, S4-E per-module emission, S4-F front end (Codex Wave A, reconciled) | `3d61a840`, `dfcc38c2`, `e8611a9c` |
| S4-M project tests (Codex Wave A) | `0dc47196` |
| S4-1a release = one unit; per-user runtime store | `b35eb846` |
| Toolchain identity by library root | `d6d3318c` |
| S4-P: capability record fields, typed stream writes, per-block test steps, provider check | `c933cad1`, `73f19884`, `4deb09ef` |
| S4-C unit and program stores, replay, `--verify-cache` (agent lane) | `f56c0f7f` |
| S4-P EDA lane: assert messages, `--max-frames`/`--max-memory`, `mut` field take-over (agent lane) | `af0bf538` |
| S4-X dev-loop fixes | `d89bc16f`, `a6e07b67` |
| S4-L Lox port on value semantics | `codex/s4-lox-value-semantics` `f44302d8` |
| S4-D EDA Stage 1 port | eda-bench `claude/s4-eda-newcore` `7e938b6` |
