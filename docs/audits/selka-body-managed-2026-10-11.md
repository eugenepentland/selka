# Selka-owned string and byte body checking

Date: 11 October 2026. Integration branch: `codex/selka-body-managed-20261011`.
Implementation commit: `9e67a52e9`. This B2 wave extends the qualified B1 scalar
body checker. Three Sol agents
implemented the producer, native wire validation, and installed qualification;
the coordinating worktree integrated catalog projection, routing, and identity.

## Completed boundary

The seventh Selka component, `body-check`, now checks ordinary nongeneric
functions using copyable `str` and `bytes` values alongside `int`/`i64`, `bool`,
and `Unit`. Its managed closure includes literals, annotations, parameters and
returns, locals, snapshots and rebinding, mutable arguments, calls and string
defaults, length, negative indexing, concatenation, comparisons, and `+=`.
The producer constructs every typed row, function, local metadata field, and
per-function range from raw syntax. Explicit integer identity conversions retain
their native cast rows, including the conversion after a byte index.

Text literals emit Unicode scalar-value `u32` children; byte literals emit `u8`
octets. Byte indexing emits the native narrow index followed by an `int` cast.
Contextual byte literals expected as `str` decode UTF-8. Byte literals in scalar
expected-type contexts require fixed-array schema interning and remain explicit
profile refusals. Byte defaults preserve native `E_DEFAULT_ARGUMENT`.

The retained native common catalog supplies only the actual prelude identities
and element kinds. It runs before the producer; no native body checking or
generic-contract body work supplies producer decisions. A missing or colliding
prelude descriptor is nullable and never guessed. Scalar-only bodies remain
admissible without managed descriptors. B2 does not append catalog schemas.

`MYLANG_BODY_CHECK_MODE=reference|shadow|component` retains its existing behavior.
Reference is the default. Component mode adopts a structurally validated batch
without native body fallback. Shadow compares complete uncached native tables,
including intermediate rows, spans, local/evaluation metadata, diagnostics and
import flags. Common catalog/entry import observations are merged before body
comparison; the producer's own import observations remain independently checked.

Native catalog construction, entry validation/adaptation, effects and origins,
domain codecs, warnings and publication remain explicit host stages. Lists and
other collections, nominal members, generic specialization, resources, checked
failure signatures, methods, slices and other unsupported forms remain outside
this profile. They are not silently delegated back to native body checking.

## Protocol and identity

Body-check protocol/schema is now **1/2**. Schema-1 manifests and exchanges fail
closed. Frame and payload magic remain `SLKBCK01`, `SLKBKI01` and `SLKBKR01`.
The request adds `Catalog{string:?Sequence,bytes:?Sequence}`, with each descriptor
carrying its authoritative type identity and element kind. Batch fields remain
`nodes`, `statements`, `functions` and `ranges`. Existing nonce, request-digest,
sealed executable authentication and publication revalidation remain enforced.

Native validation admits only matching managed identities, checks literal
octet/codepoint bounds including surrogate exclusion, and validates managed
array/index/length/binary relationships alongside existing graph ownership,
calls, ranges and acyclicity. The validator establishes structural admission;
semantic correctness is established by the authenticated producer and shadow
qualification. Managed element mutation and schema interning are not admitted.

The selected body/frontend cache identity domains advance for schema 2. The
all-reference boundary identity stays unchanged. Limits remain 64 MiB per
complete frame, 1,048,576 logical values, 4,194,304 edges, depth 256 and a 512 MiB decoded
allocation budget. Typed node/statement tables remain capped at 262,144 each;
functions and aggregate locals at 65,536. Literal children count toward these
bounds. The wire budget is not a new production process-memory guarantee.

See the [wire contract](../../selfhost/components/body_check/WIRE.md),
[producer scope](../../selfhost/components/body_check/README.md), and
[qualification guide](../tooling/body-check-component-qualification.md).

