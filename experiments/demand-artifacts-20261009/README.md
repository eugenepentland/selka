# Demand-loaded compiler artifacts

This experiment targets work performed after small edits in optimized-debug
builds. It compares against the completed selective-function-reuse compiler in
`../demand-builds-20261009`, not the older standard-debug compiler. Runtime C
optimization remains O2.

## Results (2026-10-09)

These are medians of three distinct edits per case, comparing the previous
optimized-debug compiler with this prototype. All 18 candidate edit builds
completed without cache recovery. No guest release builds were measured.

| Lines | Edit | Build seconds, before → after | Time reduction | Peak RSS GiB, before → after | RSS reduction |
|---:|---|---:|---:|---:|---:|
| 191,416 | entry | 6.40 → 3.87 | 39.5% | 1.223 → 0.499 | 59.2% |
| 191,416 | helper | 5.03 → 3.08 | 38.8% | 1.225 → 0.503 | 59.0% |
| 191,416 | three file | 6.33 → 4.25 | 32.8% | 1.222 → 0.502 | 58.9% |
| 510,436 | entry | 13.69 → 8.98 | 34.4% | 3.247 → 1.311 | 59.6% |
| 510,436 | helper | 13.13 → 8.14 | 38.0% | 3.250 → 1.314 | 59.6% |
| 510,436 | three file | 14.20 → 9.01 | 36.6% | 3.252 → 1.314 | 59.6% |

For the 510,436-line fixture:

| Work per edit | Previous compiler | Entry edit | Helper edit | Three-file edit |
|---|---:|---:|---:|---:|
| Raw IR bodies materialized | 23,597 | 6,920 | 7,052 | 7,189 |
| Final optimized bodies materialized | 23,597 | 6,920 | 7,052 | 7,189 |
| Full LLVM emission keys constructed | 2,020 | 1 | 1 | 3 |
| Native units compiled | 1 / 1 / 3 | 1 | 1 | 3 |

**The body-count and memory targets are met. The full 50% build-time reduction
is not:** median time savings are 33–40% across the two sizes. All nine measured
510k edit builds stayed below 15 seconds (8.06–14.28 seconds). The first edit
after cache setup was the slowest: 22.70 → 14.28 seconds; it is included in the
entry-edit median. Three samples per case on a shared host are not a latency
guarantee for arbitrary applications or edits.

Native compilation already compiled only one unit for one-file edits; the old
2,020-unit cost was inspecting/hashing/loading all LLVM units. The new compiler
still visits compact metadata and verifies native object checksums for all 2,020
units. For a helper edit, 2,019 use handles and only 66,220 LLVM bytes are copied
into emission output buffers. A native unit is a source module or specialization,
so the changed source module can still contain unchanged functions.

The remaining time is primarily frontend work and the optimizer: the 510k
helper-edit stage medians are 3.16 s frontend, 0.39 s lowering, 3.99 s optimizer,
0.20 s emission and 0.28 s native work. Individual medians do not add exactly to
the wall-time median. The remaining 7,052 bodies include the heavier inlining
and fusion cases, which still traverse ordered stage caches. Whole-program
declaration, dependency, parameter and effect metadata is still processed.

Fresh intermediate-cache setup remains expensive and is **not halved**:
the 510k setup was 98.98 → 94.33 seconds and 4.73 → 4.78 GiB. Those setup
runs reused validated preseeded native objects, so they are not fully cold
native-compilation measurements.

The paired run checked 20 executable pairs: all allocated ELF sections matched.
All 30 edited native-object pairs were byte-identical, including DWARF and trap
descriptors. All 40 builds passed execution, EDA export golden-hash and leak
checks. Whole executable bytes differ only in the allowed runtime-worktree
debug information described below.

Validation passed all 93 steps of `zig build test fmt-check --summary all`
(2,286 executed tests in the final run; unchanged cached steps also succeeded)
and all 88 whole-tree Guardian checks. The optimized CLI cache-loss test proved
zero-recompile native reuse without LLVM, one successful eager repair after native
object eviction, and a subsequent zero-fallback build with identical executable
bytes and execution. No Guardian policy, suppression or baseline changed.

Evidence: [validation.json](validation.json), [summary.json](summary.json), [full records](results.json.gz),
[cache recovery](cache-recovery.json), and the compressed logs under `logs/`.
The benchmark compiler SHA-256 is
`9a853e8c380e9c5888003abb7d6fb2264347bb535cea2ba9b8d59f77c81e7d7c`.
The source is kept on `codex/demand-artifacts-20261009` in an isolated worktree.

