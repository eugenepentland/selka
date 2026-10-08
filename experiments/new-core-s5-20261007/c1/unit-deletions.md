# S5-C1: unit tests deleted or trimmed while retargeting `src/native_execute.zig`

Classes (plan §4 S5-C): **1** the new core was wrong (fixed, never deleted); **2** the test asserts old
internals (the old file it asserted on is named); **3** the test asserts a retired feature (S5-D3..D6).
Every test listed failed on the new core, or (four tests: three in `native_execute.zig`, one in `qbe_rc_index_update_test.zig`) could only run
through the in-process QBE build `native_execute.program` that the retarget removed. Nothing was deleted for any other reason.

## Counts

| | Deleted | Trimmed |
|---|---|---|
| Class 2 | 29 | 3 |
| Class 3 | 29 | 2 |
| Total | 58 | 5 |

Per file (deleted):

| File | Class 2 | Class 3 |
|---|---|---|
| `src/arena_managed_test.zig` |  | 6 |
| `src/compiler_test.zig` | 2 | 1 |
| `src/cow_test.zig` | 1 |  |
| `src/environment_test.zig` | 5 |  |
| `src/external_capabilities_test.zig` | 4 |  |
| `src/integers_test.zig` | 1 |  |
| `src/invoke_test.zig` |  | 7 |
| `src/managed_cell_test.zig` |  | 2 |
| `src/managed_frontend_test.zig` |  | 2 |
| `src/managed_lists_test.zig` |  | 3 |
| `src/native_execute.zig` | 2 | 1 |
| `src/nominal_environment_test.zig` | 2 |  |
| `src/python_bytes_test.zig` |  | 1 |
| `src/python_core_test.zig` |  | 1 |
| `src/python_values_test.zig` |  | 1 |
| `src/qbe_build_test.zig` | 9 |  |
| `src/qbe_environment_names_test.zig` |  | 1 |
| `src/qbe_list_literal_test.zig` |  | 2 |
| `src/qbe_rc_index_update_test.zig` | 2 |  |
| `src/source_map_test.zig` | 1 |  |
| `src/stdlib_time_random_test.zig` |  | 1 |

`src/nominal_environment_test.zig` lost both its tests and was removed.

## Deleted

