# Selka-owned ordinary record body checking

Date: 11 October 2026. Integration branch: `codex/selka-bootstrap-20261011`.
B4 extends the qualified scalar, text, byte and list body checker with ordinary
nongeneric records. It remains an intermediate compiler boundary: the compiler
cannot yet compile its own source, and complete bootstrap and performance
acceptance remain outstanding.

## Completed boundary

Selka owns record constructor/default checking, named argument order, nominal
and alias resolution, public/private imported names, field reads and mixed
record/list mutation paths. Mutable parameters, calls, returned snapshots,
record lists and finite recursive records through lists preserve native typed
metadata and generated behavior. The recursive fixture constructs a nonempty
child list, mutates a nested field, and verifies the earlier snapshot.

Protocol/schema is **1/4**. `Catalog.records` appends the complete retained
native record prefix as the sixth input catalog field. Selka joins raw
name/declaration spans to those schemas and makes body-level decisions; there
is no per-use native answer table. New lists retain schema 3's bounded ordered
recipes. Selected unsupported forms refuse explicitly, with no native body
fallback. Native reference remains the default mode.

Shadow compares the entire typed outcome, diagnostics, import usage and ordered
list recipes against native checking on the untouched initial catalog. A fresh
common catalog then materializes producer recipes and compares every final
record field. Unions, generics, boxed/resource layouts, domains and contracts
remain outside B4. Unused/imported invariants and function `requires`/`ensures`
are rejected before producing a successful batch; native admission independently
rejects forged successful batches that omit those checks.

A native Core diagnostic printer bug exposed by recursive records was also
fixed. It now prints stable type-ID back edges on the active recursion path;
repeated sibling schemas still print structurally. Two focused regressions
cover both cases.

## Artifact identities and build policy

Both installations contain identical seven-package authenticated manifests;
full inventories are in [artifacts.json](evidence/selka-body-records-20261011/artifacts.json).

| Artifact | SHA-256 |
| --- | --- |
| Debug host | `e061ecf835b3c6aacec6c51ed87cd08dca7b6ba0a6a72a8994bd3f57b579cb0d` |
| ReleaseFast host | `0ebf9d2dda21c47ba880ac4809c676b6320967bb3393fa318334a135651a8946` |
| Qualified seed | `c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b` |
| Body-check artifact | `63c8f23e8273eb6c1ee980e0960bc70f3975881042bb2da5bb24c1ff710e6342` |

The body key is `34e4119cc824fcf5651ec7e9be1c17653c5fc5fc0d30009e1e20015e55beb287`.
Only the body component's authenticated coordinator recipe now passes
`--release`; the other six recipes keep their previous policy. Exact arguments
participate in the source/build identity. Uncached rebuilding must reproduce
the authenticated bytes. The CLI bootstrap test builds all seven packages with
an empty PATH and no interpreter. Qualification separately enables guest facts
and leaks; production component artifacts omit fact instrumentation.

The frozen seed defaults to unoptimized debug, not the current compiler's
optimized debug. B3's audit attribution was corrected without changing its
measurements. Release adds optimization, single-unit compilation and different
debug metadata; the pinned seed maps its release optimization request to
Clang `-O2`. Source hashes and the exact seed-policy evidence are retained.

## Qualification

The corpus has **109 fixtures**: 57 successes, 39 source errors and 13 native-valid
profile refusals. Forty-eight successes execute generated programs; 55 compare
typed/Core dumps. All 87 earlier B3 fixtures remain. Profile refusals are
accounted separately and do not count as implemented language coverage.

| Installed lane | Workflows | Comparisons | Warm deployment | Live sessions |
| --- | ---: | ---: | ---: | ---: |
| Debug normal, including component edit | 283 | 1132 | 30 | 4 |
| Debug release/facts/leaks | 283 | 566 | 30 | 4 |
| ReleaseFast host, release/facts/leaks | 283 | 566 | 30 | 4 |

All three lanes pass with zero failures/skips. Each accepts one authentic frame,
rejects 17 malformed requests and 24 authenticated forged replies, and requires
two cross-package publication host failures. The normal lane rebuilds a private
body-only source edit, preserving the host and six other package identities.
The pure suite passes **121 tests in each mode**, with release fact/leak checks.

Receipts: [normal/edit](evidence/selka-body-records-20261011/gate-normal.json),
[Debug release](evidence/selka-body-records-20261011/gate-release.json), and
[ReleaseFast](evidence/selka-body-records-20261011/release-host-qualification.json).

