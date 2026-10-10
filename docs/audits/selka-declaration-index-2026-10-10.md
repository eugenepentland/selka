# Selka-owned declaration and module indexing

Date: 10 October 2026. Integration branch:
`codex/selka-declaration-index-20261010`, based on `04031109a`.
Production integration commit: `d470c4958`. Three Sol agents supplied the
indexed primitives, pure declaration producer, and installed qualification.

## Completed boundary

`declaration-index` is the fifth independently seeded Selka component. It builds
per-module symbol tables from parsed AST declaration facts, import/export
headers, public markers and already indexed direct-dependency symbols. Selka
owns category order, qualified owner names, duplicate/import-alias diagnostics,
public/export/domain visibility, canonical re-export identities and import-use
flags. It does not parse the module again.

The Zig host retains filesystem discovery, dependency order, AST projection,
signature checking, general name resolution and body checking. Component mode
adopts the validated result without running the native declaration collector.
Shadow mode runs both collectors and compares complete symbols or diagnostic
code/message/site/related values. `MYLANG_DECLARATION_MODE` accepts `reference`,
`shadow` and `component`; reference remains the default.

The reusable Selka primitives provide stable name-ID sorting, bounded binary
lookup and byte-offset-to-line indexing. Counters test sort/lookup work and
snapshot independence. The producer also indexes public spans, dependency IDs
and import targets, avoiding repeated scans across export and dependency lists.
Generated key bytes are counted before allocating owner-qualified names.

## Protocol, identity and resource limits

The new package uses protocol/schema 1/1 and `SLKDIX01` framing. Test-index stays
1/1, cache-plan 2/2, and lexer/parser 1/2. Neither seed pin nor the qualified
component source profile changes. The request binds source/path/trust/module
facts, imports, exports and dependency values with nonce plus complete payload
SHA-256. Execution retains authenticated sealed executable bytes and revalidates
deployment before publication.

| Resource | Limit |
| --- | ---: |
| Source bytes per module | 1 MiB |
| Source path | 16 KiB |
| Local declarations plus facade keys | 65,536 |
| Aggregate dependency symbols | 65,536 |
| Imports and direct dependency units | 4,096 each |
| Exports and public markers | 65,536 each |
| Aggregate input names and generated keys | 1 MiB |
| Complete request or reply | 32 MiB |
| Owned reply strings, including repeated owner names | 2 MiB |

The host checks complete table counts/order, name/kind/span/owner correspondence,
visibility, canonical origins, exact import usage and located diagnostic shapes.
Malformed values remain host failures. Source errors preserve native diagnostics.
Later native signature/body checks use the adopted table. These bounds describe
the opt-in component profile, not a newly imposed native frontend limit.

Verified producer identity participates in existing syntax, semantic, executable,
test-receipt and live-session reuse. Shadow mode bypasses reuse. Warm deployment
checks replace manifests/artifacts at stable paths; live checks change deployment
inside a running session. Four authenticated native fixture producers return
validly correlated but malformed/incomplete replies; eight checks across shadow
and component modes must fail as host errors.

## Qualification

