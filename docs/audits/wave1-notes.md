# Wave 1 notes: output is a capability (D1)

Branch `eaa/wave1`. This file carries the shared-file material the wave was not
allowed to edit (SPEC bullets, `src/features.json` entries, docs examples) plus
the migration record.

## Status of this branch

Landed as a **dual-spelling stepping stone** so the tree stays green:

- New capability kind `Stream` (`stream_cap`, capability index 5) with the
  Python spelling `Stream`; `capabilityIndex` is still `u3` (6 of 8 slots used).
- `main` may declare `out: Stream` and `err: Stream`. The entry rule matches
  Stream parameters **by name** (`out`, `err`), admits at most one of each, and
  rejects any other Stream parameter name with `E_MAIN`.
- `stream.print(values..., sep=, end=)` and `stream.write(text) -> int` are
  methods on a `Stream` local. Any parameter name works on a helper
  (`def show(log: Stream)`), and it can be handed `out` or `err`.
- `debug(values...)` writes to stderr, takes no capability, contributes no
  effect, and returns unit.
- `print(...)` / `eprint(...)` are **still accepted** for this version, so the
  27 corpus files, 169 Zig `print(` sites, docs fences and SPEC IO bullets need
  no migration yet. `E_OUTPUT_CAPABILITY` is therefore not emitted yet.

Still to do in the second step (see "Remaining" below): the wide migration,
`E_OUTPUT_CAPABILITY` for bare `print`, dropping `debug` nodes in a ReleaseFast
build, and handing guest test cases a `Stream` pair.

## Proposed SPEC bullets

Append beside the IO bullets in `SPEC.md`. They intentionally describe the
final (migrated) state; trim the dual-spelling sentence once the migration
lands.

```markdown
- [STREAM-CAPABILITY] `Stream` is a capability passed like `Filesystem`. The
  entry point may declare `out: Stream` and `err: Stream`; the entry rule
  matches Stream parameters by name, admits at most one of each, and rejects any
  other name with `E_MAIN`. `stream.print(values..., sep=, end=)` renders like
  `print` and `stream.write(text) -> int` writes the text and returns its
  character count; both contribute the `output` effect and take the destination
  from the receiver value, so a helper declared `def show(log: Stream)` may be
  handed either `out` or `err`. A bare `print`/`eprint` names `E_OUTPUT_CAPABILITY`
  with the fix "add `out: Stream` to this function and pass one from main".
  Streams are granted unconditionally, including under `--restrict`. The
  per-type native renderers write through the stream's own sentinel, so one
  lowering serves `out`, `err` and a forwarded stream.

- [DEBUG-LINE] `debug(values...)` is the only way to write without a capability:
  it renders like `print` to standard error, takes no capability, contributes no
  effect, returns unit, and is emitted only by Debug builds and by `run`/`test`.
  A `--mode ReleaseFast` build drops the node in lowering, so a debug line never
  changes a signature or a checked effect bound.
```

## Proposed `src/features.json` entries

```json
"stream-capability": {
  "kind": "language",
  "summary": "`out.print(...)`/`err.print(...)` and `stream.write(text)` write through a `Stream` capability and contribute the `output` effect.",
  "doc": "docs/io.md#stream"
},
"debug-line": {
  "kind": "language",
  "summary": "`debug(values...)` writes to standard error without a capability and contributes no effect.",
  "doc": "docs/io.md#debug"
}
```

Both anchors need new sections in `docs/io.md` (shared file, not edited here).
Suggested runnable examples for those sections:

```mylang
# doc: skip Historical pre-redesign syntax retained as audit evidence.
def main(out: Stream, err: Stream) -> int:
    out.print("result:", 42)
    err.print("note", sep=": ")
    written: int = out.write("raw")
    debug("count", written)
    return 0
```

## Migration record

`scripts/migrate-print-to-stream.py` is the committed one-off rewriter. It
rewrites `print(` -> `out.print(` and `eprint(` -> `err.print(` only inside a
top-level `def main` body and adds `out: Stream` / `err: Stream` to main's
signature. Helpers that print are left to a hand pass (they need the parameter
and the call site threaded), which is the point of the rule. `--check` prints
the sites without writing.

Counts from the plan, unchanged here because the dual spelling keeps them
working: 27 corpus `.my` files, 31 Zig test files with 169 `print(` sites, 18
fenced doc examples in seven pages, two `eprint` uses, SPEC bullets IO-1..IO-6.

### Proposed `docs/io.md` prose

Replace the IO-1 opening ("`print(values...)` writes ...") with:

