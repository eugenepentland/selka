# Whole slices and grouped borrows

Use `[..]` to borrow all initialized elements without repeating an owner's length:

```my
borrow mut values[..] as view {
    write_slice(view, 0, 42);
}
```

This works with owned buffers, fixed arrays, byte strings, and existing slices.
For a buffer it uses initialized length, not capacity. For a slice it preserves
that slice's current boundaries, including an empty or previously narrowed view.
The equivalent explicit spelling remains `values[0..len_buffer(values)]` for
buffers, `values[0..len(values)]` for arrays, and
`values[0..len_slice(values)]` for slice references. Partial ranges still require
both bounds; `values[..end]` and `values[start..]` are not supported.

Independent borrows can share one declaration and block:

```my
borrow mut ids[..] as ids_view,
       mut durations[..] as durations_view,
       needs[..] as needs_view {
    discard compute(ids_view, durations_view, needs_view);
}
```

Each clause has its own optional `mut`. Omitting `mut` creates a shared view even
when an earlier clause is mutable. Whole-value references, explicit slice ranges,
whole slices, and reference-returning calls can appear in the same group.
`borrow value as reference` keeps its existing whole-value meaning.

Clauses behave exactly like nested borrow scopes in source order. Each clause is
acquired before the next clause is checked or evaluated, and later clauses may
use earlier views under the usual reborrow rules. Shared aliases remain legal;
a mutable borrow still prevents conflicting access to its owner. Two mutable
views of the same owner are rejected even if their ranges look disjoint; use the
existing checked `split` operation when disjoint mutable slices are needed.
Grouped syntax does not introduce alias annotations or bypass ownership checks.

The block sees all declared references. On normal exit, `return`, propagated
`try` failure, `break`, or `continue`, the existing cleanup machinery releases
exited borrows in reverse acquisition order. Names expire at the end of the
block, suspended parent references resume afterward, and buffer growth is still
forbidden while an element view exists. An owned element cannot be copied through
a slice, and slicing through a whole-buffer reference remains forbidden; borrow
buffer elements directly from their owner in a separate lexical scope.

Generic functions enforce the same permissions and lifetime rules before
instantiation. Every clause counts toward the existing parser nesting budget,
so a flat declaration cannot create an unbounded chain of nested semantic scopes.

The parser lowers a group into ordinary nested borrow statements. Whole slices
become the existing typed `0..length` range after the owner and element checks;
the VM, native emitter, region checks, and cleanup passes use their ordinary
borrow representations.
