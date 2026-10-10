# Cache Wave 3 qualification, 10 October 2026

The implementation adds an inventory-based developer coordinator for the complete
`test` plus `fmt-check` command. Exact source, tool, environment and native-artifact
identities are checked before shared admission. Missing evidence and explicitly
fresh work execute through the original build graph. The first implementation
reuses whole native test cohorts; it does not infer function dependencies inside
Zig test executables.

Baseline: `0d9ababf7eb434d2e02e1b2b45fe5c6593715e7a`, merging committed main
`5174fd03fb0f9dcae4f4fa51d7cb76ba649a988f`. The pinned compiler is
Zig `0.17.0-dev.1683+5ceec001b`. All work is on the local
`codex/selka-cache-wave3` branch.

## Qualification

The live inventory has 76 required actions, all 76 registered, with no unknown
actions. They form 38 cohorts: 29 eligible for reuse and nine requiring freshness.
Unknown required actions, including new compile-only checks, fall back to the
original complete gate.

Completed focused checks:

- 29 coordinator regressions and 20 immutable-snapshot regressions pass. These
  cover actual private FIFO admission, queued edits, cancellation, publication
  rollback, malformed evidence, host/tool/configuration changes, symlinks, ABA,
  restored timestamps, overflow, Git isolation, stale Python bytecode, shell
  startup hooks, exported Bash functions and newly appearing PATH directories.
- 10 native component-support tests pass, including preservation of unchanged
  metadata and repair of corrupted, missing or incorrectly permissioned files.
- The standalone build-registry regression passes (one test). It checks that a
  new compile-only gate outside explicitly prepared artifacts stays required.
- The focused build completed 46/46 steps with formatting and input coverage
  passing. Its Python suite preceded the two final shell/PATH regressions; those
  subsequently passed in the standalone coordinator suite.
- The merged baseline passed 29 unit and nine Core focused tests, and its commit
  hook passed all 88 whole-tree Guardian checks.

The complete gate and unchanged rerun both passed with stable inputs. The first
request executed the original `test fmt-check` roots with `-Dtest-rerun=true`:
110/110 steps succeeded and 2,601 native tests passed across 29 worker results,
with zero failures. The summary's 23,650 skipped entries are shard exclusions;
the selected worker results contain no skipped tests. The full gate also ran
all 49 Python coordinator/snapshot regressions.

| Observation | First request | Unchanged rerun |
| --- | ---: | ---: |
| Reused outer cohorts | 0 | 29 |
| Selected outer cohorts | 38 | 9 |
| Native test worker results | 29 | 0 |
| Build admission time | 1.874 s | 0 s |
| Gate admission time | 3,430.843 s | 21.097 s |
| Total elapsed time, including queueing | 3,751.285 s | 31.348 s |

The unchanged rerun completed 38/38 build steps for the nine fresh cohorts. It
started no cacheable native test workers and requested no build slot. Guest
fact/leak modes still executed under their existing freshness rules. Both runs
passed 88 Guardian checks using its diff scope against the merged main commit:
41 of 632 source files for the 50 per-file checks, plus 38 whole-tree checks.
Those gate checks are not described here as whole-tree Guardian verification.

Evidence is retained in [cold-run.json](cold-run.json),
[warm-run.json](warm-run.json), [inventory.json](inventory.json),
[preparation.json](preparation.json), and
[qualification-summary.json](qualification-summary.json). The summary records
raw-log hashes, exact build summaries, worker totals and Guardian scope; the
final build trees are in [cold-summary.txt](cold-summary.txt) and
[warm-summary.txt](warm-summary.txt). All 15 candidate source/document hashes in
[qualified-inputs.json](qualified-inputs.json) still matched after both runs.

The qualification command is run directly because the coordinator owns admission:

```sh
env \
  TMPDIR="$PWD/.mylang-cache/cache-wave3/tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache" \
  ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache \
  python3 -B scripts/verify_cache.py \
  --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig
```

Both requests use the default `-j3 --maxrss 8589934592 --summary all --seed=0`.
The first request has no valid outer action receipts; existing compilation and
guest caches are populated. It is not an empty-disk or cold-toolchain benchmark.
Exploratory runs cancelled during implementation are not counted as passes.

## Limits and deferred measurements

The nine fresh cohorts are component preparation, input discovery, environment
discovery, SPEC history, Juice, compiler-identity qualification, guest tests,
language tests and Guardian. Guest tests retain compiler-owned per-test receipts,
while fact/leak modes and untracked effects retain their existing execution rules.
Preparation and eligible action evidence are local to one worktree. The first
adapters conservatively share native artifact and host-tool identities.

Admission durations are operational observations that include validation overhead.
They are not isolated performance comparisons. The previously deferred Wave 2
paired measurements and after-profile have not been restarted. Wave 3's isolated
edit-matrix performance qualification remains outstanding.

## Packed-cache contention follow-up

During native qualification, `lslocks` showed one active worker holding the packed
stage store's sequence lock while other workers waited. The shared unit-test
cache contained about 3,500 packs, totaling about 36 MB at the observation. Workers
advanced to new cases; this was not an orphaned lock. These observations do not
establish a quantitative attribution for the gate's duration.

A read-only review identified separate optimization candidates in
`src/core/stage_pack.zig`:

- `saveRecord` and `flush` refresh the catalog after acquiring the sequence lock.
  Refresh enumerates filenames when the sequence advances, and performs a linear
  `fileId` lookup before the already-scanned pack shortcut. Repeated refreshes can
  therefore perform quadratic filename comparisons as retained files grow.
- `flush` holds the lock through journal reads/checksums, sorting, zlib encoding,
  pack assembly, writes/rename, catalog admission and journal deletion. Preparing
  immutable pack bytes before the publication lock is a candidate, with journal
  validation and concurrent-writer correctness preserved.
- Ordinary saves hash, copy and write the record payload while locked. The lock
  is released after each save/flush, not held for the entire guest run. Sealing
  covers the current state's journal rather than whole-store compaction.

No packed-store implementation or timing experiment was changed in this pass.
