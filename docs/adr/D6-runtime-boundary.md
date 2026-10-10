# D6: Freeze the compiler/runtime boundary

Status: accepted; restated for Core/LLVM and progressive components, October 2026.

## Rule

Self-hosted compiler logic crosses versioned value boundaries. For the first
component, Zig owns discovery and graph extraction, process control, artifact
verification and report formatting. Selka owns the informational test-index
algorithm. Its contract is `component-protocol-v1` with the `test-index-v1`
operation; each process owns its decoded values.

The current native pipeline is checked source to Core IR to LLVM text, compiled
by the pinned Zig toolchain's clang. Core's C runtime owns reference-counted
allocation, copy-on-write, traps, capabilities, startup and platform operations.
Those implementations do not move merely because a toolchain algorithm does.
The earlier QBE and `runtime-abi-v1` embedding assumptions are retired.

## Progressive ownership

Lexing, parsing, resolution, type checking and lowering can move behind qualified
boundaries in later waves. The initial pinned Zig compiler builds each native
Selka executable independently. Component edits do not rebuild that compiler.
A process invocation uses one bounded request file and one framed stdout reply;
stderr is diagnostic output. A persistent worker or in-process library needs
additional runtime support and its own lifecycle/ownership qualification.

## Compatibility consequence

Protocol, operation schema, seed identity and executable digest are independent
parts of the component manifest and build recipe. Compatible schemas do not
mean identical behavior. A component that later controls cache reuse must enter
every relevant early cache lookup's identity before production adoption.

No Zig slice, allocator, compiler tree pointer or Selka managed-object layout
crosses the boundary. Interface revisions require parity and failure-path
qualification. See [the source profile](../bootstrap-v1.md) and
[the protocol](../tooling/component-protocol.md).