| File | Test | Class | Reason / old file |
|---|---|---|---|
| `src/qbe_rc_index_update_test.zig` | RC index update preserves actual counting and site reports with positive native oracles | 2 | asserts the `MYLANG_RC_COUNTS` counting/site report of an executable `native.program` published from QBE IL; old files: `src/native_rc_stats.c`, `src/qbe_build.zig` |
| `src/native_execute.zig` | an in-process guest build hands its tools a local cache inside its own scratch | 2 | asserts the old in-process QBE link's `ZIG_LOCAL_CACHE_DIR` (NATIVE-ZIG-CACHE-3, bullet deleted); old files: `src/wiring/native_session.zig`, `src/qbe_build.zig` |
| `src/native_execute.zig` | a published native executable carries neither debug information nor a symbol table | 2 | asserts the stripped executable `native.program` published from QBE IL (QBE-STRIP-1, carried on by `src/qbe_build_cache.zig`); old file: `src/qbe_build.zig` |
| `src/native_execute.zig` | an unstressed guest runs under the RC default and a stressed one under GC | 3 | GC stress (S5-D4) |
| `src/arena_managed_test.zig` | ARENA-MANAGED-11 the header barrier traps a younger store after the arena spans many chunks | 3 | arenas' escape semantics (S5-D3): asserts `R_ARENA_ESCAPE` barriers or `scratch.escape` region sharing; `with arena():` is now an ordinary block |
| `src/arena_managed_test.zig` | ARENA-MANAGED-2 escape preserves a cycle through a record field | 3 | arenas' escape semantics (S5-D3): asserts `R_ARENA_ESCAPE` barriers or `scratch.escape` region sharing; `with arena():` is now an ordinary block |
| `src/arena_managed_test.zig` | ARENA-MANAGED-2 escape shares objects that already live in the enclosing region | 3 | arenas' escape semantics (S5-D3): asserts `R_ARENA_ESCAPE` barriers or `scratch.escape` region sharing; `with arena():` is now an ordinary block |
| `src/arena_managed_test.zig` | ARENA-MANAGED-3 the store barrier covers dictionary values written through a helper | 3 | arenas' escape semantics (S5-D3): asserts `R_ARENA_ESCAPE` barriers or `scratch.escape` region sharing; `with arena():` is now an ordinary block |
| `src/arena_managed_test.zig` | ARENA-MANAGED-3 the store barrier traps when a helper stores arena storage outward | 3 | arenas' escape semantics (S5-D3): asserts `R_ARENA_ESCAPE` barriers or `scratch.escape` region sharing; `with arena():` is now an ordinary block |
| `src/arena_managed_test.zig` | TEXT-VIEW-2 a piece made inside an arena traps when a helper stores it outward, as a copy did | 3 | arenas' escape semantics (S5-D3): asserts `R_ARENA_ESCAPE` barriers or `scratch.escape` region sharing; `with arena():` is now an ordinary block |
| `src/python_bytes_test.zig` | PY-BYTES-4 byte strings are region allocated escaped and barrier checked under with arena | 3 | arenas' escape semantics (S5-D3): asserts `R_ARENA_ESCAPE` barriers or `scratch.escape` region sharing; `with arena():` is now an ordinary block |
| `src/qbe_list_literal_test.zig` | LIST-LITERAL-PAYLOAD-1 older image evaluations retain younger-store refusal | 3 | arenas' escape semantics (S5-D3): asserts `R_ARENA_ESCAPE` barriers or `scratch.escape` region sharing; `with arena():` is now an ordinary block |
| `src/compiler_test.zig` | a class field write mutates the receiver in place without copying it | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares |
| `src/managed_cell_test.zig` | Cell equality is rejected for membership search and nested containers | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares |
| `src/managed_cell_test.zig` | generic Cell construction is recognized and tracks allocation effects | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares |
| `src/managed_frontend_test.zig` | managed generic list creation mutation and copy identity preserve shared aliases | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares |
| `src/managed_frontend_test.zig` | managed nominal recursive list record edges allow finite reference graphs | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares |
| `src/managed_lists_test.zig` | legacy sharing: an unreachable managed cycle is reclaimed while a reachable one survives collection | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares; also asserts tracing-collector reclamation (GC, S5-D4) |
| `src/managed_lists_test.zig` | legacy sharing: managed cycles lose local and record roots on block break and continue exits | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares; also asserts collector roots (GC, S5-D4) |
| `src/managed_lists_test.zig` | legacy sharing: managed recursive record cycles are traced at a later managed allocation | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares; also asserts collector tracing (GC, S5-D4) |
| `src/python_core_test.zig` | a self-referential class graph prints to the depth cap and terminates | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares |
| `src/python_values_test.zig` | the collector traces every generated shape by the plan its descriptor carries | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares; its subject is the tracing collector's plans (GC, S5-D4) |
| `src/qbe_list_literal_test.zig` | LIST-LITERAL-PAYLOAD-1 legacy literal evaluations allocate distinct mutable lists | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares |
| `src/stdlib_time_random_test.zig` | standard time random legacy generator copies share one stream | 3 | legacy sharing (S5-D4): runs under `test_support.LegacySharing` with shared `class`/alias identity, which `mylang` refuses under value semantics (E_VALUE_CLASS/E_VALUE_CELL) or no longer shares |
| `src/invoke_test.zig` | a list round-trips through invoke at every shape the codec carries | 3 | `mylang invoke` (S5-D5): spawns the retired command |
| `src/invoke_test.zig` | a nested record argument executes through the copied-value adapter | 3 | `mylang invoke` (S5-D5): spawns the retired command |
| `src/invoke_test.zig` | an export that calls another function is lowered with its call closure | 3 | `mylang invoke` (S5-D5): spawns the retired command |
| `src/invoke_test.zig` | an undersized codec result buffer reports OutputTooSmall, not WireLimit | 3 | `mylang invoke` (S5-D5): spawns the retired command |
| `src/invoke_test.zig` | a record holding a text or a list composes with Option and Result | 3 | `mylang invoke` (S5-D5): spawns the retired command |
| `src/invoke_test.zig` | a text argument and result round-trip through invoke with an embedded NUL preserved | 3 | `mylang invoke` (S5-D5): spawns the retired command |
| `src/invoke_test.zig` | invariant boundary validates nested records through ordinary and codec wire entries | 3 | `mylang invoke` (S5-D5): spawns the retired command |
| `src/qbe_environment_names_test.zig` | QBE Environment names come from grants rather than the linked provider context | 3 | `build --provider` (S5-D5): links a host provider context |
| `src/qbe_build_test.zig` | a batched build and an unbatched build of one program behave identically | 2 | spawns the old CLI for the per-module QBE build, `emit-project-qbe`/`emit-runtime`, the old build `--report`, the old `runtime` cache tree or `MYLANG_RC_COUNTS` RC-stats builds; old files: `src/qbe_build.zig`, `src/qbe_build_cache.zig`, `src/native_rc_stats.c` |
| `src/qbe_build_test.zig` | a default build shares its runtime tree under XDG while an explicit cache-dir stays hermetic | 2 | spawns the old CLI for the per-module QBE build, `emit-project-qbe`/`emit-runtime`, the old build `--report`, the old `runtime` cache tree or `MYLANG_RC_COUNTS` RC-stats builds; old files: `src/qbe_build.zig`, `src/qbe_build_cache.zig`, `src/native_rc_stats.c` |
| `src/qbe_build_test.zig` | a prebuilt runtime installed beside the compiler links directly, and damage falls back to source | 2 | spawns the old CLI for the per-module QBE build, `emit-project-qbe`/`emit-runtime`, the old build `--report`, the old `runtime` cache tree or `MYLANG_RC_COUNTS` RC-stats builds; old files: `src/qbe_build.zig`, `src/qbe_build_cache.zig`, `src/native_rc_stats.c` |
| `src/qbe_build_test.zig` | native RC argv owner balances borrowed entry returns capability refusal and traps | 2 | spawns the old CLI for the per-module QBE build, `emit-project-qbe`/`emit-runtime`, the old build `--report`, the old `runtime` cache tree or `MYLANG_RC_COUNTS` RC-stats builds; old files: `src/qbe_build.zig`, `src/qbe_build_cache.zig`, `src/native_rc_stats.c` |
| `src/qbe_build_test.zig` | native RC closed field owner balances storeback snapshot traps and arena refusal | 2 | spawns the old CLI for the per-module QBE build, `emit-project-qbe`/`emit-runtime`, the old build `--report`, the old `runtime` cache tree or `MYLANG_RC_COUNTS` RC-stats builds; old files: `src/qbe_build.zig`, `src/qbe_build_cache.zig`, `src/native_rc_stats.c` |
| `src/qbe_build_test.zig` | native RC record field transfers balance owned and caller traps, arenas and budgets | 2 | spawns the old CLI for the per-module QBE build, `emit-project-qbe`/`emit-runtime`, the old build `--report`, the old `runtime` cache tree or `MYLANG_RC_COUNTS` RC-stats builds; old files: `src/qbe_build.zig`, `src/qbe_build_cache.zig`, `src/native_rc_stats.c` |
| `src/qbe_build_test.zig` | native RC sites build attributes every counted event to a source site | 2 | spawns the old CLI for the per-module QBE build, `emit-project-qbe`/`emit-runtime`, the old build `--report`, the old `runtime` cache tree or `MYLANG_RC_COUNTS` RC-stats builds; old files: `src/qbe_build.zig`, `src/qbe_build_cache.zig`, `src/native_rc_stats.c` |
| `src/qbe_build_test.zig` | optional registration images link and run through direct and frame-map full and ThinLTO | 2 | spawns the old CLI for the per-module QBE build, `emit-project-qbe`/`emit-runtime`, the old build `--report`, the old `runtime` cache tree or `MYLANG_RC_COUNTS` RC-stats builds; old files: `src/qbe_build.zig`, `src/qbe_build_cache.zig`, `src/native_rc_stats.c` |
| `src/qbe_build_test.zig` | RC field inout unaccounted native owner and hold balances survive traps arenas and budgets | 2 | spawns the old CLI for the per-module QBE build, `emit-project-qbe`/`emit-runtime`, the old build `--report`, the old `runtime` cache tree or `MYLANG_RC_COUNTS` RC-stats builds; old files: `src/qbe_build.zig`, `src/qbe_build_cache.zig`, `src/native_rc_stats.c` |
| `src/compiler_test.zig` | frame limits count main and guest recursion never consumes the host call stack | 2 | asserts the old runtime's budget protocol: a zero frame budget answered as the trap `InvalidBudget` and sixteen reported frames of twenty thousand; the new core refuses a zero budget as a usage error and charges frames per NEW-CORE-S4-FRAMES-1; old files: `src/runtime_options.zig`, `src/qbe_runtime.c` |
| `src/compiler_test.zig` | instruction limit is checked before the next dispatch | 2 | asserts per-dispatch step counts (`return 1` exhausts one step) and `InvalidBudget`; the new core charges one step per block (NEW-CORE-S4-STEPS-1) and refuses a zero budget as usage; old files: `src/qbe.zig` step accounting, `src/runtime_options.zig` |
| `src/integers_test.zig` | scalar loop retains exact step budget and located trap under the native runtime | 2 | asserts the exact per-dispatch step count (1309/1310) and a located `R_STEP_LIMIT`; old file: `src/qbe.zig` step accounting |
| `src/cow_test.zig` | copy on write: a counting build counts every inline check, mark and pin and reports at exit | 2 | asserts the `--gc-runtime` copy-on-write counting report at exit; old file: `src/native_cow.c` |
| `src/source_map_test.zig` | mapped source locations survive parser checking lowering and native traces with all allocation failures | 2 | runs an in-memory `Source.initMapped` merge, which has no files to build, and asserts its bytecode dump; old files: `src/lower.zig`, `src/disassemble.zig`, `src/qbe.zig` debug locations |
| `src/qbe_rc_index_update_test.zig` | RC index update leaves COW allocation refusal and prior output at the original operation | 2 | asserts `R_MEMORY_BUDGET` located at the copy-on-write detach the old RC index-update lowering performed; the new core reports a budget trap without a location (NEW-CORE-S4-MEMORY-1); old files: `src/qbe_rc_index_update.zig`, `src/native_heap.c` |
| `src/environment_test.zig` | environment grants delegate explicitly and missing empty and present values remain distinct | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |
| `src/environment_test.zig` | environment reads outside an explicit allowlist are denied before the host is asked | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |
| `src/environment_test.zig` | environment returns raw bytes and canonical zero padding | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |
| `src/environment_test.zig` | generic environment lookup preserves bounded bytes and callback allocation failures | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |
| `src/environment_test.zig` | zero capacity environment values distinguish absent empty and too large | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |
| `src/nominal_environment_test.zig` | nominal environment distinguishes absent empty oversize and denied host values | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |
| `src/nominal_environment_test.zig` | nominal environment wrappers preserve binary bytes and zero unspecified padding | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |
| `src/external_capabilities_test.zig` | clock reads advance monotonically while a short circuited operand never reads | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |
| `src/external_capabilities_test.zig` | external entry grants forward through wrappers and preserve full width samples | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |
| `src/external_capabilities_test.zig` | generic provider reads preserve values callback counts and allocation cleanup | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |
| `src/external_capabilities_test.zig` | repeated provider reads keep the guest inside one frame | 2 | asserts the front end's compiler-internal raw provider intrinsics (`clock_now[...]`, `random_u64[...]`, `environment_get[...]`), which only trusted in-process source (`Compilation.initTrusted`) may spell; `mylang` builds user source only (E_INTERNAL_NAME), and the public `time`/`random`/`env.get` surface keeps its tests; old file: `src/compiler.zig` trusted-intrinsic hook through `src/qbe.zig` emission |

