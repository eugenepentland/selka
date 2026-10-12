# Development-loop wave 2 qualification report

Status: implementation integrated; final qualification in progress. Neither the
development-loop nor the self-hosting roadmap is complete.

Frozen implementation candidate:
`5e6180689b5b837aa60bd5a43f60b0981c58b638` on
`codex/dl-wave2-20261012-integration`. Base:
`c1857310e0bf623545380c8de24515f1b9970021`. Main and peer worktrees remain unchanged.
The coordinator and ten workers use separate worktrees and shared admission.
[Ownership and source ledger](status.md).

## Delivered behavior

| Assignment | Integrated result | Current qualification limit |
| --- | --- | --- |
| S01 observability | Supported native runner-protocol collection and stable reachable member identities; unknown observations remain explicit | Focused scalar/tooling 37 tests passed; final complete telemetry pending |
| S02 cancellation | Parent-death supervision through admission and owned process lineage; failed publication rolls back receipts | Real concurrent request and hard-kill matrix being finalized |
| S03 independent boundaries | Existing scalar boundary measured against broad root; golden source preparation preserves 222 executions | Warm/cold/RSS tradeoffs reported separately; repaired golden replay pending |
| S04 validation cost | Copy only selected snapshot records and omit one redundant tool scan, preserving outer authority checks | 40 paired planning observations show a scoped improvement; final whole-loop qualification pending |
| S05 profiles and work | Authenticated bounded long-qualification dispatch, actual fuzz/scaling/instruction observations, bounded large-executable validation | Wall-clock/bootstrap obligations and full long qualification remain open |
| S06 live edits | Real failure, edit, fixture-membership and revert matrix; separate repaired guest cohort | Final version 2 followup and remaining matrix rows pending |
| S07 budgets | Compatible-cohort calibration, named legacy exceptions and explicit validation headroom | Report-only; insufficient evidence for enforced policy |
| S08 loaded identity | Canonical actual-loaded-code identities plus authenticated source correspondence; versioned receipt domains | 24 helper and 7 real caller regressions passed; old namespaces remain separate |
| S09 ownership | User-approved exact memory-owner native-link repair; refreshed component/seed/ABI bridge | Historical bootstrap seed repair in private qualification; full compiler port remains open |
| S10 acceptance | Controlled semantic-edit cohorts, planning pairs and independent scope review | Complete candidate gate and native end-to-end latency pending |

## Evidence already passed

The frozen candidate's normal commit hook passed all 88 whole-tree Guardian checks.
Focused coordinator 88, retained session 15, process 35, measurement 12, fuzz 40,
Juice adapters 43, raw Juice evidence 31, canonical identity 24, qualification 11 and
profiles 13 checks passed. These are individual suite results, not an aggregate
full-gate count. Input coverage passes. The reviewed inventory contains 46 groups
and 106/106 required registered actions. Configuration projection was explicitly
qualified by S04 and the coordinator; it was not automatically repinned.

The repaired compiler built successfully. Both native driver cleanup regressions
passed, including multiunit object survival through linking and cleanup after
failure. Its source manifest matches 804 files at the frozen candidate; the binary
SHA256 is `abc4663ecc3356557a8238185005f79486343fe2ecde9258b82a266458781040`.
Previously qualified companion components are copied alongside it for focused
checks; their provenance does not establish current seed provisioning.

## Measurements and open acceptance

S10's earlier 40+40 semantic-edit observations had empirical first-check p95 values
86.255ms and145.967ms on the frozen previous compiler. Native completion is a
separate obligation. S04's 40 paired planning observations showed median
2.078s to 1.869s and empirical p95 4.876s to4.176s on frozen prior inputs with
reviewed namespace normalization. This is a planning-slice result, not a complete
verification latency or a final candidate comparison.

The registered native regression build and formatting target both stop at required
component preparation: the older authenticated bootstrap seed has the same
uncached-object deletion bug. The failed logs are retained. A private seed source
with the approved cleanup fix is being qualified; the active seed is unchanged.
The host loader-cache fingerprint also differs from the old reviewed pin. The
compiler correctly disables native reuse; adoption of the memory owner's later
host qualification is under review, not an automatic trust update.

Ordinary-edit useful feedback within 5 seconds, native completion p95 within 15
seconds, unchanged complete verification latency, final full-gate equivalence,
calibrated hard limits, and full self-hosting/bootstrap performance remain open
except where narrower evidence above explicitly applies. Every self-hosting
required workload still needs median and p95 at most 1.5 times the frozen Zig
reference. No partial component or instruction result substitutes for that gate.
