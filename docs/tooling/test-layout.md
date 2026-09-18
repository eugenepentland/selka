# Where tests live: Zig or mylang

Language behaviour is tested in the language, under `tests/lang`, and run by
`mylang test`. The compiler's machinery is tested in Zig, under
`src/root_test.zig`. This page states that rule, shows the inner loop each side
gives you, and lists the Zig tests that still belong on the mylang side as of
2026-09-18.

## The rule

| What the test checks | Where it lives | How you run one |
| --- | --- | --- |
| A guest program's value, output or collector behaviour | `tests/lang/<area>.my`, a `public def test_*() -> bool` | `mylang test tests/lang/<area>.my --filter <name> --gc-stress --cache-dir .mylang-cache/lang-tests` |
| A source that must be rejected with a diagnostic code | Zig, `src/<area>_test.zig` | `python3 scripts/focused_test.py units <name>` |
| A guest that must trap with a runtime code | Zig | same |
| A guest that needs a `Filesystem`, `Environment`, provider or stdin fixture | Zig | same |
| Cache statistics, reuse counts, invalidation, formatting round trips, AST relocation, emitted-unit facts, allocation-failure injection | Zig | same |
| A CLI command's exit status, flags and text | Zig, `test/integration.zig` | `python3 scripts/focused_test.py cli <name>` |
| A documentation example | the fenced `mylang` block itself | `zig build test-docs` |

The deciding question is: could this test be written as a program in the
language that returns `True`? If yes, it is a mylang test. If it needs to
inspect the compiler, force a rejection, expect a trap, or supply a host
fixture, it is a Zig test. A Zig test that does both is split: the value calls
move, the rest stays under the same test name.

Two runner facts shape the split. `mylang test` treats a trap as a failure and
has no way to expect one, and a directory run rejects `--cases`, so anything
that needs arguments, providers or a non-`bool` expectation cannot live under
the `tests/lang` fan-out. Both were decided on 2026-09-18 and are recorded in
`tests/lang/README.md`; reopen them only if a new class of tests needs them.

## Why the mylang side is the faster inner loop

The gate does not care which side a test is on; it runs both in parallel and
its floor is the CLI root. The per-edit check does care. Measured on
2026-09-18 on the 20-core machine:

| Loop | Command | Cost |
| --- | --- | --- |
| One Zig area | `python3 scripts/focused_test.py units arena` | 1.5 s for 34 tests, and every run recompiles the 1113-test root binary |
| One mylang area, warm | `mylang test tests/lang/python_values.my --cache-dir .mylang-cache/lang-tests --gc-stress` | 0.06 s, every unchanged test replays its receipt |
| One mylang area, cold | same after editing the file | under 1 s, only the edited tests execute |
| Whole `tests/lang` after one edit | `mylang test tests/lang --cache-dir .mylang-cache/lang-tests --gc-stress` | about 0.5 s, plus the 20 mutation or output tests that re-execute by design |

`--affected --against HEAD` narrows a mylang run further to the tests whose
dependency closure reaches a changed declaration. Nothing equivalent exists for
a Zig root: any change reruns the whole root, and sharding only divides it.

Write new language-behaviour tests on the mylang side from now on. The list
below is the backlog of existing Zig tests that belong there too.

## Converting a test

The recipe lives in `tests/lang/README.md` under "Converting one Zig test".
The points that trip people up:

- One `.my` file per Zig file, named after it, `module <stem>` first and
  `def main() -> int: return 0` last. A Zig test that ran several guest
  sources becomes several `test_` functions with a `_1`, `_2` suffix.
- The `// spec: TAG` above the Zig test becomes `# spec: TAG` above the `.my`
  test. Guardian reads both. For a split test, only one side may carry
  `spec:`; the other carries `spec-case:`. Put `spec:` on the side that holds
  the behaviour the SPEC bullet describes.
- A test whose guest source is assembled at runtime (`allocPrint`, a loop over
  cases) is written out by hand as the concrete programs it generated.
- Delete the Zig test in the same change. The unit root's selected count must
  drop by the number moved; `tests/lang` must gain the same number of
  `test_` functions or more.
- Run `zig build test-lang` and the focused Zig area, then `zig build` so
  Guardian confirms every SPEC bullet still has a tagged test.

## Remaining Zig tests that belong on the mylang side

