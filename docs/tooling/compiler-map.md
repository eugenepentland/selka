# Compiler map: where a change goes

This page is for an agent that has not seen the compiler and is about to change it. It lists the stages of a build in
order with their files, the files to touch for five common changes, and where each area's tests are. Every
`path: function` below names a function declared in that file and every path exists: the gate action `goals_register`
runs `tests/compiler_map.py` and fails with this page's line number when one does not (last section). The recipes are
what real commits of 2 October to 13 November 2026 have in common; the commits, and the files each recipe missed on a
fourth commit, are in `docs/audits/dev-loop-recipes-2026-11-12.md`. A step marked optional was not in every commit.

## Dead, frozen or only observed

- `SPEC.md` is frozen history since 19 October 2026: edit nothing there and add no `// spec:` tag.
- There is no interpreter, bytecode, QBE or garbage collector. S5 (8 October) deleted the old back end and merged
  `selka-core` into `selka`; `src/core/` is the only back end. `src/core/cli.zig: retiredFlag` refuses the old flags.
- `docs/legacy/` documents removed features and its examples do not run. `docs/audits/` and `docs/design/` are dated
  records of what was decided or measured then, not a description of today's code; so are the experiment records the
  development tree keeps beside the source.
- The stage store (`src/core/stage_store.zig`, `src/core/stage_pack.zig`, `src/core/stage_scopes.zig`,
  `src/core/stage_roots.zig`, `src/core/optimizer_shortcut.zig`) is live code although the engine exists: the engine
  (`src/core/engine/engine.zig`) decides module checks, ownership proofs and test reuse, and the stage store serves
  lowering, the optimizer and emission. The engine's other kinds are observed only.
- `selfhost/` holds Selka sources (components, a port of the lexer). It is not linked into the compiler, and its README
  still describes the retired QBE back end. `src/syntax_layout.txt` is generated. `zig-out/` and `.selka-cache/` are
  outputs.

## The pipeline, in order

Open the function after the colon first; the stage's other files follow it.

1. **Command line.** `src/main.zig: main` asks `src/core/cli.zig: dispatch` first; that owns `build`, `run`,
   `run-project`, `test`, `dump-ir`, `dump-typed`, `coverage` and the proof commands. `src/main.zig: standaloneCommand`
   routes `fix`, `doctest`, `doc-coverage`, `reference`, `docs` and `review`, each with its own argument grammar;
   `src/main.zig: parseArgs` and `src/main.zig: runCommand` serve `check`, `fmt`, `lint` and the project commands.
   Flags: `src/core/cli_args.zig: parse` (`build`, `run`), `src/core/main.zig: testCommand` (`test`),
   `src/core/check_command.zig` (`check`); usage text is in `src/core/main.zig`.
2. **Lexing and layout.** `src/lexer.zig: lex` makes tokens. `src/python_layout.zig: lower` turns a `:` that ends a
   line, and the dedent that leaves its suite, into tokens, so the parser never sees indentation.
3. **Parsing.** `src/parser.zig: parseModule` is recursive descent (`statement` parses one statement) and fills the
   untyped node and statement tables of `src/ast.zig` with spans. `src/formatter.zig: format` reprints the tokens.
4. **The merged program.** `src/project.zig` finds module headers and the import graph, `src/project_syntax.zig: build`
   merges every module's tables into one program, and `src/lazy_loader.zig` fills a function body when something asks
   (`src/ast.zig: ensureBody`). `src/core/project_entry.zig: resolve` finds the entry and reads `selka.json`. A file
   that reads the tables must be listed in `src/lazy_readers.zig`; stored syntax is `src/syntax_store.zig`.
5. **Checking.** `src/core/frontend.zig: checkFile` (the `Session`) loads, merges and checks. `src/sema.zig: check` and
   `src/project_compile.zig: check` resolve names and types: statements in `src/sema_statements.zig: statement`,
   expressions in `src/sema_expressions.zig: expressionWithTemporaries`, calls in `src/sema_calls.zig`, collections in
   `src/sema_collections.zig`. `src/generic_bodies.zig` checks a generic body once, symbolically. The result is the
   checked tree `src/typed.zig`. A rule with its own module is called from `src/sema.zig`
   (`src/capability_mut.zig: warn`).
