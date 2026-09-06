# Buffer and pool operations in generic bodies

Generic templates now acquire buffers and pools through explicit allocator
arguments and concrete result schemas. Capacity may use a symbolic type with a
declared integer requirement. The success payload must be the matching buffer or
pool type, and the error payload must be `i64`. The ordinary and symbolic checkers
share `typed.acquisitionShape` for this contract.

Buffer length/capacity/read/write/append/resize/reserve and pool
length/capacity/insert/read/replace/remove/clear now have abstract checking. Buffer
elements and pool handles retain exact nominal types; result payloads match each
operation. Mutation requires a mutable value binding. Operations evaluate arguments
before checking that their owner remains available, so an argument cannot transfer
the buffer/pool and leave an operation using a consumed owner.

Acquisition and buffer reserve contribute allocation effects to the existing
abstract call graph. Buffer append/resize stay within previously reserved capacity
and retain the ordinary `noalloc` behavior, as do in-capacity pool mutations.
`buffer_operations.Kind.allocates` is shared by the ordinary, bytecode and generic
effect checks. Effect bounds apply to uncalled templates and reachable helpers.

Result propagation, partial ownership and cleanup retain their existing rules.
A failed acquisition or mutation can propagate without leaking previously owned
values. No ambient allocator is introduced, and owned type arguments still do not
satisfy the `copy` requirement.

## Acceptance

`src/generic_runtime_test.zig` rejects invalid acquisition results, wrong allocator
arguments, noninteger capacities, insufficient symbolic constraints and forbidden
allocation effects. It also rejects moved/immutable owners, owner transfers in
operation arguments, mismatched element/handle types and malformed result schemas.

The execution/allocation-failure scenario covers acquisition, buffer append,
reserve, resize, write/read, pool insert/replace/read/remove/clear, queries and
propagation through generic helpers. `examples/generic-runtime.my` returns 33.
Native comparisons also cover imported generic acquisition/mutation helpers,
negative-capacity failure with an earlier owned buffer, and a located empty-buffer
read trap. Compiler allocation sweeps include checking, VM execution and C emission.

## Remaining work

Local arena/reset scopes and buffer views still need abstract origin, lifetime and
borrow rules. Filesystem/network acquisition/completion/I/O and clock/random/
environment operations still need their own capability, permission, result-shape
and direct-effect checks in templates. Existing owned resource forwarding and
cleanup do not imply those operations are implemented. Structural generic types,
codec constraints, public tooling and the other roadmap tracks remain pending.
