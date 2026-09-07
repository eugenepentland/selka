# Finite nominal template layouts

Nominal declarations now pass a finite storage-dependency check before the
concrete-specialization stage. This includes unused templates
and private types in imported modules. [Concrete instances](nominal-instances.md)
now use this graph to materialize executable runtime schemas.

The implementation follows [declaration checking](nominal-template-checks.md).
It retains scoped symbolic parameters instead of choosing a representative scalar
and rejects cycles with `E_RECURSIVE_RECORD`. Argument-growing type families stop
at explicit compiler resource limits with `E_GENERIC_LIMIT`.

## Identity and storage dependencies

`src/nominal_layouts.zig` interns identities by declaration and ordered argument
identities. Builtin types, parameters scoped to their declaring type, nominal
applications, numeric arrays and enum-keyed arrays remain distinct. Repeated
applications reuse one identity; equal fields do not merge different nominal
declarations. Array identities include the length, element and optional enum key.

Interning an argument does not automatically expand its storage. Expansion follows
record fields, variant payloads, array elements and buffer/pool element types.
A pool handle has no edge back to its pool. This preserves the existing explicit
handle model for recursive application data. Zero-length arrays retain the
existing rule that their element type must also have a finite definition.

These definitions have finite storage dependencies:

```text
struct Box<T:copy> { value: T }
struct Empty<T:copy> {}
struct Finite<T:copy> {
    nested: Box<Box<T>>,
    phantom: Empty<Finite<[1]T>>
}
```

The nested boxes are distinct applications whose stored payloads eventually
reach `T`. `Empty` stores no parameter value, so its argument does not introduce
a recursive storage edge. A declaration-only cycle detector would reject valid
nesting; eagerly expanding every phantom argument would create an unnecessary
infinite family. The graph does neither.

These definitions reject:

```text
struct Loop<T:copy> { next: Loop<T> }
struct Swap<A:copy,B:copy> { next: Swap<B,A> }
struct Grow<T:copy> { next: Grow<[1]T> }
```

`Loop` and `Swap` close storage cycles. `Grow` keeps generating distinct stored
applications and reaches the expansion limit. Wrapping a recursive type in a
record or union does not hide its storage dependency. Result payloads are also
followed, while their handling obligations remain governed by declaration and
ordinary semantic checking.

## Bounds, diagnostics and ownership

Expansion uses a worklist and cycle checking uses an explicit DFS stack. Long
declaration chains and substituted array arguments do not consume the host call
stack. Recursive traversal of an individual source type expression remains
bounded at 256 levels.

Each graph permits at most 4,096 argument-bearing nominal identities, including
the symbolic roots used to validate template declarations, and 4,096 array
identities. These counts include interned argument identities even when their
storage is not needed. Identity requests and expression visits share a 100,000
operation budget. Reusing an identity does not consume another identity slot.
Compiler limits reject explicitly; they do not establish a semantic cycle in an
otherwise finite program.

A cycle diagnostic points to the closing field or array dependency and includes
a related location for the layout already on the DFS stack. Mapped module spans
retain their original files. Requirement errors may precede layout errors when
a declaration violates both rules.

The graph owns its key copies, edges, hash table and worklist and releases them
through `deinit`, including partial construction failures. It borrows the template
index and diagnostic sink. Tests exercise both an arena-backed compilation and
graph storage allocated separately, with allocation-failure sweeps on successful
construction and rejected cycles.

## Remaining work

Graph IDs are semantic identities, not executable `typed.Type` IDs. The concrete
catalog now materializes only required, complete concrete layouts, keeping
unexpanded phantom arguments out of the runtime record table. Its shared runtime
layout validator derives ownership and result obligations. This graph does not
calculate backend offsets or define generic function-body operations.

Eight core graph tests cover identity reuse and separation, finite nested/phantom
forms, direct/indirect/permuted/array/result/buffer/pool cycles, instance/array/work
limits, 1,200-type finite chains, allocation failures and imported diagnostic
locations. The CLI distinguishes recursive-layout errors from accepted finite
types. Concrete execution has additional coverage in the specialization contract.

[Symbolic body operations](nominal-bodies.md) now use these semantic identities
with late concrete catalog specialization. Shared `Slot<T>` types in the board
trial and public generic tooling remain pending. Native guest compilation remains outside the
active goal.
