# Typed JSON boundaries

The compiler can read and write JSON for a checked project's exported types
without any codec being written by hand. This is the *compiler's* boundary, used
by `check-value-project`, `invoke-project` and `schema-project` to move data in
and out of a project from outside it. It is not the guest-level `json` module,
which is an ordinary library a program calls to parse and render text at run
time; see [the standard library](standard-library.md#json) for that. The two
never meet: this page is about the envelope a tool hands the compiler, not about
a value a program builds.

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
module main
export Status
export Sample
export sequence_of

enum Status:
    ready,
    failed

class Sample:
    sequence: u64
    status: Status

def sequence_of(sample: Sample) -> u64:
    return sample.sequence

def main() -> int:
    return 0
```

A `Sample` value for that project is written like this, and
`mylang check-value-project main.my --value=sample.json` decodes it, validates it
against the checked type graph, and writes the canonical encoding back to
standard output:

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

The encoder writes envelope fields in version, type, value order, record fields in
declaration order and table keys in enum declaration order. Input ordering is
irrelevant. Keys are compared after their JSON escapes are decoded, so a plain
key and its escaped spelling are duplicates and reject at every nesting level,
unknown keys included. There is no unknown-field preservation and no
unknown-case fallback: an extra key at any level rejects, and a payloadless case
rejects even an explicit null `value`.

## Calling across the boundary

`mylang invoke-project` executes one exported function or public domain method
against a request document. The request pins the interface by digest: it carries
`schema_sha256`, the SHA-256 of the exact compact document `mylang schema-project`
prints, so a changed public contract rejects an old request with
`InvocationSchemaMismatch` while a body-only change runs the freshly checked
implementation. Argument keys are source parameter names and their values use
those parameters' typed-JSON representations; the result comes back as another
`typed-json-v1` envelope.

```sh
mylang schema-project main.my                  # the language-contract graph
mylang invoke-project main.my --request=call.json
```

Calling `main::sequence_of` with `{"sample": {"sequence": "7", "status": "ready"}}`
answers `{"version":"typed-json-v1","type":"u64","value":"7"}`. Note that
`schema-project` and `typed-json-v1` describe different things: the schema is the
language contract graph — names, fields, effects, modes — while the envelope is a
wire representation. Neither is a native memory layout or a foreign ABI.

## Limits

- A type graph that reaches a domain, capability, buffer, resource, pool, handle
  or move-only value rejects with `NoImplicitCodec`, including when it is nested
  in an unselected union case or a zero-length array. An implicit decoder must
  not be able to bypass a private domain factory, mint authority, or fabricate a
  live resource identity.
- Documents are bounded at 1 MiB in each direction, 65,536 materialized value
  nodes, 262,144 scanner tokens and 64 typed levels. These are work and size
  bounds, not a memory quota or a timeout.
- The CLI selects an exact qualified exported type name, not a local import
  alias; private and unknown names reject. Root structural arrays are reachable
  only through the embedding API.
- `check-value-project` does not execute guest code, invoke providers or write
  files. `invoke-project` rejects effectful call graphs and reference parameters
  or returns before it decodes anything.
- Explicit domain codecs, external key mappings and source-level codec operations
  remain unfinished.

## Related pages

- [The standard library](standard-library.md#json) — the separate guest-level `json` module
- [Typed JSON serialization and validation](experiments/typed-json.md) — the wire contract in full
- [Schema-pinned public JSON calls](experiments/checked-calls.md) — the request format for `invoke-project`
