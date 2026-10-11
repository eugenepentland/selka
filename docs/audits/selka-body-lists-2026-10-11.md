# Selka-owned list body checking

Date: 11 October 2026. Integration branch: `codex/selka-bootstrap-20261011`.
This B3 wave extends the qualified scalar, string and byte body checker with
managed lists. It is an intermediate compiler boundary, not a self-hosted
compiler or a completed bootstrap.

## Completed boundary

The Selka producer owns list expression and statement checking in ordinary
nongeneric functions: inferred, contextual, empty and nested lists; annotations,
parameters, calls and returns; snapshots and marked mutation; negative indices
and nested element writes; common methods and sorting; repetition and augmented
updates; and iteration with native source-rebinding and element-write semantics.
Lists can contain supported scalar/text/byte values or other supported lists.
The producer supplies every typed node, statement, local metadata row and range.

The retained native common catalog projects actual prelude identities, supported
existing list descriptors and its complete initial ordinal count. Selka owns
the order, element type and original source site of each newly interned list.
The native adapter validates and materializes these recipes without making
body checking decisions. Unsupported selected bodies refuse explicitly; they
never fall back to native body checking. Reference remains the default mode.

Shadow checking compares the complete typed outcome, diagnostics, import usage
and ordered recipes against native checking on the untouched initial catalog.
A separately reconstructed common catalog then materializes the producer's
recipes and compares every final record field with the native catalog. Applying
producer recipes before the native oracle would hide interning-order bugs and
is deliberately avoided.

## Artifact identities

The Debug and ReleaseFast installations contain the same seven authenticated
packages, built with the unchanged qualified seed. The complete inventories are
in [artifacts.json](evidence/selka-body-lists-20261011/artifacts.json).

| Artifact | SHA-256 |
| --- | --- |
| Debug host | `787a2dc2aebff0d8ee808cdce71efd7e00401dbb053e7b6b7ea7f51e99bc0190` |
| ReleaseFast host | `a4b0323080cf6e247560df9e0b182baf32eb5c2dfe91873362ea424b752b83c1` |
| Qualified seed | `c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b` |
| Body-check artifact | `efab777c4a1920c6cad02898d8036ee21ff47affacefaba17402315531a32586` |

## Protocol and identity

Body-check protocol/schema is **1/3**. Both earlier schemas are refused.
Catalog adds `base_count`, supported `lists` descriptors and `list_available`;
successful output adds ordered `ListRecipe{id,element,span}` values. IDs append
contiguously after the full initial catalog, not merely the supported subset.
Existing lists may have sparse IDs and forward dependencies. New recipes cannot
refer forward, duplicate an element key, form a cycle or exceed the catalog and
wire budgets. Existing authentication, request binding and publication checks
remain enforced. The selected body/frontend identity domains advance; the
all-reference domain stays unchanged.

## Qualification

The [full gate](evidence/selka-body-lists-20261011/b3-full-gate.log.gz)
passed **131/131 steps**, reporting **2,726 passed tests**. Its 29 Guardian
verdicts report 2,724 passed, zero failed and zero selected skips; two additional
verification-cache tests account for the difference. The 24,949 skipped slots
belong to other shards. Exact totals are retained in
[gate-summary.json](evidence/selka-body-lists-20261011/gate-summary.json).
Formatting passed 20/20 steps, whole-tree Guardian passed all 88 checks, and
both final installations passed 14/14 steps.

The installed corpus contains **87 fixtures**: 48 successes, 31 source errors
and eight native-valid profile refusals. Thirty-nine successes execute generated
programs. New list cases cover the 63/64-element packed-literal boundary, source
order of type interning, expression receivers, nested updates, mutation during
iteration and source rebinding. Text methods and repetition remain explicit
refusals rather than incorrect source diagnostics.

| Installed lane | Workflows | Comparisons | Warm deployment | Live sessions |
| --- | ---: | ---: | ---: | ---: |
| Debug normal, including component edit | 234 | 936 | 30 | 4 |
| Debug release/facts/leaks | 234 | 468 | 30 | 4 |
| ReleaseFast host, release/facts/leaks | 234 | 468 | 30 | 4 |

All three lanes passed with zero failures or skips, as did **81 pure tests per mode**.
Each lane verifies one valid and 16 malformed exchanges, rejects 16 authenticated
forged replies and requires two cross-package publication host failures.
Malformed replies include bad list IDs, self-dependencies, unsupported elements
and unlocated source spans. The private component edit changes only the body
artifact while preserving the host and six other package identities.

The [normal/edit receipt](evidence/selka-body-lists-20261011/gate-normal.json),
[Debug release receipt](evidence/selka-body-lists-20261011/gate-release.json) and
[ReleaseFast receipt](evidence/selka-body-lists-20261011/release-host-qualification.json)
retain workflow hashes, package identities, warm receipts and publication checks.
The changed body artifact in the normal/edit lane is
`dd928905bcb9fbd95c0aa06e6374fccb9690c7f617a1a76c3b93c12ae8a19a9d`;
its key is `5f56344290db5affe62b4632b8567625d04c2c92a7463655753c55ed957204f7`.