Classified on 2026-09-18 by reading each test body in the 76 files that still
import `native_execute.zig`: 139 tests in 43 files. "move" means the whole
test is guest values and moves as is. "split" means the test mixes guest
values with a rejection; move the value calls, keep the rejections in Zig
under the same name. The classification is mechanical, so read the helper a
test calls before moving it; a helper that also asserts on compilation
statistics or formatting makes the test a Zig test, whatever the table says.

Summary by action:

| Action | Tests |
| --- | --- |
| move | 68 |
| split | 71 |

### `src/arena_managed_test.zig` (11)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| ARENA-MANAGED-1 nested arenas redirect helper allocation and release each scope in bulk | `ARENA-MANAGED-1` | move |
| ARENA-MANAGED-1 an anonymous arena scope still bulk releases its allocations | `ARENA-MANAGED-1` | move |
| ARENA-MANAGED-2 escape copies a shared subgraph once into the enclosing region | `ARENA-MANAGED-2` | move |
| ARENA-MANAGED-2 escape preserves a cycle through a record field | `ARENA-MANAGED-2` | move |
| ARENA-MANAGED-2 an escaped copy may be returned from the outermost arena scope | `ARENA-MANAGED-2` | move |
| ARENA-MANAGED-2 escape shares objects that already live in the enclosing region | `ARENA-MANAGED-2` | move |
| ARENA-MANAGED-5 result propagation out of an arena releases its storage in bulk | `ARENA-MANAGED-5` | move |
| ARENA-MANAGED-5 break and continue out of an arena close the scope exactly once | `ARENA-MANAGED-5` | move |
| ARENA-MANAGED-6 stress collection inside an arena sweeps unreachable arena objects | `ARENA-MANAGED-6` | move |
| ARENA-MANAGED-6 noalloc still rejects arena allocation while entering a scope is free | `ARENA-MANAGED-6` | split |
| ARENA-MANAGED-9 a managed binding first assigned inside an arena is confined once the block ends | `ARENA-MANAGED-9` | split |

### `src/effects_test.zig` (9)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| recursive effect summaries reach fixed points independent of declaration order | — | split |
| M2 nested record aliases keep the input origin | `MUTATION-METADATA-1` | split |
| M2 shallow copy severs only the outer container | `MUTATION-METADATA-1` | split |
| M2 identity-returning helpers do not launder input origins | `MUTATION-METADATA-1` | split |
| M2 branches and loops attribute writes to the receiver origin | `MUTATION-METADATA-1` | split |
| M2 recursive helpers propagate mutation footprints to a fixed point | `MUTATION-METADATA-1` | split |
| M2 indirect callbacks obey mutation contracts | `MUTATION-METADATA-1` | split |
| M2 writable and read-only arguments that may overlap reject | `MUTATION-METADATA-1` | split |
| compile-time str literals contribute no managed allocation while computed strings and collections do | `EFFECT-LITERAL-1` | split |

### `src/prelude_builtins_test.zig` (9)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| sum adds a list of ints or floats and rejects other element types | `PRELUDE-FOLD-1` | split |
| sorted returns a new ascending list for int, float and str | `PRELUDE-SORT-1` | split |
| sorted key lambdas order records stably and diagnose invalid inputs | `PRELUDE-SORT-KEY-1` | split |
| round returns the nearest integral float with halves away from zero | `PRELUDE-ROUND-1` | split |
| any and all fold a list of conditions | `PRELUDE-FOLD-2` | split |
| reversed, list and zip iterate or materialise without a new runtime | `PRELUDE-ITERATION-1` | split |
| declared len and replace functions shadow their prelude operations | `PRELUDE-SHADOW-2` | split |
| len returns int for every supported receiver and dot len is removed | `CANONICAL-LEN-1` | split |
| prelude types are registered from syntax instead of raw source text | `PRELUDE-TYPES-2` | split |

### `src/python_syntax_test.zig` (8)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| Python indentation records assignment boolean precedence and omitted unit execute | `PYTHON-1` | move |
| Python generics default to copy and None means unit | `PYTHON-2` | move |
| Python parameters rebind and existing locals update across blocks | `PYTHON-2` | split |
| PY-SCOPE-1 predeclared loop state and complete branches bind after the block | `PY-SCOPE-1` | move |
| match merges definite assignment across continuing arms | `PY-SCOPE-3` | move |
| record is the canonical declaration head without reserving the name | `PY-RECORD-1` | move |
| Python generic value records use square construction and default copy constraints | `PYTHON-3` | move |
| leading string statements are inert module and function docstrings | `DOC-1` | split |

