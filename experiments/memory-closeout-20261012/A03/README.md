# A03: fresh allocation and RC census

The fresh [C0 release sweep](C0-release/REPORT.md) passes all **81 cases and 131
guest executions**, including every historical 48-matrix sample, ten migrated
library fixtures and the later JSON/field regressions. All guest outputs and exit
statuses match, counted executions have zero RC and zero managed exit-live bytes,
and all 81 emitted-LLVM/linked-symbol audits pass. This qualifies the baseline's
release coverage; the final integrated compiler still requires all five modes.

The original 30 migrated workloads freshly measure **23 allocating, 7 workload
allocation-free, 0 executing RC, and 0 refused/failed**, at both inputs. Original
unmigrated source checks separately admit 21 and refuse 9. The 1/16/128-sibling
JSON lookup controls add three allocations per hit and none per miss. Record
explicit-copy versus field-transfer sources allocate 27,000 versus 21,000 blocks
per 1,000 unpacks on this same compiler. These are fresh observations, not copied
historical numbers or compiler-only comparisons between different source rules.

C0 source is `fbfcaa7a923186a8e773c3760f81c10aa345a432`; the full Debug compiler
installation's executable SHA-256 is
`324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
[Machine-readable results](C0-release/results.json.gz), [raw counter/command
receipts](C0-release/raw-json.tar.gz) and [controlled lookup/source-variant
comparisons](C0-release/controls.json) are preserved with hashes.

The manifest preserves all 30 original census IDs and separate original/migrated
source hashes, all 48 historical final-matrix samples, ten migrated library
fixtures, two source parallel-map samples at 1/2/8 workers, all 18 JSON lookup
construction/hit/miss cases, both record-copy/transfer variants, and the nested
owned-JSON sample. Five modes yield 405 builds and 655 counted guest executions.
The original 30 sources also receive separate source-admission checks. Their
diagnostics do not silently replace the migrated workload results.

The earlier [three-case smoke](C0-smoke/REPORT.md) and partial pre-batch scratch
run remain preserved. The coordinator requested a release-first C0 sweep and
approved bounded admission to reduce queue overhead; no successful evidence was
discarded. `complete_matrix: false` in the C0 results deliberately records that
the final five-mode 405-build/655-execution matrix has not yet been run.

`census.py` writes only below the requested fresh output directory. Unlike the
historical harnesses, it never publishes back into old experiment directories.
The coordinator approved bounded leases of at most ten compiler calls, released
after sixty seconds at the next safe command boundary. Admission queue wait has
separate receipts; compilation occurs only while the lease holder remains live.
Do **not** wrap this harness in another admission command. It catches individual refusals/failures,
keeps them in the denominator, and proceeds with independent cases. Resuming
requires identical compiler, toolchain, harness, manifest, and ownership mode.

```sh
source /home/epentland/.config/mylang/dev-env.sh
python3 -B experiments/memory-closeout-20261012/A03/census.py \
  --compiler /path/to/full/installation/bin/mylang \
  --compiler-commit FULL_SHA --zig "$ZIG" \
  --output .tmp/memory-closeout/A03/C0
```

Use `--ownership default` only after the coordinator promotes the default.
`--family historical-48`, `--case census/01_scalar`, and `--modes release` allow
focused checks without changing the complete manifest or its denominator.
Counter evidence is instrumented correctness/allocation evidence, not guest
performance. A09 owns uninstrumented runtime/RSS/compile measurements.
`SIGUSR1` requests a checkpoint after the current lane; all completed evidence is
saved before the lease is released. `--resume` can then continue safely.

Every admitted run records exact output, exit status, whole-program memory,
workload memory (excluding `<outside>`), RC counters, direct frees and leak
status. Every executable records its hash and an LLVM/symbol audit. Runtime
layout/preprocessor proof remains A07's responsibility. Managed allocation bytes
omit native dictionary metadata, sort scratch, provider buffers, task stacks and
allocator overhead. Peak live bytes are not allocation traffic or RSS, and no
peak subtraction is performed. Counter columns for emitted and runtime RC can
overlap and are never summed.

The adapter imports only the historical read-only counter summarizer and audit
functions. Historical `measure.py`, `qualify.py`, and batch `capture` functions
were inspected and deliberately not invoked: they write reports alongside
themselves even when an alternate output directory is supplied.

`compare.py --baseline PATH --candidate PATH --output NEW_JSON` produces a
machine-readable comparison of two census result files (plain or compressed).
It pairs only successful executions with identical source hashes and run
contracts, retains unmatched/refused/unmeasured statuses, and subtracts only
allocation traffic. Peak and exit-live memory remain separate observations.
Recorded recursive list-copy traffic may increase after A09's instrumentation
correction without any additional allocations or peak memory; the comparison
keeps those counters separate from allocation deltas.

The interim [Support5 original-30 sanity pass](Support5-original30/REPORT.md)
passes all 30 release builds and 72 executions on compiler source
`a1f19edf255c8c0886731d8d7cce450d5f657720`. The original allocation and source
admission denominators remain unchanged. All 72 paired C0/Support5 observations
have identical workload and whole-program allocation traffic and managed peaks.
These results qualify the requested sanity check; the other 51 expanded cases
and the final five-mode integrated matrix remain due.
