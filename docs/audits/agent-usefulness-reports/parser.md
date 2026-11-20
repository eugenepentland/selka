# D2 + S1(c) — parser hints and headerless standard-module imports

Packages: **D2** and **S1(c)** of
[`agent-usefulness-implementation-plan-2026-09-20.md`](../agent-usefulness-implementation-plan-2026-09-20.md).
Baseline: [`baseline-2026-09-20.md`](baseline-2026-09-20.md).
Measurement binary: the installed `zig-out/bin/mylang` after a green `zig build`
(guardian 88/88, `zig build fmt-check` clean). The frozen
`zig-out/bin/mylang-baseline-20260920` is used for every "before" line below and
was never overwritten.

## Status

| Item | Status | Evidence |
| --- | --- | --- |
| D2 union/enum/result case without a comma | done | `src/declaration_hints_test.zig` `PARSER-HINT-1`; probe below |
| D2 bare module-level assignment | done | `PARSER-HINT-2` (bare and annotated spellings) |
| D2 `def` inside a record/class body | done | `PARSER-HINT-3` (first member and after a field) |
| D2 `from module import name` | done | `PARSER-HINT-4` |
| D2 one table with the friction classifier | done | `PARSER-HINT-5` (Zig, runs in the gate) + `tests/parser_hints.py` (end-to-end) |
| S1(c) headerless script may import standard modules | done, one documented limit | `HEADERLESS-STD-IMPORT-1`; `probe4.my` shape checks and runs |
| S1(c) headerless project import keeps `E_MODULE_HEADER` | done | `HEADERLESS-STD-IMPORT-2`; `a41_import_os.my` byte-identical to baseline |
| S1(c) module-graph commands unaffected | done | `list-modules` on `tests/lang/standard_strings.my` unchanged; `zig build test-cli` 153/153 |

Both packages are complete. The one limit is `mylang fmt` on a module-syntax
file (pre-existing for headered files, now also reachable for the headerless
form); see *Remaining limits*.

## Files changed

| File | Change |
| --- | --- |
| `src/parser.zig` | `HintForm`, `DeclarationHint`, `declaration_hints` table and `caseCommaMessage`; `hint`/`hintHere`/`caseAtSameColumn`/`pythonDeclarationHead` helpers; the union/enum/result case loop now names the missing comma; the top-level dispatch names a bare assignment or a `from` import; `recordFields` names a `def` in a record/class body; `parseModule` split into a headerless standard-import path plus a shared `importDirectives`; the export-directive branch extracted to `reexportDirective` to keep `parse` under the cognitive-complexity cap. |
| `src/project.zig` | `moduleDeclaration` (header or headerless entry opening), `isStandardModule`, `standardImportOpening` (the one policy the parser and loader share), `ModuleName`, `eModuleHeader` and a `standard_library` import alias; `header` takes `is_entry`. |
| `src/main.zig` | `run` help text now says the entry loads the reachable graph when it opens with a module header or an import/export directive, "including a headerless script that imports embedded standard modules". |
| `src/declaration_hints_test.zig` | New: the four hints (code, message, location, `alternative` note) and the classifier agreement. |
| `src/headerless_import_test.zig` | New: `parseModule` and `Project.load` accept the headerless standard-import entry; the headerless project import, the imported headerless file and the headerless file with no imports keep `E_MODULE_HEADER` at their first token. |
| `src/root_test.zig` | Two appended `_ = @import(...)` lines in the existing import block. |
| `velocity/friction/classifier.json` | `hints` array (`union-cases`, `module-constant`, `method`, `from-import`), two new `E_SYNTAX` rows (`from-import`, `union-cases`), and a note explaining the one-table contract. |
| `tests/parser_hints.py` | New driver: static agreement by default, `--compiler PATH` also runs the four probes and the headerless script end to end. |
| `docs/python-syntax.md` | New section *Declaration forms Python spells differently* with four runnable `# doc: expect-error E_SYNTAX` examples. |
| `docs/modules.md` | New *Headerless scripts* subsection (runnable example plus a `# doc: expect-error E_MODULE_HEADER` example), the single-file rule in *Limits* restated. |
| `src/features.json` | New `headerless-standard-imports` language feature anchored at `docs/modules.md#headerless-scripts`. |
| `SPEC.md` | Seven appended bullets: `PARSER-HINT-1..5`, `HEADERLESS-STD-IMPORT-1..2`. |

