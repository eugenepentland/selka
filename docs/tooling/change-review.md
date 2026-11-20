# Change review

A change review is a plain-English review of one change to a project before it merges: what changed, why, and which
public declarations it touches. You write a change note and decisions; the compiler writes the rest.

## Write a change note

A change that touches a project's source adds one note, at `changes/unreleased/<slug>.md`. `release cut` files them under the release name. `release.changes` in `selka.json` names the directory (default `changes`).

`selka review draft` writes the note with placeholders. The slug uses letters, digits, `.`, `_` and `-`, and does not
start with `.`. An existing note is never overwritten.

```console
$ selka review draft . --name serve-event-loop
review draft: wrote changes/unreleased/serve-event-loop.md; replace the title and Summary placeholders
```

A finished note:

```text
# Serve on the event loop

Summary: `serve` now runs one event loop with a 1,024-slot connection table,
back-pressure and an idle timeout (`--idle-ms`, default 5000). `--blocking` keeps
the previous server. `--port 0` asks the system for a free port and prints it.
```

- The first line is `# Title`. A placeholder title such as `# TODO` is refused.
- A paragraph that starts with `Summary:` says what changed for someone who uses the project, and why. It runs to the
  next blank line.
- The summary has at least 40 non-whitespace characters and at most 120 words.
- `TODO`, `TBD` and `FIXME` (whole words, any letter case) and `<summary>` may not appear in the title or the summary.
- Text after the summary is the body: the review shows only the title and the summary. HTML comments are ignored.

A change needs a note when it touches a `.selka` file the project reads, or the root `selka.json`. A change limited to
Markdown or to paths the review does not read (below) needs none.

### What to write

