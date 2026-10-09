# Idiom coverage — lane C C3 (every rejection names the accepted spelling)

Package: **raise lane C C3** in the agent-usefulness plan (`D1`'s unmet target, taken
up as C3). Worktree: `mylang/.worktrees/agent-usefulness`. Measured 2026-09-20.

The package's instrument is `velocity/score.py` lane C over the 110 probes in
`velocity/suites/idioms/`. **C3** counts a rejection whose `diagnostic-v1` record carries a
non-null `fix` or a note whose `role` is `alternative`. **C2** (a probe that runs to
completion with the wrong answer) is a gate: any C2 blocks a package.

## Result

| metric | before | after | target |
| --- | --- | --- | --- |
| C1 first-try fidelity | 0.254 (17/67) | 0.254 (17/67) | 0.9 (plan) |
| C2 silent wrong answers | 0 | 0 | 0 (gate) |
| C3 rejections with a fix or alternative | **0.304 (24/79)** | **0.633 (50/79)** | **>= 0.5 (met)** |
| C3_text_any (secondary, not C3) | 0.354 (28/79) | 0.506 (40/79) | n/a |
| C3_text_spelling (secondary) | 0.038 (3/79) | 0.127 (10/79) | n/a |

26 rejections gained a structured alternative and none lost one. C1 and C2 are
byte-for-byte the same as the starting measurement: every change adds a note or a
targeted message to a program the compiler already rejected.

The plan's `D1` target for C3 was `>= 0.5`; this package reaches **0.633**. The plan's
goal.json target of 0.95 is **not** reached, and 29 rejections still carry no
alternative. The last section lists each one and why no accepted spelling is knowable
at that site.

## Commands

```sh
# starting measurement (staged binary, qbe pinned out of the shared cache)
python3 velocity/score.py --binary zig-out/bin/mylang --json --write velocity/suites/idioms/score-C3-before.json
#   C1 first-try fidelity      0.254  (17/67 oracle: cpython probes)
#   C2 silent wrong answers    0
#   C3 rejections with a fix   0.304  (24/79 rejected)

# build and stage the compiler under test
./zigw build && ./stage.sh

# finishing measurement of the *installed* binary after a green build, and the
# suite manifest regenerated from it (the install step is gated on Guardian, and
# this run followed `guardian: run-all: 88 check(s) passed`)
./zigw build
python3 velocity/score.py --binary zig-out/bin/mylang \
    --write velocity/suites/idioms/score-C3-after.json \
    --write-manifest velocity/suites/idioms/manifest.json
#   C1 first-try fidelity      0.254  (17/67 oracle: cpython probes)
#   C2 silent wrong answers    0
#   C3 rejections with a fix   0.633  (50/79 rejected)
#   C3_text_any (secondary, existing prose, not C3): 0.506 (40/79)
#   score.py: wrote velocity/suites/idioms/manifest.json (110 probes)

# the detectors themselves
python3 velocity/score.py --self-test
#   lane C detector self-test: 14 passed
#   cpython oracle self-test: 5 passed

# the one-table agreement (parser table vs friction classifier) and the compiler
python3 tests/parser_hints.py --compiler ./zig-out/bin/mylang
#   hint table and classifier agree on 19 forms
#   probes print the hinted message, span and accepted spelling

# the unit tests for the new behaviour
python3 scripts/focused_test.py units accept        # result: PASS - 54 passed, 0 failed
python3 scripts/focused_test.py units "dict get"    # result: PASS - 12 passed, 0 failed

# the whole Zig unit root, unsharded, so nothing the parser touches is left unchecked
./zigw build test-units
#   guardian/test: PASS - 1295 passed
#   guardian/test: RESULT {"passed":1295,"failed":0,"skipped":0}
#   (the step then reports peak memory 2.44GB above the 2.15GB single-process
#    bound, which is why the gate shards this root into 12 processes; the test
#    verdict itself is PASS)

# the friction harvest still reads the classifier it shares with the parser
python3 tests/test_friction_harvest.py
#   Ran 11 tests in 0.441s / OK

# the documentation examples still run
./zig-out/bin/mylang doctest . --filter docs/python-syntax.md
#   docs/python-syntax.md: 9 run, 6 checked, 0 skipped, 0 mis-tagged, 0 failed
```

The two result documents record the compiler that produced them:
`score-C3-before.json` is binary `sha256:13049d85c9f94f3e...` with
`compiler_sha256:41cde41f413129f6...`, and `score-C3-after.json` is binary
`sha256:b3265ab0679338dc...` with `compiler_sha256:d6bc5756105a656c...` — the installed
artifact of the green build. Both name `zig 0.17.0-dev.1683+5ceec001b debug
x86_64-linux-gnu`.

