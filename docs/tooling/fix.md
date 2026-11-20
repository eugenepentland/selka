# Fixes and migrations

When the compiler rejects code and knows the exact edit that repairs it, the diagnostic carries that edit as data, and
`selka fix` applies it across a project. Changes to lexical scope or failure propagation inside a larger expression may
still need a deliberate rewrite.

## Structured fixes in diagnostics

With `--diagnostics=json`, a diagnostic whose repair is certain carries a `fix` object beside its location; one without a
certain repair has no `fix` key. Each edit names the file (the module's own, not the entry's), the UTF-8 byte range it
replaces, and the replacement text; an empty range inserts and an empty text deletes. An ownership refusal also carries an
optional `rule` field, such as `"rule":"M3"`, naming the rule that failed; the
[ownership reference](../ownership-rules.md#refusal-codes-mapped-to-rules) and `selka reference --query CODE` list the rules
each code can enforce. A note's `role` is `related`, `origin`, `requirement`, `alternative`, `signature` or `cause` (the
statement elsewhere that made a local, record or collection own its value, which is why the refused line needs `copy(...)`
or `own`).

For a `main.selka` whose seventh line is `    grow(xs)` and whose `grow` declares `mut xs: int[]`:

```console
$ selka check main.selka --diagnostics=json
{"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_MUTATION_MARKER","severity":"error","message":"`grow` writes `xs`; write `(mut xs)`","location":{"path":"main.selka","start":{"line":7,"column":10},"end":{"line":7,"column":12},"bytes":{"start":107,"end":109}},"notes":[],"stack":{"frames":[],"omitted":0},"rule":"M3","fix":{"edits":[{"path":"main.selka","bytes":{"start":107,"end":107},"text":"mut "}]}}}
```

The diagnostics that carry a fix:

