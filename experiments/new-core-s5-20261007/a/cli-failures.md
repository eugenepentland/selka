# S5-A: CLI tests that fail on the new path

`zig build test-cli` on `claude/s5-a` after the switch, every test in the CLI root
(`test/integration.zig` and the files it imports: `fix_cli_test.zig`,
`native_variant_policy.zig`, `rc_teardown_test.zig`). Each failing test is listed
once with its class:

1. **new core wrong or missing**: to fix in S5-B (or S5-C when it is the runner);
2. **asserts old internals**: QBE IL, bytecode dumps, the per-module QBE build and
   its records, the old work/test report formats, the old test runner's staging,
   per-dispatch step counts;
3. **asserts a retired feature**: GC and runtime selection, legacy sharing and
   `--value-semantics`, `invoke` and host providers, `compile-module`/`emit-*`,
   `--explain-ownership`, `--pure-skip`, `--bench*`, `test --diagnostics` (S5-D3..D6).

Final run (`8a1b9ba6` + help text): 326 tests (320 before the switch plus six S5-A
spec tests), 182 passed, 144 failed (138 failed, 6 harness panics). Before the
switch all 320 passed. Every failure is in exactly one table below: class 1, 19 tests;
class 2, 75 tests; class 3, 50 tests (the nine `rc_teardown_test` tests share one row).

## Class 1: new core wrong or missing (S5-B unless noted)

| Test | Reason |
|---|---|
| CLI passes every NaN to foreign code as the canonical quiet NaN | `extern` float arguments are not canonicalized: `copysign(1.0, 0.0/0.0)` gives `-1.0` |
| a Debug build's executable does not depend on where its cache is | fails only on `--report` (not ported; S5-D6 ports it as the cache report) |
| C3s provider body changes stay visible through reused specializations | fails only on `run-project --no-cache` (not ported) |
| CLI execution timings preserve results and runtime diagnostics | `run --timings` is not ported |
| CLI test affected selects tests that reach a changed declaration | `--affected --against` not ported (S5-D6) |
| a built executable hands main every argument and reads runtime options from MYLANG_OPTIONS | a built program reads only grants and `--print-result` from `MYLANG_OPTIONS`, and only when it uses them: no startup refusal of an unknown option or unterminated quote |
| an executable built without a frame ceiling refuses a runtime frame budget | built programs do not read `--max-frames` from `MYLANG_OPTIONS` (no `R_NO_FRAME_ACCOUNTING` refusal); `mylang run` compiles its budgets in instead |
| an executable built without a requested ceiling refuses a runtime step budget | same, for `--max-steps` |
| a built program reports the frame reservation its address space cannot back | same, for `--max-frames` with `MYLANG_MEMORY_LIMIT` |
| CLI test reports a Result test's Err with its error return trace in text and JSON | the test runner's error-trace frames name `parse_port`, not `config_test::parse_port` (S5-C, runner) |
| CLI formatter and test agree on headerless sibling test imports | a header-less `_test.my` that imports a sibling module is checked as a single file and refused `E_MODULE_HEADER` (S5-C, runner) |
| CLI empty test selection names an unloaded sibling and preserves JSON | an empty selection does not name the sibling `_test.my` (S5-C, runner) |
| P1 selects a validated fake while the unfinished production body is never checked | the runner checks the replaced production module's body (`E_TYPED_HOLE`) instead of only its declarations (S5-C, runner) |
| P1 rejects stronger or malformed replacements and a bad production interface | same provider-overlay checking |
| P1 rejects every incompatible replacement dimension | same; the refusal is not `IncompatibleProvider` |
| P1 ignores an unselected production body type error while its declarations stay valid | same |
| R3 canonical descriptors compare provider scalar and nominal contracts | same provider-overlay checking |
| a typed expectation failure names both actual and expected values | the runner prints `got "3"` (the cases encoding) rather than `got 3` (S5-C, runner) |
| CLI a release build and a JSON diagnostic report the contract that failed | a contract trap's `diagnostic-v1` record has no `contract` object (kind, subject, clause, message, caller) |

## Class 2: asserts old internals

