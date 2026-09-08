# Library guide for development-velocity corpus v1

Use these reusable APIs before writing application code. This guide describes
library mechanisms and bounds; TASK.md defines application policy. The same
process contract applies to .my and Python. Python participants may use the
standard library only. .my modules below are ordinary compiler-provided modules.

## JSON, strings and safe output

`std_json_view` exposes document-local `Node`, named `Kind`, `root`, `required`,
`field`, `integer`, `boolean`, `count`, `at`, `key`, and linear
`children/current/member_key/advance` cursors. `required` reports absent separately
from a present null. `integer_between` and `count_between` check inclusive limits;
`integer_or` and `boolean_or` default only for absent fields. `only_fields` uses
`Name {start,end}` ranges into caller-supplied allowed-name bytes, with separate
required-field checks when necessary. Match typed errors or propagate them
through the supplied application wrapper; schema validation is application work.

`std_json_view::text(heap, doc, node, limit: u64) -> std_bytes::Built` materializes
the decoded UTF-8 bytes, including embedded NUL. It does not normalize or limit
strings to ASCII. Missing sentinel node zero gives `absent`, nonstrings
`wrong_type`, invalid other nodes or excessive byte length `bounds`.
`std_bytes::Built.ok` owns a Bytes buffer. Borrow it as `bytes[..]` for byte APIs.
Copies of JSON Node handles do not copy strings; keep the document alive while
using its nodes. IDs in this corpus have an additional ASCII application schema.

`std_json_builder::object(heap, limit: i64)` and `array(heap, limit: i64)` create
bounded owned builders. `string_field`, `integer_field`, `bool_field`, and
`null_field` add object members; `array_string`, `array_integer`, `array_bool`,
and `array_null` add array elements. String APIs perform JSON escaping.
`object_field`/`array_field` consume a child builder into an object;
`array_object`/`array_array` consume a child into an array. Finish each top-level
builder exactly once with `finish` or `finish_array`, returning owned bytes.
These APIs already support all nested output shapes in the corpus. No generic
JSON-node clone or unsafe raw-JSON concatenation helper is required. Adding a
nested builder transfers ownership; do not finish or reuse it afterward.

`std_strings::pad_right(heap, text, width: u64, fill: u8, limit: u64)` pads to a
minimum BYTE width without truncating. `join(heap, text, parts: &[]Range,
separator, limit: u64)` joins half-open `Range {start,end}` descriptors into a
shared byte slice. Both return `std_bytes::Built`; invalid spans/output bounds
are explicit errors. Empty spans remain present; an empty span list joins to
empty bytes. These correspond to the byte/ASCII use of Python `str.ljust` and
`str.join`, not Unicode terminal column width. `std_bytes::compare` provides
lexicographic byte comparison; `std_strings` also provides prefix/suffix checks,
splitting ranges, trimming, replacement and signed/unsigned formatting.

## Maps, identifiers and owned values

Do not pass an owned Bytes buffer as a `std_map` key. `std_map::Map<K,V>` requires
`K:equality` and `V:copy`; it does not supply dynamic-string equality. Its
`create`, borrowed `lookup`, mutable `put_mut`/`remove_mut`, and `clear` are useful
for integer keys and copyable record values. Check insertion/full status.

For corpus IDs and input paths, use `std_hash_bytes`:

- `from_bytes(&[]u8) -> KeyResult` copies 0..256 bytes into `Key`. Larger inputs
  fail; no borrow or owner is retained. This covers 32-byte IDs and 256-byte input
  paths. `key_equal` compares logical length/content and `key_hash` hashes it.
- `create<V:copy>(heap, capacity: u64) -> Created<V>` allocates fixed-capacity
  storage; capacity is a slot count, not a promise of automatic growth.
- `lookup<V>(&Map<V>, Key) -> std_map::Value<V>` returns `none` or `some(value)`.
- `put<V>(&mut Map<V>, Key, value) -> PutStatus` returns `inserted`, `replaced`,
  `full`, or `invalid`. `remove` returns `none`/`some`; `count` and `clear` are
  available. Internal empty/deleted slots are not application entries.