Two to four sentences: what changed for someone who uses the project, and why, without implementation detail (not "moved
`may_start_leaf` into `leaf.start`"). The gate checks the length and the placeholders. A reviewer judges the rest.

```text
# A refused request carries its kind

Summary: A refused request now reports what kind of refusal it was, `RefusalKind`,
instead of an HTTP status read back from the message text. A codec message can be
reworded without changing the status a client receives.
```

## Review a change

PROJECT is a directory inside a git repository. The command runs from any directory:

```text
selka review PROJECT [--against REF | --range A..B] [--head REV] [--check] [--test]
                      [--json FILE] [--html FILE]
selka review draft PROJECT --name SLUG
selka review index SITE_DIR
```

| Flag | What it does |
| --- | --- |
| `--against REF` | Compares with `REF`, default `main`. The base is the merge base of `REF` and the head. |
| `--head REV` | Uses the committed tree of `REV` as the head, not the working tree. |
| `--range A..B` | Compares commit `A` with commit `B`. Not with `--against` or `--head`. |
| `--check` | Exits 3 when the merge gate refuses the change. The review is still printed. |
| `--test` | Runs `selka test` on the head and shows its counts. It never changes the verdict. |
| `--json FILE` | Writes the change as one `review-v1` object. |
| `--html FILE` | Writes the review as one self-contained page. |

Without `--head` or `--range`, the head is the working tree, uncommitted and untracked files included, so you can review
before you commit.

### What counts as a change

- The review compares trees, not commits.
- A project is present at a revision only when its `selka.json` exists there.
- A declaration is public when the project's public interface lists it. Making one public is an addition; making one
  private is a removal.
- Source is each `.selka` file the project reads, and the root `selka.json`. Hidden paths, `build/`, the paths in
  `release.exclude` and the top-level `friction/`, `results/` and `oracle/` are not read.
- A decision (under `decisions/`) or a note (under the changes directory) counts only when its bytes are not already
  among the base's files of its kind.

### A passing review and a refused one

A change that adds a public function and no note or decision is refused, with the command that starts each repair:

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

Exit 3. After you add a note and a decision that names `main::double`, the review passes and exits 0:

```console
$ selka review sample --check
review: sample 37c6a46..working tree: OK
1 public changes (1 added, 0 changed, 0 removed), 1 explained by a decision; 1 decisions and 1 change notes in the change
  main::double: added, lines 0 → 6, decision points 0 → 0
  main::double: New function `double(x: int) -> int`. Twice the value.
review: passes; 1 public changes, 1 change notes, 1 decisions
```

A passing review prints at most 30 lines; a refused one up to 60 refusal lines, then `… N more`.

### Reading the page

The `--html` page and the terminal summary share one order: the verdict and range; "Needs your judgment" (gate
refusals, new authority, changed tests and examples, possible patching); each note and decision in the author's words;
the public changes by module; what behaves differently; the changed function bodies; and issue ids and generated files.
Possible-patching signals (a special case, a copy, a new `bool` flag) never refuse.

## The merge gate

`selka review PROJECT --check` exits 3 when a rule below fails. Each rule reads only the change's own decisions, notes and public declarations.

1. **Every public change is explained.** Each public declaration the change adds, changes or removes is named in the
   `Changes:` line of a valid decision that the change adds or edits. A decision already pending on the base does not
   count, and neither does a file that `release cut` only moves.
2. **A new project is explained.** A project absent at the base needs one valid decision that the change adds; it need
   not name every declaration.
3. **A source change carries a note.** The change adds or edits at least one note.
4. **Notes and decisions are valid.** Each one the change adds or edits passes its rules. A decision follows the pending
   rules in [release-docs.md](release-docs.md#record-each-public-interface-change).
5. **Both sides load.** A side whose declarations do not load is refused.

Nothing else refuses a change: possible patching, changed or removed tests, docstring examples, new authority,
generated files, citations and a failing `--test` run never do. No refusal can be waived.

| Code | When | Repair |
| --- | --- | --- |
| `E_REVIEW_DECISION_MISSING` | a public change is named by no valid decision that the change adds or edits | `selka release draft PROJECT --name SLUG`, then replace the title and the `Why:` placeholders |
| `E_REVIEW_SUMMARY_MISSING` | the change touches the source and adds or edits no note | `selka review draft PROJECT --name SLUG`, then replace the title and the summary |
| `E_REVIEW_NOTE_INVALID` | a note breaks a rule above | fix the rule the message names |
| `E_RELEASE_DECISION_INVALID` | a decision the change adds or edits fails the pending rules | fix the field the message names |
| `E_REVIEW_BASE_UNREADABLE`, `E_REVIEW_HEAD_UNREADABLE` | a side's declarations do not load | repair the source at that revision |

Exit statuses: `review PROJECT` exits 0 whatever the verdict, and `--check` exits 3 on a refusal. A usage error, an
unresolvable revision or a project outside a git repository exits 2. `review draft` exits 3 when the note exists or the
declarations do not load.

## The review-v1 format

`--json FILE` writes one `review-v1` object. Empty `old_signature`, `gained_authority`, `decision`, `name`, `path` and
`line` and, without `--test`, `tests_run` are left out.

| Field | What it holds |
| --- | --- |
| `version`, `project` | `review-v1`; the PROJECT argument as typed. |
| `range` | `base` and `head` as full names; `head` is `working tree` when `working_tree` is true. |
| `verdict` | `ok` and `refusals`, each with `code`, `message` and, when present, `name`, `path`, `line`. |
| `notes` | `path`, `title`, `summary`, `valid` for each note the change adds or edits. |
| `decisions` | `path`, `title`, `changes`, `valid`, `why`, `rejected` (null when none). |
| `interface` | One item per public declaration added, changed or removed: `name`, `module`, `kind`, `change`, `sentences`, `signature`, `old_signature`, `gained_authority`, `decision`. |
| `body_changed`, `source_changed` | Names whose body changed while their interface did not; whether any source file differs. |
| `behaviour` | `examples_changed`, `tests_added`, `tests_removed`, `tests_changed`. |
| `inside` | One entry per function added, changed or removed, private ones included: `name`, `public`, `state`, `file`, `line`, `lines` and `decision_points` as `[before, after]`, `signals`, `diff`. Test functions are left out. |
| `generated`, `citations` | Changed generated files with line counts; issue ids added and removed. |
| `tests_run` | With `--test`: `found`, `passed`, `failed`, `skipped`, `cached`, `output_tail`. `found` is false when the run printed no summary line, so the counts are not a verdict. |
| `attention` | The "Needs your judgment" entries in page order: `level` (`warn` or `info`), `text`, `items`. |

## Pages

Every page is one self-contained HTML file: nothing loads from the network, and it reads the same from `file://`.

### The review page

```console
$ selka review sample --range main..double-helper --check --test --json review.json --html review.html
```

`--html` writes the page even when the gate refuses the change.

### The project page

```console
$ selka overview sample --html sample.html --data sample.json --back ../index.html
```

`overview PROJECT --html FILE` cannot be combined with `--write`, `--check` or `--json`. `--data FILE` writes the
document the page is built from, and `--back HREF` links to the site's index. Both need `--html`.

### The site index

```console
$ selka review index site
```

`review index SITE_DIR` writes `SITE_DIR/index.html` from these inputs, read in name order:

- `projects/<name>/overview.json`: a project appears when this file exists.
- `changes/<branch>/<project>.review.json`: one row for each open change, linked to `changes/<branch>/<project>.html`
  (write it with `review --html`).
- `merged/<sha>/<project>.review.json`: one row for each landed change, up to 20 for each project, ordered by the
  `<sha>` directory names from the greatest down.
- `bypass.log`, optional: tab-separated UTC time, old revision, new revision and a reason. A landing shows the reason of
  the last line whose new revision starts with its `<sha>`.
- `gate-mode`, optional: `report-only` shows a banner that a refused landing still lands; `enforcing` shows a line that
  it does not.

## Generated files and citations

### Generated files

A file is generated when its first line is a `#` comment starting with `generated by`, in any letter case. Lint skips
such a file by the same rule. The review lists it with its line counts, does not diff it, and still counts its public
declarations.

### Issue ids in comments

An issue id matches `[A-Z][A-Z0-9]*-[0-9]+`, as in `FR-210`. The review lists the ids that comment lines add and remove, with their files.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/change-review.md).
