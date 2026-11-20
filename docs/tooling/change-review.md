# Change review

A change review is a plain-English review of one change to a project before it merges:
what changed, why, which decisions explain it and which public declarations it touches.
The author writes the change note and the decisions, and the compiler writes everything
else from the two sides of the change.

## Write a change note

A change that touches a project's source adds one note, at
`changes/unreleased/<slug>.md`. `release cut` moves the notes under the release name,
as it does for decisions, and records how many notes the release carries.
`release.changes` in `selka.json` names the directory; it defaults to `changes`.

`selka review draft` writes the note with its placeholders, so the author only fills
them in. The slug is a portable name: letters, digits, `.`, `_` and `-`, not starting
with `.`. A note that already exists is never overwritten.

```console
$ selka review draft . --name serve-event-loop
review draft: wrote changes/unreleased/serve-event-loop.md; replace the title and Summary placeholders
```

The note it writes holds a title and a summary to replace, and a comment that reminds
the author what the summary is for. A finished note looks like this:

```text
# Serve on the event loop

Summary: `serve` now runs one event loop with a 1,024-slot connection table,
back-pressure and an idle timeout (`--idle-ms`, default 5000). `--blocking` keeps
the previous server. `--port 0` asks the system for a free port and prints it.
```

The rules, in plain words:

- The first line is `# Title`, a title of your own. A placeholder title such as
  `# TODO` is refused.
- A paragraph that starts with `Summary:` says what changed for someone who uses the
  project, and why. It runs until the next blank line. Leave out implementation detail.
- The summary has at least 40 non-whitespace characters and at most 120 words.
- No `TODO`, `TBD`, `FIXME` or `<summary>` may appear in the title or the summary.
  `TODO`, `TBD` and `FIXME` match as whole words, in any letter case.
- Any text after the summary paragraph is the body. The file keeps it, but the review
  shows only the title and the summary.
- HTML comments (`<!-- ... -->`) are ignored. The draft's guidance comment may stay in
  the file, or be deleted.

Which changes need a note: a change that touches a `.selka` file the project reads, or the
root `selka.json`. A change limited to Markdown, `friction/`, `results/`, `oracle/`,
`build/`, hidden paths and the paths in `release.exclude` needs none. A note that
`release cut` only moves does not count as a new note.

### What to write

Say what changed for someone who uses the project, and why, in two to four sentences.
Leave out implementation detail. A reader should be able to decide from the summary
alone whether the change is what they expected. The gate checks the length and the
placeholders. It cannot tell a good summary from a poor one, so a reviewer reads it.

Three good summaries, reworded from the decisions of the Selka pilots as change
summaries:

```text
# A refused request carries its kind

Summary: A refused request now reports what kind of refusal it was, `RefusalKind`,
instead of an HTTP status read back from the message text. A codec message can be
reworded without changing the status a client receives.
```

```text
# Pad shapes are a fixed set

Summary: A pad shape is now one of a fixed set of named cases, `footprint::PadShape`,
not free text. A KiCad shape the converter does not know has to be added on purpose,
instead of silently becoming a plain rectangle.
```

```text
# A markdown leaf decides its own start

Summary: The check for whether a markdown leaf can start on a line now sits beside the
code that starts leaves, so a new leaf kind is taught to one module instead of two. The
spec examples and the site check give the same output as before.
```

Two poor summaries. Both pass the length and placeholder rules, and both would still
leave a reviewer with nothing to decide on:

```text
# Framing cleanup

Summary: Various improvements to the framing and connection code, including some fixes
and cleanup that were needed after the last review round.
```

This names no change a user could see, gives no reason, and "various" and "some" hide
what changed.

```text
# Move helpers

Summary: Moved `may_start_leaf` out of the block driver into `leaf.start`, added a
`Starter` struct, and deleted the three cache fields from the parser state.
```

This lists code moves. It leaves out what someone who uses the project sees, and why
the move was made.

## Review a change

PROJECT is a directory inside a git repository. It is a path, so the command runs from
any directory:

```text
selka review PROJECT [--against REF | --range A..B] [--head REV] [--check] [--test]
                      [--json FILE] [--html FILE]
selka review draft PROJECT --name SLUG
selka review index SITE_DIR
```

