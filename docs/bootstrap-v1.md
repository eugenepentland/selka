# Bootstrap source profiles

The original `bootstrap-v1` proposal described a QBE compiler, function-scoped
locals and `Cell[T]`. Those assumptions are historical. Main now uses block
scope, explicit bindings and the Core/LLVM runtime with checked ownership. This page
states the source contract for the first independently compiled toolchain
component. It does not declare a fully self-hosted compiler or a compatibility
release.

## Qualified component profile: component-v1

Since 19 November 2026 (GH-D5) the compiler that `zig build` builds compiles the
components; there is no seed compiler pinned to an older revision. The profile
below is the subset of the language the components are written in, kept so that
they stay small and portable; it is a convention the reviewer checks, not a
compiler pin.

The test-index component uses only these capabilities of the language:

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
through `selka test`; native process tests cover filesystem and stream behavior.
No raw pointer, foreign function, callback, managed-object layout, ambient host
provider or shared-library ABI is part of this profile.

## Qualification and adoption

[D7](adr/D7-feature-delay.md) described independently seeded components; with
the seed gone (GH-D5) a component is built by the compiler of the same commit, so
a language change and a component that uses it land together and are tested
together. Qualification requires:

1. An empty-cache component build and artifact verification.
2. Pure debug and release tests, with fact verification and leak checks.
3. Cross-language protocol fixtures, malformed-input checks and exact graph
   parity against the Zig reference and an independent oracle.
4. Normal CLI use, and a compiler with no component folder falling back to the
   built-in implementations with one line of notice.

A component should still stay within `component-v1`; future ports must
enumerate their additional requirements rather than silently extending it.

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