The initial full gate completed **131/131 steps**, reporting **2743 passed tests**.
Its 29 Guardian verdicts total 2741 passed, zero failed and zero selected skips;
two verification-cache tests account for the difference. The 25128 skipped slots
belong to other shards. It also printed a CLI bootstrap memory diagnostic:
1,538,023,424 bytes exceeded the old 768 MiB reservation. Inspection of pinned
`lib/compiler/Maker/Step.zig` showed that this runner appends the diagnostic
without returning `MakeFailed`, explaining the successful final exit.

CLI shards now reserve 2 GiB; frontend/body qualification drivers reserve
2.5 GiB for concurrent seed and clang processes. A body test build tree was
sampled at 1,304,895,488 bytes before clang's peak. These are build scheduling
allowances; guest limits and the 1.5-times performance target are unchanged.
The corrected [full gate](evidence/selka-body-records-20261011/b4-full-gate-resources.log.gz)
passes **131/131 steps** with no memory-excess diagnostic. Its nine executed
Guardian verdicts and build summary report **816 passed, zero failed**; 5642
slots belong to other shards and unchanged steps reuse prior verdicts. This is
not a fresh measurement of every cached shard. Body qualification reruns both
121-test pure modes and both complete installed matrices. Formatting passes,
and an explicit whole-tree Guardian run passes all **88 checks**. Exact initial
and corrected totals are in [gate-summary.json](evidence/selka-body-records-20261011/gate-summary.json).

Early smoke runs are retained as failures. They exposed constructor diagnostic
span differences, missing initializer location, a mutation receiver overlap,
and the recursive native printer crash. After fixes the final smoke passes
219 check/typed/Core comparisons; installed qualification adds generated
execution, authentication, source edits and cache checks. A failed intermediate
installation contained a duplicate spec tag; the final installations supersede it.

## Isolated performance

The [complete 24-row report](evidence/selka-body-records-20261011/b4-matched.json)
retains all raw samples, behavior checks, cache receipts and package identities.
The [isolation log](evidence/selka-body-records-20261011/b4-timing.log) records gate
ticket 166 and all three build reservations held on CPUs 2,3,10,11. Every holder
exits zero. The sweep exits **1** because **20 rows fail** the strict performance
budget; this is a completed measurement with a failing verdict.

Both sides use the same immutable, qualified B4 ReleaseFast host above. The
baseline selects native reference checking everywhere; the candidate selects
only `BODY_CHECK=component`. Twenty samples per row require both median and
nearest-rank p95 to be at most 1.5 times native. Scalar, text/byte, list and
record workloads each have imports, two executed tests and a generated release
program returning seven. Native units are prewarmed for both modes. Fresh
compilation uses a fresh application cache, not a cold machine or toolchain;
warm compilation requires exact replay with no new compiler processes, and
warm tests require two cached receipts. All behavior controls first pass with
release fact/leak checks, disabled consistently during timing.

For the record workload:

| Workflow | Native median ms | Selka median ms | Median ratio | p95 ratio |
| --- | ---: | ---: | ---: | ---: |
| compile-fresh-application-cache | 17.496 | 76.378 | 4.37× | 4.47× |
| check | 1.070 | 4.858 | 4.54× | 4.07× |
| compile-warm | 1.763 | 9.002 | 5.11× | 5.08× |
| test-cold | 18.831 | 82.715 | 4.39× | 4.34× |
| test-warm | 1.813 | 12.725 | 7.02× | 6.92× |
| runtime | 1.032 | 1.109 | 1.08× | 1.04× |

Only the four short generated-runtime rows pass. All twenty compile/check/test
rows fail, with medians approximately **4.4–7.2 times native**. Runtime includes
process startup and covers this small subset; it does not establish general
runtime acceptance. These results cannot be equated directly with B3's ratios:
B3 used an older B2 native baseline and a narrower producer/catalog profile.
Process launch, artifact authentication and boundary serialization remain costs
to measure and reduce alongside producer algorithms and generated code. Moving
compiler stages into one Selka executable is still future work, not a measured
performance fix. The whole-language 1.5-times requirement remains unmet.

## Remaining work

B5 variants, pattern matching and checked Result/Option failures are in progress
in separate Sol lanes. Other collections, generic specialization, scalar widths,
resources, contracts and all remaining body forms still need closure. Selka must
also own the retained common semantic phases, Core lowering/transformations,
LLVM emission, and compiler/build/test/cache orchestration. Stage 1, 2 and 3
self-compilation must establish a reproducible fixed point and pass full language
and tooling gates. Representative whole-language compile, test and generated
runtime measurements must independently meet the 1.5-times native requirement.
The external C runtime and pinned Zig/LLVM toolchain can remain dependencies.
