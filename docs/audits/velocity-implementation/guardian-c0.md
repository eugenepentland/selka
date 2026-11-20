# Guardian feedback: package C0

Recorded 2026-09-15 while implementing C0 (`work-report-v1`). Guardian ran
automatically on every `zig build test-units` / `zig build test-cli` in the
`velocity-c0` worktree; the final diff-scoped run passed all 88 checks. The
shared `guardian-zig/FEEDBACK.md` was not edited.

## Good findings

- Diff-scoped mode was accurate and fast. It reported exactly the C0 source
  files in scope and caught real problems before tests ran:
  - `function-size`: `sessionReply` had 7 runtime parameters; bundling
    `{action, status, failure}` into a `SessionReply` struct fixed it.
  - `catch-discipline`: an empty `catch {}` around best-effort receipt output;
    the file's existing `catch break :label` shape fixed it.
  - `anytype-budget`: two new generic helpers pushed `main.zig` to three
    `anytype` parameters; passing a `usize` function count instead of the
    compilation object brought it back to two.
  - `type-size`: the 7-field cap forced the `work-report` counters out of a
    flat struct. `Work` and `SessionView` now stay at seven fields, with
    `reused_results` emitted as a sibling field of `session`.
  - `spec`: a new `WORK-REPORT-1` tag was rejected as unlinked because C0 may
    not edit `SPEC.md`; retagging the regressions `// spec-case:
    INVALIDATION-EXECUTION-1` linked them to the existing bullet. A future
    `WORK-REPORT-1` SPEC bullet should let them be promoted to `// spec:`.
  - `change-classification` correctly demanded a `// spec:`-linked test in the
    same change; without it the report would have been untested behavior.

## Friction

- The type-size cap of 7 fields and the anytype cap of 2 are good discipline,
  but they interact awkwardly with a report whose contract names nine
  top-level keys. The workaround (flat JSON fields backed by a 7-field struct,
  cumulative `reused_results` outside the per-stage view) is documented in
  `docs/tooling/work-report.md`; a future cap on *JSON keys* rather than struct
  fields would match the contract better.
- Guardian's `posture` for `spec` tags assumes `SPEC.md` is writable by the
  package. C0 explicitly may not edit it, so the only way to keep a new
  behavior covered was to reuse an existing spec ID. The integrator should add
  the `WORK-REPORT-1` bullet and features.json entry before the final pass.
- `line-length` and `file-size` are report-only and produced 230 findings on an
  otherwise green diff. They are easy to ignore, but they make the summary
  noisy; a per-check summary line with the single worst location would be
  enough.
- Guardian runs at the start of `zig build test-units`; the first failing run
  also reported "zig-out binaries predate this failed run", which is useful. A
  one-line hint that `zig build` (not only the filtered unit run) installs the
  executable would make the binary/source skew easier to resolve.
