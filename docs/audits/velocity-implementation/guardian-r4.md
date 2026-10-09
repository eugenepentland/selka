# Guardian R4 feedback

Task: R4 corrective — amortize persistent checked-body cache inventory/eviction
Branch: `codex/velocity-r4`
Base: `6a99ef4b` (C1R/C2/P1 integrated)

## What Guardian exercised

`zig build` runs the repository Guardian gate on every install, and it also ran
inside `zig build test-units`/`test-cli`. The first install of this change was
blocked by three checks and each finding was addressed before commit:

- `type-size` flagged `semantic_store.Statistics` at 8 fields (cap 7) after the
  batch-inventory counter was added. The counter moved into the existing nested
  `Retained` record, keeping `Statistics` at its prior 7 fields. This is the
  second C-series change forced through the same ratchet; future observers
  should extend `Retained`/`Root`/`Context` rather than growing `Statistics`.
- `catch-discipline` rejected the empty `catch {}` used to make the deferred
  `endBatch` cleanup best-effort. Rewriting it as an explicit
  `catch |err| switch (err) { error.OutOfMemory => {} }` documents that only the
  cache-local allocation failure is deliberately dropped; `put` still propagates
  OOM on the publication path.
- `change-classification` required a named regression with the behavioral
  lines. The new unit test
  `durable publication batch inventories a fresh namespace once instead of per body`
  asserts `store.statistics.retained.inventories <= 2` across 65 publications
  and would have failed (65 inventories) under the retired per-body trim.

No waivers or `accept` entries were needed. `fmt-check`, `test-doc-coverage`,
`test-docs`, `test-native-tests`, `test-qbe`, the full unit suite and the CLI
suite were run separately after the gate was green.

## Feedback for later velocity work

1. The batch/observer split is a useful pattern for these caches: keep the
   per-body hot path to a scalar accounting update, and reconcile against the
   filesystem only at bounded intervals. Guardian's `type-size` cap pushes that
   state into small nested records instead of a wide public `Statistics`.
2. `catch-discipline` is right to reject `catch {}` even in best-effort cache
   cleanup. A named switch on the actual error set keeps the intent explicit and
   makes later changes to `endBatch`'s error set visible.
3. The internal `Retained.inventories` counter is public only so a unit test can
   prove the population path is not per-body. It is observational and not part
   of the durable format; if a future refactor adds a dedicated test-only
   observer, this field can move behind it.

## Exact integration/spec/doc patches requested

R4 is a performance/fix corrective with no new user-visible behavior, so it does
not need a new `SPEC.md` behavior bullet. The integrator may still want one short
note where the semantic cache contract is described:

- `docs/tooling/caches.md` (or the C2 cache contract section): state that a
  publication request batches its fresh bodies, inventories the namespace at
  most once at batch open and once at batch close, and may exceed a retention
  bound transiently by a bounded slack before reconciling. The durable format,
  checksums, version isolation and `--no-cache` semantics are unchanged.
- The `Retained.inventories` observation added to
  `src/semantic_store.zig` is internal accounting exposed for the regression
  test; it does not need to be named in `SPEC.md` or `src/features.json`.

`src/features.json` and `SPEC.md` were not edited; no feature registration is
required for this corrective.

## Measured effect (R4 acceptance)

Fresh independent namespace per sample, `strace -f -c -e
trace=statx,newfstatat,getdents64` around
`mylang project-dependencies <scale-N>/main.my --report --cache-dir=<fresh>`.
The before column is the pre-fix binary built from the clean base commit at
`6a99ef4b`; the after column is the final `codex/velocity-r4` binary
(compiler identity `edd089412dd506974896afe18227166c3b1b440d00f41f8233`).

| N | before `statx` | after `statx` | after/before | doubling ratio (after) |
| ---: | ---: | ---: | ---: | ---: |
| 128 | 8,388 | 260 | 0.031 | — |
| 256 | 33,156 | 516 | 0.016 | 1.98 |
| 512 | 131,844 | 1,028 | 0.008 | 1.99 |
| 1024 | 525,828 | 2,052 | 0.004 | 2.00 |

Before, each body's `put` ran a full `trim`, so cost grew as `~N^2/2` (doubling
N multiplied `statx` by ~4). After, `stored` bodies only update scalar
accounting and one `endBatch` inventory scans the namespace, so cost is linear
(doubling N multiplies `statx` by ~2). The residual per-body `statx` is the
`createDirPath` existence probe, which was already present before and is linear.

The harness is `scripts/benchmark_semantic_population.py`; exact invocation:

    python3 scripts/benchmark_semantic_population.py \
        --compiler zig-out/bin/mylang --sizes 128 256 512 1024

It exits non-zero if a sample fails or if a doubling ratio exceeds 3.0, and it
caps requested sizes at 4096 so the benchmark stays bounded.
