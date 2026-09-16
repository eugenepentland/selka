# Guardian feedback: R1/R2 corrective pass

Task: bind native-test receipt acceptance to the selected dependency closure and
share preparation/native libraries per selected provider graph
Branch: `codex/velocity-r12`
Base: `6a99ef4b`

## What Guardian exercised

Guardian ran automatically on `zig build` and on every `zig build test-*`
invocation. The final diff-scoped run passed all 88 checks with only the
existing report-only findings (`file-size`, `function-length`, `line-length`);
none of those findings named the changed code as a new hard failure. The focused
native-test and full public gates were then rerun on the final binary:

- `zig build test-units` — 1032 passed
- `zig build test-cli` — 98 passed
- `zig build test-native-tests` — 52 passed
- `zig build test-qbe` — 30 + 38 + 1 native/QBE/golden regressions passed
- `zig build test-doc-coverage` — 0 failures
- `zig build test-docs` — 120 run, 24 checked, 0 failed
- `zig build fmt-check` — clean

The shared `~/ai/canopy/guardian-zig/FEEDBACK.md` was not edited.

## Good findings and friction

- `spec` correctly rejected a second primary `// spec: NATIVE-TEST-5` tag. The
  new focused graph-sharing regression now carries `// spec-case: NATIVE-TEST-5`
  because the primary behavior remains owned by `test/integration.zig`.
- `line-length` forced the fake-compiler JSON fixture in the new unit test to be
  split at a readable declaration boundary.
- The new unit test originally left the fake compiler script open while spawning
  it, which surfaced as the platform `FileBusy` process-spawn error. Closing the
  file before `session.check` fixed it; this is worth remembering for any future
  test that writes and immediately executes a helper.
- The runner still prints `failed command: <guardian runner>` after a passing
  `PASS — N passed` summary. Polled logs therefore look like failures until the
  enclosing build status is checked; this is existing friction, not new to R1/R2.

## Concrete spec/doc patch requested

`SPEC.md` is outside this worktree's write ownership. Its NATIVE-TEST wording
still says a whole-snapshot source change invalidates the run and that receipts
record a `source` identity as an acceptance term. The corrected behavior is:

- receipt acceptance uses the planner's selected semantic dependency-closure key
  plus the selected contract and provider identities;
- the whole-snapshot source identity remains used to reject source changes during
  one invocation and as diagnostic JSON, but is not an acceptance condition;
- identical selected provider graphs share one declaration validation, checked
  project and prepared native library within one invocation.

Requested `SPEC.md` replacement text:

```text
- [NATIVE-TEST-3] ... Source changes during one invocation and compiler changes
  invalidate the run before result publication. Unrelated source edits do not
  invalidate receipts for tests whose selected semantic dependency closure and
  selected provider/contract identities are unchanged. ...
- [NATIVE-TEST-5] ... Test receipts record the selected semantic
  dependency-closure key and the selected contract and provider identities; the
  whole-snapshot source identity remains diagnostic. Identical selected provider
  graphs share one checked project and one prepared native library within an
  invocation, while distinct graphs stay isolated.
```

No `src/features.json` registration is needed; NATIVE-TEST-3/5 already exist.
`docs/tooling/guest-tests.md` already describes receipt reuse in terms of the
semantic dependency closure and selective helper invalidation, so it needs no
behavioral correction. A documentation sentence on one preparation per selected
graph would be optional.
