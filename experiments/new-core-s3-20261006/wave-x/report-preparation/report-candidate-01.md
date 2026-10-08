# S3 §7 exit report — candidate, final X pending

**S3 exit status: PENDING.** All implementation packages, including the final
application composition, have qualified. ROOT has integrated the A handoff at
`5ee5b8d2e1d1c697a98dfa590cbeda704ed7ae55` and completed fresh merge
qualification. Final S3-X receipts remain pending. This candidate neither
claims the final matrix has passed nor authorizes S4. Replace the marked fields from actual retained
receipts before publishing the exit report.

The work implements the [S3 plan](../../../../docs/audits/new-core-s3-implementation-plan-2026-10-06.md)
from S2 foundation `92590700cb0bf5e4dc19cc1f0c836c3a41693f64`. It admits the
remaining S3 text/number/byte surfaces, capabilities and resources, the property
runner, recursive values and aggregate operations, concrete generics, standard
library imports and all five application workloads. The default compiler remains
the old core until S5. User modules, persisted per-module compilation, the Lox
port and an EDA slice remain the S4 decision.

The complete remaining-bound/refusal inventory is
[limits-final-candidate.md](limits-final-candidate.md), supported by the linked
source audit. This report records qualification and scope; it does not duplicate
that inventory.

## Final exit receipts

Completed ROOT merge prerequisites below are actual executions on the frozen
integration. Every PENDING result is a required final record, not an inferred
pass from an earlier package. Final checks must identify the same frozen
compiler inputs and explicit oracle pair, retain unique command logs and inspect actual statuses,
stdout, summaries, shard verdicts, diagnostics and RSS.

| Required final record | Result / identity | Retained final receipt |
|---|---|---|
| Frozen ROOT qualification/matrix HEAD | `5ee5b8d2e1d1c697a98dfa590cbeda704ed7ae55`; final matrix must preserve it | [source freeze](../integration/final-source-freeze-run01.json) |
| Own-source installed ROOT Core | `zig-out/bin/mylang-core`; SHA-256 `05e5206c53b853ff8855d547784cec0ae8c0587da3dbd5b0e02eb0eb2744721c` | [merge qualification](../integration/final-merge-run01/summary.json) |
| Explicit corrected old/QBE pair | `.mylang-cache/s3/oracle/{mylang,qbe}`; unchanged d366/b613 SHA-256 pair below; final matrix rechecks both | [source freeze](../integration/final-source-freeze-run01.json) |
| Uncontended own-source Core rebuild | 1.79 s actual compilation; all build slots and gate exclusion; admission recorded separately | [install log](../integration/final-merge-run01/install-core.log) |
| Held full Core64 gate | 276/276; 64 native verdicts; 68/68 steps; 134.76 s, max shard 51.67 s; peak test RSS 251 MiB, no overrun | [Core log](../integration/final-merge-run01/test-core.log), [inspection](../integration/final-merge-run01/summary.json) |
| Full ordinary debug/release language conformance | PENDING; each 1518 selected, zero mismatches/refusals | PENDING |
| Full leak/fact-verify conformance | Debug and release each 1518 matches, 0 mismatches/refusals; status/stdout/reasons checked; 61.20 s | [strict conformance](../integration/final-merge-run01/full-conformance.log) |
| Full old-core `test`, `test-qbe`, `test-qbe-build`, `fmt-check` record | PENDING final X record; A's actual four-step frozen-source pass is below | PENDING |
| All40 fresh performance, sizes 4096/64 | 40 rows/80 cells, zero misses; seven rounds/three startups on locked CPU10; 3200 raw samples | [final performance](../integration/all40-final-run01.json), [command log](../integration/all40-final-run01.log) |
| Fresh all 40 natural-loop/count/call audit | PENDING; full40-row table, LLVM/assembly and scope evidence | PENDING |
| Strict nine-kind ×200 matrix | PENDING; 1800 accepted sources, 25800 comparisons; each raw outcome retained | PENDING |
| Supplementary split-key200 | PENDING; 200 accepted sources, 3000 comparisons; does not replace a matrix kind | PENDING |
| Asset-preserving four-corpus before/after coverage | PENDING; four child statuses, every remaining name/reason and frontend failure | PENDING |
| Exact execution-exception inventory | 118 retired-arena + 9 S4 names, 127 total, regenerated on frozen ROOT | [final inventory](../integration/exceptions-final-run01.json) |
| Frozen compiler/test inputs and representation | No `src`/`test`/`tests` difference from A203c; frozen IR/ownership unchanged; package formats/masks preserved | [source freeze](../integration/final-source-freeze-run01.json) |
| Main/S2 refs, no pushes, clean final tracked tree and evidence commit | PENDING final verification | PENDING |
| Serialized Guardian feedback commit | PENDING coordinator commit | PENDING |

## Source and package authority

Wave A's reviewed handoff is `3d0bfd23b73b3a90bd6ce8af4caa8fcba18a51b2`.
The user then authorized continuous B/C/X work. Bootstrap
`8918de74720f0832dabe5802c110cd0518324cf5` changes default Core sharding from 4
to 8. Reviewed semantic decisions are
`e50e508a4c4da2aefb69e0bcc0ed39f0b855b9f4`. Most Wave B branches start at the
bootstrap; the runner forks C source `722fe485165028ce04480c52791c5dc7b4cacfe3`.
A's workload foundation is `ac81831bd9e6100bf8d31cc07ca97bcff9f82d6c`.

