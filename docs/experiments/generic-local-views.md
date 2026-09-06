# Generic local arrays and buffer views

Generic bodies now borrow concrete numeric fixed arrays and owned buffers as
slices. They can narrow whole-array reference inputs and return those slices
under an explicit input lifetime. See [the runnable example](../../examples/generic-local-views.my),
which returns `22` through the VM.

The abstract checker resolves the element type using the same `typed.sliceElement`
helper as the ordinary checker. Symbolic parameters still need a declared
structural requirement before their shape can be inspected; `T:copy` does not
promise an array or buffer. Enum-indexed tables are not numeric slices.

## Ownership and access

Bounds are checked as integer expressions before the owner is inspected. If a
bound expression consumes a buffer, constructing the subsequent view rejects
with `E_OWNED_CONSUMED`. A live view keeps the original owner identity through
narrowing, reborrowing, and reference-returning calls. Shared views permit
compatible reads; exclusive views prevent direct owner access. Active views
prevent conflicting mutation, buffer growth, and ownership transfer. Exiting
the lexical scope restores access; nested loans suspend exclusive parents.

The view exposes copyable elements, without allowing a whole owned buffer or
result-bearing value to be borrowed as an ordinary value. Array mutation through
a view preserves previously copied array snapshots. A slice may be empty at its
owner's end; runtime bounds failures retain the borrow source span.

## Returned views

A function taking a concrete `&mut [3]i64` input can declare a `&mut []i64` result
`from` that input, borrow an input range, and return the slice. The result's type
must match the input array's element type and its permissions cannot exceed the
input's. The origin remains the declared input through helper calls and modules.
A view of a local array or buffer cannot escape by claiming an input lifetime.

[Generic fixed arrays](generic-arrays.md) now extend these rules to `[N]T`
inputs, local arrays and returned `&[]T` slices. An opaque type parameter still
needs a structural requirement before its shape can be inspected.
[Local arena/reset scopes](generic-regions.md) now have independent abstract
allocator-origin and escape checking.

## Acceptance

`GENERIC-LOCAL-VIEW-1` covers uncalled-template rejection for shapes, permissions,
consumed owners (including consumption inside a bound), conflicting reads,
assignments, growth and transfers, parent suspension, and local-reference escape.
VM tests cover array snapshots, buffer acquisition/mutation, empty slices,
narrowing, reference-returning helpers, restored owner access, source-located
bounds traps and host allocation failures through checking and execution.

An actual CLI test imports an array-reference helper, checks both general and
arena VM memory modes against an independent expected result, then replaces the
helper with an invalid local escape and verifies the module-located diagnostic.
Native execution is outside the active roadmap goal; this feature does not add
native acceptance or change bytecode/VM execution semantics.


Validation on 2026-09-06: 644 core and 61 CLI tests pass in both Debug and
ReleaseFast, with 100 focused generic tests and the interpreter/tooling drivers.
The initial full runs caught a module-call spelling error in the new CLI fixture;
complete CLI roots pass after that correction. Guardian and formatting pass with
baselines disabled. No native execution acceptance was run.
