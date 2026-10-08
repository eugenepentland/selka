# S5-C2: CLI tests deleted, trimmed and retargeted

Lane S5-C2 on `claude/s5-c2`, from S5-A's classification (`../a/cli-failures.md`). Class 2 asserts old internals; class 3 a retired feature (S5-D3..D6). Nothing was deleted for any other reason.

## Counts

| | Tests |
|---|---|
| Deleted, class 2 | 48 (43 in `test/integration.zig`, 5 in `test/native_variant_policy.zig`, file deleted) |
| Deleted, class 3 | 37 (27 in `test/integration.zig`, 1 in `test/fix_cli_test.zig`, 9 in `test/rc_teardown_test.zig`, file deleted) |
| Deleted, total | 85 |
| Trimmed (retired or old-internal steps removed, the rest kept) | 39 tests in 24 rows below |
| Retargeted from QBE/LLVM backend variants to the new core's debug and `--release` builds | 4 |

Per file: `test/integration.zig` 70 deleted; `test/fix_cli_test.zig` 1 (class 3); `test/native_variant_policy.zig` 5 (class 2, file deleted); `test/rc_teardown_test.zig` 9 (class 3, file deleted). Helpers only those tests used were deleted with them, and the fixtures `test/fixtures/arithmetic.dump` and `test/fixtures/warnings.dump`.

## Class 2 deleted (old internals)

