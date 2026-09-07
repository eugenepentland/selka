# Standard library

Standard modules are embedded in the compiler. Import their names directly;
projects do not need to copy these files. Allocation and external authority stay
explicit. The installed `--features` report identifies the executable actually
in use; this document describes the source tree.

| Area | Modules | Available operations |
| --- | --- | --- |
| Bytes and text | `std_bytes`, `std_text`, `std_strings` | Byte comparison/search, UTF-8 validation, decimal integers, escaping, prefix/suffix, ASCII trim, byte-delimited splitting as index ranges, replacement, bounded builders and base 2–36 integer formatting |
| Formatting | `std_math`, `std_format` | Nominal binary64 arithmetic, bounded decimal parsing and fixed-point formatting |
| Collections | `std_collections`, `std_map`, `std_set`, `std_borrowed_set`, `std_queue` | Bounded vectors, linear maps/sets, queues, borrowed lookup/mutation, append-many, clear, stable filtering/deduplication, sorting/search |
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

Capacity limits do not automatically grow storage or grant more memory. Runtime
byte budgets additionally bound backing/bookkeeping allocations. Filesystem,
clock and entropy functions require capabilities supplied by the host; importing
a module grants no permissions. Synchronous provider operations are not timed
out by a VM instruction budget.

## Examples and focused references

- [Word counts](../examples/standard-word-count/main.my) combines text splitting,
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
