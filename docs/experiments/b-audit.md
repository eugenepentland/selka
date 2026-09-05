# B acceptance audit

B's roadmap contract is shared/exclusive references and slices with deliberately
restricted lifetimes, sufficient to express common helpers and reject invalid
accesses with understandable errors. The implementation now covers that contract
and explicit returned-reference provenance. This completes B; it does not complete
C/D ownership, recoverable errors, effects, resource-backed arenas, or other tracks.

| Requirement | Implementation | Evidence |
| --- | --- | --- |
| Allocation identity, bounds, and lifetime metadata | [memory.zig](../../src/memory.zig): store identities, generation-checked allocation/lease registries, bounded views | [memory_test.zig](../../src/memory_test.zig): stale/reused/foreign/closed handles, bounds, permission conflicts, exhaustion, and rollback |
| Shared/exclusive source references | Parser, [sema.zig](../../src/sema.zig), typed reference metadata, and VM cell promotion | [references_test.zig](../../src/references_test.zig): owner access, alias conflicts, reborrowing/suspension, scope escape, snapshots, and loop reuse |
| Common read/mutate helpers | `&T`/`&mut T` parameters and temporary call reborrows | Reference parameter tests: mixed arguments, distinct owners, shared fan-out, recursive forwarding, and restored caller access |
| Bounded slices and narrowing | [slices.md](slices.md), slice metadata and operations in [vm.zig](../../src/vm.zig) | [slices_test.zig](../../src/slices_test.zig): empty and narrowed views, signed/unsigned bounds, element identity, recursive helpers, and snapshot preservation |
| Returned references with restricted lifetimes | [returned-references.md](returned-references.md): explicit `from` input, checked result scopes, capture/cleanup/reborrow protocol | [returned_references_test.zig](../../src/returned_references_test.zig): local/copy escape and wrong input rejected; scalar/narrowed results survive forwarding and restore input access |
| Cleanup and bounded storage | Iterative frames, owned values, reusable registries, child-before-parent lease cleanup | Allocation-failure sweeps; all instruction trap boundaries for nested aggregate/reference/slice/return programs; 10,000-cycle tests with bounded live allocation |
| Source diagnostics and CLI behavior | Source spans, related declarations, disassembly, and separate guest traps | [integration.zig](../../tests/integration.zig): actual selected-mode CLI checks, successful programs, alias/escape diagnostics, bounds traps, and borrow/return instructions |
| Duplicate identity stays meaningful | [duplicates.zig](../../src/duplicates.zig), `exact-v11` canonical form | Reference/slice/return tests normalize bound names while preserving origins, permissions, ranges, and call argument identities |

Verification: `zig build test --summary all` and
`zig build test -Doptimize=ReleaseFast --summary all` each pass 176/176 tests;
`zig build fmt-check --summary all` and `git diff --check` pass. These are local
runs using Guardian's exact pinned Zig snapshot. Hosted CI has not run. Guardian's
own gate was not exercised.

The implemented restriction is lexical reference scopes, whole-local storage,
explicit slice views, and one declared input origin per returned reference. There
is no pointer arithmetic, arbitrary reference storage, implicit lifetime inference,
or unsafe escape hatch. Slice writes currently copy immediate array elements to
preserve value snapshots. The test evidence validates this implemented prototype;
it is not a formal soundness proof for future ownership or unsafe features.
