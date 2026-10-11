# Current typed-to-Core ownership boundary

Read-only audit of committed text base f5628d73f on 2026-10-11. No backend build or source edits performed.

Native entry points are src/core/build.zig buildModule (49), buildRoots (56), buildExecutable (73), and buildRootsCached (93). src/core/pipeline.zig:196 selects buildExecutable versus buildExecutableCached. src/core/main.zig:107 uses buildModuleSource for dump-ir; cost_command.zig:88 and allocation_contract.zig:82 use the same native builder. Current selfhost lower helpers produce typed body graphs, not Core SSA.

Core ir.zig uses instruction Ref and block indices, predecessor-ordered PHIs, immutable value updates, compounds, capabilities and resources. build.zig constructs Braun sealed SSA and reachable roots. ir_snapshot.zig provides owned Function (insts, blocks/preds, extra, loops, signature) plus Wire strings and relocatable locations; capture151, restore205, digest243. Declaration layout guards ordinals. lowering_cache captures exact module table deltas and deferred discovery; stage_pack persists compressed cache journals, not an external component protocol.

Historical f047daa0f selfhost/lower.my, ir.my, emit.my walk old syntax/check.ProjectCheck and emit QBE with myl_qbe_int ABI, cells and frozen aggregate layouts. Semantic cases and evaluation-order tests remain useful. That donor is reference-only for current typed-to-Core and LLVM.

First port prerequisites: freeze current typed input and Core snapshot/module delta DTO with ownership, source relocation, embedded assets and root/function identities; define authenticated external lowering schema and materializer; validate CFG, SSA refs, PHI predecessor order, type/compound/layout authority with verify_ir and exact forged refusals; port per-function current build_fn/build sealed SSA against uncached native differential; expand all primitive, compound, resource and call operations; preserve lowering-cache/deferred demands. Native Core snapshot plus exact module deltas is the initial contract. No second implementation begins before text integration.
