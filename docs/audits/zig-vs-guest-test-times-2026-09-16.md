# Zig and .my test-suite timing — 2026-09-16

## Results

| Suite / state | Test count | Time | Evidence |
| --- | ---: | ---: | --- |
| Zig compiler units, Debug, actual execution | 1,036 | **84.25 s** | Just-completed user gate in `final-debug`; runner-reported test wall time |
| `.my` guest suite, fresh native cache | 42 | **8.20 s** | One fresh-cache invocation |
| `.my` guest suite, warm objects, `--force` | 42 | **4.11 s** | Median of three invocations; all 42 execute |
| `.my` guest suite, unchanged receipts | 42 | **1.36 s** | Median of five invocations; 42 cached, zero executed |

All measured guest runs passed. The existing full Debug gate also completed
successfully: 39/39 build steps; its unit runner executed and passed 1,036 tests.
Other Zig test roots could be build-cache hits in that run, so that summary is
not the repository's complete registered-test count.

## What these numbers mean

The suites have different scope. The Zig unit suite has roughly 25 times as many
test cases and covers compiler internals, rejected programs, allocation-failure
sweeps, native execution, resources, and cache correctness. The `.my` suite in
`tests/guest` has 42 positive behavior cases across 11 programs.

These totals do not establish that one implementation language executes an
equivalent test suite faster. In particular, the `.my` cached result is a skip,
whereas the 84.25-second Zig value is actual test execution.

Previous recorded warm unit runs were 69.11 seconds for 1,031 Debug tests and
80.73 seconds for 1,032 Debug tests. A prior ReleaseFast run executed 1,030 tests
in 48.72 seconds, with one skipped. These come from different snapshots/cache
states and are context rather than a controlled Debug/Release comparison.

Zig compilation and test execution are separate costs: the 80.73-second warm
unit log reports the test executable's compilation as **cached (8 ms)**. That
run's delay was in executing tests and their subprocesses. Other logs show
ReleaseFast test-executable recompilation taking approximately two minutes.
Consequently, an optimized compiler can make `.my` operations faster while
rebuilding an optimized Zig test executable remains expensive.

Self-hosting can remove the Zig compiler rebuild from ordinary frontend edits.
Preserving coverage and adding selective test reuse are still necessary to
reduce the time spent executing the tests themselves.

## Method and provenance

- The user already had full Zig gates running. Their existing logs were read;
  this measurement did not start, restart, or modify those gates.
- Current unit evidence: `/tmp/corr-debug.log`, exit 0, source worktree commit
  `216965ce7d1b50b38254e78c7980ef1d19bbb1a9`. The completed log is copied into the
  evidence JSON because that temporary filename can be reused by later gates.
- The guest measurement used a pinned copy of the Debug compiler installed in
  that worktree, a private copy of `tests/guest`, and its own native cache.
  Executable hash, advertised compiler identity, commands, outputs, and scratch
  paths are recorded in the JSON.
- Guest options: `--json --jobs 1`, Debug guest mode, the pinned Zig toolchain and
  QBE. One worker makes this a serial suite measurement; the repository's normal
  directory command may fan out across several workers.
- Guest wall time includes process start, discovery/preparation, compilation,
  execution or receipt reuse, and process exit. Zig's 84.25 seconds is the unit
  runner's execution wall time, excluding executable compilation and the wider
  build graph. No full-gate end-to-end wall time is claimed.
- Machine was shared with the active Zig gates. These are indicative local
  timings. “Fresh cache” clears the private mylang cache, not OS/Zig global
  caches or installed runtime archives.
- No Guardian gate was exercised by this measurement task; the recorded gate
  belongs to the ongoing implementation task.

[Raw measurements and copied Zig logs](zig-vs-guest-test-times-2026-09-16.json)