| Package | Frozen source | Qualification/evidence handoff | Integration merge |
|---|---|---|---|
| S3-0 | `dc1a583109be06c3e699a433be24cbcd6e5d3816` | `643858e3da7b1e3a2c4f31b1a13430ab3906cd0e` | `e39ad11d3b2d95d537b1526f7e4abfb4b0feeb76` |
| S3-L / D2 | `225bee07da44dc57ae322d3b6c1f0f68aebb404f` | Same source/qualification commit | `f5ba28e585a7c06cb80dc6c81b96fa946c55ad2a` |
| S3-T1 | `ade0ce29d743aa5168ce14417e2aee6bb11a11f6` | `0b48e921766b31dc70a8f1b66374bb8c7973bc5c` | `2e4f0f512a6d8a1f5df70602861890360ee6e2ec` |
| S3-T2 | `52a9e1ef8ca00775a5d4ac1e24b6f920eacf9766` | `5d2849ff54351cfa03d6797c6454ca376274ce7f` | `fb9bff998fb1d31f056ad0fe0ace9230bd033391` |
| S3-C, combined with M/runner | `9637eb9a1aa4af8ee0ecd88838ceed09b228d812` | `6bac5b165b1f526127c93dcc1dbd157b0ed6334d` | `f1319a774d638c664de9f02bb27098650a13249b` |
| S3-C runner | `d54e3dae0b477255841a23d3207f2d458aa42057`; final dependency source `9637eb9a1` | `e69c9f9855ff0d00877f3f279c640a1d3551aa64` | Included in C merge `f1319a774` |
| S3-M | `93030b84e1538abc35aefa6984e3b00cc7dcc958` | `d5be46e4719596080683e87e0638967a3301a6d8` | `da321c5711dff87fc5bc5aca9fca072647847025` |
| S3-A, final combined compiler/runtime | `203c0ca6100344304cbd9fd20d22cc7f9448a145` | `80fa132ad1bf5d1e5519ed9f3fb0ff65685651f6` | `5ee5b8d2e1d1c697a98dfa590cbeda704ed7ae55` |

The A repair composition is explicit:

| Repair | Source | Qualified handoff | A composition |
|---|---|---|---|
| Private whitespace/key fusion and scalar dictionary stores | `db19c8c8ddea8c0f053b5b2b1da35cd4438c1af4` | Same source/evidence commit | Word/packet merge `9bebd05b768fe102f649bac51b5dedb2aa47a216` |
| Trusted byte-index normalization | `1c3e53fd40c0ca4c16d67d09048e6ec5afbd349c` | `d8921b419c2bf3aa0932a728bc7a3f9cf0344f3c` | Merge `9bebd05b768fe102f649bac51b5dedb2aa47a216`; combined evidence `958e988a2f6ff98a0b4c5b004c49c567d8e62f8c` |
| Scalar character consumers/direct append/guarded ASCII | `3f47456ce70a4d2365fe1107123bf59a894fd859`; test-only shard distribution `c7673da2fd7819242e4c86fe973f05c8a1d18486` | `0ecd89913b6ab4ce8490f280647906cc316804fd` | Merge `0a5dd8794faaf330ab411900d1eaf4e2a00ba0e8` |
| Bounded trusted cursor emission | `8d1e135a885b6d19eb68a71313dc5a89dd35c557` | `33dc1323915592f938a56217815a360723489566` | First parent of final combined source `203c0ca6` |
| Preserving constant-action error trace ABI | `2880b5001d843ce7b277ab3c13f1190efccb5d69` | `fb9f72c6da4c0d5e24b429c3e307d5518046003f` | Second parent of final combined source `203c0ca6` |

Primary reports are [Wave A](../../wave-a/REPORT.md),
[T1](../../wave-b/s3-t1/README.md), [T2](../../wave-b/s3-t2/README.md),
[C](../../wave-b/s3-c/REPORT.md), [runner](../../wave-b/s3-runner/REPORT.md),
[M](../../wave-b/s3-m/REPORT.md), [A](../../wave-c/s3-a/REPORT.md),
[byte repair](../../wave-c/s3-packet/REPORT.md),
[character repair](../../wave-c/s3-char/REPORT.md) and
[trace repair](../../wave-c/s3-packet-trace/REPORT.md).

### Corrected old oracle

The approved `ENV-NAMES-GRANT-1` correction is
`4747ad071803589f99137d2ecf7641203120e09f`, qualified at old source
`65036fe792ef540392d0eb00c41c9ec71c7b2c82`. The original runtime incorrectly
used a provider's opaque callback context as a name list. The corrected old and
new cores use parsed grants; a controlled three-name process fixture returns
all three names without a grant allowlist and only `A`, `B` under
`--allow-env=B,A`, with and without `--restrict`. The callback still receives
its private context unchanged. The accidental old answer1 is retained as
rejected historical evidence, never an oracle target.

The frozen corrected pair is:

- Old compiler SHA-256:
  `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`.
- QBE SHA-256:
  `b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`.

[The original oracle receipt](../../wave-b/s3-c/resume-context-corrected-oracle.json)
records its clean full gate04:138/138 build steps, 3522/34118 tests, 30596
intentional skips, exit0 and clean RSS inspection. That gate qualifies the ENV
oracle, not later runner/SPEC/manifest changes. A's later complete old gate is
recorded separately below. Final X must retain its actual paths and hashes.

A's own-source compiler SHA-256 is
`c3aaee87434f185a21970f76e94b655503c1e69561884a15098787ee46cca1bc`.
Its [final qualification manifest](../../wave-c/s3-a/qualification-final-01.json)
pins source inputs, compiler/oracle pair, original reference workload
sources/binaries, 80 measured old/new binaries and 40 freshly emitted LLVM
modules. Reference algorithms remain at `runtime-baseline-20261003`, source
`9e126b553353148b955add3ac1eb5b710a9b8e7f`; no reference algorithm, input
work or checksum was changed to obtain a passing ratio.

## As-built behavior and package qualification