| Test | File | What it asserted | Old file | Tags |
|---|---|---|---|---|
| CLI project run reuses emitted manifest while no-cache and grants stay authoritative | `test/integration.zig` | `run-project --report`: the old work report and emitted-manifest reuse | src/invalidation.zig | spec-case: NATIVE-RUN-MANIFEST-CACHE-1 |
| modules compiled one by one from their imports' interfaces link into the program the build makes | `test/integration.zig` | `emit-project-qbe` and per-module QBE compiles | src/qbe_build.zig | spec-case: MODULE-COMPILE-1 |
| a project build compiles a module again only when its source or an interface it read changed | `test/integration.zig` | `module_build` counts in the old `--report` | src/module_build.zig | spec: MODULE-SCHEDULE-1 |
| a body edit no dependent reaches compiles its own module alone and links the whole-program executable | `test/integration.zig` | `module_build` counts in the old build `--report` | src/module_build.zig | spec-case: MODULE-SYMBOL-CUTOFF-2, spec: MODULE-SYMBOL-CUTOFF-5, spec: MODULE-SYMBOL-CUTOFF-4, spec: MODULE-SYMBOL-CUTOFF-3 |
| a signature change no reader uses compiles its own module alone and links the whole-program executable | `test/integration.zig` | `module_build` counts in the old build `--report` | src/module_build.zig | spec: MODULE-INTERFACE-CUTOFF-3 |
| a rename behind a dotted import path compiles and checks its caller again | `test/integration.zig` | `module_build` counts in the old build `--report` | src/module_build.zig | spec: MODULE-INTERFACE-CUTOFF-4 |
| a module-built program links from its modules' records into the whole-program build's executable | `test/integration.zig` | `module_build` counts in the old `--report` | src/module_build.zig | spec: MODULE-SCHEDULE-2 |
| run builds a project module by module, and a program the modules cannot build goes to the whole-program path | `test/integration.zig` | the old per-module records directory `cache/modules` | src/module_build.zig | spec: MODULE-SCHEDULE-3 |
| a project whose modules declare copied host functions builds module by module into the whole-program executable | `test/integration.zig` | `module_build` counts (and host functions) | src/module_build.zig | spec: MODULE-HOST-1 |
| a record whose layout changed behind a callee's body compiles a dependent that never names it | `test/integration.zig` | `module_build` counts | src/module_build.zig | spec: MODULE-EMISSION-RECORDS-1 |
| a project with a mylang.json builds module by module, and what its configuration rejects is reported as the whole-program build reports it | `test/integration.zig` | `module_build` counts | src/module_build.zig | spec: MODULE-PROJECT-1 |
| check of a project re-checks only the modules whose source or read interfaces changed, and prints what the whole-program check prints | `test/integration.zig` | the per-module check's record counts (MODULE-CHECK-1, removed by NEW-CORE-S5-CHECK-1) | src/module_build.zig | spec: MODULE-CHECK-1 |
| standard trigonometry checks through module interfaces and unchanged generic callers reuse their state | `test/integration.zig` | the per-module check records (MODULE-CHECK-1) | src/module_build.zig | spec: STANDARD-MATH-TRIG-GENERIC-1, spec-case: MODULE-CHECK-1, spec-case: STANDARD-MATH-TRIG-1 |
| a large project's first check is the whole-program check, and module records seeded after it answer the next | `test/integration.zig` | the detached module-record seeder (MODULE-CHECK-2) | src/module_seeder.zig | spec: MODULE-CHECK-2 |
| a module compile builds its units and objects at a lower priority once its interface is published | `test/integration.zig` | `module_build` report | src/module_build.zig | spec: MODULE-SCHEDULE-6 |
| a standard module is compiled once per cache and compiler for every program that imports it | `test/integration.zig` | `module_build` report | src/module_build.zig | spec: MODULE-SCHEDULE-4 |
| CLI dumps actual instructions | `test/integration.zig` | `dump-bytecode` | src/bytecode_model.zig |  |
| CLI build report states the default and explicit optimize modes | `test/integration.zig` | the old build `--report` | src/qbe_build.zig | spec-case: BUILD-MODE-1 |
| CLI build uses QBE when no backend is named and --release builds LLVM O3 with LTO | `test/integration.zig` | the old backend receipt | src/qbe_build_receipt.zig | spec-case: BUILD-RELEASE-1 |
| CLI default build keeps the shared metadata object when a function is added and its trap still names every frame | `test/integration.zig` | the old QBE metadata object and receipt | src/qbe_build.zig | spec-case: QBE-FRAMEMAP-ROOTS-1 |
| mylang test stages under TMPDIR, never under /tmp, and removes its staging after a passing run | `test/integration.zig` | the old runner's `.pending` staging and `MYLANG_TEST_TRACE` | src/native_test_snapshot.zig | spec: NATIVE-SCRATCH-ROOT-2 |
| mylang test leaves no staging behind when the project is rejected before any test builds | `test/integration.zig` | the old runner's `.pending` staging under TMPDIR and `MYLANG_TEST_TRACE` | src/native_test_snapshot.zig | spec-case: NATIVE-SCRATCH-ROOT-2 |
| mylang test with TMPDIR unset falls back to staging under /tmp | `test/integration.zig` | the old runner's `.pending` staging under TMPDIR and `MYLANG_TEST_TRACE` | src/native_test_snapshot.zig | spec-case: NATIVE-SCRATCH-ROOT-2 |
| mylang test reclaims a killed run's marked staging and keeps unmarked scratch | `test/integration.zig` | the old runner's `.pending` staging under TMPDIR and `MYLANG_TEST_TRACE` | src/native_test_snapshot.zig | spec-case: NATIVE-SCRATCH-OWNER-1 |
| CLI invalidation reports actual query work and marks unexecuted stages skipped | `test/integration.zig` | `--explain-invalidation` lower/emit/link stages | src/invalidation.zig | spec: INVALIDATION-EXECUTION-1 |
| C4 unchanged deterministic rerun executes zero tests without lowering emission or linking | `test/integration.zig` | the old runner's `--report` work counts and `MYLANG_TEST_TRACE` | src/native_test_command.zig | spec: NATIVE-TEST-6, spec-case: NATIVE-TEST-5 |
| C4 helper edit reruns only the dependent test and lower only on an uncached selection | `test/integration.zig` | the old runner's `--report` work counts and `MYLANG_TEST_TRACE` | src/native_test_command.zig | spec-case: NATIVE-TEST-5 |
| C4 invalid selected project fails before any green result | `test/integration.zig` | the old runner's `--report` work counts and `MYLANG_TEST_TRACE` | src/native_test_command.zig | spec-case: NATIVE-TEST-5 |
| C4 expectation argument budget and force invalidate while irrelevant environment preserves receipts | `test/integration.zig` | the old runner's `--report` work counts and `MYLANG_TEST_TRACE` | src/native_test_command.zig | spec-case: NATIVE-TEST-12, spec-case: NATIVE-TEST-5 |
| C4 two providers with reversed map order prepare one graph and one library | `test/integration.zig` | the old runner's `--report` work counts and `MYLANG_TEST_TRACE` | src/native_test_command.zig | spec-case: NATIVE-TEST-5 |
| C4 no-cache performs fresh runs without durable result or graph entries | `test/integration.zig` | the old runner's `--report` work counts and `MYLANG_TEST_TRACE` | src/native_test_command.zig | spec-case: NATIVE-TEST-5 |
| a large project's first test run is the whole-program run, and a seeder's module records and that run's verdicts answer the next | `test/integration.zig` | the old JSON report's `executed` and the module-record seeder (harness panics on the missing field) | src/module_seeder.zig | spec: MODULE-TEST-5 |
| a test run started while a seeder holds the project's snapshot path does not wait for it and reports the verdicts the receipts hold | `test/integration.zig` | the old JSON report's `executed` and the module-record seeder | src/module_seeder.zig | spec: MODULE-TEST-6 |
| module by module, a body edit in module k compiles no module below k and re-runs exactly the tests that depend on it | `test/integration.zig` | the old JSON report's `executed` and module records | src/native_test_command.zig | spec: MODULE-TEST-4, spec: MODULE-TEST-1, spec: NATIVE-TEST-SCALE-1 |
| after a body edit in module k exactly the tests that depend on k are rebuilt and re-run, and an unchanged rerun only replays a verdict | `test/integration.zig` | the old runner's `--report` counts | src/native_test_command.zig | spec: NATIVE-TEST-SUMMARY-1, spec-case: NATIVE-TEST-RUNNER-1, spec-case: NATIVE-TEST-INTERFACES-1, spec-case: NATIVE-TEST-STABLE-1, spec: NATIVE-TEST-FACTS-2, spec-case: NATIVE-TEST-SCALE-1 |
| an edit that makes dependent tests trap reports the edited line, re-runs the failures, and a filter still selects one test | `test/integration.zig` | the old runner's `executed` count (`c4Counts`) | src/native_test_command.zig | spec-case: NATIVE-TEST-PARALLEL-1, spec-case: NATIVE-TEST-SCALE-1 |
| an incremental build after body, signature and interface edits builds the program a clean build builds | `test/integration.zig` | the old build `--report` objects | src/qbe_build.zig | spec-case: QBE-FRAGMENT-REUSE-1 |
| a relink of reused objects keeps an identical executable, and a link over compiled ones replaces it unread | `test/integration.zig` | the old build `--report` objects and `program.qbe-manifest.json` | src/qbe_build_link.zig | spec: BUILD-PUBLISH-1 |
| a ReleaseFast project build drops debug lines and a Debug one keeps them | `test/integration.zig` | `--backend qbe` | src/qbe_build_options.zig | spec-case: DEBUG-LINE-1 |
| the first link records how zig cc links and every later link runs the linker directly | `test/integration.zig` | the old link route in `--report` | src/qbe_build_link.zig | spec-case: BUILD-LINK-1 |
| an unchanged build keeps its executable without rebuilding and a replaced one is rebuilt | `test/integration.zig` | the old build `--report` | src/qbe_build.zig | spec-case: BUILD-NOOP-1 |
| an edit to only an embedded file rebuilds the module that embeds it and nothing else | `test/integration.zig` | the old build `--report` | src/qbe_build.zig | spec-case: EMBED-3 |
| a whole-program build sees an embedded file's edit and an unchanged build is skipped | `test/integration.zig` | the old build `--report` | src/qbe_build.zig | spec-case: EMBED-3 |
| NATIVE-SCALAR-BACKEND-1 alternating emission partitions lean replay and selective units | `test/native_variant_policy.zig` (file deleted) | `emit-project-qbe --native-scalars` | src/qbe_build.zig | NATIVE-SCALAR-BACKEND-1 |
| RC-NATIVE-VARIANT-BACKEND-1 alternating emission policies cannot reuse another policy's units | `test/native_variant_policy.zig` | `emit-project-qbe --rc-runtime` | src/qbe_build.zig | RC-NATIVE-VARIANT-BACKEND-1 |
| RC-NATIVE-VARIANT-BACKEND-1 selective emission carries policy and rejects malformed internal flags | `test/native_variant_policy.zig` | `emit-project-qbe --rc-runtime` | src/qbe_build.zig | RC-NATIVE-VARIANT-BACKEND-1 |
| RC-NATIVE-VARIANT-BACKEND-1 selective emission retains original counting and check defaults | `test/native_variant_policy.zig` | `emit-project-qbe --rc-runtime` | src/qbe_build.zig | RC-NATIVE-VARIANT-BACKEND-1 |
| NATIVE-SCALAR-BACKEND-1 rejects unknown duplicate and public-command flags | `test/native_variant_policy.zig` | passed only vacuously: `emit-project-qbe` is now a usage error, so its `--native-scalars` checks test nothing | src/qbe_build.zig | NATIVE-SCALAR-BACKEND-1 |

