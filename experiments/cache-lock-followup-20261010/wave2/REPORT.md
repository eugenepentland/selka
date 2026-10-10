# Historical Wave2 deferred measurements, 2026-10-10

The frozen optimization reduced the 510,436-line synthetic shared-helper edit
median by 25.3% and three-file edit median by 23.9% against the frozen Wave2
comparison. Their restore medians fell 36.2% and 37.1%. Private-edit and no-op
measurements show no useful improvement, and peak process RSS remains near
662 MiB. These measurements complete the previously deferred historical
comparison. They do not establish performance of current-main follow-up changes.

The paired run completed all 69 compiler invocations successfully: every invocation
has 662 matching normalized verdicts, all nine optimized forced-execution pairs
have identical keys, all 27 restore pairs recover the original keys and reuse
all tests, and 27 measured edits have fresh key signatures. All 333 fixture files
are restored byte-for-byte; their relative-path corpus SHA-256 is
`5de745eb2f19246e4f590a8920e6c399ae7f99f8442a88a292f25f51dbdcee08`.

| Phase | Pre-Wave2 baseline s | Wave2 comparison s | Optimized s |
| --- | ---: | ---: | ---: |
| cold | 38.606 | 51.353 | 41.533 |
| noop | 0.228 | 0.285 | 0.282 |
| private | 0.299 | 0.349 | 0.352 |
| helper | 13.565 | 18.148 | 13.559 |
| three-file | 13.066 | 17.850 | 13.582 |
| restore-private | 0.212 | 0.275 | 0.275 |
| restore-helper | 6.797 | 11.836 | 7.554 |
| restore-three-file | 6.520 | 11.682 | 7.353 |

Cold and no-op each have one sample; other rows are medians of three first-edit
samples. `paired-summary.json` retains every raw sample, range, CPU time, RSS,
verdict count, object count, cache inventory and per-root work total. Compiler
arms share source paths but have separate application/native/Zig stores, and arm
order reverses on alternate rounds. Cold means new stores, with an already
installed toolchain and existing operating-system page cache. This is a small
synthetic comparison, with no statistical-significance claim.

Compared with the pre-Wave2 baseline, the optimization leaves cold, no-op,
private-edit and restore costs somewhat higher. Shared-helper edit medians are
nearly equal; the optimized three-file edit remains about 4% slower. RSS shows
no material reduction. The single cold comparison is 41.533 s optimized versus
51.353 s Wave2 and 38.606 s pre-Wave2.

The compiler hashes are:

- baseline: `079ee95624c5a2ff0eabd83ebaad590e7ab8e70e4b20d8eba6c939e097c4cce1`
- candidate: `df45161f422a6421a7f945163c412a61617f782fa2464e9bce30419bafde1c54`
- comparison: `92dd45fc92a79bca7eb2f273ec9ffdf6cac454526302b521b5bf33b88e0bc8c6`

Both native component manifests and their artifacts validated for all arms.
`PLAN.json` and `harness-hashes.json` preserve the exact commands and harness
identity. The implementation represented by the optimized binary is historical
commit `07927a094ae9e9c6d534834ab46c6abec4da635a`; this run used that frozen
ReleaseFast install, rather than rebuilding its sources from current main.

Normal FIFO gate admission waited 0.049 s and held the slot for 725.213 s;
command wall was 725.193 s. The held interval includes forced oracles, cache
inventories and report serialization, and is not a compiler-only time. Timing
runs use CPUs 2 and 10. Unrelated focused builds may use the other CPUs; no gate
runs concurrently. GNU time RSS is maximum individual process RSS, not summed
process-tree memory.

Per-root wall-stage counters are consistent with the catalog-hashing change:
helper lowering summed medians fall 19.574 s to 3.701 s, while planner counters
fall 14.260 s to 13.086 s. For restore, lowering falls 20.120 s to 5.332 s and
planner counters fall 14.582 s to 12.441 s. Worker intervals overlap, and shared
catalog preparation is outside these per-root intervals; these values cannot be
summed into end-to-end wall or CPU time. They leave planner execution and binding
validation as an investigation lead.

The optimized diagnostic profile completed two successful compiler invocations:
all 662 helper tests execute, all 662 restore tests reuse their original keys,
and all 333 source files restore byte-for-byte. `profile-qualification.json`
independently checks verdicts, key maps, fixture hashes and frozen compiler,
component and harness identities. Normal FIFO ticket 13 waited 1,894.540 s and
held the gate for 21.630 s. This queue time is excluded from compiler timings.
Instrumented helper and restore wall times are 13.325 s and 6.944 s; use the
paired uninstrumented medians above for performance claims.

| Diagnostic flat self sample share | Before helper | After helper | Before restore | After restore |
| --- | ---: | ---: | ---: | ---: |
| BLAKE3 + SHA2 | 45.38% | 15.58% | 58.78% | 23.63% |
| Including direct named TreeHash | 48.47% | 15.84% | 61.39% | 24.58% |

`profile-before-summary.json`, `profile-after-summary.json` and
`profile-comparison.json` retain flat event-weighted self rows, sample counts,
unresolved categories and diagnostics. The after-profile records 706 helper
and 400 restore samples with zero reported lost samples. After helper has
32.79% unresolved self samples including Zig; restore has 3.85%. Discovery's
`test_runner_discover.within` is visible at 5.50% helper and 18.17% restore self
samples, an investigation lead rather than a measured optimization claim.

The historical and new fixtures have identical relative source bytes; absolute
paths and populated stores differ. Children percentages are never summed.
Limited DWARF stack coverage does not establish hash callers, planner memfd
samples remain unresolved, and perf's `HEADER_EVENT_DESC` decoding warning is
retained. Symbol-cache commands exited zero while emitting diagnostics, so
successful indexing is not assumed. Diagnostic percentages are not wall-time
percentages and cannot establish performance of current main.

Raw paired evidence lives under
`.mylang-cache/cache-lock-followup-20261010/wave2/paired-510k/`, with independent
admission evidence alongside it. `retention.json` records removal of only the
four new stores no longer needed, releasing 4.133 GiB. Source, raw perf data,
symbol copies, reports, result JSON and compact summaries remain. Old caches
and user data were not deleted.
