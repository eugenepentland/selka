# Concrete owned values in generic bodies
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Generic templates now accept concrete buffer, pool and external-resource types,
including owned records, arrays, union payloads and results. Type parameters remain
subject to their declared copy/equality/integer constraints; this does not make
owned values satisfy `copy` or add generic type constructors.

Whole-value reads transfer owned values once. Partial field moves preserve the
remaining ownership state. Repeated moves reject, and branches, matches, loops
and short-circuit expressions must agree on the ownership state of continuing
paths. Ordinary owned values may be dropped explicitly or by scope cleanup;
result-bearing values still require handling. Replacing an ordinary owned binding
releases its old value and restores availability; replacing an unhandled result
still rejects. Owned reference parameters and general borrows remain disallowed,
matching the existing ordinary checker.

The abstract pass now collects cleanup effects from concrete return/parameter/local
types and resolved helper-call edges. It reuses the ordinary effect checker's
cleanup masks and monotone call graph inference. Filesystem/network cleanup effects
therefore propagate through recursive helper cycles and reject incompatible bounds
in uncalled templates. Empty arrays of resource types have no cleanup effect.
Concrete specialization still performs complete effect and bytecode validation.

The body checker no longer applies a wire-data-only graph restriction to concrete
signatures. The shared catalog already validates type layouts; value operations
now enforce their own transfer/copy requirements. This also allows ordinary handle
identity to pass through copy-constrained templates without treating pool ownership
as copyable.

## Acceptance

`src/generic_owned_test.zig` covers repeated moves, path disagreement, incompatible
copy requirements, owned references, nested cleanup effects and transitive recursive
helpers. Buffer execution covers forwarding, implicit cleanup on both returning
branches, replacement and partial extraction, with allocation-failure sweeps through
checking, execution and native emission. Pool tests transfer the owner and preserve
copyable handle identity.

`src/resource_source_test.zig` adds provider-observed generic forwarding, explicit
field drop and implicit parameter cleanup; each acquired resource releases exactly
once, including allocation failures. `tests/native_resources.py` compares VM/native
provider traces for filesystem/network generic cleanup, denied acquisition and a
guest trap, using address/undefined sanitizers and injected allocation failures.
Its oracle distinguishes guest traps from host errors. The ordinary native parity
driver includes buffer and pool generic cases.

`examples/generic-owned.my` returns 14. `examples/generic-resources.my` returns 8
with the deterministic test provider; it requires explicit provider authority.

## Remaining work

This milestone adds owned input/value flow and cleanup effects.
[Buffer/pool acquisition and operations](generic-runtime.md) now validate explicit
allocator arguments, result shapes, mutation and direct allocation effects.
[Provider operations](generic-providers.md) now preserve capability, permission
and effect contracts. Local buffer/array views and arena/reset scopes still need
abstract origin and lifetime rules; their explicit rejection prevents unchecked
local-region operations.

Caller-supplied owned values can be forwarded; templates cannot yet introduce a
local region. Region scopes must track origins through local/field/call transfers
and reject escapes before they are enabled. Structural constraints, codecs and
public generic tooling remain pending separately, along with the other tracks.