Values may be copyable application records or integer IDs. If a representation
uses compact IDs, `std_hash_bytes::Map<i64>` supplies the key-to-ID lookup; owned
text is not needed for the map key. There is no requirement to create a separate
string-interner library. A document node index alone is not string identity:
different nodes may decode to equal strings. `std_json::compare(doc,a,b)` compares
decoded string-node text, so callers can retain node indices with document context.

`std_owned_map::Map<K:equality,V:storable>` permits owned VALUES, while its keys
still require equality. `create`, `put(&mut map,key,value)`, `take(&mut map,key)`
and `clear` transfer/release ownership. It is not a byte-string-key map and does
not provide a borrowed get operation. Use it when transferring an owned value
under an integer key fits the data model. `std_owned` and owned buffers support
storable elements; ordinary `std_collections` vectors support copyable elements.

## Sorting, arrays, paths and encoding

`std_collections::filled<T>(heap,count,value)` initializes owned storage;
`vector<T>`, `append_many`, `find`, `contains`, `reverse`, and `clear` are also
available. `sort_by<T:copy,C:copy>(values:&mut []T, context:&[]C,
before:fn(&[]C,T,T)->bool effects())` sorts with synchronous borrowed context.
`lower_bound_by` uses the same comparator signature. Callbacks cannot retain
borrowed context. Use the same ordering for sorted lookup and sort.
`std_order::Item` offers lexicographic range descriptors and payloads for sorting,
heap operations and lower-bound search over shared integer key bytes; this is
an alternative when precomputed key ranges are convenient.

`std_path::absolute_valid(path)` accepts root `/` or `/` followed by a valid
strict relative path. `absolute_prefix(path,prefix)` requires a full component
boundary. `absolute_join(heap,base,suffix,limit)` accepts an absolute base and
empty/relative suffix, inserts one separator, and returns Built. General output
is bounded to 4095 bytes; malformed paths and output bounds are distinguished.
The corpus's narrower ASCII component grammar and 256-byte input ceiling remain
schema checks. Existing `valid/component/basename/dirname/extension/join` keep
their relative-path contracts. No API accesses or normalizes the host filesystem.

`std_encoding::read_uint(bytes,offset,width,little)` returns a checked `u64`;
`write_uint` writes into a mutable slice. Width is 1..8 bytes, with explicit
endianness. `hex_encode`/`hex_decode` provide bounded byte/hex conversion.
`std_math` provides generic integer min/max and explicit-empty-default slice
min/max. Do not substitute floating-point math for the corpus's exact integers.

## Relevant API groups by task

| Task | Reusable mechanisms |
|---|---|
| data-rollup | JSON view, byte-key map with copyable values, comparator sort, integer builder |
| ascii-table | JSON text materialization, byte padding/span join, array/string builders |
| config-layers | Required/optional JSON fields and kinds, scalar builders, byte comparisons |
| quota-boundary | Checked JSON integer bounds, exact integer arithmetic, boolean array builder |
| lru-cache | Byte-key map, copyable record/vector storage, bounded collection operations |
| ttl-boundary | Byte-key map, record/vector storage, exact integer comparison, sorting |
| record-frames | Hex decoding, bounded byte storage, endian write, hex encoding |
| little-endian-read | Hex decoding and checked endian read |
| snapshot-diff | Absolute lexical validation, byte-key map, comparator sorting |
| mount-routing | Absolute lexical validation, component-prefix test, bounded join |
| inventory-reservations | Byte-key lookup, record/vector ownership, scalar/nested builders |
| atomic-transfers | Copyable record/vector state, byte-key lookup, nested builders |

The corpus does not require a generic LRU policy, expiry scheduler, configuration
merge engine, reservation engine or transaction engine in the standard library:
those are the application behaviors being evaluated. The supplied runtime owns
transport parsing/serialization boundaries. No mechanism listed here is a claim
of full Python library breadth or proof that an application passes its tests.
