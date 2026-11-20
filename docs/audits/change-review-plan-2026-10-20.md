# Change review: a plain-English review before every merge, and a review site that is always on (plan, 2026-10-20)

Status: written on 20 October 2026 at the user's request, after two prototypes. The
user took decisions D1 to D4 (§8) the same day. The recommendations Q1 to Q10 count
as accepted when the user launches the run. An adversarial review of the first draft
found 15 problems; each fix below cites what it found. Codex implements the plan. The
compiler lanes can start now, beside wave 2 and the docs follow-up's F1 and F2 (§9).

## 1. Summary

Before a change lands on a Selka project's `main`, the user wants to read, in plain
English:
- what changed;
- why;
- which decisions it adds or edits;
- which public functions and types it changes.

This is a code review without reading the code. Two prototypes, made with the user on
20 October, settled what the review page shows:

- The **change review**, at <https://claude.ai/artifact/WZqqVFiR8uDi9USy1gizs2>. It
  was built for two real http-server changes in selka-projects:
  - `c338c34..70a50bd`, release 0.2: 3 public changes, all explained by one decision.
  - `66992fd..e5f137e`, the event-loop commit, 2,273 lines: 18 public changes and no
    decision. It also has 4 new functions that reach the network, the filesystem or
    the clock, 3 tests whose expectations changed, a copied block in `parse_serve`,
    and a 521-line regenerated `ports.my`.
- The **project page**, at <https://claude.ai/artifact/J7gDMyBvx8EiWgKJUz9iDk>: one
  project's summary, modules, public declarations, decisions and authority, built from
  the overview data. The user does not want its "Guide" tab (D4).

The prototypes' scripts, templates and outputs are in
`experiments/change-review-20261020/prototype/`. They are the visual and textual
reference, not code to port.

After this run:

1. **`mylang review`** writes the change review for one project: the change against
   `main`, or a range. It produces `review-v1` JSON, one self-contained HTML page, and
   a short terminal summary.
2. **`mylang review --check`** refuses a change (exit 3) in three cases:
   - a public declaration changes and no decision in the same change names it (D1);
   - the change carries no summary note (D2);
   - a note or decision in the change is invalid.
3. **Change notes.** Each change carries a short summary paragraph in its own file,
   `changes/unreleased/<slug>.md`. `mylang review draft` writes the skeleton, and
   `release cut` files the notes under the release.
4. **`mylang overview --html`** writes the project page.
5. **In selka-projects**, a git hook runs the check whenever `main` moves. A local site
   is always on at <http://127.0.0.1:25080/> and shows every project's page and a
   review of every open branch and recent landing (D3). The site runs on Selka's own
   `http-server`, under systemd, and a refresh job regenerates it.

## 2. What a change carries: the author's part

### 2.1 Decisions: unchanged format, a new rule

The decision files stay exactly as `docs/tooling/release-docs.md` describes them
(`# Title`, `Changes:`, `Why:`, optional `Rejected:`). What is new is the
**merge-time rule (D1, Q2):** every public declaration that is added, changed or
removed in the change must be named in the `Changes:` line of a decision file that
the same change adds or edits.

- **Where the decision lives.** A decision added or edited anywhere under
  `decisions/` counts, `unreleased/` or a release directory. The review validates it
  with the pending rules.
  - A file that `release cut` only moves, unchanged, does not count.
  - This matters because `70a50bd` adds `decisions/0.2/refusals-carry-a-kind.md` in
    the commit that cuts 0.2. Today `covering()` would not see it
    (`src/release_decisions.zig`, about line 227), since it reads only pending files.
- **Earlier decisions.** A pending decision from an earlier merge does not count.
  Each merge carries its own "why".
- **Visibility flips** count as in `release check`: made public is an addition, made
  private is a removal.
- **Body-only edits** still need no decision.
- **A new project.** When the project does not exist at the base, the rule is met by
  any valid decision added in the change, the project's initial design. It does not
  have to name every declaration.
- **The release gate is not affected.** `release check` keeps checking coverage
  against the last release baseline. The merge rule is an additional check against
  `main`.

### 2.2 Change notes: one short paragraph per change (D2, Q1)

```text
# Serve on the event loop

Summary: `serve` now runs one event loop with a 1,024-slot connection table,
back-pressure and an idle timeout (`--idle-ms`, default 5000). `--blocking` keeps
the previous server. `--port 0` asks the system for a free port and prints it.
```

- **File.** One file per change: `<changes>/unreleased/<slug>.md`. `<changes>` is a
  new `release.changes` key in `mylang.json` and defaults to `changes`.
  - The `release` object refuses unknown keys, so C1 extends its parser. It does the
    same for `release.citations` (§3.2).
  - One file per change means parallel lanes never edit the same file.
