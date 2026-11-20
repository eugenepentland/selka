# Typed JSON failure locations

Typed JSON validation now reports a JSON pointer for checked value failures. For
example, an out-of-range element inside nested variant payloads is reported as:

```text
value.json: invalid typed JSON: CodecIntegerOutOfRange at JSON pointer "/value/value/value/samples/1"
```

The pointer addresses the typed-json-v1 envelope, whose root value is `/value`.
Record fields and enum-table keys extend the path by name; fixed arrays extend it
by zero-based index; variant payloads extend it with `/value`. A bad or missing
variant discriminator uses `/case` within its containing value. Unknown/private root
types, declared-type mismatches, and unsupported implicit-codec type graphs use
`/type`. Unsupported document versions use `/version`.

Missing record/table fields identify the first missing field in schema order. Object
key completeness is checked before materializing fields. Extra object fields report
the containing object. Incorrect array lengths identify the first missing or excess
index. Malformed host value shapes report the affected value during encoding.
Byte/token failures after encoding refer to the document root when there is no more
specific value location. Error categories and exit statuses remain unchanged.

## Ownership and bounds

The new additive embedding APIs are:

- `Document.parseWithLocation(allocator, bytes, limits, ?*Location)`
- `Document.decodeWithLocation(allocator, records, type, ?*Location)`
- `encodeWithLocation(allocator, records, type, value, limits, ?*Location)`

Existing parse/decode/encode calls retain their signatures and behavior without
requesting a location. Each located operation resets the supplied location before
work, so a subsequent success cannot retain an old failure path. `has_path` indicates
whether a meaningful pointer was captured; `text()` returns its bytes.

`Location` owns a 4-KiB buffer, independent of the JSON document and checked catalog.
It remains usable after both are destroyed. Traversal uses one bounded path stack
per encoder/decoder, following the existing maximum 128-level API depth limit. It
copies the deepest failure path once, rather than allocating strings while walking
values. Out-of-memory failures do not acquire data-error locations. Decoding rechecks
limits, including when an embedding caller mutates a parsed document's limits.

Pointers escape `~` as `~0` and `/` as `~1`. A path that does not fit retains a UTF-8
prefix and sets `truncated`; escape pairs are not split. CLI rendering quotes the
pointer as JSON and explicitly appends `(path truncated)`. A truncated prefix is not
presented as a complete location. Location capture allocates nothing; final CLI
message formatting still uses the ordinary host allocator.

Failures before typed traversal, including raw JSON syntax and duplicate-key errors,
may have no pointer. They retain the input filename and error category. The API does
not invent a nested location when parsing has not established one.

## Acceptance

Actual CLI tests check nested result/union/record/array failures, integer range errors,
missing payloads/discriminators and table keys, excess array elements, version/type
selection, and long diagnostic paths. Unit tests verify encoding malformed native
values without consuming ownership, locations surviving document/catalog teardown,
reset after success, pointer escaping, ASCII/UTF-8 truncation, and mutated limits.
The allocation-failure scenario now exercises located encoding/decoding and verifies
that host allocation failures retain their classification. Existing partial-decode
cleanup, value budgets, byte-for-byte wire parity, and generated binding tests remain
in the full Debug/ReleaseFast suite.

These diagnostics improve the existing ordinary-value codecs. Domain codecs,
source-level codec/input integration, callable foreign wrappers, generics, broader
native operations, and finer incremental compilation remain separate roadmap work.
