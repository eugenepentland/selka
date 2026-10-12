# S05 handoff

## Fixed implementation and ownership

- C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
- Implementation/evidence: `6547c8b874000f8727ebbb17ae7d40edb7ce90dc`.
- Branch/worktree: `codex/dl-closeout-20261012-S05`,
  `/home/epentland/ai/canopy/mylang-dl-closeout-20261012-S05`.
- Owned code: `scripts/verification_profiles.py`, its tests,
  `scripts/development_loop_workloads_test.py`, `scripts/fuzz_campaign.py`,
  `scripts/fuzz_campaign_test.py`, `scripts/juice_cache.py`,
  `scripts/juice_cache_test.py`, and this S05 experiment directory.
- Shared files untouched. Exact C0-context requests are
  `coordinator-profile.patch` (`verify_cache.py`, guarded `cache_session.py`
  import) and `build-registration.patch` (`build.zig`, `build_test_inputs.zig`).
  Both passed `git apply --check` on C0. Root adapts around S01/S02/S04 wiring.

## Behavior and dependencies

`CONTRACT.md` describes `verification-profile-v1` and the complete API.
`quick|complete|long-qualification`, default complete, consumes the existing exact
inventory and live dependency/receipt decisions. Quick is always explicitly
partial; every required/deferred ID remains visible. Complete accounts for all
current groups through qualified reuse or successful stable execution. Shared
gate failure, skipped/explicit failed rows, missing/corrupt decisions, unstable
inputs, and filtered inventories cannot certify complete verification. Long keeps
the full gate and separates additional qualification obligations.

Both existing fuzz and Juice adapters now support optional `--max-actions`
(admitted missing actions only) and `--action-timeout` (explicit positive finite
admitted deadline excluding queues). Exhaustion reports partial and returns 3;
completed evidence survives and reuse consumes no cap. Fuzz names known pending
actions and unvisited targets. Juice names all pending selected workloads. The
explicit timeout enters existing action identities; request work caps do not.
Existing stores, leases, mutation/publication checks, fresh controls, threshold
reevaluation, and raw evidence validation remain in use.

S02 confirmed the existing `ProcessLimits` identity and cancellation contract.
S01 timing completeness remains separate from gate completeness. S04 confirmed
that fuzz/Juice compiler consumers still require broad producer/provider closure;
no independent checker boundary is qualified. No advisory budget enforcement or
default deadline was introduced. Fresh-only representative compiler and forced
guest-test-driver workloads include exact completed-work/output oracles.

## Validation and evidence

`focused-checks.log` records commands/statuses and operational output.
`validation.json` records source/tool/artifact SHA-256s and mode/inventory data.
Focused checks passed: 13 profile, 3 workload oracle, 40 fuzz adapter, 42 Juice
adapter, 27 Juice raw-evidence tests: 125 total, every suite exit 0.
The normal Guardian pre-commit hook ran, exit 0: 88 checks passed; size/length/ABI
ratchet observations were report-only. Guardian feedback was not modified.

S10's real C0 inventory is archived as `C0-inventory.json`: 45 groups and 95
required/registered members, unknown actions empty; SHA-256
`a0fe8ff69c900552da9bf6b8ba662c9478915044e6d7c5f68a7d7cc7664b185c`.
`profile-matrix.json` contains twelve deterministic adapter scenarios: cold,
warm, narrow edit, broad semantic edit across all three profiles. Every scenario
uses that same exported inventory; copied one-shot/session decisions yield
identical schedules. This is adapter accounting, not real command execution.
Cold complete accounts for 45 selected actions, warm complete for 45 reused
decisions; quick cold remains partial with 42 outstanding at its three-action
bound. Native execution of those gate actions belongs to S10/root.

Actual Debug native smoke used S10's immutable C0 compiler SHA-256
`7755a47e1e3f3eae11073effa41f4716fa7a99c818a4d836b8965c549fd0b57f`.
Compiler check exited 0; forced guest driver exited 0; the complete-work oracle
exited 0. `driver-smoke.json` archives both freshly passed tests, zero cached,
failed, skipped, or unsupported tests. Native admission used the existing build
slots, private local cache and on-disk TMPDIR, shared global cache, pinned Zig
`0.17.0-dev.1683+5ceec001b`. The guest-driver admission observed a 35-second queue;
this is queue evidence, not latency qualification.

`generated-manifest-example.json` and `generated-suite-example.json` retain the
actual fresh-only generated workload contracts. RF manifest generation succeeded
using S10's frozen compiler SHA-256
`fef6fc25c6452099e2e2f443a706676b5c39c7a2546bcdf686b1b2507b79eb8f`.
Native callgrind planning exited 2 because `valgrind` is unavailable. No performance
capture, instruction-count result, isolated cold/warm/edit timing, or peak RSS is
claimed. Those fields remain unavailable/unqualified. Smoke scratch was archived
outside the worktree at `/tmp/dl-closeout-S05-preparation/native-smoke`; all
reviewable evidence is committed as text.

## Integration and outstanding acceptance

1. Cherry-pick the fixed implementation and this handoff commit. Adapt shared
   patches serially after S01/S02/S04. The profile patch already validates controls
   before preparation, preserves individual action evidence, reports partial
   status/remaining work, and guards the loaded profile module in sessions.
2. Root adds combined coordinator quick→complete, default complete, failure,
   filtered request, and JSONL transport tests. Existing session request args
   already forward profile/budget flags unchanged. Synthetic schedule parity alone
   does not close actual retained-session acceptance.
3. Apply build registration/input closure updates; re-export the final inventory
   and run `profile_matrix.py FINAL_INVENTORY` on it. C0's 45/95 counts are never
   assumed to be final. Re-audit the final configuration qualification pin.
4. Root/S10 own the required complete gate and formatting checks on the frozen
   integrated candidate; S05 did not launch a redundant full native gate.
5. Long qualification orchestration and authentication of fuzz/wall-clock results
   remain open. The requested long adapter currently reports these obligations
   explicitly and cannot manufacture qualification success. Native Juice workload
   capture/repeatability and report-only regression calibration need a qualified
   collector and S10's isolated measurement windows. Instruction counts cannot
   satisfy wall-clock/self-hosting ratios.
6. Five-second feedback and fifteen-second p95 targets are unqualified here.
   Quick's member-count/cost ranking is visibly heuristic; S10 should supply
   measured compatible cost hints and actual cold/warm/edited request evidence.
   No recurring jobs, external publishing, main merges, or rollout changes were
   performed. DL7 compiler/bootstrap readiness remains separately owned.
