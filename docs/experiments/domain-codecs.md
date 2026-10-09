# Explicit domain codec contracts

A domain may declare one codec inside its body. The declaration associates an
ordinary wire type with two named public methods in that same domain:

```text
domain Positive: i64 {
    codec Wire {
        decode: from_wire,
        encode: to_wire
    }
    // Other methods, including private constructors, may appear before or after it.
}
```

The complete executable example is [examples/domain-codecs](../../examples/domain-codecs/main.selka).
Its Wire record contains an integer n. from_wire returns a typed Decoded result:
positive inputs produce Positive; zero and negative inputs produce an error code.
to_wire returns a Wire record from a Positive value. main explicitly handles the
result and prints 7 for the example input.

The compiler checks the complete program and transitive effects before resolving
codec method identities. It requires:

- Exactly one decode and one encode entry, with no unknown or repeated keys and no
  second codec declaration in the same domain. Entry order is immaterial.
- Public methods of the declaring domain, each taking exactly one value parameter
  and returning a value. Reference/slice call boundaries are rejected.
- An effect-free decoder from Wire to a typed result whose ok payload is exactly
  this nominal domain. Merely returning the domain directly is insufficient.
- An effect-free encoder from this domain to exactly Wire.
- Complete ordinary wire and error type graphs: scalars, records, arrays, tables,
  enums, unions, and results, with no domains, authorities, handles, or runtime
  owners hidden in unused variants or zero-length arrays.

The wire type need not equal the private backing type. It deliberately describes
ordinary external data; dependencies on other domains must be converted explicitly
by the methods into ordinary wire fields. This avoids implicit backing access and
recursive codec lookup inside a declared wire representation. Domain composition
in application values is supported by [executed JSON traversal](domain-json.md).

Method names resolve within the declaring domain rather than through ambient
function lookup. Module relocation retains their original spans and qualified
identities. Exported method signatures retain existing interface privacy checks,
so a public codec cannot expose a private wire or result type. Private raw methods
remain inaccessible to public invocation.

Public schemas retain kind=domain and opaque=true, without backing fields or
implicit construction rules. A declared domain gains a codec object with wire,
decode, encode, and error_type, using qualified type/method names. Referenced wire
and error definitions are included in the checked graph. Selecting another method
changes the public schema and thus existing schema-based artifact identities.
Domains without a codec retain their previous schema representation. Python data
bindings continue to report domains as unsupported: metadata is not permission to
fabricate an opaque value or substitute wire data for it.

Typed metadata carries the resolved method IDs and wire type into bytecode. An
embedding caller can invoke those checked methods through the typed invocation API.
The contract does not prove predicate strength, encoder/decoder inverses, canonical
wire choices, or successful termination. The author supplies validation behavior;
callers must inspect decoder errors and enforce execution/resource limits.

This milestone implements declaration checking, metadata, and public schemas.
[Executed JSON codecs and shared budgets](domain-json.md) are now implemented.
Source serialization operations and generated callable bindings remain pending. The existing
representation-only typed_json API continues returning NoImplicitCodec for domains,
including ones with declarations. Execution-aware decoding executes the declared decoder
and inspects its result; no backing-value shortcut is authorized by this metadata.

Acceptance covers single-file and module resolution, successful/error factory
execution selected from metadata, exact signatures, private/missing methods,
complete type graphs, duplicate/missing/unknown entries, effects, canonical
formatting with comments, schema identity changes and private-interface rejection,
and allocation failures through checking, schema generation, and invocation. The
module example also enters VM/native acceptance, including step/frame boundaries
and native -O0/-O2 with undefined-behavior sanitization.