## Artifact identities

The final Debug and ReleaseFast installations contain the same seven component
manifests and verified artifact bytes. Full inventories and the unchanged seed
pin are in [artifacts.json](evidence/selka-body-managed-20261011/artifacts.json).

| Artifact | SHA-256 |
| --- | --- |
| Debug host | `115b7a22c9420dba146fc66abd2b00f7d9c0c31f115e661eae576e57a4c3519c` |
| ReleaseFast host | `3c9f1f1c1806eadd21c0281b4cf216d74e2a4854415a4176e2010416b99c3496` |
| Qualified frozen seed | `c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b` |
| Body-check artifact | `31780c2b8ab565accdcac733f6a4fc5ad39d1812d04f1e618fb0df1c63be8eac` |

The body build key is
`78c9ccd846d96ad3b73592fe141b29b30e269b9ce8038886ceb8cb014e6a89d0`.

## Qualification

The [full gate](evidence/selka-body-managed-20261011/full-gate.log.gz) passed
**131/131 build steps**, reporting **2,710 passed tests**. Its 29 native Guardian
verdicts report 2,710 passed, zero failed and zero selected tests skipped. The
24,795 aggregate skipped slots belong to other shards. The
[machine-readable totals](evidence/selka-body-managed-20261011/gate-summary.json)
record the exact accounting. Formatting and cache verification passed 25/25
steps, including two separately executed registry tests. Whole-tree Guardian
passed all 88 blocking checks. Final Debug and ReleaseFast installations each
passed 14/14 steps. Final documentation and formatting passed 23/23 steps.

All **49 pure producer tests per mode** passed uncached in normal mode and
release mode with fact/leak checks. The focused native suite passed 34/34;
its cases are also covered by the full gate. Native tests cover authoritative
catalog projection, schema-1 manifest/exchange refusal, managed graph admission,
codepoint/octet bounds, and malformed identities/index relationships.

The installed corpus has 59 fixtures: 29 successes, 23 exact source errors and
seven native-valid explicit profile refusals. Twenty successes execute generated
programs; typed and lowered output are compared for the applicable successes.
The managed additions exercise Unicode and negative indices, arbitrary octets,
string defaults and named arguments, imported functions, managed mutation, and
snapshots across rebinding and later mutable arguments. The byte fixture pins
both the implicit byte-index conversion and the explicit integer cast.

| Installed lane | Workflows | Comparisons | Warm deployment | Live sessions |
| --- | ---: | ---: | ---: | ---: |
| Debug normal, including component edit | 149 | 596 | 30 | 4 |
| Debug release/facts/leaks | 149 | 298 | 30 | 4 |
| ReleaseFast host, release/facts/leaks | 149 | 298 | 30 | 4 |

Every lane passed with zero failures or skips. Each includes one valid and
15 malformed exchanges, eight authenticated forged replies, and two
cross-package publication failures. Managed graph forgeries are covered by
native unit tests; installed reply mutations retain the scalar capture.
Installed workflows use an empty PATH; Python remains developer orchestration.

The [normal/edit receipt](evidence/selka-body-managed-20261011/gate-normal.json)
asserts that the private coordinator starts with the exact installed body
package. The operational edit changes its key to
`997198a8d95557a386045c7460be4ba5976ab52cb6605209c42e6a2256858b56`
and artifact to
`8a4b676693970fb7b129690419ac867d30bab43885868ef222383f01fc94cdb8`,
while preserving the host and other six packages. The
[Debug release receipt](evidence/selka-body-managed-20261011/gate-release.json)
and [ReleaseFast receipt](evidence/selka-body-managed-20261011/release-host-qualification.json)
retain the other lanes; the latter also has an exact
[command/environment record](evidence/selka-body-managed-20261011/release-host-command.json).

