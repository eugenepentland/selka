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
| S01 | Native/guest telemetry contract and adopted supported collectors | verification_report.py/tests; new telemetry helpers | Integrated native runner protocol; guest native timing remains limited |
| S02 | Live concurrent requests, subscriber cancellation and cleanup | verification_process.py/tests; unique lifecycle harness | Live eight-case matrix in final qualification; existing claims preserved |
| S03 | Independent native root and golden cold/warm/RSS tradeoffs | unique measurement harness; test/golden_parity.zig only if justified | Warm and cold boundary costs measured; matched repaired golden replay active |
| S04 | Measure/reduce warm validation and fresh-action overhead | verification_snapshot.py/tests except loaded-code identity integration | Integrated detached selection and deferred redundant scan; final consumer audit passed |
| S05 | Authenticated long-qualification orchestration and real counters | verification_profiles.py/tests, fuzz_campaign.py, juice_cache.py adapters; new qualification helper | Integrated authenticated bounded orchestration; full long qualification remains open |
| S06 | Live edits, invalidation, revert and compatible second-worktree matrix | unique live matrix harness and fixtures | Live fail/revert/membership matrix active; final v2 followup pending |
| S07 | Calibrated action budgets and explicit headroom evidence | verification_budgets.py/tests, verification_policy.py/tests | Integrated report-only calibration; insufficient headroom for hard policy |
| S08 | Canonical actual-loaded-code identity and startup invalidation | new verification_code_identity.py/tests | Canonical identity and source authentication integrated; startup regressions passed |
| S09 | Refreshed bootstrap/memory ownership and qualified stage adoption | unique bridge/integration fixtures and evidence | Approved driver repair applied; private repaired seed qualification active |
| S10 | Controlled baseline/edit latency, timing schedule and independent acceptance | unique qualification harness and evidence | Partial cohorts and planning pairs passed; final complete candidate gate pending seed |

Each worker reports exact claims, contracts, dependencies, commits, raw commands,
source/tool/cache conditions, and passed/failed/not-qualified outcomes. All ten
assignments progress concurrently; native execution respects machine admission.
Final source candidate is frozen before complete verification and measurement.
Ordinary-edit 5-second feedback / 15-second p95 and self-host 1.5x median/p95
remain targets requiring actual evidence; prior operational samples do not qualify them.

## Integration progress (source candidate frozen)

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
sidecars exact selected inventories; 88 coordinator adversarial tests; 15 retained
session tests; 40 fuzz adapter tests; 43 Juice adapter tests; 12 measurement tests;
11 long-qualification and 13 profile tests. Late holder loss now overwrites any
prior success report and revokes newly published receipts. Meaningful changes
since a focused run require the relevant checks again. This is not a complete gate.
Input coverage passes. S04 and coordinator explicitly reviewed all configuration
consumers and qualified pin4493db3a525705b6f1222c50796175cdff55b2301d5160e8d02297d43942885e.
The fresh inventory contains46 groups and106/106 required registered actions.
No pin was auto-refreshed.

S10's isolated 40+40 guest source-edit cohorts passed real frontend checks, with
first-check empirical p95 86.255ms and 145.967ms. These are partial semantic
feedback on the frozen prior compiler, not native test or complete-gate acceptance.

The host loader-cache identity changed. The compiler correctly refuses native
cache approval, exposing pre-existing deletion of uncached object files before
linking. Owner commit 632726724 already fixes it. S09's exact reviewed three-file
adoption patch was approved by the user and applied. Both focused native
regressions pass on the repaired candidate. Main compiler compilation succeeded;
registered component preparation failed in the old immutable bootstrap seed with
the same deletion bug. The failure is preserved, not relabeled as a passing build.
S09 is qualifying an isolated replacement seed with the same owner cleanup delta;
active seed and tool trust pins remain unchanged.

S05 completed juice_evidence.py and tests/test_juice_evidence.py
for the observed executable-size adapter gap. Executables need a separate
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
f2976df integrated (24 tests pass); common caller authentication is integrated with7 real caller regressions passing.
Native process helper now preserves both supported flat and scripts.package import
forms; all35 process tests pass after the migration correction.