- **Required.**
  - The first line is `# Title`.
  - A `Summary:` paragraph of at least 40 non-whitespace characters and at most 120
    words.
  - No placeholder: `TODO`, `TBD`, `FIXME` or `<summary>`.
  - More prose may follow the summary. The review shows it under the summary.
- **What to write.** Say what changed for someone who uses the project, and why, in
  two to four sentences. Leave implementation details out. The guide section of
  `docs/tooling/change-review.md` gives three good examples and two bad ones, taken
  from the pilots.
- **`mylang review draft PROJECT --name SLUG [--against REF]`.**
  - It writes the note with a placeholder title and `Summary: TODO`.
  - After them it writes an HTML comment (`<!-- review: … -->`) listing the public
    changes that still need a decision and the exact `mylang release draft` command
    that would cover them. The note parser ignores HTML comments. A `#` line would
    read as a heading.
  - It never overwrites a file, and it reads no clock.
- **`release cut`.**
  - It moves `changes/unreleased/*` to `changes/<release>/`, as it does for decisions.
  - `release/history.txt` records the note count beside the decision count.
- **Which changes need a note.** Only a change that touches the project's source:
  - a `.my` file in the release module set or a test root;
  - `mylang.json`.

  A change limited to `friction/`, `results/`, `oracle/`, `NOTES.md`, `build/` or the
  decision and change files themselves needs none. Without this exemption, the
  coordinator's friction-log and release-cut commits would need notes.
  - A new note under `changes/unreleased/` or a release directory counts. A note that
    `release cut` only moves does not.

### 2.3 What counts as a change

| Mode | Base | Head |
| --- | --- | --- |
| `--against REF` (default `main`) | `git merge-base REF HEAD` | the working tree, including uncommitted and untracked files under the project |
| `--against REF --head REV` | `git merge-base REF REV` | the committed tree of `REV` |
| `--range A..B` | `A` | `B` |

- The working-tree mode lets an agent run the review before it commits. The hook and
  the site use committed revisions only.
- The diff is between trees, not commits. A branch that has merged `main` still sees
  its own decisions and notes.
- A project absent on one side is an empty project on that side.

## 3. What the compiler writes

### 3.1 Inputs, and what "loads" means (Q9)

- **Both trees.**
  - A revision is materialized into a private directory under the work cache,
    `.mylang-cache/review/trees/<sha>-<path-hash>/`, keyed by commit and project path.
  - It is extracted with `git archive`. Use Zig's `std.tar` if the pinned toolchain's
    std has it; check `.zigversion` and the std of the installed toolchain. Otherwise
    use the `tar` binary through the same runner. Log the choice.
  - Git is called through `src/ref_diff.zig`'s runner, extended as needed.
  - Nothing is written to the repository, no worktree is created, and no network is
    used.
- **Loading is declaration loading.** Each side is loaded the way `overview` loads a
  project: declarations, signatures, types, docstrings and the module graph.
  - If a side's bodies fail to check, the review drops only the facts that need
    checked bodies: authority, writes, the tests that reach a declaration, and the
    signals. It says so in "Needs your judgment".
  - Only a side whose declarations cannot be loaded is a refusal:
    `E_REVIEW_BASE_UNREADABLE` or `E_REVIEW_HEAD_UNREADABLE`, with the diagnostic.
  - Today's compilers fail even to load the declarations of the old prototype trees
    (`66992fd`, `e5f137e`), and `70a50bd` loads but fails to check. CR3 therefore runs
    on migrated copies (§7).
- **Both sides are loaded by the same compiler:** the one running the command. §5 says
  which compiler the hook and the site run.
- **From each side:**
  - the overview data of the release module set, through today's
    `overview_types.Document` (C2 adapts if F2 changes it);
  - the decision and change-note files;
  - the discovered tests and their bodies;
  - the docstring examples;
  - the source span of every declaration, private ones included;
  - api-diff's interface and body fingerprints, which decide added, changed, removed
    and body-only.

### 3.2 The sections, in reading order

The page and the JSON keep this order. It is the order in which a reviewer decides.

1. **Header.** The title, taken from the first change note, else the first decision,
   else the first commit subject. Then the range, the commit dates and a one-sentence
   lead, generated as in the prototype's `lead()`. For example: "18 public
   declarations change here (16 added, 2 changed, 0 removed), and none of them is
   explained by a decision. 3 existing tests now expect something different, and 21
   tests are new." Then the fact strip, listed in the next item.
2. **The fact strip:** public changes explained, decisions, tests at the head (with
   `--test`), test changes, functions edited.
3. **Needs your judgment.** The list is computed, in this order:
   1. the gate's refusals;
   2. facts a side could not provide because its bodies do not check;
   3. new authority: a public function that gains a capability, and a new public
      function that takes one;
   4. existing tests whose expectations changed, and removed tests;
   5. docstring examples whose output changed;
   6. possible patching, the heuristic signals of §3.4, which never block;
   7. generated files that changed.
