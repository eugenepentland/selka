# L1 — Untested-export lint counts test reachability

Package: **L1** of [`agent-usefulness-implementation-plan-2026-09-20.md`](../agent-usefulness-implementation-plan-2026-09-20.md).
Baseline: [`baseline-2026-09-20.md`](baseline-2026-09-20.md) (correction 3 governs the port number).
Status: **implemented; focused tests and the new spec tag pass.** Measurement
binary is the working-tree compiler; see *Binary identity* for why the installed
`zig-out/bin/mylang` was still the baseline at capture time.

## What changed

`untested-export` no longer builds its own direct-callee set. It reads the shared
`tests_index.zig` reachability index that `mylang tests-for` and the
`list-interfaces` `tests(N)` column already use, built **once per lint run**:

- `--profile=agent` (the default): an export any discovered test reaches,
  directly or transitively, is tested and produces no `L_UNTESTED_EXPORT`
  finding. An export no test reaches is reported as
  `exported <name> is not reached by any discovered test`.
- `--profile=strict` and `--profile=safety`: the direct-call fact is kept. An
  export no test calls directly but a test reaches through other calls is
  reported as
  `exported <name> is reached only transitively; no test calls it directly`.
  An export no test reaches at all keeps the old wording,
  `exported <name> is not called directly by any test_ function`.

The rule's modes are unchanged (`.agent = .report`, `.strict = .block`,
`.safety = .block`), and the related note that every declaration-naming finding
carries now reads the same index object the rule judged, not a second walk.

## Files changed

| File | Change |
| --- | --- |
| `src/lint.zig` | `Reachability { profile, index }` field on `RuleContext`; `buildReachabilityIndex` (discovery + call graph + inversion, the same three calls `navigation.renderTestsFor` makes); `evaluate` builds the index once and hands it to the rule context and to `attachReachabilityNotes`; `runUntestedExport` rewritten on `Index.answer`; `attachReachabilityNotes` takes the shared index instead of building its own; rule description updated. |
| `src/lint_test.zig` | Only the `// spec: LINT-5` test body, per the lead's authorization: it now asserts the **strict** finding carries the transitive-only wording with the `main::test_end_to_end` related note, and that under **agent** there is no `L_UNTESTED_EXPORT` finding while the note still rides the export's `L_UNDOCUMENTED_EXPORT` finding. Nothing else in the file changed. |
| `src/lint_reach_test.zig` | New spec-tagged tests: the profile split (agent silent on a transitively reached export, strict reports it as transitive, strict keeps the direct-only wording for a genuinely unreached export, severity report vs block) and lint/`tests-for` agreement on every export of one fixture. |
| `src/root_test.zig` | One appended line in the existing lint import block: `_ = @import("lint_reach_test.zig");`. |
| `SPEC.md` | One appended bullet, `- [LINT-7]` (see *Spec tags*). |
| `docs/tooling/lint.md` | `untested-export` rule row; a paragraph in *Profiles and the report/block split* describing the two facts; the related-note paragraph now says the note and the verdict read one index. The rest of the doc was verified against the code and left alone. |

## Spec tags

`LINT-1` describes the rule's modes, `LINT-5` the shared index for related notes,
`LINT-6` the advisory rules; none of them promised the direct-call default. The
new behaviour therefore has its own tag, `[LINT-7]`, appended to `SPEC.md` and
carried by the new test file. The edited `LINT-5` test keeps its tag because the
related-note behaviour it pins is unchanged; it additionally exercises the
`LINT-7` split.

## Binary identity (important)

`zig build` gates installs on a green Guardian run, and at capture time the tree
was red in **other packages' files**. Guardian reported **no finding in any file
this package owns** — specifically no unlinked `LINT-7` tag, no orphan-file or
test-reachability finding for `src/lint_reach_test.zig`, and no doc-comment,
formatting, assertion or error-path finding in `src/lint.zig`, `src/lint_test.zig`
or `src/lint_reach_test.zig`. At the last check the two remaining failures were
both in the reference package's `src/reference_test.zig`: 22 unlinked
`REFERENCE-*` spec tags and one test with no assertion. Consequently:

- `zig-out/bin/mylang` was still the baseline binary
  (`sha256 2c2ed027…`, byte-identical to `mylang-baseline-20260920`) and was used
  only for *before* numbers.
