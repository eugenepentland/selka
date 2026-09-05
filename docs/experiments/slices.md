# B: bounded slices

Status: scoped shared/exclusive slices, narrowed reborrows, indexing, and slice
parameters are implemented. [Returned-reference contracts](returned-references.md)
are also implemented and complete B. The whole-value reference contract is in [borrowing.md](borrowing.md).

## Syntax and types

```text
fn increment(values: &mut []i64) -> i64 {
    let mut i = 0u64;
    while i < len_slice(values) {
        write_slice(values, i, read_slice(values, i) + 1);
        i += 1u64;
    }
    return 0;
}

fn main() -> i64 {
    let mut values = new [3]i64 [2, 3, 5];
    borrow mut values[1..3] as window {
        discard increment(window);
    }
    return values[1] + values[2];
}
```

`borrow owner[start..end] as name { ... }` borrows a shared half-open range.
Adding `mut` requests exclusive access. Both endpoints are required. The source
must be a named fixed numeric array, a whole-value reference to such an array,
or an existing slice. Enum-indexed tables retain their nominal key API and cannot
be sliced numerically. Scalar and arbitrary record storage cannot be sliced.

`read_slice(slice, index)` returns an element value snapshot.
`write_slice(slice, index, replacement);` requires exclusive access and an exact
element type. `len_slice(slice)` returns u64. Elements may be any existing value
type, including records, domains, variants, and nested arrays. Ordinary domain
privacy and nominal identities remain enforced.

A shared slice parameter is `&[]T`; an exclusive parameter is `&mut []T`.
Parameters accept different lengths of the same element type. A whole-array
reference such as `&[3]T` is distinct; form an explicit slice to pass it to a slice
parameter. Whole-value `read_ref`/`write_ref` operations reject slices, and slice
operations reject whole-value references. Slices remain scoped references and cannot be copied into value bindings or
stored in aggregates. Returning a slice requires an explicit input-lifetime
contract; see [returned references](returned-references.md).

## Bounds, evaluation, and reborrowing

Endpoints and indices accept any integer width, with no implicit conversion to a
narrow host index. The VM checks `0 <= start <= end <= source length` before
converting endpoints. Empty ranges may start at the source's end and have no valid
index. Element access requires `0 <= index < slice length`. Negative, reversed,
full-range u64, and overflowing requests trap with `R_SLICE_BOUNDS` at the access
or borrow source span. Bounds checks apply in Debug and ReleaseFast.

Range endpoints evaluate exactly once, from start to end, before acquiring the
new loan. A write evaluates its index then replacement, then checks access and
bounds. Consequently a replacement expression that traps does so even if the
index is out of bounds. Calls retain the reference-parameter rule: value arguments
finish before temporary callee loans begin.

A child range is relative to its parent slice. The VM composes offsets after
checking against the parent's visible length. `borrow slice as child` without a
range reborrows the entire visible slice. Whole-allocation locks remain in force:
disjoint or empty exclusive slices of one owner still conflict. An exclusive
parent is suspended while a child or callee loan is active, including for length
queries. Shared parents may have shared children and remain readable.

Normal exits and early returns end child loans before parents. Loop iterations
and repeated calls reuse registry slots. Stale names, conflicting owner accesses,
shared-to-exclusive escalation, wrong element types, and suspended references
are rejected by source checking; runtime identities independently check lifetimes.

## Value preservation and costs

Borrowed arrays remain one-element guest-memory cells containing the whole array
value. A VM reference combines its generation-checked cell lease with a private
slice offset/length; guest code cannot edit these fields. Narrowing never exposes
host pointers or bypasses the cell lease's permission and lifetime checks.

Reads retain element snapshots. A slice write creates a replacement array value,
changes the selected element, and stores it through the exclusive cell lease.
Existing array and element snapshots remain valid. The current write cost is
linear in the full owning array's immediate element count, including when the
slice covers only a small range. Nested values are retained, not recursively
cloned. This is the established immutable aggregate behavior, not a constant-time
in-place write or an optimization claim. Future storage optimization must preserve
these copy semantics and the same borrow tests.

All runtime buffers use the execution allocator. Guest traps, failed array copies,
failed lease creation, and host allocation failure release storage. Emission
validation checks slice metadata, element identity, parameter modes, operation
kind, and stack effects. There is no loader for untrusted bytecode.

## Evidence and remaining work

176/176 tests pass in Debug and ReleaseFast (153 core, 23 actual CLI), on Guardian's
`0.17.0-dev.1683+5ceec001b` snapshot. Slice tests cover:

- empty/full/narrowed ranges, mixed integer widths, negative/reversed/huge bounds;
- owner and element snapshots, nested arrays/records, domain privacy, and exact types;
- shared/exclusive conflicts, recursive narrowing, helper parameters of varying length;
- evaluation order, early returns, allocation failures, and every instruction-budget
  trap boundary in a nested aggregate/slice/call program;
- 10,000 slice writes through helper calls within 16 KiB of live runtime allocation;
- malformed slice metadata, invalid operation kinds, and suspended runtime access;
- canonical duplicate identity for ranges, permissions, element types, and indexing;
- actual CLI run/check/disassembly, bounds traps, and alias diagnostics.

`examples/slices.my` returns 13 and preserves the original array snapshot.
Formatting and whitespace checks pass. Guardian gates were not exercised.
Returned-reference contracts and their escape/cleanup acceptance tests are now
implemented. [B acceptance](b-audit.md) records the completed experiment; other
unfinished roadmap tracks retain their full scope.
