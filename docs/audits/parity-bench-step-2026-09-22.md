# Parity benchmark step (plan wave 5) — 2026-09-22

Lane report for wave 5 of
[the performance parity plan](performance-parity-plan-2026-09-22.md): the suite
and its harness become a standing, opt-in benchmark with ratio thresholds.
Branch `bench/parity-step` from `base/parity-w5` (`79835b13`).

## What landed

- **`bench/parity/`** — the maintained copy of the suite:
  - `suite/`: 13 timed programs and their mylang variants, with Zig and Rust
    ports, `.expected` output and `SUITE.md`;
  - `lib/`: the three runtime-library scans, with `LIB.md` and the CPython
    oracle `expected.py`;
  - `micro/`: the eleven micro-kernels in all three languages, with `MICRO.md`;
  - `bench_parity.py`: the harness;
  - `thresholds.json`: the per-program thresholds;
  - `README.md`: method, arms, threshold policy, hardware counters.
- **`zig build bench-parity`**: an opt-in step in `build.zig` (`addParityBench`)
  with the options `-Dbench-cpu`, `-Dbench-rounds`, `-Dbench-filter` and
  `-Dbench-mylang`. Arguments after `--` reach the harness.
- **`docs/performance.md`** gains the section *Track parity with Zig and Rust*,
  with a `bash` example that `doctest` accepts.

The step adds no `src/features.json` slug. `doc-coverage` only checks slugs that
exist, so the gate does not need one, and the file is `@embedFile`d into the
compiler. A slug would change the compiler binary, and with it every
compiler-keyed cache the gate uses, for a build-system feature.

### Where it lives, and why

The repo had no standing benchmark location. `experiments/` holds dated evidence
snapshots that nothing maintains. `examples/` is documentation, and
`examples/benchmarks` is the guest `mylang test --bench` example. `tests/` is
the gate. A new top-level `bench/` holds opt-in benchmarks:

- nothing in the gate walks it;
- `mylang doctest` reads only `README.md`, `SPEC.md` and `docs/`;
- `tests/list_declarations.py` and `tests/store_roundtrip.py` walk only
  `examples/` and `experiments/`.

The two source directories stay as the frozen evidence behind the plan's
numbers:

- `experiments/perf-parity-plan-20260922/` keeps the porting notes, repros,
  counterfactual and ladder tooling, and the results;
- `experiments/perf-parity-audit-20260921/micro/` keeps the original kernels.

The S-expression parser and the schematic benchmarks are not included. They
depend on other trees and inputs; see *Unfinished*.

## The step's interface

```bash
zig build bench-parity                                     # all 27 programs, CPU 2, 7 rounds
zig build bench-parity -Dbench-filter=sieve -Dbench-cpu=10
zig build bench-parity -Dbench-filter=micro/,lib/ -Dbench-rounds=11
zig build bench-parity -Dbench-mylang=/path/to/mylang      # a prebuilt compiler, no install
zig build bench-parity -- --json out.json --arms my zig-safe --no-confirm
python3 bench/parity/bench_parity.py rebaseline a.json b.json --label quiet --note "..."
python3 bench/parity/bench_parity.py table out.json
```

- **Compiler under test.** Without `-Dbench-mylang`, the step depends on the
  install step, so Guardian runs, and times `<prefix>/bin/mylang` through an
  `install_bin` lazy path. A Debug compiler and the ReleaseFast install of the
  same commit emitted byte-identical `sieve` binaries for `my`, `my-unchecked`
  and `my-tuned`. The compiler's own optimization changes only build time.
- **Filter.** `-Dbench-filter` takes comma-separated substrings of
  `GROUP/NAME`. An empty filter is rejected at configure time. A filter that
  names nothing exits 2.
- **Build.** All arms are built before anything is timed, 4 in parallel by
  default (`--jobs`). Each Rust arm gets its own `--crate-name`: two concurrent
  `rustc` runs over one source share intermediate object names and failed to
  link.
- **Qualification.** Each arm must print exactly the bytes of `.expected` and
  exit 0.
