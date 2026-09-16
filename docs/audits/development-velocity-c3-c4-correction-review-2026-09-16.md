# C3/C4 correction review — 2026-09-16

## Decision

**The previous stale-result, directory `--no-cache`, and session-clear failures
are fixed in the independent reproductions. Shared generic retention now works,
but one P2 accounting finding remains before its strict budget contract can be
signed off.** Fix that small boundary case, then proceed to S1 remeasurement.
Benchmark preparation and self-hosting work can continue in parallel.

This review does not establish the S1 latency targets or complete per-function
lazy lowering. Those remain separate work, as the implementation report states.

## Scope and evidence

- Reviewed `b819277b..5eaa4051`, including the integrated source-ownership and
  ordinary sparse-remapping changes.
- CLI probes used a private copy of the ReleaseFast compiler from the clean
  `final3-release2` worktree at code gate
  `610656cfbc9bccd2c1e1efb92e054d3b6a7808cb`.
- Executable SHA-256:
  `35e2b8acf11e1bde026ae3b8f1dc528125ff78963e47c030cd7d91a47c8c2ca7`.
- Advertised compiler identity:
  `24d6dc299c1b7a4f9ae00f545117f0da5fc5ab018464fb1ab2d20bca4ca35329`.
- Two isolated Zig assertions imported the reviewed compiler sources directly
  to test a configurable retention budget and actual owned allocations. They
  bypassed the build graph; no Guardian gate was exercised.
- The full Debug/ReleaseFast/doc/Guardian gates were not rerun. Their totals
  remain the implementation report's evidence, separate from this review.
- No implementation files were changed. Fixtures and deliberate cache
  substitution were confined to private temporary directories.

[Probe evidence](development-velocity-c3-c4-correction-review-2026-09-16-probes.json)
contains commands, outputs, compiler identity, fixture drivers, retention samples,
and the complete standalone budget reproducer. Single-run times in that file
are diagnostic observations, not S1 measurements.

## Finding

### B1 — P2: make budget admission agree with retained allocation size

Primary location: `src/semantic_entry.zig:172-176`; consumers include
`src/semantic_cache.zig`'s `fitsOrdinaryBudget`, `remember`, and `loadPersistent`.
Related accounting helpers are at `src/semantic_entry.zig:145-168`.

`indexCapacityFor(1)` estimates two hash slots. The pinned Zig standard library
actually allocates a minimum of eight. Consequently an ordinary entry can pass
the admission check and leave the cache over its limit even after the request
has finished. Generic reconciliation cannot repair an ordinary-only overrun:
it exits when there are no generic entries to evict.

The standalone reproducer checks `def main() -> i64: return 1`, measures its row
and arena cost, then opens another cache with only 50 additional bytes allowed
for the index. Observed on the reviewed tree:

| Measurement | Bytes |
| --- | ---: |
| Configured budget | 1,400 |
| Retained after first completed check | 1,542 |
| Retained after second completed check | 1,542 |

The index has eight slots and the entry remains retained. The assertion
`retained_bytes <= max_bytes` fails. This is a persistent boundary violation,
distinct from the explicitly documented temporary overshoot within a request.

The related owned-storage count also excludes internal allocation bookkeeping:
`hashIndexBytes` counts slot arrays but omits the hash header/alignment, and
`ArenaAllocator.queryCapacity()` explicitly excludes arena bookkeeping. A
counting allocator used only by the cache, sampled after the compilation and
request temporaries were released, measured **1,598 owned bytes versus 1,550
reported bytes** for the one-entry fixture. This is a direct allocation count,
not a process-RSS estimate. The same arena/index helpers serve generic tables.

**Repair:** include the minimum hash capacity in admission estimates; make the
owned-byte model include the storage promised by the budget contract; and make
publication/promotion enforce the final bound using the same model. If allocator
bookkeeping is intentionally excluded, define that boundary explicitly rather
than describing the number as total owned retention. The eight-slot admission
error still needs fixing either way.

**Acceptance:** exercise budgets just below, at, and above actual entry/index
costs for one, two, and several ordinary entries, including a hash growth
boundary. Check fresh publication, durable promotion, warm retention, and mixed
entry kinds. After each completed request the reported bound must hold; compare
owned-allocation accounting with an allocator tracker and preserve fresh-check
acceptance and diagnostics.

This finding does not reproduce a stale compiler verdict or test result. The
unbounded generic growth reported in the previous review has been addressed.

## Verified corrections and preserved behavior

| Probe | Independent observation |
| --- | --- |
| G1: copy an intact old successful graph over the new failing snapshot's graph filename | Exit 1, failed=1, executed=1, cached=0; agrees with `--no-cache` |
| N1: directory `--no-cache`, seeded and empty caches, one and two workers | Both selected programs execute; empty cache directories contain zero durable files |
| N1: repeat against a seeded directory cache | All 70 existing files retain identical bytes and modification times |
| C3R1: `check`, `clear`, `check` with two specializations | First 3 fresh/0 reused; clear reports zero bytes in every kind; next check 3 fresh/0 reused |
| C3R2: 900 requests introducing distinct const-length specializations | Reported retention converges below 16 MiB; 590 budget evictions; clear removes reuse and preserves the eviction counter |
| C4: unchanged two-test selection | 0 executed/2 cached; 0 emissions/0 builds |
| C4: unused-helper edit | Both results cached; one preparation emission, no build |
| C4: used-helper edit | 1 executed/1 cached; one build |
| Reversed but identical provider maps | Forced run shares one build; warm run emits/builds nothing |
| Selected body/signature errors and unused malformed generics | Still reject; malformed generic rejects with and without caching |
| C3 template and concrete-argument edits | Selective reuse persists; `--no-cache` checks fresh |

The 900-request retention experiment uses the same two cohorts as the earlier
review. Both change the ordinary caller on every request; one also changes the
const-length argument each time.

| Cohort, after 900 checks | Reported semantic retention | Budget evictions | Process RSS |
| --- | ---: | ---: | ---: |
| Fixed specialization | 63,184 B | 0 | 33,996 KiB |
| Distinct specializations | 16,742,288 B | 590 | 45,928 KiB |

The configured function-cache budget is 16,777,216 bytes. RSS includes other
caches and allocator behavior, so it is not the semantic retention size. Both
cohorts check both bodies fresh after `clear`; the distinct cohort's cumulative
eviction count remains 590.

## Next steps

1. **Close B1** with the boundary/allocator assertions above and the appropriate
   repository gates. This is a narrow follow-up to C3R2.
2. **Run S1 on the resulting pinned compiler.** Compare ordinary and generic
   10k/100k projects across unchanged, body, interface and provider edits. Include
   cached/forced native tests, p50/p95, peak memory, and cache work counters. Add
   a generic workload that exceeds the retention budget so eviction cost is
   measured. Keep Zig host rebuilds separate from `.my` edit/test latency.
3. **Use those results to prioritize the next implementation.** Changed snapshots
   still emit a whole project and uncached cases build the selected-provider
   library. Per-function lazy lowering remains open; dense specialization remaps
   and eviction/compaction costs also belong in the S1 investigation.
4. **Finish D2 and the productivity trial, then final acceptance.** Reconcile
   stale descriptions of C3 and graph v1 in the status documents, retain the
   declared transient-memory and disk-budget boundaries, and record measured
   results instead of treating green correctness gates as speed evidence.