Not edited, per the ownership split: `src/diagnostic.zig`,
`src/diagnostic_output.zig`, `src/sema.zig`, `src/project_test.zig`,
`build.zig`.

## Before and after at the probes

Frozen baseline: `./zig-out/bin/mylang-baseline-20260920 check <probe>`; after:
`./zig-out/bin/mylang check <probe>`. Exit status is 1 in every case, before and
after.

```
a37_const.my:2:1: error[E_SYNTAX]: unexpected token; expected def
  MAX = 42
  ^
```

```
a37_const.my:2:1: error[E_SYNTAX]: a bare assignment declares no module-level binding
  MAX = 42
  ^
  alternative: declare it as a constant: const MAX: int = 42
```

```
a38_class_methods.my:3:5: error[E_SYNTAX]: unexpected token; expected a name
      def __init__(self, x: int, y: int):
      ^
```

```
a38_class_methods.my:3:5: error[E_SYNTAX]: a record or class body declares fields, not methods
      def __init__(self, x: int, y: int):
      ^
  alternative: declare a top-level function taking the record: def norm1(p: Point) -> int
```

```
a39_dataclass.my:2:1: error[E_SYNTAX]: unexpected token; expected def
  from dataclasses import dataclass
  ^
```

```
a39_dataclass.my:2:1: error[E_SYNTAX]: a from-import is not a declaration
  from dataclasses import dataclass
  ^
  alternative: import the module and declare a record: import dataclasses
```

The union shape has no probe in `velocity/suites/idioms/`, so the driver's own
fixture stands in for it (`union Event:` / `heartbeat` / `count: int`):

```
union_comma.my:3:5: error[E_SYNTAX]: unexpected token; expected a dedent
      count: int
      ^
```

```
union_comma.my:3:5: error[E_SYNTAX]: union cases are separated by commas
      count: int
      ^
  alternative: insert a comma after the previous case
```

The code and the offending span are identical in all four pairs — `E_SYNTAX` at
`a37 2:1`, `a38 3:5`, `a39 2:1`, the second case — which is the acceptance's
"existing `E_SYNTAX` tests keep their code and span".

S1(c), the session's `probe4.my` shape:

```
$ mylang-baseline-20260920 check probe4.my
probe4.my:1:1: error[E_MODULE_HEADER]: file must begin with a module declaration
  import strings
  ^
$ mylang check probe4.my          # exit 0, no output
$ mylang run probe4.my --print-result
42                                 # exit status 42
$ mylang build probe4.my -o probe4bin && ./probe4bin --print-result
42
```

`a41_import_os.my` (headerless, imports the non-embedded `os`) is byte-identical
before and after:

```
a41_import_os.my:2:1: error[E_MODULE_HEADER]: file must begin with a module declaration
  import os
  ^
```

## The hint table, and how agreement is tested

`src/parser.zig` holds one table, indexed by `HintForm`:

```zig
pub const declaration_hints = [_]DeclarationHint{
    .{ .form = .union_cases, .idiom = "union-cases", ... },
    .{ .form = .module_constant, .idiom = "module-constant", ... },
    .{ .form = .method, .idiom = "method", ... },
    .{ .form = .from_import, .idiom = "from-import", ... },
};
```

Each call site names a form, not a string: `self.hintHere(.method)`,
`self.hint(.union_cases, span, caseCommaMessage(head), previous_case)`. The
helper looks the row up, prints the row's message as the primary diagnostic and
attaches the row's accepted spelling. `caseCommaMessage` reads the union row and
only varies the noun, so `union`, `enum` and `result` bodies cannot drift from
each other.

