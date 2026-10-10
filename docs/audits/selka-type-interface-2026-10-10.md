# Selka-owned type and interface resolution

Date: 10 October 2026. Integration branch:
`codex/selka-type-interface-20261010`. Production source commit: `8adb2c890`.
Three Sol agents supplied the native wire validation, Selka producer, and
installed qualification, with compiler integration in the coordinating worktree.

## Completed boundary

`type-interface` is the sixth independently seeded Selka component. It owns the
whole-project signature checking pass after declaration collection, including
interface type and constraint resolution, canonical re-exports, exported type
privacy, generic and structural bounds, application arity and first-error order.
The request carries raw AST signature/type catalogs and indexed module facts;
Selka constructs its own traversal and indexes. The host supplies no pre-resolved
semantic worklist. One exchange checks the whole project.

`MYLANG_TYPE_INTERFACE_MODE` accepts `reference`, `shadow` and `component`, with
reference remaining the default. Component mode skips native signature checking
and adopts the validated import-use flags. Resolution receipts are validated
as boundary evidence. Shadow runs both implementations and compares complete ordered receipts or exact diagnostic
code/message/site/related values. All frontend shadow modes disable replay.
Verified identities participate in syntax, semantic, executable, test-result and
live-session validity.

The host retains filesystem discovery, dependency ordering and AST projection.
Body checking, specialization, later dynamic resolution, effect inference,
contract rendering and alias-cycle checks remain native. A later native cycle
error is not evidence that this signature batch detects cycles. Successful
resolution receipts are boundary evidence, not a replacement for typed body IR.

## Protocol and admission

The new package uses protocol/schema 1/1 with `SLKTIF01` framing and
`SLKTYI01`/`SLKTYR01` payloads. Existing package versions, seed pins and the
qualified source profile remain unchanged. Nonce and complete request SHA-256
bind each reply. Execution uses authenticated sealed executable bytes, and every
selected frontend identity is revalidated before publishing either success or a
source diagnostic. Mutation of another selected package therefore cannot turn a
stale source-error reply into an accepted result.

| Resource | Limit |
| --- | ---: |
| Modules | 4,096 |
| Source per module / aggregate | 1 MiB / 8 MiB |
| Source path per module | 16 KiB |
| Aggregate symbols, type rows, declarations, nested rows/edges | 65,536 each |
| Imports per module / aggregate | 4,096 / 65,536 |
| Aggregate non-source strings | 8 MiB |
| Generated lookup key bytes per sorted index | 8 MiB |
| Recursive type depth, including the leaf | 256 |
| Successful resolution receipts / owned reply strings | 65,536 / 8 MiB |
| Complete request or reply frame | 64 MiB |

Counts are admitted before allocation. Scalar type edges and constraint subjects
count toward the nested budget. Parent/child containment, duplicate same-kind
spans, module order, derived imported-module flags, canonical identities and
raw-source name association are validated. Reply checks enforce structural
validity and exact import-usage consistency with receipts and initial flags.
They do not rerun the checker or prove that a hostile structurally valid producer
reported every required semantic resolution. Semantic completeness relies on
the verified producer and shadow qualification. These are opt-in component
profile limits, not newly imposed native frontend limits.

The normative [wire contract](../../selfhost/components/type_interface/WIRE.md)
and [qualification guide](../tooling/type-interface-component-qualification.md)
describe field order and reproducible developer workflows. Installed commands
run with an empty PATH; Python is used only by developer qualification drivers.

## Artifact identities

| Artifact | SHA-256 |
| --- | --- |
| Qualified frozen seed | `c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b` |
| Debug host | `c9e8987c1180996911505500b008850ffe328432bf63ff08081f7ef1cce30c96` |
| ReleaseFast host | `16d3c3bab8160aaf30ce5e9206a7259fb3d50c85d4be7b2760c65798bc161bc3` |
| Type/interface artifact | `0dbff24e43125d9bcb0f1429f109650843e43945d07ed344290ee8172e02010a` |

