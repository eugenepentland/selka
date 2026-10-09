# Fixes and migrations

When the compiler rejects code and knows the exact edit that repairs it, the
diagnostic carries that edit as data, and `selka fix` applies every such edit
across a project. Certain changes can therefore be migrated with one command. Changes to lexical
scope or failure propagation inside a larger expression may still need a
deliberate rewrite; the compiler leaves those edits to the author.

## Structured fixes in diagnostics

With `--diagnostics=json`, a diagnostic whose repair is certain carries a `fix`
object beside its location. Each edit names the file, the UTF-8 byte range it
replaces in that file's own bytes, and the replacement text; an empty range
inserts and an empty text deletes. A diagnostic in a module of a project names
that module's file, not the entry's, and a diagnostic without a certain repair
has no `fix` key at all.

For a `main.selka` whose seventh line is `    grow(xs)` and whose `grow` declares
`mut xs: int[]`:

```console
$ selka check main.selka --diagnostics=json
{"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_MUTATION_MARKER","severity":"error","message":"`grow` writes `xs`; write `(mut xs)`","location":{"path":"main.selka","start":{"line":7,"column":10},"end":{"line":7,"column":12},"bytes":{"start":107,"end":109}},"notes":[],"stack":{"frames":[],"omitted":0},"fix":{"edits":[{"path":"main.selka","bytes":{"start":107,"end":107},"text":"mut "}]}}}
```

The diagnostics that carry a fix today:

| Code | Edit |
| --- | --- |
| `E_MUTATION_MARKER` | insert `mut ` before an argument bound to a `mut` parameter; delete a call-site `mut` the callee does not declare |
| `E_MUTATION_OVERLAP` | move a single unconditional mut call out of a simple receiver update into a fresh result local, then substitute that local |
| `E_MODULE_HEADER` | remove a redundant source header; module names come from paths |
| `E_FRONTEND_SYNTAX` | replace parsed legacy `def`, type spellings, parameter modifiers, conditionals, or postfix propagation with canonical syntax |
| `E_BINDING_DECLARATION` | introduce `mut` where an implicit local is confined to its block |
| `E_FRONTEND_VARIANT` | migrate a local union declaration and its known payload fields to named enum syntax |
| `E_NAMED_FIELDS`, `E_NAMED_PATTERN` | add labels from the resolved record or enum field declaration, preserving operand order |
| `E_NUMERIC_PARSE` | replace text calls to numeric casts with `parse_int` or `parse_float` |
| `E_FIXED_ARRAY_LITERAL` | wrap a known fixed-length literal in an explicit `FixedArray[T, N]` constructor |
| `E_NONE_UNIT` | replace an old Unit value `None` with `()` where its expected type is known |
| `E_REMOVED_SPELLING` | rename `push`→`append`, `List`→`list`, `filesystem_cap` and the other `*_cap` names→their capability types, `f64_sqrt`/`floor`/`ceil`/`trunc`/`abs`→the float builtin; `&value` in an argument→`mut value`; a declaration's `mutates(a, b)` clause→`mut` on `a` and `b` |
| `E_EXPLICIT_DISCARD_REQUIRED` | insert `_ = ` before a standalone value that is not a result |
| `E_KEYWORD_ONLY` | insert `name=` before each positional operand that reaches a keyword-only parameter |
| `W_UNUSED_IMPORT` | delete the import's line when it holds only that import |

A repair that needs judgement carries no fix: an escaping implicit block local
(`E_BINDING_SCOPE_MIGRATION`) or embedded propagation (`E_TRY_POSITION`) needs
a control-flow rewrite, discarding a `Result` would drop
its error, two overlapping writable arguments (`E_MUTATION_OVERLAP`) need a
snapshot or a split call, and a `mut` on a literal needs a local first.

A missing or superfluous call-site `mut` marker does not stop its function's
check, so one check reports every marker a function needs, each with its own
fix.

## selka fix

`selka fix ENTRY.selka` checks the entry, applies every fix the check published,
and checks again until nothing mechanical is left. It then prints what changed
per file and passes on whatever diagnostics remain, so the one thing left for a
person is the part a machine cannot decide:

The following historical report records the earlier call-site marker migration:

```console
$ selka fix main.selka
vm.selka:395:19: error[E_MUTATION_OVERLAP]: writable argument may alias an argument promised read-only; pass a fresh snapshot, make both inputs writable, or split the call
      table.add_all(heap.class_obj(rt, as_obj(parent)).methods, mut methods)
                    ^
  note: vm.selka:395:63: writable argument originates here; the two input graphs are not proven disjoint
fixed ast.selka: 49 edits (E_MUTATION_MARKER)
fixed compiler.selka: 284 edits (E_MUTATION_MARKER)
...
fixed vm.selka: 193 edits (E_MUTATION_MARKER)
fix: 957 edits in 13 files over 1 round
```