## Trimmed (the failing part removed, the rest kept)

| File | Test | Class of the removed part | What changed |
|---|---|---|---|
| `src/python_collections_test.zig` | iteration detects alias growth including continue and final step → kept as "iteration break exits a grown list without another iteration check" | 3 | the two legacy-alias loops (S5-D4 legacy sharing) were removed; the break case stays, and PY-COLLECTIONS-8 drops its "or a legacy alias" clause |
| `src/external_capabilities_test.zig` | every grant an entry point names is materialized before its body runs | 2 | its withheld-grant program was the trusted raw-intrinsic source; replaced by an ordinary program naming the same Entropy and Clock grants (same assertions) |
| `src/external_capabilities_test.zig` | clock and random bounds propagate through calls independently of noio and noalloc | 2 | the native run of a trusted raw-intrinsic program was replaced by `emit()`, which the old bytecode-validator assertion after it needs; the effect-bound rejections stay |
| `src/qbe_rc_native_variant_test.zig` | RC-NATIVE-VARIANT-1 actual native snapshots retained loans mutations and error tags survive | 2 | its `MYLANG_RC_COUNTS` counting-runtime run (`src/native_rc_stats.c`) and its GC run (S5-D4) were removed; the RC run stays |
| `src/io_print_test.zig` | IO-2 print renders records, enums, unions and checked results by name | 3 | its `class Point` fixture under legacy sharing (S5-D4) became `record Point`; the rendering assertions are unchanged |

