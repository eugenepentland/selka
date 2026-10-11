# Selka-owned variants, patterns and checked failures

Date: 11 October 2026. Integration branch: `codex/selka-bootstrap-20261011`.
B5 extends the qualified scalar, text, byte, list and record checker with
nongeneric variants, patterns and checked Result/Option failures. This is an
intermediate compiler boundary. Complete self-hosting, a bootstrap fixed point
and the 1.5-times performance requirement remain outstanding.

## Completed boundary

Selka owns variant construction, payload/default checking, named argument order,
aliases and privacy, exhaustive statement/expression matches, nested/product
patterns and wildcard coverage. Finite recursive variants through lists preserve
snapshots. Checked failure signatures, failure returns and `try` preserve native
typed metadata and Result consumption obligations across branches and loops.
Explicit discard consumes an obligation; implicit non-unit discard retains the
native diagnostic and, where applicable, repair. Pending Results cannot become
ordinary list elements. Managed payloads and multiple pending call arguments
retain their transfer sites and cleanup behavior.

Protocol/schema is **1/5**. Authenticated Result/Option template bases identify
the retained declaration or synthesized standard basis. Selka supplies ordered
tagged List/Result/Option recipes on first demand, preserving case order and
canonical identities. Unannotated `parse_int(str)` and text/bytes `.parse_int()`
calls exercise actual body-demand Option[int] interning, including invalid text
and overflow returning None. Optional annotation precollection is not used as
evidence for that append path.

Shadow compares the complete typed outcome, diagnostics, import usage and
ordered catalog recipes against native checking on the untouched initial
catalog. A separate fresh catalog materializes recipes and compares every final
record. Component mode adopts only validated outcomes and refuses unsupported
forms without native body fallback. Native reference remains the default.
Generic/boxed variants, direct by-value recursive layouts, Option narrowing and
Option receiver methods remain explicit profile refusals. Qualified standard
template applications and retained semantic phases remain future work.

## Qualification and identities

The corpus has **148 fixtures**: 79 successes, 53 source errors and 16 native-valid
profile refusals. Seventy successes execute generated programs; 77 compare
typed/Core dumps. Every B4 fixture remains, with the former record-with-union
refusal promoted to success. The 39 new cases include 21 successes, fourteen
diagnostics and four profile refusals, plus an uncounted dependency donor.

| Installed lane | Workflows | Comparisons | Warm deployment | Live sessions |
| --- | ---: | ---: | ---: | ---: |
| Debug normal, including component edit | 388 | 1552 | 30 | 4 |
| Debug release/facts/leaks | 388 | 776 | 30 | 4 |
| ReleaseFast host, release/facts/leaks | 388 | 776 | 30 | 4 |

All three lanes pass with zero failures/skips. Each accepts one authentic frame,
rejects 19 malformed requests and 66 authenticated forged replies, and requires
two cross-package publication host failures. The normal lane repeats the entire
matrix after a private body source edit changes its key and artifact while
preserving the host and six other packages. The **199 pure tests across 31 roots**
pass in both normal and release/fact/leak modes. Installed commands run with an
empty PATH; Python remains developer test orchestration only.

Receipts: [normal/edit](evidence/selka-body-variants-20261011/gate-normal.json),
[Debug release](evidence/selka-body-variants-20261011/gate-release.json), and
[ReleaseFast](evidence/selka-body-variants-20261011/release-host-qualification.json).

All seven authenticated package inventories match between the Debug and
ReleaseFast installations. [artifacts.json](evidence/selka-body-variants-20261011/artifacts.json)
retains the complete inventories and coordinator identities.

| Artifact | SHA-256 |
| --- | --- |
| Debug host | `e379d007c0a9a5e97f9c1fa9b6c4138958e8359ca3081b098f783e398c20e46e` |
| ReleaseFast host | `5be1628129c9a7783d8db636c6dd8e4319b5befb4417f201e16e073aa6666b75` |
| Qualified seed | `c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b` |
| Body-check artifact | `8a4d26ba2dbace37ae28586a86fe86883e90257eb98f82e31e200716ed2918cb` |

The body key is `76210079e48b9eaf6b78fd238f81f2b5589fec1f7d39c531db08425a674b03e0`.
The unchanged qualified seed builds the body producer with its authenticated
release recipe; the other six build recipes remain unchanged. Source/package
identity and the compiler's optimization mode are distinct from guest release
fact/leak validation. The complete component source tree, including its README,
is frozen at the qualified key. This audit records completed qualification
outside that tree so recording the result does not change the package identity.

The [final full gate](evidence/selka-body-variants-20261011/b5-full-gate-fresh.log.gz)
passes **131/131 steps** with no memory-excess diagnostic. Its nine executed
Guardian verdicts and build summary report **816 passed, zero failed**; 5,642
slots belong to other shards. Unchanged native steps reuse prior verdicts, so
this is not a fresh run of every native test. Body qualification reruns all 199
pure tests per mode and both complete installed matrices. Formatting passes
(982 live `.my` files, 204 deliberate exclusions), and an explicit whole-tree
Guardian run passes all **88 checks**. The qualification commit and exact
counts are in [gate-summary.json](evidence/selka-body-variants-20261011/gate-summary.json).
The evidence directory retains raw receipts, compressed logs, timing scripts,
all earlier B5 failures and a SHA-256 inventory.