## Class 3 deleted (retired features)

| Test | File | Retirement | Tags |
|---|---|---|---|
| CLI test renders a test entry that does not compile as diagnostic-v1 JSON | `test/fix_cli_test.zig` | `test --diagnostics=json` (S5-D6) | spec: NATIVE-TEST-DIAGNOSTICS-1 |
| fix command previews then stores back a local alias and preserves both modes | `test/integration.zig` | `--legacy-sharing` | spec: FIX-MIGRATION-1 |
| checker warns at a local collection alias that is written and observed | `test/integration.zig` | `--legacy-sharing` (`W_ALIAS_DEPENDENT`) | spec: ALIAS-MIGRATION-1 |
| checker traces a narrowed match payload back to its collection binding | `test/integration.zig` | same | spec: ALIAS-MIGRATION-2 |
| checker terminates on a cyclic alias chain and reports the observed write | `test/integration.zig` | same | spec: ALIAS-MIGRATION-4 |
| recursive type branches terminate and preserve class-graph warnings | `test/integration.zig` | same | spec: ALIAS-MIGRATION-5 |
| checker distinguishes a nested alias store from a fresh buffer conversion | `test/integration.zig` | same | spec: ALIAS-MIGRATION-3 |
| CLI runs the managed arena example under normal and stress collection | `test/integration.zig` | `--gc-stress` | spec-case: ARENA-MANAGED-1 |
| the per-module commands are listed in help and answer a bad invocation with their usage | `test/integration.zig` | `compile-module` (retired) | spec: MODULE-COMPILE-4 |
| a module compile run for the scheduler announces its interface on stderr | `test/integration.zig` | `compile-module` | spec-case: MODULE-SCHEDULE-5 |
| PURE-SKIP-1 pure failure outcome replays without executing and is never masked | `test/integration.zig` | `--pure-skip` (S5-D6) | spec: PURE-SKIP-1 |
| PURE-SKIP-1 a changed dependency invalidates the recorded pure outcome | `test/integration.zig` | `--pure-skip` | spec-case: PURE-SKIP-1 |
| PURE-SKIP-1 no-cache and force disable pure outcome replay | `test/integration.zig` | `--pure-skip` | spec-case: PURE-SKIP-1 |
| guest benchmarks write a candidate and enforce an approved baseline immutably | `test/integration.zig` | `--bench*` (S5-D6) | spec-case: NATIVE-BENCH-3 |
| a wrong benchmark result or trap fails the run and reports no measurement | `test/integration.zig` | `--bench*` | spec-case: NATIVE-BENCH-2 |
| a directory benchmark run measures sequentially and stays green without tests | `test/integration.zig` | `--bench*` | spec-case: NATIVE-BENCH-6 |
| CLI check --explain-ownership writes one JSON line per function | `test/integration.zig` | `--explain-ownership` (old ownership lowering) | spec: OWNERSHIP-EXPLAIN-1 |
| CLI project ownership explanation includes imported accessor borrow origin | `test/integration.zig` | `--explain-ownership` | spec-case: RETURN-BORROW-1 |
| CLI legacy opt out cannot reuse default value test results | `test/integration.zig` | `--legacy-sharing` | spec-case: VALUE-SEMANTICS-1 |
| CLI explicit semantic mode wins over the inherited mode and project opt out | `test/integration.zig` | `--value-semantics`/`--legacy-sharing` modes | spec-case: VALUE-SEMANTICS-1 |
| CLI value semantics defaults on and legacy sharing is an explicit opt out | `test/integration.zig` | same | spec-case: VALUE-SEMANTICS-1 |
| CLI mylang.json value_semantics opts out and a default build carries values to the frontend | `test/integration.zig` | `value_semantics: false` (the new core requires value semantics) | spec-case: VALUE-SEMANTICS-1 |
| CLI project opt out uses the entry after valued options and for test directories | `test/integration.zig` | same | spec: VALUE-SEMANTICS-12 |
| CLI invariant boundary rejects invalid JSON collection elements before the body | `test/integration.zig` | `invoke` (S5-D5) | spec-case: CONTRACT-DECODE-1 |
| CLI RC runtime contract flags reject conflicts and preserve guest arguments | `test/integration.zig` | `--gc-runtime`/`--rc-runtime` | spec: RC-RUNTIME-CLI-1 |
| CLI builds reference counting by default and --gc-stress or --gc-runtime selects the collector | `test/integration.zig` | same | spec-case: RC-DEFAULT-1 |
| CLI RC runtime contract inheritance respects project discovery and explicit GC | `test/integration.zig` | same | spec-case: RC-RUNTIME-CLI-1 |
| invoke reports an unreadable entry as a structured setup failure naming the reason | `test/integration.zig` | `invoke` | spec-case: CLI-INPUT-REFUSED-1 |
| RC-TRAP-TEARDOWN-1 a trap deep in recursion holding open files matches the collector | `test/rc_teardown_test.zig` (file deleted) | compares a default run with `--rc-runtime=stats` and `--gc-runtime` runs (S5-D4) | RC-TRAP-TEARDOWN-1 |
| RC-TRAP-TEARDOWN-1 a trap closes inline resources held in stack slots once, like the collector | `test/rc_teardown_test.zig` (file deleted) | compares a default run with `--rc-runtime=stats` and `--gc-runtime` runs (S5-D4) | RC-TRAP-TEARDOWN-1 |
| RC-TRAP-TEARDOWN-1 a trap inside an arena discards its regions and balances | `test/rc_teardown_test.zig` (file deleted) | compares a default run with `--rc-runtime=stats` and `--gc-runtime` runs (S5-D4) | RC-TRAP-TEARDOWN-1 |
| RC-TRAP-TEARDOWN-1 a trap with open receiver scopes and pins abandons them and balances | `test/rc_teardown_test.zig` (file deleted) | compares a default run with `--rc-runtime=stats` and `--gc-runtime` runs (S5-D4) | RC-TRAP-TEARDOWN-1 |
| RC-EXIT-SCOPES-1 early returns from open receiver scopes, loops and arenas balance | `test/rc_teardown_test.zig` (file deleted) | compares a default run with `--rc-runtime=stats` and `--gc-runtime` runs (S5-D4) | RC-EXIT-SCOPES-1 |
| RC-STATIC-DROPS-1 conditionally initialized locals drop exactly once on every exit | `test/rc_teardown_test.zig` (file deleted) | compares a default run with `--rc-runtime=stats` and `--gc-runtime` runs (S5-D4) | RC-STATIC-DROPS-1 |
| RC-EXIT-SKIP-1 a file the entry returns from inside is complete at exit and matches every runtime | `test/rc_teardown_test.zig` (file deleted) | compares a default run with `--rc-runtime=stats` and `--gc-runtime` runs (S5-D4) | RC-EXIT-SKIP-1 |
| RC-EXIT-SKIP-1 an entry that closed its file before returning keeps the file and balances when counted | `test/rc_teardown_test.zig` (file deleted) | compares a default run with `--rc-runtime=stats` and `--gc-runtime` runs (S5-D4) | RC-EXIT-SKIP-1 |
| RC-EXIT-SKIP-1 the function behind the synthesized entry wrapper keeps its file and matches every runtime | `test/rc_teardown_test.zig` (file deleted) | compares a default run with `--rc-runtime=stats` and `--gc-runtime` runs (S5-D4) | RC-EXIT-SKIP-1 |

