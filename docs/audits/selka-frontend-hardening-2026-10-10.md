# Frontend performance, larger profiles and the bootstrap path

Date: 10 October 2026. Integration branch:
`codex/selka-frontend-hardening-20261010`, based on `a0a4a80c5`.
This continues [frontend adoption](selka-frontend-adoption-2026-10-10.md)
with three Sol agents owning performance, resource profiles and qualification.

## Scope and acceptance

Reduce the cost of explicit lexer/parser component modes, qualify a 1 MiB
whole-source profile against realistic dense inputs, and rerun the complete
workflow/deployment matrix and isolated measurements. Authentication still
covers executable contents; launch snapshots remain sealed; changed deployment
must be detected before reusable results or native outputs are published.
Reference remains the default while adoption limits and measured costs remain.

Frontend transport stays protocol 1 and the expanded resource profile is
schema 2. The native coordinator records protocol and schema independently in
both artifact recipes and installed manifests. Previous frontend packages must
be rejected before cache reuse or execution. Test-index remains protocol/schema
1; cache-plan remains protocol/schema 2. Neither seed pin changes.

Identity-only deployment checks now hash executable contents in fixed storage,
instead of allocating the entire executable into each caller's arena. Launch
still retains and authenticates an immutable executable snapshot. A small
LLVM ReleaseSafe SHA-256 object isolates the pinned native backend's AVX/SSE
transition cost; the rest of the compiler keeps its existing backend. Neither
change treats file metadata as proof of executable identity.

The larger profile has independent limits:

| Resource | Limit |
| --- | ---: |
| Source bytes per file | 1,048,576 |
| Token rows | 1,048,833 |
| Complete parser request | 64 MiB |
| Serialized syntax values | 1,048,576 |
| Serialized child edges | 4,194,304 |
| Value data and field names | 64 MiB |
| Serialized syntax reply | 64 MiB, plus 64-byte outer header |
| Host decoder allocations | 512 MiB |
| AST expression and statement tables | 262,144 each |
| Graph visits | 4,194,304 |
| Nesting depth | 256 |

The exact serialized-value test deliberately constructs scalar records; it
proves codec admission, not native AST parity. Dense valid programs separately
exercise real token transport, AST equality and normal compiler consumers.
The scalar test receives an explicit 500-million-step/1-GiB test budget. Workflow
qualification applies a 2-GiB address-space ceiling to the host and descendants,
preserving any stricter inherited limit. This is a qualification constraint;
the production launcher does not gain a new per-component memory ceiling.

## Execution evidence

Focused qualification passed 40 component-boundary tests, 15 codec tests and
three pure producer resource tests in each of normal and release/fact/leak modes.
The performance lane separately passed 12 artifact regressions and eight SHA
differential tests. These are independent filtered runs, with shared unnamed
test blocks; their counts must not be summed as unique tests. Commands and
qualified seed identity are preserved in the [profile receipt](evidence/selka-frontend-hardening-20261010/profile-validation.txt)
and [performance receipt](evidence/selka-frontend-hardening-20261010/performance-validation.txt).
The initial 50-million-step scalar test reached its instruction limit during
encoding. Raising only this test's budget to 500 million allowed both execution
modes to complete within the unchanged 1-GiB test memory budget.

The integrated ReleaseFast installation passed **14/14 build steps**. Its host
SHA-256 is `4f41c951fa3dd9e5b2b6f17e12cc958d91e3858734f1a3439549e4b3211bdfec`.
An untimed dense-source qualification ran check, token dump and syntax dump in
reference, shadow and component modes. All nine commands succeeded with exact
status/stdout/stderr equality under the inherited 2-GiB address-space ceiling.

| Dense workload measurement | Observed size |
| --- | ---: |
| Source | 440,060 bytes |
| Token rows | 100,017 |
| Token JSON | 6,895,294 bytes |
| Serialized AST values | 900,093 |
| Serialized AST | 29,303,242 bytes |

The dense case crosses the old source, token and value limits simultaneously.
The workflow gate asserts the actual token/value counts, rather than inferring
capacity from source size. Its dedicated run's cumulative child peak RSS was
497,812 KiB, covering all commands and descendants; this is not a per-producer
memory measurement. [Raw dense qualification](evidence/selka-frontend-hardening-20261010/dense-profile.json)
records these distinctions.

The first integrated gate found two stale schema-1 fixtures: a pure lexer wire
golden and a cache-receipt replacement mock. Both were corrected; the lexer
now also tests complete schema-1 request rejection, and the receipt test checks
valid authority before replacement. Their focused reruns passed. The
[initial failed gate log](evidence/selka-frontend-hardening-20261010/initial-gate-failures.log.gz)
is retained; those failures are not exclusions.

