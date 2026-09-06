# Generic arena scopes and reset

Generic functions now use lexical `arena` scopes and typed `reset_arena` calls.
[The VM example](../../examples/generic-regions.my) returns `3` after testing
live-storage rejection, child-region rejection, reset and storage reuse.

Arena creation requires an explicit allocator and contributes an allocation
effect, including through helper calls. Reset returns an explicitly handled
bool-success/i64-error result and retains its ordinary noalloc behavior. The VM
checks whether storage or child arenas remain live before resetting; copying an
allocator capability does not create independent reset authority.

## Abstract lifetime checking

A function-local dependency graph records arena origins while the body is checked
symbolically. Stable graph nodes outlive lexical name removal. Assignment and
helper writes add dependencies monotonically; branches and loops cannot erase
an origin by restoring an earlier ownership snapshot. A worklist propagates
changed depths to a fixed point before checking escape constraints. Pending
worklist entries are unique, so its capacity is bounded by the graph's node count.
Graph construction remains subject to the generic checker's depth/work limits.

The ordinary and generic checkers share concrete type classification and the
`E_ARENA_ESCAPE` contract. Allocators, buffers/pools and aggregates containing
arena-bearing values carry dependencies. Plain values and inert pool handles do
not. A symbolic copy requirement alone may admit allocator-bearing values;
current equality/integer requirements exclude those values and need no origin.

Dependency propagation includes aggregate construction/projection/updates,
partial fields, match payloads, references, returned values and early error
propagation. Helpers conservatively retain dependencies from all relevant value
and reference arguments. Calls with mutable references must also respect the
destination lifetime, even when the helper returns a plain scalar.

A value cannot move into an outer binding or return from the function if it
retains a shorter-lived arena. Buffer/pool element stores are limited by their
owner's allocator origin. Writes through ordinary references use the owner's
lexical lifetime; writes through buffer slices use the buffer's allocator origin.
This deliberately follows the ordinary checker's conservative policy rather
than inferring that a particular helper discards an argument.

Heap allocations created inside an arena scope can leave if their actual
allocator is still the input heap. Plain snapshots can leave after reading a
local buffer. Inert handles may leave too, but runtime pool identity/generation
checks still reject stale handles. These are tested positive cases.

## Validation scope

Tests include malformed authority/result shapes, shadowing, scope exit, noalloc
bounds, copied capabilities, reset failures and success, and uncalled escapes
through returns, records, match payloads, propagated errors, helper writes,
reference writes, buffers and pools. Loop dependency cycles and writes after
initialization exercise the fixed point. Allocation sweeps cover checking and VM
execution; every step-budget boundary is checked with both VM memory backings,
including owner cleanup before region closure.

An actual CLI test imports a generic arena helper, checks general/arena VM modes,
and diagnoses an allocator escape at the imported module's source location.
The equality-constrained regression prevents rejecting a helper call whose
reference element cannot retain arena state under the current type rules.

Structural generic type constructors, codec constraints and broader public
generic tooling remain pending. Next interpreter-first work is diagnostic
provenance and repair fixtures, followed by typed host registration and the
board/constraint-processing trial. Native execution remains outside the active
goal.


Final validation on 2026-09-06: Debug and ReleaseFast pass all 714 core/CLI tests
(652 core, 62 CLI), the interpreter/tooling drivers and 96 independent corpus
comparisons. Focused generic coverage passes 108 tests. Formatting and all 88
Guardian checks pass without baselines; report-only size/line findings remain.