| Flag | What it does |
| --- | --- |
| `--against REF` | Compares with `REF`, which defaults to `main`. The base is the merge base of `REF` and the head. |
| `--head REV` | Uses the committed tree of `REV` as the head, not the working tree. |
| `--range A..B` | Compares commit `A` with commit `B`. Cannot be combined with `--against` or `--head`. |
| `--check` | Exits 3 when the merge gate refuses the change. The review is still printed. |
| `--test` | Runs `selka test` on the head and shows its counts. It never changes the verdict. |
| `--json FILE` | Writes the change as one `review-v1` object. |
| `--html FILE` | Writes the review as one self-contained page. |

Without `--head` or `--range`, the head is the working tree. That includes uncommitted and
untracked files under the project, so an author can review a change before committing it.

### What counts as a change

| Mode | Base | Head |
| --- | --- | --- |
| default, or `--against REF` | the merge base of `REF` and `HEAD` | the working tree |
| `--against REF --head REV` | the merge base of `REF` and `REV` | the committed tree of `REV` |
| `--range A..B` | `A` | `B` |

- The review compares trees, not commits.
- A project that is absent on one side is an empty project on that side. A project is
  present at a revision only when its `selka.json` exists there.
- A declaration is public when the project's public interface lists it. Making a
  declaration public is an addition. Making one private is a removal.
- Source is each `.selka` file the project reads, and the root `selka.json`. Hidden paths,
  `build/`, the paths in `release.exclude`, and the top-level `friction/`, `results/`
  and `oracle/` directories are not read.
- A decision is a Markdown file under `decisions/`, in `unreleased/` or in a release
  directory. A note is a Markdown file under the changes directory. Each one counts only
  when its bytes do not already appear among the base's files of its kind.

### A passing review and a refused one

A change that adds a public function and no note or decision is refused. The gate
names what is missing and the command that starts each repair:

```console
$ selka review sample --check
review: sample 37c6a46..working tree: REFUSED
1 public changes (1 added, 0 changed, 0 removed), 0 explained by a decision; 0 decisions and 0 change notes in the change
! 2 refusals block the change; they are listed below
  main::double: added, lines 0 → 6, decision points 0 → 0
error[E_REVIEW_SUMMARY_MISSING]: the change touches the project's source and adds no change note; run `selka review draft sample --name SLUG`
error[E_REVIEW_DECISION_MISSING]: public declaration main::double is added and no decision in this change names it; run `selka release draft sample --name SLUG`
review: refused; 2 refusals; 1 public changes, 0 change notes, 0 decisions
```

The command exits 3. After the author adds a note and a decision that names
`main::double`, the same review passes:

```console
$ selka review sample --check
review: sample 37c6a46..working tree: OK
1 public changes (1 added, 0 changed, 0 removed), 1 explained by a decision; 1 decisions and 1 change notes in the change
  main::double: added, lines 0 → 6, decision points 0 → 0
  main::double: New function `double(x: int) -> int`. Twice the value.
review: passes; 1 public changes, 1 change notes, 1 decisions
```

The command exits 0. A passing review prints at most 30 lines. A refused one prints up
to 60 refusal lines, then `… N more`.

### Reading the page

The page, from `--html`, and the terminal summary follow the same order. A reviewer
decides in this order.

1. **Header.** The verdict, passes or refused, the range, and the title. The title is
   the first change note's title, else the first decision's title, else the range. A
   lead sentence counts the public declarations and says how many a decision explains.
   A strip of facts follows: public changes, decisions, tests at the head, test changes
   and functions edited.
2. **Needs your judgment.** The entries that need a decision, in this order: the gate's
   refusals; a side whose declarations did not load; new authority, when a public
   function gains a capability; existing tests that expect something different; removed
   tests; docstring examples whose output changed; possible patching, which is a
   heuristic; and generated files that changed. Each entry names its items. When the
   list is empty, the page says so.
3. **Why, in the author's words.** Each change note, with its title and summary, then
   each decision, with what it explains, why and what it rejected. A change with neither
   shows a warning.
4. **Public functions and types.** Grouped by module. Each declaration shows its kind,
   whether it was added, changed or removed, and the sentences that describe the change.
   A chip names the decision that explains it, or says "no decision". The old and new
   signatures are folded below.
5. **What behaves differently.** Docstring examples whose output changed, shown before
   and after. Existing tests whose expectations changed, as diffs. Removed tests. New
   tests, each name read as a sentence.
6. **Inside the code.** Each function whose body changed outside the tests, private
   ones included, with its lines and decision points before and after. The possible
   patching signals appear under each function. The edit is folded, capped at 80 lines
   per function and 600 per review. Helpers in test files are listed on one line.
