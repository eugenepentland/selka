# Fixes and migrations

When the compiler rejects code and knows the exact edit that repairs it, the
diagnostic carries that edit as data, and `mylang fix` applies every such edit
across a project. This is the stability contract for code outside this
repository: a breaking language change is one command for the projects it
breaks, not a hand migration and not a one-off script.

## Structured fixes in diagnostics

With `--diagnostics=json`, a diagnostic whose repair is certain carries a `fix`
object beside its location. Each edit names the file, the UTF-8 byte range it
replaces in that file's own bytes, and the replacement text; an empty range
inserts and an empty text deletes. A diagnostic in a module of a project names
that module's file, not the entry's, and a diagnostic without a certain repair
has no `fix` key at all.

For a `main.my` whose seventh line is `    grow(xs)` and whose `grow` declares
`xs: mut list[int]`:

```console
$ mylang check main.my --diagnostics=json
{"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_MUTATION_MARKER","severity":"error","message":"`grow` writes `xs`; write `(mut xs)`","location":{"path":"main.my","start":{"line":7,"column":10},"end":{"line":7,"column":12},"bytes":{"start":107,"end":109}},"notes":[],"stack":{"frames":[],"omitted":0},"fix":{"edits":[{"path":"main.my","bytes":{"start":107,"end":107},"text":"mut "}]}}}
```

The diagnostics that carry a fix today:

| Code | Edit |
| --- | --- |
| `E_MUTATION_MARKER` | insert `mut ` before an argument bound to a `mut` parameter; delete a `mut` the callee does not declare; insert `mut ` before the type of each parameter the body writes; delete a `mut` the body never writes or that marks a type with nothing to write |
| `E_MODULE_NAME` | replace the declared module name with the one the file's path gives it |
| `E_REMOVED_SPELLING` | rename `push`→`append`, `List`→`list`, `filesystem_cap` and the other `*_cap` names→their capability types, `f64_sqrt`/`floor`/`ceil`/`trunc`/`abs`→the float builtin; `&value` in an argument→`mut value`; a declaration's `mutates(a, b)` clause→`mut` on `a` and `b` |
| `E_EXPLICIT_DISCARD_REQUIRED` | insert `_ = ` before a standalone value that is not a result |
| `E_KEYWORD_ONLY` | insert `name=` before each positional operand that reaches a keyword-only parameter |
| `W_UNUSED_IMPORT` | delete the import's line when it holds only that import |

A repair that needs judgement carries no fix: discarding a `Result` would drop
its error, an overlapping writable argument (`E_MUTATION_OVERLAP`) needs a
snapshot or a split call, and a `mut` on a literal needs a local first.

A missing or superfluous call-site `mut` marker does not stop its function's
check, so one check reports every marker a function needs, each with its own
fix.

## mylang fix

`mylang fix ENTRY.my` checks the entry, applies every fix the check published,
and checks again until nothing mechanical is left. It then prints what changed
per file and passes on whatever diagnostics remain, so the one thing left for a
person is the part a machine cannot decide:

```console
$ mylang fix main.my
vm.my:395:19: error[E_MUTATION_OVERLAP]: writable argument may alias an argument promised read-only; pass a fresh snapshot, make both inputs writable, or split the call
      table.add_all(heap.class_obj(rt, as_obj(parent)).methods, mut methods)
                    ^
  note: vm.my:395:63: writable argument originates here; the two input graphs are not proven disjoint
fixed ast.my: 49 edits (E_MUTATION_MARKER)
fixed compiler.my: 284 edits (E_MUTATION_MARKER)
...
fixed vm.my: 193 edits (E_MUTATION_MARKER)
fix: 957 edits in 13 files over 1 round
```

That is the Lox interpreter port moved across the call-site `mut` change: 957
markers restored in one command, identical to the hand migration except for the
one aliasing rewrite the compiler cannot choose for you.

- A directory argument fixes every `.my` file beneath it: files that declare
  `main` first, then `*_test.my` files, then the remaining modules. A module an
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
mylang fix src/                 # a whole tree, tests included
mylang fix --check src/         # CI: fail if a migration was not applied
mylang fix app/main.my --diagnostics=json
```

## Checking libraries and test files

`mylang check` accepts every file `mylang test` accepts. A file with no `main`
— a library module, a `*_test.my` file or any headerless file — is checked as a
library (`CHECK-LIBRARY-2`), so its real diagnostics come back located in the
file as written instead of one `E_MAIN`, and `mylang fix DIR` can check every
file it visits. `mylang test --diagnostics=json` reports a test entry that does
not compile the same way `check --diagnostics=json` does, `fix` fields included.

```bash
mylang check parser.my          # a library module: its own diagnostics, no E_MAIN
mylang check parser_test.my --diagnostics=json
mylang test parser_test.my --diagnostics=json
```

## Migrating across a breaking change

A change that makes previously accepted code a diagnostic can carry the fix
that migrates it: the diagnostic holds the exact edit, and `mylang fix` moves a
project across the change with no hand edits.

The gate proves this on real code (`FIX-MIGRATION-2`).
`test/fixtures/fix-migration/lox/` pins nine modules and tests of the Lox
interpreter port with every call-site `mut` marker stripped, as a program
written before the markers were required reads; the test copies them, runs
`mylang fix` on the directory, and requires all 91 markers restored, every entry checking clean, and a second `mylang fix --check`
finding nothing. The per-change scripts under `scripts/` (such as
`migrate_mut_arguments.py`) are superseded by the fixes the compiler carries.
