# Reusing transformed optimizer checkpoints

This experiment extends the demand-loaded compiler in
[`../demand-artifacts-20261009`](../demand-artifacts-20261009/README.md).
It measures small edits in optimized-debug builds. Runtime C optimization remains
O2; no guest release builds are included.

## What changed

Unchanged functions can now retain optimizer artifact handles even when inlining
or loop unswitching changed their bodies. The index records the exact outputs of
leaf inlining, CFG inlining, unswitching and parameter-dependent inlining. An
edited caller requests the checkpoint it would see at that point in the ordinary
physical pass order. A no-op checkpoint aliases its predecessor, and callee key
construction uses saved body identities and portable inline ancestry without
loading instructions merely to hash them.

Changed callees still invalidate their raw dependency closure. Changed incoming
argument bounds restore the affected function's pre-parameter checkpoint and
earlier pass counts. Functions changed by fusion remain eager. Missing or malformed
checkpoints take the existing one-shot eager recovery path. Cached and fresh
Core IR, LLVM, facts, ownership, vector plans, pass statistics and debugger
ancestry are checked against each other.

Frontend summary admission memoizes repeated record-shape combinations while
still checking each body's own expected digest. Summary consistency checking and
publication share one declaration-position mapping; unchanged callee lists can
borrow the immutable previous table. Stage decoding reads a verified record
directly without first copying its entire payload, and raw IR is restored once
instead of twice.

`stage-report-v3` distinguishes raw body materializations, final body loads and
intermediate checkpoint records decoded. The latter includes no-op aliases and
can exceed the number of physical bodies restored. `optimizer.restores.final`
replaces `optimizer.final_restores`; `optimizer.restores.checkpoints` is new.
Opt-in `nanoseconds.frontend_phases` reports frontend subphases. Inclusive parent
intervals must not be added to their children.

## Measurement method

The initial comparison uses the existing
[`compare.py`](../demand-artifacts-20261009/compare.py) harness; the continued warm
series uses this directory's [`compare.py`](compare.py) with `--resume`. Both use
the immediately preceding demand-loaded compiler as baseline. The reachable EDA fixtures contain
191,416 and 510,436 physical source lines. Both compilers see the same paths and
the same length-changing edits, with separate caches and alternating order.
Every build executes every replica and checks EDA export golden hashes and
leaks. Paired native objects and allocated executable sections are also compared.

Both compiler executables use ReleaseFast. Guest compilation uses optimized
debug with four workers, pinned to reserved CPUs 2,3,10,11 and holding the
shared timing-CPU lock. Other jobs stay on the nonreserved CPUs. The initial series
overlaps our single-worker full suite; the continued warm series follows suite
completion. Independent shared-host jobs can still run. Initial setup populates
fresh frontend and stage caches using previously validated native objects; it
is not a completely cold native build and is excluded from edit medians. GNU
time's peak RSS is the largest individual process's high-water mark, not the
simultaneous sum of worker memory. Measurements on this shared host and replicated
fixture are evidence for these workloads, not a bound for arbitrary codebases.

[`summarize.py`](summarize.py) accepts plain or gzipped harness results and keeps
raw, checkpoint, final and native work separate.

## Incremental build time

The continued warm series uses three additional distinct edits per case after
the full test suite finishes. Medians are full CLI wall time in seconds; RAM is
the candidate's median peak RSS. Baseline here means the immediately preceding
demand-loaded compiler, not the original compiler before the earlier speedups.

| Physical lines | Edit | Previous | New | Time reduction | New peak RSS |
|---:|---|---:|---:|---:|---:|
| 191,416 | Entry | 3.651 s | 2.914 s | 20.2% | 0.500 GiB |
| 191,416 | Helper | 2.859 s | 2.070 s | 27.6% | 0.503 GiB |
| 191,416 | Three files | 4.039 s | 3.160 s | 21.8% | 0.503 GiB |
| 510,436 | Entry | 9.356 s | 6.888 s | 26.4% | 1.312 GiB |
| 510,436 | Helper | 9.115 s | 6.675 s | 26.8% | 1.317 GiB |
| 510,436 | Three files | 10.777 s | 7.809 s | 27.5% | 1.317 GiB |

