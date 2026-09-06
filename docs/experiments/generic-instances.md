# Concrete specialization identity table

`generic_instances.Registry` supplies the bounded identity table needed to
replace semantic checking's current one-declaration/one-executable-function
assumption. It is independently tested but is not yet connected to executable
lowering. Valid generic programs still receive `E_GENERIC_UNSUPPORTED`.

## Identity and ownership

A key contains the resolved declaration ordinal in the linked syntax program and
an ordered sequence of concrete `typed.Type` identities from that compilation.
Spelling, source pointer addresses, requirement sets, and runtime layouts do not
participate in equality. Two nominal types with the same representation remain
distinct, as do reordered arguments and different declaration ordinals. The caller
must establish valid declaration/type identities, privacy, arity, and requirements
before interning; this table is not a substitute for semantic validation.

The table copies argument storage. Later caller mutations cannot change its keys.
Instance IDs follow first discovery order and survive table growth; callers retain
IDs rather than pointers into the growing entry array. A returned key's argument
storage remains valid until registry destruction. IDs are compilation-local and
must not be persisted or compared across different compilation catalogs.

## Bounded discovery and failure

At most 4096 entries and 16 type arguments per entry are accepted. Empty argument
lists can represent ordinary functions in the eventual shared discovery queue.
The eventual lowering worklist will traverse entry ordinals and append new
instances as callees are discovered. A recursive request for an existing key
returns its existing ID without extending the table, including at capacity.
Distinct expanding specializations eventually receive `TooManyInstances`.

Insertion reserves all table storage and copies arguments before publishing an
entry. Allocation failures leave logical contents and IDs unchanged, although
reserved capacity may grow. Retrying the same insertion after allocation recovery
uses the next unused ID. Destruction releases keys and both tables. Invalid reads
receive `InvalidInstance` instead of indexing outside the table.

## Acceptance and integration still required

Tests cover argument ownership, declaration separation, ordered arguments,
nominal types with equal representation, deterministic ordinals, 16/17 arguments,
4096/4097 entries, lookup at capacity, invalid IDs, allocation-failure sweeps, and
recovery with existing entries across table-growth boundaries.

Next, concrete semantic checking must resolve generic calls into this registry,
substitute each instance's types while retaining original declaration source and
module context, and check queued bodies independently. Typed-function indexes,
per-instance expression caches, effect/region analysis, schema/tooling identities,
and VM/native execution need integration. The registry alone does not prove
executable specialization, generic recursion behavior, or completion of generics.

Validation: all 568 core tests passed in Debug; focused instance-table acceptance
passed six tests in Debug and ReleaseFast, including allocation-failure sweeps
and recovery. The build passed all 88 Guardian checks with baselines disabled.
This is registry and ordinary regression evidence; no new executable generic,
CLI, or full native-suite result is claimed.
