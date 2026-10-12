# Development-loop wave 2 ownership and qualification ledger

User authorization: execute the next ten-item wave; subsequently adopt the
memory team's existing native-link fix (`632726724`). Coordinator plus ten
workers used separate branches/worktrees. No nested subteams, push or main update.

## Source and evidence freezes

- B0: `c1857310e0bf623545380c8de24515f1b9970021`; its tested production source
  was `a9a3208a4f3edbf17170cfc18d57f5f999af49c3`.
- Startup fetch: local main and origin/development both
  `fbfcaa7a923186a8e773c3760f81c10aa345a432`. Published origin/main is a separate
  lineage and was not merged.
- Integration branch: `codex/dl-wave2-20261012-integration`, worktree
  `/home/epentland/ai/canopy/mylang-dl-wave2-20261012-integration`.
- Intermediate production freeze: `5e6180689b5b837aa60bd5a43f60b0981c58b638`.
  Its compiler `abc4663e...` and historical uncacheable-host measurements remain
  distinct from the final candidate.
- Compiler source freeze: `9d1b51f310477e4ceccffd8ad41ecf6fc2156e13`; final
  Debug compiler `cc827c4e79243f299dc92327fa86049669307d1f0edfa816a5b641dc443176b0`.
  Final qualification source: `1eea987411a1ac5b42941b2ad26a25052a002460`,
  adding only the telemetry fixture isolation fix. Full forced verification at `9d1b51f3`
  passed 46 groups / 106 members; final selective requalification passed with
  33 reused / 13 executed, stable inputs and only the two declared dependent
  action keys changed.
  All captures finished before evidence-only integration, which does not alter
  the tested production source.

See [REPORT.md](REPORT.md) for acceptance and exact measurement scopes. Old
candidate trees, compiler bundles and raw failures remain preserved.

## Exclusive ownership and final disposition

Coordinator owns build registration, existing test-root imports, SPEC/Guardian
configuration, verification/session integration and tests, pins, inventory,
documentation and this ledger. Workers own their uniquely named helpers/tests
and `Sxx/` evidence; only the coordinator integrates commits. Completed claims
remain assigned unless explicitly transferred.

| Session | Source claim | Integrated work / evidence | Remaining requirement |
| --- | --- | --- | --- |
| S01 | verification_report.py/tests; new telemetry helpers | Native runner collector, labels, `8c6823d3a` fixture isolation and `8043fdffe` audit; native timing restored | Unsupported guest/driver observations remain unknown |
| S02 | verification_process.py/tests; lifecycle harness | `32faf6077`, `264fa127d`, `517a4c569`; 35 focused tests and eight-case bounded matrix | Native full-inventory shared-subscriber continuation |
| S03 | unique measurement harness; golden helper only with proof | `e20931e37`, `604de6bcc`, `52dc2fbb7`, `d40cddce5`; scalar tradeoff and two matched golden pairs | Fully cold golden tier unmeasured; no further split proposed |
| S04 | verification_snapshot.py/tests excluding loaded-code integration | `d9c40d162`, live revalidation actors and planning pairs; host/config consumer review | Five final whole-loop observations recorded by S10; broad latency remains open |
| S05 | verification_profiles.py/tests, fuzz/Juice adapters and qualification helper | `6031bf862`, `9d93b8c4a`, `005dd40f9`, `b106c6366`; bounded actual adapters | Full long-qualification wall-clock, driver and bootstrap obligations |
| S06 | unique live matrix harness and fixtures | `ded9adef1`; 17 native and 20 repaired guest cases in recorded contexts | Final complete edit matrix and native guest receipt reuse |
| S07 | verification_budgets.py/tests and verification_policy.py/tests | `a95c01122`; compatible-cohort calibration and headroom | Remains report-only pending calibrated evidence |
| S08 | verification_code_identity.py/tests and source authentication API | `b44a9241f`, `f2976df`, `a8ff1bb01`; 24 helper and seven caller regressions | Five compatible complete requests passed with identical action keys across modes |
| S09 | bridge/seed evidence, exact owner patch proposals | `8634ec91d`, `f71e3bd33`, `67d24256a`; repaired qualified seed adopted by coordinator | Full DL7 compiler port and strict performance policy |
| S10 | qualification harness, timing schedule and acceptance evidence | `40afe4e7b`, `2a9a3dee3`, `2fe140b45`; full/requalification, five compatible repeats and final helper40 passed | Full ordinary-edit matrix, stable population tails and strict port ratios unqualified |