S3-0 freezes three new counted pointer types, nine operations and trusted
`runtime_c` linkage. D2 rejects stored dictionary projections at declarations
and storage, permits immediate consumers, hashes key membership and scans
value/item membership. Only S3-L changes `tests/lang`, replacing impossible
held-view cases with explicit snapshots/immediate operations and rejection
checks.

T1 ports the old text grammar and algorithms, preserving Unicode scalar
indices for text, octet indices for bytes, negative/range/step behavior and
ASCII case/classification. T2 adds independent mutable byte buffers, source
blobs and the old Zig float-text algorithm. Scalar `Option[int/float]` returns
use the qualified internal x86-64 SysV runtime ABI; source `extern` still
requires a first erased Host followed by scalar arguments and scalar/unit
results. It admits no general pointer, aggregate, Option or variadic source ABI.

M uses structural descriptors and iterative equality/hash worklists, ignoring
padding while preserving sharing, nonreflexive NaNs, signed zero and active
variant payloads. Separate source rendering descriptors preserve nominal names,
domains, Unit spelling, exact payload presence and set/dictionary distinction.
Only exact compiler-owned `runtime_c` declarations authorize descriptor indices
or structural adapters: forged literal/blob markers and foreign name lookalikes
carry no authority. Canonical physical Unit placeholders cover stored fields,
array/list elements and dictionary keys; Unit locals remain payloadless across
SSA joins. These internal storage choices do not admit Unit-containing Host
transport graphs.

Captured mutable places preserve selected values and evaluated keys in source
argument order. Executed whole-root writes supersede publication, sibling writes
preserve it, same-place calls reread the current binding, and conditional and
reordered keyword calls preserve selection order. Eight formerly refused cases
are included in the 41 existing mutation cases. The two precise initial-index
and later-interior-ancestor refusals remain in the limits inventory; no pin
protocol is inferred from a callee body or equal leaf pointers.

C owns authority, scoped provider state and counted resources in the independent
Core runtime. Completion/lexical exits/final drop/fatal cleanup release each
external handle once. Test I/O uses private directories and deterministic
stand-ins, with no real network reads. The property runner preserves actual
trial generation, name-derived seeds, discards, shrinking, complete reasons,
Result grading, retry accounting and native signal/silent-exit behavior; each
actual trial forks and resets stand-ins. Its `processes` field counts outer
batch launches, matching the old report, rather than pretending to count every
trial child. Measured scalar trial cost is 11.81 ms at default 100 trials and
104.40 ms at 1000, excluding compilation.

A admits the checked whole-program `strings`/`json` import graph and five literal
application extractions. Its profile-driven optimizations are generic:
source-rooted whitespace/key cursors with owned insertion keys, exact small-table
span probes and scalar stores; authority-limited byte normalization; all-use
scalar comparison/append fusion with checked producer diagnostics, alias-safe
short copies and guarded ASCII decoding; bounded trusted cursor loops; and exact
preserving trace twins. Escape/foreign-call/unsupported-use near misses retain
ordinary materialized/runtime paths. Producer checks and verified ownership/fact
premises remain; ordinary source extern spellings do not grant optimization
identity.

| Completed package evidence | Qualified result |
|---|---|
| T1 source `ade0ce29` | Core221/221 at 70.17 s/max 68.20; rebuild 1.75 s; extended text50/750 exact comparisons; original35 definitions identical; five affected rows pass both gates |
| T2 source `52a9e1ef` | Core226/226 at 67.45 s/max 65.81; meaningful rebuild 2.60 s; number50/750 exact comparisons; original35 identical; affected rows pass both gates |
| C/M/runner source `9637eb9a1` | Core254 at 127.03 s/max 68.26; rebuild 3.30 s; 1518/1518 each mode, zero mismatch/refusal with leak/fact checks; 37 provider checks; 24 complete property/runner report matches |
| Standalone final M `93030b84e` | Core234 at 82.36 s with corrected slots; rebuild 1.79 s; s0/s1/functions50 each, 2250 comparisons total; exact35 definitions; final Unit-local focus closes prior mismatch |
| Character source `3f47456ce` | Core261 at 124.82 s/max 65.42 after unchanged-case test distribution; rebuild 1.72 s; 1518 each mode; 17 shared native report verdicts and 24 exact raw program outcomes; extended char text50/750 |
| Bounded cursor source `8d1e135a8` | Core275 at 124.24 s/max 75.76; 1518 each mode; fresh split50/750; exact six-store proof; bounded negative/extreme and foreign-call tests |
| Trace source `2880b5001` | Core273 at 142.65 s/max 82.81 with 64 shards; rebuild 2.39 s; 1518 each mode; exact native trace reports/ring behavior and S1 fuzz50/750 |

Package stages with dependency refusals are not represented as final full
conformance. T1/T2 initially cover1310/1397 of 1518; their integration checkpoints
and final C/A compositions close dependencies. The final required language
sweep is still the pending ROOT/X receipt.

The zero-argument `native-tests-v1` schema remains established: character checks
compare all shared fields/reasons/locations and explicitly validate the old-only
actual/expected bool fields. Those JSON objects are not called byte-identical.
Raw program status/stdout/stderr and complete located traps are exact; the
separate24 property-runner reports compare the complete property contract.

## Completed ROOT merge prerequisites

[ROOT merge qualification](../integration/final-merge-run01/summary.json) is
qualified on `5ee5b8d2e1d1c697a98dfa590cbeda704ed7ae55`. Its fresh exclusive
Core installation takes **1.79 s**. Held Core64 passes **276 unique tests** with
**64 exact native verdicts**, **68/68 steps**, **134.76 s** total and **51.67 s**
maximum shard. The complete build inspection has no RSS overrun or errors; peak
reported test RSS is **251 MiB** across 64 test-run samples. The full strict
leak/fact sweep gives **1518 matching / 0 mismatching / 0 unsupported** in each
of debug/release, **61.20 s**, with status, stdout and reasons checked.