> `stream.print(values...)` writes each argument's Python rendering to the
> stream, separated by single spaces and followed by one newline. The entry
> point receives the standard streams as `out: Stream` and `err: Stream`; a
> helper may take any `Stream` name and be handed either. The bare `print` and
> `eprint` spellings are gone: `print(...)` reports `E_OUTPUT_CAPABILITY` with
> the fix to add `out: Stream`. The keyword arguments `sep=` and `end=`, the
> rendering rules and the `output` effect are exactly the old ones.

Add a `## debug` section: `debug(values...)` writes to standard error, needs no
capability, contributes no effect, and is stripped from `--mode ReleaseFast`
builds.

### Proposed `SPEC.md` IO bullet edits

- IO-1..IO-6: replace `print` with `stream.print`/`out.print` and add that the
  destination is the receiver.
- IO-4 effect bound still applies to `.print`/`stream.write`; `debug` is exempt.
- Add an IO-12 (or renumber) for `Stream` entry naming and `E_OUTPUT_CAPABILITY`.

## Remaining (second step)

1. **Wide migration.** Run `scripts/migrate-print-to-stream.py` over
   `examples/`, `experiments/`, `test/`, `tests/`, `velocity/` and the Zig test
   source strings; hand-thread `out: Stream` through helper functions; rewrite
   the 18 fenced doc examples on non-shared pages and the shared pages from the
   prose above. Move the 13 CPython-oracle probes to `mylang-only` and record
   the lane C baseline change in `velocity/goal.json`.
2. **`E_OUTPUT_CAPABILITY`.** Once no call sites remain, make `outputBuiltin`
   return a diagnostic instead of a sink.
3. **ReleaseFast `debug` drop.** Thread the build mode into `lower` (or filter
   the bytecode at build time) so a ReleaseFast build emits nothing for `debug`.
   Today it emits to stderr in every mode.
4. **Guest tests.** Hand each `mylang test` case a `Stream` pair the way the
   entry shim does, so `def test_x(out: Stream)` works. Today a guest test can
   only reach output through the dual-spelling `print`; a test that declares a
   parameter needs a cases-file `arguments` entry, so the Stream pair is not yet
   injected.
5. **`qbe_providers.c` sentinel.** The plan put the stream sentinel there; this
   branch keeps it in `src/qbe_io.h` as `MYL_QBE_STREAM_STDOUT/STDERR` because
   only the IO runtime reads it. Move it if wave 4's `Host` sentinel table makes
   one shared header preferable.

## Test tags

`src/io_print_test.zig` carries `// spec: STREAM-CAPABILITY` tests for the
entry name rule, `out.print`/`err.print` routing, a helper receiving either
stream, `stream.write`'s count, and `debug` under `noio`.

## Verification run here

- `zig build` — green while a temporary `## Ungrouped` / `- STREAM-CAPABILITY`
  bullet and matching tag were present; the committed tree deliberately omits
  both (shared files) and so Guardian's spec check alone will block. Build the
  tree after adding the SPEC bullet above.
- `zig build test-units -Dtest-filter=STREAM-CAPABILITY` — 14 passed, 0 failed.
- `zig build test-units -Dtest-filter=IO-` — 24 passed, 0 failed.
- `zig build test-units -Dtest-filter=effect` — 83 passed, 0 failed.
- `zig build test-units` (whole root) — 1135 passed, 0 failed.
- `python3 scripts/focused_test.py cli eprint` — 1 passed.
- `python3 scripts/focused_test.py golden replay` — 1 passed (56.6 s).
- `zig-out/focus/mylang test tests/guest` — 42 passed across 11 programs.
- `zig-out/focus/mylang run` a probe with `out.print`, `err.print`,
  `stream.write`, `debug` and `return 7`: stdout `hello 42\nraw`, stderr
  `oops\ncount 3\n`, exit 7; the same under `--restrict`.

### Commit

The session sandbox mounts the main checkout's `.git` read-only, so
`git add`/`git commit` in this worktree fail with `index.lock: Read-only file
system` and a `danger-full-access` escalation was rejected for lack of an
approval channel. The working tree is therefore green but **uncommitted**; the
orchestrator should run:

```
git -C /home/epentland/ai/canopy/mylang-worktrees/eaa-wave1 add -A
git -C /home/epentland/ai/canopy/mylang-worktrees/eaa-wave1 commit -m "wave1: Stream output capability, stream.print/write and debug"
```

After adding the SPEC bullet (and features.json slugs) from above, Guardian's
spec check passes as it did locally.