## Trimmed (the test stays; only the retired or old-internal step went)

| Test | Class of the removed part | Removed |
|---|---|---|
| a scalar-only mut record parameter writes the caller in both modes → ... writes the caller | 3 | the `--legacy-sharing` and `--value-semantics` runs; the plain run stays |
| CLI managed constants import run build installed and invalidate warm caches | 3 | the `--gc-runtime` build run under `--gc-stress` |
| CLI forwards guest arguments after -- for run and build --run | 3 | the `run --gc-stress` step |
| build --run detects module projects and installed binaries receive the same argv | 3 | `--gc-runtime` on the installed build and its `--gc-stress` run |
| boundary acceptance CLI runs through run build --run and installed paths | 3 | `--gc-runtime` on the installed build |
| CLI check-module checks bodies and never invents main | 3 | the `--legacy-sharing`/`--value-semantics` checks |
| CLI check type-checks a file without main as a library | 3 | the `--legacy-sharing` check |
| CLI property test names the parameter and type it cannot generate | 3 | `--legacy-sharing` and its `class` parameter case (a class is `E_VALUE_CLASS` under value semantics) |
| CLI growth written back through a named field remains live | 3 | the `--rc-runtime`, `--rc-runtime=stats` and `--gc-stress` runs |
| test, build, run and check write no cache into the working directory under --cache-dir | 3 | the `test --gc-runtime` run; and (class 2) the old `objects` cache directory check |
| CLI commands that need an entry point still report E_MAIN for a library | 3 | `emit-qbe` and `check --explain-ownership`; (class 2) `dump-bytecode` |
| a missing, unreadable or directory entry is refused by name with the usage status | 3 | `emit-qbe` from the command list |
| CLI grant flags reject repeats empty values and commands that do not execute | 2 | `emit-project-qbe --allow-clock` (src/qbe_build.zig) |
| CLI checks external capabilities but cannot silently grant ambient providers | 2 | the `emit-project-qbe` IL check (`myl_qbe_external_read`, src/qbe_build.zig) |
| CLI test snapshots retain exact embedded budgets ... → CLI test retains exact embedded budgets ... | 3 | `test --diagnostics=json` (S5-D6) and its DIAGNOSTIC-JSON-1 tag; the budget checks stay |
| all commands reject invalid programs ..., CLI frame budgets count main ..., all commands preserve stdout ..., CLI checks runs and dumps records ..., CLI checks resource ownership ..., CLI checks resource data operations ..., CLI checks array schemas ..., CLI checks domain privacy ..., CLI executes variants ..., CLI executes complete enum tables ..., CLI handles recoverable results ..., CLI checks bounded environment access ..., CLI exposes fs.read_only ..., CLI narrows a Network ..., CLI checks and lowers the qualified whole-path helper methods (15 tests) | 2 | every `dump-bytecode` step and its bytecode assertions (src/bytecode_model.zig); `test/fixtures/warnings.dump` deleted; the check/run/discover-duplicates assertions stay |
| CLI step budgets count dispatch and reject invalid options → CLI step budgets stop a loop and reject invalid options | 2 | the per-dispatch count (`--max-steps=1` trapping `return 1`, src/vm.zig) and `dump-bytecode`; the loop trap and option checks stay |
| CLI budget traps name the flag that raises the budget | 2 | per-dispatch count: the step trap now comes from a loop rather than a one-block `main` |
| CLI checks and runs module programs with private boundaries and cross-file traps | 2 | per-dispatch count: `run-project --max-steps` now traps a loop |
| P1 selects a validated fake while the unfinished production body is never checked | 2 | the old JSON report's `executed` count (src/native_test_command.zig) |
| a directory run discovers project roots ... / a directory run runs a main-less test library ... | 2 | the old JSON report's `programs` and `unloaded` counts (src/native_test_command.zig); verdict counts and names stay |
| a single-entry test report lists the project sources its check loaded | 2 | retargeted from the old report's `modules` to the new report's `sources` |
| CLI warm imported direct and callback ABIs follow producer rebinding changes (fix_cli_test) | 2 | `run --report` and `work-report-v1` (src/invalidation.zig) |
| an executable built without a frame ceiling refuses a runtime frame budget | 2 | the `build --max-frames=1` and `--mode=Debug` accounting builds (src/qbe_build_options.zig); now `run --max-frames=1` enforces the ceiling |

