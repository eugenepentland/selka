# Closing incremental frontend and IR reuse gaps

This follows the packed-storage and frontend work merged into `main` at
`1ab0d92e7`. Both sides compile optimized-debug guest programs; runtime C
optimization stays O2. The comparison explicitly disables stage compression
(`MYLANG_STAGE_CACHE_COMPRESSION=none`) on both sides.

## Changes

In the demand-loaded optimizer, unchanged recursive functions can retain their
artifacts. A receipt checks the ordered callee return summaries at the exact
point where the eager optimizer would read them. Record-bearing programs also validate both field
analysis rounds and final field/parameter bounds. A changed or missing proof
conservatively restores the appropriate checkpoint and recomputes. This removes
the unconditional invalidation of recursive components and all their callers.

Functions transformed by fusion retain portable post-fusion checkpoints. Reuse
also checks the exact sequence of helper-creation requests, including repeated
requests, so it preserves eager helper declaration order. A changed sequence
uses the one-shot eager repair path. Tests include reordered slice producers
whose final call inventory is unchanged.

Raw-body reuse proves the current declaration position and exact source prefix
through the greatest local source offset, alongside the semantic body key and
full declaration catalog. An edit later in the same file therefore need not
invalidate an earlier body. Nonlocal source dependencies remain conservative.
Emission receipts retain compact canonical inline ancestry instead of loading
unchanged bodies merely to reconstruct source provenance.

Frontend enum payload records now have qualified identities. Stored generic
references can preregister an instance through the normal bounded worklist after
checking the current template, exact declaration bytes, type arguments, provider
contracts, and fingerprint. Nested entries remain stable across retained-table
growth. Whole-graph effect and mutation propagation still runs. Unsupported or
ambiguous types fail closed. An allocation-failure test also covers cleanup of
a decoded specialization when reserving its retained-table slot fails.

LLVM literal pooling deduplicates exact byte strings in first-use order. This
makes native output independent of whether typed bodies were freshly checked
or decoded from an interned snapshot. It intentionally changes some native
objects relative to the previous compiler.

The semantic store is now `semantic-cache-v5` with `specialization-v2` payloads;
raw-header and emission-receipt formats also change. Older entries conservatively
miss, so the first build after updating must repopulate affected caches. The
incremental measurements below apply after that setup.

## Method

[`compare.py`](compare.py) generates reachable EDA replicas with 191,416 and
510,436 physical source lines. Both compilers receive identical source paths
and three distinct, length-changing edits per case, in alternating order. The
cases edit one entry body, one helper body, or three files. Every generated
module is imported and every replica executes.

Compiler executables use ReleaseFast. Guest builds use optimized debug and four
workers on reserved CPUs 2,3,10,11 while holding the shared timing locks. The
host still has independent background work; these timings are workload
measurements, not a latency guarantee. GNU time peak RSS is the greatest
individual process high-water mark, not simultaneous aggregate worker memory.

Frontend and stage caches start empty for each compiler. Validated native
objects seed setup to avoid repeating irrelevant native compilation; the report
records their provenance and checksums. Setup is excluded from incremental
medians and is not a cold-native build or a one-build cache-capacity measurement.

Every build checks replica usage, EDA export golden hashes, and leaks. Native
compilation must be exactly 1, 1, and 3 units for the respective edit cases.
Cross-version executable differences are diagnostic because literal deduplication
changes output layout. The candidate additionally performs an eager
`--verify-cache` build at 191k lines: it bypasses frontend, IR, optimizer, and
emission reuse, verifies all native units, and must produce the exact same
executable bytes as the incremental build. A follow-up forces a fresh link too;
the current harness includes that stronger check directly. Both verifications
are outside edit timings.

[`summarize.py`](summarize.py) keeps fresh lowering/optimization separate from
raw-body loads, final-body loads, and intermediate checkpoint decodes.

## Measured incremental results

Medians of three distinct edits, in seconds. Baseline is the merged compiler at
`1ab0d92e7`; candidate production behavior is `aff944405` (later changes update
schema fixtures, documentation, and the benchmark harness). Both use uncompressed
packed storage. Full samples and compiler hashes are in
[`results.json.gz`](results.json.gz), with compact counters in
[`summary.json`](summary.json).

| Lines | Edit | Before | After | Time reduction | Before / after peak RSS |
|---:|---|---:|---:|---:|---:|
| 191,416 | Entry | 3.711 s | 2.439 s | 34.3% | 0.566 / 0.572 GiB |
| 191,416 | Helper | 2.789 s | 1.759 s | 36.9% | 0.566 / 0.572 GiB |
| 191,416 | Three files | 3.883 s | 2.584 s | 33.4% | 0.568 / 0.572 GiB |
| 510,436 | Entry | 9.619 s | 8.377 s | 12.9% | 1.738 / 1.817 GiB |
| 510,436 | Helper | 11.440 s | 7.054 s | 38.3% | 1.737 / 1.818 GiB |
| 510,436 | Three files | 13.204 s | 11.211 s | 15.1% | 1.740 / 1.819 GiB |

All 18 measured candidate edits finish below 15 seconds; the slowest is
**12.444 seconds**. The 510k samples are noisy: candidate entry edits span
6.022–12.444 seconds and three-file edits span 5.383–12.215 seconds. Background
host work is recorded through load averages in the raw report. The result is a
measured improvement, not a hard deadline guarantee. No measurements from the
aborted trial with historical edited native objects in its seed are included;
the harness rejected that trial and the clean comparison used setup-only objects.

Peak memory does **not** improve: it is roughly unchanged at 191k and increases
about 4.6% at 510k. Fewer IR loads do not remove the frontend's live program and
retained-entry memory. The frontend remains the largest 510k phase, at median
3.918–4.916 seconds. Optimizer medians drop from 2.815–4.384 seconds to
0.534–0.558 seconds. Separate stage medians need not sum to median wall time;
the native interval includes linking.