The candidate's slowest 510k edit is **10.095 s** in this warm continuation and
**11.537 s** in the initial series: all measured edits are below 15 seconds.
These results demonstrate another roughly one-quarter reduction in total build
time. They do not demonstrate another halving of either total time or RAM.

The initial series, which overlaps the full suite, is retained separately:

| Physical lines | Edit | Previous median | New median |
|---:|---|---:|---:|
| 191,416 | Entry | 5.851 s | 4.380 s |
| 191,416 | Helper | 3.111 s | 2.367 s |
| 191,416 | Three files | 4.160 s | 3.384 s |
| 510,436 | Entry | 17.216 s | 11.353 s |
| 510,436 | Helper | 12.228 s | 7.961 s |
| 510,436 | Three files | 11.703 s | 10.067 s |

For the continued 510k helper case, candidate stage medians are **3.602 s
frontend**, **0.436 s lowering**, **1.899 s optimizer**, **0.236 s emission** and
**0.340 s native**. Medians of separate stages need not sum to the median wall
time; native time includes the linker interval. This identifies the frontend as
the largest remaining phase after the optimizer savings.

## Work counts

These are bodies actually materialized from raw/final IR artifacts, not the
number freshly lowered or freshly optimized. Each cell is the count for **each**
of raw and final bodies; the two counters are equal in these runs.

| Physical lines | Edit | Previous raw / final bodies | New raw / final bodies | Reduction |
|---:|---|---:|---:|---:|
| 191,416 | Entry | 2,600 | 628 | 75.8% |
| 191,416 | Helper | 2,732 | 807 | 70.5% |
| 191,416 | Three files | 2,869 | 991 | 65.5% |
| 510,436 | Entry | 6,920 | 1,668 | 75.9% |
| 510,436 | Helper | 7,052 | 1,847 | 73.8% |
| 510,436 | Three files | 7,189 | 2,031 | 71.7% |

Fresh lowering, fresh optimizer work, full LLVM key construction and native
compilation remain **1 / 1 / 3** for the three edit types. Intermediate checkpoint
decodes are **zero** in these EDA edits: the avoided raw/final loads have not
simply moved to another artifact counter. Dirty callers that actually inspect a
transformed callee do decode checkpoints; targeted tests and the separate CLI
checkpoint-loss experiment exercise that path. Ordinary paired builds have no
eager recovery fallbacks.

## Validation

`zig build test fmt-check -j1 --summary all` passes all **93 build steps** and
**2,300 executed tests**. The 21,231 reported skips are cases not selected by the
individual shards. All 28 Guardian test-runner records report zero failures.
The full static Guardian gate passes **88 checks**, with no policy or baseline
changes.

Focused optimizer tests compare cached and fresh Core IR, LLVM, facts, ownership,
vector plans, pass counts and canonical debugger ancestry. They cover both
physical caller orders, verified/trusted IR, dirty callees and callers, changed
incoming parameter bounds, no-op aliases, deleted checkpoint artifacts and
checksum-valid corrupted provenance. Frontend tests cover changed record shapes
and declaration-order remapping. Stage-store tests cover corrupt and truncated
records.

[`checkpoint_recovery.py`](checkpoint_recovery.py) deletes a real transformed
callee checkpoint between builds. The next edited CLI build falls back once,
repairs its cache, executes correctly and produces the same complete executable
as a fresh build. A further edit reuses the repaired cache without fallback and
again matches a fresh build. The older raw/final/LLVM loss experiment also passes:
cached native objects work without LLVM artifacts, and native eviction triggers
one successful eager repair.

## Remaining work and tradeoffs

Functions changed by fusion still take the eager path. Extending checkpoint
reuse to them requires preserving fusion's catalog changes as well as its body
outputs. Recursive dependency groups and real changed-body dependency closures
also remain conservative. These are opportunities to reduce body loads further;
the counters do not imply those thousands of functions are newly compiled.

Frontend checking and replay now account for the largest portion of the helper
edit. New profiling separates loading, syntax replay, dependency-key preparation,
body replay/checking, effect propagation and summary publication. Summary
publication itself is under 1% in the inspected 191k helper profile. A substantial
remaining frontend source of fresh checking is rejected relocation of external
or default-value source spans. Reusing those safely needs stable external source
identities and dependency guards, rather than relaxing cache admission.

