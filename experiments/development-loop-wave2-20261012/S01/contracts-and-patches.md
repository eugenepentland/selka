# Wave2 S01 contracts and coordinator patches

Base B0: c1857310e0bf623545380c8de24515f1b9970021.

## Native supported observation

Guardian's current GUARDIAN_TEST_TIMINGS wide mode retains only its top100 tests
above 1ms. It cannot establish full timing coverage. Pinned Zig's TestResults
wire does not include a duration; it does include per-request test_started and
indexed test_results, plus qualified names metadata. The new native proxy uses
that supported wire contract. It forwards stdin/stdout bytes unchanged and
inherits stderr; the original runner retains selection, assertions and verdicts.

Every measured tests[] row carries `elapsed_scope: runner-protocol-interval`.
Start is receipt of test_started, end receipt of matching test_results, in the
proxy's monotonic clock. Includes runner reporting and transport/scheduling delay.
Pure test-body time remains unknown. Skipped rows have null elapsed. Leaks/logged
errors count as failed. Fuzz/unknown version, malformed metadata/results, excessive
frames, partial wire and missing completion cannot invent complete telemetry.
The document selected count names actual dispatched requests (including shard
skip responses), with `selection_scope: actual-client-dispatch`; the union of
actual passed/failed rows across shard members remains the executed test inventory.
Individual test IDs are stable root ID plus runner-qualified name, without shard
index. The registered action/member and action_key carry the mode/source identity.

The existing read_tests validator now preserves elapsed_scope per row. Legacy
Python producers default to test-execution (setup through teardown). S07 is
qualifying a separate protocol policy clock; it must never conflate these clocks.
Malformed native observations become unknown instead of appearing zero-selected.

## Exact build integration request

For the initial independent tooling root and text-scalar root, replace the
existing b.addRunArtifact(compile) step creation with equivalent test-runner mode:

```zig
const run = b.addSystemCommand(&.{
    "python3", "scripts/verification_native_telemetry.py",
    "--action-id", "tooling_unit", "--member", "0",
    "--root-id", "src/tooling_root_test.zig", "--",
});
run.addArtifactArg(tooling_unit);
run.producer = tooling_unit;
run.enableTestRunnerMode();
```

For scalar use action `text_scalar_unit`, root `src/text_scalar_root_test.zig`,
actual member index 0. Keep original name, has_side_effects, max_rss, cwd,
input/environment manifests, filters and registrations. Zig Maker adds --listen=-
in test-runner mode; append no duplicate flag. Proxy remainder passes that flag
and existing Guardian filters/shards to the original executable. Adopt other
native roots/shards only with their actual registered member indices. Never
introduce a second native run to collect telemetry. Installed/source-build graphs
continue to use no Python; this proxy is only developer-test execution.

Register scripts/verification_native_telemetry_test.py and
scripts/verification_guest_telemetry_test.py in verification-cache tests; add new
helpers/tests and the changed verification_telemetry.py to every applicable input
closure. Native recipe dependencies must include proxy + telemetry + report
helper source and Python provider identity, so changed producer code cannot reuse
an older cached Run success. Review producer qualified independent-root source
closures/configuration pin; never auto-refresh qualification.

Existing root per-request sidecar attachment works unchanged: proxy writes
`<action>.member.<index>.json` in MYLANG_TEST_TELEMETRY_DIR. Normal builds with no
sidecar dir preserve the verdict; reused steps create no fresh measurement.

## Guest supported inventory and unavailable timing

`verification_report.guest_test_timings(path, action_id=..., member=INTEGER)`
reads strict bounded native-tests-v1 JSON. It retains exact qualified test IDs,
all five native states (cached→reused), and checks declared terminal counts.
All elapsed_ns fields are null, elapsed_scope/timing_coverage/execution timing
coverage are unknown. Property ordinal counts and preparation work never stand
in for individual clocks. Setup-error placeholder rows lacking qualified test
IDs are unknown, rather than fabricated tests. Arbitrary plain-text diagnostic
strings are never parsed as test inventory.

Root approved this adapter in existing independent guest matrix --json reporting
through S06/S10. Existing gate text output stays unchanged; JSON log path, actual
producer/compiler hash, action_key/context/run provenance remain caller-owned.

## Concrete guest runtime ownership request (not implemented)

The plain runner currently batches several tests into one executable invocation;
Shared.trials wall time cannot be copied to each individual test. The current
runtime response contains no trial clocks. Joint memory/runtime/bootstrap owners
must agree on an additive authenticated contract before changes:

1. src/core/runtime/core_test.c: capture parent monotonic fork→wait interval for
   each actual selected trial, including fresh capability/process/cleanup work;
   expose optional association with actual response row. Do not change any memory,
   lifetime, timeout, fork, leak or isolated-test behavior. Missing/trapped/unanswered
   rows remain nullable, not pass-complete. Keep normal verdict protocol or version
   an extension with conservative fallback for old seeds.
2. src/core/property_execute.zig: decode that explicit trial association, preserving
   answer-prefix/crash/retry semantics and disjoint fork→wait scope. A rerun-alone
   needs its own observation; batch aggregate is never divided among members.
3. src/core/test_runner_execute.zig, test_runner_report.zig and directory.zig:
   propagate nullable structured observation into native-tests report and directory
   JSON. Verdict currently already has seven fields: group new diagnostic data
   under a reviewed nested structure instead of exceeding Guardian limits. Existing
   Cache has six fields and may admit one optional observation bundle if owners
   preserve action identities and receipt semantics. Cached/whole-report replay
   must discard historic time from fresh observations.
4. Property campaign timing has its own whole-case search/process/shrink scope,
   distinct from plain trial process and property ordinal work. Preserve provenance,
   indexed campaign eligibility, seed authentication and output/fact/leak assertions.
5. Add runtime protocol/ABI/input invalidation, no-cache/force/reuse/isolate parity,
   skip/fail/crash/timeout/partial/property tests and supported report bounds.

Core runtime remains memory-team-owned. No guest/Guardian implementation file was
edited by S01. Guest individual timing acceptance remains open until that owner
supplies and qualifies the producer; the inventory adapter does not close it.

Central adoption approved by coordinator: prefix the proxy around original argv
for reachable native Run steps whose test_runner_mode is already true, during
registry export. Preserve the entire original argv/producer/stdio/name/filters/
sideeffects and use the exported **reachable member index** (not raw registration
index when unreachable whole-root runs precede shards). Existing withTools
exec-shell forwards Maker's appended listen flag to the original artifact.
Group root ID is stable if the group owns one binary root; include stable artifact
qualification if a group spans different roots. Preserve native inherited
side-channel descriptors: proxy Popen explicitly uses close_fds=False so the
original runner retains ZIG_PROGRESS and any existing inherited capability.