- *After* numbers come from `zig-out/focus/mylang`, which the **same `install
  mylang` step** produces from the current tree; only the destination differs
  (`zig-out/focus/` rather than `zig-out/bin/`, because the focused test steps
  must not run the install gate). The results were reproduced on three separate
  tree builds (`71b81aa9…`, `fd0ccf55…`, `21733e7f…`): 22 → 8 on the scratch
  port entry, 14 strict transitive findings, 42 on `main.my`, agreement `yes`.
  `zig fmt --check src/lint.zig src/lint_reach_test.zig src/lint_test.zig
  src/root_test.zig` is clean; `zig build fmt-check` failed only on
  `src/reference_text.zig` and `src/declaration_hints_test.zig`, both other
  packages'.
- The one outstanding item is a final re-run against `zig-out/bin/mylang` after
  the other packages clear their Guardian findings and the default install
  succeeds. No source change is expected to result from it.

## Acceptance evidence

### The fixture that genuinely exercises transitive reach

The plan's premise ("ten findings on `sexpr/ast.my` accessors every parser test
reaches") does not reproduce on the port entry itself: `main.my` imports no
`tests.*` module, so the checked program contains **no test functions at all**
(baseline correction 3). `L_UNTESTED_EXPORT` and `tests-for` therefore agree
trivially — both answer "nothing reaches this".

Two fixtures supply the missing graph:

1. **In-repo unit fixture** (`src/lint_reach_test.zig`), one module:
   `public def as_text` ← `def render` ← `def test_render`, plus
   `public def orphan` that no test reaches and a `main`.
   `as_text` is `direct (0)` and `reached-by (1)`, so it is the genuine
   transitive case; `orphan` is the genuine unreached case.
2. **The port's own code and tests**, measured through a throwaway entry in a
   scratch copy of the port (never inside the repo):

   ```
# doc: not-mylang
   cp -r experiments/sexpr-port /tmp/l1-port
   cat > /tmp/l1-port/l1_check.my <<'EOF'
   module l1_check
   import sexpr.ast as ast
   import sexpr.parser as parser
   import sexpr.printer as printer
   import sexpr.tokenizer as tk
   import sexpr.view as view
   import tests.ast_test
   import tests.parser_test
   import tests.printer_test
   import tests.roundtrip_test
   import tests.smoke_test
   import tests.tokenizer_test
   import tests.view_test

   def main() -> int:
       return 0
   EOF
   ```

### Port, before and after, with the reason

```
$ ./zig-out/bin/mylang-baseline-20260920 lint experiments/sexpr-port/main.my --profile=agent | grep -c L_UNTESTED_EXPORT
42
$ ./zig-out/focus/mylang          lint experiments/sexpr-port/main.my --profile=agent | grep -c L_UNTESTED_EXPORT
42
$ ./zig-out/focus/mylang tests-for experiments/sexpr-port/main.my 'sexpr.ast::as_text'
tests-for sexpr.ast::as_text
  direct (0):
  reached-by (0):
```

Unchanged at 42 **because the checked graph contains no test function**: lint and
`tests-for` both need an entry point, `main.my` imports no `tests.*` module, and
a rule cannot count reachability that the program does not contain. This is the
honest reading of correction 3, not a null result for the rule — the code the
plan names is exercised in the next measurement.

```
$ ./zig-out/bin/mylang-baseline-20260920 lint /tmp/l1-port/l1_check.my --profile=agent | grep -c L_UNTESTED_EXPORT
22
$ ./zig-out/focus/mylang          lint /tmp/l1-port/l1_check.my --profile=agent | grep -c L_UNTESTED_EXPORT
8
$ ./zig-out/focus/mylang lint /tmp/l1-port/l1_check.my --profile=agent | grep -o 'exported [a-z_.:]*'
exported byte_builder::append_byte
exported byte_builder::append_float
exported byte_builder::append_text
exported byte_builder::reserve
exported sexpr.ast::as_atom
exported sexpr.ast::as_items
exported sexpr.ast::as_string
exported sexpr.ast::span_of
```

