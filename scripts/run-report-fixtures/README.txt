Samples of what the test runners print, for tests/test_focused_test.py (the failure reader scripts/failure_report.py).
Real (trimmed from logs of 5 to 18 November 2026; the build runner's step tree after `Build Summary:` is cut):
  zig-expect-int.log        expectEqual on integers: `expected 1, found 3`
  zig-expect-strings.log    expectEqualStrings: the two blocks and `First difference occurs on line N`
  zig-expect-bool.log       expect(false): no message, the source line of the test names the check
  zig-error-return.log      a test that returned an error from a parser: first frame is not the test's
  zig-compile-error.log     a compile error in a test root (no test ran)
  guardian-nothing-ran.log  a filter that named no test: `test: FAIL - nothing the filter named ran`
  zig-crash-134.log         a test that panicked: `exited with code 134 with stderr:` and the panic line
  zig-leak.log              a test that leaked: `leaked 9 allocations:`
  zig-pass.log              a passing run: only the build runner's `Build Summary:` counts the tests
  terminal-fail.log         a test binary run by itself (dev_loop.py test): message, then `N name...FAIL (Err)`, then the trace
  terminal-pass.log         the same, passing: `All 19 tests passed.`
  build-slot-queued.log     a run still queued for a slot: `build-slot: FIFO ticket N, position P; ... waiting (Xs so far)`
Constructed from the exact wording of the code that prints it (no log of it was saved):
  zig-deadline.log          `test deadline: ... killed` (scripts/gate_summary.py's pattern) and a timed-out header
  zig-trap13.log            the F22 signature inside the found text of a guest-build test (as the gate printed it on 17 November)
