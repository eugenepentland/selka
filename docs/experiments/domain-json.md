# Executed domain JSON codecs

check-value-project now executes declared domain codecs while traversing ordinary
records, arrays, tables, and variant payloads. The typed-json-v1 envelope still
names the nominal application type. A domain's JSON value has its declared wire
type's ordinary representation, not its private backing representation.

For the [Positive example](../../examples/domain-codecs/data.my):

```json
{"version":"typed-json-v1","type":"data::Positive","value":{"n":"7"}}
```

The CLI decodes Wire, calls Positive.from_wire, checks its typed result, and calls
Positive.to_wire to produce canonical output. Zero or negative n rejects with the
JSON pointer and typed error payload. Declared normalization is observable: a
factory that rounds valid input down to a multiple of ten produces 10 from 19.
This behavior comes from executing the declared methods, not a compiler-inferred
predicate or round-trip law. No domain backing value is fabricated by traversal.

Complete type preflight requires a declared codec for every domain dependency,
including inactive union arms and zero-length arrays. Wire representations must
remain ordinary data as required by declaration checking. Rechecking that condition
also rejects recursive host-supplied wire metadata before traversal. The source
program still undergoes complete checking; public root selection and method
visibility retain the existing module interface rules.

## Budgets and ownership

One operation shares these defaults across all domain calls and, for
[invoke-project](checked-calls.md), the requested public function:

| Limit | Default | CLI override |
| --- | --- | --- |
| Guest instructions | 1,000,000 | --max-codec-steps=N |
| Frames per invocation | 256 | --max-codec-frames=N |
| VM invocation attempts | 4,096 | --max-codec-calls=N |
| Requested live allocation bytes | 32 MiB | --max-codec-bytes=N |
| Traversed application/wire values across both directions | 131,072 | --max-codec-values=N |

The ordinary JSON limits also remain: 1 MiB input/output bytes, 65,536 traversed
values per direction, 262,144 lexical tokens per document, and wire depth 64
(maximum configurable depth 128 in the embedding API). A domain node and its wire
representation both count as traversal work, at the same JSON depth. Limits do not
restart at each domain or each collection element. CLI round trips share execution,
work, and live-memory accounting across decoding and encoding while retaining the
per-direction value limit. A standalone decode or encode is its own operation.

The live-memory limit includes parsing/materialization, graph checking, VM
validation/bookkeeping, copied invocation arguments, returned values/errors, JSON
serialization temporaries, and the returned output buffer. It counts requested
allocation lengths, not allocator metadata or resident process memory. It excludes
the caller's existing input bytes/values and checked compiler/source storage.
Frontend checking/lowering occurs before runtime accounting. Guest steps do not
measure frontend, parsing, bytecode validation, or serialization CPU time.

The allocator wrapper forwards allocation, resizing, remapping, and freeing to the
caller. Values, error payloads, and text returned from the operation can therefore
be released directly through that original allocator after the wrapper is gone.
Encoding uses a separate temporary JSON arena but executes each codec through the
shared reclaiming allocator, so completed invocation storage is not retained in the
JSON arena. Lower memory budgets can change arena growth decisions; an observed
peak from one successful run is not necessarily the minimum successful budget.

Budget exhaustion is CodecMemoryLimit, while a failure from the caller's allocator
remains OutOfMemory. No allocation failure is converted into a decoder rejection.
Optional statistics report executed guest instructions, attempted calls, traversal
work, and peak requested live bytes, including partial progress on failure.

## Embedding and diagnostics

codec_json.decode returns an owned typed value; encode returns owned canonical JSON.
canonicalProject selects an exported root from the envelope and performs both
directions. All require an initialized Failure and expose the options above.
Release returned storage with the caller allocator. Failure.deinit releases any
owned decoder error payload; call it before reusing a Failure after rejection.
Reusing an unreleased rejection returns UnreleasedCodecFailure and preserves that
payload instead of losing its ownership.
Nominal type IDs and source-trace metadata still require the compilation alive.

A DomainCodecRejected failure retains the decoder's typed error value, its domain
identity, and the JSON pointer of that domain occurrence. A DomainCodecTrap retains
the VM diagnostic and source call frames at the same pointer. Wire shape failures
point inside the wire representation. Pointers remain bounded, owned, and marked
when truncated. The CLI prints rejection payloads through the bounded ordinary JSON
codec; an oversized diagnostic payload is explicitly reported as unrenderable.
Diagnostic rendering happens after operation accounting. It does not erase the
primary failure, and allocation failures still propagate.

Encoding checks structural input validity through invocation copying. It does not
prove domain invariants for values fabricated by trusted host code. Untrusted wire
input must use decoding and its declared factory.

The old typed_json API remains representation-only and still rejects domains. The
new execution-aware API and CLI use checked bytecode; this is not a serialized
bytecode loader, foreign ABI, or permission for generated Python classes to wrap
opaque backing data. Source serialization operations, generated callable bindings,
richer declared-input integration, and other unfinished roadmap work remain open.

Acceptance includes nested arrays/records/unions/tables, typed rejection payloads,
wire and domain JSON pointers, exact shared step/call/work limits, frame traces,
maximum u64 values at wire depth one, memory limits and host allocation failures,
complete-graph rejection, canonicalization, CLI option validation, and unchanged
ordinary JSON boundary acceptance. Failure injection covers compilation, parse,
copying, invocation, encoding, and project round trips.