- **Timing.** Every sample is a fresh `posix_spawn` with the harness pinned to
  `-Dbench-cpu`, which the child inherits, and stdout to `/dev/null`. Each run
  does 2 warm-ups, then the rounds, with the arm order shuffled per round. Wall
  time and `wait4` CPU time are both recorded, along with peak RSS.
- **Verdict.** Each arm's result is the median of its per-round ratios to
  `zig-fast`, with a 95% bootstrap interval. A program over its limit is
  re-measured once, and fails only if the second pass also exceeds it.
- **Output.** A markdown table goes to stdout. It shows `zig-safe`, `rust`,
  `rust-checked`, `my` with its limit, `my-unchecked` and the variants, then
  geometric means per group beside the plan's §1 targets, notices, and
  failures. The JSON (default `.mylang-cache/bench-parity/result.json`) holds
  every sample, build command, binary hash, RSS, counters and verdict.
- **Failures.** A run fails when:
  - a mylang arm fails to build or qualify;
  - `zig-fast` fails;
  - a thresholded arm exceeds its limit on both passes.
- **Notices, not failures.** These are skipped with a notice:
  - Rust missing. This was demonstrated by running with `find_rustc` stubbed
    out: `notice: rustc not found (RUSTC, PATH, ~/.cargo/bin): Rust arms
    skipped`, then `PASS`.
  - Any other non-mylang arm that fails.
- **Hardware counters.** When `perf stat -e instructions:u,cycles:u` works
  (`perf_event_paranoid <= 2`), each qualified arm gets one extra counted run.
  Otherwise the step prints a notice. This machine is at 4, so that path is
  implemented but was not exercised. Lowering the setting needs root; the
  harness never touches it.
- **SMT sibling.** The harness records how busy the pinned CPU's SMT sibling
  was while each program was timed (`sibling_busy`), and prints a notice when
  it was over 25%. The next section explains why.
- **Cost.** A full run is 179 arms of 27 programs: about 14 minutes cold with
  9 rounds on a loaded machine, and about 9 minutes when the builds are
  cached. The filtered `sieve` run takes about 30 s.

## Thresholds, and what the machine taught about them

`thresholds.json` holds a baseline ratio and a tolerance for each program and
each mylang arm (`my`, `my-unchecked`, `my-<variant>`): 71 arms. The limit is
`ratio × (1 + tolerance)`. A re-baseline pools the per-round ratios of one or
more batches of one compiler. The tolerance is the largest of:

- 15%;
- twice the upper half-width of the pooled 95% interval;
- 1.5 × the excess of the slowest batch's median over the pooled median.

It is rounded up to a percent and capped at 50%. The thresholds are rewritten
only by the deliberate `rebaseline` command or by `-- --write-thresholds`.

Five full 9-round batches of the base compiler ran on CPU 10. The binaries were
byte-identical across batches. Table: `my` median ratio to Zig ReleaseFast.

