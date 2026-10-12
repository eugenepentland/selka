# Coordinator patch requests

1. Register `scripts/verification_telemetry_test.py` in the existing
   `test-verification-cache` Python loop in build.zig. Add
   `scripts/verification_telemetry.py` and `scripts/verification_telemetry_test.py`
   to build_test_inputs.zig's verification_cache closure, plus the helper to any
   verification/session closure importing verification_report.py or the new
   diagnostics. Re-audit configuration projection; do not auto-update its pin.

2. Adopt an actual producer for Python unittest action members where module
   loading preserves current script semantics. The CLI in schema.md is supported;
   production routing is coordinator-owned. Keep action/member IDs attached to
   output paths; pass expected IDs to report.test_timings. Receipt reuse never
   generates new timings. This producer is demonstrated against the existing
   report suite, not yet automatically enabled for every registered Python driver.

3. Add an explicit test_telemetry unknown object to each action/member when no
   supported producer exists. Attach supported records separately from Zig summary
   observations. Preserve slow/summary logs as action-level advisory data only.
   All required inventory IDs can be represented with report.action_coverage;
   translate planned states execute/fresh into final executed only after status
   and publication checks, otherwise partial/failed/outstanding. No report API
   establishes verification success. Keep current action state schema intact.

4. Aggregate S08 Snapshot.stability_diagnostics(role=...) on failed checks.
   `verification_telemetry.stability_diagnostics` bounds/detaches its reason rows.
   Capture reasons before release; preserve the failing boolean and provider dirty
   state. No additional hashing/discovery/clear/retry comes from diagnostics.

5. Native Guardian runner upstream request (external owner): an opt-in structured
   sidecar with qualified root/test IDs, selected count, every selected final
   state, monotonic duration around actual selected execution, explicit skipped
   and reused states with null duration, and terminal completeness. Include shard
   selection and fail-fast/crash missing rows; do not emit only slow tests. A
   completed document uses schema.md, atomic output after terminal runner state;
   crash/partial document must never claim complete. No Guardian implementation
   changes were made in S01.

6. Guest runner request (joint root/bootstrap owner): expose the same per-test
   sidecar around trial execution, carrying actual test qualified names and
   debug/release/fact/leak modes through the existing action/member identity.
   Keep receipt reuse null-timed. Discovery/startup/frontend/native-build/link/
   execution boundaries must come from explicit runner events; S06 currently
   reports unsupported phases honestly. No guest runner files changed in S01.

Exact additive build argv for report module member3, after confirming the action
ID/member index in the final registered inventory:

```zig
verification_run.addArgs(&.{ "python3", "scripts/verification_telemetry.py", "--action-id", "verification-cache", "--member", "3", "--output-directory-env", "MYLANG_TEST_TELEMETRY_DIR", "verification_report_test" });
```

For the newly registered telemetry test use its actual inventory member index
and module `verification_telemetry_test`. The driver function currently derives
`verification-cache` from input-list `verification_cache`; review this ID rather
than using a new parallel group. Set the directory in the admitted live command
environment; do not use Step.Run.setEnvironmentVariable. Keep a per-request
fresh directory and attach validated sidecars only for that actual execution.
On each report action attach a list `test_telemetry`, one row per registered
member. Each row holds member_id and report.test_timings(path,action_id=group_id,
member=member_id); unsupported/absent/reused rows use report.test_timings() unknown.
Saved measurements may be historical descriptive data, never fresh observations.