### `src/io_print_test.zig` (7)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| IO-1 print renders scalars, text, bytes and containers with Python spellings | `IO-1` | move |
| IO-2 print renders records, enums, unions and checked results by name | `IO-2` | move |
| IO-3 print accepts sep and end keyword arguments and rejects other keywords | `IO-3` | split |
| IO-4 print contributes the output effect that noio withholds | `IO-4` | split |
| STREAM-CAPABILITY out.print and err.print route a Stream receiver to its fd | `STREAM-CAPABILITY-1` | move |
| STREAM-CAPABILITY a helper takes any Stream name and stream.write returns its count | `STREAM-CAPABILITY-1` | move |
| DEBUG-LINE-1 debug writes to stderr and contributes no output effect | `DEBUG-LINE-1` | move |

### `src/managed_lists_test.zig` (7)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| managed aliases mutate immutable bindings across helpers without allocator authority | `GC-SOURCE-1` | move |
| managed recursive record cycles are traced at a later managed allocation | `GC-SOURCE-2` | move |
| managed intermediate call arguments and record snapshots survive collection | `GC-SOURCE-3` | move |
| noalloc rejects transitive managed allocation while permitting fixed-slot mutation | `GC-SOURCE-6` | split |
| managed cycles lose local and record roots on block break and continue exits | `GC-SOURCE-11` | move, hand-written source |
| a managed alias keeps one identity and an aggregate snapshot roots its elements | `GC-ROOTS-1` | move |
| an unreachable managed cycle is reclaimed while a reachable one survives collection | `GC-CYCLES-1` | move |

### `src/callbacks_test.zig` (6)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| a callback type names itself the way the surface writes it | `CALLBACK-1` | split |
| callbacks drive sorting and visitor helpers across module boundaries | — | move |
| module projects preserve expression lambdas through merging and execution | `PY-LAMBDA-1` | move |
| callbacks reject malformed invoke metadata and dispatch dynamically selected targets | — | move, hand-written source |
| E1 pure callbacks enter output-permitting slots and the reverse direction rejects | `CALLBACK-1` | split |
| E1 unused generic declarations use the directional callback relation | `CALLBACK-1` | split |

### `src/structural_constraints_test.zig` (6)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| structural operation forwarding retains type identity and public contracts | — | split |
| structural concrete operations reject private absent wrong typed and excessive effect methods | — | split |
| structural composite fields substitute arrays and nominal applications | `STRUCTURAL-COMPOSITE-1` | split |
| named constraint operation ceilings accept subsets and reject excess | `NAMED-CONSTRAINT-SEMANTICS-3` | split |
| named constraints coalesce identical members and reject conflicts | `NAMED-CONSTRAINT-SEMANTICS-6` | split |
| named constraints reject conflicting callback parameters results and effects | `NAMED-CONSTRAINT-CALLBACK-1` | split |

### `src/exit_status_test.zig` (5)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| a program returning 7 exits with status 7 | `EXIT-STATUS-1` | move |
| a returned value wider than a byte truncates so 256 exits 0 | `EXIT-STATUS-1` | move |
| a returned value keeps only its low byte so 259 exits 3 | `EXIT-STATUS-1` | move |
| print-result still prints the value while the status reflects it | `EXIT-STATUS-1` | move |
| a unit entry exits 0 and a Result entry carries its adapted code | `EXIT-STATUS-1` | move |

### `src/python_core_test.zig` (5)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| prelude list Result and Option keep one identity across modules and spellings | `PYTHON-CORE-1` | move |
| unit and checked-result main adapt to scalar status without changing guest call signatures | `PYTHON-CORE-2` | move |
| Python exported module signatures share builtin types and resolve enum members | `PYTHON-CORE-1` | move |
| representable integer literals inherit parameter local and expression contexts | `PYTHON-CORE-3` | split |
| a self-referential class graph prints to the depth cap and terminates | `CLASS-MANAGED-1` | move |

### `src/builtin_context_test.zig` (4)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| builtin list and Result share identity across imported module signatures | `BUILTIN-CONTEXT-8` | move |
| module-local Bucket declaration remains distinct from the prelude list | `BUILTIN-CONTEXT-9` | move |
| module-local Ok and Err functions shadow contextual constructors in generic and ordinary bodies | `BUILTIN-CONTEXT-10` | move |
| builtin list and declared Result types retain their own nominal identity | `BUILTIN-CONTEXT-7` | move |

