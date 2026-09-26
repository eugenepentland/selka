# D9 stage 3b: phase 1 mechanism and phase 2 join

Phase 1 adds an internal QBE emission policy, `Policy.cow = .checks` or
`.counting`. The ordinary policy is `.off`, and its QBE IL is unchanged. The
policy plans uniqueness checks from stage 2 ownership sites, moves safe checks
to loop entry edges, handles writes through nested element/entry/field places,
and pins collection arguments during `mut` calls. The native runtime stores a
sticky shared bit and a temporary pinned bit in the existing two-word object
header. `myl_native_cow_share`, `myl_native_cow_unique`,
`myl_native_cow_unique_in`, and `myl_native_cow_copy` are the payload operations.
`myl_native_cow_share_value` marks direct collection payloads in an inline
record, array or active variant without walking into a marked collection.
The C tests exercise these operations with collection on every allocation.

Stage 3a's only real-copy hook is `qbe_value_copy.zig:Lower.emit`, which emits
`myl_qbe_value_copy(ctx, descriptor, source, output, children)` after ownership
analysis rejects moves and borrows. The phase 2 join should keep that decision
and the hook's output scratch. For a real copy, memmove the value into the
scratch, root it by its descriptor, then mark each directly held mutable
collection shared. A pinned payload needs an immediate shallow copy in the
scratch because the callee's `mut` slot cannot be redirected. When `children`
is one, the outer list or dictionary is already fresh from a shallow copy,
slice or concatenation: leave its header unshared and mark the mutable payloads
held by its elements or entries. Inline records, variants and arrays inside
those elements must be traversed; a child collection's own storage must not.
Class and Cell remain shared references, and immutable text and byte strings
need no mark. The runtime can expose a `myl_qbe_cow_transfer` entry with this
signature while reusing the existing C primitives and output root protocol.

Enable `Policy.cow = .checks` when stage 3a enables `--value-semantics`, and
`.counting` for an internal measurement build. Pass `shares = false` to
`cow_plan.plan`: its present transfer marking is a phase 1 stand-in for the
3a hook, and retaining both would mark one transfer twice or mark a transfer
3a classified as a move or borrow. Keep uniqueness checks and pinning in the
plan. Include the COW policy in per-function cache identity, as phase 1
already does, then test the 3a switch corpus, nested paths, arena exits and
`--gc-stress` against the eager result. The final performance comparison and
counters belong to phase 2.

The close-out plan says a COW copy allocates in the current arena. Phase 1
allocates it in the replaced payload's owning region instead. A uniqueness
check redirects the *existing owner's* slot; an outer-arena or tracing-heap
value may be shared and then written while an inner arena is open. Allocating
its replacement in the inner region would leave that owner pointing at memory
released when the inner scope ends. The ordinary region store barrier prevents
placing a younger value into an older collection, and `arena.escape` copies
values explicitly into the enclosing region. The C arena regression exercises
an outer owner whose COW replacement survives an inner arena exit, plus a heap
owner surviving an arena exit. This choice preserves the region lifetime
invariant without changing the language's arena escape rules; phase 2 should
compare the same cases with stage 3a's eager implementation.