[The source freeze](../integration/final-source-freeze-run01.json) records no
`src`/`test`/`tests` difference from qualified A source 203c and no frozen IR/
ownership difference. Protected `main` is
`df55c52d7b4d319c02dfac66d7222701151825aa`; S2 integration remains
`92590700cb0bf5e4dc19cc1f0c836c3a41693f64`. Those are recorded freeze values;
the post-X reference/clean-tree checks remain pending.

The final explicit executables are rooted at
`/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-integration`:
`.mylang-cache/s3/oracle/mylang`, `.mylang-cache/s3/oracle/qbe` and
`zig-out/bin/mylang-core`. Old/QBE hashes remain the corrected d366/b613 pair;
ROOT Core's own-source SHA-256 is
`05e5206c53b853ff8855d547784cec0ae8c0587da3dbd5b0e02eb0eb2744721c`.
It is a fresh ROOT build, separately identified from A's c3aa compiler.

The fresh final all 40 performance receipt is green. Ordinary conformance,
old gate, count audit, 9×200 matrix, supplementary split200 and asset-preserving
coverage remain **PENDING**. Their
results must retain this source/oracle authority rather than borrowing the
package counts below without an explicit final record.

## Completed final A composition

[A's final manifest](../../wave-c/s3-a/qualification-final-01.json) qualifies
source `203c0ca6100344304cbd9fd20d22cc7f9448a145`. This is actual package evidence,
with final integrated ROOT/X status still PENDING.

| Check | Actual result | Receipt |
|---|---|---|
| Exclusive own-source install |2.33 s, all three build slots, no other-build wait | [A install log](../../wave-c/s3-a/logs/core-trace-combined-11.txt) |
| Held Core64 |276/276 unique tests; 64 exact native verdicts; 68/68 steps; 125.95 s,max 52.87 s; peak test RSS 249 MiB,no overrun | [Core review](../../wave-c/s3-a/trace-combined-core64-review-04.json) |
| Full strict conformance |1518 matches in debug and release, 0 mismatches/refusals, leak/fact checks; 52.00 s | [conformance](../../wave-c/s3-a/logs/trace-combined-full-conformance-06.txt) |
| All40 /80 size cells | Both unrounded ratios <=1.10 in every cell; 3200 retained raw samples; 283.10 s after admission | [performance](../../wave-c/s3-a/all40-combined-final-03.json) |
| Applications/imports/original native |137 executions, correct status/checksum/output, no leaks or unexpected stderr; old/debug/release/verify | [native summary](../../wave-c/s3-a/qualification-combined-final-02/summary.json) |
| Managed pinned split | Seven exact output lines in all four modes, 0 exits,empty leak stderr | [pinned split](../../wave-c/s3-a/split-qualification-combined-final-03/summary.json) |
| Split-key50 |50 sources, 750 comparisons, 0 mismatches; 145.83 s | [split sweep](../../wave-c/s3-a/fuzz-split-cursor-50-02/summary.json) |
| Corrected original35 proof |343 actual definitions; six scalar stores,two trace calls; zero residual instruction changes; exact module remainder after trace declaration replacement | [proof](../../wave-c/s3-a/combined35-final-04/summary.json) |

A's fresh complete old gate, source 203c, uses unique external private scratch
and retains gate/build slots, exact statuses, successful summaries and RSS
inspection:

| Step | Actual command time | Checked outcome |
|---|---:|---|
| `test` |808.42 s | exit0; 115/115 steps, 3002/33598 tests, 30596 intentional skips |
| `test-qbe` |75.43 s | exit0; 51/51 steps, 520/520 tests |
| `test-qbe-build` |3.01 s | exit0; 29/29 steps |
| `fmt-check` |0.24 s | exit0; 2/2 steps |

[Old gate run03](../../wave-c/s3-a/old-gate-combined-final-03/summary.json)
qualifies these actual executions. Old-compiler and old-suite times do not use
the <=10 s Core rebuild or <300 s Core-suite limits. Final X must record its
required full old-gate authority explicitly rather than silently relabel this
package receipt as a new execution.

## All40 performance table — final ROOT receipt

[The fresh final receipt](../integration/all40-final-run01.json) is valid and
passes both gates in all **40 rows /80 size cells**, with **zero misses**.
It uses the frozen ROOT 5ee source and its fresh 05e5206c Core oracle, not A's
older measurements. Every paired cell below is **4096 /64** in the row's
registry unit. Decisions use the exact unrounded ratios; the table renders
three decimals. The largest new/old ratio is packet_decode/64 at
**1.0489398227302076**; the largest new/Zig ratio is int_parse/64 at
**1.089964229247634**, both below 1.10.

Timing uses CPU10, seven shuffled interleaved rounds and subtraction of the
median of three one-iteration startup samples. All **3200** retained samples
require exit0, exactly two integer stdout fields, agreeing four-program
checksums and one positive finite cycle counter. The two observed CPU10 locks
are held external EDA first, required S2 second. No cell or gate is averaged
away. Original registry units/iteration counts and reference workload sources
remain unchanged. The final [command log](../integration/all40-final-run01.log)
retains actual execution authority; A's prior qualified table remains in its
package receipt and is not relabeled as this final execution.

| Row | Unit | Old | New | Rust | Zig ReleaseSafe | New/old | New/Zig |
|---|---|---:|---:|---:|---:|---:|---:|
| record_reads | iteration | 24.607 / 24.491 | 17.605 / 17.378 | 17.502 / 17.254 | 24.068 / 23.895 | 0.715 / 0.710 | 0.731 / 0.727 |
| tagged_stack | iteration | 63.306 / 63.285 | 33.345 / 33.327 | 25.939 / 25.908 | 47.831 / 47.800 | 0.527 / 0.527 | 0.697 / 0.697 |
| mutate_unique | iteration | 17.477 / 17.075 | 14.592 / 14.563 | 13.194 / 13.176 | 16.991 / 16.884 | 0.835 / 0.853 | 0.859 / 0.863 |
| mutate_shared | element | 0.957 / 6.968 | 0.636 / 0.640 | 0.637 / 0.656 | 1.122 / 0.989 | 0.664 / 0.092 | 0.567 / 0.647 |
| record_construct | element | 11.608 / 11.765 | 2.304 / 2.401 | 6.898 / 7.330 | 10.494 / 11.037 | 0.198 / 0.204 | 0.220 / 0.218 |
| record_update | element | 11.743 / 11.794 | 6.187 / 6.310 | 6.903 / 7.335 | 11.172 / 11.646 | 0.527 / 0.535 | 0.554 / 0.542 |
| option_handle | element | 4.027 / 4.054 | 2.015 / 2.439 | 2.415 / 3.156 | 6.503 / 7.392 | 0.500 / 0.602 | 0.310 / 0.330 |
| result_propagate | element | 6.136 / 5.595 | 3.635 / 3.505 | 3.514 / 4.123 | 7.095 / 7.458 | 0.592 / 0.626 | 0.512 / 0.470 |
| list_scan | element | 3.845 / 4.013 | 3.970 / 4.045 | 2.700 / 2.792 | 4.571 / 4.663 | 1.032 / 1.008 | 0.868 / 0.868 |
| list_append | element | 7.226 / 14.141 | 7.035 / 9.558 | 6.200 / 10.294 | 12.286 / 16.872 | 0.974 / 0.676 | 0.573 / 0.566 |
| list_filter | element | 9.297 / 17.726 | 8.209 / 10.426 | 5.738 / 10.038 | 10.596 / 13.872 | 0.883 / 0.588 | 0.775 / 0.752 |
| alloc_short | element | 242.838 / 246.341 | 4.888 / 5.086 | 5.010 / 5.460 | 21.847 / 22.221 | 0.020 / 0.021 | 0.224 / 0.229 |
| alloc_retained | element | 143.042 / 156.728 | 34.698 / 38.468 | 80.026 / 82.381 | 80.655 / 78.955 | 0.243 / 0.245 | 0.430 / 0.487 |
| mutate_nested | element | 28.908 / 45.857 | 12.696 / 14.405 | 81.394 / 72.284 | 75.271 / 74.523 | 0.439 / 0.314 | 0.169 / 0.193 |
| bytes_scan | element | 0.083 / 0.248 | 0.052 / 0.244 | 1.136 / 1.201 | 1.384 / 1.805 | 0.634 / 0.982 | 0.038 / 0.135 |
| string_equal | iteration | 53.673 / 16.601 | 50.461 / 15.149 | 134.713 / 12.639 | 277.633 / 16.773 | 0.940 / 0.913 | 0.182 / 0.903 |
| string_search | iteration | 420.110 / 79.359 | 433.629 / 68.467 | 5586.456 / 184.561 | 12927.119 / 385.522 | 1.032 / 0.863 | 0.034 / 0.178 |
| string_split | element | 201.805 / 210.688 | 60.103 / 65.188 | 27.869 / 35.618 | 65.466 / 68.958 | 0.298 / 0.309 | 0.918 / 0.945 |
| string_join | element | 6.073 / 10.126 | 4.545 / 6.055 | 14.033 / 14.802 | 18.072 / 20.226 | 0.748 / 0.598 | 0.251 / 0.299 |
| dict_lookup | element | 30.947 / 16.965 | 15.397 / 15.262 | 41.949 / 41.210 | 52.203 / 30.981 | 0.498 / 0.900 | 0.295 / 0.493 |
| dict_lookup_str | element | 61.829 / 28.619 | 23.461 / 19.796 | 60.899 / 57.308 | 62.441 / 31.868 | 0.379 / 0.692 | 0.376 / 0.621 |
| dict_update | element | 827.876 / 732.621 | 191.418 / 182.069 | 414.036 / 413.038 | 550.151 / 309.474 | 0.231 / 0.249 | 0.348 / 0.588 |
| dict_update_str | element | 1024.282 / 886.155 | 272.196 / 251.146 | 920.497 / 864.702 | 731.081 / 404.893 | 0.266 / 0.283 | 0.372 / 0.620 |
| set_dedup | element | 175.640 / 168.423 | 24.646 / 28.712 | 62.665 / 62.716 | 81.158 / 37.592 | 0.140 / 0.170 | 0.304 / 0.764 |
| int_parse | iteration | 46.181 / 41.476 | 29.420 / 26.538 | 22.803 / 19.215 | 28.837 / 24.347 | 0.637 / 0.640 | 1.020 / 1.090 |
| int_format | iteration | 213.166 / 208.965 | 68.515 / 62.782 | 63.727 / 60.716 | 214.500 / 197.731 | 0.321 / 0.300 | 0.319 / 0.318 |
| call_indirect | element | 5.015 / 5.087 | 0.301 / 0.312 | 7.173 / 7.554 | 9.013 / 9.509 | 0.060 / 0.061 | 0.033 / 0.033 |
| sort_int | element | 45.492 / 11.667 | 46.832 / 9.630 | 70.044 / 15.373 | 67.661 / 17.700 | 1.029 / 0.825 | 0.692 / 0.544 |
| sort_records | element | 54.531 / 66.377 | 31.265 / 40.509 | 40.915 / 44.759 | 117.738 / 50.854 | 0.573 / 0.610 | 0.266 / 0.797 |
| int_math | element | 8.700 / 9.068 | 0.358 / 0.496 | 5.704 / 6.187 | 7.808 / 8.311 | 0.041 / 0.055 | 0.046 / 0.060 |
| float_math | element | 8.297 / 8.433 | 1.570 / 1.708 | 6.967 / 7.329 | 6.512 / 7.031 | 0.189 / 0.202 | 0.241 / 0.243 |
| call_direct | element | 3.045 / 3.152 | 0.301 / 0.321 | 2.019 / 2.935 | 3.023 / 4.113 | 0.099 / 0.102 | 0.100 / 0.078 |
| branch_predictable | element | 4.025 / 4.154 | 0.396 / 0.498 | 3.200 / 3.257 | 7.727 / 7.908 | 0.098 / 0.120 | 0.051 / 0.063 |
| branch_mixed | element | 4.124 / 4.131 | 0.395 / 0.499 | 4.868 / 4.521 | 9.261 / 9.060 | 0.096 / 0.121 | 0.043 / 0.055 |
| binary_search | element | 144.931 / 33.011 | 32.173 / 18.095 | 36.455 / 19.521 | 136.954 / 27.825 | 0.222 / 0.548 | 0.235 / 0.650 |
| word_count | element | 292.387 / 376.083 | 35.820 / 49.800 | 59.352 / 66.172 | 47.242 / 50.824 | 0.123 / 0.132 | 0.758 / 0.980 |
| csv_aggregate | element | 4882.112 / 4165.975 | 1116.255 / 1053.984 | 1164.207 / 1060.945 | 1030.158 / 989.316 | 0.229 / 0.253 | 1.084 / 1.065 |
| json_transform | element | 13591.043 / 14003.033 | 2827.884 / 2964.471 | 1752.711 / 1980.167 | 2825.011 / 2866.805 | 0.208 / 0.212 | 1.001 / 1.034 |
| packet_decode | element | 15.382 / 15.090 | 15.731 / 15.828 | 10.237 / 10.726 | 19.393 / 19.661 | 1.023 / 1.049 | 0.811 / 0.805 |
| lox_eval | element | 630.551 / 659.600 | 205.983 / 214.263 | 165.474 / 171.560 | 505.022 / 521.629 | 0.327 / 0.325 | 0.408 / 0.411 |

## Count updates, loop scopes and original-row identity

**Final all 40 count receipt and 40-row table: PENDING.** Use a fresh explicitly
selected all 40 binary/LLVM/assembly directory with the final
[audit driver](../integration/audit_all40.py). A parser-success/`valid` result
alone is not a proof that every dynamic count effect is known.

Report tagged caller count stores separately from constant-one initialization
or release stores, other constant stores, dynamic count reads and saturated
checks. Natural innermost loops, exclusive parent blocks, timed nonloop blocks,
before-start setup loops and paths that abort before the stop clock are separate
scopes. Newly emitted LLVM helper loops/calls must remain in their own callee
scope, not disappear because a caller loop was inspected. The binary's static
site counts apply to both4096/64; dynamic execution counts are not inferred from
that equality. Opaque runtime/callee effects and untagged allocation-header
writes are **unknown**, not zero. Preserve all raw LLVM/assembly and complete
per-function loop/call inventory in the final receipt.

Two independent instruction proofs have different scope:

1. [The retrospective C/M/runner→S2 proof](../integration/c-identity-retrospective-run01/README.md)
   preserves all 35 complete before/after modules and raw diffs, matching every
   input SHA to the historical C receipt. Its corrected header parser covers
   all 343 actual definitions, including the previously hidden dotted helper.
   Exactly70 adjacent timer `io_at`/Host-check pairs are outside CFG cycles,
   exactly 35 single-use native entry grants are restored, and removing exactly
   two guard sites per row reproduces the complete old semantic site table.
   Only instruction-defined SSA names and semantic site/debug IDs are resolved;
   zero residual function differences remain. **Other module-level declarations,
   globals and attributes are unqualified by this retrospective proof.** It is
   a predecessor function/site proof, not full-module S2 identity or final X.
2. [A's complete corrected proof](../../wave-c/s3-a/combined35-final-04/summary.json)
   compares all 343 definitions against qualified C LLVM. It expands only six
   private i64 dictionary-set calls into the exact stride 16/value-offset 40,
   alignment 8 typed store and same-dictionary forwarding, removing their six
   proven-private spill slots: one each in dict_lookup/dict_lookup_str and two
   each in dict_update/dict_update_str. It changes only two result_propagate
   trace calls to the exact constant-action preserving ABI. Bijective SSA/block
   correspondence and semantic metadata preserve every remaining instruction,
   operand, flag, CFG/phi edge and trap. Outside-function module content is
   byte-identical after replacing the single old trace declaration with its two
   exact preserving declarations. There is no wholesale helper/function/global
   elision and zero residual differences. This proves A's delta against C;
   it does not expand the predecessor proof's unqualified module-level scope.

The full raw inputs and diffs are retained for both. The final count audit and
performance gates remain separate obligations from either static identity proof.

## Float-text first-build cost and cache authority

The [T2 cold receipt](../../wave-b/s3-t2/float-cold-final/summary.json) measures
separate fresh source programs. A fresh runtime-object directory and fresh Zig
global cache produce a3.116963 s first program build, including 0.965590 s and
one compilation of the independent formatter unit. A different next source
reuses that object in 0.113942 s with zero formatter compilations. Simulating a
Zig-version suffix invalidates the key:1.023885 s total, including 0.881457 s
for one new formatter compilation. The actual executing toolchain remains
`0.17.0-dev.1683+5ceec001b`; no second installed Zig version is claimed.

The recorded object key is
`714db03fe3fa391c9b5a852fe8b845a55a788be7cbede44ff2b90ac1dbe77348`.
[The key manifest](../../wave-b/s3-t2/runtime-cache-key.json) records the Blake3
fingerprint domain, executing Zig version, every target/build option, each
helper name and its complete content digest, separated by NULs. Explicit options
are `-target x86_64-linux-gnu -mcpu baseline -O ReleaseFast -fPIC
-fno-stack-check -fno-stack-protector -lc`. Helper SHA-256 values are:

| Complete helper | SHA-256 |
|---|---|
| `core_number_text.zig` | `e2e4b6ce5941c0e80dac7f064196f93869a1f2c325bb9b3e8914805e8ffee046` |
| `core_number_parse.zig` | `53ad97811d5888d72102b60cb7a6535ba8718900b360ca39d5b30f01df3e0e1e` |
| `core_number_format.zig` | `002d54fdcf9409c54c43006ffc5da860cf730e6c80eb77021f1278f1719424a7` |

These hashes still match the integrated files at this candidate's5ee5b8d2
snapshot. Unique partial objects, per-program staging and atomic publication
protect concurrent cache misses. Integer-only programs do not pay the float
unit. This historical exact-unit measurement is distinct from the final whole
Core compiler rebuild timing; later application packages introduce no new
formatter cold-cost claim.

## Final fuzz matrix — PENDING

The final [driver/protocol](../integration/README.md) requires fresh evidence
and explicit qualified old/new paths on the final frozen integrated head. It
runs 200 sources for each of `s0`, `s1`, `rc`, `rebinding`, `iteration`, `dict`,
`text`, `number`, `functions`:1800 sources and 25800 required comparisons.
Every kind must accept all 200, keep all original harness argument sets and
compare raw stdout, exit status and primary native trap outcome across old
release and new debug/release/verify. Refusals, old rejects, build failures,
timeouts, crashes, leaks, fact failures and unexpected exits invalidate the
receipt. Unique logs and append-only command journals retain every native
outcome, including intended traps.

The text generator retains the complete original T1 work literally, then adds
observable multi-consumer scalar comparisons/appends, UTF-8 widths, NUL, branch
and destination aliasing, saved snapshots and capacity growth. Number extends
the original numeric harness with S3 float/format/buffer cases. The separate
split-key200 sweep adds3000 comparisons for cursor/key lifetime, managed
returns, rebinding, collisions, indexed/deleted tables and fallback cases;
it supplements rather than weakens the nine-kind matrix.

Package50 sweeps are listed above and remain retained evidence. They are not
substitutes for these200-case exit receipts. Final matrix and supplementary
sweep identities, counts, elapsed/admission times, failure totals and source/
oracle-unchanged checks: **PENDING**.

## Coverage, conformance and named S4 exceptions

The ordinary final conformance target is 1518 selected tests in each mode.
Final ordinary ROOT counts are **PENDING**. The completed ROOT strict
leak/fact sweep and final A/C compositions execute1518 each with zero
mismatches/refusals; ordinary and strict receipts remain separately identified.

The historical four-corpus qualified-name sums are:

| Checkpoint | Accepted / assessed | Accounting context |
|---|---:|---|
| S2 foundation |3185 /3627 | Original baseline coverage |
| D2/Wave A |3213 /3595 |46 names removed, 14 accepted added, 20 retained admitted; no accepted-name regression |
| T1 |3324 /3595 | New text surfaces |
| T2 |3456 /3595 | Bytes/numbers/blobs |
| Combined C |3589 /3595 | Capabilities/runner/dependencies |
| Asset-preserving tool preparation |3633 /3639 per-corpus; 3410 /3416 globally deduplicated | Original embedded assets retained; examples202/207,parity123/123,language3168/3168,runtime140/141 |
| Final X asset-preserving before/after |PENDING | Fresh frozen-source receipts, child statuses, exact names/reasons |

The later asset-preserving denominator/context is explicit; 3633/3639 must not
be treated as a direct delta from 3589/3595 without name accounting. Restoring
original embedded assets clears four prior scratch-copy `E_EMBED` failures.
D2 separately changes the conformance denominator1540→1518 by retiring35
stored-view cases, adding12 snapshot replacements and one immediate-membership
case.

The six retained bodyless declarations are extern `abs`, `floor`,
`main::runtime_bench_now`, and Host `io::length`, `io::byte`, `io::put`.
Repeated imports yield11 raw occurrences. Their linked calls are executed;
a declaration has no independent Core body. Seven flattened example contexts
fail `E_MODULE_NAME`: invoice/{catalog,money,pricing},
interface-files/shop/{billing,money}, input-values/config/values and
modules/shared/units. These are failures of that coverage source context,
not a claim that every valid module-headed source is refused. Final coverage
must retain actual names/statuses rather than count them as executions.

The explicit S4 execution exclusion is `tests/lang/migrated/propagation.my`,
which imports `propagation_case_1` through `_9`. Its exact nine top-level names
are:

- `test_nested_results_can_be_propagated_repeatedly_1`
- `test_nested_results_can_be_propagated_repeatedly_2`
- `test_nested_results_can_be_propagated_repeatedly_3`
- `test_option_propagation_unwraps_some_and_forwards_1`
- `test_option_propagation_unwraps_some_and_forwards_2`
- `test_try_unwraps_success_and_remaps_errors_betwee_1`
- `test_try_unwraps_success_and_remaps_errors_betwee_2`
- `test_try_wraps_a_mismatched_error_into_the_matchi_1`
- `test_try_wraps_a_mismatched_error_into_the_matchi_2`

The [final 127-name inventory](../integration/exceptions-final-run01.json)
also includes118 retired arena cases: five whole modules plus 85 individual
cases elsewhere. Those five modules are `arena_class_escape`, `arena_managed`,
`arena_regions`, `arena_scopes` and `rc_arena_values`; that module-only list is
not the complete retirement list. The final frozen-ROOT inventory contains
exactly 9 S4 and 118 arena names; no extra refusal is folded into those exceptions.

## Historical failures and their actual closure

Earlier failures stay retained and keep their original statuses. They are not
removed, averaged away, converted into passes or waived by a later successful
prototype. The package reports provide complete command/run histories.

- Wave A's12 s old-compiler build, timed during the full old gate, was not a
  qualifying Core rebuild stop. The user's amendment applies the 10 s rule only
  to an uncontended `zig build core`; admission and old-compiler build times are
  distinct. Final actual Core rebuild timing remains required.
- C's context-as-name old answer triggered review and the approved ENV oracle
  correction above. Old gate03 found missing context fixture cache inputs and
  an unsupported old `ReleaseSafe` test mode; the source/fixture corrections
  precede clean oracle gate04. That oracle gate does not silently qualify later
  runner edits.
- T1's true find_any negative-start error and verify-only header-after-release
  lifetime defect were corrected and qualified by final range fuzz, long
  find_any and large final-use native tests. Stale pre-D2 or pre-install oracle/
  compiler runs and nonexistent-file harness attempts remain setup history.
- T2's first Core run had a stale expectation for the implemented byte fixture's
  intentional `42` output. The test-only correction and 16-shard pass supersede
  that failure; no fixture case was removed to satisfy the gate.
- M/runner's one full-conformance Unit-local `InvalidIr record_set` mismatch
  is retained. Source930 canonicalizes payloadless Unit locals; focused final
  M and the actual combined1518/1518 C/A sweeps close it. Initial capture probes
  were checked against the old pin behavior; the two unmodeled ancestor cases
  remain precise refusals rather than invented semantics.
- Byte/text edge probes exposed adjusted-versus-source index diagnostic errors.
  Narrow authorized provenance recovery preserves the original source index,
  full location/reason/details, producer checks and receiver. Final byte54
  comparisons and character raw/report tests qualify extreme/Unicode failures.
  Known no-detail Core traps now emit the existing version1 marker with valid
  escaping while preserving the original human diagnostic; no report schema
  replacement or parser-only semantic workaround was used.
- Initial A application measurements missed four rows. Profiles justified the
  generic word/byte/character repairs. The first complete composition still
  failed word/64 new/Zig1.103086 and packet/64 new/old1.101765; a fresh paired
  repeat confirmed1.103926 and 1.106961. The receipts remain failed. Bounded
  cursor emission and constant-action preserving trace wrappers qualify the
  repaired source; final A all 40 run03 passes all 80 cells. The generic trace
  prototype's1.1087 packet/64 miss is also retained before its exact refinement.
- Functional-but-over-time Core receipts are explicitly unqualified for timing:
  the character matrix run had max 120.64 s despite 259 functional passes, and
  trace Core32 had max 104.32 s despite 273 passes. Meaningful case-preserving
  distribution and the plan's prescribed shard increase produce the actual
  qualified char Core32 and trace/A Core64 receipts. Default sharding stays 8.
- A old gate run01 used project `.zig-cache` TMPDIR and failed
  NATIVE-ZIG-CACHE-4; run02 used `.mylang-cache`, whose absolute-path filter
  excluded incremental scratch sources despite 3002 passing unit tests.
  Both failed runs remain. Tool commit
  `2213bcc00b75538d2c19017c9bc57e7e39e62952` uses unique private `/var/tmp`
  scratch, and fresh focused preflight plus the actual four-step run03 pass.
  These tool corrections changed no compiler/runtime or valid performance input.
- The inherited identity parser searched a whole function body and silently
  overwrote dotted helper names. A's incomplete run03 is retained as unqualified
  history. Correct header parsing/duplicate rejection/count assertions produce
  the actual 343-definition A run04 and the independently reproducible C
  retrospective receipt. Their zero-residual result has the precise scopes
  stated above; no wholesale module-content omission is called a proof.

## Remaining limits and final decision

[The complete limits inventory](limits-final-candidate.md) separates actual
source refusals, inherited frontend/runtime budgets, optimization fallbacks and
S4 persisted-module boundaries. In particular, source foreign signatures remain
Host-first scalar; copied Host rejects None anywhere in its value graph;
property generation thresholds are not blanket source-type limits; the packed
storage cap is not a bound on every separately copied payload; and managed
classes/computed assertion messages/keyed-sort shape limits remain explicit.
Standard-library imports and merged checked module source are supported without
claiming S4 persisted `.myi`/Core-IR caches or incremental per-module compilation.

IR remains frozen at `dc1a583109be06c3e699a433be24cbcd6e5d3816`. Ownership was
not rewritten, no record phi was emptied, and aggregate parameters remain in the
first 64 positions. Formats remain `module-interface-v5`, `check-summaries-v6`
and `mutation-v2`; provider ABI 7 and published wire-format versions remain intact.
Compiler/runtime metadata is ephemeral and authority-limited. Every premise
used by facts, uniqueness or stack promotion retains its verification check.
The frozen source-input/IR/ownership and main/S2 snapshot is recorded above.
Post-X reference checks, no-push confirmation, clean tracked tree/evidence
commit and serialized Guardian feedback commit remain **PENDING**.

**S4 decision: not yet open.** Complete and validate every pending X receipt,
then publish the frozen source/evidence identities and this exit report. At that
point S3 stops for the user's explicit **go/stop on S4**: user modules,
persisted interfaces/incremental builds, the Lox port and an EDA slice. This
candidate grants no S4 authorization and does not start that work.
