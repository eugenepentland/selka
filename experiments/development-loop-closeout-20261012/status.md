# Development-loop closeout status — 2026-10-12

C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432` (local main = fetched origin/development).
Integration: `codex/dl-closeout-20261012-integration`, in the isolated
`/home/epentland/ai/canopy/mylang-dl-closeout-20261012-integration` worktree.
The original dirty checkouts and published origin/main lineage are preserved.
Publishing or updating main is outside this execution; this branch is the reviewable result.

Bootstrap: `codex/selka-bootstrap-20261011` at
`dff9304b9cd7bc72e66f9feb20f1b05281d67333`, inspected read-only.
Memory owner: `codex/memory-closeout-20261012`, ledger
`experiments/memory-closeout-20261012/ledger.json`; A07 owns ABI/ownership,
A08 cache scaling, A09 timing, A10 rollout. No ownership transfer received.
Direct owner communication was unavailable; S09 archives patch requests.
No memory mode, ABI, seed or compiler port was taken over.

Coordinator plus ten Sol 6.1 workers ran concurrently in private worktrees at C0.
All use the pinned Zig, private local caches and on-disk temporary directories,
shared global cache and shared admission. Native tests use build admission;
S10 owns complete gates and exclusive timing. No slot limits or shared caches were reset.
No Guardian feedback entries were written. Normal worker commits passed Guardian hooks.

The coordinator exclusively owns shared build/registration/input/inventory/CLI
files, verify_cache.py/tests, cache_session.py/tests, configuration pins, final
docs and this ledger. Shared patch requests were applied serially.

| Worker | Exclusive implementation scope | Integrated commits | Evidence and remaining dependency |
| --- | --- | --- | --- |
| S01 | verification_report, telemetry helper/tests | c7ee0f716, ce3e72c8c, 0b2daa25d, 10d88952e | Python selected-test telemetry, bounded malformed-output handling; native/guest timing hooks remain unknown. [Handoff](S01/handoff.md) |
| S02 | verification_budgets/process/policy and tests | 2da4d4f8f, 7466accc9 | Process-tree adversarial checks; policy remains report-only. Concurrent subscriber acceptance and calibrated enforcement open. [Handoff](S02/handoff.md) |
| S03 | text_scalar_root_test and exact existing scalar tests/oracles | 45f7676ef, c246edc13, 548508300 | Nine native tests pass; embedded semantic mutation fails. Root authored existing imports/build/Guardian changes. Paired cold/RSS cost open. [Handoff](S03/handoff.md) |
| S04 | verification_artifacts/producers and tests | 8fd2eb10e, a0b515753, 3ab3bb15c, 2b61af2d8, 82bf79ce5, ec4aed4e1 | Two independent roots adopted; actual lowercase Zig mode fixed. Coordinator/S04 final configuration review passed. [Review](S04/final-review.md) |
| S05 | profiles, fuzz_campaign, juice_cache and adapter tests | 88a7a46bb, 3223f2735 | Explicit quick partial status; bounded fuzz work; long profile lists outstanding external obligations. Long orchestration/counter qualification open. [Handoff](S05/handoff.md) |
| S06 | guest profiling/controls; discover candidate only after overlap review | b5919178a, f605f3bde | Eighteen mandatory cold/warm actions and eight controls pass; production indexing rejected, source and SPEC unchanged. [Profile](S06/PROFILE.md) |
| S07 | test/golden_parity.zig | 0713e4a8e | All 222 compiler checks retained, 165 distinct source preparations; mutable cwd remains per case. Full golden passes. Paired latency/RSS open. [Handoff](S07/handoff.md) |
| S08 | verification_snapshot and profiling helpers/tests | 05a9746e4, 79ec85e79, 7c5e326d6 | Bounded sticky invalidation reasons; 74 tests. Cross-snapshot stat memoization rejected. Warm validation savings not claimed. [Handoff](S08/handoff.md) |
| S09 | bootstrap matrix and uniquely named bridge fixtures | 4c4833b54, a1bd6bef7 | Schema11 refreshed, component support checks pass; no port edits. Real stages/seeds/bootstrap and strict performance acceptance open. [Handoff](S09/handoff.md) |
| S10 | frozen baseline/final harnesses, edit matrix and timing evidence | 9dce60867, e692f5fee | C0 and C1 complete gates pass; C1 two unchanged requests pass with 35/46 reused. [Acceptance](S10/acceptance-report.md) |

## Integrated contracts

The shared coordinator registers the new native root and Python suites, collects
request-specific telemetry, validates qualified producer source and artifact
metadata, and dispatches quick/complete/long-qualification profiles over one
inventory. Quick always reports partial status 3; missing long obligations cannot
become success. Advisory budget changes do not impose deadlines. Runtime source
watching covers dispatch helpers. Source mutation diagnostics persist even when
execution also fails, and exceptions replace stale success reports.

Producer fixture tests declare all copied source/oracle files and their own
build_test_inputs declaration dependency. Missing or incompatible producer data
retains whole-artifact identity; existing reviewed selectors are preserved.
Arbitrary configuration still invalidates broadly. The configuration pin is only
updated after S04's consumer audit, regression evidence and actual writer check;
it is never refreshed automatically.

## Candidate and acceptance

C0 baseline complete verification passed with stable inputs, 45 selected groups,
95 registered required members and no unknown members. Gate admission occupancy
was 1034.160 seconds; this is operational evidence, not isolated compiler timing.
Historical 34/45 reuse and 28–37 second warm figures are not current acceptance.

The coordinator and S04 explicitly qualified configuration pin `68663185…b655`
after the consumer audit, actual writer/caller checks and regression evidence.
Current exported inventory has 46 groups, 101 required/registered members and no
unknown members. Focused coordinator74/process33/session15 checks pass.

Frozen and tested C1: `a9a3208a4f3edbf17170cfc18d57f5f999af49c3`.
The full forced complete gate and formatting passed, followed by two unchanged
retained requests, all with stable inputs. The C1 normal commit hook separately
passed all 88 whole-tree Guardian checks. Source stayed frozen through final
Debug/ReleaseFast artifact preparation, pinning and qualification. Later commits
contain only closeout evidence and this ledger; C1 remains the tested source SHA.

| C1 request | Result | Groups executed / reused | Gate admission | Total coordinator elapsed |
| --- | --- | --- | --- | --- |
| Forced complete | Passed | 46 / 0 | 985.953 s | 1012.058 s |
| Unchanged 1 | Passed | 11 / 35 | 65.862 s | 73.310 s |
| Unchanged 2 | Passed | 11 / 35 | 91.618 s | 101.175 s |

Both unchanged requests performed zero file hashing and zero directory enumeration,
but still performed 175,816 metadata observations. These are operational samples,
not isolated latency or a stable p95. They do not establish the warm latency goal.
Per-test telemetry observed all 286 selected Python tests in 11 members; 90 other
members explicitly have unknown supported per-test timing.

C0 retained startup conservatively recomputed all groups and was canceled with
status143; its warm acceptance is absent. S08 demonstrated reference-sensitive
Python marshal serialization as a possible contributor to cross-process code
identity drift; the actual startup contributors remain unproven. The follow-up
requires canonical authentication of actual loaded code, not trusting current
source bytes or suppressing source guards. See [diagnosis](S08/code-digest-followup.md).

| Requirement | Current status | Concrete remaining work |
| --- | --- | --- |
| DL1 complete observability | Not fully qualified | Final inventory/report parity passed; obtain supported native and guest individual timing hooks from runner owners. |
| DL2 calibrated limits/cancellation | Partial implementation, acceptance open | Archive compatible headroom and concurrent subscriber lifecycle evidence before enforced action limits. |
| DL3 independent boundaries | Bounded checks passed; performance open | Native split, inventory and full gate passed; paired warm/cold/RSS tradeoff still required. |
| DL4 real qualified producer | Adopted checks passed; broader acceptance open | Reviewed pin, real writer/caller, semantic mutation and full gate passed; broader store/live compatible-worktree matrix remains open. |
| DL5 fresh execution cost | Partial implementation, target not qualified | Measure golden preparation end-to-end; obtain supported guest phase spans. Indexing and stat memo candidates rejected. |
| DL6 supported profiles/work budgets | Partial implementation | Quick/complete contracts and work caps pass focused checks; authenticated long qualification orchestration/counters remain open. |
| DL7 self-hosting integration | Open | Active port owner supplies qualified stage/ABI/seed milestones and full bootstrap/per-workload median and p95 at most 1.5× frozen Zig reference. |
| DL8 final correctness/performance | Complete correctness passed; performance open | Exact frozen complete gate and two retained requests passed; live one-shot/edit/cold matrix and latency/p95 targets remain unqualified. |

The development-loop milestone is not declared closed while required acceptance
remains open. The independent self-hosting milestone remains open. Useful checked
feedback within five seconds and fifteen-second p95 are targets, not watchdogs;
no hard policy is inferred from a few observations or an instruction-count proxy.