The 14 that disappear are exactly the exports `tests-for` answers `reached-by
(N)` for with `N > 0` (e.g. `sexpr.ast::as_text` reached by 5 tests,
`sexpr.ast::max_source_bytes` by 55, `sexpr.parser::parse` by 54, every
`byte_builder` accessor the printer uses by 30). The 8 that remain are exactly
the exports `tests-for` answers `reached-by (0)` for, so the port still reports
genuinely unreached accessors (`as_atom`, `as_items`, `as_string`, `span_of`).

### `lint` and `tests-for` agree on every export, by construction

Both now call the same three functions (`tests_index.discoveredTests`,
`tests_index.callGraph`, `tests_index.build`) and the rule reads `Index.answer`
directly, so there is one walk and no second notion of "test" or "call". Checked
against the third consumer as an independent surface —
`list-interfaces`' `tests(N)` column — over every export, using
`/tmp/l1_agree.py` (compares the set of exports with `tests(0)` to the set of
`L_UNTESTED_EXPORT` findings under `agent`):

```
$ python3 /tmp/l1_agree.py ./zig-out/focus/mylang /tmp/l1-port/l1_check.my
  exports with tests(0): 8
  exports with tests(N>0): 148
  L_UNTESTED_EXPORT findings: 8
  tests(0) but not flagged: []
  flagged but tests(N>0): []
  AGREEMENT: yes

$ python3 /tmp/l1_agree.py ./zig-out/focus/mylang examples/named-constraints/main.my
  exports with tests(0): 2
  exports with tests(N>0): 0
  L_UNTESTED_EXPORT findings: 2
  tests(0) but not flagged: []
  flagged but tests(N>0): []
  AGREEMENT: yes
```

(`examples/named-constraints` is the only other in-tree entry with its own test
module; its tests are not imported by `main.my`, so it is an agreement check
rather than a second transitive case.)

### Strict-profile wording

```
$ ./zig-out/focus/mylang lint /tmp/l1-port/l1_check.my --profile=strict | grep -c L_UNTESTED_EXPORT
22
$ ... | grep -c 'reached only transitively'
14
$ ... | grep -c 'not called directly'
8
```

Examples:

```
sexpr/ast.my:106:12: warning[L_UNTESTED_EXPORT]: untested-export: exported sexpr.ast::as_text is reached only transitively; no test calls it directly
sexpr/ast.my:81:12:  warning[L_UNTESTED_EXPORT]: untested-export: exported sexpr.ast::as_items is not called directly by any test_ function
```

The strict *count* is unchanged (22 before and after): every export the old rule
flagged is still flagged, 14 of them now with the factually different wording.
That is the intended split — the two profiles report different facts, not the
same fact at different thresholds.

### `--gate` behaviour

Rule modes are untouched, so exit statuses are unchanged for every report that
does not involve reachability, and for reachability reports they change only
where the fact changed:

| Command | Baseline | After |
| --- | --- | --- |
| `lint /tmp/l1fix/main.my --profile=agent --gate` (transitive export) | exit 0 | exit 0 |
| `lint /tmp/l1fix/main.my --profile=strict --gate` (same file) | exit 3 | exit 3 |
| `lint /tmp/l1dead/main.my --profile=agent --gate` (dead private only, no reachability) | exit 3 | exit 3 |
| `lint /tmp/l1-port/l1_check.my --profile=agent --gate` | exit 0 (22 report findings) | exit 0 (8 report findings) |

The one intended exit-status change is a project that *configures*
`untested-export` to block while running the default `agent` profile: a
transitively reached export no longer refuses, which is the point of the package.
Under both stock profiles the exit statuses are identical before and after.

### Existing tests

```
$ python3 scripts/focused_test.py units lint
selected: 26 test(s)
result: PASS - 26 passed, 0 failed, 0 skipped

$ python3 scripts/focused_test.py units lint_reach
selected: 13 test(s)
result: PASS - 13 passed, 0 failed, 0 skipped

$ zig fmt --check src/lint.zig src/lint_reach_test.zig src/lint_test.zig src/root_test.zig
(clean)
```

(The selected counts include the unnamed test blocks of the shared root that
every focused run executes, and other packages keep adding them, so the numbers
drift; both roots passed on every run while L1 was in the tree. `lint_reach`
itself contributes two named tests.)

