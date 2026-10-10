# Bootstrap source profiles

The original `bootstrap-v1` proposal described a QBE compiler, function-scoped
locals and `Cell[T]`. Those assumptions are historical. Main now uses block
scope, explicit bindings and the Core/LLVM reference-counted runtime. This page
states the source contract for the first independently compiled toolchain
component. It does not declare a fully self-hosted compiler or a compatibility
release.

## Qualified component profile: component-v1

The seed is the immutable source revision and Zig toolchain in
`selfhost/component-seed.json`. Its locally built executable is qualified by a
receipt containing the source/runtime/library identity, toolchain identity and
executable digest. The builder verifies that receipt before use. The historical
`selfhost/stage0-pin.json` remains the seed for its existing fixtures.

The independently seeded components use these capabilities of the seed:

- `func`, `public`, imports, records, annotated parameters and return values;
- block-scoped `const` and `mut` bindings, explicit `mut` arguments and indexed
  list updates;
- `int`, `bool`, `str`, `bytes`, `byte_buffer`, records and nested `T[]` lists;
- conditionals, loops, ranges, indexing, slicing, comparisons and integer
  arithmetic, including shifts/bitwise operations for the bounded wire codec;
- list append/pop, length, byte-buffer construction and byte output;
- checked failures using `fails`, `fail` and `try`;
- a native entrypoint receiving arguments, `Filesystem` and output/error
  streams. Filesystem authority is confined to the entry adapter.

The graph and codec modules are ordinary Selka libraries. Their pure tests run
through `mylang test`; native process tests cover filesystem and stream behavior.
No raw pointer, foreign function, callback, managed-object layout, ambient host
provider or shared-library ABI is part of this profile.

## Qualification and adoption

[D7](adr/D7-feature-delay.md) distinguishes the full compiler's release delay
from independently seeded components. A component may use this frozen profile
because its seed precedes it and can be rebuilt without it. Qualification
requires:

1. An empty-cache seed/component build and immutable artifact verification.
2. Pure debug and release tests, with fact verification and leak checks.
3. Cross-language protocol fixtures, malformed-input checks and exact graph
   parity against the Zig reference and an independent oracle.
4. Normal CLI use and a component-only edit/rebuild with the host executable's
   digest unchanged.

The component cannot use a newly implemented language feature merely because
another compiler on `PATH` accepts it. Change the pinned profile and qualify a
new seed before adopting such a feature. Future ports must enumerate their
additional requirements rather than silently extending `component-v1`.

The declaration index uses the same frozen source profile. Its new protocol/schema
1 contract is separate from lexer/parser protocol 1/schema 2. It receives parsed
declaration facts, direct dependency symbols and explicit source/module context;
it returns symbol tables or located declaration diagnostics. Neither seed pin is
extended. See [declaration qualification](tooling/declaration-component-qualification.md).

## Runtime boundary

[D6](adr/D6-runtime-boundary.md) defines the current boundary. The Zig host
extracts graph facts and owns process control, artifact verification and command
formatting. Selka inverts the graph and returns values using
[component-protocol-v1](tooling/component-protocol.md). Core lowering, LLVM
emission, runtime allocation, traps and platform I/O remain native machinery.

The first component provides informational reachability. Its graph omits
unresolved function-value calls; it is not the Core runner's execution-dependency
graph and cannot decide to skip a test. Core test-cache traversal and persistent
queries require their own qualification.

See [building components](tooling/selfhost-components.md) for the supported
build, installation, recovery and verification commands.