| Test | What it asserts |
|---|---|
| CLI project run reuses emitted manifest while no-cache and grants stay authoritative | `run-project --report`: the old work report and emitted-manifest reuse |
| modules compiled one by one from their imports' interfaces link into the program | `emit-project-qbe` and per-module QBE compiles |
| a project build compiles a module again only when its source or an interface it read changed | `module_build` counts in the old `--report` |
| a body edit no dependent reaches compiles its own module alone and links the whole-program executable | same |
| a signature change no reader uses compiles its own module alone and links the whole-program executable | same |
| a rename behind a dotted import path compiles and checks its caller again | same |
| a module-built program links from its modules' records into the whole-program build | same |
| run builds a project module by module, and a program the modules cannot build goes to the whole-program path | the old per-module records directory `cache/modules` |
| a project whose modules declare copied host functions builds module by module into the whole-program executable | `module_build` counts (and host functions) |
| a record whose layout changed behind a callee's body compiles a dependent that never reads it | `module_build` counts |
| a project with a mylang.json builds module by module, and what its configuration rejects is reported as the whole-program build reports it | `module_build` counts |
| check of a project re-checks only the modules whose source or read interfaces changed, and prints what the whole-program check prints | the per-module check's record counts (MODULE-CHECK-1, removed by NEW-CORE-S5-CHECK-1) |
| standard trigonometry checks through module interfaces and unchanged generic callers reuse their state | same |
| a large project's first check is the whole-program check, and module records seeded in the background answer the next | the detached module-record seeder (MODULE-CHECK-2) |
| a module compile builds its units and objects at a lower priority once its interface is published | `module_build` report |
| a standard module is compiled once per cache and compiler for every program that imports it | `module_build` report |
| CLI computes and traces the same from QBE and from LLVM without LTO, with ThinLTO and with --release | `--backend`, `--llvm-opt`, `--lto` builds |
| CLI dumps actual instructions | `dump-bytecode` |
| CLI step budgets count dispatch and reject invalid options | per-dispatch step counts (`return 1` costs 2 steps in the old core, 1 block in the new, NEW-CORE-S4-STEPS-1) |
| CLI budget traps name the flag that raises the budget | same per-dispatch count (`--max-steps=1` on a one-block `main`) |
| CLI checks and runs module programs with private boundaries and cross-file traps | same per-dispatch count (`run-project --max-steps=1`) |
| a frame-map trap names every logical frame an inlined callee, a callback, a runtime helper or recursion passes through | QBE frame maps and backend variants |
| a trap through a halting failure path reports the same code, trace, record and status | QBE noreturn paths across backends |
| checked arithmetic at every width reports the same result and trap from the LLVM overflow intrinsics as from QBE | QBE vs LLVM backends |
| CLI build report states the default and explicit optimize modes | the old build `--report` |
| CLI build uses QBE when no backend is named and --release builds LLVM O3 with LTO | the old backend receipt |
| CLI default build keeps the shared metadata object when a function is added and its trap still names every frame | the old QBE metadata object and receipt |
| CLI frame budgets count main and reject invalid overrides | `dump-bytecode` usage |
| all commands reject invalid programs before execution and locate runtime traps | `dump-bytecode` |
| CLI checks runs and dumps records and declared complete conversions | `dump-bytecode` |
| CLI checks resource ownership completion and implicit cleanup effects without ambient access | `dump-bytecode` |
| CLI checks resource data operations effects and required mutation without ambient providers | `dump-bytecode` |
| CLI commands that need an entry point still report E_MAIN for a library | `dump-bytecode` |
| mylang test stages under TMPDIR, never under /tmp, and removes its staging after a passing run | the old runner's `.pending` staging and `MYLANG_TEST_TRACE` |
| mylang test leaves no staging behind when the project is rejected before any test builds | same |
| mylang test with TMPDIR unset falls back to staging under /tmp | same |
| mylang test reclaims a killed run's marked staging and keeps unmarked scratch | same |
| all commands preserve stdout and deterministic advisory stderr | `dump-bytecode` output |
| CLI checks array schemas dumps indexing and reports bounds traps | `dump-bytecode` |
| CLI checks domain privacy unit mismatches and qualified factory execution | `dump-bytecode` |
| CLI executes variants dumps dispatch and rejects newly incomplete matches | `dump-bytecode` |
| CLI executes complete enum tables and rejects missing mappings in every command | `dump-bytecode` |
| CLI handles recoverable results and rejects silent error loss | `dump-bytecode` |
| CLI checks external capabilities but cannot silently grant ambient providers | `emit-project-qbe` |
| CLI checks bounded environment access without granting ambient process access | `dump-bytecode` |
| CLI exposes fs.read_only permission attenuation and rejects the removed spelling | `dump-bytecode` |
| CLI narrows a Network to one literal endpoint and rejects a dynamic host | `dump-bytecode` |
| CLI checks and lowers the qualified whole-path helper methods | `dump-bytecode` |
| CLI invalidation reports actual query work and marks unexecuted stages skipped | `--explain-invalidation` lower/emit/link stages |
| C4 unchanged deterministic rerun executes zero tests without lowering emission or linking | the old runner's `--report` work counts and `MYLANG_TEST_TRACE` |
| C4 helper edit reruns only the dependent test and lower only on an uncached selection | same |
| C4 invalid selected project fails before any green result | same |
| C4 expectation argument budget and force invalidate while irrelevant environment preserves receipts | same |
| C4 two providers with reversed map order prepare one graph and one library | same |
| C4 no-cache performs fresh runs without durable result or graph entries | same (and `--no-cache`) |
| a large project's first test run is the whole-program run, and a seeder's module records and that run's verdicts answer the next | the old JSON report's `executed` and the module-record seeder (harness panics on the missing field) |
| a test run started while a seeder holds the project's snapshot path does not wait for it and reports the verdicts the receipts hold | same |
| module by module, a body edit in module k compiles no module below k and re-runs exactly the tests that depend on it | same |
| after a body edit in module k exactly the tests that depend on k are rebuilt and re-run, and an unchanged rerun only replays a verdict | the old runner's `--report` counts |
| an edit that makes dependent tests trap reports the edited line, re-runs the failures, and a filter still selects one test | same |
| a directory run discovers project roots instead of every module | the old JSON report's `programs` field (harness panics) |
| a directory run runs a main-less test library no root imports, and every test once | same |
| a single-entry test report lists the project sources its check loaded | the old JSON report's `modules` field (harness panics) |
| an incremental build after body, signature and interface edits builds the program a clean build builds | the old build `--report` objects |
| a relink of reused objects keeps an identical executable, and a link over compiled ones replaces it unread | same |
| a ReleaseFast project build drops debug lines and a Debug one keeps them | `--backend qbe` |
| the first link records how zig cc links and every later link runs the linker directly | the old link route in `--report` |
| an unchanged build keeps its executable without rebuilding and a replaced one is rebuilt | the old build `--report` |
| an edit to only an embedded file rebuilds the module that embeds it and nothing else | the old build `--report` |
| a whole-program build sees an embedded file's edit and an unchanged build is skipped | the old build `--report` |
| native_variant_policy: RC-NATIVE-VARIANT-BACKEND-1 alternating emission policies cannot reuse another policy's units | `emit-project-qbe --rc-runtime` |
| native_variant_policy: RC-NATIVE-VARIANT-BACKEND-1 selective emission carries policy and rejects (…) | same |
| native_variant_policy: RC-NATIVE-VARIANT-BACKEND-1 selective emission retains original counting (…) | same |
| native_variant_policy: NATIVE-SCALAR-BACKEND-1 alternating emission partitions lean replay and (…) | same |
| fix_cli_test: CLI warm imported direct and callback ABIs follow producer rebinding changes | `run --report` and `work-report-v1` |

