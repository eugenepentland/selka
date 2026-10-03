# Independent table-source review

Assessment: no actionable semantic issue found in lookup's source commit
`b862e559011f7e92e8491826b90e590290473a79` and the requested composed table paths.
The reviewed candidate is `codex-lox-ownership-inline-20261003`'s
`.tmp-lox-table-read-20261003/final-direct` (81 tests); the composed source is
root's `.tmp-lox-next/combined` (84 tests). This review made no source edits and
ran no tests, guests or performance workloads. `review.json` records source,
overlay, pinned SPEC and evidence identities plus independently checked results.

The five-file overlay replays in memory with exact context and matches all 37
final source/metadata files. Control and final hashes match both lane freeze
descriptors and root's composition receipt. `table.my` and `table_test.my` are
byte identical in the 81- and 84-test sources. The six changed production caller
bodies are also identical in those sources. All 80 baseline tests remain; the
new table snapshot test remains in both the 81- and 84-test sources.

The original public `get(Table,key,hash)` function body is byte identical to
control. `get_entries` has that exact body after replacing only `t.entries` with
`entries` and `t.count` with `count`. Count zero returns None before indexing.
Live nil values return Some(nil); NO_OBJ keys never match a tombstone. Tombstones
continue probing and a truly empty entry terminates it. The same capacity mask,
u32 conversion, checked addition, bitwise wrap and checked list access remain.
The insertion/deletion finder, capacity adjustment, set/delete/add_all and
tombstone predicate are unchanged. This retains pinned SPEC v1.1 §§0 and 6.1:
the layout and algorithm remain the existing linear probe, with a readonly
argument representation that other ports can copy; no cache or unsafe shortcut
is added.

The six call changes are class method lookup, hashed class lookup, instance
member lookup, two tree globals paths, and VM global lookup. Entries and count
come from the same readonly owner, with no callback or mutation between their
evaluation. The only computed later argument is the unchanged `string_hash`,
which reads the unchanged `string_obj` kind check and hash field; it invokes no
observer, Lox allocation or collection. Moving the count projection from the
callee to argument evaluation therefore cannot observe a different Table.
Tree assignment still evaluates its RHS before taking these projections. Nil
and false instance fields still produce Some and shadow methods; binding and
allocation occur only after the probe returns. Normal readonly parameter and
snapshot/COW rules retain the list; no mutable view escapes and no owned Table
carrier is needed during the read. The original public getter keeps its old
native frame behavior for existing direct API calls. Internal helper names can
differ in native implementation-bug diagnostics; Lox errors use the unchanged
VM/tree error paths and are covered by saved exact comparisons.

The added regression retains a Table snapshot and an independently saved list
plus count across overwrite, deletion, tombstone reuse and capacity growth. Its
hash 7 chain starts at the final slot and wraps through zero; it checks empty
reads, missing/NO_OBJ keys, live nil, old values, live replacements, and 8→16
capacity. Existing wrap/tombstone tests continue exercising the public getter.

Saved qualification evidence independently verifies four fresh 81-test runs
(324 passes, zero cached/failed/skipped/dropped), their log hashes and zero
process statuses. The compressed validation receipt contains 712 exact
status/stdout/stderr comparisons, including Lox GC statistics, with all sample
input hashes and six binary hashes still matching. Its 104 omitted native
stressed corpus smoke observations are explicitly unrun. These are existing
author receipts, not new executions by this review.

Limits: this review does not independently qualify VM callee changes outside
the six composed table caller bodies or establish the runtime qualification of
the complete 84-test composition. It makes no timing or speedup claim. Root
retains measurement, canonical acceptance and the prior accepted source.
