# Text, formatting and common data utilities

These embedded modules work with both the VM and native C backend. Import them
without copying source files into your project. They use explicit byte slices,
allocators, capacities and typed `std_result::Error` values.

| Module | Operations |
| --- | --- |
| `std_strings` | `starts_with`, `ends_with`, ASCII `trim`, `split_next`, `replace_all`, `append_range`, `push`, `unsigned`, `signed` |
| `std_encoding` | `read_uint`, `write_uint`, `hex_encode`, `hex_decode`, `base64_encode`, `base64_decode` |
| `std_format` | `parse_float`, `fixed` |
| `std_args` | `classify`, `name_is`, `is_flag`, `integer_value` |
| `std_json_builder` | Object/array creation, typed field/element appends, nested objects/arrays, finalization, integer-array convenience |

`std_bytes::create`, `append`, `escaped`, and `decimal` remain compatible and form
the shared bounded builder. A builder operation consumes its input. Success
returns the updated owner; failure releases the intermediate owner and returns a
typed error. Capacity does not grow automatically. Each output and intermediate
allocation has an explicit bound; the output bound is not a combined runtime
memory quota. Use the runtime allocator budget for a total requested-byte limit.

## Text and bases

Offsets are byte offsets. `trim` recognizes ASCII space and bytes 9 through 13;
it does not perform Unicode whitespace classification or normalization.
`starts_with` and `ends_with` accept an empty pattern. `replace_all` makes
nonoverlapping left-to-right replacements and rejects an empty needle.

`Range { start, end }` is a half-open range of indices, independent of ownership.
To split, call `split_next(text, delimiter_byte, 0u64)`, consume its `part`, and
repeat using `next` until `done` is true. Empty input produces one empty field;
consecutive and trailing delimiters preserve empty fields. Out-of-range starting
indices return `bounds`. Retaining a range does not keep its source bytes alive;
borrow the source again before accessing the range.

`unsigned` and `signed` accept bases 2 through 36, emit lowercase digits, and
cover the full u64/i64 range, including the signed minimum. No prefix is added.
`append_range` validates both endpoints before reading. All builders report
capacity exhaustion through the shared typed allocation error.

## Endian, hex and base64

`read_uint(bytes, offset, width, little)` and
`write_uint(bytes, offset, width, little, value)` support 1 through 8 bytes.
`little=true` selects little-endian. Invalid widths/bounds return `malformed`;
a value that does not fit the requested width returns `overflow`. Failed writes
leave the destination unchanged. Use integer casts or explicit sign extension
when interpreting the resulting unsigned bit pattern.

Hex encoding is lowercase; decoding accepts either case, requires even length,
and rejects whitespace. Base64 uses the standard `+/` alphabet with mandatory
canonical `=` padding. Decoding rejects whitespace, misplaced padding, short
quanta and nonzero unused padding bits. Empty input is valid for both codecs.

## Bounded floating-point conversion

`parse_float` accepts `-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?`, consuming the
entire input. It rejects whitespace, leading `+`, NaN/infinity, missing digits,
and trailing text. The mantissa has at most 19 significant digits; both the
explicit exponent magnitude and the exponent after fractional-digit adjustment
must be at most 308. Exceeding these limits or producing infinity returns
`overflow`, including unsupported very small decimal inputs. Negative zero is
preserved. Leading zeros are allowed.

This implementation converts the integer mantissa and scales it using binary64
operations. It is **not a correctly rounded arbitrary-decimal parser**: rounding
can accumulate during scaling. Use it for explicitly bounded approximate numeric
input, not exact decimal financial arithmetic or bit-for-bit interchange.

`fixed(heap, value, places, limit)` writes 0 through 9 fractional digits and
truncates the represented binary64 magnitude toward zero using exact integer
arithmetic on its fractional significand. It rejects nonfinite
values and magnitudes whose integral part does not fit u64. It preserves the sign
of zero. This is not shortest-roundtrip formatting; values such as binary64 0.1
may expose approximation when many digits are requested. `std_math::bits` remains
the exact representation interface.

## Arguments and JSON

`std_args` parses one already-separated argument; it does not access ambient
process arguments or implement shell quoting. `classify(text, options)` recognizes
`--name`, `--name=value`, and the `--` terminator. After a terminator, pass
`options=false` for subsequent tokens. Short options are positional. The caller
chooses how to consume separate option values, reject unknown/empty names, handle
duplicates and enforce required arguments. The returned ranges contain no views.
`integer_value` returns `absent` when no `=` value exists and otherwise invokes
the checked decimal integer parser.

JSON builders emit valid escaping and support strings, i64 integers, booleans,
null, objects and arrays. Start with `object(heap, limit)` or `array(heap, limit)`,
thread the returned owner through operations, then call `finish` or
`finish_array`. `object_field`, `array_field`, `array_object`, and `array_array`
consume separately bounded nested builders. `integers` and `integers_field`
accept a borrowed i64 slice. Object keys retain insertion order and duplicate
keys are permitted. There is no unchecked raw JSON insertion or float insertion.
Builder record fields are language-visible: constructing or modifying their raw
byte field directly is outside the valid-builder contract.

## Executable evidence

The guest fixtures [text_data.my](../src/stdlib/fixtures/text_data.my) and
[text_data_errors.my](../src/stdlib/fixtures/text_data_errors.my) are examples
and independent assertions. [Float edge cases](../src/stdlib/fixtures/text_data_float_edges.my)
add 30 exact expectations calculated independently with Python `Fraction`,
covering signed zero, subnormals, fractional limb carries and large integers.
The test harness provides each fixture as `main.my`.
They cover integer extrema, malformed codecs, atomic failed writes, float
consumption/range/negative zero, argument ranges, escaping and nested JSON.

Run `zig test src/root_test.zig --test-filter 'text data'` with the pinned
compiler to include runtime allocation-failure cleanup checks.
`python3 tests/native_stdlib_text.py --compiler /absolute/path/to/mylang --zig
/absolute/path/to/zig` executes all three fixtures on the VM and native builds at
O0/O2 with undefined-behavior sanitization. This native test also belongs to
`zig build test-native`.

Byte-oriented preparation helpers:

- `std_strings::pad_right(heap, text, width, fill, limit) -> std_bytes::Built`
  pads to a minimum byte width without truncation. Width and limit are `u64`,
  fill is `u8`; this does not measure Unicode display columns.
- `std_strings::join(heap, text, parts: &[]Range, separator, limit) -> Built`
  joins half-open ranges into shared bytes, preserving empty parts. Zero parts
  produces empty bytes. Invalid ranges and output limits yield `bounds` before
  allocation; allocation failures remain typed and release partial output.
- `std_path::absolute_valid(path)` accepts `/` or `/` followed by an existing
  valid relative path. `absolute_prefix(path,prefix)` requires a complete
  component boundary. `absolute_join(heap,base,suffix,limit)` accepts an absolute
  base and empty/relative suffix, inserts one slash, and never treats an absolute
  suffix as replacement. Malformed paths yield `malformed`; output beyond the
  caller limit or 4095 bytes yields `bounds`. Original relative APIs are unchanged.
- `std_json_view::text(heap,doc,node,limit) -> std_bytes::Built` allocates exactly
  the decoded UTF-8 byte length, preserving Unicode and embedded NUL. Limit is
  `u64`. Missing sentinel node zero yields `absent`, nonstrings `wrong_type`,
  other invalid nodes and too-small limits `bounds`; allocator failures remain
  typed. Documents retain the existing unmodified-parser-output precondition.
