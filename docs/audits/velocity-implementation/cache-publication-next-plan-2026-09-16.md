# Next package: amortize persistent-cache publication — 2026-09-16

## Decision

Freeze the current green source and its compiler artifacts, then fix persistent
semantic-cache publication on the actual development filesystem. Keep tmpfs as
a comparable CPU/control benchmark; retain ext4 results as a separate primary
development measurement instead of discarding them.

The current export-index and single-check changes have demonstrated benefits.
Further dependency-key preparation work is not the next priority. The remaining
storage issue can turn a millisecond check into hundreds of milliseconds even
on a tiny project, and the implementation report observed seconds at 10k.

The inspected worktree is still based on `df39a308` with the implementation in
tracked working-tree modifications. Commit the exact gated change set before
the next implementation, preserving unrelated concurrent work. The report's
final compiler is SHA-256
`d2dde81c6d4dfd8c6397489efa379d09e7c4b5ae1db996e9482654b88acaa866`.

## Independent evidence

`/tmp` is tmpfs. The repository is on `/home/epentland/ai`, an ext4 mount backed
by `/dev/nvme0n1p1`. Both locations were inspected directly.

A private 101-function project, using a copy of the final compiler above:

| Location/policy | Observed wall time |
| --- | ---: |
| tmpfs, cold cache, median of three | 5.9 ms |
| ext4, cold cache, median of three | 298.4 ms |
| tmpfs, no-cache control | 2.4 ms |
| ext4, no-cache control | 2.4 ms |

These are diagnostic observations, not a new S1 percentile run. All checks
succeeded. The ext4 cold samples spent about 288–304 ms in
`retention_store_io`. A separate syscall wall-time trace recorded **101 fsync
calls totaling 287.9 ms**, 97.4% of the measured syscall wall time.

`src/semantic_store.zig:500` synchronizes each entry before its atomic rename.
The existing `beginBatch`/`endBatch` amortizes namespace inventory and trimming;
it does not batch entry synchronization. This explains the observed disk cost.

[Raw probe evidence and driver](cache-publication-review-2026-09-16-probes.json).
No repository build or Guardian gate was invoked for this probe.

## Scope of the next package

### 1. Amortize durable writes

- Publish bounded groups of entries with shared synchronization, for example
  immutable batch/segment files plus an atomically published index. Choose and
  document the smallest design that removes a synchronous flush per body.
- Keep updates proportional to changed/new entries. A one-body edit must not
  rewrite the entire project's retained set or repeatedly scan the whole store.
- Preserve successful-check-only publication, contract isolation, bounded
  payload decoding, checksums, stable identity/context validation and remapping.
- Preserve the documented publication guarantees. Do not silently remove file
  synchronization or declare partial data valid to reach the timing target.
  Interrupted/corrupt/incompatible data must produce cache misses and fresh
  checking, never an accepted stale result.
- Version changed storage layouts. Keep memory ownership, disk bounds,
  compaction and concurrent readers/publishers explicit. Account for any new
  retained index memory rather than excluding it from existing bounds.
- Keep `--no-cache` free of semantic durable reads/writes. Unchanged successful
  requests should not republish already-valid entries.

### 2. Acceptance evidence

- Demonstrate that file-sync operations scale with bounded publication batches,
  not the number of cached bodies. Record syscall counts, bytes written and
  publication time alongside wall time.
- Test interrupted publication, truncated data, damaged entries, stale/missing
  indexes, concurrent publication/read/eviction, allocation failure, and bounds.
  Prove cold/warm/no-cache agreement in status, diagnostics and results.
- Run 10k/100k ordinary and managed workloads on **both tmpfs and the repository's
  ext4 volume**, with private directories, the same pinned ReleaseFast binary,
  default 16 MiB semantic retention and recorded host load.
- Separate cold population, unchanged hits, body edits, interface/provider edits
  and no-cache controls. Use successful warm-up and enough successful samples
  for the stated percentile; record failure/timeout counts explicitly.
- Re-run relevant repository and semantic-store gates. Preserve C4's one check
  per provider graph, selective lowering, invalid-project rejection and
  no-cache behavior.

**Completion means:** the per-body synchronous publication cost is removed and
measured on ext4 without changing cache acceptance. It does not by itself imply
the <500 ms check or <1 s affected-test goals have been achieved.

## Keep the remaining targets accurate

The latest report's headline native numbers are forced execution, not every
affected edit. The saved probe gives these p95 values:

| Actual edit state, 100k | p95 |
| --- | ---: |
| ordinary used-helper edit | 1,453 ms |
| ordinary unused-helper edit, cached test result | 1,131 ms |
| managed used-helper edit | 3,467 ms |
| managed provider edit | 1,822 ms |
| managed unused-helper edit, cached test result | 1,185 ms |

The forced-test matrix has five samples; check states have twenty. Correct the
objective table so affected-test acceptance uses actual edit-to-result samples.

After publication is fixed, profile the remaining native path by preparation,
selection, lowering, object compilation, linking and execution. The difference
between managed forced runs (~1.5 s) and used-helper edits (~3.5 s) needs a phase
explanation before choosing another optimization. In particular, inspect changed
object counts and invalidation breadth; do not assume the extra time is provider
materialization without measurement.

Then reevaluate warm checking. Current managed-100k edits take ~757 ms median
versus ~625 ms with no cache, so cache read/replay/retention overhead still needs
attention. Improve that tradeoff before raising the retention budget or adding
another persistent preparation cache. The ranking should come from the profile
after the storage change, not from the old dependency-key bottleneck.

Self-hosting frontend work and productivity-trial setup remain independent. The
trial still requires reviewed task packs and a frozen comparison baseline; no
benchmark here establishes a comparative productivity result.
