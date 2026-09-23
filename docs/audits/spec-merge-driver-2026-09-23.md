# A merge driver for `SPEC.md` — 2026-09-23

`SPEC.md` is Guardian's only spec file, and every behavioural change adds a
`- [TAG] …` bullet to it. Parallel lanes add those bullets at the end of the
same sections, so git's line merge sees two insertions at one point and
conflicts. That was item one of §3 of the
[development-speed audit](development-speed-audit-2026-09-23.md). This change
merges `SPEC.md` by tag instead of by line.

## What changed

- `scripts/merge_spec.py` is the driver. Git calls it with the base, ours and
  theirs files, the path and the marker size (`%O %A %B %P --marker-size %L`).
  It writes the result over ours and exits 1 when a conflict is left.
- `.gitattributes`: `/SPEC.md merge=spec-bullets`.
- `scripts/setup-git.sh` registers the driver in the clone's config. Run it
  once per clone.
- `tests/test_spec_merge.py` holds the tests: synthetic cases, git end to
  end, and a replay of history. They run as `zig build test-spec-merge`, which
  `zig build test` depends on (about 1.5 s).
- `CLAUDE.md` and `README.md` say to run the setup once per clone.

## The merge rule

A **bullet** is a line starting `- [TAG]`, plus every following line up to a
blank line, a heading or the next `- ` item. `SPEC.md` has wrapped bullets:
`FEATURE-REPORT-*`, `DOCCOV-*`, `DOCTEST-*`. There are no fenced blocks.

The **bullet text** is merged per tag, comparing its full text in base, ours
and theirs:

| base / ours / theirs | result |
|---|---|
| ours = theirs | that text (both deleting it counts) |
| ours = base | theirs' text, or theirs' deletion |
| theirs = base | ours' text, or ours' deletion |
| all three differ, including modify/delete and a tag added twice with different text | **conflict**: standard diff3 markers at the bullet's place |

The **layout** is merged with a three-way line merge (diff3) over tokens. Each
prose, blank or heading line is one token. Each bullet is one token, made of
its tag alone, so amending a bullet does not change the layout. This keeps
untagged prose, headings and section order as git would. Where both sides
changed the same stretch:

1. If the stretch holds only bullets and blank lines on all three sides, it is
   resolved. The result is ours' version of the stretch, minus the bullets
   theirs removed from it, followed by the tokens theirs inserted, minus
   bullets already present. Each side's additions stay where that side put
   them, in their section. Two appends at one point come out ours-then-theirs.
   That is the order a merge of the lane into the integration branch reads,
   and the order the hand union used, which is why the replay matches byte
   for byte.
2. Otherwise, lines both sides added identically are taken once. This is git's
   own hunk trimming: the common head and tail, and every shared run when the
   base had nothing there. The rest is resolved by rule 1 if it holds only
   bullets. If not, it is a standard conflict: an untagged line is never
   unioned, because two sides adding text at one point may be two versions of
   one paragraph.

**Text is never dropped silently.** A bullet leaves the result only when its
text decision says it was deleted. Modify/delete is a conflict that shows both
the base text and the amended text. A bullet that both sides placed in
different spots is written once, at its first place; its text, or its
conflict, is already decided per tag. The driver declines and returns
`git merge-file`'s own result for the whole file in two cases: an input
already repeats a tag, or a bullet the decisions keep would be missing from
the result.

## Replay of the real conflicts

Every merge from 2026-09-17 to 23, on any branch, whose `SPEC.md` conflicted
under git's merge (`git merge-tree`) was replayed: 17 merges, all six on
`perf/parity-integration` among them. Each replay took the merge commit's two
parents and their merge base, ran the driver, and compared the output with the
committed `SPEC.md`. The `fix/checker-bugs` merge named in the request is in
the table too; git merged its `SPEC.md` cleanly. To reprint the table:

```bash
python3 tests/test_spec_merge.py --replay
```

```text
merge     lane                          git hunks/lines  union dup tags                 driver hunks/lines  verdict
977acf88  perf/lib-text-scan            1/8              -                              0/0   identical
92ca76b7  perf/lib-sort                 1/9              -                              0/0   identical
21c8c63f  perf/root-liveness            1/9              -                              0/0   identical
996a89ec  perf/lib-dict-hash            1/15             PY-DICT-2                      0/0   same bullets, one moved
79835b13  lang/keyed-sort               2/22             PRELUDE-SORT-KEY-2,PY-DICT-2   0/0   identical
17642218  fix/lox-port-bugs             1/10             MUT-PARAM-4                    0/0   identical
b95ad5d5  fix/checker-bugs              0/0              -                              0/0   identical
9a43eea3  ba857f44 → loop-range-facts   1/9              -                              0/0   identical
027cf1b3  parity-integration → main     1/10             IO-13                          1/6   real conflict
e42d48c0  overnight → codex             1/18             SELFHOST-COMPONENT-IDENTITY-1  0/0   identical
915daf10  item 3 → integration          1/29             -                              0/0   identical
0560eebb  item 4 → integration          1/26             -                              0/0   identical
e727d8e2  items 5, 6 → integration      1/18             -                              0/0   identical
e3ae1df8  lever-search → main           1/191            INVOKE-TEXT-1                  2/41  real conflicts + deliberate drop
0c199005  L2 onto L1                    1/24             -                              0/0   identical
d091db50  W10 frontend cache            1/6              -                              0/0   identical
5adafee3  eaa139c → ab0f…               1/14             PY-STR-3,PY-ASSERT-1           0/0   identical
9456e476  991bdea → ab0f…               1/10             PYTHON-CORE-1,PYTHON-CORE-2    0/0   identical
```

How to read the columns:

- **git hunks/lines** counts git's own conflict hunks (`git merge-file --diff3`)
  and the lines inside them.
- **union dup tags** lists the tags that taking both sides of every hunk
  (`git merge-file --union`) leaves twice *with different text*. These are
  amended bullets: one side rewrote a bullet next to where the other side
  appended. Guardian rejects this failure. It hit 8 of the 17 merges, so it
  was not a rare corner.
- **driver hunks/lines** counts the conflicts the driver left.

**14 of 17 identical.** For these the driver reproduces the committed
resolution byte for byte, including the two merges where the hand union needed
a fix-up before commit. In `lang/keyed-sort` the lane amended
`PRELUDE-SORT-KEY-2`; in `perf/lib-dict-hash` the lane amended `PY-DICT-2`
(a `str` key now hashes UTF-8 octets, not scalars). In both, the driver keeps
only the new text, with no duplicate.

**`996a89ec` (perf/lib-dict-hash): the same bullets and text, one moved.** The
lane amended `PY-DICT-2` and appended `PY-DICT-3..5` after it. The integration
branch had appended `PRELUDE-SORT-KEY-2`, `TEXT-SCAN-1..3` and
`LIST-SORT-RUNS-1` after it. The coordinator kept theirs' copy of `PY-DICT-2`,
so it moved down next to `PY-DICT-3..5`. The driver keeps it at its base place
with the amended text. The set of bullets and every bullet's text are
identical; only that one line's position differs.

**`027cf1b3` (perf/parity-integration into main): one real conflict, `IO-13`.**
Both sides added `IO-13` with different text: main said "a fixed-array
element", the integration branch said "a tuple or fixed-array element". The
driver leaves exactly that bullet in markers. Resolving it with the committed
text, which is theirs, gives the committed file byte for byte.

**`e3ae1df8` (perf/lever-search into main): two real conflicts and a
deliberate drop.** The two branches had implemented the same agent features
separately. The driver leaves two conflicts, 41 lines, where git left one of
191:

- `INVOKE-TEXT-1` was added on both sides with different text.
- One side added an HTML marker line (`<!-- WS1-CONTEXT-SPEC-APPEND -->`) at
  the point where the other side added bullets.

After those two are resolved to the committed text, every bullet matches
except 14 draft `INVOKE-*`, `WIRE-TEXT-*` and `NATIVE-WIRE-*` bullets. The
coordinator removed those on purpose, together with their tests (the merge
message says so), and no merge rule can infer that. The driver also keeps the
ten bullets (`OPTION-FLOW-1..4`, `GENERIC-EXPECTED-1..3`, `PY-DICT-2`,
`SCHEMATIC-BULK-1`, `HOST-PACKED-1`) that the hand resolution first lost and
then restored.

`tests/test_spec_merge.py` pins each verdict. A clone that lacks these commits
skips the replay tests.

## Synthetic cases

Every rule has a case: both sides append to one section; one side amends a
bullet at the point where the other appends; one-sided amendment; two-sided
different amendment (conflict); two-sided identical amendment; deletion next
to an append; modify/delete (conflict, text kept); additions in different
sections; a one-sided prose edit; a two-sided prose edit (conflict); prose
against bullets at one point (conflict); prose and bullets at different points
(clean); a wrapped bullet amended; one tag added by both sides with the same
text (kept once) and with different text (conflict); a bullet moved on one
side and amended on the other; a repeated tag in an input (declines).

The command-level cases check that the result is written over `%A`, the exit
status, that `%L` sets the marker size, and that a declined merge falls back to
`git merge-file`.

The git end-to-end cases run in a throwaway repository with global and system
config disabled and inherited `GIT_*` variables removed:

- A configured merge is clean, and running the setup twice leaves one config
  entry.
- A linked worktree picks up the shared config, even when the merge runs from
  a subdirectory.
- An unconfigured repository gets git's ordinary `CONFLICT (content)`.
- A tree whose `scripts/merge_spec.py` is missing falls back to
  `git merge-file`.

## Setup and failure modes

Run this once per clone:

```bash
sh scripts/setup-git.sh
```

It sets `merge.spec-bullets.name` and `merge.spec-bullets.driver` with plain
`git config`. That writes the clone's common `.git/config`, which every linked
worktree shares, and running it again only rewrites the same two keys. The
driver command is relative, and git runs it from the top of the worktree being
merged, so each worktree uses its own branch's copy of the script.

- **Driver not configured.** Git ignores a `merge=` attribute that names no
  configured driver and uses its ordinary text merge. Nothing breaks: the old
  append conflicts come back. The end-to-end test pins this.
- **Script missing** (a branch from before this change, or a bare
  repository). The configured command runs `git merge-file`, which is exactly
  git's default result.
- **Driver declines** (a tag already repeated in an input). Same as above:
  `git merge-file`, with a note on stderr.
- **Python 3.9 or newer** is needed at merge time, as for the repository's
  other scripts.

## Other append-heavy files

`git merge-tree` over every merge from 2026-09-10 to 23 on every branch counts
the conflicts per file:

| file | conflicted merges |
|---|---|
| `SPEC.md` | 17 |
| `src/sema.zig` | 9 |
| `src/main.zig` | 4 |
| `src/qbe_build.zig` | 4 |
| `test/integration.zig` | 4 |
| `src/features.json` | 2 |
| everything else | 3 or fewer each |

Only `SPEC.md` is an append-only list keyed by an identifier. `src/features.json`
conflicted twice in two weeks: once in the big `lever-search → main` merge, and
once in a worktree merge (`f6ba0d3e`). That does not justify a JSON-aware
driver. The code files conflict because two lanes edited the same function,
which a text-structure driver cannot fix. That is the audit's other advice:
split lanes by file ownership.