SHAs in the table identify worker deliverables; integration cherry-picks have
their own SHAs in Git. Coordinator commit `5e6180689` contains shared wiring and
small reviewed patches while preserving overlapping canonical-identity edits.

All ten sessions completed their assigned wave deliverables and committed their
evidence. The 40 final helper edits observed median 365.503 ms and empirical p95
425.486 ms; the five unchanged complete windows took 47.72–56.50 seconds. Final
source remains explicitly `1eea9874`; later commits only archive evidence and
update this report/ledger. Both broader roadmap milestones remain open.

## Joint owner decisions

Memory ownership remains with its active workstream: A07 ABI, A08 caches, A09
timing and A10 rollout. The memory checkout and active bootstrap checkout were
read-only to this wave. The bootstrap snapshot remains
`dff9304b9cd7bc72e66f9feb20f1b05281d67333`; it does not qualify full port acceptance.

The user approved the exact memory-owner native-link repair. Both current native
regressions pass. The same approved cleanup delta was separately qualified on
the immutable historical seed as `1665d74029c406dd5b90807186a752ebac6bcbb8`.
Coordinator adopted that pin and preserved the exact object as a merge parent
in `02975797051dae5bfb2306ddc439f18af86bd6e8`, without replacing current source
with historical APIs. Forty fact/leak tests, four protocol oracles, two seed
native regressions, reproducibility and five rejection controls passed.

Coordinator also explicitly reviewed and adopted the memory owner's current-host
qualification `a9dc0edfe640b98a0869330fe6a19d21b6bbc255`: one loader-cache digest
plus its evidence comment. The unrelated owner test rename was excluded.
Meaningful current tests reject substitution of every declared runtime input.
Unknown-host fallback, runtime/ABI, default mode and tool pin remain unchanged.

Neither platform source nor seed JSON is part of the actual 212-file CONFIG
projection. S04 verified their preparation and producer/action invalidation;
the reviewed pin remains
`4493db3a525705b6f1222c50796175cdff55b2301d5160e8d02297d43942885e`.
No automatic repin occurred.

S09 transferred exclusive use of
`/home/epentland/ai/canopy/mylang-dl-wave2-20261012-S09/.tmp/S09-native-component-cache`
to the coordinator through supported `MYLANG_COMPONENT_CACHE`. Keep the exact
root for this frozen identity; no mutable seed Zig cache was moved or shared.
S09 stopped all jobs before handoff. The old seed remains intact.

## Operational and evidence boundaries

Use the repository-pinned Zig, worktree-local Zig cache/on-disk TMPDIR and shared
global cache. Significant work follows shared build/gate admission; direct
verification owns its own admission. S10 schedules exclusive bounded timing.
The external dev-env changed at 02:10:41 UTC to build3/gate2/jobs4; this wave did
not raise slot limits. Captures retain actual environment and CPU affinity.

Receipts use namespace/version 2, reports schema 1 and versioned action domains.
Canonical actual-loaded code is authenticated against watched sources. Failed,
interrupted, late-unstable or expired-window work cannot publish reusable success;
new receipts are revoked even after a late qualification/publication failure.

Only the coordinator launches the integrated complete gate. Candidates remain
frozen through all captures; no evidence cherry-picks change HEAD mid-run.
Required work is never dropped to meet latency targets. Timeout exceptions are
bounded qualification controls, not inferred production policy.

All normal hooks ran. No Guardian FEEDBACK changes, shared-cache clearing,
unrelated process cancellation, main update or push occurred. S03 canceled only
its own obsolete fallback runs on coordinator request and deleted only completed
private cold caches, preserving raw evidence and frozen artifacts.

The full ordinary-edit target, calibrated hard policies, unsupported timing,
remaining long qualification and self-hosting median/p95 acceptance remain
explicit in the report. This ledger does not mark either entire roadmap complete.

## Telemetry cache follow-up

User-authorized investigation with coordinator, S01 and S10 confirmed that the
random developer telemetry path invalidated native guest receipts. Source
`fe7637e82f58430573d99473e5389a4369bbba7e` moves the owned diagnostic channel
out of `MYLANG_` without changing compiler code or receipt rules. Complete
verification passed all 46 groups; two unchanged requests each reused 3,616 guest
results and executed the required 1,796, with gate occupancy 23.02/27.84 seconds.
The inventory and compiler binary are unchanged. These two observations do not
qualify p95 or close the remaining ordinary-edit/self-hosting milestones.
See [the investigation](../telemetry-cache-invalidation-20261012/REPORT.md).
