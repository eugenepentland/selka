# Read-only integration review

Reviewed coordinator integration scripts/verify_cache.py, build.zig,
build_test_inputs.zig and cache_session.py on 2026-10-12.

Confirmed registered Python verification_cache members use actual underscore
inventory ID and enumerated member indices. The collector remains opt-in on
ordinary builds. Caller-supplied telemetry directory is scrubbed before semantic
common environment capture; a fresh directory is passed only to admitted selected
gate commands. Directory allocation failure preserves selection/verdict. Reads
require exact action/member identities and occur before temporary directory
cleanup. Reused/unselected/unsupported members receive explicit unknown records;
no older sidecar is read. Registered driver modules have ordinary unittest main
entry points. Helpers/tests are in declared verification input closure. Profile
completeness is separate from telemetry coverage. No integration files edited.

Reported coordinator diagnostic gap: when the gate exits nonzero AND final
stability check fails, `inputs_stable` is false but the current report attaches
stability_diagnostics only for RETRY status. Recommendation: attach when
`not stable or status == RETRY`, preserving original failure status.

Found and fixed owned report defect: a bounded JSON document may contain a huge
integer CPU observation; math.isfinite raises OverflowError converting it to
float. Process observation parser now catches that exception and reports unknown
process data while preserving valid test rows. Adversarial test exercises direct
API and serialized supported-sidecar read with `10 ** 400` CPU seconds. Focused
collector suite: 10 tests, exit 0. No production gate or isolated timing run.