4. **Why, in the author's words.** The change notes' summaries first, then each
   decision added or edited (title, explains, why, rejected). If a change has no note
   and no decision, the section shows the commit messages under a warning, as the
   prototype does for `e5f137e`.
5. **Public functions and types.** Grouped by module, with new modules marked. Each
   declaration shows its kind (added, changed or removed) and its sentences from §3.3.
   It is marked with the decision that explains it, or with "no decision". The old and
   new signatures are folded below.
6. **What behaves differently.**
   - Docstring examples whose source is unchanged but whose output changed, shown
     before and after.
   - Existing tests that changed, as diffs.
   - Removed tests.
   - New tests by module, with each test name read as a sentence: `test_serve_port_zero_is_for_the_event_loop`
     becomes "serve port zero is for the event loop".
7. **Inside the code.**
   - Every function whose body changed, private ones included, but not test
     functions and not generated files.
   - For each one: lines and decision points before and after, and the signals of
     §3.4. Decision points are counted on the syntax tree, with the constructs
     `L_DECISION_POINTS` counts, so a side whose bodies fail to check still has them.
   - The edit itself, folded. It is capped at 80 lines per function and 600 per
     review, with "N more lines" when cut.
   - Test helpers are listed on one line.
8. **Also in this change.**
   - Comment citations of issue ids that were added or removed. The default pattern is
     `[A-Z][A-Z0-9]*-[0-9]+`, and `release.citations` overrides it.
   - Generated files, summarized and not diffed. A file is generated when its first
     line is a comment whose first word is "generated" in any letter case.
     - Lint's own rule (`src/lint.zig`, about lines 1001–1004) matches only a lowercase
       `# generated by`, so it misses `ports.my`'s `# GENERATED by gen_ports.py`. C3
       makes the rule case-insensitive and shared, and changes lint with a test.
     - A generated file's public declarations still count for the gate.
   - Test results, when `--test` ran: `mylang test` over the project's roots at the
     head, with receipts reused.

### 3.3 Sentence templates (exact wording, pinned by tests)

Every sentence is built from the two sides' declarations. The prototype's
`describe_new` and `describe_change` are the reference. Code goes in backticks, and
each sentence starts with its verb so it reads after the declaration's name.

| Change | Sentence |
| --- | --- |
| new function | New function `SIGNATURE`. First sentence of its docstring |
| new record / enum | New record `Name` with fields `a: A`, `b: B`. / New enum `Name` with cases `x`, `y`. First docstring sentence |
| new constant | New `const NAME: T = value`. |
| removed | Removed `SIGNATURE`. |
| made public / made private | Now public: (as new) / No longer public: `SIGNATURE`. |
| parameter added | now takes `name: T` (defaults to `d`) |
| parameter removed | no longer takes `name` |
| parameter type | takes `name` as `B` instead of `A` |
| `mut` added / removed | now changes the caller's `name` / no longer changes the caller's `name` |
| return type | returns `B` instead of `A` |
| failure | can now fail with `E` / can no longer fail / fails with `B` instead of `A` |
| capability | now needs `Network` / no longer needs `Clock` |
| contract | gained contract `@requires(...)` / lost contract `...` / contract `...` is now `...` |
| record field | gained field `f: T = d` / lost field `f` / field `f` is `B` instead of `A` / field `f` defaults to `d` instead of `c` |
| enum case | gained case `c` / lost case `c` / case `c` gained `f: T` / case `c` lost `f` / case `c` carries `x: B` instead of `y: A` |
| invariant | gained invariant `...` / lost invariant `...` |
| constant value | `NAME` is now `v` (was `u`) |
| anything else | declaration changed. This is a fallback, and CR1 forbids it on the fixture corpus |

When a changed function's docstring changes as well, its first sentence is shown
after "Docstring now says:".

### 3.4 Possible patching: signals that never block (Q6)

The signals come from the syntax tree of both sides, not from text. Each one is a line
under its function, and each also appears in "Needs your judgment".

- **Special cases:** the head's function compares one subject against two or more
  literals that the base's version did not. The output names the literals, for
  example: "adds branches that compare `args[index]` against `"--blocking"`,
  `"--idle-ms"`, `"--idle-ms="`".
- **Copied block:** a new statement block of four or more lines that is at least 80%
  similar to another block in the same function. The output reads: "the new block at
  line 42 repeats the block at line 62 with only names or literals changed".
  - `duplicates.zig` cannot provide this. Its `canonical` is private, works per
    function over `typed.Program`, and writes lines with no spans.
  - C3 therefore writes a small AST block canonicalizer that keeps spans: names and
    literals are masked, structure is kept.
  - The 4-line and 80% thresholds are starting values. C3 calibrates them on the CR3
    pair and logs the result.
- **Flag parameter:** a new `bool` parameter that the body branches on.

