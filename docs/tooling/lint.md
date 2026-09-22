# Linting a project

`mylang lint` runs the project-verification layer over guest (`.my`) code. It
loads the project exactly as `check-project` does, runs every enabled rule over
the checked program, and reports findings with a fourth diagnostic code family,
`L_*`. Rules never change the inner check-run-test loop: they report during
development and refuse only at the commit gate.

## `mylang lint`

```console
$ mylang lint src/app/main.my
lint: 2 finding(s): 0 blocking, 2 report, 0 waived, 0 accepted
$ mylang lint src/app/main.my --gate
app.my:12:1: error[L_DEAD_PRIVATE]: dead-private: private app::helper has no call site
  def helper(value: int) -> int:
  ^
lint: 1 finding(s): 1 blocking, 0 report, 0 waived, 0 accepted
$ echo $?
3
```

The command takes the entry file and these options:

| Option | Meaning |
| --- | --- |
| `--gate` | Make every `block` rule refusing (exit 3) and raise its findings to error severity. |
| `--json` | Render findings as `diagnostic-v1` JSON Lines on stderr. `--diagnostics=json` does the same. |
| `--profile=NAME` | Override the configured profile for this run: `agent`, `strict` or `safety`. |
| `--accept` | Record the current findings in the baseline store under `.mylang/lint/`. |
| `--against=REF` | Judge the working tree against reference `REF` (a git revision). Only `change-without-test` reads it, and only together with `--gate`; every other rule ignores it. |

Exit statuses are `0` (valid, nothing blocking), `1` (a source, type, effect or
ownership error, with no rule evaluated), `2` (usage or configuration failure)
and `3` (valid source with at least one blocking finding).

## Profiles and the report/block split

A project with no `lint` object in `mylang.json` runs the `agent` profile:
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
setting that makes a plain `mylang lint` (no `--gate`) refuse. `min_chars`
(default 12) is the non-whitespace length floor for `undocumented-export`. A
`lint` object requires `mylang.json` `version: 2`; a version 1 document keeps
parsing without one. The configured `lint` object participates in verdict cache
identity exactly as `import_policy` does, so changing a rule mode invalidates an
earlier green.

`warnings: "deny"` is the one setting that reaches into the inner loop: with it,
a checker `W_*` diagnostic makes `check`, `check-project`, `run` and
`run-project` exit 1 instead of reporting and exiting 0. The warning is still
printed, and the run neither caches a green verdict nor lowers the program. The
default, `report`, leaves the inner loop untouched.

## Rules