These are populated-cache edits. With validated native seeds but empty
frontend/stage caches, setup takes 27.804/27.728 seconds before/after at 191k,
and 119.192/108.238 seconds at 510k. Setup is neither a cold-native measurement
nor below the 15-second edit target.

## Work counts

Each row's counts are identical across its three samples. A materialization is
not necessarily fresh lowering or optimization. Raw and final counters can refer
to the same logical function, so they must not be added as distinct functions.

| Lines | Edit | Frontend bodies checked, before → after | Raw bodies, before → after | Final bodies, before → after |
|---:|---|---:|---:|---:|
| 191,416 | Entry | 555 → 135 | 628 → 5 | 628 → 6 |
| 191,416 | Helper | 553 → 133 | 807 → 30 | 807 → 44 |
| 191,416 | Three files | 557 → 137 | 991 → 61 | 991 → 90 |
| 510,436 | Entry | 1,475 → 355 | 1,668 → 5 | 1,668 → 6 |
| 510,436 | Helper | 1,473 → 353 | 1,847 → 30 | 1,847 → 44 |
| 510,436 | Three files | 1,477 → 357 | 2,031 → 61 | 2,031 → 90 |

Fresh lowering, fresh optimization, LLVM keys built, and native units compiled
remain **1 / 1 / 3** for entry/helper/three-file edits at both sizes. Intermediate
checkpoint record decodes are **6 / 0 / 3**; fusion checkpoint restores and eager
fallbacks are zero. The residual IR counts stay flat when the replicated codebase
grows from 191k to 510k. This removes the unrelated recursive-component load
floor, while preserving the conservative dependency and emission work below.

## Remaining work

The remaining materializations are not all fresh compiler work. For the 191k
fixture, entry edits activate three optimizer functions (one freshly optimized,
two final-cache hits), inspect two additional green base bodies, and load three
green final bodies for emission. Helper edits activate 30 functions (one fresh,
29 final-cache hits) and load 14 emission peers. Three-file edits activate 60
functions (three fresh, 57 final-cache hits), inspect one additional green base
body, and load 30 emission peers. These are aggregate-counter decompositions,
not a trace identifying every individual function.

The helper's conservative work comes from the reverse raw call/reference
dependency closure. Emission still operates in source-module native units:
compiling one native unit can compile several unchanged peer functions. Reducing
those costs further requires finer dependency evidence and native-unit
granularity. A checkpoint counter counts decoded transform records, including
no-op aliases; it must not be described as that many complete IR body decodes.

The frontend still reconstructs and validates global declarations, replays syntax
and typed trees, and runs graph-wide effect/origin passes. In this EDA fixture,
11 ordinary bodies per replica conservatively fail retention: five first fail
an interned-record guard and six a function-value guard. These are body counts,
not counts of distinct unsupported types. All 19 concrete specializations per
replica now reuse their checked bodies after an unrelated edit. Removing the
remaining ordinary misses needs fresh, validated recipes for those structural
and callable types, including expected-slot contracts; trusting stored contracts
would be unsound.

Work counts can grow for edits to shared callees, changed parameter/field
intervals, or declaration/helper layout. A mismatched field receipt deliberately
demotes all still-green bodies for that exploration, and an incompatible helper
creation sequence or missing artifact can require eager recovery. Results on
independent reachable replicas do not establish constant work for arbitrary
dependency graphs.

## Validation evidence

The final `zig build test fmt-check -j2 --maxrss 8589934592 --summary all`,
through the normal shared gate slot, passes **97/97 build steps** and **2,462
executed tests**. All 28 Guardian test-runner records report zero failures. The
22,611 skips are tests not selected by each individual shard. The first run had
two outdated CLI cache-format fixture markers; both were corrected and the
complete final suite passes. The full static Guardian commit gate passes all
**88 checks**. Machine-readable validation and artifact hashes are in
[`validation.json`](validation.json).

The focused optimizer suite passes **18 tests**, comparing cached and eager Core
IR, LLVM, facts, ownership/vector plans, pass counts, and debugger ancestry. It
covers both record-bearing and record-free recursion, changed DFS return inputs,
missing receipts, and changed helper-creation order. Frontend suites pass **77
cache tests**, **15 semantic-project tests**, and the decoded-entry allocation
failure regression. The **10 C2/C3s CLI tests** also pass after updating their
fixture directory/key markers for the new cache formats.

All **41 benchmark builds** pass replica usage, export golden hashes, and leak
checks. Edited native objects are byte-identical between compiler versions in
every measured case. The initial eager verification regenerates all **760 native
units** but reuses the linked-program cache. A separate follow-up moves that
program cache aside, regenerates and verifies all 760 units again, and forces a
fresh link. It reports `program=linked`, `verified=760`, `compiled=0` (zero native
cache misses), and 761 native/linker processes. The freshly linked executable is
byte-identical to the incremental executable and again passes usage, exports,
and leak checks. Both the initial 138.685-second verification and the follow-up
136.671-second verification are excluded from edit medians. The follow-up report
and exact script are also archived in [`evidence/`](evidence/).

The one-replica frontend probe uses `check-session` with a **128 MiB semantic
retention budget**, so budget eviction does not obscure type-remapping misses.
After the cold check, an entry-body edit checks 12 bodies and a prefix-only edit
checks 11; each reuses all 19 concrete specialization bodies. Its counters are
cumulative where indicated by the check-session schema. The exact probe and
output are archived under [`evidence/`](evidence/), alongside the focused tests,
successful compiler build, and whole-tree Guardian commit gates. No policy,
suppression, or ratchet baseline was weakened.
