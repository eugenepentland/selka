# Provider operations in generic bodies

Generic bodies now support clock/random reads, bounded environment lookup,
filesystem/network acquisition and completion, capability attenuation, fixed-byte
resource I/O and I/O through caller-supplied slices. Concrete result schemas and
capability types are checked before instantiation, including for uncalled templates.

Clock success is `i64`, random success is `u64`, and both use `i64` errors.
Environment results require the existing bounded bytes/length/present schema and
a fixed-byte name. Resource acquisition requires the matching resource success,
`i64` error, correct capability family and fixed-byte request. Completion transfers
the resource and returns the existing bool-success/owned-error contract so failure
can be retried without copying ownership.

Resource I/O requires a mutable, available value binding after evaluating its
arguments. Fixed-byte read/write results keep their existing contracts. Slice
reads require an exclusive `u8` view; writes may use shared or exclusive byte
views. Reference kind, parent suspension and mutability checks remain active.
Only bytes reported by a successful read replace the destination; unreported tail
bytes remain unchanged. Permission attenuation operates on explicit capabilities,
and the runtime retains its intersection rules so narrowing cannot amplify rights.

Direct provider effects enter the existing abstract call graph and propagate
through helper cycles. Bounds still apply to uncalled templates and source branches
that do not execute at runtime. Generic forwarding does not create capabilities or
bypass provider availability, permissions, budgets or ordinary specialization checks.

## Acceptance

`src/generic_providers_test.zig` covers malformed concrete results, wrong capability
families, non-byte inputs, immutable/consumed owners, argument-induced transfers,
incompatible read views and forbidden effects. The existing recursive-helper test
now checks effect-bound rejection rather than blanket unsupported-operation rejection.

Provider tests execute generic clock/random reads, environment lookup, resource
completion retries and slice I/O with callback counts and allocation-failure sweeps.
Native provider/environment harnesses include generic versions of their scalar,
error, missing-capability and bounded-byte cases. Resource parity covers retries,
denied completion, fixed I/O for both provider families, typed read failure,
permission attenuation and caller-supplied slices. Sanitizers and allocation
injection check cleanup and provider trace agreement. The provider builder fixture
is selected explicitly so its expectation does not depend on source-list order.

`examples/generic-provider-slices.my` takes explicit filesystem authority and uses
a caller-owned byte array. Its result is the reported read length plus write length,
so the numerical result depends on the selected provider's partial I/O behavior.

## Remaining work

Local arena/reset scopes and constructing buffer/array views inside templates still
need abstract origin, lifetime and borrowing rules. Existing caller-supplied slices
and lexical reborrows remain distinct from those pending local view operations.
Structural generic types, generic codec constraints, public generic tooling, source
byte serialization and the remaining roadmap tracks remain open.