That is the Lox interpreter port moved across the call-site `mut` change: 957
markers restored in one command, identical to the hand migration except for the
one aliasing rewrite the compiler cannot choose for you.

- A directory argument fixes every `.selka` file beneath it: files that declare
  `main` first, then `*_test.selka` files, then the remaining modules. A module an
  already-fixed entry imports is skipped, and hidden and `zig-out` directories
  are never entered. A diagnostic several entries share is printed once.
- `--check` writes nothing: it prints `would fix PATH: N edits` lines and exits 1
  when anything would change, which makes it a CI guard.
- `--diagnostics=json` passes the remaining diagnostics on as `diagnostic-v1`
  lines; `--cache-dir=DIR` and `--no-cache` apply to the checks it runs.
- Within a round, a fix whose edits would overlap another's waits for the next
  round, which sees the updated file; the same edit reported twice (a generic
  function's instances) is applied once.

Exit status: 0 when nothing is left to fix and every entry checks (warnings
allowed), 1 when errors remain or `--check` found a change, 2 on a usage or host
failure.

```bash
selka fix src/                 # a whole tree, tests included
selka fix --check src/         # CI: fail if a migration was not applied
selka fix app/main.selka --diagnostics=json
```

## Checking libraries and test files

`selka check` accepts every file `selka test` accepts. A file with no `main`
— a library module, a `*_test.selka` file or any headerless file — is checked as a
library (`CHECK-LIBRARY-2`), so its real diagnostics come back located in the
file as written instead of one `E_MAIN`, and `selka fix DIR` can check every
file it visits. To get a test entry's diagnostics as `diagnostic-v1` JSON
lines, `fix` fields included, run `selka check --diagnostics=json` on it:
`selka test` prints a test entry that does not compile as text and exits 1,
and its `--diagnostics` flag was dropped (S5-D6).

```bash
selka check parser.selka          # a library module: its own diagnostics, no E_MAIN
selka check parser_test.selka --diagnostics=json
```

## Migrating across a breaking change

A change that makes previously accepted code a diagnostic can carry the fix
that migrates it: the diagnostic holds the exact edit, and `selka fix` moves a
project across the change with no hand edits.

The gate proves this on real code (`FIX-MIGRATION-2`).
`test/fixtures/fix-migration/lox/` pins nine modules and tests of the Lox
interpreter port with every call-site `mut` marker stripped, as a program
written before the markers were required reads; the test copies them, runs
`selka fix` on the directory, and requires the current declarations and call
markers, every entry checking clean, and a second `selka fix --check` finding
nothing. The per-change scripts under `scripts/` (such as
`migrate_mut_arguments.py`) are superseded by the fixes the compiler carries.

A retired feature migrates the same way. `with arena():` blocks were retired in
S5 and now report `E_ARENA_REMOVED`; the error carries the edit that deletes the
`with` line, dedents the block's body and rewrites `name.escape(value)` to
`value`, so `selka fix` turns pre-S5 arena code into a clean check
(`NEW-CORE-S5-ARENA-3`, corpus `test/fixtures/fix-migration/arenas.selka`). Where the
edit is not certain (tab indentation, a triple-quoted string in the body, a
header that shares its line with code, shadowed arena names, or declarations
that would collide after dedenting) the error carries no fix and the block
is left for a hand edit.

## Embedded sources

The developer helper stages guest programs from `.selka` files, Markdown fences,
Zig multiline strings and golden JSON sources, runs the compiler's own fixes,
and checks the result before replacing a file. It does not implement a second
set of syntax rewrites. Preview a selected group with:

```bash
scripts/build-slot.sh build python3 scripts/migrate_embedded.py \
  --compiler ./zig-out/bin/selka --dry-run \
  --report .selka-cache/migration-preview.json docs/functions.md
```

Remove `--dry-run` to apply validated edits. The report records exclusions,
unsafe source shapes and each compiler invocation. Headerless embedded modules
need unambiguous host path bindings; quoted or concatenated host strings that
cannot be rewritten safely are reported for explicit handling. Golden IDs,
options and expected results stay fixed. Writes replace one validated file
atomically and refuse a file changed since it was read.

The repository's `zig build fmt-check` also checks live `.selka` sources. Its
reasoned exclusions in `scripts/selka_format_exclusions.json` preserve migration
inputs, deliberate rejections, internal builtin syntax and recorded source spans.
New files under the selected live roots join the check automatically.
