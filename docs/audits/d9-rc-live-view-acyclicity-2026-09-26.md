# WP-4 stored live-view cycles

The acyclic heap premise in D9 did not follow from the previously admitted type
rules. A live dictionary view can be stored inside a value of its own mapping:
`Entry.view: DictValues[int, Entry]`, followed by
`mapping[0] = Entry(view=mapping.values())`. This is a real persistent cycle,
not just a recursive type or a temporary borrow.

The accepted GC compiler at `f6bea5d9` built and ran this source successfully;
both live-view assertions passed with exit status zero. The experimental H-token
lowering also ran it successfully, but counting recorded four heap allocations
and zero retirements, with nine hold acquires and eight releases. The remaining
hold keeps the dictionary, its raw backing, and the stored entry alive. The
source and execution records are preserved in
`experiments/d9-rc-view-cycles-20260926/`. This was not previously rejected.

The new default-model admission rule, `LIVE-VIEW-ACYCLIC-1`, rejects a strongly
connected component of actually stored types when it contains a builtin live
view's reference to its dictionary. Stored edges include record fields, variant
payloads, domain representations, nonempty arrays, and managed collection keys
and elements. Generic arguments that are not physically stored, zero-length
arrays, and callback signatures do not add edges. Builtin declaration identity
selects the rule; a user record named `DictValues` has ordinary record policy.

This is deliberately conservative: instances of the same recursive type may
refer to disjoint dictionaries and still receive `E_LIVE_VIEW_CYCLE`. It is a
new source restriction needed by the existing D9 acyclic runtime decision.
Replacing the field with a `list(view)` snapshot preserves a recursive value
model, while pool ids express graph links. Ordinary retained or returned views,
dictionary snapshots, and recursive types without stored live-view cycles remain
admitted. `--legacy-sharing` preserves the earlier tracing-only behavior.

The check runs after catalog filling, including each new concrete generic
instantiation. Iterative Tarjan traversal uses O(types + stored edges) work and
O(types) temporary storage, with no fixed recursion cutoff or native recursion.
All temporary arrays and refused diagnostic allocations are released on failure.

Validation: five focused tests (16 selected/import tests) pass. They cover direct,
mutual, generic, variant and array cycles; accepted ordinary views, snapshots and
recursive values; phantom arguments, empty arrays and user-shadowed names; legacy
compatibility; a 32,768-type stored chain, both cyclic and acyclic; and refusal at
every allocation in the graph traversal and diagnostic publication. The separate
builtin declaration marker test passes 12/12. The final joined full gate remains
the integration owner's responsibility.
