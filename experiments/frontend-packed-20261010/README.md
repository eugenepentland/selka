# Frontend source proofs and compressed stage packs

This follows the optimized-debug compiler in
[`../checkpoint-reuse-20261009`](../checkpoint-reuse-20261009/README.md).
The baseline is commit `ef6e0144f`. Both compiler executables use ReleaseFast;
the programs they produce use optimized debug. Runtime C remains at O2.

## Changes

Retained checked bodies now preserve proofs for source locations outside their
own declaration. A referenced original file must still have the same unique
path, length and byte digest before its old merged interval can be relocated.
This covers locations inherited from record defaults. Parser spans extending
three bytes beyond the saved declaration can also relocate after those exact
trailing bytes compare equal. Existing dependency, identity, shape, effect and
mutation checks remain authoritative. The semantic cache format is now v4.

Structural-record and specialization retention remain conservative, and
declaration collection still runs. The paired measurements below quantify
how many additional checked bodies are retained.

Intermediate artifacts now use `stages-packed-v1`. Complete checksummed records
are appended to a session journal and published under a shared sequence lock.
After about 4 MiB of published records, the journal is automatically sealed
into packs after releasing the publication locks. A single oversized record
can exceed this threshold. I/O failure preserves the journal for recovery;
allocation failure remains explicit. Packs have separate independently
compressed blocks: up to 256 KiB for small records and 64 KiB for bodies. Records
larger than a block occupy their own block. Records of at most 4 KiB are
separated from larger bodies so metadata lookups do not automatically decode
those bodies.

Blocks use portable standard-library zlib/deflate, with a raw encoding for
incompressible data. A decoded-block cache retains at most 16 MiB. Reads validate
compiler identity, index bounds and checksums, the selected compressed block,
record framing and payload checksum. File identity and modification checks keep
cached blocks from concealing deleted or damaged files. A successful build
flushes packs before recording its whole-build replay receipt.

The existing stage report remains v3. The enclosing JSON cache report gains an
optional `storage` object with final flush time, success, and packed read/decode
counts. Final partial-flush time is separate from the stage intervals; automatic
sealing is included in the stage that triggers it. All CLI wall measurements
include both.

Old loose stage caches are not migrated or removed. Disk comparisons use one
successful build starting with empty project and native caches, excluding the
source, output executable, logs and shared installed compiler/toolchain.

## Validation and measurement

The paired timing harness is
[`compare.py`](../checkpoint-reuse-20261009/compare.py). It generates reachable
EDA replicas, uses identical absolute paths and edits for both compilers,
alternates their order, and keeps their caches separate. Native caches start
from validated original cold objects. Setup is excluded from edit medians.
Each measured build runs every replica, verifies EDA export hashes and leak
checks, and compares edited native objects and executable allocated sections.

[`summarize.py`](summarize.py) adds frontend work counts, rejection reasons,
pack-flush time and decoded/read bytes to the earlier stage summary.
[`single_build_cache.py`](../checkpoint-reuse-20261009/single_build_cache.py)
measures logical bytes, allocated disk blocks and file counts after exactly one
empty-cache build; it now also records GNU time's peak RSS and filesystem I/O
counts. Journal sizes are sampled every 100 ms. These observations can miss
short-lived files and are not strict maximum-size guarantees.
RSS is GNU time's maximum process RSS, not the sum of simultaneous compiler
and native-worker memory.

[`cache_recovery.py`](cache_recovery.py) damages real compressed packs before
launching a new compiler process. It covers whole-pack deletion, index
corruption, and body-block corruption with small metadata blocks preserved.
Repaired binaries and leak-checked execution must match an empty-cache oracle.
It records actual eager fallback counts; early misses are not mislabeled as
post-admission recovery.

The full `zig build test fmt-check -j2 --maxrss 8589934592 --summary all`
run passed all 93 build steps and 2,315 executed tests, including the automatic
sealing allocation-failure test. The large skipped count in the build summary
comes from dividing compiled test roots into shards. See
[`validation.json`](validation.json) and [`tests-final.log.gz`](tests-final.log.gz).
All 88 whole-tree Guardian checks passed without changing policy or baselines.
The final executable also passed all three recovery scenarios in
[`cache-recovery-bounded.json`](cache-recovery-bounded.json); body-block damage
exercised two actual eager fallbacks.

Reproduction uses the pinned Zig `0.17.0-dev.1683+5ceec001b`, a ReleaseFast
compiler executable, and optimized-debug guest builds. The final executable's
SHA-256 is
`c1450bf0caa9a90541f894a532854a7204adcd98a1c3005b004a4d074bfb2e7b`;
the baseline executable's SHA-256 is
`3bb9d1b2c2c15056334a9577e966c984782a8b33aae83f5c3137756efbbea518`.
The JSON reports retain exact commands, paths, CPU affinity, compiler hashes,
work counts, and validation results. The EDA source/dependency/golden fixtures
and original native seed are external inputs referenced by the harness. The
191k and 510k workloads are reachable EDA replicas, not independent applications
of those sizes.

## One-build cache size

Allocated disk space, starting with every project and native cache empty:

| Source lines | Previous cache | Packed cache | Reduction | Previous files | Packed files |
| --- | ---: | ---: | ---: | ---: | ---: |
| 191,416 | 1.217 GiB | 0.379 GiB | 68.8% | 89,589 | 15,929 |
| 510,436 | 3.234 GiB | 1.008 GiB | 68.8% | 237,589 | 42,377 |

