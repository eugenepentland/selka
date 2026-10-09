# Guardian feedback — M3 corpus migration, activation and ergonomics

## Good findings

- The build-wired diff-scoped gate ran `run-all` (88 checks) with zero blocking
  findings across the corpus, docs and test edits. `test-no-conditional`
  accepted the one-loop corpus regression test, `function-size` and `file-size`
  reported no new findings in `test/integration.zig` or
  `src/navigation_test.zig`, `spec` reported 386/386 behaviors covered, and
  `debug-print-ban` found none.
- `spec` plus `change-classification` kept the new M3 assertions linked to the
  existing `MUTATION-ENFORCE-1` and `NAVIGATION-1` ids as `// spec-case:`
  references, so a docs/corpus migration did not have to invent or fork SPEC
  bullets.

## Friction

- As in M2, a successful `zig build test-units` still prints
  `failed command: <test runner>` after the runner's `PASS — N passed`
  summary. Only the enclosing build status distinguishes the two, which is
  easy to misread in a polled background log.
- The full `test-units`/`test-cli` gates exceed short tool timeouts under the
  shared machine load and had to run as polled `setsid` jobs. The build-wired
  Guardian banner is emitted before the test result, so the log can look
  complete while the test runner is still working.

## Concrete request

- No blocking request. If the success-label ambiguity is cheap to fix, print the
  runner command only on a nonzero status, or prefix it with `guardian: rerun:`
  so a passing run is not labelled `failed`.
