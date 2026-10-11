# Selka-owned scalar body checking

Date: 11 October 2026. Integration branch: `codex/selka-body-check-20261011`.
Production implementation commit: `218608460`; the wire contract's common-phase
import-use clarification is included with this audit. Three Sol agents supplied the native
wire validation, Selka producer, and installed qualification; the coordinating
worktree integrated compiler routing and cache identity.

## Completed boundary

`body-check` is the seventh independently seeded Selka component. B1 owns the
checking of ordinary nongeneric functions using `int`/`i64`, `bool`, and `Unit`:
raw signature and local annotations, expressions, calls, named/default arguments,
mutable arguments, local bindings and definite assignment, branches, while and
basic range loops, break/continue, returns, discards, and static assertions.
It constructs complete typed nodes, statements, functions, local metadata, and
per-function ranges directly from raw AST and module facts. The request contains
no native checked bodies or pre-resolved semantic worklist.

`MYLANG_BODY_CHECK_MODE=reference|shadow|component` selects the boundary.
Reference remains the default. Component mode bypasses native body checking and
adopts the validated typed batch. Shadow checks uncached native bodies and
compares every logical typed field, including unreachable intermediate nodes,
ordered diagnostics with related sites and repairs, and import-use flags.
Selected modes disable native body, specialization, and summary replay.

Native catalog foundations, entry validation/adaptation, effects and origins,
domain codecs, warnings, and final cache publication remain explicit host
stages. The retained catalog/entry phases can observe imports after the raw
request snapshot. Their flags are copied into the producer result before either
adoption or native shadow body checking. This preserves common-phase work while
still detecting missing producer body observations.

Managed values, generic functions and specialization, checked failure signatures,
lambdas, resources, contracts, nominal declarations, non-i64 literal suffixes,
floating division, chained comparisons, dynamic assertion messages, and explicit
range strides remain outside B1. Unsupported programs produce an explicit
`P_BODY_PROFILE` refusal and a host failure in selected modes, without native body
fallback. Scalar alias declarations can remain in the native catalog; annotations
using aliases exceed B1. This stage does not claim that the component can check
its own source or the complete compiler.

## Protocol and publication

Protocol/schema 1/1 uses `SLKBCK01` framing and named `SLKBKI01`/`SLKBKR01`
payloads. The nonce and full request SHA-256 bind replies to requests. The host
executes authenticated sealed bytes, verifies the artifact again afterward, and
revalidates the aggregate selected frontend identity before publishing success
or source errors. That identity participates in syntax, semantic, executable,
test-result, and live-session validity. All frontend shadow modes disable replay.

| Resource | Limit |
| --- | ---: |
| Modules | 4,096 |
| Source per module / aggregate originals | 1 MiB / 8 MiB |
| Top-level source path | 16 KiB |
| Typed nodes / statements | 262,144 each |
| Functions / aggregate locals | 65,536 each |
| Logical values / edges | 1,048,576 / 4,194,304 |
| Logical depth | 256 |
| Decoded allocation budget | 512 MiB |
| Complete request or reply frame | 64 MiB |

Merged source permits up to 4,096 delimiter bytes beyond the original source
budget. Independent graph limits can reject inputs before individual table caps.
Validation enforces source association, table partitions, function/local
ownership, scalar payload types, call permutations, and acyclic references.
Decoded replies are cloned before releasing their arena. Validation establishes
structural admission; semantic correctness relies on the authenticated producer
and full shadow qualification. These limits apply to the selected component,
not the native reference compiler.

The [wire contract](../../selfhost/components/body_check/WIRE.md),
[producer scope](../../selfhost/components/body_check/README.md), and
[qualification guide](../tooling/body-check-component-qualification.md) describe
the boundary and developer commands. Installed execution uses an empty PATH;
Python is developer orchestration only.

## Artifact identities

| Artifact | SHA-256 |
| --- | --- |
| Debug host | `8af1f6ae8f1d7b2302d5c1cda04950c64fba4eb5db7c4f245aa8ba91e83c4533` |
| ReleaseFast host | `20fb7facf405ff440f38703d9c600ed9cbd74af904fbeba5a45571bc159ea273` |
| Qualified frozen seed | `c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b` |
| Body-check artifact | `9b6d1f86e5e6cae1f57e8f369da629794550635de7a6355e31518ed51f4c5ae0` |

The body-check build key is
`fbe7f04a7ee3943df223e40f58306df12d317375a7c610650493d098fb80eda5`.

## Qualification

The full gate passed **131/131 build steps**, reporting **2,704 passed tests**.
Its 29 Guardian native verdicts reported 2,702 passed, zero failed, and zero selected tests
skipped. The 24,707 skipped
aggregate slots belong to other shards. The complete
[gate log](evidence/selka-body-check-20261011/full-gate.log.gz) and
[machine-readable totals](evidence/selka-body-check-20261011/gate-summary.json)
are retained. Existing frontend, declaration, and type/interface gates passed.

All 32 pure body-checker tests passed uncached in each of normal and release
fact/leak modes. The focused native run passed 26/26 tests, and final Debug and
ReleaseFast installations passed 14/14 steps. These focused counts overlap the
full gate and are not additional unique tests.

The corpus contains 47 fixtures: 21 scalar successes, 19 exact
source diagnostics, and seven native-valid profile refusals. Twelve success
fixtures also execute generated programs. The installed matrix includes 113
workflows, mixed selection of all five frontend boundaries, build/run/test and
library paths, deterministic typed/lowered output, and imported implementation
edits. Each lane checks 30 warm deployment cases, four live sessions, one valid
and 13 malformed exchanges, eight forged typed replies, and two cross-package
publication failures.

