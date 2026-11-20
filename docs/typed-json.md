# Typed JSON boundaries

The compiler derives a JSON representation for a checked project's exported types, with no codec written by hand.
`schema-project` renders the contract, and `selka test --cases` uses the representation to carry a test's arguments and
expected result. This is not the guest-level `json` module, an ordinary library a program calls at run time (see
[the standard library](standard-library.md#json)). A program that wants its own records as JSON calls `json.encode` and
`json.decode`, which derive a plain form ([the standard library](standard-library.md#deriving-json-for-your-own-types)).

## Typed JSON boundaries

A signature is JSON-compatible when its complete type graph is: integers, booleans, records, fixed arrays, enum-indexed
tables, closed enums, tagged unions and results. Export the types and the function, and the boundary exists. Every
document is the three-field `typed-json-v1` envelope, whose `type` names the checked nominal type with its module
qualification and must match the selected decoder exactly. Integers travel as canonical decimal strings, so a 64-bit
value survives a JSON client whose native numbers cannot hold it.

```selka
# doc: check

public enum Status:
    ready
    failed

public record Sample:
    sequence: u64
    status: Status

public func sequence_of(sample: Sample) -> u64:
    return sample.sequence

public func test_sequence(sample: Sample) -> u64:
    return sequence_of(sample)

func main() -> int:
    return 0
```

A `Sample` value for that project:

```json
{
  "version": "typed-json-v1",
  "type": "main::Sample",
  "value": {"sequence": "18446744073709551615", "status": "ready"}
}
```

## The value representation

| Language type | JSON |
| --- | --- |
| Integer | canonical decimal string: no suffix, plus sign, whitespace, separators, leading zeroes, exponent or negative zero, and it must fit the declared width and sign |
| Boolean | JSON boolean |
| Record | object with every declared field exactly once and no extra fields |
| Fixed array | array of exactly the declared length |
| Enum-indexed table | object with every enum case name exactly once |
| Closed enum | the case-name string; ordinals and unknown names reject |
| Tagged union or result | object with `case`, plus `value` only for a payload-bearing case |
| `float` | string: the shortest decimal that reads back to the same value, always with a `.` (`"-0.0"`, `"2.5"`, `"5.0e-324"`), or `"inf"`, `"-inf"`, `"nan"` |
| `str` | JSON string |
| `bytes`, `list[T]` | array of the elements (an octet is an integer string) |
| `set[T]` | array of the elements in iteration order; a repeated element rejects |
| `dict[K, V]` | array of `[key, value]` pairs in iteration order, so a key may be any hashable value; a repeated key rejects |

The encoder writes envelope fields in version, type, value order, record fields in declaration order and table keys in
enum declaration order. Input order is irrelevant. Keys are compared after their JSON escapes are decoded, so a plain
key and its escaped spelling are duplicates and reject at every nesting level. There is no unknown-field preservation
and no unknown-case fallback: an extra key at any level rejects, and a payloadless case rejects even an explicit null
`value`.

## Where the representation is used

`selka schema-project` prints the language-contract graph (names, fields, capabilities, modes) for every reachable
exported declaration. A signature that is not JSON-compatible still appears there; it just has no derived codec. The
schema is the contract and the envelope is a wire representation; neither is a memory layout or a foreign ABI.

`selka test --cases` is what moves typed JSON in and out of a running program. A case names its arguments by source
parameter name, each in the typed-JSON representation of its type. A test whose result is not `bool` declares an expected
value in the same representation. See [guest tests](tooling/guest-tests.md#selka-test).

```sh
selka schema-project main.selka                  # the language-contract graph
selka test main.selka --cases cases.json         # typed JSON arguments and expectations
```

Driving `main::test_sequence` from the project above takes a `Sample` in and a `u64` out:

```console
$ cat cases.json
{
  "main::test_sequence": {
    "arguments": {"sample": {"sequence": "7", "status": "ready"}},
    "expected": "7"
  }
}
$ selka test main.selka --cases cases.json
passed main::test_sequence
1 passed, 0 cached, 0 failed, 0 skipped
```

Arguments are supplied in declaration order; an extra or missing name rejects. An argument and an expectation are bare
values of their type, not envelopes: the case already names the test whose signature fixes both types.

## Limits

- A type graph that reaches a capability, buffer, resource, pool, handle or move-only value rejects with
  `NoImplicitCodec`, even nested in an unselected union case or a zero-length array. An implicit decoder never mints
  authority or a live resource identity.
- Documents are bounded at 1 MiB in each direction, 65,536 materialized value nodes, 262,144 scanner tokens and 64 typed
  levels. These are work and size bounds, not a memory quota or a timeout.
- A document selects an exact qualified exported type name, not a local import alias; private and unknown names reject.
- No command decodes a standalone value document. `selka test --cases` takes bare values, not envelopes.
- A record invariant is checked before a decoded value reaches guest code: `{"value":"-5"}` fails a nonnegative
  invariant with `R_INVARIANT`.
