# Joint runner follow-up

C0: fbfcaa7a923186a8e773c3760f81c10aa345a432.

## Supported guest phase telemetry

`cache.work.nanoseconds` describes key planning, facts and lowering only. It does
not support a complete discovery/startup/frontend/native compile/link/execution
profile. `--explain-invalidation` is explicitly retired; use existing `--json`.
Do not derive per-test elapsed time from the existing per-root key-work totals.

Coordinator/S09-owned changes are needed in `src/core/test_runner.zig`,
`src/core/test_runner_directory.zig`, `src/core/test_runner_execute.zig`,
`src/core/test_runner_report.zig`, and the native build caller. Use S01's
versioned supported event contract and explicit nested phase spans. Capture
start-stop monotonic intervals through child teardown. Reused/skipped tests have
null fresh execution duration. A batched child duration must remain a batch
measurement until the child reports per-test timings. Distinguish exclusive
host work from concurrent/inclusive root intervals. Whole action wall time must
start before discovery and finish after report generation, with admission queue
time separate. Instrumentation must not change eligibility or receipts.

## Shared immutable discovery preparation

`discoverLoaded` passes a small root closure to discovery, while a directory
shared check may hold functions from all roots. An all-module synthetic indexing
improvement does not prove a gain for this common shape. A more relevant candidate
builds an immutable function/declaration lookup once on the shared checked
program, then answers each root's exact imported-module selection from it.
This crosses `test_runner_union.zig`, `test_runner_shared.zig`, main runner and
frontend lifetime ownership: S06 does not edit those files.

A caller contract must include the exact checked program and source mapping,
source/provider identities, duplicates/order semantics, and read-only lifetime
bound to the shared session. No persisted or cross-provider table is implied.
Verify headerless fallback, provider cases, missing imports/shared-load fallback,
synthetic-name occupancy, allocation failures, and the `MYLANG_TEST_CHILDREN=1`
differential oracle. Facts/leaks/force/no-cache and effects remain fresh under
current eligibility. Directory membership and source/tool mutation validation
must execute before acceptance/publication. Measure construction in the same
developer loop, and retain child process isolation/crash behavior.
