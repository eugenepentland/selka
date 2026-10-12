# S01 advisory telemetry contract v1

This extends reports, never cache authorization. Existing dependency summaries
remain v1. Test telemetry is a separate strict UTF-8 JSON document, at most 2 MiB:

```json
{"version":1,"producer":"python-unittest-v1","action_id":"verification-cache","member_id":"verification-cache/member/0","selected":1,"complete":true,"tests":[{"test_id":"verification_report_test.Reports.test_precise_changes","state":"passed","elapsed_ns":123}]}
```

`member_id` is inventory action ID plus `/member/` plus registered member index.
A test ID is the producer's qualified root/module/case name. Renaming/re-registering
an action/member changes its identity; source identity remains the action key,
not a display name. Native producers must include root qualification and avoid
shard IDs in the underlying test ID. Never infer test IDs from slow-test rows.

States: passed, failed, skipped, reused. Elapsed is a nonnegative monotonic integer
nanosecond interval, or null; skip/reuse must be null. The unittest interval starts
before setup and ends after teardown. Class/module setup outside those callbacks
is outside the per-test interval and remains part of action time. Subtests belong
to the parent test ID. Selected count comes from the actual loaded suite, not from
how many success messages happened to appear. Fail-fast/class setup failures can
leave selected cases without a record: report completeness becomes false.

`verification_report.test_timings(path, action_id=..., member=...)` returns strict
detached data, selected/executed/reused/skipped/timed counts, `complete`,
`timing_coverage` for **selected** tests and `execution_timing_coverage` for executed
tests. Reuse or skips do not fabricate elapsed measurements. Missing/malformed,
duplicate-ID/key, wrong-version/identity or excessive output is unknown. Partial
records remain visibly partial even if the producer incorrectly says complete.
At most 16,384 rows and 512 characters per identity are accepted. No selected
count of zero is inferred from absent data. Telemetry completeness is unrelated
to complete verification coverage or a test verdict.

`process` optionally holds runner-process user/system CPU seconds and Linux
process lifetime high-water RSS bytes. CPU deltas cover the suite in the runner
process, excluding child CPU; RSS covers the entire process lifetime and is not a
delta. Aggregate concurrent peak RSS is null. Invalid process observations become
unknown without discarding otherwise valid test results. `phase_spans` accepts
explicit monotonic `{phase,start_ns,end_ns}` intervals. Nested intervals are
non-additive; boundaries in different processes require a documented clock scope.

Supported producer:

```bash
python3 scripts/verification_telemetry.py --action-id report-python --member 0 \
  --output .tmp/report-telemetry.json verification_report_test
```

The module arguments use unittest loading. It runs the same assertions, outputs,
and unittest verdict, then writes advisory output atomically. Output publication
failure does not change the verdict. It does not accept cache receipts or choose
which tests run. Existing script-specific CLI/setup must be preserved if the
coordinator adopts it; use the result/runner classes directly when module loading
would change script semantics.

Stability helper `stability_diagnostics(reasons, unknown=False,truncated=False)`:

```json
{"version":1,"status":"observed","reasons":[{"role":"publication","facet":"path","name":"fixture.my","reason":"watcher_event"}],"unknown":false,"truncated":false}
```

Facets path/host/authority/watch; name is a path or host-facet identifier, or null.
Providers choose precise reason strings, including watcher_event, metadata_changed,
missing_path_changed, authority_unavailable, watch_overflow, fork, reset, unknown.
64 records, 512 characters per string; omitted/malformed reasons remain unknown;
truncation remains visible. This helper only detaches observations: it does not
read inputs, poll watchers, hash files, clear dirty state or decide stability.
Byte-restored ABA remains dirty when the authority provider observes the event.