## Failures retained and corrected

The first full gate exposed a local Option receiver falling through into import
resolution. Unsupported local receivers now produce the explicit profile
refusal after admitted methods have been considered. An exact regression is in
the pure suite. A subsequent full gate reached the private coordinator rebuild
and failed. Preserved child diagnostics and a standalone reproduction identified
`LLVM ERROR: out of memory` under the inherited 2 GiB address-space ceiling.

Only the two coordinator rebuild commands now receive a bounded 4 GiB
address-space allowance. Ordinary installed requests, forged replies and guest
workflows retain 2 GiB; output limits and stricter inherited limits remain
enforced. The uncached edited producer rebuilt in **49.91 seconds**, with a
reported maximum child RSS of **2,051,872 KiB**, and changed only its own package.
That timed reproduction deliberately omitted the matrix; the completed normal
qualification separately proves adoption and all workflows after the edit.
Maximum child RSS is not a sampled aggregate process-tree peak. The build
scheduler's existing 2.5 GiB component-driver reservation remains separate.

Hostile-reply commands now force `--no-cache`; capture helpers also remove prior
request/reply files before launching. This makes each test exercise a fresh
exchange rather than depending on a previously cached verdict. All three final
installed qualification lanes use this hardening. Earlier
ReleaseFast receipts are retained explicitly as pre-hardening evidence.
Harness selftests exercise the resource limits and fresh-exchange requirements.

Early private replay, installation and qualification failures remain in the
evidence bundle. The final installed smoke passed 604 check/typed/Core
comparisons; it is narrower than the generated-runtime and hostile-input
qualification above. No failed or profile-refused case is counted as implemented
language support.

## Isolated performance

The [36-row report](evidence/selka-body-variants-20261011/b5-matched.json)
retains all raw samples, cache receipts, behavior checks and deployment
identities. Both sides use the same B5 ReleaseFast host and seven-package
installation above. Baseline uses native reference everywhere; candidate selects
only `BODY_CHECK=component`. Each of six workloads has 20 samples for fresh
application-cache compilation, checking, warm compilation, cold and warm tests,
and generated release runtime. Every row must pass both median and nearest-rank
p95 at **1.5 times native**; there is no averaging across failures.

The [isolation log](evidence/selka-body-variants-20261011/b5-timing.log)
records gate ticket 183 and all three build slots held on CPUs 2,3,10,11. Each
reservation exits zero and all are released. The sweep exits **1** because its
strict budget fails **30 of 36 rows**. This is a completed measurement with a
failing verdict, not an incomplete timing run.

Native units are prewarmed on both sides. Fresh compilation means a fresh private
application cache, not a cold toolchain or machine. Warm compilation requires
exact replay without compiler subprocesses; warm tests require two cached test
receipts. Each workload first passes release fact/leak behavior checks. Facts
and leaks are then disabled consistently for timing. The measured subset covers
scalars, text/bytes, lists, records, variants and checked failures, not the whole
compiler or language.

For the new variant workload:

| Workflow | Native median ms | Selka median ms | Median ratio | p95 ratio |
| --- | ---: | ---: | ---: | ---: |
| compile-fresh-application-cache | 16.830 | 94.775 | 5.63× | 5.73× |
| check | 1.097 | 6.125 | 5.59× | 5.15× |
| compile-warm | 1.821 | 11.672 | 6.41× | 6.09× |
| test-cold | 18.406 | 103.398 | 5.62× | 5.51× |
| test-warm | 1.816 | 16.410 | 9.04× | 8.70× |
| runtime | 1.072 | 1.130 | 1.05× | 1.09× |

All thirty compile/check/test rows fail, with medians **5.3–9.2 times native**.
The six short generated-runtime rows pass, but include process startup and
cannot establish whole-language runtime acceptance. The broader B5 producer and
its process, authentication and transport costs need further optimization.
Joining stages in one compiler remains future work, not a measured performance
fix. Neither this subset nor the earlier B4 measurements satisfy the completed
compiler's performance requirement.

## Remaining work

B6 byte slicing/conversions and buffer operations are implemented in separate
Sol branches but still require coherent integration and installed qualification.
Actual compiler pure libraries additionally need text/byte iteration, `ord`,
integer-to-text casts, range/iterable comprehensions, list slicing, nested
collection iteration, conditional expressions and imported managed constant
getters. Those implementations and a strict actual-library admission runner
are being developed separately; initial actual-library refusals and shadow
disagreements remain failures until corrected.
B7 then admits Filesystem/Stream entry signatures, bounded reads, output and
scoped file cleanup across all seven component entrypoints. Checking those
component closures is a source-coverage milestone, not full compiler bootstrap.

Remaining language forms and semantic phases, Core lowering/transformations,
LLVM emission and compiler/build/test/cache orchestration must move to Selka.
The pinned seed must build stage 1, stage 1 build stage 2, and stage 2 build
stage 3 with retained identities, an explained reproducibility comparison and
the full language/tooling gates. Representative compile, test and generated
runtime measurements must independently meet the 1.5-times native requirement.
The external C runtime and pinned Zig/LLVM tools may remain dependencies.
