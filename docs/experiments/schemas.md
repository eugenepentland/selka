# Checked public schema derivation

`schema-project` derives a versioned JSON type graph from the checked public
contracts of all modules reachable from an entry file:

```sh
zig build
zig-out/bin/mylang schema-project examples/schema/main.my
zig-out/bin/mylang schema-project examples/modules/domain_main.my
```

The command checks the entire project, including private and uncalled bodies,
before emitting anything. Source errors exit 1 with diagnostics and empty stdout;
usage/host errors exit 2. Successful JSON goes to stdout with status 0. The command
does not execute the VM, write files, or require native backend support. Existing
module/source budgets apply. Evaluation flags and input bindings are not accepted.

The embedding API is `schema.render(allocator, *project_compile.Compilation)`.
It checks the compilation as needed and returns owned bytes. Scratch storage is
released on success and failure. The caller must retain the compilation's index
and project throughout the call, as with the other project APIs.

## Document contract

The format is `language-schema-v1`, with scope `reachable-module-exports` and
representation `language-contracts-no-wire-format-or-abi`. It is a language schema,
not a JSON Schema standard document. It describes:

- `entry`: the logical entry module name.
- `exports`: sorted, fully qualified exported nominal type names.
- `functions`: sorted exported function contracts, including public domain methods.
  Parameters retain names, referenced types, and value/shared/exclusive reference
  or slice modes. Results reference a type. Reference returns additionally record
  their zero-based source parameter index, mutability, and slice status. Effects
  list the inferred transitive effects in the language effect declaration order.
- `types`: the transitive public type graph, sorted by name. References use names,
  never compiler-local numeric type IDs. Structural array/table names incorporate
  the qualified identities of their element and key types.

Integer definitions include width, signedness, and decimal-string bounds so the
full 64-bit range survives JSON consumers with limited number precision. Record
fields and variant cases retain declaration order. Arrays record length/element;
tables additionally reference their enum key. Results retain their handling
obligation; all definitions expose move-only and required-handling properties.
Optional metadata that does not apply is absent, rather than null.

Domain definitions are opaque: no backing type or private construction function
is emitted merely because a domain is exported. Public factory/accessor signatures
are included normally. Their existence does not identify a serialization codec or
prove that arbitrary external values satisfy the domain's invariants.

Capabilities, buffers, resources, pools, and handles are explicitly opaque for
reconstruction. Buffer elements, resource authority kinds, and pool element/handle
relationships remain visible. Pool/handle graphs may contain cycles; derivation
uses an iterative worklist and emits each reachable type once. Consumers must
resolve graph references without assuming a tree or declaration-before-use order.

Private declarations and implementation-only types are excluded. Public signatures
already undergo the compiler's export/privacy checks. Exported types are roots even
when no function uses them. Exported function parameter/results also contribute
roots, including structural arrays and built-in capabilities. An empty public
interface produces empty exports/functions/types even if main uses scalar values.

## Consistency and limits

Names and field/case keys come directly from checked declarations; the language
rejects duplicate declarations/fields/variants before schema emission. There is
currently no separate external-name mapping that could introduce alias collisions.
Public type and function identities retain their module qualification. Import
aliases, discovery order, comments, and private implementation changes do not affect
the document when the public contract stays the same. Field/variant order, public
shape, parameter names, inferred effects, and nominal identities are contract data
and can change the output. This is not a byte-level source receipt or compiler
identity fingerprint.

Derivation does not establish a wire format, target memory layout, foreign ABI,
codec, or external-data validator. Explicit effect bounds are not emitted separately
from inferred effects. Serialization/deserialization, domain codec declarations,
external key mappings, generated language bindings, and generation budget/receipt
integration remain roadmap work. Consumers must not treat an opaque type as safely
constructible from its descriptive metadata.

## Acceptance

The actual CLI driver `tests/schemas.py` checks records, arrays, tables, enums,
unions/results, integer bounds, qualified duplicate short names, domain privacy,
cyclic pool/handle graphs, buffer/resource/capability opacity, reference/slice return
contracts, inferred effects, deterministic output, public-shape changes, empty
interfaces, invalid private bodies, duplicate fields, private signature leaks, and
irrelevant flags. A project unit scenario exercises repeated rendering and all
allocation failures with leak checking. The driver runs in `zig build test` in both
host optimization modes alongside the existing compiler/native acceptance suites.