| Rule | Code | Default (`agent`) | What it finds |
| --- | --- | --- | --- |
| `untested-export` | `L_UNTESTED_EXPORT` | report; block under `strict` | An exported function or public domain method that no discovered test reaches, directly or transitively, under `agent`; under `strict` and `safety` one that no test calls directly, where an export only reached transitively is reported with that wording instead. |
| `dead-private` | `L_DEAD_PRIVATE` | block | A private function with no call site anywhere in the project. |
| `undocumented-export` | `L_UNDOCUMENTED_EXPORT` | report; block under `strict` | An exported function, record, union or domain with no docstring, one under `lint.min_chars` non-whitespace characters, or one that merely restates the name. |
| `change-without-test` | `L_CHANGE_WITHOUT_TEST` | block, but only under `--gate --against REF` | A declaration that changed since `REF` and whose callers are not tests that changed in the same diff. Judged against a diff, never the standing tree, and never suppressed by a baseline. |
| `test-no-assertion` | `L_TEST_NO_ASSERTION` | block | A test body whose every `return` is the literal `true` and which never asserts. |
| `test-conditional` | `L_TEST_CONDITIONAL` | block | A branch or match, or more than one loop, at a test body's top level. |
| `test-empty` | `L_TEST_EMPTY` | block | A discovered test with an empty body. |
| `waiver-reason` | `L_WAIVER_REASON` | always block | A `# lint: allow` comment with no `reason="..."`. |
| `function-length` | `L_FUNCTION_LENGTH` | report only | A function over `rules.function-length.max` lines (default 80). |
| `parameters` | `L_PARAMETERS` | report only | A function over `rules.parameters.max` parameters (default 6). |
| `nesting-depth` | `L_NESTING_DEPTH` | report only | A function over `rules.nesting-depth.max` control-nesting levels (default 4). |
| `decision-points` | `L_DECISION_POINTS` | report only | A function over `rules.decision-points.max` decision points (default 10). |
| `dead-export` | `L_DEAD_EXPORT` | report only | An exported declaration with no caller anywhere in the project; ambiguous for a library, so it never blocks. |
| `integration-tests` | `L_TEST_CAPABILITY` | report only | A discovered test whose parameters request `Filesystem`, `Network`, `Clock` or `Entropy` in a module outside `rules.integration-tests.modules` (default `*_integration`, `integration.*`). |
| `record-size` | `L_RECORD_SIZE` | report only | A `record` or `class` over `rules.record-size.max` fields (default 7). |
| `file-length` | `L_FILE_LENGTH` | report only | A module over `rules.file-length.max` code lines (default 1000). Blank and whole-line `#` comment lines do not count. |
| `bool-ops-per-condition` | `L_BOOL_OPS` | report only | One branch or loop condition combining more than `rules.bool-ops-per-condition.max` `and`/`or` operators (default 3). |
| `naming` | `L_NAMING` | report only | A function, parameter, local, `record`, `union` or `domain` that is not snake_case/PascalCase or is on the vague-name list (`tmp`, `data`, `info`, `obj`, `mgr`, `Helper`, `Util`, `Manager`). |
| `repeated-literal` | `L_REPEATED_LITERAL` | report only | An integer literal other than `0` or `1` appearing three or more times in one module. |
| `same-type-adjacent-params` | `L_SAME_TYPE_ADJACENT_PARAMS` | report only | Adjacent parameters sharing one non-capability type, where a keyword argument reads better. |
| `duplicate-body` | `L_DUPLICATE_BODY` | report only, never blocking | Two or more checked functions whose normalized bodies are identical. |
| `output-in-library` | `L_OUTPUT_IN_LIBRARY` | report only | A function whose inferred effects include `output` in a module outside `rules.output-in-library.modules` (default `main`, `*_cli`, `cli`, `cli.*`, `*_integration`, `integration.*`). |
| `sentinel-int` | `L_SENTINEL_INT` | report; block under `strict` | An `int` used as a sentinel: a function that returns a negative integer literal on some path and whose result a caller compares against a negative literal (or the `< 0`/`>= 0` presence guards), and a parameter or record field compared against `-1` in two or more places. Every finding names the `Option[int]` rewrite. A function named `find` or `find_any` is exempt, because `-1` is that method's own contract. |

The section-9 advisory rules are `.report` under `agent`, `strict` and
`safety`: they measure, print and never refuse. `integration-tests` is likewise
report-only, but a test in a matching module is exempt by construction, so the
default `*_integration` / `integration.*` globs keep a project's own integration
suite quiet.

A finding that names a declaration also carries the discovered tests that reach
it as a related note, from the same index `mylang tests-for` answers from and
the same one the `untested-export` verdict reads, so the report says which test
to extend without a second command and cannot claim a declaration is unreached
where `tests-for` names a test.


## Waivers

A waiver is a directive comment on the line above a declaration, in the same
family the documentation gate already parses:

```text
# doc: not-mylang
# lint: allow function-length reason="exhaustive opcode table, split hurts review"
def dispatch(op: Op, frame: Frame) -> Result[Frame, VmError]:
    ...
```

A waiver without `reason=` is itself a finding (`L_WAIVER_REASON`), always
blocking, so silencing a rule always costs a sentence explaining why.