### 3.5 The gate: `--check`

`--check` refuses the change, with exit 3, in these cases:

| Code | When | Repair named in the message |
| --- | --- | --- |
| `E_REVIEW_DECISION_MISSING` | a public change in the range is not named by a decision added or edited in the range (§2.1) | `mylang release draft PROJECT --name SLUG` |
| `E_REVIEW_SUMMARY_MISSING` | the change touches the project's source and adds or edits no change note | `mylang review draft PROJECT --name SLUG` |
| `E_REVIEW_NOTE_INVALID` | a note in the change has a placeholder, no title, or a summary under 40 characters or over 120 words | the file and the rule |
| `E_RELEASE_DECISION_INVALID` | a decision in the change fails the pending validation | as today |
| `E_REVIEW_BASE_UNREADABLE` / `E_REVIEW_HEAD_UNREADABLE` | a side's declarations do not load (§3.1) | §5's pin-bump rule |

- None of these is waivable, which matches the release codes.
- `--check` never refuses on signals, tests or generated files. Tests belong to
  `mylang test` and `release check`.
- Without `--check`, the command always exits 0 when it can write the review. The JSON
  carries the verdict either way.
- A usage or host error (not a git repository, git missing, a bad range) exits 2.
- Every code gets a row in `src/diagnostic_codes.zig`. Codex may rename them and logs
  the rename.

### 3.6 Outputs

- **The terminal.**
  - It prints the verdict line, the counts, and the refusals in full: up to 60 lines,
    then "N more".
  - A passing review prints at most 30 lines.
  - It ends with a `review:` summary line, in the style of `lint` and `release check`.
- **`--json FILE`: `review-v1`.**
  - It holds `range`, `verdict`, `notes`, `decisions`, `interface`, `new_modules`,
    `behaviour`, `inside`, `generated`, `citations`, `tests_run`, `unavailable` and
    `attention`.
  - The prototype's `review-*.json` files show the content. Field names may differ,
    but each field is documented in `docs/tooling/change-review.md`.
- **`--html FILE`: one self-contained page (Q5).**
  - The template is `src/review_page.html`, embedded with `@embedFile`, with the JSON
    inlined. `</` is escaped.
  - The CSS and JS are its own. It makes no network request: system fonts, no CDN.
  - It has light and dark themes and works at phone width.
  - It reads the same from `file://` and from the site.
  - The prototype is the visual reference, with its Google Fonts removed.
- **Determinism.**
  - Output bytes depend only on the two trees, the compiler's identity and the options.
  - The page shows commit dates from git. It never reads the clock.
  - The working-tree side is labeled "working tree".

### 3.7 `mylang review index SITE_DIR`

The command reads its inputs by directory:
- `SITE_DIR/projects/*/overview.json`: the project pages;
- `SITE_DIR/changes/<branch>/*.review.json`: open changes;
- `SITE_DIR/merged/<sha>/*.review.json`: landed changes;
- `SITE_DIR/bypass.log`, a copy that `refresh.sh` makes: the bypasses;
- `SITE_DIR/gate-mode`: one word, `enforcing` or `report-only`.

It writes `SITE_DIR/index.html`:
- the gate mode, as a banner while the gate is report-only;
- the projects, each linking to its page at `main`;
- the open changes, one row per branch and project: a verdict pill, the note's title,
  the counts and a link;
- the landed changes, up to 20 per project, newest first, with bypassed ones marked
  and their reasons.

The index uses the same template family and is equally self-contained.

## 4. The project page: `mylang overview PROJECT --html FILE [--data FILE] [--back HREF]`

- **A third mode of `overview`.** Today the command takes `--write` or `--check`, and
  `--json` is a boolean that switches `--check`'s output. `--html` is a third mode,
  exclusive with both. It writes the page, and `--data FILE` writes the overview-v1
  content beside it. `--back HREF` adds a link back to the site's index.
- **Its parts:**
  - **Summary:**
    - the project docstring;
    - the at-a-glance counts;
    - authority, as a table of capabilities and the functions that take them;
    - releases, with their decisions and their change-note titles.
  - **A module index and module pages.** Each public declaration shows its signature,
    docstring, examples rendered as code, the tests that call it directly, the
    parameters it writes, the capabilities it takes, and any waiver.
  - **A decisions page.**
  - **Search over declarations.**
- **What it does not have:** a Guide (D4), or the prototype's git-history churn table.
  The site's list of landed changes covers history.
- **It builds on F2's data model** once F2 has landed (§9). The note titles in the
  release section are part of C4, not C1, so that this run never edits the overview
  renderer while F2 rewrites it.

## 5. The review site in selka-projects (D3)

