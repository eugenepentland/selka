# Typed JSON boundaries

The compiler derives a JSON representation for a checked project's exported
types without any codec being written by hand. This is the *compiler's* boundary:
`schema-project` renders the contract, and `mylang test --cases` uses the
representation to carry a test's arguments and its expected result. It is not the
guest-level `json` module, which is an ordinary library a program calls to parse
and render text at run time; see [the standard library](standard-library.md#json)
for that. The two never meet: this page is about the envelope a tool hands the
compiler, not about a value a program builds.

## Typed JSON boundaries

A signature is JSON-compatible when its complete type graph is: integers,
booleans, records, fixed arrays, enum-indexed tables, closed enums, tagged unions
and results. Export the types and the function, and the boundary exists — the
codec is derived from the checked declarations rather than declared. Every
document is the three-field `typed-json-v1` envelope, whose `type` names the
checked nominal type with its module qualification and must match the selected
decoder exactly. Integers travel as canonical decimal *strings*, so a 64-bit
value survives a JSON client whose native numbers cannot represent it.

```mylang
# doc: check

public enum Status:
    ready
    failed

public record Sample:
    sequence: u64
    status: Status

public func sequence_of(sample: Sample) -> u64 effects():
    return sample.sequence

public func test_sequence(sample: Sample) -> u64 effects():
    return sequence_of(sample)

func main() -> int:
    return 0
```

A `Sample` value for that project is written like this, and anything that accepts
a value of that type decodes it against the checked type graph:

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
| tuple | object with fields `$0`, `$1`, … |

The encoder writes envelope fields in version, type, value order, record fields in
declaration order and table keys in enum declaration order. Input ordering is
irrelevant. Keys are compared after their JSON escapes are decoded, so a plain
key and its escaped spelling are duplicates and reject at every nesting level,
unknown keys included. There is no unknown-field preservation and no
unknown-case fallback: an extra key at any level rejects, and a payloadless case
rejects even an explicit null `value`.

## Where the representation is used

`mylang schema-project` prints the language-contract graph — names, fields,
effects, modes — for every reachable exported declaration. A signature that is
not JSON-compatible still appears there; it simply has no derived codec. The
schema and the envelope describe different things: the schema is the contract,
the envelope is a wire representation. Neither is a native memory layout or a
foreign ABI.

`mylang test --cases` is what actually moves typed JSON in and out of a running
program. A case names its arguments by source parameter name and gives each one
the typed-JSON representation of that parameter's type; a test whose result is
not `bool` must declare an expected value in the same representation, which the
runner compares against what the native process returned. See
[guest tests](tooling/guest-tests.md#mylang-test).

```sh
mylang schema-project main.my                  # the language-contract graph
mylang test main.my --cases cases.json         # typed JSON arguments and expectations
```

Driving `main::test_sequence` from the project above takes a `Sample` in and a
`u64` out, both in the representation this page describes:

```console
$ cat cases.json
{
  "main::test_sequence": {
    "arguments": {"sample": {"sequence": "7", "status": "ready"}},
    "expected": "7"
  }
}
$ mylang test main.my --cases cases.json
passed main::test_sequence
1 passed, 0 cached, 0 failed, 0 skipped
```

Arguments are named by source parameter and supplied in declaration order; an
extra or missing name rejects. Note that an argument and an expectation are bare
values of their type, not three-field envelopes — the case already names the test
whose signature fixes both types.

## Limits

- A type graph that reaches a domain, capability, buffer, resource, pool, handle
  or move-only value rejects with `NoImplicitCodec`, including when it is nested
  in an unselected union case or a zero-length array. An implicit decoder must
  not be able to bypass a private domain factory, mint authority, or fabricate a
  live resource identity.
- Documents are bounded at 1 MiB in each direction, 65,536 materialized value
  nodes, 262,144 scanner tokens and 64 typed levels. These are work and size
  bounds, not a memory quota or a timeout.
- A document selects an exact qualified exported type name, not a local import
  alias; private and unknown names reject.
- There is no longer a command that decodes a standalone value *document*: no
  surface reads a `typed-json-v1` envelope from a file and materializes it. The
  one command that executes guest code from typed JSON, `mylang test --cases`,
  takes bare values rather than envelopes, because the selected signature
  already fixes every type.
- Explicit domain codecs, external key mappings and source-level codec operations
  remain unfinished.

## Related pages

- [The standard library](standard-library.md#json) — the separate guest-level `json` module
- [Typed JSON serialization and validation](experiments/typed-json.md) — the wire contract in full
- [Guest tests](tooling/guest-tests.md) — the runner that carries typed JSON arguments and expectations