`velocity/friction/classifier.json` keeps the same idioms in a `hints` array and
carries an `E_SYNTAX` rule for each one. Two tests fail when the two sides
diverge:

1. `src/declaration_hints_test.zig` (`PARSER-HINT-5`), which runs in the gate:
   it reads `velocity/friction/classifier.json` from the repository root at test
   time (`std.Io.Dir.cwd().readFileAlloc`, with `../` and `../../` fallbacks),
   parses it with `std.json`, and asserts the `hints` array is exactly the
   parser's idioms in the same order and that every hinted idiom has an
   `E_SYNTAX` rule. An unreadable classifier is a failure
   (`error.ClassifierUnreadable`), never a skip. This is the mechanism
   `@embedFile` cannot provide: `@embedFile("../velocity/...")` is rejected with
   "embed of file outside package path" (verified with a scratch module before
   choosing this route), and `src/` has no copy of the classifier that could be
   embedded instead.
2. `tests/parser_hints.py` — the same set comparison from the other side (it
   scrapes the `declaration_hints` block out of `src/parser.zig`), plus the part
   the Zig test cannot do without a regex engine: it applies the classifier's
   own rows to the probe sources and asserts the first matching `E_SYNTAX` row
   answers `module-constant` for `a37`, `method` for `a38`, `from-import` for
   `a39` and `union-cases` for the union source. With `--compiler PATH` it also
   runs the four probes and the headerless script and checks the code, the
   `line:column`, the `alternative:` text and the exit statuses.

Both were falsified by deleting `method` from the classifier's `hints` array:
the Zig test failed (`expected 4, found 3`) and the driver exited 1 with
`parser idioms [...] != classifier hints [...]`. Restoring the file made both
pass again.

One honest gap: `tests/parser_hints.py` is **not wired into `build.zig`**, which
is outside this package's file ownership. The gate-running half of the
acceptance is the Zig test above; the driver is runnable by hand
(`python3 tests/parser_hints.py --compiler zig-out/bin/mylang`) and is the
natural candidate for the next `zig build test-…` step.

### The note shape that shipped