The added checkpoint histories also cost memory and initial cache population
time. Peak incremental RSS is essentially unchanged: approximately **0.50 GiB**
at 191k lines and **1.32 GiB** at 510k. In the initial 510k setup, elapsed time is
**88.98 s previous / 93.09 s new**, and peak RSS is **4.78 / 4.81 GiB**. That setup
has native objects preseeded and is not a fully cold build.

## Cache footprint after one build

The separate [`single_build_cache.py`](single_build_cache.py) experiment starts
each size with empty project, frontend, semantic, stage, executable and native
caches. It makes exactly one optimized-debug build, with no seed and no edits.
The resulting program executes every replica, matches the EDA export goldens
and passes leak checking. The compiler report must show zero lowering/native
reuse and native compilations equal to the total native unit count.

The measurement runs after compilation has removed its temporary LLVM/toolchain
work directory. It counts retained project caches plus runtime/native caches,
including directory blocks. It excludes source, the output executable outside
the executable cache, measurement logs, and the installed compiler/toolchain's
shared support cache. Allocated bytes describe disk usage; logical bytes describe
the contents of files before filesystem block rounding. These disk measurements
use eight requested native workers on nonreserved CPUs and are separate from the
paired incremental timing experiment.

| Physical lines | Allocated disk space | Logical file contents | Files | Native units compiled / reused |
|---:|---:|---:|---:|---:|
| 191,416 | **1.217 GiB** | 0.935 GiB | 89,589 | 760 / 0 |
| 510,436 | **3.234 GiB** | 2.487 GiB | 237,589 | 2,020 / 0 |

Allocated-byte totals independently match GNU `du`. The retained components,
in MiB, are:

| Cache component | 191k lines | 510k lines |
|---|---:|---:|
| Compiler stages: IR, optimizer, LLVM and receipts | 1,030.99 | 2,741.35 |
| Semantic cache | 128.61 | 342.74 |
| Frontend cache | 34.72 | 92.50 |
| Runtime and native objects | 35.00 | 91.43 |
| Cached executable | 16.67 | 43.58 |
| Build replay | 0.14 | 0.36 |

Totals also include root-directory allocation. Source, measurement logs and the
separate output executable are not included. The cold builds took 142.28 s and
338.23 s respectively under this separate disk-measurement setup; these are full
first builds with every native unit compiled, unlike the 1–3-unit edited builds.
The exact byte counts and build reports are in
[`single-build-cache.json.gz`](single-build-cache.json.gz).

## Reproduction and evidence

Build the baseline from `bf85fcf6b` and the candidate from this change with
`zig build -Doptimize=ReleaseFast --prefix <output>`. The executable SHA-256 values
are recorded in each results archive and [`validation.json`](validation.json).
Use the validated native seed documented in the preceding experiment, then run:

```sh
flock /run/user/1000/mylang-slots/cpu10.lock taskset -c 2,3,10,11 \
  python3 experiments/checkpoint-reuse-20261009/compare.py \
  --baseline <previous-compiler> --candidate <new-compiler> \
  --native-seed <validated-scaling-output> --output <new-output> \
  --copies 12 32 --repeats 3
```

Repeat the command with `--resume` to continue the completed caches with sample
numbers 3–5 and new source bytes. It writes `warm-results.json` separately and
verifies that the compiler executables have not changed. Summarize either series
with `python3 experiments/checkpoint-reuse-20261009/summarize.py <results.json>`.

For the single-build disk measurement, use a new output directory:

```sh
python3 experiments/checkpoint-reuse-20261009/single_build_cache.py \
  --compiler <new-compiler> --output <new-output> --copies 12 32 --jobs 8
```

The initial series has 40 builds and 20 identical complete-binary pairs; the
continued warm series adds 36 builds and 18 identical complete-binary pairs. All
edited native objects, allocated executable sections, replica execution, EDA
golden exports and leak checks also match. The eight-build integration smoke run
is retained as correctness evidence only; its unreserved-CPU times are excluded
from the performance comparison.

Raw records, summaries, recovery results and compressed validation logs are kept
in this directory. Shared-host timing variation is retained in the records,
including per-build load averages; neither series is silently discarded.