| Code | Edit |
| --- | --- |
| `E_MUTATION_MARKER` | insert `mut ` before an argument bound to a `mut` parameter; delete a call-site `mut` the callee does not declare |
| `E_TASK_CAPABILITY` | delete a capability argument of `g.submit` or a trailing argument of `parallel.map`, with the parameter it fills, when the task function never reads it; any other refused argument has no edit (return the values and read or write in the caller) |
| `E_UNUSED_CAPABILITY` | an unused `out` or `err` Stream parameter of the entry `main` is deleted with its comma (`main(args: str[], out: Stream)` becomes `main(args: str[])`); any other capability parameter is renamed to a `_` name |
| `E_METHOD_REMOVED` | a removed method call becomes its function, with the import added: `text.split(":")` as `strings.split(text, ":")`, `", ".join(parts)` as `strings.join(parts, ", ")`, `s.parse_int()` as `parse_int(s)`, a set's `add` of a non-literal as `sets.include(mut values, value)`; no edit where both operands do work (they would change places) or the import would hide a name the file binds |
| `E_LIST_MEMBERSHIP_REMOVED` | `value in values` becomes `lists.contains(values, value)`, with `import lists`; offered when both operands are pure reads, or one is and the other names no `mut` or `own` argument |
| `E_UNKNOWN_SYMBOL`, `E_GENERIC_INFERENCE` | `strings.contains(text, part)` (also `has`, `includes`, and on `bytes`, `sets`, `dicts`) and `lists.contains(data, x)` of text, bytes, a set or a dictionary become `part in text`; `lists.has` and `lists.includes` become `contains`; `import sort` before the builtin `sort(mut values)` loses its line; `argparse.MissingValue(name="db")` gains its enum, `argparse.Error.MissingValue(name="db")`, when exactly one enum has that case; `x in range(lo, hi)` becomes `lo <= x < hi`. Offered only where operands are names, fields or literals; otherwise the message names the form |
| `E_INTERNAL_NAME` | `acquire_resource` on a Network becomes the `network` operation sending the same request: `network.connect(net)`, `network.listen(net)` or `network.open_poller(net)`; a request held in a name or carrying an address has no edit |
| `E_UNKNOWN_FUNCTION` | delete the value of `return Unit()`, `return Unit` or `return unit` in a function whose result is `Unit`, when the file declares no such name; the `x in range(...)` rewrite above |
| `E_SINGLE_OWNER_OVERLAP` | where proven safe, bind one unconditional direct `mut` call that returns a scalar to a fresh local before a simple receiver update; a lent value stored by `sets.add` has `add` renamed to `include` |
| `E_MODULE_HEADER` | remove a redundant source header |
| `E_FRONTEND_SYNTAX` | replace parsed legacy `def`, type spellings, parameter modifiers, conditionals or postfix propagation with canonical syntax |
| `E_BINDING_DECLARATION` | introduce `mut` where an implicit local is confined to its block |
| `E_FRONTEND_VARIANT` | migrate a local union declaration and its known payload fields to named enum syntax |
| `E_NAMED_FIELDS`, `E_NAMED_PATTERN` | add labels from the resolved declaration, keeping operand order; `case Ok:` becomes `case Ok(_):` (`case circle(..):` for named fields) when the arm reads nothing of the payload |
| `E_NUMERIC_PARSE` | replace text calls to numeric casts with `parse_int` or `parse_float`; no edit where a declaration claims that name |
| `E_FIXED_ARRAY_LITERAL` | wrap a known fixed-length literal in `FixedArray[T, N]` |
| `E_NONE_UNIT` | replace an old Unit value `None` with `()` where its type is known |
| `E_REMOVED_SPELLING` | rename `push` to `append`, `List` to `list`, the `*_cap` names to their capability types, `f64_sqrt` and the like to the float builtin, `&value` to `mut value`, `mutates(a, b)` to `mut` on `a` and `b`; a removed `receiver.contains(value)` becomes `value in receiver` (`lists.contains` for a list); the second spellings become the one that stays: `unwrap_or(x, d)` as `x.unwrap_or(d)`, `math.min`, `math.max`, `math.sqrt`, `math.round`, `floor`, `ceil` and `trunc` as the prelude's (a zero result keeps its sign: `round(-0.4)` is `-0.0`), `strings.to_int` and `to_float` as `parse_int` and `parse_float`, `exists(fs, path)` as `fs.exists(path)`; no edit for `math.abs`, or where the file declares or binds the new name |
| `E_EXPLICIT_DISCARD_REQUIRED` | insert `_ = ` before a standalone value that is not a result |
| `E_PATTERN_PAYLOAD` | a bare `else:` or `else None:` over a Result becomes `else Err(_):`; no edit when the error type itself needs handling |
| `E_SYNTAX` | a call statement followed by `else Err(e):` or `else None:` becomes `if CALL is Err(e):` (`is None`); a module constant without its type (`const X = 1`) gains it (`const X: int = 1`) when one literal is the whole value |
| `E_KEYWORD_ONLY` | insert `name=` before each positional operand that reaches a keyword-only parameter |
| `E_BYTE_ESCAPE` | `"\u{fffd}"` becomes `"�"` for one to four hex digits of a scalar value; longer braces have no edit |
| `E_INDENTATION`, `E_TOKEN` | a line continued by a trailing operator or backslash is put in parentheses, backslashes removed (an assignment, `return`, `if`, `elif` or `while`); `f"{text!r}"` becomes `{repr(text)}` (`!s` likewise) |
| `W_BYTE_SET`, `W_RANGE_CHAIN`, `W_LITERAL_MATCH`, `W_PATTERN_SHORTHAND`, `W_OPTION_TRY`, `W_ELSE_IS_TRY`, `W_MATCH_ELSE`, `W_MATCH_IS` | the shorter spelling replaces the long one ([idiom rewrites](lint.md#idiom-rewrites)) |
| `W_UNUSED_BINDING` | a name a `match` pattern binds and the arm never reads becomes `_` (`radius=r` becomes `radius=_`; a bare enum field `case number(n, lit)` becomes `case number(n, lit=_)`); no repair where the arm writes the name (`match mut`) or in a `case a(x) \| b(x):` list |
| `W_CAPABILITY_OWN` | remove an `own` marker or parameter mode on a capability: capabilities are shareable handles ([io](../io.md#records-that-hold-capabilities)) |
| `W_CAPABILITY_MUT` | remove `mut` from a capability parameter its function never assigns or passes on as `mut`; the call sites' `mut` then carry `E_MUTATION_MARKER`, so a chain settles one level per two rounds |
| `E_BUILTIN_TYPE_NAME` | rename a type declared under a builtin type's name (`Unit`, `int`) and every qualified reference in importing modules; no edit when not every reference can be found |
| `E_INCOMPLETE_CONSTRUCTION` | delete a field default that builds a record without a required field (` = Inner()`) |
| `E_INCOMPLETE_MATCH` | where a standard enum gained a case by splitting an older one (`http.Error`'s `HeaderTooLarge`, `BodyTooLarge`, `UnsupportedVersion`), insert a copy of the older case's arm under the new name; any other missing case has no edit |
| `E_OWN_PARAMETER` | insert `own ` before the name of a plain parameter whose type is move-only, or in a function type; a type-parameter type has no edit |
| `E_OWN_MARKER` | insert `own ` for a proved final transfer; `copy(...)` when the binding is used again; remove `own` on a bare return, fresh value, scalar or borrowing position; `own x` becomes `copy(x)` for an option narrowed to `Some` that something only lends; where a later argument of the same call only reads the moved binding as a number or `bool`, reorder so the moving argument is last (`Source(total=len(plain), mem=own plain)`); in a generic body only when every instance asks for the same edit |
| `E_SINGLE_OWNER_MOVED` | the same reorder when a read follows `own` in a later argument of one call (also a field and a number or `bool` field of the same record); several fields moved out of one `mut` record become `take(mut state.field)` when the statement is the record's last use; a `const` record, a parameter or a later use has no edit |
| `E_BORROW_SOURCE` | remove a duplicate source name, or `from` from a nongeneric result with no managed successful value |
| `E_SINGLE_OWNER_BORROW` | insert `own ` before a bare `x` stored where a value is kept, for an option narrowed to `Some` that nothing reads after; replace `own` with a proved explicit copy, or remove it where returning the declared borrow keeps the `from` contract; an element binding's `mut` becomes `const` (it borrows), or its fields are written through `xs[i]`, or the read is wrapped in `copy(...)`; a lent value stored by `sets.add` has `add` renamed to `include` |
| `E_BORROW_UNDECLARED` | add missing parameter names to the result's `from` clause, in parameter order; for a function with no `from` yet, only when no caller keeps the result, otherwise wrap each borrowed return in `copy(...)` and name that caller |
| `E_BORROW_MIXED` | where all borrowed returns can be copied exactly, copy them and remove `from` |
| `E_BORROW_VIEWS_REMOVED` | `TextView` becomes `str`, `ByteView` `bytes`, and a removed `.borrow(start, end)` or `.view(start, end)` a slice (`raw.view(2, 4)` becomes `raw[2:4]`) |
| `W_COPY_FOR_STORE` | in a project check, declare `own` a parameter a function copies into storage, writing `own name` at each last-use copy and `own ` at each call, where the function is not generic, recursive or named as a value and every caller passes a new value or a name it gives up; a `public` function only when `selka.json` sets no `interface_files` and its modules have more than one top-level name; a plain list parameter whose elements a loop copies is the same repair (`for x in own xs:`) |
| `W_COPY_RETURNED` | in a project check, declare `from p` the result of a function every return of which copies a place of parameter `p`, under the conditions of `W_COPY_FOR_STORE` and when no caller is refused with the result `from p`; no caller is edited, and the repair waits for a round that applies no other fix |
| `W_COPY_IN_RECURSION` | delete every `copy(...)` of a record passed to the function's own recursive call where each managed field then borrows ([lint](lint.md#copies-in-recursion)) |
| `E_MODULE_NOT_IMPORTED` | insert `import MODULE` at its place in the sorted import block; one round adds every import a file lacks, a project module's too (`util.twice(2)` without `import util`) |
| `W_UNUSED_IMPORT` | delete the import's line when it holds only that import |
| `E_ERROR_CASE_AMBIGUOUS` | wrap `fail value` in the constructor of the first enum case that can carry it (`fail AppErr.Parse(value="text")`); a `try`, and one instance of a generic function, have no edit |
| `W_NEEDLESS_COPY` | delete the `copy(...)` whose copy-free form checks, or write the move (`own row.name`, `take(mut place)`, `options.take_or(own opt, d)`) ([lint](lint.md#needless-copies)) |
| `E_UNREACHABLE` | delete the whole line of a `return` or `fail` that ends its block after a statement that always leaves; any other statement there has no edit |
| `E_REPETITION_REMOVED` | `"-" * n`, `b"ab" * 3` and `[0] * n` become `strings.repeat("-", n)`, `byte_builder.repeat(b"ab", 3)` and `lists.filled(n, 0)`, with the import; a `u64` count gets a generated helper function |

The borrowed-result migration changes declarations, including those in imported project modules, and never inserts copies to
disguise an undeclared borrow; an unknown or ineligible `from` source needs a hand edit. Ownership move repairs check the
whole function: where the check stops at another refusal that the function without the marker stops at too, `own` is still
offered when the moved local is used nowhere else and no loop gives it away, and otherwise the message says the repair waits
for the error it names. A copy repair is withheld when source declarations shadow `copy`.

The receiver split repair is narrow: `items[selected(mut items)] = 9` can become a call bound to a fresh local followed by
`items[that_local] = 9`, only when moving the call cannot reorder another effect. Conditional calls, `own` transfers and
borrowed managed results have no edit. A fix never captures a user declaration: a wrapper named for the builtin it wraps
(`func parse_int(s: str) -> int?` around `int(s)`) keeps its diagnostic without a fix.

## Removed spellings

The method forms of text, bytes, the byte buffer, lists and sets, and the second spellings `math.min`, the bare `unwrap_or`
and `exists(fs, path)`, are refused (`E_METHOD_REMOVED`, `E_REMOVED_SPELLING`), each with its rewrite as a fix, so one round
of `selka fix` rewrites every site. No waiver excuses one. A call to a function of a standard module you did not import
(`strings.encode(text)` with no `import strings`) is `E_MODULE_NOT_IMPORTED`, and its fix is the import.

```bash
selka check src/                # names each refused spelling and the function to write
selka fix src/                  # writes them all, imports included
```

A repair that needs judgement carries no fix:

- an escaping implicit block local (`E_BINDING_SCOPE_MIGRATION`), embedded propagation whose order of evaluation hoisting
  could change (`E_TRY_POSITION`), and a `try` that several error cases fit (`E_ERROR_CASE_AMBIGUOUS`) need a control-flow
  rewrite;
- discarding a `Result` would drop its error, two overlapping writable arguments (`E_SINGLE_OWNER_OVERLAP`) need a snapshot
  or a split call, and a `mut` on a literal needs a local first;
- a binding named like a function of its module or an imported module (`E_SHADOWING`) has no fix because the new name is
  yours to choose; its refusal names the [`selka rename`](rename.md#a-binding-that-hides-a-module-level-name) command.

A missing or superfluous call-site `mut` marker does not stop its function's check, so one check reports every marker a
function needs, each with its own fix.

## selka fix

A check that printed diagnostics with a fix ends its report with `` `selka fix FILE` repairs N of these M ``: N of the M
diagnostics (errors and warnings together) carry a structured fix. `--diagnostics=json` has no such line. The line names
`selka fix FILE --warnings` when a repair is a warning's, `selka packages fix ENTRY --lock LOCK` for a command run through
`selka packages` ([packages](packages.md#repairing-with-packages)), and one summed line for a directory run.

`selka fix ENTRY.selka` checks the entry, applies every fix the check published, and checks again until nothing mechanical
is left. It then prints what changed per file and passes on the remaining diagnostics, so what is left for a person is the
part a machine cannot decide.

- **A file named alone is repaired for its errors only; a directory, or `--warnings`, repairs the warnings too.** A
  warning's repair rewrites code you may be editing (`match` into `is Some(x)`, `copy(a)` into `take(mut a)`). A file run
  that leaves warnings with a repair says so (``fix: left 2 warnings with a repair alone; `selka fix main.selka --warnings`
  repairs them too``). `--check` lists what the run would apply. A project whose `selka.json` sets `lint.warnings: "deny"`
  keeps severity `warning`, so a file run leaves them until `--warnings`.
- **A module or test file named alone is repaired alone.** A fix whose edits reach another file (a rename into its
  importers) waits, whole, and the last line says what waited (``fix: left 3 fixes in 2 other files that src/render_json.selka
  imports; `selka fix --imports src/render_json.selka` repairs them too``). `--imports` repairs the file and every module it
  imports. The file that declares `main` always repairs the program it builds, and a directory repairs every file beneath it.
- **Several paths are repaired one after another, each as if named alone,** in the order written, on the files as the paths
  before it left them. A file is edited once and `fix:` counts it once; a path named twice is repaired once. A file named on
  the command line is repaired even when its first line says `# generated by`. A path that does not exist, is neither a
  `.selka` file nor a directory, or a `SELKA_JOBS` that is not a whole number ends the run with exit 2 before any edit. A path
  that then fails as a host stops the run. The last line counts edits, files and rounds (`fix: 4 edits in 3 files over 2
  rounds`). `--check`, `--imports`, `--warnings`, `--cache-dir` and `--no-cache` apply to every path, `--report` adds one line
  for the run, and `--diagnostics=json` prints each diagnostic once.
- **A directory argument** fixes every `.selka` file beneath it: files that declare `main` first, then `*_test.selka` files,
  then the remaining modules. Each file is an entry; hidden and `zig-out` directories are never entered, and a diagnostic
  several entries share is printed once. The walk does not follow symbolic links, but an import may: a file reached through a
  link and by its own path is one file, edited once and reported under its real path.
- **A directory that is one project is checked once a round**, when every entry is a module of the project `selka check DIR`
  loads, there is more than one entry, and no source under the root holds a docstring example or a link that leaves it. Each
  module is then checked once instead of once per entry, to the same tree (a run through errors can take more rounds). Any
  other tree is checked entry by entry, up to `SELKA_JOBS` at once. With no `selka.json` the root is the directory, so
  `rows/more.selka` is module `rows.more`; a folder of independent programs that import the files beside them is refused by
  `check DIR` (`E_MODULE_READ`) and each file is checked with its own folder as root. `--report` adds a line counting the
  checks of each kind.
- Tuple declaration repairs wait for complete migration facts from every entry in the connected group of imported user
  modules; `fix` names withheld proposals and their reason on stderr.
- An entry that checks clean also has its `>>>` examples checked, and each certain fix is applied inside the docstring
  ([below](#docstring-examples)); an entry that does not check yet has them reached the round after it does.
- A run whose two rounds in a row leave every file as it was stops at once, exit 1, with `fixes stopped: two rounds in a row
  left every file as it was; the repair of CODE (PATH) did not change anything`.
- The `E_BUILTIN_FUNCTION_NAME` rename leaves a bare call whose arguments cannot be the declared function's: beside
  `func flush(n: int)`, `flush(out)` with `out: Stream` stays the builtin's and `flush(1)` is renamed. A module that
  re-exports the name cannot keep such a call bare, so the repair is withheld there.
- A rename that follows a declaration into importing modules (`E_BUILTIN_FUNCTION_NAME`, `E_BUILTIN_TYPE_NAME`) waits while
  a file of the directory does not parse and imports a module the rename edits: `fix` applies none of it and names the file
  and module on stderr, and the next run, after the file parses, renames everything together.
- Within a round, a fix whose edits would overlap another's waits for the next round, and a fix whose own edits overlap is
  never applied (`fix` names it on stderr). `W_COPY_RETURNED` waits for a round of its own, since another repair may rewrite
  a caller so that it takes the result.
- `--check` writes nothing: it prints `would fix PATH: N edits` and exits 1 when anything would change, so it is a CI guard.
  `--diagnostics=json` passes the remaining diagnostics on as `diagnostic-v1` lines.

Exit status: 0 when nothing is left to fix and every entry checks (warnings allowed), 1 when errors remain or `--check`
found a change, 2 on a usage or host failure.

```bash
selka fix src/                 # a whole tree, tests included
selka fix --check src/         # CI: fail if a migration was not applied
selka fix app/main.selka --diagnostics=json
selka fix app/main.selka --warnings   # the errors' repairs and the warnings' too, as a directory run applies them
selka fix src/render_json.selka   # that module only; what waited in its imports is named
selka fix --imports src/render_json.selka   # the module and every module it imports
```

A program that imports a locked package is repaired with `selka packages fix ENTRY --lock LOCK [SWITCHES]`: the same
switches and rules over a verified snapshot, never applying a repair that edits a package's file
([packages](packages.md#repairing-with-packages)).

## Generated files

A module a generator writes is written again by that generator, so a repair `selka fix` made there would be lost at the
next run. `fix` therefore leaves a generated file alone. A file is generated when **its first line is a `#` comment that
starts with `generated by`, in any letter case** (`# generated by tools/gen.py`, `# GENERATED by viewgen`). `selka lint` and
the change review use the same rule, and there is no list in `selka.json`.

| Command | A generated file |
| --- | --- |
| `selka fix` | no edit is applied, and a fix with an edit there is set aside whole; the summary counts them (`fix: left 2 fixes in 1 generated file alone`), and `--check` does not count them as a change |
| `selka fix FILE` | the file named on the command line is repaired (its errors, and its warnings with `--warnings`), generated or not |
| `selka check` | unchanged: every diagnostic prints, with its `fix` in `--diagnostics=json`; the repair belongs in the generator |
| `selka lint` | its `L_*` findings are dropped |
| `selka fmt` | formats the file it is given; `fmt-project` reports a difference there like any other |

```bash
selka fix src/                  # the generated modules under src/ are left alone and counted
selka fix src/detail_view.selka    # this one is repaired, because it is named
```

## Docstring examples

`selka test` compiles a function's `>>>` examples as code, so a breaking change can refuse an example while the module
still checks. `selka fix` checks them too: for an entry that checks clean it runs `selka check ENTRY --examples`, which
reports each refused example at its prompt line with the checker's own `fix`. An edit is applied only when its whole range
lies inside the text one `>>> ` or `... ` line copies and the bytes there still read the same. A moved name in a `>>>` line
and in a `...` continuation become:

```diff
-    >>> count(Holder(refs=refs))
+    >>> count(Holder(refs=own refs))
-    ...         greeting = text
+    ...         greeting = own text
```

An edit that cannot be placed exactly (it reaches text the runner synthesized, spans two lines, or holds a line break, a
backslash or a triple quote) is not applied: the diagnostic has no `fix`, carries a note saying why, stays in the report and
keeps the exit status at 1, so edit the example by hand. An edit outside the generated function is applied as published.
Warnings in examples are neither reported nor applied.

## Checking libraries and test files

`selka check` accepts every file `selka test` accepts. A file with no `main` (a library module, a `*_test.selka` file, any
headerless file) is checked as a library, so its diagnostics come back located in the file instead of one `E_MAIN`, and
`selka fix DIR` can check every file it visits. For a test entry's diagnostics as `diagnostic-v1` JSON, run
`selka check --diagnostics=json` on it: `selka test` prints one that does not compile as text and exits 1.

```bash
selka check parser.selka          # a library module: its own diagnostics, no E_MAIN
selka check parser_test.selka --diagnostics=json
```

## Migrating across a breaking change

A change that makes previously accepted code a diagnostic can carry the fix that migrates it, so `selka fix` moves a project
across the change with no hand edits. One run repairs every certain edit it finds: a file that keeps a diagnostic with no fix
still receives its other certain edits, and the unfixable one is reported for a hand edit. A removed spelling refused where
it is used reports together with every other diagnostic, so one `selka fix` sees all of a file's repairs at once.

A repository can also hold inputs that deliberately do not join a project (pre-change corpora, oracles, reproduction
sources). List those paths in [`release.exclude`](release-docs.md#configure-entries-and-paths) instead of formatting or
checking them.

A retired feature migrates the same way. `with arena():` blocks report `E_ARENA_REMOVED`, and the error carries the edit that
deletes the `with` line, dedents the body and rewrites `name.escape(value)` to `value`. Where the edit is not certain (tab
indentation, a triple-quoted string in the body, a header that shares its line with code, shadowed arena names, or
declarations that would collide after dedenting) the error carries no fix and the block is left for a hand edit.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/fix.md).