See [`cache-size-summary.json`](cache-size-summary.json) and
[`single-build-bounded.json.gz`](single-build-bounded.json.gz). These totals
include frontend, semantic, stage, program and native caches after one build;
there is no revision history in either comparison. All golden exports and
leak-checked execution passed at both sizes.

The candidate cold runs took 255.0 and 500.1 seconds, with peak RSS of 2.44 and
5.23 GiB. Native compilation accounted for 218.9 and 369.2 seconds. These are
unpaired measurements on a shared host, not evidence of a cold speedup. This
change does not claim a substantial reduction in cold peak memory.

Sampled journal maxima were 41.63 and 40.96 MiB. Both are single-artifact-sized
exceptions to the 4 MiB sealing trigger; normal batches are sealed during the
build. No multi-gigabyte journal accumulated. The final partial flush took less
than 0.1 seconds at each size; packing during stage execution is also included
in the reported wall time.

## Paired incremental results

Three fresh edits per phase, alternating compiler order. Times include automatic
packing, the final partial flush, and linking; setup is excluded. These are the
combined frontend and storage changes, not an isolated compression A/B test.
The machine was shared and timing variation was large, so the disk and work-count
results are stronger evidence than the timing percentages.

| Lines | Edit | Previous median (range), s | Candidate median (range), s | Median change |
| --- | --- | ---: | ---: | ---: |
| 191,416 | entry | 4.59 (4.14–5.83) | 4.70 (4.16–5.81) | +2.2% |
| 191,416 | helper | 4.15 (3.38–5.23) | 4.49 (4.38–4.70) | +8.3% |
| 191,416 | three files | 6.52 (5.46–7.78) | 7.65 (7.35–7.85) | +17.4% |
| 510,436 | entry | 17.52 (10.56–22.67) | 13.97 (11.43–15.56) | -20.3% |
| 510,436 | helper | 10.76 (9.69–16.44) | 9.91 (9.01–10.18) | -7.9% |
| 510,436 | three files | 9.68 (7.49–17.17) | 9.80 (8.32–13.06) | +1.2% |

Positive changes are slower. Packing adds decoding work, while reducing file
count and disk traffic. The 191k workload was 2–17% slower in this run; at 510k,
entry/helper medians improved and the three-file median was approximately
unchanged. This is not a uniform speedup. All three 510k candidate medians were
below 15 seconds, but one candidate sample reached 15.56 seconds; a 15-second
maximum is not established.

Incremental peak process RSS was about 0.495–0.498 GiB at 191k and
1.292–1.295 GiB at 510k, compared with 0.500–0.503 and 1.312–1.318 GiB for the
baseline: roughly 1–2% less, not a large RAM reduction.

On entry edits, checked frontend bodies fell from 1,106 to 651 at 191k and
2,946 to 1,731 at 510k, about 41%. Newly stored checked bodies fell from
458 to 3 and 1,218 to 3. Helper and three-file edits show comparable checked-body
reductions. Raw/final IR materialization counts were unchanged: 628/807/991
bodies for the three 191k edit phases, and 1,668/1,847/2,031 at 510k. Each
single-file edit compiled one native unit; each three-file edit compiled three.
No normal-build eager fallback occurred.

All 40 builds, including the four setup builds, passed replica execution,
export-golden and leak checks. Each paired executable had identical allocated
sections, and the changed native objects passed instruction, literal, DWARF
and trap-descriptor equivalence checks. See [`paired-summary.json`](paired-summary.json)
and the full records in [`paired-bounded.json.gz`](paired-bounded.json.gz).
Earlier prototype/tuned archives are retained for investigation; they are not
the final implementation's measurements and several overlapped heavy I/O.

## Codec experiment

[`codec-comparison.json`](codec-comparison.json) and
[`codec-normal-comparison.json`](codec-normal-comparison.json) compare portable
deflate with system zstd level 1 on sampled real stage records. In the normal
block sample, compressed size was 30.18% for deflate and 24.13% for zstd; random
block decoding was approximately 333 versus 1,299 MiB/s. These are codec-only
measurements, not build times. Production uses portable deflate without adding
a system-library dependency. The standalone benchmark uses raw deflate, while
production adds zlib framing.

The accompanying sampling and benchmark programs retain the original artifact
paths used for this experiment. Generated input blobs and executables remain
outside the repository.

The direct-output decoder avoids a separate history buffer and copy. On 111
real blocks with shuffled lookups, three alternating-order runs measured a
4.1% median decoding improvement, or 6.7% with fresh output allocations. See
[`codec-direct-comparison.json`](codec-direct-comparison.json). The production
decoder rejects short, oversized, trailing and overflowing outputs; tiny
compressed outputs and allocation failures are regression-tested.

## Remaining work

This change removes source-relocation misses, not every frontend operation.
Declaration collection and global semantic passes still run; summaries still
cover many unchanged bodies, and record identities and specializations can
still prevent checked-body retention. The raw and optimized IR demand rules
are unchanged.

Packs reduce file count and disk allocation but add decompression work. A read
can still decode neighboring records in its block. Metadata blocks, program
catalogs and index scans remain opportunities for smaller reads. The new
physical-read, decoded-byte, returned-payload and block-hit counters make that
remaining cost visible.

This is storage for newly produced stage artifacts. Semantic and frontend
caches retain their existing layouts, and obsolete revisions and legacy loose
stage directories are not garbage-collected. Single-build measurements must not
be interpreted as a bound on cache growth over many revisions.
Each process still indexes all compatible packs, so accumulated history can
also increase startup work and catalog memory. Compaction and garbage
collection remain separate follow-up work.