The final full gate on production/component source commit `137c9f53e` passed
**122/122 steps**. Its 29 Guardian native verdicts total **2,651 passed, zero
failed and zero skipped**; two ordinary Zig tests bring the build aggregate to
2,653 passes. The 24,146 skipped slots are assigned to other shards, not omitted
selected tests. [Machine-readable totals](evidence/selka-frontend-hardening-20261010/gate-summary.json)
and the [complete log](evidence/selka-frontend-hardening-20261010/full-gate.log.gz)
are preserved. All 88 blocking Guardian checks passed in the repository's
configured diff scope (50 per-file checks on 59 changed files and 38 whole-tree
checks).

| Frontend lane | Workflows | Comparisons | Warm deployment checks | Live-session checks |
| --- | ---: | ---: | ---: | ---: |
| Normal, including parser-only coordinator edit | 34 | 136 | 60 | 8 |
| Release, fact verification and leak checks | 34 | 68 | 60 | 8 |

Both lanes have zero failures or skips. Fourteen adversarial qualification
harness tests passed. The same gate passed 18 lexer, 89 parser and 11 probe
pure tests in each mode. Both parser corpus runs selected 379 modules: 378
exact AST matches and one previously pinned lexical exclusion. Both lexer
runs compared 79 fixtures and 1,714 token/error rows, with no failures or skips.
The historical lexer driver retains three exclusions, and documentation retains
23 declared skips; those are not counted as current frontend parity.

The final combined documentation/format check passed **23/23 steps**, including
221 executed examples, 62 checked examples, 23 declared skips and no failures
or mistagged blocks. Its [complete log](evidence/selka-frontend-hardening-20261010/docs-fmt.log.gz)
is retained. No Guardian feedback file was modified.

## Isolated measurements

Matched measurements completed after the correctness gate, holding the FIFO
gate reservation and all three build reservations on CPUs `2,3,10,11`.
The frozen baseline and candidate are prebuilt ReleaseFast installations.
The baseline host SHA-256 is
`51c207cb030c5c5c9cf19ef041d7eeaea3ddb5924c05d991f46a665e06b97b19`;
the candidate is the `4f41c951…` installation identified above. Both runs,
the launcher and all reservation holders exited zero. Production/component
sources and installed package identities stayed unchanged throughout.

[Baseline samples](evidence/selka-frontend-hardening-20261010/timing-baseline.json),
[candidate samples](evidence/selka-frontend-hardening-20261010/timing-candidate.json),
[commands and identities](evidence/selka-frontend-hardening-20261010/measurement-receipt.json)
and [admission/release receipts](evidence/selka-frontend-hardening-20261010/timing-admission.log)
are retained. Private reservation and matched-runner source snapshots accompany
the receipt.

Each cell below is **baseline → candidate**, in milliseconds.

| Complete parser CLI invocation, median of 20 | Reference | Shadow | Component |
| --- | ---: | ---: | ---: |
| 33-byte source | 1.016 → 1.055 | 10.246 → 9.157 | 10.092 → 9.363 |
| 65,533-byte comment source | 1.128 → 1.172 | 10.425 → 9.543 | 10.274 → 9.689 |
| 700 helper declarations, 25,013 bytes | 4.268 → 4.057 | 83.513 → 85.688 | 80.019 → 81.898 |

| Application build | Reference | Shadow | Component |
| --- | ---: | ---: | ---: |
| Empty application cache, one sample | 17.205 → 51.391 | 113.435 → 101.534 | 121.099 → 105.975 |
| Unchanged warm command, median of 20 | 1.858 → 1.872 | 98.678 → 84.915 | 13.821 → 12.771 |
| Imported function edit, median of five | 16.090 → 16.140 | 114.175 → 100.133 | 109.718 → 96.336 |

The component warm and edit medians fell by 7.6% and 12.2% respectively in
this run. Small parser invocations improved modestly; the original dense parser
case became slightly slower (80.019 to 81.898 ms). This does not establish a
general parser speedup or justify switching defaults. The single empty-cache
reference sample also rose from 17.205 to 51.391 ms; it is retained without
inferring a stable or causal regression from one sample.

Every retained cold/edit cache report shows three native units reused and none
compiled, followed by linking. Warm reference/component commands replayed the
program; shadow continued frontend comparison and reused native artifacts.
These are empty application-cache and source-edit measurements with a warm
shared native-unit store, not cold native compilation.

