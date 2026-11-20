# Linting a project

`selka lint` checks a project against rules for dead code, needless copies, weak tests and size, and reports findings
with `L_*` codes. It reports while you work and refuses only at the gate (`--gate`).

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

| Option | Meaning |
| --- | --- |
| `--gate` | every `block` rule refuses (exit 3) and its findings become errors |
| `--json` | findings as `diagnostic-v1` JSON Lines on stderr, always complete (also `--diagnostics=json`) |
| `--all` | every finding in full, not one count line per report-only rule |
| `--profile=NAME` | `agent`, `strict` or `safety`, for this run |
| `--accept` | record the current findings in the baseline under `.selka/lint/` |
| `--against=REF` | judge the tree against git revision `REF`: `change-without-test` evaluates the diff, and findings in changed declarations print in full |
| `--rule=NAME` | turn on, at `report`, a rule the profile leaves off (today only `dead-write`); an unknown name is a usage error |
| `--copies` | print how many `copy(...)` calls the program writes ([Counting copies](#counting-copies)); takes neither `--gate` nor `--accept` |

Exit status: `0` nothing blocking, `1` a source, type, effect or ownership error (no rule evaluated), `2` a usage or
configuration failure, `3` a blocking finding, or a `--gate` run whose
[loop analysis failed](#when-the-analysis-behind-the-loop-rules-fails).

## What a run prints

A run prints in full the findings that block and those in declarations changed against `--against REF`, and every other
finding as one count line per code. `--all` lists them all; `--json` is always complete.

```console
$ selka lint main.selka
L_UNTESTED_EXPORT: 32 findings (selka lint --all lists them)
L_DEAD_EXPORT: 1 finding (selka lint --all lists them)
lint: 200 finding(s): 0 blocking, 200 report, 4 waived, 0 accepted
```

## Profiles and the report/block split

- With no `lint` object in `selka.json` a project runs the `agent` profile: correctness rules report, style rules stay
  silent, nothing refuses until `--gate`. `strict` blocks everything blockable; `safety` also demotes size budgets.
- `untested-export` reports a different fact by profile: under `agent` an export any test reaches, directly or
  transitively, is tested; under `strict` and `safety` only a direct call counts. To ask the direct question without
  refusing, set `"profile": "strict"` and list `untested-export` under `report`.

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

The `block`, `ratchet` and `report` lists override the profile (precedence block, report, ratchet). `on_build: "block"` is
the only setting that makes a plain `selka lint` refuse. `min_chars` (default 12) is the non-whitespace floor for
`undocumented-export`. A `lint` object requires `selka.json` `version: 2`. `warnings: "deny"` makes a checker `W_*`
diagnostic exit `check` and `check-project` with 1 (`run` and `run-project` ignore it); the default, `report`, leaves the
inner loop alone.

## Rules

Defaults are those of the `agent` profile; a rule's name goes in the `block`, `ratchet` and `report` lists and in
`# lint: allow` waivers.

**Block in every profile** (waive the site with a reason):

- `noalloc-allocates` (`L_NOALLOC_ALLOCATES`): a `noalloc` function that allocates, calls something unresolved or has an
  unsupported body.
- `needless-copy` (`L_NEEDLESS_COPY`): a `copy(value)` the checker proved carries no value; `selka fix` deletes it and no
  baseline adopts it ([Needless copies](#needless-copies)).

**Block:**

- `dead-private` (`L_DEAD_PRIVATE`): a private function with no call site and no use as a value or in a docstring example (a
  function passed as a value, or called by a module constant's initializer, is used).
- `test-no-assertion` (`L_TEST_NO_ASSERTION`): a test whose every `return` is the literal `true` and which never asserts.
- `test-conditional` (`L_TEST_CONDITIONAL`): a branch or match, or more than one loop, at a test body's top level.
- `test-empty` (`L_TEST_EMPTY`): a discovered test with an empty body.
- `waiver-reason` (`L_WAIVER_REASON`, always): a `# lint: allow` comment with no `reason="..."`.
- `change-without-test` (`L_CHANGE_WITHOUT_TEST`, only under `--gate --against REF`): a declaration changed since `REF`
  whose callers are not tests changed in the same diff; no baseline suppresses it.

**Block only in a declaration changed against `--against REF`:** `linear-search-in-loop` (`L_LINEAR_SEARCH_IN_LOOP`),
`shift-in-loop` (`L_SHIFT_IN_LOOP`), `sort-in-loop` (`L_SORT_IN_LOOP`) and `copy-in-loop` (`L_COPY_IN_LOOP`) name work
inside a loop that grows with what the loop does ([Loop rules](#loop-rules)).

**Block under `--gate`:**

- `function-length` (`L_FUNCTION_LENGTH`): over `rules.function-length.max` body lines (default 60).
- `parameters` (`L_PARAMETER_COUNT`): over `rules.parameters.max` data parameters (default 5); capability parameters do not
  count.
- `nesting-depth` (`L_NESTING_DEPTH`): over `rules.nesting-depth.max` nesting levels (default 5); `if`, `for`, `while` and
  `match` each open one, `elif` and `else` are siblings, `with` opens none.
- `call-nesting` (`L_CALL_NESTING`): one expression nesting over `rules.call-nesting.max` calls (default 3); bind the
  innermost to a `const`.
- `counting-while` (`L_COUNTING_WHILE`): `mut i = start`, `while i < bound:`, `i += 1`; write `for i in range(start, bound):`.
- `double-lookup` (`L_DOUBLE_LOOKUP`): one statement that reads a dictionary key and writes it
  (`counts[key] = counts[key] + 1`); `dicts.add` and `dicts.append_to` probe once.
- `data-clump` (`L_DATA_CLUMP`): a function that writes three or more of its caller's arguments and is called from two or
  more sites; make them a record.
- `discarded-failure` (`L_DISCARDED_FAILURE`): `_ = call()` of a checked result; handle it or waive the site.
- `public-dict` (`L_PUBLIC_DICT`): a `public` function whose parameter or result type is a bare `dict[...]`; name it with a
  `type` alias.

**Report, and block under `strict`:**

- `untested-export` (`L_UNTESTED_EXPORT`): an export no test or docstring example reaches (directly, under `strict` and
  `safety`).
- `undocumented-export` (`L_UNDOCUMENTED_EXPORT`): an exported function, record, enum or union with no docstring, one under
  `lint.min_chars` characters, or one that restates its name; constants, entry points and tests are exempt.
- `sentinel-int` (`L_SENTINEL_INT`): an `int` used as a sentinel (a negative literal returned and compared, a field compared
  against `-1` twice); use an `int?`. `find` and `find_any` are exempt.

**Off, and report under `strict` and `safety`:** `undocumented-module` (`L_UNDOCUMENTED_MODULE`) finds a project module
without a docstring; `missing-example` (`L_MISSING_EXAMPLE`) a public function without a runnable `>>>` example or a
reasoned waiver (entry points and tests are exempt). `dead-write` (`L_DEAD_WRITE`) is off in every profile and reports under
`--rule=dead-write` ([Writes nothing reads](#writes-nothing-reads)).

**Report only:**

- The eight idiom rules `byte-set`, `range-chain`, `literal-match`, `pattern-shorthand`, `option-try`, `else-is-try`,
  `match-else` and `match-is` (`L_BYTE_SET`, `L_RANGE_CHAIN`, `L_LITERAL_MATCH`, `L_PATTERN_SHORTHAND`, `L_OPTION_TRY`,
  `L_ELSE_IS_TRY`, `L_MATCH_ELSE`, `L_MATCH_IS`) find a long spelling that has a shorter one ([Idiom rewrites](#idiom-rewrites)).
- `alloc-in-loop` (`L_ALLOC_IN_LOOP`): a construction or conversion at loop depth 1 or more; only in declarations changed
  against `--against REF`.
- `copy-move` (`L_COPY_MOVE`): a copy whose source is not read again, where a move replaces it but the rewrite is not
  certain ([Moves instead of copies](#moves-instead-of-copies)).
- `copy-for-store` (`L_COPY_FOR_STORE`): a parameter `copy`-ed into a record field, an element or field assignment, or a list
  write; declare it `own` ([Owned parameters](#owned-parameters)).
- `long-example` (`L_LONG_EXAMPLE`, never blocking): see [Long examples](#long-examples).
- `text-slice-octets` (`L_TEXT_SLICE_OCTETS`, never blocking): see [A text cut at a count of octets](#a-text-cut-at-a-count-of-octets).
- `decision-points` (`L_DECISION_POINTS`): over `rules.decision-points.max` decision points (default 10); each `if`, `elif`,
  `for`, `while`, `and`, `or` and `try` counts one, a `match` its arms minus one.
- `dead-export` (`L_DEAD_EXPORT`, never blocking): an exported declaration with no caller in the project.
- `integration-tests` (`L_TEST_CAPABILITY`): a test that requests `Filesystem`, `Network`, `Clock` or `Entropy` in a module
  outside `rules.integration-tests.modules` (default `*_integration`, `integration.*`).
- `record-size` (`L_RECORD_SIZE`): a `record` or `class` over `rules.record-size.max` fields (default 7).
- `file-length` (`L_FILE_LENGTH`): a module over `rules.file-length.max` code lines (default 1000; blank and comment lines
  do not count).
- `bool-ops-per-condition` (`L_BOOL_OPS`): a condition with more than `rules.bool-ops-per-condition.max` `and`/`or`
  operators (default 3).
- `naming` (`L_NAMING`): a name that is not snake_case or PascalCase, or is on the vague list (`tmp`, `data`, `info`, `obj`,
  `mgr`, `Helper`, `Util`, `Manager`).
- `repeated-literal` (`L_REPEATED_LITERAL`): an integer literal other than `0` or `1` three or more times in one module.
- `same-type-adjacent-params` (`L_SAME_TYPE_ADJACENT_PARAMS`): adjacent parameters of one non-capability type.
- `duplicate-body` (`L_DUPLICATE_BODY`, never blocking): two or more functions with identical normalized bodies.
- `output-in-library` (`L_OUTPUT_IN_LIBRARY`): a print in a module outside `rules.output-in-library.modules` (default
  `main`, `*_cli`, `cli`, `cli.*`, `*_integration`, `integration.*`).

A file whose first line is `# generated by …` (any letter case) is exempt from every rule, as is an imported
standard-library module. The three documentation rules exempt `*_test.selka` modules and the standard library;
[`selka release check`](release-docs.md) evaluates them as blocking under every profile. A module waiver goes immediately
before the first declaration, after imports.

A finding that names a declaration carries the tests that reach it as a related note. A docstring example counts as a use
of the declarations it names and as a test of what it calls (transitively too, under `agent`).

## Writes nothing reads

`dead-write` finds a write to a local that no later read can see: dead code, or an update made on a copy and lost. It is off
in every profile, because the compiler accepts such writes on purpose; name it with `--rule=dead-write` to run it. It
reports without refusing, even under `--gate`.

```console
$ selka lint bump.selka --rule=dead-write --all
bump.selka:7:5: warning[L_DEAD_WRITE]: dead-write: nothing reads `first` after this field write, so the write changes nothing
      first.count = first.count + 1
      ^
lint: 1 finding(s): 0 blocking, 1 report, 0 waived, 0 accepted
```

It follows every path from the write to the function's end and judges a local as a whole: a later read of `x.b` keeps an
earlier write to `x.a` alive. It never reports a write to a `mut` parameter or through one, a write through a `match mut`
binding, or a writer call whose result is used (`lists.pop`). This program reads `total` on the next iteration, so the rule
is quiet:

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

A `str` slice counts octets. `kind[0:1]` and `text[at:at + 1]` pass every ASCII test, then trap `R_TEXT_BOUNDARY` at the
first text whose character spans the cut. `text-slice-octets` reports a slice whose end, or whose start other than `0`, is an
integer literal (`text[2:]`), a module constant or an expression over constants and literals (`text[0:WIDTH - 1]`), the
other bound plus or minus a literal, or the length of a text literal or constant (`line[len("content-length:"):]`).

It is quiet where the program tested the text it measures (`line[len(PREFIX):]` after `strings.starts_with(line, PREFIX)`
held), and never reports a found offset, `len(...)` of a variable, a start of `0`, an empty slice, or a slice of `bytes`, a
list or a text the program wrote in place. A text known to be ASCII for another reason is reported all the same: write
`# lint: allow text-slice-octets reason="..."`.

The repairs: `strings.cut_octets(text, limit)` cuts a width at the end of a character (a view; `copy(...)` it to keep it),
`strings.char_slice(text, start, end)` cuts by characters, and `strings.starts_with_at(text, prefix, at)` asks about a
prefix at an octet offset without slicing ([standard library](../standard-library.md#a-text-cut-at-a-width)).

```selka
import strings

func initial(kind: str) -> str:
    return copy(strings.cut_octets(kind, 1))

func main(out: Stream) -> int:
    print(out, initial("\u00e9clair"), len(initial("\u00e9")))
    return 0
```

## Long examples

`long-example` (`L_LONG_EXAMPLE`) reports a docstring example whose expected output runs past 120 characters on one line, or
whose `>>>` block runs past 6 lines. It never blocks; `release check` lists it as a warning. Show the call, not a dump: pick
the smallest input, show `Ok(…)` or `Err(…)` directly, and assert a property (`len(...)`, a prefix, one field) instead of
printing a large value. A display that needs the whole value takes a reasoned waiver.

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

The checker warns when a `copy(value)` carries no value, and the warning holds the edit that deletes it:

```console
$ selka check report.selka
report.selka:10:18: warning[W_NEEDLESS_COPY]: `total` only reads `rows`, so pass `rows` itself rather than a copy
        sum += total(copy(rows))
                     ^
check: ok (1 module, 0 cached)
$ selka fix report.selka --warnings
fixed report.selka: 1 edit (W_NEEDLESS_COPY)
```

The warning fires only where the copy-free form checks:

- the copy is an argument to a read-only parameter, an f-string hole or a printed value;
- the copy is the last use of an owned local, so binding the value moves it;
- a `const` copies a place of a parameter or local that does not change while the binding is read, so it can borrow;
- the copy of an owned local or `own` parameter, at its last use, is taken over (appended, stored, a constructor field, an
  `own` argument, an assignment, a return): the fix writes `own value`;
- the copy duplicates a value that is already new (a module constant, a fresh call result) or a borrowed value only read;
- the copy is the last use and the pass can make the move whole: `own row.name`, `take(mut row.name)`, `for x in own xs` with
  `own x`;
- the copies are fields of a record constructor passed to a read-only parameter of a call that is not recursive, so the
  record borrows ([B9](../ownership-rules.md#b9--const-place-bindings-borrow)); one warning holds the whole record's edits.

It stays silent in a generic instance, in a loop the value was not declared in, and while an alias or a view is live. A
`return copy(place)` of a borrowed place keeps its copy. A copy that is the point of the code takes a waiver:

```text
# lint: allow needless-copy reason="this test measures what a copy costs"
```

The lint rule reads the checker's warning, so `selka lint` reports `L_NEEDLESS_COPY` at the same line and `--gate` exits 3.

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
whole; for the rest the checker warns `W_COPY_MOVE`, which has no `fix`, and `selka lint` reports `L_COPY_MOVE`. The forms,
in the order the checker tries them:

- a local, or a field of one, that nothing reads again: `own x`, `own row.name` (a bare `x` when the value holds nothing
  managed, since `own` there is `E_OWN_MARKER`);
- a field of a `mut` local or parameter: `take(mut row.name)`, which leaves the default behind;
- a loop variable of a list nothing reads after the loop: `for x in own xs`, then `own x` or `own x.f`; for a plain list
  parameter also `own xs` in the signature and `own` at each caller's last use (`W_COPY_FOR_STORE`);
- the payload of a `match` over a fresh result, or over an owned local nothing reads after it: `own payload`, with
  `match own name:` or `const x = own name else:`;
- `opt.unwrap_or(default)` of an option nothing reads again: `options.take_or(own opt, default)`.

`take` is proposed only where nothing reads that place again. A copy that is the point of the code takes
`# lint: allow copy-move reason="..."`.

A function every return of which copies a place of one parameter is told to declare its result `from` that parameter. A
project check (`selka check DIR`) makes that `W_COPY_RETURNED`, whose `fix` writes ` from p` after the result type and each
returned `copy(PLACE)` as `PLACE`, where the function is not generic, recursive or named as a value and no caller is refused.
A `public` function is repaired too, its signature changed, when `selka.json` sets no `interface_files` and its modules have
more than one top-level name.

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

A copy at loop depth 1 or more runs on every iteration. The message names the form that fits where the copy goes, in this
order:

- the checker proves the copy-free line (`W_NEEDLESS_COPY`): a borrow ([Needless copies](#needless-copies));
- a source not read again: a move, `own x`, `take(mut x.f)` or `for x in own xs`
  ([Taking and exchanging a value](../value-semantics.md#taking-and-exchanging-a-value));
- a slice of `bytes` kept in a record, list or dictionary: a `spans.Span` into the source
  ([Long-lived data](../value-semantics.md#long-lived-data-hold-the-key-not-the-borrow));
- the same `bytes` name on every iteration, from a place the loop does not write: a `symbols` key
  ([`symbols`](../standard-library.md#symbols));
- a `str` read from the element of a `for x in xs` loop over a list the function owns: `for x in own xs`, then `own x` or
  `own x.field`;
- anything else, a `str` from a list the function is lent included: a real transfer, and the message says no more.

The judgement errs toward the last form: a name the loop changes, or a copy whose source the function reads again, is a real
transfer. A span and a symbol hold `bytes`, so a `str` is never sent to them. The span form is advice to weigh against the
code, not a proof.

## Counting copies

`selka lint --copies PATH` prints how many `copy(...)` calls the program writes (test files included, the standard library
left out) and how many per 1,000 lines, so the number can be watched over time. It prints nothing else and exits 0. Each
copy is counted once, in the first category whose finding sits on it:

- `selka fix removes them` (`L_NEEDLESS_COPY`): the copy-free form checks;
- `a move replaces them` (`L_COPY_MOVE`): the source is not read again;
- `stored from a parameter` (`L_COPY_FOR_STORE`): the copy stores a parameter;
- `in a loop` (`L_COPY_IN_LOOP`): the copy runs on every iteration;
- `named by nothing`: no finding sits on the copy.

A finding sits on a copy when it starts inside the copy's text or at the start of its statement. The categories follow the
run's profile and `--rule`; a waived copy is named by nothing. `PATH` is an entry file. `--json` prints one `copy-count-v1`
line with `entries` and a `files` list of each file's `copies` and `lines`.

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

Saved as `counts.selka`, the program writes four copies:

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

### Counting copies over several entries

`selka lint --copies A.selka B.selka ...` lints each entry as a lone entry is linted and prints one count for the union of
the files they reach:

- a file reached by several entries is counted once (`./a.selka` and `a.selka` are one file; links are not followed);
- a copy takes the best category any entry gave it, `L_NEEDLESS_COPY` first and "named by nothing" last;
- the text gains a first line `entries: N` when N is 2 or more; the JSON always has `"entries":N`.

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

The entries are the files you name. An entry that gives no count ends the command with its status and a line on standard
error (`selka lint: bad.selka gave no count (status 1), so there is no total`); a missing file is refused first, with exit
2. Several entries without `--copies`, or beside `--gate` or `--accept`, are a usage error.

### When the analysis behind the loop rules fails

`L_COPY_IN_LOOP` and `L_ALLOC_IN_LOOP` read the rows of `selka cost --sites`. A program `check` accepts can still fail that
build (a `@noalloc` promise its body breaks, a Core refusal), and the two rules then judged nothing. A run whose analysis
failed says so first, on standard error:

```console
$ selka lint main.selka
selka lint: main.selka: the analysis behind the loop rules failed (E_NOALLOC_ALLOCATES), so L_ALLOC_IN_LOOP and L_COPY_IN_LOOP were not judged
```

- **The count.** `--copies` prints `?` for "in a loop" and "named by nothing" and says how many copies the two share;
  `--json` sets `"in_loop":null` and `"unnamed":null` and adds `"split_known":false` and `"in_loop_or_unnamed":N`.
- **The status.** A failed analysis is not a finding, so without `--gate` the status is unchanged. Under `--gate` (or
  `on_build: "block"`) the run exits 3 when `copy-in-loop` was not judged, and the line adds `; --gate refuses (status 3)`.
- **Nothing to analyse.** A file with no `main` (a library, a `_test.selka` file) is no failure and prints no line.

## Copies in recursion

A recursive walk that builds its callee's context from copies copies the caller's whole context at every level. The checker
warns with `W_COPY_IN_RECURSION` when a `copy(...)` of a parameter, a loop variable over one, or a place of either is a field
of a record (or the payload of `Some` in one) passed to the function's own call:

```console
$ selka check walk.selka
walk.selka:18:35: warning[W_COPY_IN_RECURSION]: `walk` passes a copy of its own context into its recursive call, so every level copies the caller's; pass the places themselves: a record built from borrows borrows, and it may hold `Some(p)` of a read-only record parameter
        total += walk(Scope(block=copy(sb.block), parent=Some(copy(scope))))
                                  ^
check: ok (1 module, 0 cached)
$ selka fix walk.selka --warnings
fixed walk.selka: 2 edits (W_COPY_IN_RECURSION)
```

The fix deletes every copy of the record at once, and only where the record then borrows (see
[borrowed parents](../ownership-rules.md#borrowed-parents)): the record is the argument of a read-only parameter, and each
managed field is a literal, `None`, a read-only parameter or a place of one, or `Some` of such a place. Otherwise the
warning reports alone.

## Idiom rewrites

Eight compiler-shaped spellings have a shorter one the language accepts. The checker warns on each with the certain edit,
`selka fix` applies it, and `selka lint` reports the site as an `L_*` finding. None blocks.

- `W_BYTE_SET`: `c == 43 or c == 45 or c == 47` becomes `c in b"+-/"`.
- `W_RANGE_CHAIN`: `c >= 48 and c <= 57` becomes `48 <= c <= 57`.
- `W_LITERAL_MATCH`: an `if`/`elif` chain of `x == 1`, `x == 2`, `x == 3` becomes `match x:` with `case _:` for the `else`.
- `W_PATTERN_SHORTHAND`: `case text(value=value):` becomes `case text(value):`.
- `W_OPTION_TRY`: `match call():` with `case Some(x):` and `case None: return None` becomes `const x = try call()`.
- `W_ELSE_IS_TRY`: `const x = call() else Err(e):` over only `fail e` (or `return None` for an Option) becomes
  `const x = try call()`.
- `W_MATCH_ELSE`: a two-arm `match f():` whose `None` arm is `return 0` becomes `const x = f() else:` over `return 0`.
- `W_MATCH_IS`: a two-arm `match f():` whose `None` arm is `pass` becomes `if f() is Some(x):`.

Each fires only where the rewrite cannot change the program: the value tested is a plain name, field or index (never a
call), and a literal-match chain has three or more tests. `selka fix` repeats until a nested shape is settled. A site that
is the subject of a test takes a waiver, per site or for a file:

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

Four rules name work inside a loop that grows with what the loop does. The first three read the checked tree; a finding
refuses only in a declaration changed against `--against REF`. `alloc-in-loop` reads the `cost --sites` rows and only
reports.

### linear-search-in-loop

A list a loop appends to, searched with `lists.contains` (or a list `index`) in the same loop, costs one walk of everything
built so far per probe. Keep a `set` or `dict` beside it and probe that. A search on a list the loop leaves alone only
reports.

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

Removing or inserting at index 0 of a list declared outside the loop shifts every later element. Keep an index cursor, or
use `deque`.

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

Sorting a list the same loop appends to re-sorts it as it grows. Sort once after the loop, or use `heap`. A list created and
sorted once inside the iteration is not this shape.

```selka
func sort_once(n: int) -> int:
    mut window: int[] = []
    for i in range(n):
        append(mut window, (i * 7919) % 1000)
    window = sorted(window)
    return window[0]
```

### alloc-in-loop

A construction or conversion at loop depth 1 or more builds a value on every iteration; its kind and hint are those of
`selka cost --sites`. A growth site (`append`, `insert`, a sort) and a copy are not this rule. It reports only in a
declaration changed against `--against REF`, and never refuses: move the value out of the loop, or reuse one buffer.

```selka
func build(n: int) -> int:
    mut total = 0
    for i in range(n):
        const row = {"key": i}
        total += row["key"]
    return total
```

### copy-in-loop

A `copy(value)` at loop depth 1 or more copies the value on every iteration. The rule reports every one, and refuses under
`--gate` only where the declaration changed against `--against REF`. The message names the rewrites in the order to try
them: a field store through the place (`xs[i].f = value`); `exchange(index, placeholder)` for an element taken out, updated
and stored back; a `const` that borrows the place (`const row = xs[i]`); an `own` hand-off. The first example copies a
record on every iteration only to read one field; the second reads it through the loop variable. A copy that is the point
of the code takes `# lint: allow copy-in-loop reason="..."`.

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

## Owned parameters

`own` is a parameter mode: a plain parameter reads its argument, a `mut` parameter writes the caller's value, and an `own`
parameter takes it, so the caller's binding is unusable after the line and the callee may store or move the value.

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

At a call the marker is required where a named binding of a value that owns storage is given away, and refused on a fresh
value (a call result, a constructor, a literal, `copy(value)`) or a scalar: `append(mut rows, 1)` carries no marker and
`append(mut rows, own row)` does. `own` and `mut` do not combine, and a function type spells the mode:
`func(own Node) -> int`. `L_COPY_FOR_STORE` never blocks `release check`: whether every caller can give the value up is the
author's decision. The standard library's storing functions (`append`, `sets.add`, the item of `dicts.append_to`) take their
element `own`; the keys of `dicts.add` and `dicts.append_to` are borrowed and copied only when new.

## Waivers

A waiver is a directive comment on the line above a declaration:

```text
# doc: not-selka
# lint: allow function-length reason="exhaustive opcode table, split hurts review"
func dispatch(op: Op, frame: Frame) -> Result[Frame, VmError]:
    ...
```

A waiver without `reason=` is itself a finding (`L_WAIVER_REASON`), always blocking, so silencing a rule always costs a
sentence. When the same reasoned waiver repeats above many declarations, one file-level waiver replaces them:

```text
# lint: allow-file untested-export reason="the fixture programs exercise this module end to end"
```

`allow-file` covers every finding of the named rule in the file and no other rule, and needs the same `reason=`; a
per-declaration waiver covers only the declaration below it. [`release check`](release-docs.md#check-every-change-and-release)
applies the same waivers in its lint step and, for the three documentation rules, its docs step.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/lint.md).