Earlier red runs remain evidence, not exclusions. A full disk stopped the first
root focused run during coordinator compilation; no tests ran in that attempt.
Only regenerable integration caches and an archived earlier-wave source scratch
were removed. A concurrent producer write was truncated by the same disk failure;
it was recovered from the prior source and known helpers, then fully retested
before integration. The recovery record and producer logs are retained.
A Guardian condition-complexity failure was resolved by splitting a catalog
representation guard. Initial installed qualification and the first full-gate
attempt exposed the unsupported explicit `int(bytes[index])` call. Commit
`807ffd073` preserves its native cast row and adds a regression; all final
matrices above include the unchanged fixture. No fallback or comparison was
weakened. [commands.txt](evidence/selka-body-managed-20261011/commands.txt)
identifies the passing commands and earlier failing logs.

## Isolated measurements

The completed run held FIFO gate ticket 145 and all three build reservations,
pinned to CPUs 2,3,10,11. Every holder exited successfully and released its lock.
The [admission log](evidence/selka-body-managed-20261011/timing.log),
[completed receipt](evidence/selka-body-managed-20261011/body-managed-timing-receipt.json)
and retained launchers record the exact commands and identities.

The baseline is the prior B1 seven-package ReleaseFast host at `b7b62cdc6`,
SHA-256 `20fb7facf405ff440f38703d9c600ed9cbd74af904fbeba5a45571bc159ea273`,
with body schema 1. The candidate is the schema-2 installation above. Both
hosts check the same two-module string/byte workload; the baseline uses native
reference checking. Other six selectors remain reference throughout. The
baseline coordinator uses a verified seed-only pin snapshot, explicitly not a
full source build closure; its provenance receipt is retained.

Both hosts' original and five edited native workloads were prewarmed before
any timed run. The program returns seven initially; every implementation edit
changes the byte length and verified result. Values below are wall-clock
milliseconds; the fresh application-cache row has one sample and other rows
show medians.

| Workflow | B1 host/reference | B2 host/reference | B2 host/body component |
| --- | ---: | ---: | ---: |
| Fresh application cache (one sample) | 15.13 | 15.60 | 71.77 |
| Warm executable replay (20 samples) | 1.77 | 1.80 | 9.07 |
| Implementation edit/link (5 samples) | 15.21 | 15.29 | 71.28 |
| Project body checking (20 samples) | 1.07 | 1.06 | 4.93 |

Component selection adds about 7.27 ms to warm replay, 55.99 ms to edit/link,
and 3.86 ms to project checking relative to the B2 reference control. These
small-fixture samples establish neither large-project scaling nor a compiler
speedup. Reference remains the default.

The [baseline samples](evidence/selka-body-managed-20261011/body-managed-timed-baseline.json)
and [candidate samples](evidence/selka-body-managed-20261011/body-managed-timed-candidate.json)
retain every cache receipt. All fresh/edit builds reused three native units,
compiled zero and linked once; all warm samples replayed the executable with
zero compiler subprocesses. Shared native unit/runtime/toolchain stores were
warm. These are not cold native-code measurements. Fact/leak checks were
disabled for timings and qualified separately. Cumulative child high-water RSS
was 47,164 KiB for baseline and 47,176 KiB for candidate; this covers whole
measurement processes including seed/native tools, not per-exchange memory.

## Bootstrap position

Seven packages still build independently with the unchanged qualified native
seed. This wave expands the body checker; it does not add an eighth package or
establish a compiler fixed point. The body checker cannot yet check its own
source, which uses lists, records, generics and checked failures.

Next comes list/aggregate body checking with a bounded catalog-interning
contract, followed by nominal member operations, generic specialization,
checked failures and resources, and the remaining native semantic postpasses.
Core lowering, code generation and driver/build ownership also remain before
an entirely Selka compiler and a reproducible stage-to-stage bootstrap can be
claimed. The C runtime and pinned Zig/LLVM toolchain can remain external
dependencies of a self-hosted compiler; rewriting them is not a prerequisite.
