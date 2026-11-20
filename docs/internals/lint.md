# Linting a project: how it works

What the [lint guide](../tooling/lint.md) leaves out: the full rule table, the exact shapes each rule and rewrite fires on,
and how the analysis behind the loop rules fails. Each section keeps the heading of the guide's section it belongs to.

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
| `copy-in-loop` | `L_COPY_IN_LOOP` | block in an `--against` diff | A copy the Core passes placed at loop depth 1 or more, read from the `cost --sites` rows. Under rule C every copy is written, so each one is a choice: the rule reports it in every declaration and refuses under `--gate` only in a changed one. The message is one line that names the zero-copy form which fits where the copy goes, with the section that teaches it: a borrow (the checker's `W_NEEDLESS_COPY` already proves the copy-free form), a move (`own x`, `take(mut x.f)`, `for x in own xs`: the source is not read again), a `spans.Span` into the source (the copy is a slice of `bytes` that is kept), an interned `symbols` key (the same `bytes` name, read from a place the loop does not write, is copied every iteration), for a `str` the loop that takes the elements (`for x in own xs`, since a span and a symbol hold `bytes` and are refused for `str`), or nothing more for a real transfer. It names the form and never repairs: `selka fix` writes the moves and borrows the checker proves, as `W_NEEDLESS_COPY`. The rows are those of the functions `main` reaches and, when the checked project has discovered tests (a `_test.selka` file linted as the entry has no `main`), of the functions each test reaches. A reasoned waiver takes a copy that is the point. See [Copies in a loop](../tooling/lint.md#copies-in-a-loop). |
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
| `copy-move` | `L_COPY_MOVE` | report only | A copy whose source is not read again, where a move replaces it and the rewrite is not certain: `take(mut x.f)` of a place declared with no `const` to make `mut` (a loop variable, one name of several), `options.take_or(own opt, default)` where a local named `options` or a comment is in the way or a statement around the copy holds `opt`, `for x in own xs` over a field, a list the function does not own or a list parameter a caller keeps, `match own` that an arm or a later line stops, and `from` that a caller stops. It reads the checker's `W_COPY_MOVE`, which carries no `fix`; see [Moves instead of copies](../tooling/lint.md#moves-instead-of-copies). |
| `copy-for-store` | `L_COPY_FOR_STORE` | report only | A parameter that is `copy`-ed into storage, in one of the three storing shapes: a record field (`State(keys=copy(keys))`), an element or field assignment (`hub.conns[id] = copy(state)`), or a list write (`append(mut rows, copy(row))`). A statement that copies several parameters (a constructor with four `copy(...)` fields) gets one finding for each parameter, at that parameter's own `copy(...)`; a parameter copied twice in one statement is named once. A parameter that is already `own`, one that is `mut`, and one whose type holds no managed storage (a record of numbers: `own` on it is `E_OWN_MARKER`) get no finding, because declaring them `own` cannot be done or changes nothing. The value is then independently owned, so the finding suggests declaring the parameter `own` and passing `own arg` where every caller can give the value up. Report only: the copy is correct, and the change moves every caller's binding, so the author decides. See [Owned parameters](../tooling/lint.md#owned-parameters). |
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
| `text-slice-octets` | `L_TEXT_SLICE_OCTETS` | report only, never blocking | A slice of a `str` whose end or start is an integer literal, a module constant, the length of a text literal or constant, an expression over those, or the other bound plus or minus a literal (`kind[0:1]`, `text[0:WIDTH - 1]`, `text[at:at + 1]`, `text[2:]`, `line[len("content-length:"):]`; quiet where a `strings.starts_with` or `ends_with` of the same literal or constant guards the cut): cuts that count octets without having found them, which trap `R_TEXT_BOUNDARY` at the first text whose character spans the cut. See [A text cut at a count of octets](../tooling/lint.md#a-text-cut-at-a-count-of-octets). |
| `dead-write` | `L_DEAD_WRITE` | off in every profile; report only under `--rule=dead-write` | A write to a local, to a field or element of a local, or a call that writes a local (`append(mut x, ...)`, `sets.add(mut x, ...)`, `helper(mut x)`), when no path from the write to the function's end reads the local again. A write to a `mut` parameter or through a `match mut` binding reaches the caller and is never reported. See [Writes nothing reads](../tooling/lint.md#writes-nothing-reads). |

A file whose first line is a `#` comment starting `generated by …`, in any letter case
(`# generated by …` or `# GENERATED by …`), is exempt from
every rule, because its text is a build product rather than a review surface: lint
drops its findings before any mode resolves, so neither a plain run nor `--gate` sees
them. An imported standard-library module is never the project's review surface
either: its findings are dropped the same way, unless the linted entry is itself in
the standard library.

The three documentation rules exempt `*_test.selka` modules and the standard
library. [`selka release check`](../tooling/release-docs.md) evaluates them as blocking in
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

## A text cut at a count of octets

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

## Needless copies

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

## Moves instead of copies

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

### When the analysis behind the loop rules fails

- **The count.** `--copies` cannot split the copies no earlier rule names between "in a loop" and "named by nothing", so it
  does not print a `0` for either. The text puts `?` where the number would be and says how many copies the two lines share;
  `--json` keeps `"schema":"copy-count-v1"` and, only in this case, sets `"in_loop":null` and `"unnamed":null`, adds
  `"split_known":false` and `"in_loop_or_unnamed":N`. The schema name does not change because a run whose analysis ran prints
  the document it always printed, byte for byte, and the one new key is absent from it (as `entries` was new and the schema
  stayed). A reader tests `split_known` (absent means known); one that ignores it and adds `in_loop` reads `null`, never a false
  0. `needless`, `move` and `for_store` stay exact, since those rules do not read the analysis. With several entries the
  total is unknown when any entry's split is.

## Idiom rewrites

Each fires only where the rewrite cannot change the program: the value tested is a plain name, field or index (never a
call), the bytes are integer literals, a literal-match chain has three or more tests of an integer, or of a `str` or `bytes` name (never an Option, a `str` or `bytes` field or element, or a value in a generic function, where a literal arm is refused), with no comment between its
bodies and a body that can be re-indented, an Option match ends its block in a function that returns `T?`, and a bind-or-else has an `else` block of that one statement, no comment and a call as its value (`try` over a borrowed place would take the payload). `W_MATCH_ELSE` and `W_MATCH_IS` read a `match` written in the source with exactly the two cases of an Option or a Result (checked, so a generic body draws none), each binding one name or `_`, not `match mut`, and the success arm's statements move into the enclosing block only when nothing after the `match` declares a name they declare; `match own x` becomes `const x = own x else:` and has no `is` form. Where `W_OPTION_TRY` reports a `match`, `W_MATCH_ELSE` does not, and a bind-or-else it writes that only passes the failure on draws `W_ELSE_IS_TRY` in the next round. A comment on a `case` line moves to the line written for it. A run
settles a nested shape over rounds: `selka fix` repeats until nothing is left. A site that is the subject of a test
