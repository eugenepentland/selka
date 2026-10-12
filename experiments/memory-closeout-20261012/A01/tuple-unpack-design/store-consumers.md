# Complete tuple Store consumer audit

This is a consumer inventory, not completed qualification. The marker preserves the
original RHS as one expression and adds only local binding metadata.

| Consumer | Required handling |
| --- | --- |
| `sema_places.zig` | Produce initialize-only marker; stage all fields before source destination effects; null only explicit `_`. Existing named Result obligation logic remains. |
| `typed.zig` | Coordinator declaration; hidden whole slot and optional exact-arity local vector. |
| `core/single_owner.zig`, `core/build.zig` | A07 source move/provider checks, live-catalog shape/type validation, single checked transfer and ordinary non-destructive projection; original hidden slot unavailable after checked split. |
| `semantic_store.zig` | A08 format v8 and load/publish structural validation. |
| `semantic_copy.zig`, `ast_copy.zig`, `persist_codec.zig` | Generic recursion handles/deep-copies optional local-ID slice; local IDs remain function-local. A08 tests exact restore. |
| Core tree hashing | Generic recursion includes optional presence, length and local IDs. A08 tests cached source edits and relocation. |
| `origins.zig` | Preserve the previous projected-field mutation origin in every non-null staged local whose type carries writable storage. Named independent copy semantics still apply when fields are subsequently published. |
| `effects.zig` | Preserve projected parameter origin. A fresh tuple shell alone does not make every field fresh; staged fields use the previous conservative field-projection freshness. |
| `value_semantics.zig` | Synthetic staged locals trace the whole RHS path for existing source write diagnostics; metadata does not reevaluate RHS. |
| `value_semantics_check.zig` | Reads the updated Facts table. Named destination initialization remains a separate source store; no new source payload binding is introduced. |
| `duplicates.zig` | Exact canonical fingerprint must encode marker presence, vector length, each position/null/slot identity. Otherwise first-vs-second same-type extraction becomes a false duplicate. |
| `typed_walk.zig` | Visits original RHS once; binding metadata is not an additional expression. |
| `iteration_place.zig` | Named destinations are published by subsequent ordinary stores before source iteration can reference them. New staged locals are never exposed as syntactic loop sources; existing root-rebinding snapshot semantics remain. |
| `navigation.zig`, `lint.zig` | Internal locals stay hidden. Source-visible named writes/reads remain ordinary later stores; sentinel logic already skips internal stores. |
| `core/typed_dump.zig` | Display unpack vector to make the new ownership operation inspectable; coordinate with A07. |

The initial source class-mutation probe is rejected with E_VALUE_CLASS both before
and after staging. It is preserved as a refused probe, not an admitted-source
regression. The concrete provenance test instead starts from a supported tuple
of list/int, proves the named copy has no external mutation, then changes only
that destination to a compiler temporary in a controlled typed graph. Its mutation
must retain parameter zero's origin; erasing the staged-field binding would mark
it fresh. A second test checks the exact staged read traces its RHS parameter in
Facts. Neither test enables classes, stored views or new inference.
