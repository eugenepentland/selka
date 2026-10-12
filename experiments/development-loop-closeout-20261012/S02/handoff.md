# S02 handoff: policy clocks and reliable cancellation

C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Implementation commit: `1b40c024b984332eef28451646f067b41d646165`.
Branch: `codex/dl-closeout-20261012-S02`. No main merge, push, peer edit,
Guardian implementation change, or FEEDBACK change was performed.

Owned production files: `scripts/verification_process.py`,
`scripts/verification_budgets.py`, new `scripts/verification_policy.py`.
Owned tests: `scripts/verification_process_test.py`, new
`scripts/verification_policy_test.py`. Evidence is restricted to this S02
experiment directory. The implementation commit includes the exact small
shared-file request [coordinator.patch](coordinator.patch), which the coordinator
must apply to `scripts/verify_cache.py`, `build.zig`, and
`build_test_inputs.zig`; these shared files were not edited here.

The patch exposes optional `--budget-policy PATH` in verification, passes it to
`execute`, and adds advisory `report.scoped_policy`. Invalid/unavailable policy
prints an advisory diagnostic while preserving the gate verdict and captures.
It registers the new focused policy driver and declares its source in affected
verification/fuzz/Juice test inputs. Policy data/module are excluded from common
execution identity. Actual implementation/CLI changes still require the normal
configuration qualification review; no fingerprint was refreshed automatically.

The lifecycle fix creates one isolated inner subreaper per admitted command.
Only its action descendants are frozen, killed and reaped. Preexisting admission
helpers and their later children remain owned by the outer launcher; this removes
the previous inherited-PID exclusion ambiguity. Signals are masked during fork
until the inner cancellation handler exists, preventing a cancelled startup from
launching work. Admission descriptors remain inherited. Detached/thread-owned
children, CPU loops, blocked children, leader exit, signal status, publication
interruption/retry, independent other sessions, pid reuse, log bounds, and cleanup
windows remain covered. This adds one supervisor process per admitted command;
its startup/RSS cost has not been isolated or qualified. Parent watchdog grace
must remain at least 0.5 seconds, preserving the preexisting supported contract.

The policy schema/API and clock meanings are in [schema.md](schema.md). Expected
cost, regression thresholds, deadlines, aggregate resident memory, and declared
completed work units remain independent. Scope clocks exclude queues and include
appropriate teardown/lineage cleanup. Advisory changes preserve compatible
captures; explicit ProcessLimits execution controls continue to affect identity.
All policy enforcement remains unavailable/unqualified, even with SHA references
to proposed headroom evidence. Legacy exceptions require a name, reason and review
point; no test is automatically renamed or exempted.

`verification_budgets.evaluate_scoped_policy(path, report, inventory)` consumes
explicit exact scoped observations and S01 validated member documents from
`actions[].test_telemetry` lists. A supported complete/fresh passed test contributes
its `elapsed_ns`; reused/skipped/failed/incomplete rows cannot calibrate execution.
Shared gate action/setup clocks and aggregate RSS remain unknown unless a supported
explicit observation supplies them. The adapter cannot authorize receipt reuse or
publication. S01's telemetry schema commit was communicated as
`277089d18`; this adapter consumes its documented contract without editing peer
files or requiring a cherry-pick into S02.

[Evidence and exact commands](evidence.txt) record hashes, environment, modes and
statuses. Final lifecycle source passed 133 focused verification unittest cases
under ordinary build admission (0 reused/partial); final work-unit policy changes
then passed 11 focused cases. These are focused checks, not the complete native
verification inventory or gate. `git diff --check` passed. Normal commit hooks ran
Guardian's whole-tree gate and passed 88 checks; raw output is
[implementation-commit.log](implementation-commit.log).

The first two broad attempts failed on fixture marker visibility races (new and
existing helper fixtures). Both now publish content atomically. Their raw failed
logs remain archived. A 132-case pass during active source edits is explicitly
unqualified in evidence.txt; the later 133-case pass tested the final lifecycle
source. Final policy validation has its own subsequent 11-case pass.

Required integration/follow-up:

1. Apply the shared-file request after integrating the fixed implementation SHA.
   S01 and root should populate `actions[].test_telemetry` as documented; missing
   data remains unknown. Add root-owned CLI regression proving malformed/missing
   advisory policy does not alter verdict/selection/identity, and threshold-only
   changes preserve saved compatible captures. No new timing gate is implied.
2. Root owns shared receipt/publication/session tests. Existing root regressions
   already cover interrupted publication rollback; the process fixture proves
   timeout cannot finish its staged success and a subsequent retry succeeds.
   Matching concurrent subscriber cancellation/coalescing acceptance remains open
   until root/S10 exercise the actual shared-store/session workflow. S02 preserves
   independently owned sessions and avoids introducing another scheduler.
3. S10 must run the exact integrated complete gate and isolated latency/memory
   matrix. Cold/warm/edit medians, p95, aggregate RSS, artifact overhead, and
   policy headroom evidence are unavailable/unqualified here. S10 has declared
   nearest-rank p95 with at least 40 samples for selected short loops; existing
   five-sample recommendations remain operational advisory evidence only.
4. Enforcement adapters for action/setup/test deadlines and memory/work ceilings
   remain open. Do not convert these advisory fields into automatic controls or
   label DL2's full headroom/subscriber acceptance complete. Explicit existing
   caller deadlines remain supported after admission.
5. Preserve external bootstrap/memory ownership, Zig pin, private local caches,
   shared global cache, admission policy, and configuration qualification review.
