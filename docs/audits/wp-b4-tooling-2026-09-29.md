# WP-B4 tooling and GC follow-up

This lane starts from `claude/rc-perf` at `1a098368`. Embed work waits for the
combined Phase A branch. Independent changes and their evidence are recorded
here so that integration does not mistake the remaining collector work for a
completed item.

## Independent tooling changes

| Item | Rule and coverage | Evidence |
| --- | --- | --- |
| Named module tests | `test-memory-budget` uses `src/memory_budget.zig` as its own test root and participates in `test` and `test-compile`. The named `runtime_contract` module has no tests; other named modules have existing dedicated roots. | Six memory budget tests pass; input coverage recognizes the new root. |
| No-cache objects | `--no-cache` disables frontend reuse independently of `--cache-dir`; no-cache tests stage native objects inside their owned source snapshot. | CLI-CACHE-ISOLATION-1 checks both argument orders; the CLI driver checks test/build source-root cleanliness and explicit build object placement. |
| Doctest workspaces | Workspaces use `TMPDIR` or `/tmp`; child builds receive the workspace object directory. | The CLI driver checks both documentation and caller roots remain clean and temporary workspaces are removed. |
| Frame advice | Failed tests retain their located R_FRAME_LIMIT trap and explain `--max-frames=N` and the required `--max-memory`. | TEST-FRAME-ADVICE-1 exercises a recursive test with a two-frame budget. |
| Host and guest ceilings | Only guest children receive a one-use receipt for restoring the compiler-installed soft RLIMIT_AS; caller soft and hard ceilings remain effective. | MEMORY-HOST-GUEST-1 covers the named module and native guard. The CLI maps over 9 GiB virtually under the default compiler ceiling; an inherited 6 GiB soft ceiling permits a 5 GiB reservation and rejects a 9 GiB reservation. |
| Selfhost numbers | The lexer recognizes numeric prefixes, underscores, leading dots and exponent extents with the production token boundaries, including malformed spelling boundaries. The existing differential harness accepts a live compiler and runs in `test-selfhost-numeric`. | NUM-LITERAL-1 fixture plus the full lexer corpus: 31 fixtures, 450 token lines, zero mismatches, three documented skips. Ampersand now produces the production lexer's existing token; expression rejection belongs to parsing. |

## Proven snapshot corrections

- GC-MUT-ARG-ROOT-1: preparing a mutable field or element can redirect the owner
  at the beginning of its copy-on-write place. A previously read expression
  snapshot must then publish its own root. The original mutable argument repro
  passes regular GC and stress; the reduced guest test passes RC, GC, stress,
  counting RC, release RC and release GC.
- ITERATION-FIELD-SNAPSHOT-1 and RC-ITERATION-HOLD-TRANSFER-1: a hidden loop
  source remains a semantic observer of a named transfer, so moving a record
  field cannot give that name exclusive ownership of the loop's header.
  Ownership classification and field extraction preserve a snapshot. The RC
  field-transfer planner no longer treats the hidden iteration hold as an
  exception. Direct structural writes to the actual iteration source retain
  their existing mutation trap. The original field-move repro passes regular
  GC and stress; the guest regressions pass all six modes above. The older CLI
  assertion has been updated to check the original iteration sum and final
  grown collection rather than expecting a false mutation trap.

The iteration observer currently compares root identity conservatively. Exact
field paths would let later interface analysis avoid copying unrelated sibling
fields of the same record. Generated code and corpus measurements remain lane
acceptance requirements.

## Remaining work and validation

The arena and scan-plan historical repros still fail under stress (139 and 134
respectively) and pass regular GC. Removing only their `with arena()` scope
lines, while retaining the bodies, makes both pass stress. Backtraces place the
failures in collection during list clones before the arenas open: `f1` through
`cow_unique_in`, and `f3` through `cow_share`. This narrows the issue to arena
presence and generated root/lifetime planning. A dictionary metadata lifetime
experiment and a live scalar root-slot experiment did not fix these failures
and are excluded from the change.

Focused tooling and native tests pass. The first broad Zig gate found the old
CLI iteration assertion described above; it requires rerunning after the
contract update. Broad guest modes, Lox, 100-seed fuzz, both-backend corpus
measurements and combined-base embed coverage remain outstanding at this
checkpoint. Scratch evidence lives under the lane's private `.tmp`; it is not
durable acceptance evidence until the final results are summarized here.
