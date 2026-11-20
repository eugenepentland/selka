# Checked project documentation

`selka release check` checks the generated overview (`OVERVIEW.md`), docstrings whose examples run as tests, and
decision files that say why each public change was made, along with formatting, checking, lint and tests. It requests no
optimized build. `selka test` also runs docstring examples.

## Write the current design in docstrings

The module docstring goes after the imports, before the first declaration; a function or type's docstring is first in
its body. Give the reasons the signature cannot, and a runnable call for every public function.

```selka
# doc: expect 42
"""Line totals use integer cents so rounding never depends on floating point."""

public func line_total(quantity: int, unit_cents: int) -> int:
    """Multiply a count by its price in cents; tax is applied by the caller.

    >>> line_total(2, 21)
    42
    """
    return quantity * unit_cents

public func test_line_total() -> bool:
    return line_total(2, 21) == 42

func main() -> int:
    return line_total(2, 21)
```

- An example starts with `>>> `; `... ` continues its source. The lines after it are the expected output, up to a blank
  line, another example or the end of the docstring. `<BLANKLINE>` is an empty output line. Output must match exactly.
- A string or bytes value prints with `repr`. Statements and unit expressions show nothing. Output written to `out`
  comes before a displayed value.
- Examples in one docstring share a function, so a binding carries to the next. Private module helpers are in scope.
  `fs`, `net`, `clock`, `entropy` and `env` are the stand-ins of
  [test capability parameters](guest-tests.md#capability-parameters).
- A failed example is reported at its docstring line. The case name is `module::function.example`.

```console
$ selka test . --filter .example
$ selka test . --filter line_total.example --force
```

Module and type docstrings need no example. `main`, test functions, `*_test.selka` modules and public constants are
exempt (constants cannot carry docstrings). A waiver for a public function goes on the preceding line and the overview
shows its reason:

```text
# lint: allow missing-example reason="accepts a live socket; covered by server_test::test_serve"
```

`undocumented-module` and `missing-example` are off in plain lint's `agent` profile and report in `strict` and
`safety`. `release check` makes them blocking, with `undocumented-export`, in every profile.

## Adopt an existing project

`PROJECT` is a directory holding `selka.json`, or an entry `.selka` file in its root. Record the current public
interface once; choose one form:

```console
$ selka release init .
$ selka release init . --adopt-comments
```

`init` refuses to overwrite a baseline. It creates `release/baseline.txt`, `release/history.txt`, `decisions/unreleased/`
and the overview, and does not make an undocumented project releasable.

`--adopt-comments` turns the comment block above the imports into the module docstring, and a comment block directly
above a public declaration (no blank line between) into its docstring. A block after a blank line, a banner
(`# =====`), `# lint:` directives, comments inside bodies, existing docstrings and comments on constants stay. Each
adoption prints `adopt-comments: PATH:LINE: TARGET`; `--dry-run` prints the same lines and writes nothing:

```console
$ selka release init . --adopt-comments --dry-run
adopt-comments: main.selka:4: main::answer
```

## Generate and check the overview

`selka overview PROJECT --write` writes two shapes:

- `OVERVIEW.md`, a summary to read top to bottom: modules, authority, pending decisions, public declarations, releases.
- `reference/<module>.md`, one file per module, to look things up: signatures, docstrings and examples, contracts, tests,
  holes, waivers and decisions.

```console
$ selka overview . --write
$ selka overview . --check
$ selka overview . --check --json
```

`--write` regenerates both and removes a reference whose module is gone. `--check` compares them to exact bytes, exits 1
when either differs, and prints diffs capped at 60 lines with a repair command. JSON output is `overview-v1`: `markdown`
is the summary and `references` lists every generated file.

Resolve a merge conflict by taking either version and running `selka overview . --write`. For an HTML page see
[the project page](change-review.md#the-project-page).

## Record each public-interface change

Added declarations, changed interfaces and removals since the baseline need a pending decision (public is an addition,
private a removal). Body-only edits need none.

```console
$ selka release draft . --name per-line-rounding --date 2026-10-19
```

The draft names every uncovered change; replace its placeholders. A decision:

```text
# Round each line before summing

Date: 2026-10-19
Changes: totals::line_total
Why: The invoice audit compares individual line amounts, so rounding only the
invoice total can disagree with the amounts a customer sees on each line.
Rejected: rounding the complete invoice, which loses the per-line audit trail.
```

- The first line, `Changes:` and `Why:` are required.
- `Changes:` is a comma-separated list of current public names or baseline names (so a removal can be explained).
- `Why:` has at least 30 non-whitespace characters and no `TODO`, `TBD`, `FIXME` or `<why>`.
- `Date:` is optional and comes only from `--date`.
- One file per decision under `decisions/unreleased/`. Only pending decisions are validated. `draft` never overwrites.

## Check every change and release

While you work, check decisions and overview without tests:

```console
$ selka overview . --write
$ selka release check . --step decisions,overview
```

Before a release, run the whole gate:

```console
$ selka release check .
$ selka release check . --json
```

The steps run in this order: format, check (every entry and test root, no holes), lint, tests (with docstring
examples), docs (docstrings, examples, references, Markdown examples), decisions (also pending change notes, by
[these rules](change-review.md#write-a-change-note)), overview (summary, references, `.api` files). A blocked step is
reported as skipped.

- The project's `lint` object and waivers apply as in `selka lint` (see [waivers](lint.md#waivers)). `E_RELEASE_*`
  errors are never waivable.
- Every selected test and example must pass or have a reusable passing receipt. A skipped case refuses the release.
- A code span that is entirely `module::name` must resolve in docstrings, pending decisions, `README.md` and
  `docs/**/*.md`; a removed name resolves from the baseline only in `Changes:`. Dotted module names and standard-library
  names resolve.
- Markdown `selka` fences run as standalone doctests and cannot import the project. A fence marked to skip refuses the
  release; `selka doctest` itself needs at least one executable block.

Exit 0 means releasable, 3 refused, 2 a usage or host error. A source error is a failed check step (exit 3) naming the
file, line, column and code, for example `helper.selka:1:16: error[E_SYNTAX]: …`. JSON output is `release-check-v1` with
`diagnostic-v1` findings.

## Cut a release

```console
$ selka release cut . --name 0.1
```

The command checks the full gate, records the public-only baseline, moves pending decisions into `decisions/0.1/` and
`changes/unreleased/*` under `changes/NAME/`, adds the name and decision count to `release/history.txt`, and rewrites
the overview. An existing release name is refused. It needs no Git and no network.

## Configure entries and paths

A multi-entry project can use the version-2 `release` object:

```json
{"version":2,"release":{"entries":["md2html.selka","site.selka"],"exclude":["oracle/","repros/","results/"],"overview":"OVERVIEW.md","decisions":"decisions","baseline":"release/baseline.txt"}}
```

Entries default to the named entry file or `main.selka`. The module set is the entry and test-root import closures, minus
test modules and the standard library; `build/` and hidden directories are always excluded. Paths are relative to the
project root; unknown keys are refused. Examples cannot be switched off project-wide, only waived.

`release.exclude` is a file or directory prefix every release command skips, for fixtures and reproductions.

## Diagnostics

| Code | Repair |
| --- | --- |
| `L_UNDOCUMENTED_MODULE` | Write the module docstring after imports. |
| `L_UNDOCUMENTED_EXPORT` | Explain the public declaration in its docstring. |
| `L_MISSING_EXAMPLE` | Add a runnable example or a reasoned waiver. |
| `L_LONG_EXAMPLE` | Shorten the output to 120 characters and 6 `>>>` lines, or assert a property such as `len(...)`. |
| `L_WAIVER_REASON` | Add `reason="..."` to the waiver. |
| `E_RELEASE_NO_BASELINE` | Run `release init`. |
| `E_RELEASE_DECISION_MISSING` | Run `release draft` and explain the change. |
| `E_RELEASE_DECISION_INVALID` | Complete the fields, remove placeholders. |
| `E_RELEASE_REFERENCE_UNKNOWN` | Correct the qualified name. |
| `E_RELEASE_OVERVIEW_STALE` | Run `overview --write`. |
| `E_RELEASE_STEP_FAILED` | Follow the step's details; an intentional fixture goes in `release.exclude`. |

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/release-docs.md).