### `src/compiler_test.zig` (4)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| precedence grouping left associativity and operand order | `CORE-1` | move |
| signed division and remainder implement truncation toward zero | — | move |
| function signatures entry points and all uncalled bodies are checked | — | split |
| all comparisons boolean operations and logical precedence have observable results | — | move, hand-written source |

### `src/dotted_modules_test.zig` (4)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| dotted imports preserve function values and generic body type references | `MODULE-DOT-2` | split |
| dotted imports retain private symbol private domain and alias shadow checks | `MODULE-DOT-3` | split |
| unaliased dotted imports resolve the full module path and the trailing alias | `MODULE-DOT-6` | split |
| a bare dotted-import prefix stays an ordinary name beside the qualified path | `MODULE-DOT-6` | split |

### `src/float_operations_test.zig` (4)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| binary64 IEEE boundaries canonical NaNs signed zero and FloatConversion | `FLOAT-DOMAIN-1` | move |
| float intrinsics evaluate at runtime and reject raw operands | `FLOAT-DOMAIN-1` | split |
| ordinary float values reach the same binary64 semantics without a nominal domain | `FLOAT-DOMAIN-1` | move |
| a float-in float-out intrinsic takes a float operand and answers a float | `FLOAT-INTRINSIC-FLOAT-1` | split |

### `src/python_surface_test.zig` (4)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| case _ covers every variant no earlier arm names | `PY-WILDCARD-1` | move, hand-written source |
| len and replace name ordinary declarations and members | `PY-RESERVED-1` | move |
| a while True with no break never falls through to a missing return | `PY-LOOP-1` | split |
| prelude float operations replace hand-rolled bit-pattern intrinsics | `PY-FLOAT-1` | split |

### `src/results_test.zig` (4)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| binding transfer and explicit release cannot silently drop results | `CORE-10` | split |
| result obligations must agree across all continuing branch and match paths | — | split |
| loops and short circuit evaluation cannot conditionally lose result obligations | — | split |
| mutable result slots require handling before replacement and permit explicit transfer | — | split |

### `src/nominal_instances_test.zig` (3)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| nominal instances preserve argument order and nominal declaration identity | — | split |
| nominal instances retain concrete checks within generic bodies | — | split |
| nominal instances carry domain payloads beside resource declarations | — | move |

### `src/records_test.zig` (3)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| complete conversion accounts named source fields and requires complete destination | — | split |
| record field defaults fill omitted fields in positional and named construction | `RECORD-DEFAULT-1` | split |
| functional record update copies only named fields and leaves the base alone | `RECORD-UPDATE-1` | split |

### `src/unit_test.zig` (3)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| unit calls bare returns and generic fallthrough preserve results | `UNIT-1` | move |
| unit result payloads still require handling and propagation only drops successful unit | `UNIT-5` | split |
| unit fallthrough and early return release managed parameters without losing result obligations | `UNIT-4` | move |

### `src/const_lengths_test.zig` (2)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| const length function parameters specialize array shapes and forward values | — | move |
| one helper serves distinct nominal element types and empty lengths | — | move |

### `src/domain_equality_test.zig` (2)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| domain equality resolves declaration identity through module aliases | — | split |
| domain equality compares every scalar backing by value | `DOMAIN-EQUALITY-1` | move, hand-written source |

### `src/generic_arrays_test.zig` (2)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| generic array templates reject invalid uncalled bodies and invalid lengths | — | split |
| generic array membership reuses code across nominal IDs without mixing domains | `GENERIC-ARRAY-1` | split |

### `src/generic_concrete_test.zig` (2)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| generic match payload scopes and fallthrough preserve independent arm checking | — | split |
| generic concrete enum tables require complete unique nominal keys | — | split |

### `src/managed_cell_test.zig` (2)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| generic Cell construction is recognized and tracks allocation effects | `CELL-GENERIC-1` | split |
| Cell equality is rejected for membership search and nested containers | `CELL-EQUALITY-1` | split |

### `src/managed_frontend_test.zig` (2)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| managed generic list creation mutation and copy identity preserve shared aliases | `GC-GENERIC-1` | move |
| managed nominal recursive list record edges allow finite reference graphs | `GC-GENERIC-2` | move |

