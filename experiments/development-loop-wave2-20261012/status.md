# Development-loop wave 2 ownership and qualification ledger

User authorized the next ten-item wave after reviewing the prior closeout.
Base B0: `c1857310e0bf623545380c8de24515f1b9970021` (tested source
`a9a3208a4f3edbf17170cfc18d57f5f999af49c3`; later changes are evidence only).
Fetched local main and origin/development still equal
`fbfcaa7a923186a8e773c3760f81c10aa345a432`. Published origin/main is separate.
Integration: `codex/dl-wave2-20261012-integration`; no main update or push.
Prior candidate and its pinned compilers remain frozen, read-only baselines.

## Operating contract

Read CLAUDE.md, prior REPORT.md and S10/final-matrix.md, and the DL roadmap.
Each Sxx owns its new `mylang-dl-wave2-20261012-Sxx` worktree at B0 and its
`experiments/development-loop-wave2-20261012/Sxx/` evidence directory. Do not
modify old worktrees. No nested workers. Commit fixed changes with normal hooks;
only the coordinator cherry-picks. Do not push, merge main, or change peers.

Source `/home/epentland/.config/mylang/dev-env.sh` from your worktree. Use the
pinned Zig, private local cache and on-disk TMPDIR; keep shared global cache and
admission unchanged. Significant native work uses build admission; S10 owns
the timing schedule and only the coordinator launches final complete gates.
No redundant full gates. Ask S10 before timing; never nest timing in build/gate.
Disk is shared and limited: avoid unnecessary full compiler builds and preserve
pinned artifacts. No clearing shared caches or stopping other teams' processes.
No Guardian FEEDBACK entries. No weaker cache authority, skipped required tests,
automatic configuration-pin refresh, uncalibrated hard policies or false speed claims.

Coordinator alone owns shared build files, SPEC.md, guardian.toml, existing root
imports, verify_cache.py/tests, cache_session.py/tests, configuration pins, docs,
and final inventory/CLI integration. Send small patches with caller contracts and
tests. Compiler driver/guest runner/test receipt/runtime/ABI and bootstrap edits
require an explicit coordinator ownership decision. Guardian implementation is
outside this wave. Memory team is active at 3cc4953b0a2be79fd9c91a6c1ba8e7dc11aa0526;
A07 owns ABI, A08 caches, A09 timings, A10 rollout. Its checkout is dirty and not ours.
Bootstrap remains dff9304b9cd7bc72e66f9feb20f1b05281d67333; do not take over its checkout.

## Assignments

| Session | Next-wave responsibility | Exclusive source scope | Status / evidence |
| --- | --- | --- | --- |
| S01 | Native/guest telemetry contract and adopted supported collectors | verification_report.py/tests; new telemetry helpers | Starting; runner changes require ownership review |
| S02 | Live concurrent requests, subscriber cancellation and cleanup | verification_process.py/tests; unique lifecycle harness | Starting; existing claims remain authoritative |
| S03 | Independent native root and golden cold/warm/RSS tradeoffs | unique measurement harness; test/golden_parity.zig only if justified | Starting; timing scheduled with S10 |
| S04 | Measure/reduce warm validation and fresh-action overhead | verification_snapshot.py/tests except loaded-code identity integration | Starting; no cross-snapshot stat shortcuts |
| S05 | Authenticated long-qualification orchestration and real counters | verification_profiles.py/tests, fuzz_campaign.py, juice_cache.py adapters; new qualification helper | Starting; common dispatch via coordinator |
| S06 | Live edits, invalidation, revert and compatible second-worktree matrix | unique live matrix harness and fixtures | Starting; no shared production-cache mutation |
| S07 | Calibrated action budgets and explicit headroom evidence | verification_budgets.py/tests, verification_policy.py/tests | Starting; enforcement only after qualified evidence |
| S08 | Canonical actual-loaded-code identity and startup invalidation | new verification_code_identity.py/tests | Starting; existing consumer patches via coordinator |
| S09 | Refreshed bootstrap/memory ownership and qualified stage adoption | unique bridge/integration fixtures and evidence | Starting; port checkout read-only |
| S10 | Controlled baseline/edit latency, timing schedule and independent acceptance | unique qualification harness and evidence | Starting; owns timing schedule, no redundant full gate |

