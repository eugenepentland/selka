# Symbolic nominal function bodies

Generic functions can now use parameterized records, unions, results and enums
in their signatures and bodies. The compiler checks each generic declaration
before its calls, retaining scoped parameters and nominal identity. It does not
choose a representative scalar to decide whether a body is valid.

```text
struct Box<T:copy> { value:T }
fn pack<T:copy>(x:T)->Box<T> { return new Box<T>{value:x}; }
fn extract<T:copy>(box:Box<T>)->T { return box.value; }
```

The executable example `examples/nominal-bodies.my` additionally forwards a
payload through a generic union and returns `7` on the VM.

## Abstract types and operations

A symbolic application contains its declaration identity and ordered arguments.
Arrays preserve their length, element expression and optional concrete enum key.
Substitution uses the callee's parameter list and caller's argument values;
separate parameters remain distinct even with identical requirements. Mixed
symbolic/concrete comparisons use semantic identities, including phantom arguments.
Records and unions do not gain equality from their fields; closed enums retain it.

Member lookup checks the declared shape. Construction requires complete matching
fields; updates preserve type and reject dropped result obligations. Variant
construction and matching check payload presence, case identity, duplicate arms
and exhaustiveness. `try` checks named result success/error types, propagation
obligations and error remapping even when case order differs between declarations.

Stored-member traversal derives move-only, result-handling, cleanup-effect and
region contracts using an explicit stack and cached nominal shapes. It follows
fields and payloads rather than type arguments. Empty phantom values and
zero-length arrays acquire no owner, result or lifetime obligation from an absent
stored value. Actual parameter requirements determine whether stored parameters
may carry allocator origins.

Partial field moves preserve the remaining obligations through existing flow
snapshots. Borrowed mutation, returned-input reference contracts, arena escapes
and cleanup effect bounds use those same symbolic contracts. The shape context
borrows the function's arena; the function checker owns and releases that arena.
Shape resolution shares the generic body's 100,000-operation budget, and recursive
source-expression substitution retains its 256-level bound.

Unconstrained `T` still has no known fields or cases. Those operations report
`E_GENERIC_BODY_UNSUPPORTED` until structural constraints are defined. Nominal
parameters retain their existing declared requirements, all of which imply copy;
this work does not admit arbitrary owned type arguments under `copy`.

## Late VM specialization

The compilation retains the nominal metadata and layout graph until semantic
checking and function specialization finish. Concrete applications discovered in
function signatures, bodies and calls append complete runtime schemas without
changing existing type IDs. Numeric arrays already created by another generic
specialization reuse their runtime identity. Field-index storage grows with
amortized capacity, avoiding a fresh full index allocation per instance.

The shared runtime layout validator derives final ownership/result contracts.
Only successfully checked programs reach bytecode lowering. Argument-growing
function families reject at existing graph, checking and display-name budgets
before emitting an executable program. Catalog, graph and identity storage belong
to the compilation arena; their source/name/diagnostic context is borrowed during
checking. No symbolic type parameters reach the runtime value representation.

## Coverage and remaining work

Tests execute construction, projection, updates, argument forwarding, named-result
success/error propagation, partial result fields, owner acquisition/cleanup,
borrowed mutation and returned-input references. Imported helpers retain public
value lookup and nominal identity after specialization. Allocation-failure sweeps
cover shape/canonical storage, arrays, ownership, modules and VM execution.
Uncalled invalid templates reject field/payload/type errors, incomplete matches,
result drops/loops, duplicate moves, cleanup effects and arena escapes. Growing
function specialization is checked without guest execution. CLI tests execute a
late-created instance and verify structured diagnostics for an uncalled bad body.

Validation: the full interpreter suite passes 841/841 Zig tests and all 21
Python drivers. The 83 nominal-focused tests pass in ReleaseFast. Formatting,
the gated install and all 88 Guardian checks pass with baselines disabled.

Buffer/pool acquisition and their fixed operation result contracts can use
symbolic nominal result wrappers. [Provider-specific symbolic shapes](nominal-providers.md) now cover external
resources, resource I/O and environment reads. Generic callers may use codecs for
concrete domains; codec constraints on type parameters remain pending. Public generic schema exports, structural
constraints, source serialization, finer incremental
checks and measured agent repairs remain open. The board trial now uses shared
`Slot<T>` declarations and one equality-constrained membership helper. Native guest compilation remains
outside the active goal.