| Piece | Where |
| --- | --- |
| Scripts, units, hooks | `tools/review-site/` in selka-projects: `refresh.sh`, `build-server.sh`, `install.sh`, `systemd/`, `hooks/`, `README.md` |
| Installed hooks | `~/.cache/selka-review/hooks/`, copied by `install.sh` |
| Site files | `~/.cache/selka-review/site/` (regenerated, never in git) |
| State, caches, logs | `~/.cache/selka-review/state/`, `bypass.log`, `landings.log`, `friction.jsonl` |
| A tree of `main` | `~/.cache/selka-review/main-tree`, a detached, locked worktree of selka-projects, moved to `main` at each refresh |
| Server binary | `~/.cache/selka-review/bin/http-server`, built from `http-server/` with main's pin, rebuilt when that pin changes |
| Address | <http://127.0.0.1:25080/> (Q4) |

- **Projects.** A project is a top-level directory of selka-projects with a
  `mylang.json`. A nested `mylang.json`, such as `ledger/repros/FR-413`, never makes a
  project. A project absent on one side counts as empty on that side (§2.3).
- **Which compiler (Q10).** Every review runs
  `SELKA_COMPILER_PREFIX=<prefix> tools/mylang`. The prefix comes from
  `git show <REV>:COMPILER`, where `REV` is:
  - the new tip, for the hook;
  - the branch tip, for an open change on the site, so that its verdict matches what
    the gate will say;
  - the landed tip, for a landed change.

  A landed change's page is written once, with that pin, and kept. It is never
  regenerated when `main`'s pin moves, so a later breaking pin cannot turn history
  unreadable. If the named compiler is not installed, the review says so and names
  `tools/install-compiler.sh`.
- **No side effects in a project.** The hooks and `refresh.sh` set
  `MYLANG_FRICTION_LOG` and `MYLANG_PROFILE_DIR` to files under
  `~/.cache/selka-review/`. `tools/mylang` would otherwise write friction logs into
  the project directory it runs in, and they would appear as untracked files in
  whichever checkout merged.
- **Server.**
  - `selka-review.service` runs
    `http-server serve ~/.cache/selka-review/site --port 25080 --no-log` with
    `Restart=always`. Lingering is already on for this user, so it survives logout and
    reboot.
  - http-server listens on loopback only, on ports 25000 to 25255, because of FR-210.
    It already serves `index.html` for a directory and the HTML, CSS, JS and JSON
    content types the site needs.
- **Refresh.** `selka-review-refresh.service` is a oneshot with `Nice=15` and
  `IOSchedulingClass=idle`. `refresh.sh` takes a `flock`, so two refreshes never run at
  once. It then:
  1. moves `main-tree` to `main`;
  2. writes `projects/<p>/index.html` and `overview.json` for each project, with
     `overview <p> --html … --data … --back ../../index.html`;
  3. for every local branch other than `main` whose commits touch a project's source,
     writes `changes/<branch>/<p>.review.json` and `.html` with
     `review <p> --against main --head <branch> --test`;
  4. writes `merged/<new>/<p>.*` with `--range <old>..<new>` for each landing that has
     no page yet. The landings come from `landings.log`, which the hook appends at the
     `committed` state, and, for landings before the hook existed, from `main`'s reflog.
     - selka lands by fast-forward and by direct commit, as the reflog shows
       (`merge release-docs: Fast-forward`).
     - First-parent merge commits would miss these landings, and would mislead on
       merges of `main` into lanes.
  5. copies `bypass.log` and writes `gate-mode`;
  6. runs `review index`.

  A page is regenerated only when its key changes: the base sha, the head sha, the
  compiler prefix and the options. Branches checked out in lane worktrees appear with
  their committed state.
- **When it refreshes.**
  - `selka-review-refresh.timer` fires every 5 minutes (`OnCalendar=*:0/5`) and at
    boot (`OnBootSec=2min`). It is a calendar trigger, so it always has a next run;
    this is the lesson of the store timer that died on 16 October.
  - The `post-commit` and `post-merge` hooks start the refresh service without
    waiting: `systemctl --user start --no-block selka-review-refresh.service`.
  - They ignore a `systemctl` that fails. A sandboxed agent may have no user bus.