### `src/nominal_bodies_test.zig` (2)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| nominal bodies reject invalid uncalled field payload and identity operations | — | split |
| nominal bodies propagate results with named error remapping and obligations | — | split |

### `src/python_arrays_test.zig` (2)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| truncating helpers check arity and defer to a binding of the same name | `PY-DIV-1` | split |
| a conversion body accepts the Python record constructor | `PY-CONVERSION-1` | split |

### `src/surface_statements_test.zig` (2)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| a newline or a dedent ends a statement and a semicolon separates two on one line | `SURFACE-STMT-1` | split |
| newline suffixes end an expression outside parentheses and continue inside parentheses | `SURFACE-STMT-9` | move |

### `src/domain_codecs_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| source codec operations follow selected method names rather than naming conventions | — | move |

### `src/domains_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| domain backing types require built-in scalars and exact wrapping types | — | split |

### `src/for_range_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| half-open ranges evaluate bounds once and support generic nested exits | `FOR-RANGE-1` | move |

### `src/generic_execution_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| generic execution preserves nominal values through copy contracts | — | split |

### `src/integer_operations_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| named integer width boundaries reject InvalidShift and DivisionByZero | `INTEGER-EXTENDED-1` | move |

### `src/integers_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| all integer widths accept their limits and reject one-past literals | `CORE-4` | split |

### `src/loop_exit_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| loop exits release the nested managed arenas they jump out of | — | move |

### `src/managed_values_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| user nominal str declaration preserves its declared fields | — | move |

### `src/propagation_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| propagation cannot abandon pending locals parameters or unfinished expression results | — | split |

### `src/python_assert_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| assert checks a Boolean condition under any effect bound and inside loops | `PY-ASSERT-1`, `PY-ASSERT-2` | split |

### `src/python_calls_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| Python keyword scalar and reference calls emit native source with identical side effects | `PYTHON-CALL-1` | move |

### `src/python_format_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| a native build spells an interpolated aggregate exactly as print writes it | `PY-FSTRING-1` | move |

### `src/python_variants_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| an imported generic variant takes its arguments from the expected type across modules | `PY-VARIANT-3` | move |

### `src/standard_library_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| standard modules load through embedded providers and execute reserved sources | `STANDARD-MODULES-1` | move |

### `src/type_aliases_test.zig` (1)

| Zig test | Spec tags | Action |
| --- | --- | --- |
| transparent aliases compose scalar arrays nominal applications constants and generic functions | `TYPE-ALIAS-1` | move |


## What stays in Zig, and why

Of the 1113 tests in `src/root_test.zig`, 486 never build a guest and are not
in question. Of the 627 in files that do, these stay:

| Kind | Tests | Why |
| --- | --- | --- |
| Diagnostic tests | 138 | The source must be rejected; `mylang test` needs a checked project |
| No guest run at all | 123 | Formatter, parser, project and schema checks that share a file with guest tests |
| Compiler internals | 86 | Assert on `statistics`, reuse counts, relocation, formatting round trips or emitted-unit facts |
| Allocation-failure injection | 74 | `checkAllAllocationFailures` and `FailingAllocator` have no equivalent in the language |
| Host fixtures | 36 | `Filesystem`, `Environment`, providers, stdin, sandboxes |
| Expected traps | 31 | The runner has no `expect_trap` |

Whole files that stay for those reasons, so nobody re-audits them:
`semantic_cache_test`, `syntax_cache_test`, `syntax_cache_large_test`,
`interfaces_test`, `io_files_test`, `environment_test`,
`external_capabilities_test`, `resource_source_test`, `resource_io_test`,
`nominal_providers_test`, `nominal_environment_test`, `python_bytes_test`, `python_collections_test`, `python_strings_test`,
`python_values_test`, `python_generics_test`,
`generic_results_test`, `generic_codecs_test`, `nominal_type_syntax_test`, `diagnostic_recovery_test`, `qbe_test`,
`source_map_test`, `semantic_project_test`, `tables_test`, `variants_test`,
`arrays_test`.

## Done when

- `grep -l native_execute.zig src/*_test.zig | wc -l` has dropped from 76 to
  the files in the table above, and none of the 139 tests listed here remains
  in Zig in its value form.
- Every SPEC bullet those tests carried still resolves to a tagged test,
  which `zig build` verifies.
- The inner-loop table above is re-measured and the mylang rows still hold.
- `tests/lang/README.md` and this page are updated with the new counts, and
  this section is replaced by the date it was finished.