The type/interface build key is
`956c45e7de93c862ddebd291481b33479e29f5b1c35fafc7fe74af5ce8fd7f06`.

## Qualification

The final Debug and ReleaseFast installations each passed 14/14 build steps.
The hardened focused native run passed 25/25 selected tests, including admission,
reply validation, allocation failure and signature error precedence. Packaging,
verification-cache tests and formatting passed 30/30 build steps. These focused
counts overlap the full gate and are not additional unique tests.

The pure producer has 27 ordinary tests and one exact-profile test, run normally
and with release/fact verification and leak checking. The profile test uses an
explicit 100-million-step budget and proves admission of exactly 65,536 nested
edges and refusal of the next edge. Ordinary tests retain their default budget.
Depth tests separately distinguish 256 nodes, including the leaf, from 257.

The installed corpus covers 29 source fixtures, deterministic interface listings,
all six component entry sources and mixed selection of the four frontend
components. Exact status, stdout and diagnostic-v1 stderr include byte locations,
related sites, privacy, canonical re-exports, generic/structural bounds, arity and
native first-error precedence. A dotted qualifier containing internal whitespace
is explicitly a parser refusal; it is not counted as successful type resolution.

Each installed lane also verifies one valid exchange, 35 malformed-request
refusals, eight authenticated but malformed reply refusals, and two cross-package
publication failures. The latter forward a real valid source diagnostic unchanged
after removing another selected frontend manifest: both type modes must return
host status 2. The focused regression was observed failing before the aggregate
identity check was added and passing afterward. Its pre-fix status 1 is retained
as an explicitly labeled [tool-output transcription](evidence/selka-type-interface-20261010/publication-red-transcription.json),
not an original redirected log; the final green JSON/log is retained directly.
Cache-enabled test receipts prove two tests reused in component mode and both rerun in shadow mode. Developer
qualification imposes a 2 GiB address-space ceiling, bounded capture and deadlines;
this does not establish a new production memory guarantee.

The separately installed ReleaseFast host passed 60 workflows, 120 comparisons,
30 warm deployment checks and four live-session checks, plus every transport,
forged reply and publication check above, with zero failures or skips. Its
[receipt](evidence/selka-type-interface-20261010/release-host-qualification.json)
and [command receipt](evidence/selka-type-interface-20261010/release-host-qualification-receipt.json)
are retained separately from the full gate's Debug host.

Initial integration failures were repaired before qualification: Zig 0.17
reflection API changes, unfinished package staging while parallel work converged,
Guardian style/spec findings, and a diagnostic encoder that omitted commas.
The encoder now covers printable ASCII and has a regression for the actual failing
constraint message. Review also aligned host/producer nested budgets and stricter
span, module-authority and canonical-source admission. Initial failure logs are
retained alongside successful runs, not treated as exclusions.

| Installed Debug-host lane | Workflows | Comparisons | Warm deployment checks | Live checks |
| --- | ---: | ---: | ---: | ---: |
| Normal, including component-only edit | 60 | 240 | 30 | 4 |
| Release/facts/leaks | 60 | 120 | 30 | 4 |

The gate passed all 28 uncached pure tests in each mode and all installed checks
with zero failures or skips. The
[normal](evidence/selka-type-interface-20261010/normal.json) and
[release](evidence/selka-type-interface-20261010/release.json) receipts retain
package identities, workflow output hashes, deployment changes and cache checks.
The normal lane privately edits operational `checking.check` code and rebuilds
through the native coordinator. Its key becomes
`d3cb561632b97d4e217550e6289524a9dcff1b33a637e7092487d622b8794401`
and artifact SHA-256 becomes
`5963d39d6c1c5bea0a675cd558696f15a0b03fba00e48f1fffabdbd8d3d8bbec`.
All sixty workflows are repeated against that deployment; the host and the other
five packages remain unchanged. This does not bypass coordinator qualification
by calling the seed directly.

