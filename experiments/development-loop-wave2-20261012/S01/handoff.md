# Wave2 S01 handoff

B0 c1857310e0bf623545380c8de24515f1b9970021.
Implementation c6a107d0c2a3de577ebad7cd21694af2e5a5bce8.
Own files: verification_report.py, verification_telemetry.py scope preservation,
new verification_native_telemetry.py/tests and verification_guest_telemetry.py/tests,
plus this S01 experiment directory. No old/peer/integration worktree edits,
Guardian implementation changes, guest/runtime edits, push or main merge.

Native observation uses the actual pinned Zig/Guardian test protocol; it forwards
wire bytes and stderr, matches test metadata to actual dispatched result IDs,
and measures test_started→test_results receipt intervals. The explicit
runner-protocol-interval clock includes reporting/transport; pure body duration
is unknown. Selection scope includes dispatched shard skips; skips get no timing.
Malformed/unsupported/truncated streams cannot fabricate a complete record.
SIGTERM/SIGINT propagate to the runner with bounded cleanup for noncooperation.
S07 consumes this through its separately qualified protocol policy clock.

Guest adapter retains exact supported native-tests-v1 JSON verdict inventories,
validates every terminal count, and reports timing unknown for all cases. Reuse
remains reuse; unsupported is distinct; property ordinals/preparation counters
cannot fabricate individual clocks. Root approved adoption in S06/S10's actual
independent JSON qualification path while preserving current gate text output.
Runtime source ownership prevents actual guest trial-clock implementation here.
contracts-and-patches.md specifies exact runtime/runner files and nullable scoped
observation requirements. This remains an explicit acceptance dependency.

Focused checks:

```bash
python3 -m unittest discover -s scripts -p 'verification*telemetry_test.py'
python3 -m unittest discover -s scripts -p 'verification_report_test.py'
source /home/epentland/.config/mylang/dev-env.sh
scripts/build-slot.sh build "$ZIG" test experiments/development-loop-wave2-20261012/S01/native-fixture.zig --test-runner /home/epentland/ai/canopy/guardian-zig/src/test_runner.zig --test-no-exec -femit-bin=.tmp/native-telemetry-fixture
scripts/build-slot.sh build python3 experiments/development-loop-wave2-20261012/S01/native_control.py
```

Python: 18 telemetry regressions plus 12 existing report regressions, exit0.
Raw output python-tests.log. Native fixture compile: exit0, shared build admission
FIFO394 (216s queue); private worktree Zig local cache/on-disk TMPDIR; shared Zig
global cache. No full compiler build/full gate/timing qualification launched.
Native paired-control outcome is recorded separately after its pending FIFO418
admission; native-control.log was initially committed while waiting, not as a
passed observation. Normal implementation commit hook passed 88 Guardian checks.
Tool pin 0.17.0-dev.1683+5ceec001b, Python3.14.4, Guardian source commit
 ae1ae2899cc60b575e9e1b9212d73eddf9e2df72. Native source/binary hashes are in
native-source-hashes.txt. No FEEDBACK.md edit.

Coordinator integration requires exact build argv/test-runner-mode changes and
input closures in contracts-and-patches.md; existing per-request sidecar read APIs
remain compatible. Explicit unknowns persist for unsupported members/receipts.
S01 does not claim DL1 complete based on helper fixtures: production adoption,
real pinned-runner equivalence and full candidate qualification are required.
No latency/p95/memory reduction is claimed; runtime clock ownership remains open.

## Actual pinned-runner follow-up

FIFO418 admitted after497s; native_control.py exited0. Direct and proxied commands
produced byte-identical protocol transcripts AND stderr, equal process status0,
and the same two qualified selected tests (one pass, one skip). The executed case
has a supported runner-protocol interval; skipped time is null. Selected timing
coverage is partial because skip is untimed; executed timing coverage is complete.
Native-observed.json carries the explicit selection scope. All raw direct/proxy
results, control log and native-equivalence.json are committed. These tiny-fixture
operational observations qualify protocol behavior, not p95 or a speed claim.

Review follow-ups preserve inherited original descriptors (including ZIG_PROGRESS),
with an actual inherited-FD regression; protect child stdin close from broken-pipe
errors; mark missing-version/metadata native observations unknown; and preserve
selection_scope through report parsing. Final focused tally is19 telemetry plus12
existing report tests, exit0. Existing Python producers now identify their
loaded-unittest-suite selection scope explicitly. Root approved central wrapping
of existing reachable native Run steps, using actual exported member indices.
That integration avoids duplicate execution and retains current install graphs.