6. **Source ownership.** `src/ownership_rules.zig` is the closed list of rules and the codes that may enforce each.
   `src/core/single_owner.zig: check` checks every move, borrow and `own` marker over the whole typed tree, before
   lowering.
7. **Core IR.** `src/core/build.zig: buildExecutable` lowers the typed tree to SSA instructions, one function at a time,
   for what `main` reaches (`statement` lowers a statement). `src/core/ir.zig` defines `Op` and `Inst`. Each family has
   a builder: `src/core/build_text.zig`, `src/core/build_bytes.zig`, `src/core/build_cap.zig` (capabilities),
   `src/core/build_parallel.zig`. `src/core/verify_ir.zig: check` verifies a module.
8. **Ownership in Core.** `src/core/own.zig: run` classifies each value and schedules the drops.
   `src/core/validate_ownership.zig: validate` re-checks that from the operation table
   `src/core/ownership_ops.zig: row`, and every compiler build runs it. `src/core/zero_rc.zig: contract` is the audited
   list of runtime helpers.
9. **Passes.** `src/core/passes.zig: run` is the release order (inlining, facts, trip guards, ownership, vector plans);
   `debug` runs ownership alone. `src/core/facts.zig: analyze` computes facts and
   `src/core/validate_facts.zig: validate` checks them.
10. **LLVM text.** `src/core/emit_llvm.zig: emitModule` writes one LLVM function per IR function.
    `src/core/emit_units.zig: emit` splits a module into units: one per source module in a debug build, one whole
    program in `--release`.
11. **The build driver.** `src/core/pipeline.zig: build` checks, builds, runs the passes, emits and links; an unchanged
    build is replayed first (`src/core/build_replay.zig: replay`). `src/core/driver.zig: link` compiles each unit with
    `zig cc` and links the runtime. Build modes are `src/core/build_mode.zig`.
12. **Caches.** Unit objects `src/core/unit_cache.zig`, linked programs `src/core/program_store.zig`, lowering
    `src/core/lowering_cache.zig`, front end `src/semantic_cache.zig` and `src/syntax_cache.zig`. Read
    `docs/tooling/caches.md` and `docs/tooling/engine.md` before changing a key.
13. **The test runner.** `src/core/test_runner.zig: run` builds one executable per entry file; each test runs in a
    forked trial of it (`src/core/test_runner_batch.zig`, `src/core/test_runner_execute.zig`).
14. **The runtime, in C.** `src/core/runtime/core_rt.c` (blocks, lists, output) and the family files `core_text.c`,
    `core_bytes.c`, `core_io.c`, `core_durable.c`, `core_process.c`, `core_tasks.c` and `core_test.c`.
    `src/core/driver.zig` embeds them with `@embedFile` and compiles them once per content (`runtimeDirectory`).
15. **The embedded standard library.** `src/stdlib/*.selka` are the modules and `src/standard_library.zig: source` is
    the table that embeds them. A function with no body is `builtin func`, and `src/builtin_functions.zig: supplier`
    says what supplies it. Bare names such as `len` and `copy` are `src/prelude_builtins.zig`.
16. **Diagnostics.** `src/diagnostic.zig` holds `Diagnostic` and `Fix`; `src/diagnostic_output.zig: render` prints text
    and `diagnostic-v1` JSON; `src/diagnostic_codes.zig` indexes every code; `src/reference.zig: run` answers
    `selka reference`; `src/docs_command.zig` prints the guides `src/user_docs.zig` lists.
17. **`selka fix`.** `src/fix_command.zig: run` runs `check --diagnostics=json` in rounds and applies each `fix` until
    nothing mechanical is left; `src/fix_plan.zig` picks the edits.
    `src/rename_command.zig: run` is `selka rename`: it resolves every token of the old name with
    `src/rename_uses.zig` and checks the renamed copy in memory before it writes (`docs/tooling/rename.md`).