The only pre-existing lint test that had to change is the `LINT-5` one, and only
because its fixture is a reachability report: it asserted a default-profile
`L_UNTESTED_EXPORT` finding for a transitively reached export, which is exactly
the finding `agent` now suppresses. It now asserts the strict finding and the
agent silence. No other lint, config or store test changed.

## Design: one index, built once

```zig
// evaluate()
var reach = try buildReachabilityIndex(scratch, request.compilation);
defer reach.deinit();
...
.reach = .{ .profile = profile, .index = &reach },   // RuleContext
...
try attachReachabilityNotes(scratch, &facts, &reach, findings.items);
```

`buildReachabilityIndex` performs the identical three calls
`navigation.renderTestsFor` performs:

```zig
const modules = try compilation.index.moduleSyntax(scratch);
const call_graph = try tests_index.callGraph(scratch, program);
const discovered = try tests_index.discoveredTests(scratch, program, modules);
return tests_index.build(scratch, program, call_graph, discovered);
```

Notes on the two deliberate structural choices:

- The test set comes from `tests_index.discoveredTests`, **not** from lint's own
  `facts.tests` filter over `testRoots`. Lint's filter tolerates a generic test
  the shared discovery excludes; using the shared discovery for reachability is
  what makes the verdict and the command agree by construction. `facts.tests`
  still drives the test-hygiene rules, unchanged.
- The index is built even when no test is discovered, so the run has one code
  path; with no discovered tests every `reached` list is empty and the agent
  profile reports every export, which is the only honest answer for a graph with
  no tests.

## Remaining limits

1. **No new reachability for graphs without tests.** If the entry does not
   import the modules that hold the tests, lint cannot see them. On the port's
   `main.my` that is all 42 findings (before and after). Making lint accept a
   separate test entry, or having a project declare test roots, is a different
   package (W0/F1 territory); L1 does not change test discovery.
2. **Static reachability only.** A test that reaches an export through a
   function value (`invoke` site, callback) is not counted, by the same rule the
   quality call graph and `tests-for` already apply. This is a documented
   exclusion in `tests_index.zig`, unchanged here.
3. **`safety` follows `strict`.** The plan freezes `agent` vs `strict`; `safety`
   is the block-everything profile, so it keeps the direct-call fact too. If the
   intended reading is that `safety` should also accept transitive reach, this
   is a one-line change (`profile != .strict`).
4. **Installed binary re-run outstanding** — see *Binary identity*; blocked by
   other packages' Guardian findings, none of them in this package's files.
5. The scratch port copy lives in `/tmp/l1-port`; it is evidence, not a repo
   artifact, and is reproducible from the command block above.

## Cross-package findings

- **Correction 3 confirmed, with a twist worth recording in the ledger.** With
  the port's own tests in the graph, the baseline reports only 22
  `L_UNTESTED_EXPORT`, not the 40 seen through `main.my`, and 14 of the 22 are
  transitively reached accessors — the defect the plan describes, in a
  measurable form.
- **`docs/audits/real-project-readiness-2026-09-18.md:181`** records
  "`L_UNTESTED_EXPORT` and `list-interfaces` `tests(0)` miss tests that call an
  export from another module". After L1 the lint verdict is the same index that
  produces `tests(0)`, and the measurement above shows them equal on all 156
  exports of the port, so whatever remains of that item is on the `tests-for`
  side, not the lint side.
- **`docs/audits/quality-and-maintainability-2026-09-18.md:302`** specifies
  `untested-export` as "no test calls it directly"; that historical audit now
  describes the `strict` profile only. Not edited (historical evidence), noted
  here so a later reader does not treat it as current.
- **Install gating.** `zig build` refuses to install while any Guardian check
  fails anywhere in the tree, so one package's red file freezes every other
  package's `zig-out/bin/mylang`. Several packages in this tree hit that during
  L1 (`src/sema.zig`, `src/parser.zig`, `src/project.zig`,
  `src/friction_log_test.zig`, `src/buffer_operations.zig`,
  `src/prelude_builtins.zig`, `src/reference_text.zig`,
  `src/declaration_hints_test.zig`). The `test-units` copy at
  `zig-out/focus/mylang`, produced by the same `install mylang` step from the
  same tree, is what made measurement possible; a documented escape hatch for
  parallel work would help every later package.