## Class 1 (new core wrong; fixed, nothing deleted)

| Tests | What was wrong | Fix |
|---|---|---|
| native_execute (QBE-TRAP-DETAIL-1 bounds detail) | a negative list or fixed-array index past the start reported the normalized index (`-3`) instead of the written one (`-5`) | `src/core/emit_llvm.zig` (`countsFromEnd`/`originalIndex`), `src/core/emit_fn.zig`; NEW-CORE-S5-NEGATIVE-INDEX-1 |
| native_execute (TRAP-UNSIGNED-1) | unsigned overflow, division and cast traps printed their operands signed and their record had no `"unsigned":true` | `src/core/emit_llvm.zig` (`unsigned_site` bit in the site width), `src/core/runtime/core_rt.c` (`MYL_CORE_SITE_UNSIGNED`) |
| io_print (STREAM-CAPABILITY, STREAM-BYTES-1, QBE-BULK-TEXT-1, IO-15, STREAM-BYTES-2) | `stream.write` was void in the Core IR, so a helper returning its count failed `E_CORE_INVALID_IR` | `src/core/build_cap.zig`; NEW-CORE-S5-STREAM-WRITE-1 |
| io_print (STREAM-BYTES traps R_OUTPUT) | a refused write to standard output was dropped and the program exited with `main`'s status | `src/core/runtime/core_rt.c` (`output_refused`) |
| embed_test (4) | `mylang build`/`run` of a header-less file never read its `embed_bytes`/`embed_str` files (`E_EMBED_UNAVAILABLE`) | `src/core/frontend.zig` (`attachEmbeds`); NEW-CORE-S5-EMBED-1 |
| compiler_test long expressions, qbe_list_literal thousand elements | a block after many checks got a label made of every earlier label, which LLVM refuses as too long | `src/core/emit_llvm.zig` (`freshBase`); NEW-CORE-S5-LABELS-1 |
| contracts_test (CONTRACT-REQUIRES) | a broken precondition did not name the caller that broke it | `src/core/runtime/core_rt.c` (`frame_capture`); NEW-CORE-S5-CONTRACT-1 |
| error_trace_test (runtime Err) | an `Err` a runtime operation answered (file read, capability result, UTF-8 decode) started the trace as `Err(...) created` | `src/core/build_cap.zig`, `src/core/build_text_more.zig` (trace mode `runtime`) |