18. **Other tools.** `src/lint.zig: evaluate` (`L_*` rules), `src/doctest_command.zig: run` (fenced examples),
    `src/doc_coverage_command.zig: run` (the feature and library documentation gate), `proofs/` (the Lean copies).

## Recipes: the files to touch

In the order to work. Every change also needs a test in the same diff, a `///` comment on each `pub` declaration
(conventions since Guardian was turned off on 18 November 2026: nothing enforces them), and `.selka` files formatted by
`selka fmt` (the `my_format` check).

### (a) A library function

Three shapes, by where the work is. Most are the first.

**(a1) A body in Selka** (`4e926b92d6`, `82627b6d91`, `3452b23a04`).

1. `src/stdlib/<module>.selka`: the function, `public func`, with a `#` comment directly above it.
2. `tests/lang/<area>.selka`: a `public func test_*() -> bool` that calls it.
3. `docs/standard-library.md`: the module's section names the function and a `selka` example runs it. Gate:
   `selka doc-coverage .` fails for an export that is not named, has no comment or has no executed example.
4. Optional: `src/features.json` (a slug needs `kind`, `summary` and a `doc` anchor whose section has an example),
   `CHANGES.md`, and a Zig test for what a guest cannot return as `True` (a refusal, a trap):
   `src/stdlib_<module>_test.zig`, registered in `src/root_test.zig`.
5. A new module also needs a row in `src/standard_library.zig`, a heading in `docs/standard-library.md` and the new
   count in words wherever a guide states one (`STDLIB-COUNT-1` in `src/standard_library_test.zig` names the file).

**(a2) The host provides it: a `Filesystem`, `Clock`, `Process` or `Network` call** (`e6948446a4`, `7c188f6360`,
`0cb4221085`).

1. `src/stdlib/<module>.selka` as in a1: the public wrapper over the capability call.
2. `src/file_operations.zig` and `src/io_builtins.zig`: the operation's kind and arity.
   `src/sema.zig: fileAccessSignature` and `src/sema_builtins.zig: checkFileAccess`: its signature and argument types.