The independently verified seed SHA-256 is
`c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.
The installed declaration artifact SHA-256 is
`95c6c7703af54241393933d76ba8b5b82217c514f50f9e6993b3034ef4b04b29`.

Both normal and release/fact/leak modes passed all 39 uncached pure tests:
16 indexed-primitive tests and 23 declaration/codec tests. Exact primitive
limits use an explicit 100-million-step test budget. The installed harness
uses a 2 GiB address-space ceiling, bounded output and deadlines; these are
qualification budgets rather than a new production process memory policy.

| Installed lane | Workflows | Comparisons | Warm deployment checks | Live checks | Forged replies rejected |
| --- | ---: | ---: | ---: | ---: | ---: |
| Normal, including declaration-only edit | 30 | 120 | 30 | 4 | 8 |
| Release/facts/leaks | 30 | 60 | 30 | 4 | 8 |

Each lane also passed one valid exchange and nineteen malformed-request refusals,
with zero failures or skips. Tests cover Unicode byte locations, duplicate and
alias precedence, direct exports, public/private domain members, the test-module
privacy exception, and transitive re-exports of functions, types and constraints.
Three workflows select all three frontend components together. Cache-enabled
checks prove two test receipts reused in component mode and both tests rerun in
shadow mode.

The normal lane privately edits declaration implementation code and rebuilds
through the native coordinator. The declaration key and artifact change while
the host and the other four package receipts remain unchanged; all 30 workflows
are repeated against the new deployment. The native seed is not invoked directly
to bypass coordinator qualification.

The full gate on `d470c4958` passed **125/125 steps**. Its 29 native verdicts
reported **2,666 passed, zero failed and zero selected tests skipped**. The build
aggregate's 24,311 skipped slots belong to other shards. The full
[log](evidence/selka-declaration-index-20261010/full-gate.log.gz) and
[machine-readable totals](evidence/selka-declaration-index-20261010/gate-summary.json)
are retained. A separate whole-tree Guardian run passed all 88 blocking checks.
The focused native declaration run passed 148/148 selected tests; packaging,
cache verification and formatting passed 30/30 build steps. These overlapping
focused counts are not additional unique tests. The final documentation and
formatting check passed 23/23 build steps.

The [normal](evidence/selka-declaration-index-20261010/normal.json) and
[release](evidence/selka-declaration-index-20261010/release.json) receipts retain
package identities, workflow/output hashes, cache checks and coordinator-edit
identities. The ReleaseFast host separately passed all 30 workflows with 60
comparisons, 30 warm checks, four live checks and eight forged-reply refusals
under release/fact/leak settings; its
[receipt](evidence/selka-declaration-index-20261010/release-host-qualification.json)
is separate from the full gate's Debug host. The ReleaseFast installation passed
14/14 build steps and has SHA-256
`9d4390768195d5b2022f7cc910c753c6dbb0e0487bf965536574cf1c07feb5ee`.

Reproduce the integration checks through FIFO admission with private disk TMPDIR
and worktree-local Zig cache: `zig build`,
`zig build test-selfhost-declarations`, `zig build test --summary all`, and
`zig build fmt-check`. The registered declaration gate verifies its external seed
receipt on every invocation and retains JSON reports in its build output directory.

Initial integration issues were repaired before the final gate: stale private
Zig cache manifests after pruning old outputs, one Zig identifier shadowing
error, three Guardian style findings, and a qualification-driver flag unsupported
by the frozen seed. Leak checks use the supported `MYL_CORE_LEAKCHECK=1` environment
control. These initial failures are retained as evidence, not exclusions.

## Isolated measurements

The successful run held FIFO gate ticket 92 and all three build reservations
(tickets 891–893) through both measurements, pinned to CPUs 2,3,10,11. The
[reservation log](evidence/selka-declaration-index-20261010/timing.log) and
[completed receipt](evidence/selka-declaration-index-20261010/timing-receipt.json)
retain exact commands, host/output digests and successful release of every slot.
An initial launcher invocation applied affinity before reservation creation and
was rejected before collecting samples; the successful invocation pins only the
measurement process after acquiring the build reservations.

The frozen prior ReleaseFast host is
`4f41c951fa3dd9e5b2b6f17e12cc958d91e3858734f1a3439549e4b3211bdfec`.
The candidate is the separately qualified ReleaseFast host above. Lexer, parser,
test-index and cache-plan stay in reference mode throughout this comparison.
Both runs use the same small imported project and verify executable behavior.
Values below are wall-clock medians in milliseconds, except the explicitly
single-sample fresh-application-cache row.

| Workflow | Prior host/reference | Candidate/reference | Candidate/declaration component |
| --- | ---: | ---: | ---: |
| Fresh application cache (one sample) | 18.52 | 17.24 | 33.04 |
| Warm executable replay (20 samples) | 1.81 | 1.76 | 3.77 |
| Implementation edit/link (5 samples) | 15.68 | 15.03 | 32.61 |
| Interface listing (20 samples) | 1.42 | 1.39 | 12.21 |

The component adds about 2.01 ms to warm replay, 17.58 ms to edit/link, and
10.82 ms to interface listing compared with candidate reference in this fixture.
It is approximately 2.14×, 2.17× and 8.80× respectively. This stage establishes
functional ownership and parity; these results support keeping reference as
the default. The small reference differences do not establish a speedup.

The [baseline](evidence/selka-declaration-index-20261010/timing-baseline.json) and
[candidate](evidence/selka-declaration-index-20261010/timing-candidate.json) files
retain every sample and compiler cache report. Fresh application caches and
edited builds reused all three native units and performed linking; shared native
unit/runtime/toolchain stores were warm. Warm rows report executable replay with
zero compiler subprocesses. These are not cold-toolchain or cold-native-code
measurements, nor a broad compiler-corpus performance result. Pure boundary and
operation-counter tests establish larger input admission separately.

Recorded cumulative child high-water RSS was 47,092 KiB for the baseline run
and 47,160 KiB for the candidate run. It covers each entire measurement process,
including seed verification and native tools; it is not per-component exchange
memory. Fact/leak checks were disabled for timings and qualified independently.

## Bootstrap position and next work

Five components now build independently from the frozen native seed. This is a
new production compiler boundary in Selka; the complete compiler has not yet
compiled itself. The next stage is type/interface analysis: general name and type
resolution, declaration metadata and signature checking. Body checking follows,
then Core lowering/optimization/backend and command coordination, followed by
clean A→B→C bootstrap and artifact/corpus reproducibility checks. Type checking
and backend migration remain substantially larger than this declaration stage.
