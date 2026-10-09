# Typed JSON serialization and validation

The compiler now derives an implicit JSON codec for checked ordinary values.
`check-value-project` checks all source bodies, selects the document's declared
public nominal type (or built-in scalar), decodes the data into owned compiler
values, and serializes it canonically:

```sh
zig build
zig-out/bin/selka check-value-project examples/schema/main.selka \
  --value=examples/schema/message-value.json
```

Successful canonical JSON goes to stdout with status 0. Source or data errors
exit 1 with empty stdout; usage and host I/O/allocation failures exit 2. Diagnostics
identify the input path, error category, and a JSON pointer for typed value failures.
See [codec failure locations](codec-diagnostics.md) for ownership, truncation, and
raw-syntax limitations. Missing/duplicate `--value` and unrelated
flags reject. The command does not execute source code, invoke providers, or write
files. It resolves an exact qualified exported type name, rather than a local import
alias. Private/unknown nominal names reject. Root structural arrays are available
through the embedding API; the CLI selects exported nominal or built-in types.

## Wire contract

A document has exactly three fields:

```json
{"version":"typed-json-v1","type":"message::Message","value":{"case":"reading","value":{"sequence":"18446744073709551615","status":"ready"}}}
```

`type` is the checked nominal/structural name, including module qualification when
present. It must match the selected decoder type exactly. The representation of
`value` follows the checked type graph:

| Language type | JSON representation |
| --- | --- |
| Integer | Canonical decimal **string**, without suffix, plus sign, whitespace, separators, leading zeroes, exponent, or negative zero; value must fit the declared width/sign |
| Boolean | JSON boolean |
| Record | Object containing every declared field exactly once, with no extra fields |
| Fixed array | Array with exactly the declared number of elements |
| Enum-indexed table | Object containing every enum case name exactly once |
| Closed enum | Case-name string; numeric ordinal and unknown case names reject |
| Tagged union or result | Object with `case` and, only for a payload-bearing case, `value` |

The encoder emits envelope fields in version/type/value order, record fields in
source declaration order, and table keys in enum declaration order. Object ordering
on input is irrelevant. String escapes are decoded before key comparison: `x` and
`\u0078` are duplicates. Duplicate keys reject at every nesting level, including
unknown fields. Extra envelope/record/table/variant keys reject; there is no implicit
unknown-field preservation or unknown-case fallback. Payloadless cases reject even
an explicit null `value`. All integer widths retain their full range in JSON clients
whose native numbers cannot represent every 64-bit integer.

The selected **complete type graph** must support the implicit codec. Domains,
capabilities, buffers, resources, pools, handles, and move-only values reject with
`NoImplicitCodec`, including when nested in an unselected union case or zero-length
array. This prevents an implicit decoder from bypassing a private domain factory,
creating authority, or fabricating a live resource identity. Explicit domain codecs
and authority-aware transfer protocols remain future work.

## Bounds and ownership

The default `typed_json.Limits` apply to both parsing and encoding:

- 1 MiB input/output bytes, inclusive. Output length is counted before allocating
  the final output buffer. Encoding does allocate bounded intermediate JSON nodes.
- 65,536 materialized value nodes, including container values as well as leaves.
- 262,144 scanner tokens/string fragments across the entire JSON envelope.
- 64 typed value levels, with the root value at level 1. A preliminary JSON scan
  also caps container nesting at this limit plus one for the envelope, before DOM
  allocation. The embedding API accepts positive depth limits up to 128.

Limits are explicit per call in the embedding API; the CLI uses these defaults.
The node limit is checked before allocating a declared aggregate's field buffer.
The entire raw document is scanned, so an invalid or unused subtree cannot evade
syntax budgets. Both directions check depth, value count, output/input bytes, and
scanner tokens. These are work/size bounds, not a total compiler-memory byte quota
or a wall-clock timeout. JSON parsing, type-graph traversal, and materialized values
use the host allocator; allocation failure remains a host error.

`typed_json.Document.parse(allocator, bytes, limits)` owns the parsed document.
`Document.decode(allocator, checked_records, type)` returns a separately owned
`typed.Value`; it remains valid after document deinitialization. Release it with
`value.release` using the same allocator. Partial aggregate decoding releases all
already materialized fields on failure.

`typed_json.encode(allocator, checked_records, type, value, limits)` borrows its input
and returns owned bytes. It validates types, integer ranges, field counts, variant
tags/payloads, and partial-move state before emitting any bytes. These APIs require
records from a successful compiler check, rather than a caller-forged type catalog.
Typed result flags remain in the catalog and values retain their nominal identities;
future execution integration must preserve language handling obligations. Data
validation alone does not run or handle a source program's errors.

The same `Type.parseDecimal` implementation now supplies manifest and codec integer
validation while retaining each command's existing error categories.

## Acceptance and remaining integration

`tests/typed_json.py` runs through the actual CLI. It checks every integer width's
bounds, strict spellings and JSON types, both booleans, enum/union/result cases,
records, arrays, tables, deterministic round trips, explicit unknown-case rejection,
escaped duplicate keys, private names, opaque dependencies, changed schemas, invalid
private source bodies, host failures, flags, exact 1-MiB documents, 65,536-value
materialization, and 64-level typed nesting.

Unit tests inspect decoded compiler values independently of the encoder, encode
separately constructed values, verify retained ownership, reject malformed host
values, test custom budgets, release partial materializations after data errors, and
exercise every allocation failure with leak checking. Existing manifest acceptance
continues to cover the shared integer parser.

This establishes ordinary typed serialization/deserialization. Domain codec
declarations, external key mappings, callable foreign wrappers, source-level codec
operations, richer declared-input integration, and
generation budget/receipt/cache integration remain pending. The schema report is a
language-contract graph; `typed-json-v1` defines this separate wire representation.
Neither establishes a native memory layout or foreign ABI.

[Generated Python data bindings](python-bindings.md) now implement this wire contract
in standalone annotated nominal classes and bounded Python codecs, with executed
compiler/Python parity acceptance.
