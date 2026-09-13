# Standard library

Ordinary application code uses builtin `list[T]`, `str`, and `dict[K, V]` with GC; see the [Python-style guide](python-syntax.md). The explicit-storage APIs below remain useful for bounded binary I/O and host interfaces. Their byte-oriented limits do not apply to managed Unicode strings.

Standard modules are embedded in the compiler. Import their names directly;
projects do not need to copy these files. Allocation and external authority stay
explicit. The installed `--features` report identifies the executable actually
in use; this document describes the source tree.

| Area | Modules | Available operations |
| --- | --- | --- |
| Bytes and text | `std_bytes`, `std_text`, `std_strings` | Byte comparison/search, UTF-8 validation, decimal integers, escaping, prefix/suffix, ASCII trim, byte-delimited splitting as index ranges, replacement, bounded builders and base 2–36 integer formatting |
| Formatting | `std_math`, `std_format` | Integer extrema and empty-default reductions, nominal binary64 arithmetic, bounded decimal parsing and fixed-point formatting |
| Collections | `std_collections`, `std_map`, `std_set`, `std_borrowed_set`, `std_queue` | Bounded vectors, linear maps/sets, queues, borrowed lookup/mutation, append-many, clear, stable filtering/deduplication, sorting/search |
| Application primitives | `std_order`, `std_counter`, `std_ascii`, `std_iter`, `std_graph` | Range-key sorting/search and heaps, bounded frequencies, ASCII classes, distinct pairs and directed graph readiness |
| Managed collections | `std_list` | Allocator-free shared lists, automatic growth, value reads, fixed-slot replacement and cycle collection |
| Owned collections | `std_owned`, `std_owned_map` | Storable owned vectors and linear maps, consuming insertion/replacement, extraction, shrink-only truncation and deterministic cleanup |
| Hashing | `std_hash`, `std_hash_map`, `std_hash_set`, `std_hash_bytes`, `std_hash_byte_set` | Deterministic hashes, bounded u64-key and inline byte-key tables, deletion/tombstones, replacement and explicit slot iteration |
| Data interchange | `std_json`, `std_json_view`, `std_json_builder`, `std_encoding` | Typed/document JSON, checked node access, nested JSON construction, endian integers, hex and canonical padded base64 |
| Arguments | `std_args` | Explicit token classification, long option names/values, `--` terminator and checked integer values |
| I/O and paths | `std_io`, `std_path`, `std_fs` | Buffered reads/writes, exact reads, bounded complete-file/line reads, retryable progress, typed open modes, file convenience functions, metadata, bounded directory listings and checked relative path components/joining |
| Time/random | `std_time`, `std_random` | Checked durations and wall-clock instants, explicit clock/entropy capabilities, seeded SplitMix64, bounded unbiased range sampling and byte fills |
| Results | `std_result`, `std_unit` | Copyable Option/Result, categorized errors, owned error context and Unit |

## Contracts to use consistently

Borrowed collection operations preserve their owner. Builder operations consume
and return an owner on success; their documented failure releases intermediate
output. Buffered I/O operations return state and partial progress on recoverable
failure, allowing a retry. File convenience calls close the file on failure.
Always check the individual API contract before reusing an input after failure.

Explicit-storage capacity limits do not automatically grow storage or grant more memory.
Managed `std_list` collections grow automatically; see [managed memory](managed-memory.md). Runtime
byte budgets additionally bound backing/bookkeeping allocations. Filesystem,
clock and entropy functions require capabilities supplied by the host; importing
a module grants no permissions. Synchronous provider operations are not timed
out by a VM instruction budget.

## Examples and focused references

- [Managed word counts](../examples/python-word-count/main.my) uses ordinary strings, dictionaries, and iteration without explicit storage.
- [Bounded word counts](../examples/standard-word-count/main.my) combines text splitting,
  byte-key hashing and JSON construction. Its exported `histogram` handles up to
  16 unique space-delimited words, each at most 256 bytes, with bounded output.
- [Buffered file example](../examples/standard-io/README.md) runs against an
  explicitly granted directory.
- [Directory example](../examples/standard-directory/README.md) inspects metadata and
  enumerates a granted directory without implicit authority.
- [Time/random example](../examples/standard-time-random/main.my) checks full-width
  boundaries and reproducible streams without ambient authority.
- [Text/data contracts](stdlib-text-data.md), [collection contracts](stdlib-collections.md),
  [I/O contracts](standard-io.md), and [time/random contracts](standard-time-random.md)
  specify errors, ownership and supported ranges.