- **The merge gate (Q3).**
  - `reference-transaction` covers fast-forwards as well as merge commits;
    `pre-merge-commit` misses fast-forwards.
  - **Environment.** Inside a linked worktree the hook runs with `GIT_DIR` set to
    `…/.git/worktrees/<name>`. With it set,
    `git -C proj diff --name-only --relative` printed paths relative to the
    repository, not to `proj`, and `ref_diff.changedModules` relies on `--relative`.
    So the hook first unsets `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE`, then
    passes the repository's top level explicitly.
  - **Which updates it checks.** On the `prepared` state, for each line that updates
    `refs/heads/main`:
    - An old value of all zeros, which `git update-ref` sends, is replaced by the
      current value from `git rev-parse refs/heads/main`. Only a real creation
      (nothing there) passes unchecked.
    - Deleting `main`, and an update where old equals new (as `git reset --merge`
      sends), pass at once.
    - An update to a descendant of the old tip is reviewed as `old..new`.
    - Any other move, such as `commit --amend` on `main` or a sideways reset, is
      reviewed as `merge-base(old,new)..new`. Moving `main` back to an ancestor passes.
    - For each project whose source the range touches, the hook runs
      `review <p> --range … --check`.
    - It exits fast for every other ref, because it fires on every ref update.
  - **A refusal leaves the checkout dirty.** After an aborted `merge --ff-only`,
    `main` stayed put but the index held the branch's files. An aborted merge commit
    leaves `MERGE_HEAD` behind. Other runs land only from a clean checkout, so the
    refusal text ends with the command that restores it, `git reset --merge`.
  - **Bypass (D1 kept strict).** `SELKA_REVIEW_BYPASS="reason"` is accepted only for:
    - `E_REVIEW_BASE_UNREADABLE` or `E_REVIEW_HEAD_UNREADABLE`;
    - a range that changes `COMPILER`, which is a pin bump with its migration.

    A missing decision or note is never bypassed: the fix is to write it. Each bypass
    is appended to `bypass.log` (UTC time, old, new, reason) and shown on the index.
  - **Install.** `install.sh` copies `tools/review-site/hooks/` to
    `~/.cache/selka-review/hooks/` and sets `core.hooksPath` to that absolute path.
    - The setting is shared by every worktree.
    - A path inside the repository would silently run no hook in a lane worktree whose
      branch predates the hooks directory.
    - selka-projects has no hooks today.
- **Gate mode and go-live.** Other runs will land on selka `main` without knowing
  about notes: wave 2's batch P, the docs follow-up's F3, and the perf-feedback plan's
  B9. Their plans stop on unexpected refusals.
  - So `install.sh --report-only` installs the hook in report-only mode. It prints the
    review and logs "would refuse" in `landings.log`, but never aborts.
    `install.sh --enforce` switches it to blocking. `gate-mode` records which.
  - S2 installs report-only as soon as `main`'s pin contains C1 to C4 and the projects
    pass on it. That pin is wave 2's P or F3's re-pin when one carries C1 to C4. If
    both have landed without them, bump the pin yourself with the ladder plan's
    procedure and run every project's `check.sh` and `release check` on the new pin.
  - S2 switches to `--enforce` once P, F3 and B9 have all landed on selka `main`
    (their REPORT.md say so).
  - If no qualifying pin exists by the end of the run, S2 finishes everything on the
    scratch clone, records "go-live pending" with the exact `install.sh` commands in
    `REPORT.md`, and ends the run. That is not a failure.

## 6. Lanes

| Lane | Contents | Starts | Lands when |
| --- | --- | --- | --- |
| C0 | Read-only start: F2's status, today's `overview_types.Document`, the shared tables (`diagnostic_codes.zig`, lint and feature registration, the command list in `main.zig`), the files other active runs are editing; the lane order goes in `status.md` | now | `status.md` committed |
| C1 | Change notes (§2.2): parser, validation, `release.changes` and `release.citations` keys, `review draft`, `release cut` moving notes and counting them; not the overview listing (C4) | now | its tests; complete verification |
| C2 | The review core and the gate: §2.1, §2.3, §3.1, §3.3, §3.5, the terminal and JSON outputs of §3.6, and §3.2 items 1 to 5 | after C1 | CR1, CR2, and CR3's interface and decision items; complete verification |
| C3 | §3.2 items 6 to 8, §3.4 (with the AST block canonicalizer and the calibration), the shared generated-file rule and lint's change, `--test` | after C2 | the rest of CR3; complete verification |
| C4 | HTML: `review --html`, `review index`, `overview --html` with the note titles (§3.6, §3.7, §4) | after C3 **and** F2 on `main` | CR4; complete verification |
| C5 | `docs/tooling/change-review.md` (commands, formats, the note guide, codes), the `release-docs.md` changes, `features.json` entries with runnable doc examples, `experiments/change-review-20261020/parity.md` | with C1 to C4 | `doc-coverage .` and `doctest .` pass |
| S1 | The gate hook (every case of §5), `install.sh` with `--report-only` and `--enforce`, the bypass rule; tested on a scratch clone of selka-projects | after C2 | CR6's gate items on the scratch clone |
| S2 | The site: `refresh.sh`, `build-server.sh`, the units, the timer, `landings.log`; go-live (§5) | after C4 | CR5 and CR6 on the real selka-projects, or "go-live pending" (§5) |
| S3 | Pilot: reviews of the last 10 landings per project, the bypass and refusal counts, the report | after S2 | `REPORT.md` |

