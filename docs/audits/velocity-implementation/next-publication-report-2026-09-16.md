# Persistent-cache publication report — 2026-09-16

Status: **implementation + measurement.** The gated export-index / one-check
work was frozen as commit `fd103f82`, then durable semantic-cache publication
was changed to amortize synchronization across a bounded batch. The per-body
`fsync` is gone: a 101-body cold check on ext4 drops from ~298 ms to ~13 ms
with one `syncfs` instead of 101 `fsync` calls. The full gate is green.

The actual 100k used-helper edit (not forced execution) is now
**1.45 s p95 ordinary / 3.59 s p95 managed**. Profiling attributes the managed
gap over a forced run to **QBE object compilation of 64 re-emitted fragments**,
not to provider materialization or additional checking.

## 1. Frozen baseline

| Item | Value |
| --- | --- |
| Freeze commit | `fd103f82` (`perf: index exports once and share one checked native-test compilation`) |
| Frozen compiler (S1 measurement) | `/tmp/vel-rf/bin/mylang` `186ac5c6…`; final `/tmp/vel-rf-final/bin/mylang` `d2dde81c…` |
| Gate at freeze | `test` 1,216/1,216, `test-qbe` 133/133, `test-qbe-build` 22/22, `fmt-check` clean |

Unrelated concurrent work (`.claude/`, `.zig-global/`, `docs/audits/deepseek-tools-2026-09-16/`,
`env.my`, `qualified_unresolved.my`) was deliberately left uncommitted.

## 2. Change: one shared sync per publication batch

`src/semantic_store.zig` still writes each entry as a complete checksummed
image and atomically renames it over its stable key, but inside a
`beginBatch`/`endBatch` publication group it no longer calls `file.sync` per
body. `endBatch` issues **one `syncfs`** for the whole group, through the raw
syscall so an unsupported or refused flush is a counted bypass rather than a
compiler abort. `Batch.dirty` tracks whether a batch published anything, so a
warm request that publishes nothing performs no synchronization. The
unbatched single-`put` path keeps its own flush.

Guarantees preserved:

- Each entry is still a complete header/body/checksum image; version,
  contract, mutation version, stable key, context, checksum, bounds and C1R
  remap validation are unchanged.
- The rename stays atomic and data is visible from the page cache immediately,
  so a concurrent reader sees a complete image.
- A crash before the shared sync can leave a torn image, which the checksum
  rejects as a miss; no partial or stale image is accepted.
- Updates stay proportional to changed entries; no whole-store rewrite or
  index is introduced.
- `--no-cache` opens no store and performs no durable read or write.
- The on-disk layout and `semantic-cache-v1` version are unchanged; only the
  durability timing changed, and the batch contract is documented in the
  module and in `SEMANTIC-CACHE-15`.

Tests (`src/semantic_cache_test.zig`):

- `durable batch publication issues one shared sync per batch and none when
  warm` — 65 fresh bodies cost exactly one sync; a warm re-read costs zero.
- `a torn durable entry is a miss that rechecks and republishes in one batch`
  — truncating a published image forces a fresh check, one shared sync, and
  unchanged acceptance/diagnostics.
- `an interrupted staging file and a foreign entry are ignored` — a stale
  `.tmp` and an unrelated file are invisible to lookup.
- Existing contract-isolation, byte/entry-bound eviction and allocation-failure
  coverage still passes.

## 3. Publication probe (101 bodies)

`scripts/benchmark_semantic_publication.py`, ReleaseFast compiler
`16ddcf8b8d40e7f592869e4b0475a4371bcd515156be25e137da7c04ebb0606c`, default
16 MiB semantic budget, private cache per sample. Raw:
`next-publication-2026-09-16/publication-probe.json`.

| filesystem | state | retention_store_io median | sync syscalls | cache bytes/files |
| --- | --- | ---: | --- | --- |
| tmpfs | cold (3) | **1.9 ms** | `syncfs` 1 | 97,830 / 103 |
| tmpfs | no-cache | 0.0 ms | – | 0 |
| ext4 | cold (3) | **12.8 ms** | `syncfs` 1 | 97,830 / 103 |
| ext4 | no-cache | 0.0 ms | – | 0 |

The independent pre-change diagnostic measured ~298 ms and 101 `fsync` calls
for the same shape on ext4. The residual ~13 ms is entry encoding plus 101
file create/rename operations and one filesystem sync, not a per-body flush.

## 4. 10k/100k matrices on both filesystems

Same pinned ReleaseFast binary, private workdirs, default 16 MiB budget, 10
samples for baseline/edit states and 5 for `forced_tests`. Raw:
`matrix-tmpfs.json` / `matrix-ext4.json`. Load: tmpfs 2.9 → 2.6, ext4 2.6 → 4.0.