## Retargeted (backend variants → the new core's builds; expected outputs unchanged)

| Test | Change |
|---|---|
| a frame-map trap names every logical frame ... | QBE, LLVM ThinLTO and `--release` builds → the debug and `--release` builds (QBE frame maps, src/qbe_build.zig) |
| a trap through a halting failure path ... | QBE `hlt` and sticky-return builds → debug and `--release` builds; `run` with and without `--max-frames` |
| checked arithmetic at every width ... → ... from a release build as from a debug build | QBE vs LLVM overflow intrinsics → debug vs `--release` |
| CLI computes and traces the same from QBE and from LLVM ... → ... from a debug build and from --release | QBE, LLVM -O3, ThinLTO, `--release` → debug and `--release` |

## SPEC.md

**29 bullets deleted**, each of which lost its last tagged test with the deletions above: ALIAS-MIGRATION-1, ALIAS-MIGRATION-2, ALIAS-MIGRATION-3, ALIAS-MIGRATION-4, ALIAS-MIGRATION-5, BUILD-PUBLISH-1, MODULE-CHECK-2, MODULE-COMPILE-4, MODULE-EMISSION-RECORDS-1, MODULE-HOST-1, MODULE-INTERFACE-CUTOFF-3, MODULE-INTERFACE-CUTOFF-4, MODULE-SCHEDULE-1, MODULE-SCHEDULE-2, MODULE-SCHEDULE-3, MODULE-SCHEDULE-4, MODULE-SCHEDULE-6, MODULE-SYMBOL-CUTOFF-3, MODULE-SYMBOL-CUTOFF-4, MODULE-TEST-4, NATIVE-SCRATCH-ROOT-2, NATIVE-TEST-DIAGNOSTICS-1, NATIVE-TEST-FACTS-2, NATIVE-TEST-SCALE-1, NATIVE-TEST-SUMMARY-1, OWNERSHIP-EXPLAIN-1, RC-TRAP-TEARDOWN-1, STANDARD-MATH-TRIG-GENERIC-1, VALUE-SEMANTICS-12.