Current shared dev-env was changed externally at02:10:41 UTC to build3/gate2/jobs4.
No session command edited it or increased a slot limit. Captures record their actual
environment; timing still owns the same shared namespace and excludes cooperating
build/gate holders. Older admission declarations are not pooled silently.

## Frozen wave2 source and current qualification boundary

Source candidate: `5e6180689b5b837aa60bd5a43f60b0981c58b638`. Normal commit hook
passed88 Guardian checks. Repaired main compiler SHA256
`abc4663ecc3356557a8238185005f79486343fe2ecde9258b82a266458781040`;804 source
file hashes match the frozen candidate. The copied companion components retain
their prior provenance and do not qualify new seed provisioning. See coordinator/
repaired-compiler-manifest.json and native-driver-{registered-build,focused-tests}.log.
The direct selected native executable passed both required cleanup regressions.

Final complete verification, unchanged complete requests, native golden replay,
and final ordinary-edit native completion remain pending. Existing observed
semantic-feedback and planning-slice improvements are narrower claims. DL7 full
bootstrap and every required median/p95 ratio remain open. No main update or push.

## Explicit current-host qualification adoption

Coordinator reviewed the memory owner's committed runtime probes, loader traces,
S04's independent current six-file comparison, and positive/negative production
approval checks. The owner-authored hash update in `a9dc0edfe640b98a0869330fe6a19d21b6bbc255`
is explicitly adopted on this isolated integration branch: only the reviewed
`/etc/ld.so.cache` fingerprint and evidence comment change. The unrelated owner
test rename is excluded. The evidence comment names the adopted committed package.
No runtime/ABI, default memory mode, discovery policy, or unknown-host fallback
changes. This is a reviewed owner qualification, not an automatic pin refresh.
Focused production runtime identity checks remain required on the new candidate.

Neither this platform source nor the proposed seed JSON belongs to the actual
212-file CONFIG projection. S04 independently verified their preparation,
compiler/component producer and action-input invalidation paths. The explicitly
qualified declarative CONFIG fingerprint remains unchanged; no repin is needed.
The repaired5e618 artifact and all earlier measurements retain their original
uncacheable-native context. A new source/artifact candidate will be frozen for
final verification; previous successful measurements are not relabeled.

## Qualified historical seed adoption

The same user-approved owner cleanup fix is backported to the original immutable
seed source, with only its adapted regression and root import. S09 qualified exact
commit `1665d74029c406dd5b90807186a752ebac6bcbb8`, archive SHA256
`2632c3ddd2992a989a08e1a070288901c58391eade2e330af5fb14f291d063d5`.
The coordinator explicitly adopts that reviewed seed pin on this isolated branch.
No seed mode, ABI, Zig version, trust policy or build recipe changes. Normal seed
source and binary authentication remain mandatory. No existing seed is overwritten.

Private evidence passes: 40 component tests in debug and release with fact/leak
checks; four protocol/property/hostile-frame oracles; two native cleanup tests
under current admission; both component binaries reproduce with --uncached;
five bad/missing/malformed/recipe/archive controls reject. S09 rehashed all 621
seed source records and the seed/component artifact chains before handoff.

S09 transferred exclusive use of its qualified component cache at the existing
absolute path via supported MYLANG_COMPONENT_CACHE. No mutable Zig cache is moved
or shared across compiler generations. The original seed and old measurements
remain immutable. The coordinator will retain exact seed1665d740 as a merge parent
so a future published full clone has the source object for normal git archive.
Shallow/source-only distributions still need the existing verified archive route.
This does not establish the full self-hosting compiler-port milestone.

The first host-adoption commit hook correctly required a same-change tagged test.
The existing approvedRuntime regression is strengthened to reject substitution
of each declared runtime input, including the loader cache, while preserving
positive actual-host, missing-input, preload and SourceChanged controls. This
adds meaningful coverage to the reviewed six-file contract; no production
approval algorithm changes. The failed hook is archived before retry.