Each worker reports exact claims, contracts, dependencies, commits, raw commands,
source/tool/cache conditions, and passed/failed/not-qualified outcomes. All ten
assignments progress concurrently; native execution respects machine admission.
Final source candidate is frozen before complete verification and measurement.
Ordinary-edit 5-second feedback / 15-second p95 and self-host 1.5x median/p95
remain targets requiring actual evidence; prior operational samples do not qualify them.

## Integration progress (source candidate not yet frozen)

Worker source commits adopted: S01 c6a107d0c/1eb747d6e; S02 32faf6077;
S04 d9c40d162 plus planning/evidence commits; S05 6031bf862/9d93b8c4a;
S07 a95c01122; S08 b44a9241f; S09 8634ec91d/f71e3bd33; S10 40afe4e7b.
Original SHAs identify worker deliverables; integration cherry-picks have distinct
SHAs recorded by git. S03/S06/live lifecycle and final timing evidence remain active.

Coordinator wiring currently adopts native runner-protocol telemetry, reachable
member labels, selected snapshot records, deferred redundant tool validation,
parent-death cleanup, canonical loaded-code identities, authenticated bounded long
qualification, and exclusive request measurement with receipt rollback.
Verification receipts move to version/directory 2; report schema remains 1.
Deterministic fuzz seed derivation remains unchanged; only action domains migrate.

Focused integration checks so far: 37/37 real native scalar/tooling tests; native
sidecars exact selected inventories; 78 coordinator adversarial tests; 15 retained
session tests; 40 fuzz adapter tests; 42 Juice adapter tests; 11 measurement tests;
11 long-qualification and 13 profile tests. Late holder loss now overwrites any
prior success report and revokes newly published receipts. Meaningful changes
since a focused run require the relevant checks again. This is not a complete gate.
Input coverage currently passes. Final config consumer review is active with S04;
no pin has been auto-refreshed.

S10's isolated 40+40 guest source-edit cohorts passed real frontend checks, with
first-check empirical p95 86.255ms and 145.967ms. These are partial semantic
feedback on the frozen prior compiler, not native test or complete-gate acceptance.

The host loader-cache identity changed. The compiler correctly refuses native
cache approval, exposing pre-existing deletion of uncached object files before
linking. Owner commit 632726724 already fixes it. S09's exact reviewed three-file
adoption patch is committed but unapplied. A joint-ownership approval question is
pending with the user, as required by the original handoff. No trust pin changes.
Native guest completion, matched golden comparisons and final complete candidate
qualification remain blocked on that independent repair/decision.

S05 has exclusive ownership of juice_evidence.py and tests/test_juice_evidence.py
for a newly observed executable-size adapter gap. Executables need a separate
bounded allowance; raw file, aggregate evidence and shared blob-store bounds stay
unchanged. Coordinator preserves the canonical loaded-code edit during integration.

## Approved owner repair

The user explicitly approved “Adopt the existing fix” for memory owner commit
632726724. Coordinator applied S09's reviewed exact driver delta, unchanged A01
regression and current-root import. Source ownership remains with the memory
team; its checkout is untouched. Tool approval/ABI/default memory mode unchanged.
This supersedes the pending adoption authorization above. Candidate checks follow.

Additional integration: S05 artifact adapter patch 005dd40f96128d7d8c38de944c825d7c50876a5c
applied exactly via git show/git apply to preserve coordinator-owned edits in the
same files. Executable-only validation supports256MiB; raw64MiB, aggregate1GiB and
shared blob64MiB remain. Oversized executables produce fresh-only observations,
never expanded reusable-store authority. Raw31 tests pass. S08 authentication API
f2976df integrated (24 tests pass); common caller authentication is being finalized.
Native process helper now preserves both supported flat and scripts.package import
forms; all35 process tests pass after the migration correction.

Current shared dev-env was changed externally at02:10:41 UTC to build3/gate2/jobs4.
No session command edited it or increased a slot limit. Captures record their actual
environment; timing still owns the same shared namespace and excludes cooperating
build/gate holders. Older admission declarations are not pooled silently.