**13 bullets kept by promoting a surviving carrier** from `// spec-case:` to `// spec:` (the deleted test held the `spec:` tag; S5-D deletes these old files with their bullets):

| File | Tag |
|---|---|
| `test/fix_cli_test.zig` | FIX-MIGRATION-1 |
| `src/invalidation_test.zig` | INVALIDATION-EXECUTION-1 |
| `src/module_build.zig` | MODULE-CHECK-1 |
| `src/import_policy_test.zig` | MODULE-PROJECT-1 |
| `src/module_symbols_test.zig` | MODULE-SYMBOL-CUTOFF-5 |
| `src/native_test_facts.zig` | MODULE-TEST-1 |
| `src/native_test_snapshot.zig` | MODULE-TEST-5 |
| `src/module_seeder.zig` | MODULE-TEST-6 |
| `src/native_test_graph.zig` | NATIVE-TEST-6 |
| `src/native_test_receipts.zig` | PURE-SKIP-1 |
| `src/rc_trap_teardown_test.zig` | RC-EXIT-SCOPES-1 |
| `src/qbe_il_passes.zig` | RC-EXIT-SKIP-1 |
| `src/main_runtime_flags.zig` | RC-RUNTIME-CLI-1 |

`// spec: DIAGNOSTIC-JSON-1` was dropped from the trimmed snapshot-budget test (the tag has other carriers).