Each C lane follows CLAUDE.md's test rule: guest behaviour goes in `tests/lang`, Zig
behaviour in Zig tests beside the code, and CLI behaviour in `test/integration.zig`.
The fixture repositories are built in the tests the way the `lint --against` tests
build theirs (`src/lint_test.zig`), under `test/fixtures/review/`, and every fixture
read is declared in `build_test_inputs.zig`.

## 7. Gates and done criteria

| # | Criterion |
| --- | --- |
| CR1 | Every row of §3.3 has a unit test. A fixture corpus of at least 15 changes (one per row, plus mixtures) never prints the fallback "declaration changed" |
| CR2 | The gate cases are named tests: a decision added (pass); a decision edited (pass); a decision added under a release directory in the same change as its cut (pass); a decision only pending from an earlier merge (refused); a body-only change with a note (pass); a source change with no note (refused); a placeholder, too short and too long (refused); a visibility flip; a removal named from the base; a public change in a generated file (refused without a decision); a new project with one initial decision (pass); working-tree mode with untracked note and decision; `--range` over a fast-forward and over a merge commit; a side whose bodies fail to check (facts dropped, no refusal); a side whose declarations do not load (refused); a change outside the source (no note needed) |
| CR3 | Parity with the prototype on migrated copies. Build a scratch repository that replays `c338c34`, `70a50bd`, `66992fd` and `e5f137e` of `http-server`, each migrated by the compiler under test's `mylang fix`, with any hand edits logged. For `c338c34..70a50bd`: the 3 interface items explained by "Refusals carry a kind, not a status read back from prose"; the `framing::next_request` example change; `framing::Head` gives "case `Reject` carries `kind: RefusalKind` instead of `status: int`". For `66992fd..e5f137e`: 18 public changes and none explained; `cli::Command` gives "case `Serve` gained `blocking: bool`, `idle_ms: int`" and `ports::serve_on` gives "now takes `mode: launch.Mode`"; new authority on `conn::advance`, `event_server::run`, `launch::run` and `ports::serve_any`; changed tests `test_serve_errors`, `test_serve_no_log` and `test_serve_with_port`; 21 new tests; `parse_serve` flagged for special cases and a copied block; `ports.my` reported as generated. Wording may differ only where the migration changed a declaration's text, and every difference is logged in `parity.md` |
| CR4 | Two runs give byte-identical JSON and HTML. A test refuses any `http://` or `https://` resource reference in the template. The page renders both prototype changes, and the light, dark and phone widths are checked once by hand, with the check noted in `status.md` |
| CR5 | Targets, measured through `scripts/build-slot.sh timing` and reported: warm `review --check` on each pilot project under 10 s with a ReleaseFast compiler, markdown included; under 20 s added by the hook to a landing that touches one project; under 10 s for a full site refresh with nothing changed. A miss gets one profiled investigation within §10's bound and is reported with the profile. It is not a hard stop |
| CR6 | On a scratch clone: every update case of §5 behaves as written; a landing with an unexplained public change is refused, `git reset --merge` then leaves the checkout clean, and `git status --porcelain` is empty; a bypass for a missing decision is refused; a bypass for a pin bump is logged and passes; report-only mode logs and never aborts. On the real selka-projects, at go-live: the service survives `systemctl --user restart` and a killed process, the timer has a calendar trigger, and the index lists every project and every open branch with source changes |
| CR7 | Each landing passes complete verification, `fmt-check`, `doctest .` and `doc-coverage .`. Guardian is clean. No Python is added to `src/` or the install graph; the selka-side scripts are bash |

## 8. Decisions

**The user's, 20 October:**
- **D1.** A public change with no decision blocks the merge.
- **D2.** Every merge carries a short summary paragraph.
- **D3.** A server that is always on shows the project page and the change reviews.
- **D4.** No project guide. The summary page is enough.

**Recommended, accepted at launch unless struck:**
- **Q1.** Notes are files, `changes/unreleased/<slug>.md`, filed by `release cut`.
- **Q2.** The decision must be added or edited in the change, under any directory of
  `decisions/`. An older pending one does not count.
- **Q3.** In selka-projects the gate is a `reference-transaction` hook on
  `refs/heads/main`. It is report-only until the three other runs have landed, then
  enforcing. Bypasses are logged and allowed only for unreadable sides and pin bumps.
- **Q4.** The site runs on Selka's `http-server` at `127.0.0.1:25080` and is
  regenerated by a timer and by hooks.
- **Q5.** Pages are rendered by the compiler from an embedded template. They are
  self-contained and make no network request.
- **Q6.** Patching signals come from the syntax tree and never block.
- **Q7.** Only source changes need a note (§2.2).
- **Q8.** `--test` is optional, and the site uses it. `--check` never runs tests.
- **Q9.** A side loads when its declarations load. Facts that need checked bodies are
  dropped and named, never guessed.
- **Q10.** The hook and the site review with the pin of the revision under review.
  Landed pages are written once and kept.