The full gate on `8adb2c890` passed **128/128 build steps**. Its 29 native
verdicts reported **2,684 passed, zero failed and zero selected tests skipped**.
The build aggregate's 24,509 skipped slots belong to other shards. The complete
[gate log](evidence/selka-type-interface-20261010/full-gate.log.gz) and
[machine-readable totals](evidence/selka-type-interface-20261010/gate-summary.json)
are retained. The existing declaration and frontend component gates also passed.
The [command record](evidence/selka-type-interface-20261010/commands.txt) describes
admission, private caches and reproducible checks.

A separate whole-tree Guardian run passed all 88 blocking checks. The final
documentation and formatting check passed 23/23 build steps.

## Isolated measurements

The successful run held FIFO gate ticket 107 and all three build reservations
(tickets 1020–1022), then pinned measurements to CPUs 2,3,10,11. Every reservation
exited successfully and was released. The [admission log](evidence/selka-type-interface-20261010/timing.log),
[completed receipt](evidence/selka-type-interface-20261010/timing-receipt.json)
and retained launchers record exact commands and identities.

The baseline is the prior five-package ReleaseFast host, SHA-256
`9d4390768195d5b2022f7cc910c753c6dbb0e0487bf965536574cf1c07feb5ee`.
The candidate is the separately qualified six-package ReleaseFast installation
above. All other component selectors remain reference. Both runs verify behavior
on the same small imported project. Values are wall-clock milliseconds; the
fresh-application-cache row is a single sample, and the other rows are medians.

| Workflow | Prior host/reference | Candidate/reference | Candidate/type component |
| --- | ---: | ---: | ---: |
| Fresh application cache (one sample) | 17.35 | 18.70 | 48.56 |
| Warm executable replay (20 samples) | 1.80 | 2.12 | 5.72 |
| Implementation edit/link (5 samples) | 16.77 | 17.76 | 43.45 |
| Interface listing (20 samples) | 1.49 | 1.71 | 18.11 |

Component mode adds 3.60 ms to warm replay, 25.68 ms to edit/link, and
16.40 ms to interface listing compared with candidate reference: approximately
2.70×, 2.45× and 10.60× respectively. Reference remains the default. Candidate
reference also measured slightly slower than the prior host on this fixture;
these limited samples establish neither a broad compiler regression nor a speedup.

The [baseline](evidence/selka-type-interface-20261010/timing-baseline.json) and
[candidate](evidence/selka-type-interface-20261010/timing-candidate.json) retain
every sample and cache report. Fresh application caches and edit builds reused
all three native units and linked; shared unit/runtime/toolchain stores were
warm. Warm rows replayed executables with zero compiler subprocesses. These are
not cold-native-code or cold-toolchain measurements, nor a large-project cost
claim. Larger input admission is established by separate boundary tests.

Cumulative child high-water RSS was 46,952 KiB for baseline and 47,072 KiB for
candidate. This covers the complete measurement process, including seed
verification and native tools; it is not per-exchange component memory. Fact/leak
checks were disabled for timing and qualified separately.

## Bootstrap position and next work

Six components now build independently with the frozen native seed: test-index,
cache-plan, lexer, parser, declaration indexing and type/interface checking.
This proves incremental compiler ownership in Selka; it does not prove that the
complete compiler can compile itself.

The next substantial boundary is body checking: expression and statement typing,
local scopes, calls and generic specialization, with a validated typed-body
result suitable for existing Core lowering. Remaining native interface consumers
(effect inference, contract rendering and later dynamic resolution) need explicit
ownership in that work rather than being counted as already ported. Core
lowering, optimization, backend emission and command coordination follow, then
clean A→B→C compiler bootstrap and artifact/corpus reproducibility. Body checking
and backend migration remain substantially larger than this signature stage.
