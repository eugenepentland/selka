# C: transitive effect-bound foundation

Status: effect inference, explicit bounds, allocation checking through calls, witness
diagnostics, and independent emission validation are implemented.

This is a dated checkpoint. The explicit-storage tier it was written against was
removed on 2026-09-13, and the `allocation` effect it describes is now
`managed_allocation` over garbage-collected values; see
[managed memory](../managed-memory.md) for the current contract. The example
below keeps its original spelling and is not executed.

## Contracts

A function may have one contextual annotation between its result/lifetime contract
and body:

> The example below is quoted from the removed explicit storage tier (`&mut []T` slices, `borrow`, `discard`, `std_json`) and is not source the compiler accepts; see [docs/legacy/](../legacy/README.md).

```text
fn edit(values: &mut []i64) -> i64 noalloc {
    write_slice(values, 0, 7);
    return read_slice(values, 0);
}

fn release(values: Numbers) -> i64 effects() {
    discard values;
    return 0;
}

fn main() -> i64 effects(allocation) {
    // Acquisition is permitted here; no other external effect is permitted.
    return 0;
}
```

The finite effect vocabulary is `managed_allocation`, `filesystem`, `network`,
`clock`, `random`, and `environment`. `effects(...)` names the allowed set; an empty list
allows none. Unknown names and duplicate entries are source errors. List order
has no semantic significance. An omitted annotation imposes no explicit bound.
All ordinary function summaries are inferred, including uncalled functions.

`noalloc` excludes managed allocation and permits the other effects. `noio`
excludes only filesystem and network access: it permits allocation, clock,
randomness, and environment access. Neither annotation implies determinism,
absence of traps, bounded memory, or termination. Local mutation is not an
external-I/O effect. The external names have declared meanings, but no source primitives for
those external effects have been added at this checkpoint.

## Allocation meaning

Allocation is creation or potential growth of **managed guest storage**:
constructing or growing a list, dictionary, string or byte string. Fixed-slot
writes, reads and element copies do not allocate managed storage.

This contract does not promise zero host allocator calls. The VM may allocate for
operand/frame bookkeeping, immutable value representation or result wrappers. A
noalloc function can return a value or result wrapper without allocating managed
storage. Generated operations inherit that semantic classification.
Native/alternate execution must preserve the guest contract; a physical
allocation-free backend guarantee is a separate, unfinished concern.

## Inference and diagnostics

An iterative traversal visits the checked body, including constructor/update
operands, branch conditions/bodies, loop bodies, short-circuit operands, slice
bounds, and calls. It follows resolved call identities,
not function spelling. It conservatively includes syntactically present untaken
branches and short-circuit operands. Suppressing or handling a result does not
erase effects.

A reverse call graph propagates finite effect sets until unchanged. Only callers
of a changed summary are revisited; recursion does not require recursive host
traversal. Each newly discovered effect keeps an origin or callee witness. A bound
violation reports `E_EFFECT_BOUND` at the annotation, names a path such as
`main -> helper -> allocate`, and points to the originating operation.
Witness edges are recorded when a bit first becomes known, so recursive cycles
cannot create a cyclic explanation path.

Typed nodes, operation kinds, and emitted instructions are classified with
exhaustive switches. New variants require an implementation decision. The bytecode
validator independently recomputes summaries from operations and all call forms;
it rejects a forged summary or a bound that the emitted program violates. There
are no function values, external declarations, or unknown dynamic call effects yet.

Dumps show inferred sets and explicit allowed sets. Exact duplicate discovery is
`exact-v16`, preserving inferred effects and normalized declared bounds. Identical
bodies with distinct interface contracts are not grouped as exact duplicates.

## Acceptance evidence

`src/effects_test.zig` and the lattice test in `src/effects.zig` cover direct and
transitive allocation, unused functions, mutually recursive graphs, declaration
reordering, calls/results, constructor operands, conservative branches,
annotation errors, forged emitted metadata, and duplicate
identity. A 512-function recursive graph produces a finite allocation witness.
An internal lattice test exercises all six effect bits and isolates unrelated
functions; external capability behavior is not inferred from that synthetic test.

Allocation-failure sweeps cover inference, witness rendering, checking, emission,
execution, dumps, and discovery. Debug and ReleaseFast pass 251 tests (223 core,
28 actual CLI). The effects example returns 14; every checking command rejects
transitive allocation under noalloc. Formatting and whitespace checks pass.