| program | b1 | b2 | b3 | b4 | b5 | max/min |
|---|---:|---:|---:|---:|---:|---:|
| binary_trees | 2.38 | 2.34 | 1.92 | 2.33 | 1.90 | 1.26 |
| fannkuch_redux | 1.31 | 1.37 | 1.16 | 1.37 | 1.18 | 1.18 |
| knucleotide | 3.20 | 3.49 | 3.40 | 3.39 | 3.40 | 1.09 |
| mandelbrot | 0.98 | 0.98 | 0.99 | 1.03 | 1.03 | 1.06 |
| matmul | 3.85 | 4.24 | 3.86 | 4.02 | 3.89 | 1.10 |
| nbody | 3.19 | 2.67 | 3.61 | 1.97 | 1.98 | 1.84 |
| raytrace | 2.43 | 1.83 | 2.56 | 1.80 | 1.78 | 1.44 |
| sieve | 1.53 | 1.59 | 2.03 | 1.81 | 1.97 | 1.32 |
| sort_builtin | 0.52 | 0.49 | 0.49 | 0.52 | 0.50 | 1.07 |
| sort_quick | 1.32 | 1.30 | 1.33 | 1.31 | 1.30 | 1.02 |
| sort_records | 0.28 | 0.29 | 0.27 | 0.28 | 0.29 | 1.06 |
| spectral_norm | 1.71 | 2.30 | 1.79 | 1.70 | 1.75 | 1.35 |
| text_ops | 4.33 | 4.65 | 4.16 | 4.29 | 4.43 | 1.12 |
| scan_count | 0.66 | 0.66 | 0.65 | 0.67 | 0.67 | 1.04 |
| scan_replace | 0.43 | 0.40 | 0.39 | 0.41 | 0.40 | 1.11 |
| scan_split | 3.82 | 3.11 | 3.60 | 2.94 | 3.02 | 1.30 |
| alloc_churn | 2.60 | 2.65 | 2.64 | 1.99 | 1.99 | 1.34 |
| bytes_scan | 1.27 | 1.31 | 1.23 | 1.35 | 1.42 | 1.16 |
| calls | 1.00 | 1.00 | 0.95 | 1.00 | 1.00 | 1.06 |
| dict_count | 1.04 | 0.95 | 1.05 | 1.03 | 1.01 | 1.11 |
| fib | 3.36 | 3.08 | 3.40 | 3.36 | 3.41 | 1.11 |
| float_loop | 1.01 | 0.99 | 1.01 | 1.01 | 1.01 | 1.02 |
| intloop | 0.96 | 0.95 | 0.95 | 0.94 | 0.94 | 1.03 |
| list_append_sum | 1.37 | 1.37 | 1.37 | 1.39 | 1.42 | 1.04 |
| list_records | 1.38 | 1.37 | 1.44 | 1.50 | 1.49 | 1.09 |
| records | 0.99 | 0.89 | 0.91 | 0.91 | 0.91 | 1.11 |
| str_build | 1.24 | 1.21 | 1.18 | 1.18 | 1.21 | 1.05 |
| load (1-min, start→end) | 28→16 | 15→19 | 12→16 | 11→6 | 6→5 | |

Most programs hold within ±5% across batches. A few do not, on identical
binaries:

- `nbody` 1.97–3.61;
- `raytrace` 1.78–2.56;
- `alloc_churn` 1.99–2.65;
- `spectral_norm` 1.70–2.30;
- `sieve` 1.53–2.03.

The three most loaded batches (b1–b3) sit high on `nbody`, `raytrace` and
`alloc_churn`. The two quieter ones (b4, b5) agree with each other to within
1–2% on those programs, and with the wave-3 measurements (`nbody` 1.93–2.01).
Interleaving cancels load that slows both arms alike, but not load that slows
them differently. The likeliest cause is the SMT sibling (CPU 11) running other
agents' builds, but no experiment has isolated it. That is why the harness now
records `sibling_busy`, and why the README says to choose a core whose sibling
is idle.

How the policy was arrived at, each step validated on a later batch:

1. **Thresholds from b1 alone at 15%.** Checked against b2, 3 of 71 arms
   failed: `spectral_norm` `my` and `my-tuned`, and `matmul` `my-flat`.
2. **Pooled b1+b2, with the between-batch term.** Checked out of sample
   against b3, 5 of 71 failed: `sieve` ×3 and `nbody` ×2.
3. **Confirmation pass added.** b4 and b5 were then checked against the pooled
   b1–b3 thresholds: 0 failures, many `improved`.
4. **The committed thresholds pool b4+b5**, the quietest pair, at load 5–11,
   labelled `loaded`. By construction b4 and b5 pass. Checked against the
   heavily loaded b1–b3, 9–10 of 71 arms per batch exceed (`nbody`, `raytrace`,
   `alloc_churn`, `scan_split`, `spectral_norm`, `sort_records` `my-keyed`).
   Under load that heavy the step reports false regressions. The confirmation
   pass removes those that do not persist through a second pass.

Two choices were available: thresholds loose enough to pass under a load of
25, or tight enough to catch a 20% regression when the machine is calm. The
committed file favours the second, because a benchmark that passes everything
catches nothing. Its `note` field records all of this.

Of the committed thresholds, 65 of 71 arms carry the 15% default. The widened
ones are:

| arm | tolerance | why |
|---|---:|---|
| `binary_trees` `my` | 28% | 2.33 vs 1.90 between b4 and b5 |
| `scan_count` `my`, `my-unchecked` | 50% (cap) | wide within-batch intervals |
| `sort_records` `my-keyed` | 19% | |
| `scan_split` `my` | 17% | |
| `sieve` `my` | 16% | |

**The coordinator should re-baseline on a quiet machine**, with two batches
pooled, on a P-core whose sibling is idle:

```bash
zig build bench-parity -Dbench-mylang=... -Dbench-cpu=N -Dbench-rounds=9 -- --json a.json
zig build bench-parity -Dbench-mylang=... -Dbench-cpu=N -Dbench-rounds=9 -- --json b.json
python3 bench/parity/bench_parity.py rebaseline a.json b.json --label quiet --note "..."
```

## Injected regression

`sieve`'s `my` baseline was tightened from 1.885 to 1.20 in `thresholds.json`,
giving a limit of 1.39×. Then:

```console
$ zig build bench-parity -Dbench-filter=sieve -Dbench-cpu=10 -Dbench-mylang=.../install-ksort/bin/mylang
sieve: zig-fast 124.0 ms | my=1.74x  my-unchecked=1.40x  my-tuned=1.66x  zig-fast=1.00x ...
bench-parity: re-measuring 1 program(s) that exceeded a threshold: sieve
sieve (confirmation): my=1.59x  my-unchecked=1.21x  my-tuned=1.59x ...
| suite | sieve | 124.0 | 1.36 | 1.05 | 1.16 | 1.74 | 1.39 | 1.40 | tuned 1.66 | FAIL my |
REGRESSION sieve my: ratio 1.74x to zig-fast (95% CI 1.68-1.77) exceeds threshold 1.39x (baseline 1.20x + 16%); re-measured 1.59x (95% CI 1.51-1.60)
bench-parity: FAIL — 3 thresholded arm(s) checked, 1 failure(s); result .tmp/injected.json
error: process exited with code 1
Build Summary: 0/2 steps succeeded (1 failed)
```

The change was then reverted (`git checkout -- bench/parity/thresholds.json`).
With the committed thresholds, the same filtered run, now with the installed
Debug compiler (`zig build bench-parity -Dbench-filter=sieve -Dbench-cpu=10`),
passes: `my` 1.91× against a limit of 2.19×.

## Gate

`zig build test` is unaffected in content: the step is attached only to its own
`b.step`, and its options change no other step. Guardian passes on the branch,
both in the plain `zig build` the step runs and in the commit hook. The gate
diff against the `ksort` base logs:

| step | result | base (`ksort`) | new failures |
|---|---|---|---|
| `zig build` (Guardian) | pass, 88 checks | | |
| `test` | 52/73 steps, 1666/19089 tests, 45 failed | identical summary | 0 (46 = 46 names) |
| `test-qbe` | 43/48 steps, 272/274 tests | identical summary | 0 (2 = 2) |
| `test-qbe-build` | 30/30 | 30/30 | 0 |
| `test-schematic` | 27/27 | 27/27 | 0 |
| `test-byte-io` | 26/26 | 26/26 | 0 |
| `fmt-check` | 2/2 | 2/2 | 0 |

The `test` and `test-qbe` summaries match the base's step and test counts
exactly: the step adds nothing to either graph.

## Unfinished

- **Quiet-machine baseline.** The committed thresholds are provisional; see
  above.
- **Parser and schematic benchmarks.** The plan's application benchmarks are
  not in the step:
  - `parser_bench.py` needs a migrated `sexpr-port` copy and the zig-bench
    tree;
  - `bench_svg.py` needs the schematic inputs and ports.

  Each needs its tree vendored or pinned before it can be a standing arm.
- **Hardware counters.** The `perf stat` path is implemented but unexercised
  here, because `perf_event_paranoid=4` and lowering it needs root.
- **Sibling hypothesis.** Whether a busy SMT sibling explains the batch-level
  swings is not yet isolated. The new `sibling_busy` field lets the next quiet
  run test it: pin a load to CPU 11 and compare.