The normal lane rebuilds only the body component through the qualified native
coordinator and repeats all workflows, preserving the host and other six package
identities. Release qualification enables fact and leak checks. Strict accounting
rejects incomplete, duplicate, cached pure, or skipped verdicts.

| Installed lane | Workflows | Comparisons | Warm deployment | Live sessions |
| --- | ---: | ---: | ---: | ---: |
| Debug normal, including component edit | 113 | 452 | 30 | 4 |
| Debug release/facts/leaks | 113 | 226 | 30 | 4 |
| ReleaseFast host, release/facts/leaks | 113 | 226 | 30 | 4 |

Every lane passed with zero failures or skips. The independently installed
ReleaseFast host has a separate [receipt](evidence/selka-body-check-20261011/release-host-qualification.json)
and [command record](evidence/selka-body-check-20261011/release-host-command.json).
The Debug [release receipt](evidence/selka-body-check-20261011/gate-release.json)
retains the gate's second lane. Installed commands run with an empty PATH and
bounded developer capture/deadlines. These checks do not establish a production
memory ceiling beyond the documented wire admission budget.

The final [normal/edit receipt](evidence/selka-body-check-20261011/frozen-normal.json)
and [command receipt](evidence/selka-body-check-20261011/frozen-normal-command.json)
also assert that the private coordinator's initial package exactly matches the
installed package. Its operational edit changes the key to
`e2edf2a457cb8df9607c9979b84bb0950335c4639e2705957328e694c0a3ecb4`
and artifact SHA-256 to
`ac1bf327652404623a52224c0587c64d04d93e6f5277f76e5e606e5b4c77f190`;
the other six packages remain unchanged. This repeats, rather than adds to,
the normal lane's coverage.

The gate's original [normal receipt](evidence/selka-body-check-20261011/gate-normal.json)
is retained separately: a concurrent wire-document clarification changed the
source recipe used for its private coordinator baseline, while production Selka
code stayed identical. Both installations were reconciled and the entire
normal/edit matrix rerun against the frozen documented source. The final receipt
above is the adoption evidence for the exact installed package.

A separate whole-tree Guardian run passed all 88 blocking checks; final
documentation and formatting passed 23/23 build steps. Command,
environment, and admission records are in the
[command record](evidence/selka-body-check-20261011/commands.txt).

Integration regressions cover negative literals and signed i64 bounds, defaults
and named argument order, private imports and repair sites, mutable argument
markers, augmented assignment origin/span/remainder semantics, retained mutation
wrapper nodes, and imports observed by private aliases in the common catalog
phase. Earlier failures are retained as failures, not exclusions.

## Isolated measurements

The final measurement held FIFO gate ticket 126 and all three build reservations
while pinned to CPUs 2,3,10,11. Every reservation exited successfully and was
released. The [admission log](evidence/selka-body-check-20261011/timing.log),
[completed receipt](evidence/selka-body-check-20261011/timing-receipt.json), and
retained launchers record exact commands and identities.

The baseline is the prior six-package ReleaseFast host from `6dce322ef`, SHA-256
`16d3c3bab8160aaf30ce5e9206a7259fb3d50c85d4be7b2760c65798bc161bc3`.
The candidate is the qualified seven-package ReleaseFast installation above.
All other component selectors remain reference. Both runs check behavior on the
same small imported scalar project. Values are wall-clock milliseconds: the
fresh application cache has one sample, and remaining rows show medians.

| Workflow | Prior host/reference | Candidate/reference | Candidate/body component |
| --- | ---: | ---: | ---: |
| Fresh application cache (one sample) | 17.15 | 16.94 | 68.38 |
| Warm executable replay (20 samples) | 1.82 | 1.78 | 8.67 |
| Implementation edit/link (5 samples) | 15.26 | 14.96 | 67.38 |
| Project body checking (20 samples) | 1.00 | 1.02 | 4.53 |

Component selection adds approximately 6.89 ms to warm replay, 52.42 ms to
edit/link, and 3.51 ms to project checking compared with candidate reference.
Reference remains the default. These small-fixture samples establish neither
large-project scaling nor a general native-compiler speedup.

The [baseline](evidence/selka-body-check-20261011/timing-baseline.json) and
[candidate](evidence/selka-body-check-20261011/timing-candidate.json) retain every
sample and cache report. Fresh application and edit builds reused all three
native units and linked; warm rows replayed executables with no compiler
subprocesses. Shared unit/runtime/toolchain stores were warm. The first run
compiled an edit unit only in the baseline; it is retained as
[cache preparation evidence](evidence/selka-body-check-20261011/timing-prewarm/README.txt),
and all measurements were repeated after that unit was warm. Final comparisons
therefore use matching cache work. They are not cold native-code measurements.

Cumulative child high-water RSS was 47,104 KiB for baseline and 47,036 KiB for
candidate. This covers complete measurement processes, including seed validation
and native tools, not per-exchange component memory. Fact/leak checks were
disabled for timings and qualified separately.

## Bootstrap position

Seven packages now build independently with the frozen native seed: test-index,
cache-plan, lexer, parser, declaration indexing, type/interface resolution, and
the B1 scalar body checker. This is incremental compiler ownership in Selka.
The compiler still depends on the native host and seed.

The next body-checking work is managed and aggregate values, nominal members,
ownership/failure semantics, then generics, specialization, and callbacks.
Remaining effect/origin/contract and dynamic-resolution phases need explicit
ownership. Core lowering, optimization, backend emission, and command coordination
follow. Full self-hosting is established only after a clean A→B→C compiler
bootstrap and artifact/corpus reproducibility checks; B1 does not establish it.
