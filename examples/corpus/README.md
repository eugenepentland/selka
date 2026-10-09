# Ordinary application corpus

These are authored application-sized experiments for reviewing language/tooling
integration. They are not production deployments or a sample of independent users.
The initial corpus has 13 modules and 320 canonical source lines across two programs.

## Invoice calculator

The invoice program validates three quantities in 0..99, prices a fixed three-product
catalog in cents, discounts the gross amount by ten percent (rounded down) at ten
items, and rounds a synthetic 750-basis-point tax to the nearest cent with halves
rounded up. Empty invoices have no fees. Delivery and packaging each charge 100 cents
through ten items and 200 above ten. Handling charges 100 or 250 respectively.
These are test policies, not real tax or commercial rules.

Quantity and money domains keep construction explicit. The catalog is an exhaustive
enum-indexed table. A complete conversion produces a public scalar Receipt from
internal domain-valued totals. Quantity errors propagate as typed results. The entry
reads its quantities from an imported inputs module; a declared-input manifest can
replace that module in memory during restricted evaluation.

```sh
zig-out/bin/selka run-project examples/corpus/invoice/main.selka
# 7019
zig-out/bin/selka discover-project-duplicates examples/corpus/invoice/main.selka --approximate
zig-out/bin/selka check-policy examples/corpus/invoice/main.selka --policy=examples/corpus/invoice/import-policy.json
```

## Packet decoder

The packet program borrows a bounded byte slice, validates a fixed frame, and returns
a typed heartbeat or reading message. Its frame is nine bytes:

| Byte | Meaning |
| --- | --- |
| 0 | Version, exactly 1 |
| 1 | Kind: 1 heartbeat or 2 reading |
| 2 | Payload length: 0 for heartbeat or 4 for reading |
| 3 | Sequence number |
| 4..7 | Big-endian unsigned reading; ignored padding for a heartbeat |
| 8 | Sum of bytes 0..7 modulo 256 |

Validation precedence is frame length, version, kind, payload length, checksum.
Errors map to -1 through -5 in that order. The entry prints the sequence for a
heartbeat, or sequence * 2^32 + reading for a reading. This integer encoding is an
acceptance output, not a proposed public wire representation.

```sh
zig-out/bin/selka run-project examples/corpus/packet/main.selka
# 30064771372
```

## Reviewed findings

The initial review used exact-v28 and near-v3 with production population, min-nodes 8,
90 percent line similarity, and the default one-million work budget.

| Finding | Evidence | Decision |
| --- | --- | --- |
| Delivery and packaging fees have identical structure | One 21-node exact group; both functions are called independently by pricing | Keep separate: these are independent policies with coincident amounts. The test changes delivery alone and verifies packaging source and behavior remain separate. |
| Handling is structurally close to delivery | One canonical edit across 52 body lines, explicitly showing 100 changing to 150 in the increment | Keep separate: the amount difference is intentional and changes invoices above ten items. |
| No packet duplicate candidates | Five of six functions indexed; zero exact groups and zero near pairs | No extraction follows. This is not proof of semantic uniqueness. |
| Decoder validation line exceeds the default byte threshold | 103 bytes versus 100; decode has 30 lines, one control-nesting level, and ten decision points | Retain the cohesive condition. A review signal should not force a helper or boundary change. |

Invoice discovery examined nine of fifteen functions, charged 25,142 work units,
and did not truncate. Packet discovery charged 4,858 and did not truncate. Source
hashes/bytes stay unchanged across report runs. The 21 functions are statically
reachable from their entries; exported roots are also reported. The tool correctly
leaves runtime coverage and assertion outcomes unmeasured.

## Acceptance and limitations

`zig build test` runs `tests/corpus_review.py` in VM-only mode. Its independent
Python expectations use a
price-vector calculation and Python byte decoding, never the language VM or generated
bindings to calculate expected execution results. It covers 24 invoice cases and 24
packet cases, including quantity extrema/rejection, fee/discount boundaries, tax
rounding, maximum unsigned readings, short frames, each error category, and seeded
valid inputs. Every case executes with general/arena VM memory: 96 oracle checks
per compiler host build mode. The default acceptance does not compile guest C.

Existing native acceptance is optional through `zig build test-native` or directly
with `python3 tests/corpus_review.py --compiler zig-out/bin/selka --native --zig /path/to/zig`.
That mode adds native -O0/-O2 with undefined-behavior sanitization, retaining the
historical 192 oracle checks. Native execution is outside the active roadmap goal.

The driver checks formatter idempotence through project checking, exact/near discovery
determinism and non-mutation, default quality reports, explicit dependency policies,
policy rejection of a new cross-boundary import, added-field/variant/table rejection,
typed JSON values, and generated Python data-binding round trips. Invoice declared
inputs change evaluation without overwriting checked-in input source. Independent
Python expectations and generated binding artifacts stay outside production duplicate
analysis; intentional-policy decisions are recorded here rather than suppressed.

The review found useful integration rather than a new compiler defect. Domain-valued
internal totals use an explicit conversion for ordinary JSON/data bindings.
Domain codecs and callable Python wrappers were added after the initial review;
this corpus exercises its documented conversion and data-binding path. Fixed arrays keep these applications bounded;
unbounded catalog ingestion, real transport I/O, performance validation, generics,
and production-user corpus evidence remain separate work. Neither this corpus nor
its green tests establish production readiness or exhaust all input behavior.