## `test/golden_parity.zig` (test-golden)

The replay of `tests/goldens/qbe_*.json` (recorded by the old core, unchanged) now runs
through `mylang run` on the new core, without `--qbe`. 222 cases checked (167 source,
55 fixture), 0 mismatches. Changes:

| Cases | Class | Handling |
|---|---|---|
| 24 recorded under `--gc-stress` (`qbe_files`, `qbe_native_cases`) | 3 (option retired, S5-D4) | the option is dropped and the recorded outcome still checked (stress mode never changed an outcome) |
| 5 recorded under `--legacy-sharing` (`qbe_managed`, `qbe_arena`, `qbe_parity`) | 3 (S5-D4) | counted as retired skips |
| 3 recording `R_ARENA_ESCAPE` (`qbe_arena`) | 3 (managed arenas, S5-D3) | counted as retired skips |
| 1: `qbe_native_cases/4031fd54…`, `arithmetic` under `--max-steps=1` (one block) | 2 (per-dispatch step count, src/vm.zig) | counted as a retired skip by key |

## Other edits to kept tests

- "the old back end's commands and flags are refused by name …": `run --no-cache` (ported
  by S5-B2) replaced by `run --explain-invalidation`, which B2 retired (coordinator note).
- `src/core/test_runner_project_test.zig` "providers preserve exported record layouts …":
  the changed record layout is now refused `IncompatibleProvider` (status 2) by the
  declaration-level provider validation (NATIVE-TEST-5) rather than
  `ProviderSignatureChanged` (status 1) after a full check.
