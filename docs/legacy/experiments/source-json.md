# Typed JSON from language source

> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Source programs can encode checked values into bytes and decode those bytes
without a host wrapper or a Zig rebuild. These operations use the existing
`typed-json-v1` envelope and checked type identities used by the CLI boundary.

The signatures below are written in the explicit-storage spelling that was
removed on 2026-09-13; the operations survive, but their managed `bytes`
spelling is not settled yet, so the examples on this page are not executed.

```my
# doc: skip removed feature
buffer Bytes: u8;
result Encoded { ok: Bytes, err: i64 }
struct Item { count: u64, ready: bool }
result Decoded { ok: Item, err: i64 }

fn roundtrip(heap: allocator, item: Item) -> Decoded {
    let bytes = try json_encode::<Encoded>(heap, item, 4096);
    return json_decode::<Decoded>(heap, bytes, 4096);
}
```

Both calls require one explicit result type, allocator authority, a value, and a
maximum wire-byte count. Encoding returns a result whose success payload is an
owned `u8` buffer. Decoding consumes an owned `u8` buffer and returns the result's
checked success type. Both error payloads must be `i64`. A consumed byte buffer
cannot be used again, and active borrows prevent its transfer. Encoding observes
the normal value-transfer rules, including mandatory handling of result values.
The operation names are reserved for compiler use.

The encoded envelope contains `version`, `type`, and `value`. Types come from the
checked program, including qualified module identities. Integer values preserve
all supported integer widths; numeric JSON coercion does not relax their range
checks. Records, finite arrays and tagged variants use the existing typed JSON
representation. Every encountered domain must declare a codec. The decoder runs
that domain's checked public factory, including its validation, and encoding runs
its declared public encoder. Neither direction exposes or implicitly wraps a
private domain representation. Native resources, capabilities and owned buffers
are not serializable data values.

| Error code | Meaning |
| --- | --- |
| `1` | Malformed wire data, wrong version/type/shape, invalid value or integer range. |
| `2` | Byte, traversal, nesting, codec-call, operation-memory or output-buffer capacity limit. |
| `3` | A domain decoder rejected the wire value, or a domain codec trapped. |
| `4` | Invalid requested byte budget; permitted range is 1 through 1,048,576. |

Malformed inputs include duplicate fields, unknown fields, trailing content and
wrong nominal type identities. A failed decode publishes no partial value. A
failed encode publishes no partial buffer. Host allocation exhaustion remains a
VM allocation failure; it is not misreported as malformed input. The compact
source error code does not currently carry the detailed JSON pointer or domain
rejection payload available to host-side codec callers.

Both operations have the allocation effect and honor the supplied allocator's
region and capacity restrictions. A call is also bounded by 32 MiB of temporary
codec memory, 65,536 traversed values, 262,144 tokens, depth 64 and 256 domain codec
calls. VM instruction accounting includes bytes, traversed values and executed
domain instructions. Domain calls share the parent's remaining instruction and
active-frame budgets; exhaustion produces the normal VM `R_STEP_LIMIT` or
`R_FRAME_LIMIT` trap. Domain codecs must remain transitively effect-free, so they
cannot acquire authority or recursively perform allocating JSON operations.

## Generic codec requirements

```my
// doc: skip fragment: continues the Encoded declarations of the block above
fn encode<T: codec>(heap: allocator, value: T) -> Encoded {
    return json_encode::<Encoded>(heap, value, 4096);
}
```

The `codec` requirement promises serialization eligibility for each actual type,
including its nested data and explicit domain codecs. An unused generic body is
checked against this promise; `T: copy` alone does not promise serialization.
The requirement does not grant equality, arithmetic, field access, private
unwrapping or access to a domain's associated wire type. It also does not imply
`copy`, because result types can carry mandatory handling obligations. Add
`copy` explicitly when the generic algorithm requires it. Forwarded type
parameters must preserve the declared requirements.

This is an interpreter feature. The deferred C backend reports unsupported
source JSON operations explicitly. It does not silently generate different wire
or ownership semantics.

Validation lives in `src/source_json_test.zig`: full-width round trips,
allocation-failure cleanup, malformed inputs, domain rejection, generic body
contracts, ownership and effect failures, instruction/frame limits, and malformed
bytecode rejection.

Ordinary JSON input now has a separate
[json_parse document API](plain-json-ergonomics.md). It does not change the
typed-json-v1 encoding/decoding operations described above.
