# Guardian feedback: W0 baseline verification (mylang)

## 2026-09-15 · codex · mylang — W0 baseline verification and 42-probe re-run

- **good:** The build-wired diff-scoped `run-all` gate passed all 88 checks on every
  target exercised here (`zig build`, `zig build test --summary all`,
  `zig build test-qbe`, `zig build test-native-tests`, and the ReleaseFast unit
  run) without policy, baseline, or snapshot changes. It explicitly stated
  `6/339 source file(s) in scope` and "NOT a whole-tree verification", which
  prevented me from over-claiming whole-tree coverage in the W0 evidence.
- **good:** The report-only `file-size` (4 findings) and `line-length` (88 findings)
  results stayed non-blocking on a documentation-only worktree, so evidence
  commits did not need ratchet edits.
- **friction:** Successful filtered/normal runs still print `failed command:` after
  the Guardian runner's `PASS`/`RESULT` summary for a zero-exit test process
  (reproduces the entries from 2026-09-14/15). I had to read the enclosing build
  exit status to avoid recording a false failure; a `PASS ... (exit 0)` tag on
  that line would remove the ambiguity.
- **friction:** Guardian's diff-scoped gate and the repository's doc-example gate
  disagree by design here: Guardian was green while `zig build test` and
  `zig build test-docs` failed on a mis-tagged fenced block in the newly added
  historical audit document. That is correct scope separation, but the build
  summary did not name the doctest step until the summary tree was read; a short
  "Guardian passed; failing step is `run exe mylang doctest`" line would make
  baseline triage faster.
- **wish:** When a ReleaseFast test compilation exceeds a declared `max_rss`
  ceiling, report the offending test root's name/path beside the peak (the
  full-gate output only said `compile test fast native failure`), and say whether
  the step was retried or cached afterward. I recorded the 2.31 GB vs 2.15 GB
  signal but could not attribute it to a specific root from the log alone.