| workload/state | tmpfs p50/p95 | ext4 p50/p95 |
| --- | ---: | ---: |
| ordinary-10k cold | 110/113 | 180/202 |
| ordinary-10k implementation_edit | 66/67 | 90/99 |
| ordinary-100k cold | 782/1,581 | 1,034/1,098 |
| ordinary-100k implementation_edit | 547/558 | 587/645 |
| ordinary-100k no_cache | 565/581 | 630/873 |
| ordinary-100k forced_tests | 1,436/1,442 | 1,586/1,650 |
| managed-10k cold | 135/150 | 391/401 |
| managed-10k implementation_edit | 97/102 | 147/158 |
| managed-100k cold | 857/875 | 1,767/1,888 |
| managed-100k implementation_edit | 692/710 | 798/811 |
| managed-100k no_cache | 659/707 | 729/743 |
| managed-100k provider_edit | 747/766 | 782/795 |
| managed-100k forced_tests | 1,648/1,697 | 1,800/1,835 |

`retention_store_io` p50 for `implementation_edit`: ordinary-100k 79 ms tmpfs
vs 93 ms ext4; managed-100k 106 ms vs 153 ms. The old ext4 penalty is gone
from the edit path.

**Residual cold-population cost.** The cold managed-100k ext4 phase is
`retention_store_io` 758 ms vs 164 ms on tmpfs (total 1,762 vs 852 ms). With
syncs already O(batches) — three `syncfs` for the ordinary, symbolic and
specialization groups, confirmed by a traced run — the remaining ext4 cost is
creating and renaming ~32k entry files. A segment/batch-file layout, not more
sync batching, is the candidate if cold ext4 population matters.

## 5. Actual edits vs forced runs

100k native probe, ReleaseFast `16ddcf8b…`, 5 repeats, `--report`. Raw:
`native-probe-tmpfs.json` / `native-probe-ext4.json`.

| state | tmpfs p50/p95 | ext4 p50/p95 |
| --- | ---: | ---: |
| ordinary used-helper edit | 1,578/1,667 | **1,435/1,452** |
| ordinary unused-helper edit | 1,314/1,320 | 1,157/1,162 |
| ordinary forced run | 1,524/1,551 | 1,454/1,787 |
| managed used-helper edit | 3,553/3,730 | **3,525/3,587** |
| managed unused-helper edit | 1,310/1,416 | 1,401/1,414 |
| managed provider edit | 1,737/1,891 | 1,810/1,956 |
| managed forced run | 1,733/1,753 | 1,576/1,589 |

The managed used-helper edit is ~2× a forced run with nearly identical
checking; the next section explains where the time goes. `--no-cache` controls
still write zero durable files; their wall time is dominated by the shared
default object cache and is not a semantic-cache comparison.

## 6. Profile: managed-100k used-helper vs forced

`profile_native_path.py`, tmpfs, 3 samples. Raw: `native-path-profile.json`.

| | forced run | used-helper edit |
| --- | ---: | ---: |
| `mylang test` median | **1,525 ms** | **3,388 ms** |
| checked bodies (fresh/reused) | 24,136 / 8,572 | 24,200 / 8,508 |
| selected/lowered functions | 322 | 322 |
| build `compiled_functions` | **0** | **64** |
| build `reused_functions` | 322 | 258 |
| build `codegen_seconds` | 0.022 s | **1.886 s** |
| build `link_seconds` | 0.042 s | 0.041 s |
| check phases total (`check-project`) | – | 685 ms |

The ~1.86 s difference is object compilation: the used-helper edit re-emits 64
QBE fragments and recompiles them, while the forced run's unchanged source
reuses all 322 objects. Checking is essentially identical (fresh/reused bodies
differ by <1%). Linking is identical. Provider materialization is not the
cause. The next optimization should target invalidation breadth/object
recompilation (why 64 fragments change for a one-helper edit) or batched QBE
compilation, not checking or provider handling.

## 7. Retention reassessment

Default budget stays at 16 MiB for this round. The new matrices reproduce the
plan's observation: managed-100k `implementation_edit` (692/798 ms p50) is
slower than its `no_cache` control (659/729 ms), so retention read/replay
overhead still exceeds its savings on this edit. Raising retention needs fresh
evidence after that overhead is addressed.

## 8. Gate

Full repository gate on the final source: `zig build fmt-check` clean;
`zig build test --summary all` 41/41 steps and **1,219/1,219 tests**;
`zig build test-qbe --summary all` 36/36 steps and **133/133 tests**
(includes `test-native-tests`); `zig build test-qbe-build --summary all`
22/22 steps. C4 selective-lowering integration tests pass unchanged.

## 9. Follow-ups

1. Cold ext4 population still pays per-entry file creation; evaluate a
   segment/batch-file layout with a bounded index if cold builds matter.
2. Managed used-helper edits recompile 64 objects; profile why a one-function
   edit widens QBE emission before optimizing checking further.
3. Cached managed checks remain slower than no-cache; improve replay/retention
   overhead before raising the budget.