| Candidate-only parser input, median of 20 | Source bytes | AST values | Reference ms | Shadow ms | Component ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Exact source limit, mostly comments | 1,048,576 | 69 | 2.253 | 13.270 | 13.508 |
| Dense valid assignments | 440,060 | 900,093 | 75.472 | 1,116.129 | 1,056.869 |
| Sixteen nested parentheses | 65 | 69 | 1.217 | 9.537 | 9.469 |
| Unicode comments above the old limit | 375,033 | 69 | 1.640 | 10.886 | 10.888 |

The large dense syntax reply is 29,303,242 bytes; the other three replies are
2,457 bytes. Large dense component parsing still costs about 1.06 seconds per
complete invocation, so transport/serialization and parser work remain material
follow-ups.

| Native coordinator operation | Baseline seconds | Candidate seconds |
| --- | ---: | ---: |
| Build/install four packages in an empty artifact store, one sample | 24.931 | 25.496 |
| Verify/reuse existing packages, median of three | 0.439 | 0.380 |
| Parser-only implementation edit, one sample | 8.706 | 8.109 |

Each coordinator edit changed the parser recipe and executable digest while
the host and other three packages stayed unchanged. Edited-package AST parity
passed. Cumulative child peak RSS was 399,384 KiB for the baseline driver and
399,572 KiB for the candidate, including coordinator/compiler descendants;
these are not per-case or per-producer memory measurements.

Parser timings cover complete `dump-syntax` invocations with the lexer held in
reference mode. Each case/mode receives 20 samples after a correctness-checked
warm-up. Application timings select both frontend modes together, use 20
unchanged-command samples and five imported-function edits, and execute every
resulting native program. Auxiliary test-index/cache-plan modes stay reference;
fact/leak verification is disabled only for these measurements. All measured
commands inherit the same 2-GiB address-space constraint.

Both hosts run the same three original parser inputs. Only the candidate runs
the larger profile inputs. Modes and hosts run in fixed order on a warm machine;
the candidate's extra parser cases precede its application cases. An empty
application cache may reuse shared native objects, and the coordinator reuses
an independently qualified seed. Retained cache reports distinguish replay,
native-unit reuse and linking. These are command measurements for the selected
fixtures, not an isolated parser algorithm or a general performance forecast.

## What remains before self-hosting

The independently rebuilt native seed can already compile the four Selka
components. That is component bootstrapping. It is not yet a compiler written
in Selka compiling itself. The current checker, Core builder and native backend
remain in Zig; `src/core/pipeline.zig` still connects those implementations.
Historical self-hosted QBE/checker sources are possible salvage material but
have not been requalified against the current language and Core/LLVM pipeline.

| Remaining milestone | Completion evidence |
| --- | --- |
| Contained analyses and module/symbol handling | Explicit Selka-owned operations, matching native results and diagnostics, dependency/cache identities and measured command costs |
| Semantic checking | Names, types, generics, effects, ownership and compile-time constructs needed by compiler source work in Selka, with diagnostic and failure parity |
| Core lowering and backend | Selka produces correct Core/LLVM and native programs, including memory ownership, traps and capabilities; optimizer ports retain correctness checks |
| Compiler driver and required host operations | A Selka compiler reads projects, coordinates compilation and the external toolchain, emits diagnostics and manages artifacts without delegating compiler algorithms to the Zig host |
| Staged bootstrap and reproducibility | A rebuildable seed builds A; A builds B; B builds C from the same clean source; B/C satisfy the declared artifact comparison and compiler correctness corpus |

The first self-compilation milestone may use a deliberately restricted compiler
source profile and a simple backend. It does not require every optimization,
persistent cache or developer command to be ported first. Full compiler parity
does require those remaining behaviors or an explicitly agreed scope reduction.
Checker and backend migration are the largest unresolved bodies of work; the
completed lexer/parser boundary does not make a defensible percentage or date
estimate possible.

Here, full compiler self-hosting permits an external LLVM toolchain, native
runtime and platform libraries. Reimplementing those in Selka is additional work,
not a prerequisite for the compiler to compile itself. Required process/I/O
capabilities must be independently implemented and qualified before the compiler
source depends on them. The full-compiler feature-delay rule in
[D7](../adr/D7-feature-delay.md) and runtime boundary in
[D6](../adr/D6-runtime-boundary.md) still apply.

## Reading the source limit

The old 262,144-byte limit applied to each source file, including comments,
whitespace, newlines and multibyte encodings. At this baseline, measured physical
line averages are 32.6 bytes for `src/stdlib`, 31.9 for `tests/lang`, and 47.2 for
`selfhost/components`: approximately 8,040, 8,217 and 5,549 lines respectively.
A 1 MiB source cap is four times those byte counts, but token/AST/depth and
allocation limits remain independent constraints. Source-byte acceptance alone
does not establish complete language parity.