## Class 3: asserts a retired feature

| Test | Retirement |
|---|---|
| a scalar-only mut record parameter writes the caller in both modes | `--legacy-sharing` (S5-D4) |
| fix command previews then stores back a local alias and preserves both modes | `--legacy-sharing` |
| checker warns at a local collection alias that is written and observed | `--legacy-sharing` (`W_ALIAS_DEPENDENT`) |
| checker traces a narrowed match payload back to its collection binding | same |
| checker terminates on a cyclic alias chain and reports the observed write | same |
| recursive type branches terminate and preserve class-graph warnings | same |
| checker distinguishes a nested alias store from a fresh buffer conversion | same |
| CLI managed constants import run build installed and invalidate warm caches | `--gc-runtime` build under `--gc-stress` (the run, `build --run` and installed steps pass) |
| CLI runs the managed arena example under normal and stress collection | `--gc-stress` |
| the per-module commands are listed in help and answer a bad invocation with their usage | `compile-module` (retired) |
| a module compile run for the scheduler announces its interface on stderr | `compile-module` |
| CLI forwards guest arguments after -- for run and build --run | `--gc-stress` (the plain forwarding steps pass) |
| build --run detects module projects and installed binaries receive the same argv | `build --gc-runtime` |
| boundary acceptance CLI runs through run build --run and installed paths | `build --gc-runtime` |
| CLI check-module checks bodies and never invents main | `--legacy-sharing` |
| CLI check type-checks a file without main as a library | `--legacy-sharing` |
| CLI grant flags reject repeats empty values and commands that do not execute | `emit-project-qbe` (every grant check before it passes) |
| PURE-SKIP-1 pure failure outcome replays without executing and is never masked | `--pure-skip` (S5-D6) |
| PURE-SKIP-1 a changed dependency invalidates the recorded pure outcome | `--pure-skip` |
| PURE-SKIP-1 no-cache and force disable pure outcome replay | `--pure-skip` |
| guest benchmarks write a candidate and enforce an approved baseline immutably | `--bench*` (S5-D6) |
| a wrong benchmark result or trap fails the run and reports no measurement | `--bench*` |
| a directory benchmark run measures sequentially and stays green without tests | `--bench*` |
| CLI property test names the parameter and type it cannot generate | `--legacy-sharing` |
| CLI check --explain-ownership writes one JSON line per function | `--explain-ownership` (old ownership lowering) |
| CLI project ownership explanation includes imported accessor borrow origin | `--explain-ownership` |
| CLI legacy opt out cannot reuse default value test results | `--legacy-sharing` |
| CLI explicit semantic mode wins over the inherited mode and project opt out | `--value-semantics`/`--legacy-sharing` modes |
| CLI value semantics defaults on and legacy sharing is an explicit opt out | same |
| CLI mylang.json value_semantics opts out and a default build carries values to the frontend | `value_semantics: false` (the new core requires value semantics) |
| CLI project opt out uses the entry after valued options and for test directories | same |
| CLI invariant boundary rejects invalid JSON collection elements before the body | `invoke` (S5-D5) |
| CLI growth written back through a named field remains live | `--rc-runtime` |
| CLI RC runtime contract flags reject conflicts and preserve guest arguments | `--gc-runtime`/`--rc-runtime` |
| CLI builds reference counting by default and --gc-stress or --gc-runtime selects the collector | same |
| CLI RC runtime contract inheritance respects project discovery and explicit GC | same |
| a missing, unreadable or directory entry is refused by name with the usage status | `emit-qbe` in its command list (`run` and `run-project` give the old sentence) |
| invoke reports an unreadable entry as a structured setup failure naming the reason | `invoke` |
| test, build, run and check write no cache into the working directory under --cache-dir | `test --gc-runtime` |
| CLI test snapshots retain exact embedded budgets and recapture tightened and widened policy | `test --diagnostics=json` (S5-D6) |
| fix_cli_test: CLI test renders a test entry that does not compile as diagnostic-v1 JSON | `test --diagnostics=json` (S5-D6) |
| rc_teardown_test: all nine RC-TRAP-TEARDOWN-1 / RC-EXIT-SCOPES-1 / RC-STATIC-DROPS-1 / RC-EXIT-SKIP-1 tests | compare a default run with `--rc-runtime=stats` and `--gc-runtime` runs |

## test-units (src/root_test.zig) tests that spawn the CLI

These drive the old back end through the `mylang` binary rather than through
`native_execute`, so the switch reaches them. Final run: 2639 tests, 2622 passed,
17 failed (16 failed, 1 harness panic), all listed here:

| Test | Class | Reason |
|---|---|---|
| invoke_test (7 tests) | 3 | `mylang invoke` |
| qbe_environment_names_test: QBE Environment names come from grants rather than the linked provider context | 3 | `build --provider` |
| qbe_build_test (9 tests, one a harness panic) | 2 | spawn the compiler for `emit-project-qbe`, `emit-runtime`, the old build `--report`, the old `runtime` cache tree and `MYLANG_RC_COUNTS` RC-stats builds |
