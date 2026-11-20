# Linting a project

`selka lint` runs the project-verification layer over guest (`.selka`) code. It
loads the project exactly as `check-project` does, runs every enabled rule over
the checked program, and reports findings with a fourth diagnostic code family,
`L_*`. Rules never change the inner check-run-test loop: they report during
development and refuse only at the commit gate.

## `selka lint`

```console
$ selka lint src/app/main.selka
lint: 2 finding(s): 0 blocking, 2 report, 0 waived, 0 accepted
$ selka lint src/app/main.selka --gate
app.selka:12:1: error[L_DEAD_PRIVATE]: dead-private: private app::helper has no call site
  func helper(value: int) -> int:
  ^
lint: 1 finding(s): 1 blocking, 0 report, 0 waived, 0 accepted
$ echo $?
3
```

The command takes the entry file and these options:

| Option | Meaning |
| --- | --- |
| `--gate` | Make every `block` rule refusing (exit 3) and raise its findings to error severity. |
| `--json` | Render findings as `diagnostic-v1` JSON Lines on stderr, always complete. `--diagnostics=json` does the same. |
| `--all` | List every finding in full instead of one count line per report-only rule. |
| `--profile=NAME` | Override the configured profile for this run: `agent`, `strict` or `safety`. |
| `--accept` | Record the current findings in the baseline store under `.selka/lint/`. |
| `--against=REF` | Judge the working tree against reference `REF` (a git revision), with or without `--gate`: `change-without-test` evaluates the diff, and findings in a declaration changed since `REF` print in full. |
| `--rule=NAME` | Turn on, at `report`, one rule the profile and the project leave off (today only `dead-write`). A rule already on keeps its mode; an unknown name is a usage error (exit 2). |
| `--copies` | Print how many `copy(...)` calls the program writes and what names each, in place of the findings ([Counting copies](#counting-copies)); with two or more entry files, one count for the union of what they reach. It takes neither `--gate` nor `--accept`. |

Exit statuses are `0` (valid, nothing blocking), `1` (a source, type, effect or
ownership error, with no rule evaluated), `2` (usage or configuration failure)
and `3` (valid source with at least one blocking finding, or a `--gate` run whose
[loop analysis failed](#when-the-analysis-behind-the-loop-rules-fails)).

## What a run prints

A run prints in full the findings an agent has to act on — the ones that block
in that run, and the ones in a declaration changed against `--against REF` — and
prints every other finding as one count line per code:

```console
$ selka lint main.selka
L_UNTESTED_EXPORT: 32 findings (selka lint --all lists them)
L_DEAD_EXPORT: 1 finding (selka lint --all lists them)
lint: 200 finding(s): 0 blocking, 200 report, 4 waived, 0 accepted
```

The count line carries the code, so a rule that fires a lot still says where to
look, and the closing `lint:` line still carries the totals. `--all` lists every
finding in full, and `--json` is unchanged and always complete. A finding that
refuses under `--gate` is never summarized: it prints in full above the count
lines of this run, so a gate run reads every finding that exits 3. `--against=REF`
prints the findings in the declarations the working tree changed since `REF` in
full even without `--gate`, so a review of a diff reads the diff's own findings
and summarizes the standing tree.

The target is a default output of at most 30 lines for a project that blocks
nothing, which the count line makes reachable: a selka project with 300 findings
prints a dozen count lines and its closing summary line rather than 300
diagnostics.

## Profiles and the report/block split

A project with no `lint` object in `selka.json` runs the `agent` profile:
correctness rules report, style rules stay silent, and nothing refuses until
`--gate`. `strict` blocks everything blockable; `safety` additionally demotes
size budgets so a large legacy project can adopt the gate without a wall.

The profile selects the fact a rule reports, not only its severity.
`untested-export` is the one rule with two facts: under `agent` an export any
discovered test reaches, directly or transitively, is tested, so a helper an
end-to-end test exercises through another function is not reported at all;
under `strict` (and `safety`) the rule keeps the narrower direct-call fact and
reports such an export as "reached only transitively", while an export no test
reaches at all is reported as not called directly. A project that wants the
direct-call question answered without refusing can select `"profile": "strict"`
and list `untested-export` under `report`: the lists below override the
profile's severity, while the profile still chooses which fact the rule reports.

```json
{
  "version": 2,
  "lint": {
    "profile": "agent",
    "on_build": "report",
    "warnings": "deny",
    "min_chars": 12,
    "block":   ["untested-export"],
    "ratchet": ["function-length"],
    "report":  ["dead-export"],
    "rules": {
      "test-coverage":   {"exempt": [{"name": "cli.usage", "reason": "exercised by the binary's own CLI tests"}]},
      "function-length": {"max": 80, "hard_max": 200, "recover_pct": 20}
    }
  }
}
```

The per-rule `block`/`ratchet`/`report` lists override the profile with
precedence block, then report, then ratchet. `on_build: "block"` is the only
setting that makes a plain `selka lint` (no `--gate`) refuse. `min_chars`
(default 12) is the non-whitespace length floor for `undocumented-export`. A
`lint` object requires `selka.json` `version: 2`; a version 1 document keeps
parsing without one. The configured `lint` object participates in verdict cache
identity exactly as `import_policy` does, so changing a rule mode invalidates an
earlier green.

`warnings: "deny"` is the one setting that reaches into the inner loop: with it,
a checker `W_*` diagnostic makes `check` and `check-project` exit 1 instead
of reporting and exiting 0. The warning is still printed, and the check does
not cache a green verdict. `run` and `run-project` do not enforce this setting.
The default, `report`, leaves the inner loop untouched.

## Rules

| Rule | Code | Default (`agent`) | What it finds |
| --- | --- | --- | --- |
| `noalloc-allocates` | `L_NOALLOC_ALLOCATES` | block in every profile | A written `noalloc` function has a Core allocation witness, unresolved call, or unsupported concrete body. Plain lint reports it; `--gate` exits 3 unless waived with a reason. |
| `needless-copy` | `L_NEEDLESS_COPY` | block in every profile | A `copy(value)` the checker proved carries no value: its source is only read by the use, or the copy is the source's last use. It reads the checker's `W_NEEDLESS_COPY` the way `noalloc-allocates` reads `E_NOALLOC_ALLOCATES`, so `selka fix` deletes the copy and a plain run reports it. Never adopted by a baseline; waive the site with a reason. |
| `byte-set` | `L_BYTE_SET` | report only | An or-chain of three or more `value == literal` tests of one plain integer value against bytes (`c == 43 or c == 45 or c == 47`). It reads the checker's `W_BYTE_SET`; `value in b"+-/"` tests the same set and `selka fix` writes it. A `float` or an Option value (`int?`) draws no finding: `in b"..."` is refused there. |
| `range-chain` | `L_RANGE_CHAIN` | report only | Two comparisons that bound one plain value from both sides (`x >= a and x <= b`). It reads the checker's `W_RANGE_CHAIN`; `a <= x <= b` is one chain and `selka fix` writes it. |
| `literal-match` | `L_LITERAL_MATCH` | report only | An `if`/`elif` chain of three or more `x == literal` tests of one plain value against integers, strings or bytes. It reads the checker's `W_LITERAL_MATCH`; a literal `match` compares the value once and `selka fix` writes it, with `case _:` for the `else`. A value of an Option type (`bytes?`), a `str` or `bytes` field or element, and a value in a generic function draw no finding: a literal arm is refused there. |
| `pattern-shorthand` | `L_PATTERN_SHORTHAND` | report only | A pattern field written `name=name`, in the case an arm names. It reads the checker's `W_PATTERN_SHORTHAND`; the bare `name` binds the same field and `selka fix` drops the label. A field of a nested pattern (`case Some(item(value=value))`) draws no finding: the checker refuses the bare form there (`E_NAMED_PATTERN`), so the label stays (FR49). |
| `option-try` | `L_OPTION_TRY` | report only | An Option `match` on a call result whose `None` arm only returns `None`, ending a block of a function that returns an Option. It reads the checker's `W_OPTION_TRY`; `const x = try call()` says the same and `selka fix` writes it. |
| `else-is-try` | `L_ELSE_IS_TRY` | report only | A bind-or-else (`const x = call() else Err(e):`) whose `else` block is only `fail e`, or only `return None` in a function that returns an Option. It reads the checker's `W_ELSE_IS_TRY`; `const x = try call()` unwraps the value and passes the failure on the same way, and `selka fix` writes it. A block that does anything else is the reason to use `else`, and draws no finding. |
| `match-else` | `L_MATCH_ELSE` | report only | A two-arm `match` over an Option or a Result whose `None` or `Err` arm leaves (`return`, `fail`, `break`, `continue` on every path). It reads the checker's `W_MATCH_ELSE`; `const x = value else:` (`else Err(e):` for a Result) with that block, followed by the other arm's statements, says the same and `selka fix` writes it. |
| `match-is` | `L_MATCH_IS` | report only | A two-arm `match` over an Option or a Result one of whose arms does nothing (`pass`), or whose success arm leaves while the other binds nothing. It reads the checker's `W_MATCH_IS`; `if value is Some(x):` (or `is None`, `is Ok(x)`, `is Err(e)`) says the same and `selka fix` writes it. |
| `linear-search-in-loop` | `L_LINEAR_SEARCH_IN_LOOP` | block in an `--against` diff | A list declared outside a loop is searched (`lists.contains`, a list `index`) in that loop while the loop also appends to it, so every probe walks what the loop has built. The rewrite is a `set` or `dict` kept alongside. A search on a list the loop does not change only reports. |
| `shift-in-loop` | `L_SHIFT_IN_LOOP` | block in an `--against` diff | A list declared outside a loop loses its front element or grows at the front (`lists.pop_at(..., 0)`, `lists.insert(..., 0, ...)`, a native index-0 `pop_at`/`insert`) inside it, so every later element shifts. The rewrite is an index cursor, or B6's `deque`. |
| `sort-in-loop` | `L_SORT_IN_LOOP` | block in an `--against` diff | A list declared outside a loop is appended to and sorted in the same loop (`L = sorted(L)` or `L.sort()`), so it is re-sorted as it grows. The rewrite is one sort after the loop, or B6's `heap`. A list created inside the iteration and sorted once there is the negative shape. |
| `alloc-in-loop` | `L_ALLOC_IN_LOOP` | report only | A construction or conversion site the Core passes placed at loop depth 1 or more, read from the `cost --sites` rows: the same classification the build reports, never a second one. It names the site's kind and that kind's hint, reports only in a declaration changed against `--against REF`, and never refuses. |
| `copy-in-loop` | `L_COPY_IN_LOOP` | block in an `--against` diff | A copy the Core passes placed at loop depth 1 or more, read from the `cost --sites` rows. Under rule C every copy is written, so each one is a choice: the rule reports it in every declaration and refuses under `--gate` only in a changed one. The message is one line that names the zero-copy form which fits where the copy goes, with the section that teaches it: a borrow (the checker's `W_NEEDLESS_COPY` already proves the copy-free form), a move (`own x`, `take(mut x.f)`, `for x in own xs`: the source is not read again), a `spans.Span` into the source (the copy is a slice of `bytes` that is kept), an interned `symbols` key (the same `bytes` name, read from a place the loop does not write, is copied every iteration), for a `str` the loop that takes the elements (`for x in own xs`, since a span and a symbol hold `bytes` and are refused for `str`), or nothing more for a real transfer. It names the form and never repairs: `selka fix` writes the moves and borrows the checker proves, as `W_NEEDLESS_COPY`. The rows are those of the functions `main` reaches and, when the checked project has discovered tests (a `_test.selka` file linted as the entry has no `main`), of the functions each test reaches. A reasoned waiver takes a copy that is the point. See [Copies in a loop](#copies-in-a-loop). |
| `untested-export` | `L_UNTESTED_EXPORT` | report; block under `strict` | An exported function that no discovered test or docstring example reaches, directly or transitively, under `agent`; under `strict` and `safety` one that no test or example calls directly, where an export only reached transitively is reported with that wording instead. |
| `dead-private` | `L_DEAD_PRIVATE` | block | A private function with no call site and no use as a value or in a docstring example anywhere in the project. A function passed as a value (`values.sort(key=by_key)`) is used even though no call node names it, and so is one a module constant's initializer calls (`const N: int = triple(3)`), which the check folds away. |
| `undocumented-export` | `L_UNDOCUMENTED_EXPORT` | report; block under `strict` | An exported function, record, enum or union with no docstring, one under `lint.min_chars` non-whitespace characters, or one that merely restates the name. Public constants, entry points and tests are exempt. |
| `undocumented-module` | `L_UNDOCUMENTED_MODULE` | off; report under `strict` and `safety` | A project module without a module docstring. |
| `missing-example` | `L_MISSING_EXAMPLE` | off; report under `strict` and `safety` | A public function without a runnable `>>>` example or a reasoned waiver. Entry points and tests are exempt. |
| `long-example` | `L_LONG_EXAMPLE` | report only, never blocking | A docstring example whose expected output prints more than 120 characters on one line, or whose `>>>` block runs past 6 lines. It names the docstring line and suggests showing a property (`len(...)`, a prefix) instead of a dump. Waive a display that genuinely needs the whole value with a reason. |
| `change-without-test` | `L_CHANGE_WITHOUT_TEST` | block, but only under `--gate --against REF` | A declaration that changed since `REF` and whose callers are not tests that changed in the same diff. Judged against a diff, never the standing tree, and never suppressed by a baseline. |
| `test-no-assertion` | `L_TEST_NO_ASSERTION` | block | A test body whose every `return` is the literal `true` and which never asserts. |
| `test-conditional` | `L_TEST_CONDITIONAL` | block | A branch or match, or more than one loop, at a test body's top level. |
| `test-empty` | `L_TEST_EMPTY` | block | A discovered test with an empty body. |
| `waiver-reason` | `L_WAIVER_REASON` | always block | A `# lint: allow` comment with no `reason="..."`. |
| `function-length` | `L_FUNCTION_LENGTH` | block under `--gate` | A function over `rules.function-length.max` body lines (default 60). |
| `parameters` | `L_PARAMETER_COUNT` | block under `--gate` | A function over `rules.parameters.max` data parameters (default 5). A capability parameter is authority, not data, so it does not count. |
| `nesting-depth` | `L_NESTING_DEPTH` | block under `--gate` | A function over `rules.nesting-depth.max` control-nesting levels (default 5). Levels are counted in the source, not in a lowered form: `if`, `for`, `while` and `match` each open one level for their body, `elif` and `else` are siblings of their `if` (a chain counts one level however long), a bind-or-else (`const x = f() else:`) opens one level for its `else` block and none for the statements after it, `if`, `elif` and `while` over a binding `is` test (`while x is Some(y):`) count as the statement they are, `with` opens none, and the branches and loops the compiler synthesizes (slice bounds checks, `try`, literal-arm `match` chains) count nothing. |
| `call-nesting` | `L_CALL_NESTING` | block under `--gate` | One expression nesting more than `rules.call-nesting.max` calls (default 3). The finding names the innermost call to bind to a named `const` first. |
| `counting-while` | `L_COUNTING_WHILE` | block under `--gate` | `mut i = start` / `while i < bound:` / `i += 1`, where `for i in range(start, bound):` says the same thing. Only an exact shape reports: one initialization, one final step, and no `continue` that would skip it. |
| `copy-move` | `L_COPY_MOVE` | report only | A copy whose source is not read again, where a move replaces it and the rewrite is not certain: `take(mut x.f)` of a place declared with no `const` to make `mut` (a loop variable, one name of several), `options.take_or(own opt, default)` where a local named `options` or a comment is in the way or a statement around the copy holds `opt`, `for x in own xs` over a field, a list the function does not own or a list parameter a caller keeps, `match own` that an arm or a later line stops, and `from` that a caller stops. It reads the checker's `W_COPY_MOVE`, which carries no `fix`; see [Moves instead of copies](#moves-instead-of-copies). |
| `copy-for-store` | `L_COPY_FOR_STORE` | report only | A parameter that is `copy`-ed into storage, in one of the three storing shapes: a record field (`State(keys=copy(keys))`), an element or field assignment (`hub.conns[id] = copy(state)`), or a list write (`append(mut rows, copy(row))`). A statement that copies several parameters (a constructor with four `copy(...)` fields) gets one finding for each parameter, at that parameter's own `copy(...)`; a parameter copied twice in one statement is named once. A parameter that is already `own`, one that is `mut`, and one whose type holds no managed storage (a record of numbers: `own` on it is `E_OWN_MARKER`) get no finding, because declaring them `own` cannot be done or changes nothing. The value is then independently owned, so the finding suggests declaring the parameter `own` and passing `own arg` where every caller can give the value up. Report only: the copy is correct, and the change moves every caller's binding, so the author decides. See [Owned parameters](#owned-parameters). |
| `double-lookup` | `L_DOUBLE_LOOKUP` | block under `--gate` | One statement that reads a dictionary key and then writes the same key, for example `counts[key] = dicts.get(counts, key, 0) + 1` or `counts[key] = counts[key] + 1`. `dicts.add` and `dicts.append_to` probe once. |
| `data-clump` | `L_DATA_CLUMP` | block under `--gate` | A function that writes three or more of its caller's arguments and is called at two or more sites: the group is a record in waiting. Introduce the record and pass one argument. |
| `discarded-failure` | `L_DISCARDED_FAILURE` | block under `--gate` | A `_ = call()` whose value is a checked result: the failure is dropped without a decision. Handle the result, or waive the site with a reason. |
| `decision-points` | `L_DECISION_POINTS` | report only | A function over `rules.decision-points.max` decision points (default 10). Decisions are counted in the source: each written `if`, `elif`, `for` and `while` is one, a `match` is `arms - 1` (a `case _` included), each written `and` and `or` is one, and each `try` is one. The branches the compiler synthesizes (slice bounds checks, a literal-arm `match` chain, the `try` it lowers) count nothing. |
| `public-dict` | `L_PUBLIC_DICT` | block under `--gate` | A `public` function whose parameter or result type spells a bare `dict[...]`, so the shape it publishes is unnamed. Name it with a `type` alias. |
| `dead-export` | `L_DEAD_EXPORT` | report only | An exported declaration with no caller anywhere in the project; ambiguous for a library, so it never blocks. |
| `integration-tests` | `L_TEST_CAPABILITY` | report only | A discovered test whose parameters request `Filesystem`, `Network`, `Clock` or `Entropy` in a module outside `rules.integration-tests.modules` (default `*_integration`, `integration.*`). |
| `record-size` | `L_RECORD_SIZE` | report only | A `record` or `class` over `rules.record-size.max` fields (default 7). |
| `file-length` | `L_FILE_LENGTH` | report only | A module over `rules.file-length.max` code lines (default 1000). Blank and whole-line `#` comment lines do not count. |
| `bool-ops-per-condition` | `L_BOOL_OPS` | report only | One branch or loop condition combining more than `rules.bool-ops-per-condition.max` `and`/`or` operators (default 3). |
| `naming` | `L_NAMING` | report only | A function, parameter, local, `record` or `union` that is not snake_case/PascalCase or is on the vague-name list (`tmp`, `data`, `info`, `obj`, `mgr`, `Helper`, `Util`, `Manager`). Only a name the program wrote is judged: the owners the compiler makes for a hidden move (`consumed list` for `for x in own CALL():`, `temporary list`, `temporary option`, `temporary default`, `temporary payload`, `temporary result`) draw no finding, here or under `dead-write`. |
| `repeated-literal` | `L_REPEATED_LITERAL` | report only | An integer literal other than `0` or `1` appearing three or more times in one module. |
| `same-type-adjacent-params` | `L_SAME_TYPE_ADJACENT_PARAMS` | report only | Adjacent parameters sharing one non-capability type, where a keyword argument reads better. |
| `duplicate-body` | `L_DUPLICATE_BODY` | report only, never blocking | Two or more checked functions whose normalized bodies are identical. |
| `output-in-library` | `L_OUTPUT_IN_LIBRARY` | report only | A function whose checked body contains a print operation in a module outside `rules.output-in-library.modules` (default `main`, `*_cli`, `cli`, `cli.*`, `*_integration`, `integration.*`). |
| `sentinel-int` | `L_SENTINEL_INT` | report; block under `strict` | An `int` used as a sentinel: a function that returns a negative integer literal on some path and whose result a caller compares against a negative literal (or the `< 0`/`>= 0` presence guards), and a parameter or record field compared against `-1` in two or more places. Every finding names the `int?` rewrite. A function named `find` or `find_any` is exempt, because `-1` is that method's own contract. |
| `text-slice-octets` | `L_TEXT_SLICE_OCTETS` | report only, never blocking | A slice of a `str` whose end or start is an integer literal, a module constant, the length of a text literal or constant, an expression over those, or the other bound plus or minus a literal (`kind[0:1]`, `text[0:WIDTH - 1]`, `text[at:at + 1]`, `text[2:]`, `line[len("content-length:"):]`; quiet where a `strings.starts_with` or `ends_with` of the same literal or constant guards the cut): cuts that count octets without having found them, which trap `R_TEXT_BOUNDARY` at the first text whose character spans the cut. See [A text cut at a count of octets](#a-text-cut-at-a-count-of-octets). |
| `dead-write` | `L_DEAD_WRITE` | off in every profile; report only under `--rule=dead-write` | A write to a local, to a field or element of a local, or a call that writes a local (`append(mut x, ...)`, `sets.add(mut x, ...)`, `helper(mut x)`), when no path from the write to the function's end reads the local again. A write to a `mut` parameter or through a `match mut` binding reaches the caller and is never reported. See [Writes nothing reads](#writes-nothing-reads). |

A file whose first line is a `#` comment starting `generated by …`, in any letter case
(`# generated by …` or `# GENERATED by …`), is exempt from
every rule, because its text is a build product rather than a review surface: lint
drops its findings before any mode resolves, so neither a plain run nor `--gate` sees
them. An imported standard-library module is never the project's review surface
either: its findings are dropped the same way, unless the linted entry is itself in
the standard library.

The three documentation rules exempt `*_test.selka` modules and the standard
library. [`selka release check`](release-docs.md) evaluates them as blocking in
its docs step under every profile, while its lint step evaluates the other rules.
A reasoned waiver applies in both commands. Module waivers go immediately before
the first declaration, after imports.

The section-9 advisory rules are `.report` under `agent`, `strict` and
`safety`: they measure, print and never refuse. `integration-tests` is likewise
report-only, but a test in a matching module is exempt by construction, so the
default `*_integration` / `integration.*` globs keep a project's own integration
suite quiet.

A finding that names a declaration also carries the discovered tests that reach
it as a related note, from the same index `selka tests-for` answers from and
the same one the `untested-export` verdict reads, so the report says which test
to extend without a second command and cannot claim a declaration is unreached
where `tests-for` names a test.

A docstring example is code and counts for the reachability rules: a declaration
an example names is used, and an example is a test of what it calls (directly,
and under `agent` also transitively). A private helper that only its function's
example calls is therefore not `dead-private`, and an exported function whose
only caller is its example is not `untested-export`. The reading is syntactic
and uses the project's own declarations, its module first and then its imports.


## Writes nothing reads

With value semantics and no aliases, a write to a local that no later read can see changes nothing: it is dead code,
or an update made on a copy and lost. `dead-write` finds such writes. It is off in every profile, because the
compiler accepts them on purpose (a deliberately mutable local copy is legal even when its last value is unused), and it
exists to count them: name it to run it, and it reports without refusing, even under `--gate`.

```console
$ selka lint bump.selka --rule=dead-write --all
bump.selka:7:5: warning[L_DEAD_WRITE]: dead-write: nothing reads `first` after this field write, so the write changes nothing
      first.count = first.count + 1
      ^
lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted
```

The analysis follows every path from the write to the function's end, through branches, `match` arms, loops (a later
iteration's read counts), `break`, `continue`, `return` and `fail`. It never reports a write to a `mut` parameter or to a
place reached through one, a write through a `match mut` binding, a write the compiler made, a declaration's
initializer, or a writer call whose result is used (`lists.pop`, a function that returns a value). It judges a local as
a whole: a later read of `x.b` keeps an earlier write to `x.a` alive.

The program below writes `total` in a loop that reads it on the next iteration and returns it, so the rule is quiet:

```selka
func sum_to(n: int) -> int:
    mut total = 0
    for i in range(n):
        total = total + i
    return total


func main(out: Stream) -> int:
    print(out, sum_to(4))
    return 0
```

## A text cut at a count of octets

A `str` slice counts octets. `text[0:WIDTH - 1]`, `kind[0:1]` and `text[at:at + 1]` check, lint clean and pass every test
whose texts are ASCII, and trap `R_TEXT_BOUNDARY` at the first text whose character spans the cut (F-74: one sat in a live
server for a day). `text-slice-octets` reports them: a slice of a `str` whose end, or whose start other than `0`, is

- an integer literal (`kind[0:1]`, `text[2:]`),
- a module constant or an expression over constants and literals (`text[0:WIDTH - 1]`), or
- the other bound plus or minus a literal (`text[at:at + 1]`, `text[end - 1:end]`), or
- the length of a text literal or of a module constant, alone, in a sum with a literal or as the base of the other bound
  (`line[len("content-length:"):]`, `line[len(PREFIX):len(line)]`, `text[len(text) - len(SUFFIX):len(text)]`): the length of a
  literal is the number it is (F-77).

A cut at exactly such a width is quiet where the program tested the text it measures, and only there. `line[len(PREFIX):]`
is not reported where control reaches it only after `strings.starts_with(line, PREFIX)` held: in the `then` branch of the
`if` (alone or one conjunct of an `and` chain), in the `else` branch of an `if not` test (alone or one disjunct of an `or`
chain), or in the rest of the block after an `if not` test (or an `or` chain with that disjunct) with no `else` whose body
leaves (`return`, `fail`, `break`, `continue`). The prefix must be the same literal or the same constant, and the text the
same name, field chain or element read of one (`args[2]`), spelled the same; the stretch must not assign that text or a
name in its index, write through it or pass it as `mut` or `own`. The same holds for `text[len(text) - len(SUFFIX):len(text)]`
under `strings.ends_with(text, SUFFIX)`, and a plain number is quiet when it is the number of octets of the tested literal
(`text[3:]` after `starts_with(text, "é:")`). A loop's own condition, a negated `and`, a test of a copy of the text, a test in
another function and any other control flow guard nothing. When a test of the same text covers the cut but names another
prefix, the finding stays and its message names that test beside the width the cut measures.

It never reports a bound that is a found offset (`strings.find`, a position a loop reads out of the text), `len(...)` or a
variable of any kind (the length of a parameter, `len(text) - 1`), a start of `0`, an empty slice, a slice of `bytes` or of a list, or the strip of a tested prefix:
a literal start `N` of a text that the same function tested with `strings.starts_with(text, "prefix")` for an ASCII prefix
of at least `N` octets before the slice (`url[7:]` after `starts_with(url, "http://")`), since that cut is inside the
prefix, and the slice of a text the program wrote in place, whose bytes the author sees: a text literal
(`"héllo"[0:1]`) or a name the same function bound once to an ASCII text literal (`const data = "abcdefghijkl"`). A text known to be ASCII for another reason (a hex digit, a protocol keyword) is reported all the same: say so with
`# lint: allow text-slice-octets reason="..."` above the declaration. The rule reports and never blocks, under every profile
and under `--gate`.

The repairs the message names: `strings.cut_octets(text, limit)` cuts a width at the end of a character (a view of `text`;
`copy(...)` it to keep it); `strings.char_slice(text, start, end)` cuts by a count of characters; and
`strings.starts_with_at(text, prefix, at)` asks whether a prefix starts at an octet offset without slicing, so a scanner can
ask at every octet. [Standard library](../standard-library.md#a-text-cut-at-a-width) has an example of each.

```selka
import strings

func initial(kind: str) -> str:
    return copy(strings.cut_octets(kind, 1))

func main(out: Stream) -> int:
    print(out, initial("\u00e9clair"), len(initial("\u00e9")))
    return 0
```

## Long examples

An example is the documentation's executable claim, not a transcript of a debug
session. `long-example` (`L_LONG_EXAMPLE`) reports an example whose expected
output runs past 120 characters on one line, or whose `>>>` block runs past 6
lines. It never blocks: a plain `selka lint` reports it, `release check` lists it
as a warning, and the gate stays green.

Show the call, not a dump:

- pick the smallest input that demonstrates the behavior;
- show `Ok(…)` or `Err(…)` directly rather than unwrapping it with a `match`;
- assert a property — `len(...)`, a prefix, one named field — instead of printing
  a large value.

`selka lint --all` names the docstring line and the repair. A display that
genuinely needs the whole value takes a reasoned waiver.

```selka
public func names(items: int[]) -> str:
    """Describe the item count in one short sentence.

    >>> names([1, 2, 3])
    '3 items'
    """
    return f"{len(items)} items"


func main(out: Stream) -> int:
    print(out, names([1, 2, 3]))
    return 0
```

## Needless copies

The checker warns when a `copy(value)` carries no value, and the warning holds
the one edit that deletes it:

```console
$ selka check report.selka
report.selka:10:18: warning[W_NEEDLESS_COPY]: `total` only reads `rows`, so pass `rows` itself rather than a copy
        sum += total(copy(rows))
                     ^
check: ok (1 module, 0 cached)
$ selka fix report.selka --warnings
fixed report.selka: 1 edit (W_NEEDLESS_COPY)
```

The warning names the callee as its source names it: a call to an instance of a generic
function reads `` `contains[Item]` only reads `v` ``, the function's name without its module and the
type arguments without theirs, not the tail of the instance's checked name.

There are exact shapes, and the warning fires only where the copy-free form
checks:

- the copy is an argument to a read-only parameter, an f-string hole or a printed
  value, so the callee only reads it and passing the value itself passes the same
  borrow;
- the copied value is an owned local and the copy is its last use, so binding the
  value itself moves it and hands back the same bytes;
- a `const` binds a copy of a parameter's place, or of a field or element of a
  parameter (a `mut` one too) or a local, and only reads it while the source does
  not change, so the binding can borrow the source. An element is a list element
  (`items[i]`) or a dictionary value (`by_root[key]`), and a local that `take` or
  `exchange` moved a collection into counts as a local the binding can read;
- the copied value is an owned local or an `own` parameter, the copy is its last
  use, and the copy is taken over (appended, stored as a dictionary key or value
  or a set member, a case payload, a constructor field, a list element, an `own`
  argument, an assignment or a return): the fix writes `own value` (a bare
  `value` when it is returned), which moves the same bytes. It stays silent in a
  generic instance, in a loop the value was not declared in, beside another read
  of the value in the same statement, inside a match whose head reads the value
  or a condition the copy is part of, and while an alias or a view of the value
  is live. A copy in the branch of an `if` whose condition only reads the value
  moves it, as does the value of an element write (`items[0] = copy(x)`). A copy in a `return` or a `fail` is followed only by
  the rest of its own statement, so a later `return` that reads the value does not keep it; the last of several copies of the
  value in one constructor, list or call moves when every other mention is an earlier operand's copy; and the body of a `with`
  holds only what its head names. The value may be a record, a list or a dictionary as well as text, and a value
  declared in the same `match` arm as its last use moves there, and so does the payload of a `match` or an
  `is Ok(x)` over a fresh result, whether the result is a call's, a library function's (`strings.decode(bytes[a:b])`) or
  a capability's method's (`fs.read_file(path)`); a failing function's `return copy(x)` is written `return x`, with no
  `own`. A field of a local moves with the
  local (`own row.name` consumes `row`, which nothing reads again): the same rules
  apply, with no other read of the record in the statement, and a returned field
  is written `return own row.name`.

- the copy duplicates a value that is already new: a module constant (`copy(family)`),
  a call that returns a fresh result, a concatenation. The fix keeps the value and
  drops the second allocation, in any position;
- the copy duplicates a borrowed value, a call's declared borrowed result, an option's
  default (`opt.unwrap_or("")`) or an element read, and the position only reads it: a
  read-only argument (of a call or of a function value), a printed value, an f-string
  hole, a set member or a `const` binding. The warning follows the value to the one
  local it borrows (a loop variable stands for the list it walks) and judges it as it
  judges a copy of that local's place: the binding must only be read while the local
  does not change;
- a `const` that copies a whole local the function owns, and reads it while it is
  live, borrows it instead.

- the copy is the last use of what it copies, and the move is a rewrite the pass makes whole: a field of a local
  that nothing reads again (`own row.name`), the payload of a `match` that consumes a fresh call result
  (`own err`), a field or element of a `mut` local or parameter that nothing reads again (`take(mut row.name)`),
  and each element of a list a loop copies out (`for x in own xs`, `own x`).

- the copies are fields of a record constructor (or the payload of `Some` in one) passed to a read-only parameter of a
  call that is not recursive, and with them deleted the record borrows: every managed field is a literal, `None`, a
  place of a read-only parameter or of a loop variable over one, a bare read-only parameter (a record, dictionary, set,
  text, bytes or list), or `Some` of a place or of a read-only record parameter
  ([B9](../ownership-rules.md#b9--const-place-bindings-borrow)). One warning holds the edits of the whole record. A text,
  bytes or list parameter is then held as a frame block, copied once per call instead of once per record when the
  argument was a slice or bytes. The same record in a `const` or a `mut` local is not repaired: what the binding does
  later decides whether it may borrow, and the front end does not follow it.

A `return copy(place)` of a borrowed place preserves an owned result contract.
Removing that copy would require declaring `from`, so the needless-copy fix
leaves it intact.

A copy that is the point of the code — a test of copying, or a copy inside a loop
whose next iteration still reads the source — takes a waiver:

```text
# lint: allow needless-copy reason="this test measures what a copy costs"
```

The lint rule reads the checker's warnings rather than re-deriving them, so a
plain `selka lint` reports `L_NEEDLESS_COPY` at the same line, `--gate` exits 3,
and the checker's message, repair and the lint finding cannot disagree.

```selka
func total(values: int[]) -> int:
    mut sum = 0
    for value in values:
        sum += value
    return sum


func main(out: Stream) -> int:
    mut rows: int[] = []
    append(mut rows, 1)
    append(mut rows, 2)
    print(out, total(rows))
    return 0
```

## Moves instead of copies

A copy whose source is never read again is a move that was not written. `W_NEEDLESS_COPY` writes the moves it can make
whole, and `W_COPY_FOR_STORE` and `W_COPY_RETURNED` the ones that also change a signature and its callers. For the rest the
checker warns `W_COPY_MOVE`, which has no `fix` because the rewrite is not certain there, and `selka lint` reports it as
`L_COPY_MOVE` (report only). The forms, in the order the checker tries them:

| Where the copy comes from | The form | Repair |
| --- | --- | --- |
| a whole local, or a field of a local, nothing reads again | `own x`, `own row.name` | `W_NEEDLESS_COPY` writes it |
| the same, when the value has no managed part (a number, a record or an option of numbers) | the bare `x`, `row.colour`: `own` on it is `E_OWN_MARKER` | `W_NEEDLESS_COPY` writes it, and its message says the value holds nothing managed |
| a field of a `mut` local or `mut` parameter, which other fields' reads follow | `take(mut row.name)` leaves the default behind | `W_NEEDLESS_COPY` writes it |
| the same place in a `const` local | declare the local `mut`, then `take(mut row.name)` | `W_NEEDLESS_COPY` writes both edits; a place declared with no `const` (a loop variable, one name of several) stays a hint |
| a loop variable of a list local that nothing reads after the loop | `for x in own xs`, `own x` | `W_NEEDLESS_COPY` writes both edits |
| a loop variable of the list a call returns, or a field of it, copied where a store, a `return`, a `fail` or an `own` argument stands, that nothing reads after the copy | `for x in own call()`, `own x` or `own x.f` (a bare `x` at a `return` or `fail`) | `W_NEEDLESS_COPY` writes both edits; a copy a loop around it runs twice, a view of the element and a list lent by an argument stay a hint or nothing |
| a field of a loop variable of a list local the function owns | `for x in own xs`, `own x.f` | `W_NEEDLESS_COPY` writes both edits |
| a loop variable of a plain list parameter, or a field of it | `own xs` in the signature, `for x in own xs`, `own x` or `own x.f`, and `own` before each caller's last use of a name | `W_COPY_FOR_STORE` writes them in a project check where every caller passes a new value or a name it gives up (as for a stored parameter); otherwise, and for a field (`for x in r.items`) or a list the function does not own, a hint |
| the payload of a `match` that consumes a fresh result | `own payload` | `W_NEEDLESS_COPY` writes it |
| the payload of a `match name:` statement, or of `const x = name else:`, on an owned local that nothing reads after it | `match own name:` or `const x = own name else:`, and `own payload` (a bare `payload` at a `return` or `fail`) | `W_NEEDLESS_COPY` writes both edits; an arm or a later line that reads `name`, a payload read after the copy, a loop around it that `name` was declared outside of, and `if name is Some(x):` (which has no `own` spelling) stay a hint |
| `opt.unwrap_or(default)` of an option nothing reads again | `options.take_or(own opt, default)` | `W_NEEDLESS_COPY` writes it, with `import options`; a local named `options`, a comment in the call, or a statement around the copy that holds `opt` leaves a hint |

`take` leaves the type's default behind (an empty collection, `None`, a record built from its field defaults), so the
pass proposes it only where nothing reads that place again: every later use of the local is a field the copy did not
take, or there is none. A copy that is the point of the code takes `# lint: allow copy-move reason="..."`.

A function every return of which copies a place of one parameter is told to declare its result `from` that parameter
instead. `check` leaves that hint out when a caller in the checked program keeps the result: the ownership check accepts
the caller as it is and refuses it once the result is declared `from`, so the copy is the one that caller needs (F-8).
The hint names only what the function itself allows: its other returns are constants (`None`, `""`, `[]`; a new value
beside a borrow is `E_BORROW_MIXED`) and the parameter can lend the result. A project check (`selka check DIR`) makes it
`W_COPY_RETURNED`, whose `fix` writes ` from p` after the result type and each returned `copy(PLACE)` as `PLACE`, where the
function is not generic, recursive or named as a value and no caller is refused with the result `from p`, a
caller that returns it included; callers are not edited. A `public` function is repaired too, its signature changed (the
warning says so), when the project's `selka.json` sets no `interface_files` and its modules have more than one top-level
name; a package, a project with `interface_files` and a check of one file keep their public signatures.

```selka
record Props:
    material: str
    items: str[]
    thickness: float


record Entry:
    material: str
    thickness: float


func parse(n: int) -> Props:
    return Props(material="m" + str(n), items=["a"], thickness=1.5)


func entry(n: int) -> Entry:
    mut props = parse(n)
    return Entry(material=take(mut props.material), thickness=props.thickness)


func main(out: Stream) -> int:
    print(out, entry(3).material)
    return 0
```

## Copies in a loop

A copy at loop depth 1 or more runs on every iteration, and the cheap way to silence the lint is also the fast way: the
message names the form that fits where the copy goes, judged from the checked program and the checker's own warnings, in this
order:

| Where the copy goes | The form | Taught in |
| --- | --- | --- |
| the checker proves the copy-free line (`W_NEEDLESS_COPY`) | a borrow | [Needless copies](#needless-copies) |
| a value whose source is not read again | a move: `own x`, `take(mut x.f)`, `for x in own xs` | [Taking and exchanging a value](../value-semantics.md#taking-and-exchanging-a-value) |
| a slice of `bytes`, kept in a record, list or dictionary | a `spans.Span` into the source | [Long-lived data](../value-semantics.md#long-lived-data-hold-the-key-not-the-borrow) |
| the same `bytes` name on every iteration, from a place the loop does not write | a `symbols` key | [`symbols`](../standard-library.md#symbols) |
| a `str` read from the element of a `for x in xs` loop, over a list the function owns (a local or an `own` parameter) | the loop that takes the list, if neither it nor the element is read again: `for x in own xs`, then `own x` or `own x.field` | [Taking and exchanging a value](../value-semantics.md#taking-and-exchanging-a-value) |
| a `str` read from the element of that loop, over a list the function is lent | a real transfer; an `own` list parameter would let the loop take the elements | [Taking and exchanging a value](../value-semantics.md#taking-and-exchanging-a-value) |
| anything else | a real transfer: the message says no more | |

The judgement errs toward the last row: a name the loop changes, or a copy whose source the function reads again, is a
real transfer however it is stored. A span and a symbol hold `bytes`, so a `str` is never sent to them (`symbols.intern`
and `spans.add` refuse `str`, and `spans.text` gives `bytes`): a slice of a `str`, or a `str` read outside a `for x in xs`
loop, is a real transfer. The span row follows the copy's operand, a slice whose owner outlives the loop; it
does not know that the slice is kept past the call, so it is advice to weigh against the code, not a proof.

## Counting copies

`selka lint --copies PATH` answers "how many copies does this program write, and how many per 1,000 lines" with one
report, so the number can be watched over time. It prints the count and nothing else, and exits 0 (when the analysis the loop
rule reads failed it adds one line on standard error and [does not print a split it does not know](#when-the-analysis-behind-the-loop-rules-fails)). A copy is a `copy(...)`
call written in a source file of the program, test files included and the standard library left out; every line of those
files is a line. Each copy is counted once, in the first of these categories whose finding sits on it, and in the last
one when none does:

| Category | Finding | What it says |
| --- | --- | --- |
| `selka fix removes them` | `L_NEEDLESS_COPY` | the copy-free form checks; [`selka fix`](#needless-copies) deletes or moves the copy |
| `a move replaces them` | `L_COPY_MOVE` | the copy's source is not read again; [a move](#moves-instead-of-copies) replaces it |
| `stored from a parameter` | `L_COPY_FOR_STORE` | the copy stores a parameter; an `own` parameter would take it |
| `in a loop` | `L_COPY_IN_LOOP` | the copy runs on every iteration of a [loop](#copies-in-a-loop) |
| `named by nothing` | none | no finding sits on the copy |

A finding sits on a copy when it starts inside the copy's text, or at the start of the statement that holds it (a store is
reported at its statement). The categories follow the run's profile and `--rule`, because a rule that is off reports
nothing; and a waiver comment removes a finding, not the copy, so a waived copy is counted as named by nothing. The count
adds no finding and changes none. `PATH` is an entry file, as for every `lint` run (a directory is refused, here as
there), and the closing `lint:` line is not printed. A project with several entries has [one count for all of them](#counting-copies-over-several-entries).

```selka
# doc: check
record Plan:
    head: int[]


func show(name: str) -> int:
    return len(name)


func needless(name: str) -> int:
    return show(copy(name))


func plan(head: int[]) -> Plan:
    return Plan(head=copy(head))


func spread(n: int) -> str[]:
    const base = "x" + str(n)
    mut out: str[] = []
    for i in range(n):
        append(mut out, copy(base))
    return out


func kept(xs: int[]) -> int:
    mut ys = copy(xs)
    append(mut ys, 1)
    return len(ys)


func main() -> int:
    return needless("a") + len(plan([1]).head) + len(spread(2)) + kept([2])
```

Saved as `counts.selka`, the program writes four copies in 32 lines, one of each kind a finding names and one it does not:

```console
$ selka lint --copies counts.selka
copies: 4 in 32 lines, 125.0 per 1000 lines
     1 selka fix removes them (L_NEEDLESS_COPY)
     0 a move replaces them (L_COPY_MOVE)
     1 stored from a parameter (L_COPY_FOR_STORE)
     1 in a loop (L_COPY_IN_LOOP)
     1 named by nothing
$ selka lint --copies --json counts.selka
{"schema":"copy-count-v1","entries":1,"copies":4,"lines":32,"per_1000":125.0,"needless":1,"move":0,"for_store":1,"in_loop":1,"unnamed":1,"files":[{"path":"counts.selka","copies":4,"lines":32}]}
$ selka lint --copies --gate counts.selka
selka lint: --copies prints a count and refuses nothing, so it takes neither --gate nor --accept
$ echo $?
2
```

`--json` prints one line. Its `files` list gives every file counted, sorted by path, each with its own `copies` and `lines`
(a file with no copy is listed with 0), written beside the entry file's folder as the command line reached it. The first
example above is also the program `selka doctest` checks; the transcript is what `lint --copies` printed for it. The JSON
carries `"entries"`, the number of entry files the count reads (1 here), after the schema name; the field is new, and the
schema stays `copy-count-v1`.

### When the analysis behind the loop rules fails

`L_COPY_IN_LOOP` and `L_ALLOC_IN_LOOP` read the rows of the analysis `selka cost --sites` runs (a Core build with LLVM left
out). A program `check` accepts can fail that build: a `@noalloc` promise its body breaks is one (`E_NOALLOC_ALLOCATES`), a
Core refusal or a stale record in the work directory is another. The two rules then have no rows and judged nothing, which a
clean run would also print. So a run whose analysis failed says so first, in one line on standard error that names the file,
the first error code of the failure and the rules that were not judged (only those that are on in this run):

```console
$ selka lint main.selka
selka lint: main.selka: the analysis behind the loop rules failed (E_NOALLOC_ALLOCATES), so L_ALLOC_IN_LOOP and L_COPY_IN_LOOP were not judged
```

- **The count.** `--copies` cannot split the copies no earlier rule names between "in a loop" and "named by nothing", so it
  does not print a `0` for either. The text puts `?` where the number would be and says how many copies the two lines share;
  `--json` keeps `"schema":"copy-count-v1"` and, only in this case, sets `"in_loop":null` and `"unnamed":null`, adds
  `"split_known":false` and `"in_loop_or_unnamed":N`. The schema name does not change because a run whose analysis ran prints
  the document it always printed, byte for byte, and the one new key is absent from it (as `entries` was new and the schema
  stayed). A reader tests `split_known` (absent means known); one that ignores it and adds `in_loop` reads `null`, never a false
  0. `needless`, `move` and `for_store` stay exact, since those rules do not read the analysis. With several entries the
  total is unknown when any entry's split is.

```console
$ selka lint --copies main.selka
selka lint: main.selka: the analysis behind the loop rules failed (E_NOALLOC_ALLOCATES), so L_ALLOC_IN_LOOP and L_COPY_IN_LOOP were not judged
copies: 1 in 18 lines, 55.6 per 1000 lines
     0 selka fix removes them (L_NEEDLESS_COPY)
     0 a move replaces them (L_COPY_MOVE)
     0 stored from a parameter (L_COPY_FOR_STORE)
     ? in a loop (L_COPY_IN_LOOP): not known, the analysis failed
     ? named by nothing: not known, the analysis failed (the two lines share 1 copy)
```

- **The status.** A failed analysis is not a finding, so without `--gate` the status is what it was (0 for `--copies`, which
  refuses nothing). Under `--gate` (or `on_build: "block"`) a gate that passes says every blocking rule was judged: when
  `copy-in-loop`, a `block` rule in every profile, was not, the run exits 3 and the line adds `; --gate refuses (status 3)`.
  A rule that is off, or `alloc-in-loop`, which only reports, never makes a gate refuse.
- **Nothing to analyse.** A file with no `main` (a library, or a `_test.selka` file) has no entry for the analysis to follow, so it
  is not a failure and prints no line: its rows are those of the functions its discovered tests reach, and with no tests it has
  none, so each of its copies is named by nothing, as before. `selka cost --sites` on a failing program prints its diagnostics
  and exits 1; it was never silent.
- **Left out.** A test the Core refuses is left out of the rows without a line, as it always was.

### Counting copies over several entries

A project with many entries (a `main.selka`, tools, a test file for each module) has one number to follow over time:
`selka lint --copies A.selka B.selka ...` lints each entry in turn, in one process and as a lone entry is linted (the same
check, the same findings), and prints one count for the union of the files they reach:

- a file reached by several entries is counted once: its lines once, and each of its copies once (a path is read
  plainly, so `./a.selka` and `a.selka` are one file, and a link is not followed);
- a copy takes the best category any entry gave it, in the order of the table above (`L_NEEDLESS_COPY` first, "named by
  nothing" last), so an entry whose rules could not see a caller, or a loop, cannot turn a copy another entry named into
  an unnamed one;
- the text gains the first line `entries: N` when N is 2 or more (one entry prints what it always printed), and the JSON
  always has `"entries":N`; its `files` list holds each file once, written plainly.

```console
$ selka lint --copies counts.selka counts.selka
entries: 2
copies: 4 in 32 lines, 125.0 per 1000 lines
     1 selka fix removes them (L_NEEDLESS_COPY)
     0 a move replaces them (L_COPY_MOVE)
     1 stored from a parameter (L_COPY_FOR_STORE)
     1 in a loop (L_COPY_IN_LOOP)
     1 named by nothing
```

The same file twice is one program counted once (the total is not 8). The entries are the files you name: nothing is
discovered, and a directory is refused as for one entry. An entry that gives no count ends the command with what it
printed and its status, as a lone entry would (a program that does not check prints its diagnostics and exits 1; a file
that is not there is refused, before any entry is linted, with exit 2), and one more line on stderr names it:
`selka lint: bad.selka gave no count (status 1), so there is no total`. Naming several entries without `--copies`, or
beside `--gate` or `--accept`, is a usage error. The project's `stores` are those of the first entry.

## Copies in recursion

A recursive walk that builds its callee's context from copies copies the caller's
whole context at every level: the parent scope holds the parent block, so each level
copies everything above it. The checker warns with `W_COPY_IN_RECURSION` when a
`copy(...)` of a parameter, of a loop variable over one, or of a place of either is a
field of a record (or the payload of `Some` in one) passed to the function's own call:

```console
$ selka check walk.selka
walk.selka:18:35: warning[W_COPY_IN_RECURSION]: `walk` passes a copy of its own context into its recursive call, so every level copies the caller's; pass the places themselves: a record built from borrows borrows, and it may hold `Some(p)` of a read-only record parameter
        total += walk(Scope(block=copy(sb.block), parent=Some(copy(scope))))
                                  ^
check: ok (1 module, 0 cached)
$ selka fix walk.selka --warnings
fixed walk.selka: 2 edits (W_COPY_IN_RECURSION)
```

The fix deletes every copy of the record at once, and only where the record then
borrows (see [borrowed parents](../ownership-rules.md#borrowed-parents)): the record
is the argument of a read-only parameter, and each managed field is a literal, `None`,
a place of a read-only parameter or of a loop variable over one, a bare read-only
parameter (a record, dictionary, set, text, bytes or list), or `Some` of a place or of
a read-only record parameter. Otherwise the warning reports alone.

## Idiom rewrites

Eight shapes of compiler-shaped code have a shorter spelling the language already accepts. The checker warns on each
with the certain edit that rewrites it, `selka fix` applies the edit, and `selka lint` reports the same site as an
`L_*` finding the way it does for `W_NEEDLESS_COPY`. None blocks, in any profile.

| Warning | The long spelling | The short one |
| --- | --- | --- |
| `W_BYTE_SET` | `c == 43 or c == 45 or c == 47` | `c in b"+-/"` |
| `W_RANGE_CHAIN` | `c >= 48 and c <= 57` | `48 <= c <= 57` |
| `W_LITERAL_MATCH` | `if x == 1: ... elif x == 2: ... elif x == 3: ...` | `match x:` with `case 1:`, `case 2:`, `case 3:`, and `case _:` for an `else` |
| `W_PATTERN_SHORTHAND` | `case text(value=value):` | `case text(value):` |
| `W_OPTION_TRY` | `match call():` with `case Some(x):` and `case None: return None` | `const x = try call()` |
| `W_ELSE_IS_TRY` | `const x = call() else Err(e):` over `fail e` (or `else:` over `return None` in a function that returns an Option) | `const x = try call()` |
| `W_MATCH_ELSE` | `match f():` with `case Some(x): ...` and `case None: return 0` | `const x = f() else:` over `return 0`, then the `Some` arm's statements |
| `W_MATCH_IS` | `match f():` with `case Some(x): ...` and `case None: pass` | `if f() is Some(x):` over the `Some` arm's statements |

Each fires only where the rewrite cannot change the program: the value tested is a plain name, field or index (never a
call), the bytes are integer literals, a literal-match chain has three or more tests of an integer, or of a `str` or `bytes` name (never an Option, a `str` or `bytes` field or element, or a value in a generic function, where a literal arm is refused), with no comment between its
bodies and a body that can be re-indented, an Option match ends its block in a function that returns `T?`, and a bind-or-else has an `else` block of that one statement, no comment and a call as its value (`try` over a borrowed place would take the payload). `W_MATCH_ELSE` and `W_MATCH_IS` read a `match` written in the source with exactly the two cases of an Option or a Result (checked, so a generic body draws none), each binding one name or `_`, not `match mut`, and the success arm's statements move into the enclosing block only when nothing after the `match` declares a name they declare; `match own x` becomes `const x = own x else:` and has no `is` form. Where `W_OPTION_TRY` reports a `match`, `W_MATCH_ELSE` does not, and a bind-or-else it writes that only passes the failure on draws `W_ELSE_IS_TRY` in the next round. A comment on a `case` line moves to the line written for it. A run
settles a nested shape over rounds: `selka fix` repeats until nothing is left. A site that is the subject of a test
takes a waiver, per site or for a file:

```text
# lint: allow-file literal-match reason="the if/elif dispatch chains are the programs under test"
```

```console
$ selka check lexer.selka
lexer.selka:7:12: warning[W_BYTE_SET]: 3 equality tests of `c` against bytes: `c in b"+-/"` tests the same set
      return c == 43 or c == 45 or c == 47
             ^
check: ok (1 module, 0 cached)
$ selka fix lexer.selka --warnings
fixed lexer.selka: 1 edit (W_BYTE_SET)
```

## Loop rules

Four rules name work inside a loop that grows with what the loop does. The
first three read the checked tree and an exact shape only; they name the
rewrite, and a heuristic finding refuses only in a declaration changed against
`--against REF` (P1), so old code never walls the gate.
`linear-search-in-loop` reports a search on a list the loop leaves alone; the
blocking shape is the "seen list" the loop builds and probes. `alloc-in-loop`
reads the `cost --sites` rows instead of the checked tree: the classification
is the one the build reports, and the rule only reports, in changed
declarations.

### linear-search-in-loop

A list a loop appends to, searched with `lists.contains` (or a list `index`) in
the same loop, costs one walk of everything the loop has built per probe. Keep a
`set` or `dict` beside it and probe that instead.

```selka
import sets

func first_repeat(n: int) -> int:
    mut seen: int[] = []
    mut seen_set: set[int] = set()
    mut found = -1
    for i in range(n):
        const value = (i * 7919) % 1000
        if value in seen_set:
            found = value
        append(mut seen, value)
        sets.add(mut seen_set, value)
    return found + len(seen)
```

### shift-in-loop

Removing or inserting at index 0 of a list declared outside the loop shifts
every later element. Keep an index cursor over the list, or use B6's `deque`.

```selka
func drain(n: int) -> int:
    mut queue: int[] = []
    for i in range(n):
        append(mut queue, i)
    mut cursor = 0
    mut total = 0
    while cursor < len(queue):
        total += queue[cursor]
        cursor += 1
    return total
```

### sort-in-loop

Sorting a list the same loop appends to re-sorts it as it grows. Sort once after
the loop, or use B6's `heap`. A list created inside the iteration and sorted once
there is not this shape.

```selka
func sort_once(n: int) -> int:
    mut window: int[] = []
    for i in range(n):
        append(mut window, (i * 7919) % 1000)
    window = sorted(window)
    return window[0]
```

### alloc-in-loop

A construction or conversion the Core passes place at loop depth 1 or more
builds a value on every iteration. The rows are exactly `selka cost --sites`'s,
so the kind and its hint cannot disagree with the build report; a site outside
a loop, a growth site (`append`, `insert`, a sort) and a copy are not this rule.
It reports only in a declaration changed against `--against REF`, and never
refuses: move the value out of the loop, or reuse one buffer.

```selka
func build(n: int) -> int:
    mut total = 0
    for i in range(n):
        const row = {"key": i}
        total += row["key"]
    return total
```

### copy-in-loop

A `copy(value)` the Core passes place at loop depth 1 or more copies the value
on every iteration. Each copy is a choice under rule C, so the rule reports
every one, in every declaration. It refuses under `--gate` only where the
declaration changed against `--against REF`. The message names the rewrites in
the order to try them:

1. a field store through the place, `xs[i].f = value`, which changes the one
   field and copies nothing;
2. `exchange(index, placeholder)` for an element that must be taken out,
   updated as an owned value and stored back (`xs[i] = updated`);
3. a `const` that borrows the place (`const row = xs[i]`), when the owner is a
   parameter or a local and nothing changes it while the borrow is live (a loop
   variable already borrows its list, so it cannot be borrowed again);
4. an `own` hand-off, when the callee can take the value without a copy.

The first example copies a record on every iteration only to read one field.
The second reads the field through the loop variable, and the copy is gone.

```selka
record Box:
    items: int[]
    tag: int


func count_items(boxes: Box[]) -> int:
    mut total = 0
    for box in boxes:
        mut local = copy(box)
        total += len(local.items)
    return total


func main() -> int:
    return count_items([Box(items=[1, 2], tag=0)])
```

```selka
record Box:
    items: int[]
    tag: int


func count_items(boxes: Box[]) -> int:
    mut total = 0
    for box in boxes:
        total += len(box.items)
    return total


func main() -> int:
    return count_items([Box(items=[1, 2], tag=0)])
```

A copy that is the point of the code, such as a test of copying, takes a
reasoned waiver on the line above its statement:
`# lint: allow copy-in-loop reason="..."`.

## Owned parameters

`own` is a parameter mode: a plain parameter reads its argument, a `mut`
parameter writes the caller's value, and an `own` parameter takes it, so the
caller's binding is unusable after the line and the callee may store, return or
move the value without a copy. The mode is visible at both ends.

```selka
record State:
    keys: int[]


public func order_by_key(own keys: int[]) -> State:
    return State(keys=own keys)      # stored, not copied


func main(out: Stream) -> int:
    mut samples = [3, 1, 2]
    const ordered = order_by_key(own samples)
    print(out, ordered.keys[0])
    return 0
```

At a call the marker is required exactly where a named binding of a value that
owns storage is given away, and refused where nothing is lost: on a fresh value
(a call result, a constructor, a literal, `copy(value)`) or a scalar. So
`append(mut rows, 1)` and `make([1, 2])` carry no marker, while
`append(mut rows, own row)` and `make(own samples)` do. `own` and `mut` do not
combine, and a function type spells the mode: `func(own Node) -> int`.

`L_COPY_FOR_STORE` is the report-only rule for the copies this replaces. It
reads the three storing shapes above and names the parameter to declare `own`;
it never blocks `release check`, because whether every caller can give the value
up is a design decision the author makes. The standard library's storing
functions (`append`, `sets.add`, and the item of `dicts.append_to`) take
their element `own`, and the marker is required where a named binding the caller owns
is given away (`DECISIONS.md` F71, lane A). The keys of `dicts.add` and `dicts.append_to`
are borrowed and copied only when new.

## Waivers

A waiver is a directive comment on the line above a declaration, in the same
family the documentation gate already parses:

```text
# doc: not-selka
# lint: allow function-length reason="exhaustive opcode table, split hurts review"
func dispatch(op: Op, frame: Frame) -> Result[Frame, VmError]:
    ...
```

A waiver without `reason=` is itself a finding (`L_WAIVER_REASON`), always
blocking, so silencing a rule always costs a sentence explaining why.

When the same reasoned waiver repeats above many declarations, one file-level
waiver replaces all of them:

```text
# lint: allow-file untested-export reason="the fixture programs exercise this module end to end"
```

`allow-file` covers every finding of that named rule in the file, and no other
rule. It needs the same `reason=` clause, and a file waiver without one is the
same blocking `L_WAIVER_REASON`. A per-declaration waiver still covers only the
declaration below it. [`release check`](release-docs.md#check-every-change-and-release)
applies the project's `lint` object and the same waivers in its lint step, and its
docs step honors them for the three documentation rules.
