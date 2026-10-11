# Semantic ownership still required for full self-hosting

Source audit of `cce6c1e83c1ceea88f650276f8ceaa96365c67b9`, 11 October 2026.
This inventory describes remaining implementation work. Body qualification,
component rebuilds, and this audit do not establish complete frontend ownership.

## What selecting the body component actually replaces

`src/sema.zig:selectedBodies` routes component mode to `adoptBodies` and shadow
mode to an exact comparison with `checkBodies`. The adopted value supplies body
nodes, statements, functions, diagnostics, import-use observations, and catalog
append recipes. `openBody` rejects a profile outcome; component mode does not
fall back to native body checking. Catalog reconstruction and validation remain
native. Selecting all existing frontend components does not replace the entire
`checkProgram` coordinator or its later passes.

## Remaining native work, in execution order

| Stage | Current implementation | Required migration evidence |
| --- | --- | --- |
| Catalog and declarations | `records.collectWithNames`; function/type name conflicts and ordinary/lambda instance indexing in `sema.checkProgram` | Identical nominal and structural catalogs, generic identities, import resolution and declaration diagnostics, including unused declarations and errors preceding body diagnostics. |
| Symbolic contracts | `sema.checkGenericContracts`, invariant indexing and contract helpers | Generic template requirements, record invariants, pre/postconditions and their diagnostics, including uninstantiated templates. Successful specialized bodies alone do not prove this stage. |
| Executable entry | `sema.checkEntry`, parameter validation, `entry_adapter.supported` and `entry_adapter.adapt` | Exact argument/capability validation and synthesized entry behavior for supported scalar, unit and checked-result returns. Cover library checking without an entry and project entry name resolution. |
| Foreign declarations and aliases | `c_abi.validateImports`, `catalog.aliases` | Foreign declaration agreement and alias metadata with the same failure ordering. |
| Effects and origins | `effects.check`, `origins.check`, `value_semantics_check.checkWrites` | Complete inferred effects, call-graph propagation, mutation/return-origin summaries, declared bounds, overlap and dead-copy-write diagnostics; compare facts as well as accepted/rejected programs. |
| Domain codecs | `domain_codecs.check` | Codec contract resolution, data-type admissibility, signatures and ordered diagnostics after body/effect checking. |
| Binding/import diagnostics | `sema.warnBindings`, import-use recovery, `sema.warnImports`, `normalizeDiagnostics` | Exact severity, ordering, spans, related locations and structured repairs. An unused capability is an error, not an ordinary unused-binding warning. |
| Removal repairs | `arena_fix.reject` in `sema.checkCore` | Preserve available migration repairs even when an unrelated body fails. |
| Incremental semantic retention | Symbolic/specialization sessions, `sema_summaries.Plan`, semantic cache publication | Identical cold/warm/edit behavior, invalidation and replayed diagnostics; authenticated implementation identities must participate in reuse. |

## Constraints on the next implementation wave

The current selected-body path sets `cache` to null in `sema.checkProgram`.
Reference mode alone can reuse native body/specialization results and summary
stand-ins. Therefore a body implementation with exact cold results has not yet
established the incremental behavior or compile/test performance required by the
full goal. Port the algorithms and reuse contracts; do not enable native summary
replay as a substitute for Selka ownership.

Effects/origins require the complete checked program, source and syntax mapping,
exported-function flags, and (when reuse is enabled) explicit summary stand-ins.
They update inferred function-signature facts and produce ordered diagnostics.
The nine effect categories in `effect_set.zig` include managed allocation and
mutation as well as capability effects. Resource cleanup, callbacks and
transitive calls contribute; scanning only direct file/stream operations would
not implement the pass. Contract purity checks also belong to this stage.

Keep body coverage and common semantic ownership separately accountable while
implementing them against the native oracle. Preserve validation and diagnostic
ordering across their join. Tests must exercise selected execution, complete
metadata, successful and failing inputs, source repairs, and malformed replies;
an unchanged native post-pass cannot prove its Selka replacement.

The next backend boundary is documented in
[the typed-to-Core audit](selka-core-lowering-boundary-2026-10-11.md).
Lowering can be developed against fully checked input while semantic migration
continues, but full compiler bootstrap still requires every stage above, Core
transformations and LLVM emission, and the installed compiler driver. The pinned
external toolchain and C runtime may remain dependencies, as specified in
[the continued self-host plan](selka-incremental-selfhost-parallel-work-2026-10-10.md).
