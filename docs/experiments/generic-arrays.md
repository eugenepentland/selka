# Generic fixed arrays

Numeric fixed-array types can now depend on a function's type parameters. The
same function can construct or inspect arrays of distinct IDs without exposing
their backing values or duplicating its implementation.

```text
fn pair<T:copy>(a: T, b: T) -> [2]T {
    return new [2]T[a, b];
}
fn contains<T:equality>(items: [2]T, needle: T) -> bool {
    let mut i = 0u64;
    while i < len(items) {
        if items[i] == needle { return true; }
        i += 1u64;
    }
    return false;
}
```

Run `examples/generic-arrays.my` on the VM; it returns `3`. It uses one membership
function for component IDs and net IDs. Substituting one domain for the other
still fails type checking.

## Rules

`[N]T` requires an explicit unsuffixed numeric length. `T` can appear in nested
arrays, function parameters/results, local annotations, constructors, reference
and slice contracts, and explicit arguments such as `pair::<[2]T>(...)`.
Every use retains its declared element identity and length. Independently
spelled `[2]i64` types resolve to the same concrete shape. Empty arrays preserve
type identity even though they contain no values.

Uncalled templates are checked symbolically. Reading `[2]T` produces `T`, so
arithmetic needs `T:integer` and equality needs `T:equality`. Arrays themselves
do not acquire equality or integer operations. Existing `copy` contracts exclude
owned values and pending results; zero-length concrete arrays retain their
ordinary copy rules. Unknown names are still errors: only the type parameters
of the enclosing function can defer element resolution.

Construction checks element count and type. Indexing, `len`, replacement,
snapshots, local whole-value/slice borrowing, exclusive writes and returned
input slices use the existing language rules. Shared views cannot write, local
views cannot escape, and arrays cannot hide arena-local authority. VM operations
retain bounds and step limits and source locations. Copyability does not promise
allocation-free host storage.

## Implementation and limits

The abstract checker preserves recursive array shapes with symbolic leaves.
Calls substitute type expressions, and structural matching compares lengths,
elements and any already-concrete enum keys. It never uses a representative
integer type to validate a template.

The concrete checker interns instantiated numeric arrays by `(length, element
identity)` and reuses existing concrete declarations. Additional layouts grow
with the catalog, and downstream ownership, effects, region checks and lowering
consume that final catalog. There are at most 4096 added array shapes and the
existing 4096 function-specialization limit remains. Type traversal retains
checking depth/work limits; expanding generic recursion fails explicitly.

This is the fixed-array part of parameterized composites. Parameterized records
and unions/results now follow [nominal body checking](nominal-bodies.md). Generic
named buffers, length parameters and structural requirements on an otherwise
opaque `T` remain open. A parameter-dependent enum-keyed table
rejects with `E_GENERIC_ARRAY_KEY`; existing concrete enum tables remain usable.
The [board trial](../../experiments/board_trial/README.md) now uses a shared
optional-slot union and one equality-constrained membership routine, preserving
its fixed contract.

No guest-native backend implementation or acceptance work accompanies this
change. Specializations lower to existing typed-array IR and VM instructions.

## Evidence

`src/generic_arrays_test.zig` covers shared nominal-ID membership, nested and
cross-template substitution, concrete shape reuse, empty arrays, invalid
uncalled templates, copy/result obligations, arena escapes, snapshot mutation,
borrowed/returned views, bounds locations, formatter round trips, imported
public generic functions, allocation failures and expanding recursion limits.
`test/integration.zig` checks real CLI execution and structured diagnostics.
These are development regressions, not measured agent repair outcomes.
