# Checked project documentation

The compiler writes a project's public interface into `OVERVIEW.md`. Docstrings
explain the design and show calls that run as tests. A decision file records why
each public-interface change was made. `selka release check` checks all three
alongside formatting, source checking, lint and tests.

A project's ordinary `check`, `build` and `run` commands retain their edit-loop
behavior. `selka test` also runs docstring examples. `release check` does not
request an optimized build: `build --release` is the separate optimization flag.

## Write the current design in docstrings

Put the module docstring after its imports and before its first declaration.
With no imports, it is the first statement. Put a function or type's docstring
first in its body. Explain the reason for choices a reader could not infer from
the signature, and include a runnable call for every public function.

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

An example starts with `>>> `; `... ` continues its source. The following lines
are its expected output, ending at a blank line, another example or the end of
the docstring. `<BLANKLINE>` represents an empty output line. Output must match
exactly. A string or bytes value uses `repr`; other values use their printed
form. Statements and unit expressions have no displayed value. Output written
to `out` precedes a displayed value.

Examples in one docstring share a generated function, so a binding from one
example is available to the next. Private module helpers are in scope. `fs`,
`net`, `clock`, `entropy`, `env` and `out` are bound to the same deterministic
stand-ins as [test capability parameters](guest-tests.md#capability-parameters).
A failed example is reported at its docstring line and does not prevent other
cases from running. The case name is `module::function.example`:

```console
$ selka test . --filter .example
$ selka test . --filter line_total.example --force
```

Module and public type docstrings need no example. `main`, test functions,
`*_test.selka` modules and public constants are exempt from example requirements.
Constants cannot carry docstrings. When a public function needs a waiver, put a
reason on the preceding line:

```text
# lint: allow missing-example reason="accepts a live socket; covered by server_test::test_serve"
```

The overview displays the waiver's reason. `undocumented-module` and
`missing-example` are off in plain lint's `agent` profile and report in `strict`
and `safety`; the release docs step makes them blocking with
`undocumented-export` in every profile.

## Adopt an existing project

`PROJECT` is a directory holding `selka.json`, or an entry `.selka` file whose
directory is the project root. A single-entry project normally uses `main.selka`.
Start by recording its current public interface:

```console
$ selka release init .
$ selka release init . --adopt-comments
```

Choose one form. Initialization refuses to overwrite an existing baseline.
It creates `release/baseline.txt`, `release/history.txt`, `decisions/unreleased/`
and the generated overview. It does not make an undocumented project releasable.

`--adopt-comments` moves the comment block above the imports to a module
docstring after the imports. It moves a contiguous comment block immediately
above a public declaration to that declaration's docstring — directly adjacent,
with no blank line between the comment and the declaration. A block separated by
a blank line stays an ordinary comment. It never adopts a banner or section
divider (`# =====`, `# -------`), so a decorative header keeps its place. It uses
each block once and keeps `# lint:` directives and comments inside bodies.
Existing docstrings and comments on constants or bodyless extern declarations
remain in place. Every adoption is printed as
`adopt-comments: PATH:LINE: TARGET`, once per block.

```console
$ selka release init . --adopt-comments --dry-run
adopt-comments: main.selka:4: main::answer
```

`--dry-run` lists the same lines and writes nothing: no source, baseline,
history or overview file changes. Review the result and supply the missing
examples and design explanations. Standard-library comments keep their existing
convention.

## Generate and check the overview

`selka overview PROJECT --write` writes two shapes from one generator:

- `OVERVIEW.md`, a summary to read top to bottom: the project summary, the
  contents, an at-a-glance table, a flat module table, the authority table, the
  pending changes with each decision's title and `Why:`, each module's docstring
  with a table of its public declarations, and the releases with each decision's
  title and first sentence;
- `reference/<module>.md`, one file per module, to look things up: signatures,
  full docstrings and examples, contracts, field and case tables, direct test
  callers, holes, waivers and per-declaration decisions.

The summary's flat module table names each module's purpose (its docstring's
first sentence), imports, public declaration count and private function count.
Each public-declaration row carries the linked name, the first sentence of its
docstring, and compact markers: `mut` when the function writes a parameter, each
capability it holds, and `fails E`. It is built from declarations and syntax, so
it can be generated before every body checks. Private declarations are counted in
the module table; their implementations are never shown.

```console
$ selka overview . --write
$ selka overview . --check
$ selka overview . --check --json
```

`--write` regenerates the summary and every reference, and removes a reference
file whose module is gone. `--check` compares both to exact bytes, exits 1 when
either differs, and prints diffs capped at 60 lines with a repair command. JSON
output uses `overview-v1`: `markdown` is the summary and `references` lists every
generated file.

Empty facts are never printed. A fact appears only when it has content, so
`Status: implemented` is gone, `Contracts: none` and `Tested directly by: none`
do not exist, a hole reads `hole`, and an absent section is omitted rather than
announced. Signatures, full docstrings, examples, field tables, tests and
per-declaration decisions live in the reference, which keeps the summary close to
a tenth of the project's source lines. A body-only change to a non-test function
changes neither output. A direct test call, docstring, example, hole or decision
change changes one of them; a reference-only edit still fails `--check`.

Always review the generated diff. Resolve a merge conflict in either shape by
taking either version and running `selka overview . --write` on the merged
sources; one file per module keeps parallel lanes out of each other's files.

`selka overview PROJECT --html FILE` writes the same project as one self-contained
page, with its module pages and search. See [the project page](change-review.md#the-project-page).

## Record each public-interface change

Added declarations, changed interfaces and removals since the current baseline
need a pending decision. Making a declaration public is an addition; making one
private is a removal. Body-only edits need no decision. A decision may also
explain a behavior change even when the interface is unchanged.

```console
$ selka release draft . --name per-line-rounding --date 2026-10-19
```

The draft names every uncovered change and contains placeholders. Replace them
with a title and a reason before checking. A decision has this form:

```text
# Round each line before summing

Date: 2026-10-19
Changes: totals::line_total
Why: The invoice audit compares individual line amounts, so rounding only the
invoice total can disagree with the amounts a customer sees on each line.
Rejected: rounding the complete invoice, which loses the per-line audit trail.
```

The first line, `Changes:` and `Why:` are required. `Changes:` is a comma-separated
list of current public names or names from the baseline, so a removed declaration
can still be explained. `Why:` needs at least 30 non-whitespace characters and no
`TODO`, `TBD`, `FIXME` or `<why>` placeholder. `Date:` is optional and comes only
from `--date`; the compiler does not read the clock. Additional prose is allowed.
The draft command never overwrites a file.

Use one file per decision under `decisions/unreleased/`. Only pending decisions
are validated; archived decisions remain historical text even after their named
declarations disappear.

## Check every change and release

Keep the reasoning and generated overview current while working:

```console
$ selka overview . --write
$ selka release check . --step decisions,overview
```

The subset compares the interface baseline, checks pending decisions and checks
generated documentation without running tests. Run the complete gate before a
release:

```console
$ selka release check .
$ selka release check . --json
```

The steps run in this order: format, check, lint, tests, docs, decisions, overview.
They cover source formatting; every entry and test root with no holes; the
project's lint profile; tests and docstring examples; required docstrings,
examples, references and standalone Markdown examples; decision coverage; and the
current summary, every generated reference and existing `.api` files. A blocked
step is reported as skipped with a reason. The lint and docs steps report each
doc finding once. The decisions step also checks every pending change note under
`changes/unreleased/`, with the rules in [change-review.md](change-review.md#write-a-change-note),
so `release cut` never files an invalid note.

A project's lint configuration applies inside `release check` exactly as it does
in `selka lint`: the `lint` object supplies the profile, the per-rule modes,
`min_chars` and the reasoned exemptions, and the same waivers apply. A comment
on the line above a declaration, an `@allow` attribute, or a file-level
`# lint: allow-file RULE reason="..."` covers the lint step's finding and the
docs step's finding for that rule. Release errors (`E_RELEASE_*`) are never
waivable. See [waivers](lint.md#waivers).

Every selected test and example must pass or have a reusable passing receipt.
The tests step runs each selected root once through `selka test`, the same path
an ordinary run takes: one build per root, forked trials, and the runner's
receipts, so an unchanged rerun reuses every case's receipt instead of compiling
each case separately. A skipped or unsupported case refuses the release; it is
never counted as a pass. Ordinary `selka test` keeps its existing skip behavior.

Exit 0 means releasable, 3 means refused, and 2 means a usage or host error. A
source error is a failed check step and exits 3; `release init` and `release check`
name the file, line and column and the compiler's own diagnostic code (for example
`helper.selka:1:16: error[E_SYNTAX]: …`) instead of reporting an unnamed
`declaration loading failed: SourceError`. JSON output is
`release-check-v1` with `diagnostic-v1` findings. Certain repairs name the command
to run: `fmt`, `release init`, `release draft` or `overview --write`.

An inline code span consisting entirely of `module::name` must resolve in
project docstrings, pending decisions, `README.md` and `docs/**/*.md`. Dotted
module names and standard-library declarations are supported. Fenced blocks and
other code-span shapes are excluded. A removed name resolves from the baseline
only in `Changes:`. Markdown `selka` fences run as standalone doctests; they
cannot import the surrounding project, and having no fences is allowed.
An executable Markdown fence marked to skip refuses release checking. Ordinary
`selka doctest` still requires at least one executable block.

## Cut a release

Once the full gate passes, record the release:

```console
$ selka release cut . --name 0.1
```

The command checks the full gate again, records the current public-only
`api-diff-baseline-v2` baseline, moves pending decisions into `decisions/0.1/`,
adds the name and decision count to `release/history.txt`, and rewrites the
overview from that new state. It also files `changes/unreleased/*` under
`changes/NAME/`. An existing release name is refused. No Git operation or network
connection is needed.

## Configure entries and paths

A multi-entry project can use the optional version-2 `release` object:

```json
{"version":2,"release":{"entries":["md2html.selka","site.selka"],"exclude":["oracle/","repros/","results/"],"overview":"OVERVIEW.md","decisions":"decisions","baseline":"release/baseline.txt"}}
```

Entries default to the named entry file or `main.selka`. The module set combines
entry and test-root import closures, including files with docstring examples,
then excludes test modules and the standard library. `build/` and hidden
directories are always excluded. Every command uses the same set. Paths are
relative to the project root; unknown keys are refused. There is no project-wide
switch to make examples optional: use a reasoned per-function waiver, or a
file-level waiver when one rule repeats through a file.

`release.exclude` names intentional fixtures, oracle inputs and reproduction
sources that must stay in the tree without joining the project: a project-relative
file or a directory prefix, applied by every release command. Exclude a source
the project deliberately does not check; never exclude one that should be
formatted and checked. The format step names this option when an intentional
fixture fails canonical formatting.

## Diagnostics

| Code | Repair |
| --- | --- |
| `L_UNDOCUMENTED_MODULE` | Write the module docstring after imports. |
| `L_UNDOCUMENTED_EXPORT` | Explain the public declaration in its docstring. |
| `L_MISSING_EXAMPLE` | Add a runnable example or a reasoned waiver. |
| `L_LONG_EXAMPLE` | Show the call, not a dump: shorten the output to 120 characters and 6 `>>>` lines, or assert a property such as `len(...)`. |
| `L_WAIVER_REASON` | Add `reason="..."` to the waiver. |
| `E_RELEASE_NO_BASELINE` | Run `release init`. |
| `E_RELEASE_DECISION_MISSING` | Run `release draft` and explain the change. |
| `E_RELEASE_DECISION_INVALID` | Complete the required fields and remove placeholders. |
| `E_RELEASE_REFERENCE_UNKNOWN` | Correct the qualified name. |
| `E_RELEASE_OVERVIEW_STALE` | Run `overview --write` and review its diff. |
| `E_RELEASE_STEP_FAILED` | Follow the named step's details: fix formatting, or a failed/skipped test or Markdown example; an intentional fixture the format step names goes in `release.exclude`. A project whose declarations do not load reports its own file, position and compiler code instead. |

Release errors are not waivable. The compiler checks that a reason exists and
names the change; a human reviewer still judges whether that reason explains it.