`MYLANG_QBE` was pointed at a copy of the freshly built `qbe` and
`ZIG_GLOBAL_CACHE_DIR` at the checkout's cache for the runs above, because this
sandbox has no writable `$HOME`; that is an environment detail, not a measurement
choice — the scored binary is the staged `zig-out/bin/mylang` whose sha256 and
`compiler_sha256` the result document records.

## No collateral change

Comparing the two result documents probe by probe:

* every probe keeps its verdict — `verdict changes: []`, and the 31 accepted probes
  before are exactly the 31 accepted probes after;
* the C1 agreement set is identical (`agree set equal: True 17 17`);
* exactly 24 probes have a different first message, and all 24 are probes this package
  re-messaged on purpose (the 15 hinted `E_SYNTAX` forms, the five `E_EXPRESSION` forms,
  the two tuple shapes, and the two `dict.get` calls, which changed only by an added
  note); every other rejection and every accepted program reports the same bytes.

So no existing diagnostic code changed and no untouched diagnostic's text or JSON moved,
except where a targeted message replaced the generic one for a rejection that was already
happening.

## Per-probe classification

The 79 rejected probes, with the primary diagnostic code and whether C3 credited the
rejection before and after. The 26 `no -> yes` rows are the package's work.

| probe | primary code | C3 before | C3 after |
| --- | --- | --- | --- |
| `a01_ternary.my` | E_SYNTAX | no | yes |
| `a02_chained_cmp.my` | E_TYPE | no | no |
| `a03_tuple_swap.my` | E_SYNTAX | no | yes |
| `a04_tuple_return.my` | E_SYNTAX | no | yes |
| `a05_is_none.my` | E_SYNTAX | no | yes |
| `a10_chained_assign.my` | E_SYNTAX | no | yes |
| `a11_truthiness.my` | E_TYPE | no | no |
| `a13_nested_def.my` | E_EXPRESSION | no | yes |
| `a14_lambda_capture.my` | E_LAMBDA_CAPTURE | no | no |
| `a16_fstring_spec.my` | E_FORMAT_STRING | no | no |
| `a17_percent_format.my` | E_TYPE | no | no |
| `a18_str_format.my` | E_COLLECTION_METHOD | yes | yes |
| `a19_str_repeat.my` | E_TYPE | no | no |
| `a21_set.my` | E_UNKNOWN_TYPE | no | no |
| `a22_set_literal.my` | E_SYNTAX | no | yes |
| `a23_optional_annot.my` | E_TOKEN | no | no |
| `a24_optional_typing.my` | E_SYNTAX | yes | yes |
| `a26_sort_key.my` | E_CALL_ARGUMENT | no | no |
| `a28_sorted_reverse.my` | E_CALL_ARGUMENT | yes | yes |
| `a30_range_step.my` | E_ARITY | no | no |
| `a32_join_map.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `a33_round2.my` | E_ARITY | no | no |
| `a34_power.my` | E_EXPRESSION | no | yes |
| `a35_div.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `a36_module_global.my` | E_SYNTAX | yes | yes |
| `a37_const.my` | E_SYNTAX | yes | yes |
| `a38_class_methods.my` | E_SYNTAX | yes | yes |
| `a39_dataclass.my` | E_SYNTAX | yes | yes |
| `a40_try_except.my` | E_SYNTAX | no | yes |
| `a41_import_os.my` | E_MODULE_HEADER | no | no |
| `a42_open_python.my` | E_ARITY | yes | yes |
| `a44_enumerate_start.my` | E_ARITY | no | no |
| `a47_print_record.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `a48_for_else.my` | E_EXPRESSION | no | yes |
| `a49_match_literal.my` | E_SYNTAX | no | yes |
| `a50_match_str.my` | E_SYNTAX | no | yes |
| `a51_del.my` | E_SYNTAX | no | yes |
| `a53_multiline_str.my` | E_SYNTAX | no | yes |
| `a54_bitops.my` | E_REMOVED_SPELLING | no | no |
| `a55_chr_ord_hex.my` | E_UNKNOWN_FUNCTION | no | no |
| `a56_divmod_pow.my` | E_SYNTAX | no | yes |
| `a57_assert_fstring.my` | R_ASSERT | x was 1 |
| `a60_overflow.my` | R_OVERFLOW | no | no |
| `a61_result_unwrap.my` | E_SYNTAX | no | yes |
| `a62_option_or.my` | E_ARITY | no | yes |
| `a63_dict_get_option.my` | E_ARITY | no | yes |
| `a65_str_cmp.my` | E_TEXT_OPERATOR | no | no |
| `a66_nested_comp.my` | E_SYNTAX | no | yes |
| `a67_dict_comp.my` | E_SYNTAX | no | yes |
| `a68_genexp.my` | E_SYNTAX | no | yes |
| `a69_print_end.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `a70_int_from_float.my` | E_SYNTAX | no | yes |
| `a71_type_alias.my` | E_SYNTAX | yes | yes |
| `a73_while_else_walrus.my` | E_SYNTAX | no | yes |
| `a75_list_of_records_mutate.my` | E_ASSIGNMENT_TARGET | no | no |
| `a77_dict_record_key.my` | E_DICT_KEY | no | no |
| `a79_str_methods.my` | E_LIST_METHOD | no | no |
| `a80_none_return_call.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `c02_result_err_convert.my` | E_TYPE | no | no |
| `c06_result_record_err.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `c08_match_expr.my` | E_EXPRESSION | no | yes |
| `d01_loop_record_copy.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `d02_alias_record_copy.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `d03_record_param_mutate.my` | E_ASSIGNMENT_TARGET | no | no |
| `d04_dict_items_keys.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `d05_round_half.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `d06_record_field_in_dict_loop.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `d07_str_index_assign.my` | E_COLLECTION_METHOD | no | no |
| `d08_int_float_mix.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `d09_shadow_builtin.my` | E_SHADOWING | no | no |
| `d10_unused_result.my` | E_EXPLICIT_DISCARD_REQUIRED | no | no |
| `e02_bitops_each.my` | E_TOKEN | no | no |
| `e03_shift.my` | E_EXPRESSION | no | yes |
| `e08_format_float.my` | E_MODULE_NAME | no | no |
| `e09_walk_dict_sorted.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `e10_while_assign_after_loop.my` | E_UNBOUND | no | no |
| `e11_if_no_else_bind.my` | E_OUTPUT_CAPABILITY | yes | yes |
| `e12_none_default_param.my` | E_OUTPUT_CAPABILITY | yes | yes |

## The forms added, and the accepted spelling each names

Fifteen `E_SYNTAX` statement forms joined the one shared
`declaration_hints` table in `src/parser.zig`; `velocity/friction/classifier.json`'s
`hints` array and its `E_SYNTAX` rules gained the same idioms, so
`src/declaration_hints_test.zig` and `tests/parser_hints.py` check both sides. Five
forms whose rejection is not `E_SYNTAX` carry the alternative directly, and one
collection-method rejection gained an alternative through
`buffer_operations`/`alternativeFor`.

| form | probes | diagnostic | accepted spelling the note names |
| --- | --- | --- | --- |
| `ternary` | a01, a70 | `E_SYNTAX` at the `if` | write an if/else statement that assigns the same name |
| `tuple` | a03, a04, a56 | `E_SYNTAX` at the comma | bind one name per statement and use a temporary variable; declare a record to return several values |
| `is-none` | a05 | `E_SYNTAX` at `is` | compare the value with `== None`, or match it: `case Some(value)` and `case None` |
| `chained-assign` | a10 | `E_SYNTAX` at the second `=` | assign one name per statement: `x = 21` first, then `y = 21` |
| `set-literal` | a22 | `E_SYNTAX` at the comma | use a dict literal keyed by the value: `{1: True, 2: True}` |
| `exceptions` | a40 | `E_SYNTAX` at the `try` suite | return `Result` and match it: `case Ok(value)` and `case Err(reason)` |
| `match-literal` | a49, a50 | `E_SYNTAX` at the literal | compare literals with `if`/`elif`: `if x == 1:` then `elif x == 3:` |
| `del` | a51 | `E_SYNTAX` after `del` | remove with `_ = xs.pop(index)` for a list or `_ = d.pop(key)` for a dictionary |
| `string-prefix` | a53 | `E_SYNTAX` at the literal | drop the prefix and write the escape in an ordinary quoted string |
| `main-guard` | a58 | `E_SYNTAX` at the top-level `if` | delete the guard: `mylang run` calls `def main()` directly |
| `option-unwrap` | a61 | `E_SYNTAX` at `unwrap` | extract with `match`: `case Ok(value)` or `case Some(value)`; `?` propagates a `Result` |
| `nested-comprehension` | a66 | `E_SYNTAX` at the second `for` | write the loops out and append |
| `dict-comprehension` | a67 | `E_SYNTAX` at the `for` | build the dictionary with a loop |
| `generator-argument` | a68 | `E_SYNTAX` at the `for` | materialize a list instead: `any([x > 2 for x in xs])` |
| `walrus` | a73 | `E_SYNTAX` at the `:=` | assign the name on its own line first, then test it |
| nested `def` | a13 | `E_EXPRESSION` | declare the function at the top level and call it from the body |
| loop `else` | a48 | `E_EXPRESSION` | use a flag: assign it before the loop, set it before `break`, and test it after |
| `match` expression | c08 | `E_EXPRESSION` | assign the value in each branch of an if/elif statement |
| `**` | a34 | `E_EXPRESSION` | multiply in a loop |
| `<<` / `>>` | e03 | `E_EXPRESSION` | use `shift_left(value, count)` or `shift_right(value, count)` |
| `dict.get(key)` | a62, a63 | `E_ARITY` | a dictionary `get` always takes its fallback: `d.get(key, default)` |

Every `E_SYNTAX` form is a shape the parser already rejected: the hint is consulted only
where the terminator, the suite's indent, the call's `)`, the literal's `:` or the
declaration head has already failed, so no previously-rejected program becomes legal and
no previously-accepted program changes message. The five `E_EXPRESSION` forms keep their
code and span and add one note: a `**` or `<<` written where an expression is expected
keeps its former message unless the preceding token is the same operator.

Proof that the accepted spellings are real, not prose invented at the failure site:
the doc examples for the new table entries live in `docs/python-syntax.md` and run under
`mylang doctest` (`9 run, 6 checked, 0 failed`), and the spellings themselves are the
constructs the language guide already documents — an if/else statement, a record, a
dict literal, `Result`/`match`, `pop`, `shift_left`, `Option[int]`, `?`, `len`, an
f-string.

## What remains uncredited, and why

| probe | code | primary message |
| --- | --- | --- |
| `a02_chained_cmp.my` | E_TYPE | expected bool, found int |
| `a11_truthiness.my` | E_TYPE | expected bool, found list[int] |
| `a14_lambda_capture.my` | E_LAMBDA_CAPTURE | lambda cannot capture local `k`; use a top-level function or pass the  |
| `a16_fstring_spec.my` | E_FORMAT_STRING | format specifications are not supported; convert the value before inte |
| `a17_percent_format.my` | E_TYPE | expected str, found int |
| `a19_str_repeat.my` | E_TYPE | expected str, found int |
| `a21_set.my` | E_UNKNOWN_TYPE | type is not declared |
| `a23_optional_annot.my` | E_TOKEN | unexpected character in source |
| `a26_sort_key.my` | E_CALL_ARGUMENT | keyword arguments require a declared function or record constructor |
| `a30_range_step.my` | E_ARITY | range requires end or start, end |
| `a33_round2.my` | E_ARITY | `round(value: float) -> float` takes 1 argument, but this call passes  |
| `a41_import_os.my` | E_MODULE_HEADER | file must begin with a module declaration |
| `a44_enumerate_start.my` | E_ARITY | enumerate requires one iterable and two iteration names |
| `a54_bitops.my` | E_REMOVED_SPELLING | `&` was removed and has no replacement |
| `a55_chr_ord_hex.my` | E_UNKNOWN_FUNCTION | no function has this qualified name |
| `a57_assert_fstring.my` | R_ASSERT | x was 1
/home/epentland/ai/canopy/mylang/.worktrees/agent-usefulness/v |
| `a60_overflow.my` | R_OVERFLOW | native execution failed (add: left 9223372036854775807, right 1, width |
| `a65_str_cmp.my` | E_TEXT_OPERATOR | managed collections support equality and str/bytes support concatenati |
| `a75_list_of_records_mutate.my` | E_ASSIGNMENT_TARGET | augmented assignment to a record field is not supported; write the fie |
| `a77_dict_record_key.my` | E_DICT_KEY | dictionary keys must be integers or str |
| `a79_str_methods.my` | E_LIST_METHOD | unknown method for a str receiver; accepted methods: count, encode, en |
| `c02_result_err_convert.my` | E_TYPE | expected int, found str |
| `d03_record_param_mutate.my` | E_ASSIGNMENT_TARGET | augmented assignment to a record field is not supported; write the fie |
| `d07_str_index_assign.my` | E_COLLECTION_METHOD | operation is not supported by this collection |
| `d09_shadow_builtin.my` | E_SHADOWING | binding shadows an active local or top-level function |
| `d10_unused_result.my` | E_EXPLICIT_DISCARD_REQUIRED | a standalone non-unit value requires `_ =` or result handling |
| `e02_bitops_each.my` | E_TOKEN | unexpected character in source |
| `e08_format_float.my` | E_MODULE_NAME | declared module name does not match its requested path |
| `e10_while_assign_after_loop.my` | E_UNBOUND | name may be read before it is assigned; some control-flow path reachin |

Grouped by why no accepted spelling is knowable at the failure site (the 29 rows
above, partitioned so every row is in exactly one group):

* **The language deliberately has no replacement** (8): `a54_bitops` and
  `e02_bitops_each` are `&` and `|` — `src/removed_names.zig` already says `&` "was
  removed and has no replacement", and `|`/`^`/`~` are rejected by the lexer before any
  site this package owns; `a19_str_repeat` (`"ab" * 3` has no operator or method);
  `a21_set` (there is no set type); `a65_str_cmp` (`str` has no ordering operator);
  `a77_dict_record_key` (dict keys are `int` or `str`); `d07_str_index_assign` (strings
  are immutable); `a79_str_methods` (`title` has no equivalent, and the message already
  lists the accepted method spellings). Correct silence.
* **Runtime traps, not rejections** (2): `a57_assert_fstring` (`R_ASSERT`) and
  `a60_overflow` (`R_OVERFLOW`) are traps in programs the compiler accepts; the failure
  is the guest's, so there is no spelling to name.
* **A repair exists but is a formula rather than a spelling** (3): `a30_range_step`
  (`range` takes one or two bounds; a step needs a `while` loop), `a33_round2`
  (`round` takes one argument; scaling before and after is arithmetic), and
  `a44_enumerate_start` (the offset has to be added inside the loop).
* **The failure site cannot name an accepted spelling without inventing one** (3):
  `c02_result_err_convert` is a propagated `Result` error type that does not match the
  enclosing declaration, and which of the two types to change is the author's decision;
  `d09_shadow_builtin` needs a new name only the author can choose; `a26_sort_key` is the
  ledger's follow-up 4 — the keyword check fires before the receiver type is known, so no
  accepted callee can be named truthfully there.
* **A known spelling exists; a later round should add it** (13): `a41_import_os`
  (`E_MODULE_HEADER`, a `fix` edit can insert the module line), `e08_format_float`
  (`E_MODULE_NAME`, a `fix` edit can rename the declaration to its path),
  `d10_unused_result` (`_ = value`), `d03_record_param_mutate` and
  `a75_list_of_records_mutate` (their message already says "write the field out in
  full"), `e10_while_assign_after_loop` (predeclare it before the loop, documented in
  `docs/python-syntax.md`), `a55_chr_ord_hex` (`strings.ord`/`strings.chr`, and `hex` is a
  module), `a14_lambda_capture` (its own message names the top-level function),
  `a23_optional_annot` (`Option[int]`), `a02_chained_cmp` (join with `and`),
  `a11_truthiness` (`len(xs) > 0`), `a17_percent_format` (an f-string), and
  `a16_fstring_spec` (convert or pad the value before interpolating it). These are
  recorded as remaining scope, not as unknowable.

## Honest statement of the target

* C3 reached **0.633 (50/79)** against the package target of **>= 0.5** — met.
* C2 stayed **0** across every measurement in this package, and `--gate` was never
  tripped. **Caveat, carried from the ledger and verified here:** the suite's only
  silent-wrong-answer probe (`d05_round_half.my`) is rejected before it runs
  (`E_OUTPUT_CAPABILITY`), so `C2 = 0` certifies only that no probe that *did* run
  disagreed with CPython. The divergence it exists to expose is live: measured in this
  worktree, `def main() -> int: return int(round(2.5))` answers `3` under
  `zig-out/bin/mylang` and `2` under CPython, and `docs/python-syntax.md` documents
  "halves away from zero" as the language's rule. Restoring a running `round` probe
  therefore *would* report `C2 = 1` and block this package, so it was deliberately not
  added: it is a `round` semantics decision (lane C's C1/C2 work), not a C3 rejection, and
  this note is here so `C2 = 0` is not read as a certification that no divergence exists.
* C1 is unchanged at **0.254 (17/67)**. Nothing in this package was allowed to move it:
  every hinted shape was already rejected, and the parser's acceptance set is identical.
* The plan's `goal.json` C3 target of **0.95 is not reached**. 29 rejections still carry
  no alternative; the section above names each one and gives the reason. The single
  largest remaining group (13) is "a known spelling exists but was not added in this
  round", which is a scope statement, not a claim that they are unknowable.