7. **Also in this change.** Only when present: issue ids that comment lines add or
   remove, generated files with their line counts, and the test counts when `--test` ran.

The possible-patching signals are heuristics, and none of them refuses a change. There
are three kinds. A special case: a function compares one subject against two or more
literals that the base did not. A copy: a new block of at least four code lines is at
least 80% alike, with names and literals masked, to another block in the same function.
A flag: a new `bool` parameter that the body branches on.

## The merge gate

`selka review PROJECT --check` refuses a change, with exit 3, when a rule below fails.
Each rule reads only the change's own decisions and notes, and the public declarations
it changes.

1. **Every public change is explained.** Each public declaration the change adds,
   changes or removes is named in the `Changes:` line of a valid decision that the change
   adds or edits. A decision counts under any directory of `decisions/`, whether
   `unreleased/` or a release directory. A decision that was already pending on the base
   does not count, and neither does a file that `release cut` only moves.
2. **A new project is explained.** A project that is absent at the base needs only one
   valid decision that the change adds. Its initial design does not have to name every
   declaration.
3. **A source change carries a note.** A change that touches the project's source adds
   or edits at least one change note.
4. **Notes and decisions are valid.** Each note and decision the change adds or edits
   passes its rules. A note needs a title and a summary; a decision follows the pending
   rules in [release-docs.md](release-docs.md#record-each-public-interface-change).
5. **Both sides load.** The declarations of each side must load. A side that does not
   load is refused, and the review cannot compare the public interface.

Nothing else refuses a change. Possible patching, changed or removed tests, docstring
examples, new authority, generated files and citations never refuse. Tests belong to
`selka test` and `selka release check`. A failing `--test` run never refuses either.
No refusal can be waived.

| Code | When | Repair |
| --- | --- | --- |
| `E_REVIEW_DECISION_MISSING` | a public change is named by no valid decision that the change adds or edits | `selka release draft PROJECT --name SLUG`, then replace the title and the `Why:` placeholders |
| `E_REVIEW_SUMMARY_MISSING` | the change touches the project's source and adds or edits no change note | `selka review draft PROJECT --name SLUG`, then replace the title and the summary |
| `E_REVIEW_NOTE_INVALID` | a note has no title, no `Summary:` paragraph, a placeholder, a summary of fewer than 40 non-whitespace characters, or more than 120 words; the message gives the file and line | fix the rule the message names |
| `E_RELEASE_DECISION_INVALID` | a decision the change adds or edits fails the pending rules; the message gives the file and line | fix the field the message names |
| `E_REVIEW_BASE_UNREADABLE`, `E_REVIEW_HEAD_UNREADABLE` | a side's declarations do not load; the message gives the file and line when it has them | repair the source at that revision |

Exit statuses:

- `review PROJECT` exits 0 when it writes the review, whatever the verdict.
- `review PROJECT --check` exits 3 when the gate refuses the change, and 0 otherwise.
- A usage error, a revision that cannot be resolved, or a project that is not in a git
  repository exits 2.
- `review draft` exits 0 when it writes the note. It exits 3 when the note already exists
  or the project's declarations do not load.

## The review-v1 format

`--json FILE` writes one `review-v1` object and a newline. The keys below are the top-level
fields, in the order the writer emits them. Some values are left out when they have no
content: `old_signature`, `gained_authority` and `decision` on an interface item; `name`,
`path` and `line` on a refusal; and `tests_run` unless `--test` ran.

| Field | What it holds |
| --- | --- |
| `version` | `review-v1`. |
| `project` | The PROJECT argument as typed. |
| `range` | `base` and `head`, the compared commits as full names. `head` is `working tree` when `working_tree` is true. |
| `verdict` | `ok`, true when there are no refusals, and `refusals`. Each refusal has a `code` and a `message`, and a `name`, `path` or `line` when it has one. |
| `notes` | The change notes the change adds or edits, each with `path`, `title`, `summary` and `valid`. |
| `decisions` | The decisions the change adds or edits, each with `path`, `title`, `changes`, `valid`, `why` and `rejected`, which is null when the decision has none. |
| `interface` | One item per public declaration the change adds, changes or removes: `name`, `module`, `kind` (for example `function`), `change` (`added`, `changed` or `removed`), `sentences`, `signature`, `old_signature`, `gained_authority`, and `decision`, the title of the decision that explains it. |
| `body_changed` | The names whose body changed while their interface did not. |
| `source_changed` | `true` when any source file differs. |
| `behaviour` | `examples_changed`, each with `name`, `source`, `old` and `new`; `tests_added` and `tests_removed`, each with `module` and `name`; and `tests_changed`, each with `module`, `name` and `diff`. |
| `inside` | One entry for each function the change adds, changes or removes, private ones included: `name`, `public`, `state`, `file`, `line`, `lines` and `decision_points` as `[before, after]`, `signals` with each `kind` and `text`, and `diff`. Test functions are left out. Helpers in `*_test.selka` files are included. |
| `generated` | Each generated file that changed, with `path`, `first_line`, `lines_before` and `lines_after`. |
| `citations` | `added` and `removed`, the issue ids that comment lines add or remove, each with `id` and `path`. |
| `tests_run` | Only with `--test`: `found`, `passed`, `failed`, `skipped`, `cached` and `output_tail`. `found` is false when the run printed no summary line, so the counts are not a verdict. |
| `attention` | The "Needs your judgment" entries, in page order, each with `level` (`warn` or `info`), `text` and `items`. |

Two choices shape the format:

- A side that does not load has no field of its own. Its refusal is in `verdict`, and the
  attention list has a warning for it. `tests_run.found` tells "no summary line" apart
  from "no tests".
- `decisions` carry `why` and `rejected`, which the page shows. The format has no
  `new_modules` field, so the page does not mark new modules.

## Pages

Every page is one self-contained HTML file. It loads nothing from the network: no fonts,
no external scripts and no external stylesheets. It reads the same from `file://` and
from a web server.

### The review page

```console
$ selka review sample --range main..double-helper --check --test --json review.json --html review.html
```

`--html` writes the page from the same object that `--json` writes. It is written even when
the gate refuses the change, and `--check` still sets the exit status. The page has light
and dark themes and works at phone width.

### The project page

```console
$ selka overview sample --html sample.html --data sample.json --back ../index.html
```

`overview PROJECT --html FILE` is a third mode of `overview`. It cannot be combined with
`--write`, `--check` or `--json`. `--data FILE` writes the overview document the page is
built from, and it is only valid with `--html`. `--back HREF` adds a link to the site's
index, and is also only valid with `--html`.

The page has a summary: the project docstring, the counts, the authority table and the
releases, each with its decisions and change-note titles. It also has the pending changes,
one page per module, a decisions page and a search over declarations. The page does not
have a guide, and it does not show git history.

### The site index

```console
$ selka review index site
```

`review index SITE_DIR` writes `SITE_DIR/index.html` and reads only these inputs. Each
directory is read in name order, so two runs over the same site write the same bytes.

- `projects/<name>/overview.json`: a project appears when this file exists. Its title and
  the first sentence of its summary come from the file. The index links to
  `projects/<name>/index.html`.
- `changes/<branch>/<project>.review.json`: one row for each open change. The index links
  to `changes/<branch>/<project>.html`, so write that page beside the JSON with
  `review --html`.
- `merged/<sha>/<project>.review.json`: one row for each landed change, up to 20 for each
  project. The rows follow the `<sha>` directory names from the greatest down, so the
  order follows the names, not the time the change landed. The index links to
  `merged/<sha>/<project>.html`.
- `bypass.log`, optional: tab-separated lines of UTC time, old revision, new revision and
  a reason. A landing is marked with the reason of the last line whose new revision
  begins with the landing's `<sha>`.
- `gate-mode`, optional: one word. `report-only` shows a banner that a refused landing still
  lands. `enforcing` shows a line saying a refused landing does not land.

## Generated files and citations

### Generated files

A file is generated when its first line is a `#` comment whose text starts with
`generated by`, in any letter case. `# generated by gen_ports.py` and
`# GENERATED by gen_ports.py` both qualify. `# Generated helpers` does not. Lint uses the
same rule and skips such a file. The review lists a changed generated file with its line
counts, and it does not diff the file. Its public declarations still count for the merge
gate.

### Issue ids in comments

An issue id is an uppercase letter, then more uppercase letters or digits, a hyphen, and one
or more digits. The pattern is `[A-Z][A-Z0-9]*-[0-9]+`, as in `FR-210`. The review lists the
ids that comment lines add and remove, with the file that holds each one. The pattern is
fixed, and no project can change it.