Earlier failing runs exposed a raw pool-ID versus typed node-ID mixup in the
iteration guard, index diagnostic location/text differences, missing admission
for native nested list augmentation, and expression receiver error precedence.
The fixes retain exact validation and shadow equality. Disk exhaustion also
required recovering an uncommitted producer write from committed source and
retesting; only owned regenerable inactive caches were removed.

## Isolated performance and release-producer experiment

The [timing log](evidence/selka-body-lists-20261011/b3-timing.log) records FIFO
gate ticket 159 and all three build reservations held on CPUs 2,3,10,11. All
reservation holders exited zero. The sweep exited **1** because the strict
budget verdicts failed; both complete reports were retained. This is a measured
performance failure, not a passing gate or an incomplete measurement.

The baseline is the frozen B2 ReleaseFast host using native reference checking,
SHA-256 `3c9f1f1c1806eadd21c0281b4cf216d74e2a4854415a4176e2010416b99c3496`.
Both candidates use the B3 ReleaseFast host above with only `BODY_CHECK=component`;
the other selectors stay reference. Each of the three two-module workloads
(scalar, text/bytes and lists) has two guest tests and returns seven. Twenty
samples per row enforce **both median and p95 ≤1.5×**; no averaging removes a
failed row. Native units are prewarmed for both hosts before timing; fresh
compilation means a fresh application cache. Warm compilation requires exact
replay and zero new compiler processes; warm tests require two reused receipts.
Every workload first passes release facts/leak behavior checks. Runtime measures
the generated release executable including process startup, so these short rows
cannot establish broad runtime performance acceptance.

The qualified seed's default guest policy is unoptimized debug (`-O0`), with
one LLVM unit per module. Guest `--release` enables optimization, combines the
program into one LLVM unit and changes debug metadata. The pinned compiler maps
its release `-O3` request to Clang `-O2`. This corrects the original audit's
attribution to module fusion alone, which mistakenly used the current compiler's
default rather than the frozen seed's `src/core/pipeline.zig:24` default. The
measured artifacts, samples and verdicts are unchanged. The private release
producer preserves the exact 39-file source snapshot,
qualified seed, host and other six packages. Its artifact is 2,185,984 bytes,
versus 4,643,320 bytes for the installed producer, with SHA-256
`289030f7b035e99548af76afc155aeaab88c732a57f12ea5a5098549f58c7af3`.
Its [full installed qualification](evidence/selka-body-lists-20261011/release-producer-full-qualification.json)
passes 234 workflows, 468 comparisons and all cache, transport, forged-reply and
publication checks. A separate instrumented artifact is qualification-only;
the measured artifact has no fact instrumentation. This experiment does not
change the installed coordinator recipe.

The reports retain raw samples, receipts and artifact provenance:
[standard producer](evidence/selka-body-lists-20261011/b3-standard.json) and
[release producer](evidence/selka-body-lists-20261011/b3-release-producer.json).
For the list workload, median times and candidate/native ratios are:

| Workflow | Native ms | Standard Selka ms (ratio) | Release producer ms (ratio) |
| --- | ---: | ---: | ---: |
| compile-fresh-application-cache | 16.070 | 99.507 (6.19×) | 56.358 (3.49×) |
| check | 1.018 | 6.488 (6.37×) | 3.646 (3.65×) |
| compile-warm | 1.759 | 12.304 (7.00×) | 6.856 (3.93×) |
| test-cold | 18.048 | 108.864 (6.03×) | 61.632 (3.39×) |
| test-warm | 1.780 | 17.386 (9.77×) | 9.122 (5.13×) |
| runtime | 1.039 | 1.095 (1.05×) | 1.056 (1.03×) |

Each candidate passes only **3/18 rows**, the three generated-runtime rows.
All 15 compile/check/test rows fail. The release producer lowers median overhead
substantially, but still takes about 3.4–5.1 times native across those workflows.
Its own matched native samples are retained in the report; the table's native
column displays the first run. Repeated authenticated artifact reads, process
launches and boundary encoding remain architectural costs to measure and reduce;
artifact size correlates with this experiment but is not a causal cost breakdown.
A fused compiler can remove intermediate process/transport boundaries, while
Selka algorithm, allocation and generated-code costs still require measurement.
None of these subset results meets the whole-language performance requirement.

## Remaining work

Records/member checking is next. Unions, checked failures, other collections,
generic specialization, resources and the remaining body forms are still
outside this boundary. Native catalog construction and semantic postpasses,
Core/LLVM compilation and driver orchestration also remain to be ported.
Staged self-compilation, reproducibility and representative whole-language
performance acceptance remain unproven. The external C runtime and pinned
Zig/LLVM toolchain may remain dependencies.