**Open, for the user, none of them blocking:**
- Reach the site from other devices through a tunnel, like the user's other services,
  behind access control. It is loopback-only until then.
- Give the compiler repository's own merges a review. That needs a Zig front end and is
  out of scope here.

## 9. How it fits

- **Wave 2** goes on in `~/ai/canopy/mylang-wave2`. This run shares only small sorted
  tables with it (diagnostic codes, feature and lint registration, guide sections), as
  the docs follow-up's amendment of 20 October found for F1 and F2. Merge `main`
  before every landing and keep both sides' rows in order.
- **The docs follow-up.**
  - F1 and F2 run now in `~/ai/canopy/mylang-docs-followup`. F2 rewrites the overview
    generator, so **C4 starts only after F2 has landed on `main`**. Until then, C2 reads
    today's `overview_types.Document` and adapts if F2 changes it.
  - C1's change to `release cut` touches release code that F1 may also edit. Merge
    F1's landing first if it is on `main`.
  - F3 and wave 2's batch P re-pin selka-projects. §5 says how go-live waits for them.
- **The perf-feedback plan.** Its B9 lands on selka `main` too; §5's gate mode covers
  it.
- **If one Codex session runs several plans,** it finishes its current batch and then
  takes this run's lanes in §6's order.
- **The design-drift ideas** of 20 October (decision anchors, change classes,
  workaround witnesses) build on `review-v1` later. They are not in this run.

## 10. Operating rules and launch instruction for Codex

The language wave 2 plan's §10 applies, with these changes:
- Decisions go in `experiments/change-review-20261020/DECISIONS.md`. Progress goes in
  `status.md` and the finish in `REPORT.md`, in the same directory.
- Compiler work happens on `change-review/integration` in the worktree
  `~/ai/canopy/mylang-change-review`, branched from `main`. Land each C lane by
  fast-forward from the primary checkout after complete verification, as that §10
  says. Leave the untracked files in the primary checkout alone.
- selka-projects work happens on the branch `change-review` in the worktree
  `~/ai/canopy/selka-projects-change-review`. Fast-forward selka `main` only for S2's
  go-live, after CR6 passes on a scratch clone. Bump `COMPILER` only as §5 says.
- systemd units are installed only in S2, and only for this user. Never edit another
  unit in `~/.config/systemd/user/`.

**Hard stops:**
1. a change to the language itself;
2. a change to a decision in §8, D1 to D4;
3. relaxing CR1 to CR4, CR6 or CR7 (measuring better is allowed; CR5 is a target);
4. a broken premise, for example `reference-transaction` cannot abort a fast-forward
   on this git;
5. a failure that cannot be fixed within about 6 to 8 h;
6. anything outside these branches. Never touch pushes, `origin`, `claude/*`,
   `docs-followup/*`, `wave2/*`, `perf-feedback/*`, another run's worktree,
   `../guardian-zig`, `SPEC.md` or `selfhost/`;
7. resources: free space on `/` under 25 GB, or the machine swapping.

```text
You are implementing docs/audits/change-review-plan-2026-10-20.md in ~/ai/canopy/mylang: a
plain-English review of every change to a Selka project before it merges (mylang review,
with --check refusing a public change that no decision in the change explains, or a change
with no summary note), change notes, mylang overview --html, and in selka-projects a merge
gate hook plus a review site that is always on at http://127.0.0.1:25080/ on Selka's own
http-server. Read the plan fully, then CLAUDE.md, docs/tooling/release-docs.md,
docs/tooling/api-diff.md, docs/tooling/lint.md, the docs follow-up plan
(docs/audits/checked-docs-followup-plan-2026-10-20.md, with its 20 October amendment) and the
prototypes in experiments/change-review-20261020/prototype/. The two prototype pages are
https://claude.ai/artifact/WZqqVFiR8uDi9USy1gizs2 and
https://claude.ai/artifact/J7gDMyBvx8EiWgKJUz9iDk; if you cannot open them, the templates in
the prototype directory are the same pages. Decide, log in
experiments/change-review-20261020/DECISIONS.md, and continue; stop only for the hard stops in
section 10. Create the worktree ~/ai/canopy/mylang-change-review on branch
change-review/integration from main. Run the lanes of section 6 in order: C0, C1, C2, C3, then
C4 once the docs follow-up's F2 is on main, with C5 alongside; S1 after C2 and S2 after C4, in
~/ai/canopy/selka-projects-change-review on branch change-review. Install the hook report-only
first and switch it to enforcing only as section 5 says; if no qualifying pin exists, record
go-live pending and finish. Then run S3. Land each C lane on main after a green complete
verification, fast-forwarding only from the primary checkout, and merge main first whenever it
has moved. Never push. Install systemd units only in S2 and only the three this plan names.
Commit at every step with a progress section in status.md. Finish with REPORT.md.
```