## SPEC bullets

Deleted with their last test: ARENA-MANAGED-3, PY-BYTES-4, CLASS-WRITE-1, CELL-EQUALITY-1,
CELL-GENERIC-1, GC-GENERIC-1, GC-GENERIC-2, GC-CYCLES-1, GC-SOURCE-11, GC-SOURCE-2, CLASS-MANAGED-1,
INVOKE-11, QBE-TEXT-4, INVOKE-TEXT-1, QBE-BATCH-2, VM-AUDIT-1, OWN-10, GENERIC-PROVIDER-EXEC-1,
NATIVE-ZIG-CACHE-3.

Primary tag moved to a remaining `spec-case`: GC-SCAN-PLAN-2 (`src/native_descriptors.zig`), INVOKE-9
(`src/invoke_test.zig`), CONTRACT-DECODE-1 (`test/integration.zig`, an `invoke` CLI test S5-A listed as
class 3: the CLI lane deletes it with this bullet), COW-STATS-1 (`src/value_semantics_test.zig`),
QBE-STRIP-1 (`src/qbe_build_cache.zig`).

Edited: PY-COLLECTIONS-8 drops "or a legacy alias"; NEW-CORE-S5-CONTRACT-1 adds the caller.
Added: NEW-CORE-S5-UNITS-1, NEW-CORE-S5-NEGATIVE-INDEX-1, NEW-CORE-S5-STREAM-WRITE-1,
NEW-CORE-S5-EMBED-1, NEW-CORE-S5-LABELS-1.

## Counts before and after (`zig build test-units-sharded -Dtest-shards=6`, same root)

| Run | Tests | Passed | Failed |
|---|---|---|---|
| S5-A merge, old runner | 2639 | 2622 | 17 |
| retargeted runner, before any fix (`units-01`) | 2636 | 2560 | 76 (one crashed) |
| after the class 1 fixes and the deletions (`units-03`) | 2584 | 2583 | 1 (`stand_ins`, the runner's environment; fixed after) |
| gate: `zig build test-units` at 251a03f9 (one process, test wall 420 s) | 2584 | 2584 | 0 |

Qualification at 251a03f9: `qualify-01` (test-core 421/421 in 64 shards, conformance 1518/0/0 debug and
release with leak and verify, against `references/conformance-v1.json`); `fuzz50-01` (frozen fuzz, 9 kinds x 50,
0 mismatches).