3. `src/core/build_cap.zig: durableOperands` and its neighbours lower the call to a runtime call, which
   `src/core/runtime/core_durable.c`, `src/core/runtime/core_io.c` or `src/core/runtime/core_process.c` implements for
   the real provider and for the in-memory one a test receives (`src/core/runtime/core_tasks.c` for a child's tasks).
4. Tests: `src/<area>_test.zig` registered in `src/root_test.zig`, a fixture beside it (`src/core/durable_fixture.c`,
   `src/stdlib_fixture.zig`), and `tests/lang/<area>.selka` against the in-memory provider. The docs of a1 apply:
   `docs/standard-library.md` and `docs/io.md`. Optional: `src/features.json`, `CHANGES.md`.

**(a3) A C runtime helper under a function** (`cec29ffe8d`, `6f8a115bd9`, `ab3d10b31f`).

1. `src/core/runtime/core_<family>.c`: the helper `myl_core_*`. A new `.c` file is added to the `@embedFile` list of
   `src/core/driver.zig`.
2. `src/core/zero_rc.zig: contract`: its ownership contract. An unlisted helper is refused when a program calls it.
3. The caller, in the builder of its family: `src/core/build_text.zig`, `src/core/build_text_more.zig`,
   `src/core/build_bytes.zig`, `src/core/build_borrowed_view.zig`, `src/core/span_forms.zig` or the dispatch in
   `src/core/build.zig`. A helper that traps with a source position is also named in
   `src/core/emit_llvm.zig: siteTaking`.
4. Tests: `tests/lang/<area>.selka` for the value, and where a count of copies or allocations is the point
   `src/core/<area>_test.zig`, registered in `src/core/root_test.zig`, with its program `src/core/<area>_fixture.selka`.
5. Optional: `src/core/cost.zig` (a helper that allocates nothing is listed there so `--cost` agrees); the library
   function's own steps (a1) when the helper serves a new function rather than a faster form of an old one.

A function the compiler itself supplies is declared `public builtin func` in `src/stdlib/<module>.selka` and answered by
a row of `src/builtin_functions.zig: supplier` (a lane operation in `src/sema_simd.zig`, a scalar text helper in
`src/scalar_text_helpers.zig`, a retired method's home in `src/retired_methods.zig`). No commit since W10 (12 November)
added one, so that line comes from W10's own diff (`81cffefaa6`) and was not tried on a fourth commit.

### (b) A diagnostic

From `6e5416a64b`, `fff7b16347`, `734515c3ea`.

1. `src/diagnostic_codes.zig`: one row `.{ .name, .meaning, .guide }` in the group of its prefix (`E_`, `W_`, `L_`,
   `R_`), in sorted order. Gate: `src/reference_test.zig` fails for a printed code with no row, an unsorted row or a
   guide that is not a topic.
2. Where it is raised: a rule module `src/<rule>.zig` called from `src/sema.zig`, or the checker file that owns the
   construct (`src/sema_*.zig`, and `src/generic_bodies.zig` for generic bodies), or `src/core/single_owner.zig` for an
   ownership refusal, which also names its rule from `src/ownership_rules.zig`; a lint is in `src/lint.zig`. Attach
   `provenance.fix` where the edit is certain.
3. `src/<rule>_test.zig`, registered in `src/root_test.zig`: a program that must be refused, with its code (a refusal
   raised in Core: `src/core/<area>_test.zig`, registered in `src/core/root_test.zig`). A new file under `src/`
   that reads `.nodes.items` must be listed in `src/lazy_readers.zig` (`src/lazy_readers_test.zig` fails otherwise).
4. The guide named by the row (`src/user_docs.zig` maps the topic to a `docs/*.md` page) says what the code means.
5. If it refuses code that was accepted: a `fix`, a row in the table of `docs/tooling/fix.md`, a corpus in
   `test/fixtures/fix-migration/` (a directory of `*.selka` with `*.expected.selka`, or one flat pair) and a test beside
   `FIX-MIGRATION-1` in `test/fix_cli_test.zig`.
6. Optional: `tests/lang/<area>.selka`, `CHANGES.md`, a pinned example under `test/fixtures/goals/docs/` with its entry
   in `docs/goals.md`. A message that names a replacement spelling is tested by `src/advice_messages_test.zig`.

### (c) A statement form

From `31aa2ca803`, `5b1d599886`, `2c887cfc3b`. Each reuses an existing statement tag (a flag on `match`, a block that
desugars, a clause). The only commit of the six weeks that added tags, `d0f4cb93b0` (the 9 October syntax rewrite),
is too large to be a recipe, so step 2 and the layout half of step 1 come from counting which files name every tag.

1. `src/parser.zig: statement`: parse the form into `src/ast.zig` nodes. A change to `src/ast.zig` changes the stored
   layout: regenerate `src/syntax_layout.txt` with `selka dump-syntax --layout` (`src/syntax_dump_test.zig` fails on
   drift).
2. A new `Statement` tag is named in every one of `src/generic_bodies.zig`, `src/local_qualifiers.zig`,
   `src/quality.zig` and `src/sema_statements.zig`.
3. `src/sema_statements.zig: statement` checks it (`src/sema_expressions.zig` for the part that is an expression) and
   produces `src/typed.zig` nodes; `src/generic_bodies.zig` must accept or refuse the same programs inside a generic
   function.
4. `src/core/build.zig: statement` lowers it; `src/core/single_owner.zig` checks its moves and borrows.
5. `src/formatter.zig: format` prints it back, so `selka fmt` is stable on it.
6. The rule in `src/<form>.zig` with `src/<form>_test.zig` (registered in `src/root_test.zig`), and rows in
   `src/diagnostic_codes.zig` for its errors (recipe b).
7. `src/features.json` and a page `docs/<page>.md` (`docs/statements.md`, `docs/match-expressions.md`) whose section
   has a `selka` example that runs; `tests/lang/<form>.selka` tests the behaviour.
8. Optional: `CHANGES.md`; rewrites of the repository's own sources the form shortens
   (`src/stdlib/*.selka`, `selfhost/`, `tools/selka/`).

### (d) A Core instruction

From `83a34d66ad`, `5c139d5a61`, `fee0a76968`. Six files name every `Op`: the four Zig and two Lean files of steps 1-3.

1. `src/core/ir.zig`: the `Op` variant, appended last, with a `///` line for its operands and result.
2. `src/core/verify_ir.zig`: its operand and result types. `src/core/ownership_ops.zig: row`: its class (that switch has
   no `else`, so the compiler refuses to build until it has a row). `src/core/emit_llvm.zig`: its LLVM text.
3. The Lean copies list every `Op`: `proofs/verify_ir/VerifyIr/Types.lean` and `proofs/facts/Facts/Parse.lean`. An op
   they do not list fails their readers in the gate actions `verify-ir-proof` and `ownership-proof` once a corpus
   program uses it (O4's `box_frame` landed without it and `334b18ac21` added it).
4. The producer: a builder in `src/core/build.zig` or its family file (`src/core/build_<family>.zig`, for instance
   `src/core/build_byte_load.zig`), and `src/core/own.zig` where the ownership pass must know it; `src/core/fuse.zig`
   if a pass moves or fuses it.
5. Optional: a row in `docs/design/ownership-certificates.md` (106 of the 108 ops have one; no test reads it).
6. If it is the lowering of a new checked expression, `src/typed.zig` gets a node, `src/sema_calls.zig` or
   `src/sema_builtins.zig` produces it, and every file that names all the nodes handles it: `src/typed_walk.zig`,
   `src/duplicates.zig`, `src/origins.zig`, `src/dead_writes.zig`, `src/sema_expressions.zig`,
   `src/core/single_owner.zig` and `src/core/build.zig`. The library function over it is recipe (a).
7. Tests: `src/core/<area>_test.zig` in `src/core/root_test.zig`, building a program from `test/core/*.selka`; the
   verifier's own cases are `src/core/verify_ir_test.zig`.

### (e) A command-line flag

From `84579310f4`, `c5e21468b5`, `c3fb63b072`.

1. Parse it: `src/core/cli_args.zig: parse` for `build`, `run` and `run-project` (a field of `Request` or `Run`);
   `src/core/main.zig: testControls` for `test` (with `src/core/test_runner_options.zig`);
   `src/core/check_command.zig` for `check`; `src/main.zig` for every other command.
2. Its usage text: `usage` and `test_usage` in `src/core/main.zig`.
3. Carry it to where it acts: `src/core/pipeline.zig` (`Options`), `src/core/cli_run.zig` for a run, for `test`
   `src/core/test_runner.zig` (plus `src/core/test_runner_receipt.zig` when it changes a result's cache key), and for
   `check` `src/core/frontend.zig` (the `Session`) or `src/core/project_entry.zig`.
4. Tests: `test/integration.zig` or a `test/*_cli_test.zig` for the exit status and output, and
   `src/core/cli_flags_test.zig` for conflicts and bad values.
5. `docs/tooling/native-build.md` or `docs/tooling/guest-tests.md`, and a `kind: "tooling"` slug in `src/features.json`
   with a command block.
6. Optional: `CHANGES.md`.

## Where the tests live

`docs/tooling/test-layout.md` is the rule; this is the lookup. Run Zig tests through `scripts/build-slot.sh build ...`
after `source ~/.config/selka/dev-env.sh`, as `CLAUDE.md` says.

- Lexer, parser, checker, formatter, lint, diagnostics: `src/<area>_test.zig`, listed in `src/root_test.zig`.
  Run `python3 scripts/focused_test.py units NAME`.
- Text contracts, input probing, fix edit selection: `src/tooling_root_test.zig`.
  Run `python3 scripts/focused_test.py tooling NAME`.
- Core IR, ownership, passes, emission, runtime: `src/core/<area>_test.zig`, with programs in `test/core/`.
  Run `zig build test-core -Dtest-filter=NAME`.
- Command lines, exit statuses, caches by process: `test/integration.zig` and `test/*_cli_test.zig`.
  Run `python3 scripts/focused_test.py cli NAME`.
- Language behaviour: `tests/lang/<area>.selka`. Run `zig-out/bin/selka test tests/lang/<area>.selka --filter NAME`.
- `selka fix` migrations: `test/fix_cli_test.zig` and `test/fixtures/fix-migration/`. Run the `cli` command above.
- Diagnostic rows: `src/reference_test.zig`. Run `python3 scripts/focused_test.py units reference`.
- Fenced examples: the page itself. Run `zig-out/bin/selka doctest . --filter docs/<page>.md`.
- Feature and library documentation: `src/features.json`, `src/stdlib/*.selka`. Run `zig-out/bin/selka doc-coverage .`.
- Goals register and this page: `tests/goals_register.py`. Run `python3 tests/compiler_map.py`.
- Lean copies of the checkers: `proofs/` and `scripts/verify_ir_proof.py`, `scripts/ownership_proof.py`.
- Which tests an edit reaches: `python3 scripts/edit_check.py`; it is not the landing gate.

### The recipe for each kind of test

One entry per kind, from a commit that added such a test (15 November 2026 unless dated); each command was run once and
selected the test. NAME is a fragment of the test's name. `dev_loop.py test` compiles nothing: run
`python3 scripts/dev_loop.py start` once first. A test file that its root does not import does not run.

- **Guest behaviour** (`646aa75464`): `public func test_NAME() -> bool` in `tests/lang/<area>.selka`. Registered by
  nothing (the directory is read whole). Run `zig-out/bin/selka test tests/lang --filter NAME`; NAME matches
  `file::function`.
- **A message or a refusal** (`a057a95e28`, 14 Nov): a `test "..."` in `src/<area>_test.zig` that gives a program and
  its code to `src/stdlib_fixture.zig: rejectsWith`. A new file adds `_ = @import("<area>_test.zig");` to
  `src/root_test.zig`; a test added to a file already there needs nothing.
  Run `python3 scripts/dev_loop.py test units NAME`.
- **A golden diagnostic**, a whole message pinned (`2c7b5ab16a`): `expectMessage` in
  `src/core/escape_message_test.zig`, for advice raised in Core. A new file adds its import at the end of
  `src/core/root_test.zig` (the order sets the shards).
  Run `python3 scripts/dev_loop.py test core NAME`; `units` answers "nothing the filter named ran".
- **A command line** (`095308ec3c`): `test/<area>_cli_test.zig`, registered by `_ = @import("<area>_cli_test.zig");` in
  `test/integration.zig`. Run `python3 scripts/dev_loop.py test cli NAME`.
- **A `selka fix` migration** (`832ce49cf6`): `test/fixtures/fix-migration/<name>.selka` and `<name>.expected.selka`,
  and a `test` in `test/fix_cli_test.zig` that embeds both. Registered by nothing (the directory is an input).
  Run the `cli` command.
- **A Core test** (`c5f039d8db`, 14 Nov): `src/core/<area>_test.zig`, imported by `src/core/root_test.zig`; a program
  kept in a file is `test/core/<name>.selka` (`a057a95e28`), registered by nothing. Run the `core` command.
- **A fixture a Zig test reads** (`c5f039d8db`): a file in `test/fixtures/`, taken with
  `@embedFile("fixtures/<name>.selka")` by a `test/*_cli_test.zig`. Registered by `test/fixtures/` in the `unit` and
  `cli` lists of `build_test_inputs.zig`; a fixture elsewhere needs its path in the list of the step that reads it
  (`tests/test_inputs_coverage.py` fails without).

## Keeping this page true

`tests/compiler_map.py` reads this page's backquoted spans outside fenced blocks. A span that is a repository path must
exist (`<name>` stands for any name); a span written `path: name` must name a function that file declares; a command
that names a repository path is checked the same way; the page may have 300 lines of 120 characters; and every named
file must be an input of the `goals_register` list in `build_test_inputs.zig`. Each finding is
`docs/tooling/compiler-map.md:LINE: ...`. The gate runs it inside `goals_register` (`--map`), and
`tests/compiler_map_test.py` shows that a renamed file and a renamed function are each found.

```sh
python3 tests/compiler_map.py
python3 tests/compiler_map_test.py
```