## Changes

- Raw lowering artifacts now have compact discovery headers. Replaying a header
  restores declaration/type/string discovery without decoding the function's
  instructions. The optimizer requests a body only when it needs to inspect it.
- Unchanged optimizer artifacts carry compact dependency, effect and final-output
  metadata. Reusable final bodies and analysis are loaded only for LLVM units
  whose cached output cannot be reused.
- LLVM cache receipts avoid rebuilding full body-based emission keys on unchanged
  units. Receipts bind source files, layout, dependencies, analysis and renderer
  metadata; the existing exact LLVM artifact keys remain authoritative.
- Verified native objects can be linked through compact artifact handles without
  loading their LLVM text. The mapping preserves the original native key and all
  tool, CPU, mode and runtime ABI guards; object checksums are still checked. LLVM
  is loaded only on an object miss or explicit verification.
- Loop IDs are local to each function, removing false invalidation when an earlier
  function gains or loses loops. Callable summary identities distinguish matching
  schemas and include return-origin information.
- Effect path sets have a deterministic order after analysis. Cold and seeded
  incremental worklists can discover the same set in different orders; those
  orders previously changed both cache fingerprints and generated field-store
  order. The regression checks set equality as well as serialized equality.
- Missing or invalid deferred artifacts trigger one conservative retry. The retry
  repairs metadata so subsequent edits can return to the demand-loaded path.

## Meaning of the work counters

`lowering.materialized` counts freshly lowered plus restored raw function bodies.
`optimizer.final_loaded` counts optimized bodies materialized in memory, including
bodies loaded during emission. `emission.work.keys_built` counts full LLVM keys
constructed after compact receipt misses. Native `compiled` counts units actually
sent to the native compiler. `emission.work.llvm_loaded_bytes` counts LLVM text
bytes copied into emission output buffers, including freshly rendered text;
`native_handles` counts deferred native units. This byte count excludes helper
symbol seed scratch and any later driver reload following an object or mapping
miss. It is not a count of total disk reads or peak live memory.

These are different kinds of work. Lightweight declaration, dependency and cache
metadata still covers the wider program. Native compilation was already one unit
for a one-file edit in the previous compiler; this change targets the work needed
to establish that the other units can be reused.

## Measurement method

The adapted `./compare.py` harness uses identical source
paths, alternating compiler order, separate caches and three distinct edits of
each kind. Its 12- and 32-copy fixtures contain 191,416 and 510,436 physical lines
of reachable EDA code. Every replica is called, and each sample checks execution,
export golden hashes, leaks and paired native output.

Both host compilers use ReleaseFast. Guest builds use optimized debug and four
native workers on reserved CPUs 2,3,10,11. Fresh intermediate-cache setup is
excluded from edit medians and uses validated original native objects; it is not
a measurement of a completely cold native build. Peak RSS is GNU time's
largest-process high-water mark, not simultaneous aggregate worker memory.
The stage timers are useful for locating remaining costs but are not all directly
comparable: the candidate charges demand-loaded raw bodies and final effect
analysis to optimization, while the baseline loads raw bodies during lowering
and computes final effects between its optimizer and emission timers. The primary
speed comparison therefore uses complete build wall time.

`binary_audit.py` checks that every allocated ELF section matches between paired
executables, including machine code, literals, data and unwind information. The
host compilers were built in different worktrees, so runtime source-directory
strings in DWARF differ. The audit allows differences only in debug sections and
requires differing debug strings to be those runtime paths. The existing native
object audit separately checks edited guest objects, including their debugger
and trap metadata. This does not claim whole-executable byte identity.

`./summarize.py RESULTS` reports work counts separately from cache reuse counts.
`./cache_recovery.py --compiler COMPILER --output NEW_DIRECTORY` checks actual
CLI recovery after removing raw/final/LLVM artifacts while preserving lowering
headers. It first proves verified native objects remain usable without LLVM,
then evicts native objects to force recovery, and checks that the following build
needs no fallback.

## Limits

This is a modular scaling fixture, not an independently developed half-million-
line application. Changes to declarations, types, call graphs or effects can
invalidate larger regions. Raw demand keys conservatively bind the owning source
file, so a large single-file edit may require loading many bodies in that file.
The fast path is limited to ordinary optimized-debug builds; explicit full IR
output, verification modes and instrumentation retain their complete analyses.