`src/diagnostic.zig` landed `Role = enum { related, origin, requirement,
alternative }` with `Related.role`, and **no `fix` field**. Every hint therefore
ships as a related note with `.role = .alternative` (the shape W0 froze and the
one lane C's C3 counts), rendered as `  alternative: <accepted spelling>`. For
the union case the note's message is the fix instruction — `insert a comma after
the previous case` — and its span is the previous case, so the data needed for a
mechanical edit is present even though `diagnostic-v1` has no edit field. If a
`fix` role lands later, the change is one line inside `Parser.hint`.

## Commands and observed output

```
$ zig build
guardian: run-all: 88 check(s) passed — diff-scoped vs b8f6ec3f…
(install succeeds; zig-out/bin/mylang rebuilt)

$ zig build fmt-check
(exit 0)

$ python3 scripts/focused_test.py units "headerless"
selected: 13 test(s)
result: PASS - 13 passed, 0 failed, 0 skipped

$ python3 scripts/focused_test.py units "one table"
result: PASS - 11 passed, 0 failed, 0 skipped

$ python3 tests/parser_hints.py --compiler zig-out/bin/mylang
hint table and classifier agree on 4 forms
probes print the hinted message, span and accepted spelling
(exit 0)

$ zig build test-cli          # integration root, whole file
guardian/test: PASS — 153 passed

$ zig build test-docs
Doc examples: 325 files scanned, 675 blocks found, 154 run, 41 checked, 10 skipped, 0 mis-tagged, 0 failed

$ zig build test-lang
231 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 65 programs

$ ./zig-out/bin/mylang doc-coverage .
doc-coverage: 0 failures

$ zig build test --summary all
Build Summary: 60/60 steps succeeded; 1405/15942 tests passed (14537 skipped)
test success
```

While packages were still landing, one whole-root `zig build test-units` run
reported 1245/1252 with the seven failures in `reference_test.zig`,
`prelude_scalar_test.zig` and `python_core_test.zig`; all were other packages'
in-flight edits and all are green in the final gate above. My new tests and
every parser/loader-adjacent test (`module`, `union`, `enum`, `variant`,
`record`, `import policy`, `standard modules compose`) pass.

## Design notes and cross-package findings

- **The loader's one policy is shared, not copied.** `standardImportOpening` in
  `src/project.zig` decides "headerless file whose every leading import names an
  embedded standard module"; `Parser.standardImportScript` calls the same
  function, so `parseModule` (used by `fmt-module`, `list-declarations` and
  `interfaces`) and `Project.header` cannot disagree. `parser.zig` now imports
  `project.zig`; the edge is acyclic (`project.zig` does not reach `parser.zig`).
- **A regression I introduced and fixed inside the session:** restructuring
  `Project.header` dropped `expect(.semicolon)` after the module name. Files
  whose header is newline-terminated were unaffected (the loader synthesizes the
  terminator), but `module main; import core.service; import io.fs;` — the shape
  `src/import_policy_test.zig` uses — silently loaded zero imports.
  `import_policy_test` caught it; `list-modules` on a scratch project then
  matched the baseline again. It is worth recording because *no* new test in D2
  or S1(c) covers the semicolon-terminated header: only the pre-existing suite
  did.
- **`mylang fmt` does not follow `usesModuleSyntax`.** `fmt` on a module file
  (headered or headerless) still runs the single-unit parse and reports
  `E_SYNTAX: unexpected token; expected def` at line 1; `fmt-module <file>`
  formats it correctly. Pre-existing for headered files (the frozen baseline
  behaves identically), but S1(c) now makes `check`, `run`, `build` and
  `list-declarations` accept the headerless form while `fmt` does not.
- **Headerless `check` goes through `check-project`.** `main.zig` routes any
  `usesModuleSyntax` file to the project loader, so a headerless standard-import
  script is checked with the project policy path (including `mylang.json`
  validation) rather than the single-unit path. The program is still one user
  unit — the embedded modules are the only other modules in the graph — but a
  project configuration file in the directory now applies to it.
- **Trailing comma in a case list.** `union Event:` with `a,` / `b,` still
  reports `E_SYNTAX: unexpected token; expected a name` at the next declaration.
  D2 was scoped to targeted messaging, so accepting the trailing comma was left
  alone; it is the same "shape an agent writes first" family and is a candidate
  for a follow-up.
- **Classifier regex coverage vs. hint coverage.** The parser hints *any* bare
  top-level assignment (including `counter = 0`, probe `a36_module_global`),
  while the existing `module-constant` regex is uppercase-only
  (`^[A-Z_][A-Z_0-9]*\s*=`). The tables agree on the idiom set, which is what
  the acceptance requires, but a lowercase bare assignment classifies as
  `unclassified`. Widening that row to lowercase would match ordinary
  assignments inside function bodies in a line-based classifier, so it was left
  as the M1 owner's call.
- **The headerless entry must be a valid module name.** `run`/`check` route it
  through `listModules`, which requires an `<identifier>.my` entry file; a
  headerless script named `my-script.my` reports the entry-name error instead of
  the old `E_MODULE_HEADER`. Pre-existing for any file that opens with `import`,
  and unchanged by this package.

## Spec tags

| Tag | Test |
| --- | --- |
| `PARSER-HINT-1` | `src/declaration_hints_test.zig`: union, enum and result cases name the comma rule, the fix and the span |
| `PARSER-HINT-2` | bare and annotated module-level assignment |
| `PARSER-HINT-3` | `def` as the first member and after a declared field |
| `PARSER-HINT-4` | `from dataclasses import dataclass` |
| `PARSER-HINT-5` | `declaration_hints` ≡ classifier `hints`, every form has an `E_SYNTAX` rule, unreadable classifier fails |
| `HEADERLESS-STD-IMPORT-1` | `parseModule` and `Project.load` accept `import strings` without a header |
| `HEADERLESS-STD-IMPORT-2` | project import, imported headerless file and no-import file keep `E_MODULE_HEADER` at the first token |