Owned buffer elements may contain nested buffer owners, but cannot contain
must-handle results, external resource owners or recursive ownership. Read/resize
fill/slices cannot copy an owned element; use extraction to inspect it. Owned map
search may reorder entries and is linear. Existing hash table values remain
copyable. These limits keep implicit collection destruction free of provider
effects; see the owned section in the collection reference.

These are intentionally bounded foundations. Text offsets are byte offsets and
trimming is ASCII; there is no Unicode normalization. Hash byte keys hold at
most 256 bytes. Decimal float parsing has documented precision/range limits and
is not correctly rounded for arbitrary decimal input. Argument parsing receives
already-separated tokens and does not perform shell parsing. Wall-clock instants
are not monotonic timers, and the deterministic generator is not cryptographic.

See [application library parity](stdlib-application-parity.md) for ordering,
counting, character classes, pair iteration and graph contracts.


## Ordinary JSON schema and iteration

`std_json_view` is the checked layer over ordinary `std_json::Document`, distinct
from the `typed-json-v1` compiler invocation format. Existing `Node`, `Kind`,
`root`, `kind`, `integer`, `boolean`, `count`, `at`, `key` and text accessors remain
compatible. `field` returns `Option<Node>`; present null is a node with `Kind.null`,
not absence. Handles and cursors belong to the same unmodified parser-produced
document; they do not encode ownership or validate a fabricated tape. Do not
construct or mutate cursor positions. Fraction nodes expose their kind, but the
ordinary tape currently does not retain a recoverable fractional numeric value.

The following additions return `std_result::Result<value, std_result::Error>` and
compose with `try` inside an application schema function using that error type:

| Function | Successful value and contract |
| --- | --- |
| `required(doc, object, name)` | `Node`; missing is `absent`, present null is retained |
| `integer_or(doc, object, name, fallback)` | `i64`; fallback only for missing fields |
| `boolean_or(doc, object, name, fallback)` | `bool`; fallback only for missing fields |
| `integer_between(doc, node, lower, upper)` | `i64` within inclusive bounds |
| `count_between(doc, container, lower, upper)` | `i64` count within inclusive nonnegative bounds |
| `children(doc, container)` | `Cursor` over immediate array values or object members |
| `current(doc, cursor)` | Current value `Node`; exhausted cursor is `absent` |
| `member_key(doc, cursor)` | Current object key `Node`; array cursor is `wrong_type` |
| `advance(doc, cursor)` | Next `Cursor`; exhausted cursors remain exhausted |
| `only_fields(doc, object, text, allowed)` | `bool`; every decoded member name appears in the allowlist |

Defaults never conceal null or a wrong type. Typed access happens before numeric
range validation; reversed bounds, negative count bounds and out-of-range values
produce `bounds`. Invalid node indices produce `bounds`; wrong node kinds produce
`wrong_type`. Array/object cursors run in source order and skip entire nested
subtrees in constant work per advance, avoiding repeated indexed scans. Inspect
`cursor.done` before `current` or `member_key`.

`only_fields` accepts a byte slice and a slice of `Name {start:u64,end:u64}`
half-open ranges into those bytes. It checks every descriptor before inspecting
members, including on an empty object: reversed or out-of-buffer ranges produce
`bounds`. Names are compared as exact decoded UTF-8 bytes, with no delimiter
encoding: empty names, Unicode, pipes and embedded NUL are representable.
Duplicate descriptors are harmless. An empty allowlist accepts only an empty
object. This helper does not require all allowed fields to be present; combine
it with `required` for requiredness and kind/value predicates for field schemas.

For example, an application helper returning `Result<i64,Error>` can write:

```mylang
// doc: skip fragment: helper body without its enclosing function, document or module
let names = new [2]std_json_view::Name[
    new std_json_view::Name {start:0u64,end:2u64},
    new std_json_view::Name {start:2u64,end:5u64}
];
borrow names[0..2] as allowed {
    let known = try std_json_view::only_fields(doc, object, "idlag", allowed);
    // The application maps false to its own invalid-schema result.
}
let lag = try std_json_view::integer_between(doc,
    try std_json_view::required(doc, object, "lag"), 0, 1000000);
let mut cursor = try std_json_view::children(doc, array);
while !cursor.done {
    let child = try std_json_view::current(doc, cursor);
    // Validate this child within the application's complete schema phase.
    cursor = try std_json_view::advance(doc, cursor);
}
```

These helpers do not choose application error precedence. Complete the whole
schema phase before checking duplicate identifiers, references or graph rules.
Parsing strictness, input limits, transport errors and raw tape APIs are unchanged.
The integrated `json_schema.my` fixture checks nested traversal, exhaustion,
missing/null/default distinctions, strict kinds, bounds and arbitrary-name lists.
