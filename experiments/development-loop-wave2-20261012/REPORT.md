# Development-loop wave 2 qualification report

Status: wave 2 implementation and the bounded qualification recorded here are
complete. The broader development-loop roadmap and self-hosting compiler port
remain open for the requirements listed below.

Final qualification source: `1eea987411a1ac5b42941b2ad26a25052a002460` on
`codex/dl-wave2-20261012-integration`. Base B0:
`c1857310e0bf623545380c8de24515f1b9970021`. Later evidence-only commits do not
change the tested production source. We did not modify main or other teams' worktrees;
nothing was pushed. The coordinator and ten workers used isolated worktrees and
shared admission. [Ownership ledger](status.md).

## Delivered behavior and acceptance

| Session | Delivered result | Qualification and remaining scope |
| --- | --- | --- |
| S01 | Supported native runner-protocol telemetry, stable action/member/test identifiers and explicit unknown observations | All 106 member slots accounted for; fixture collision fixed and native unit timing regenerated; guest and standalone-driver timing remains limited |
| S02 | Parent-death supervision through admission, owned descendant cleanup and rollback of failed publication | 35 focused tests and eight bounded lifecycle cases passed across documented cohorts; native full-inventory concurrent subscriber continuation remains unqualified |
| S03 | Measured the existing independent scalar root and golden fixture preparation | 40 paired warm observations, two cold pairs and two matched golden pairs passed with tradeoffs below |
| S04 | Copies only selected snapshot records and removes one redundant immediate tool scan while retaining outer authority checks | 40 paired planning observations improved the measured slice; configuration consumers and actual dirty/revert rejection paths reviewed |
| S05 | Authenticated bounded long-qualification dispatch, real fuzz/scaling/instruction observations and bounded large-executable validation | Focused adapter tests passed; full wall-clock, driver and bootstrap qualification remains open |
| S06 | Live edits, failures, membership changes, reverts and compatible second-worktree checks | 17 native and 20 repaired guest cases passed their expected decisions in their recorded contexts; final full edit matrix remains unqualified |
| S07 | Compatible-cohort calibration with distinct clocks, headroom and named expensive-action exceptions | Report-only; available evidence does not authorize calibrated hard deadlines |
| S08 | Canonical identities of actually loaded code and authenticated correspondence to watched sources | 24 helper and seven actual-caller regressions passed; all 46 action keys match across five compatible one-shot/retained requests |
| S09 | User-approved memory-owner native-link fix, authenticated replacement historical seed and reviewed current-host qualification | Four current native checks, 40 component fact/leak tests, four protocol oracles, byte reproducibility and five rejection controls passed; full compiler bootstrap remains open |
| S10 | Frozen workload manifests, exclusive timing windows and independent complete-coverage validation | Forced complete gate, selective final requalification, five unchanged complete requests and 40 final helper edits passed within their stated scopes |

Verification receipts use namespace/version 2; the report schema remains 1.
Action identity contracts are versioned. The actual loaded helpers are bound into
verification, fuzz and Juice identities without changing deterministic fuzz seeds.
Admission capability, source authority and publication guards remain mandatory;
serialized success, an expired timing holder or a late stability failure cannot
authorize success. Ordinary builds and installed commands remain Python-free.

## Final candidate correctness

The final preparation and formatting run passed all 47 build steps. Formatting
checked 841 files, with 204 deliberate exclusions and zero failures. The exported
inventory accounts for all 106 required registered members in 46 action groups, with no
unknown or filtered inventory. Four final native tests passed, covering runtime
identity substitution, runtime-generation refresh and both native-link cleanup
regressions. Normal commit hooks passed all 88 Guardian checks.

The forced complete gate at `9d1b51f3` passed all 46 groups / 106 required
members with stable inputs and no outstanding work. Its exclusive request window
was 920.507 seconds after 25.116 seconds of admission queue; outer duration was
946.415 seconds. This was a complete current-inventory run, not a filtered gate.

Independent telemetry review exposed a fixture isolation defect during that run:
two nested fake-proxy tests inherited the gate's telemetry directory and
clobbered the real unit-shard-0 sidecar after its 134 tests passed. The report
correctly marked the lost timings unknown; assertion verdicts remained valid.
The old capture and damaged observation are retained. The final test-only fix
isolates every nested proxy and adds a regression that exercises all three
subprocess paths while preserving parent sidecar bytes and membership. All eight
focused tests passed. No production collector, compiler or configuration changed.
A separate admitted unit-root replay then passed all 1,532 tests and regenerated
the native timings. These are distinct runs, not summed wall time.

Complete requalification of `1eea9874` passed with 33 groups reused and 13
executed, no filtered or outstanding work, and stable inputs. The exclusive
request took 123.360 seconds after 85.215 seconds of queue. Independent key
comparison found exactly two changed actions: `verification_cache` and
`verification_session` (the latter declares all `scripts/`). The common budget
context and the other 44 action keys were identical. No config repin, artifact
rebuild or receipt deletion was used to arrange this result.

An attempted warm request from the independent S10 launcher was canceled when it selected all 46 groups. Hash-only comparison proved that its full normalized inherited environment differed solely in `CODEX_THREAD_ID`; reuse was correctly rejected. The selected environment fields in the initial capture were insufficient to prove complete equality. This archived, incomplete attempt supplies no warm latency or success sample. Compatible warm captures use the original root launcher context.

The original forced report accounts for all 106 telemetry member slots:
46 supported observations and 60 explicit unknowns, including the corrupted
unit member. It contains 3,121 measured executed cases (2,752 native and 369
Python), without summing nested durations as elapsed gate time. The subsequent
unit replay independently supplies 1,532 unique successful protocol intervals
across all 12 shards, restoring the missing 134. These protocol intervals are
not native test-body clocks. Unsupported guest/standalone driver timings and
aggregate concurrent memory remain unknown. The separate runs are not pooled
as a single timing sample.

The final Debug compiler SHA256 is
`cc827c4e79243f299dc92327fa86049669307d1f0edfa816a5b641dc443176b0`.
It was built at `9d1b51f3`; the final telemetry-test-only change leaves all its
producer inputs and bytes unchanged. Its frozen bundle manifest SHA256 is
`f11fb105af095c1c919ea41ad8db77e0eb328b8425f3f6892ba6f4dfb01ff467`.
Inventory SHA256:
`4b53118959cb27aa245ddb9ba1c8197b5029e85d591bf7eab8a16e53c60b1b23`.
The final bundle contains the compiler and authenticated current component
artifacts/manifests; it does not borrow historical companion provenance.

Focused suites also passed: coordinator 88, retained session 15, process 35,
measurement 12, fuzz 40, Juice adapters 43, raw Juice evidence 31, canonical
identity 24, qualification 11 and profiles 13. These are individual suite results,
not a summed full-gate test count. Input coverage passed.

## Measurements

All five compatible unchanged complete requests passed with stable inputs,
35 groups reused, 11 executed, all 106 required members represented and no
outstanding work. All 46 action keys and the budget context remained identical
across one-shot and retained transports. The retained session stopped cleanly.

| Transport / request | Admitted request window (s) | Admission queue (s) | Outer elapsed (s) |
| --- | ---: | ---: | ---: |
| One-shot 1 | 56.496 | 30.142 | 86.909 |
| One-shot 2 | 52.936 | 0.062 | 53.273 |
| One-shot 3 | 50.490 | 5.091 | 55.844 |
| Retained session, first request | 51.727 | 5.086 | 57.252 |
| Same retained session, second request | 47.720 | 0.083 | 47.831 |

One-shot requests and the first retained request each hashed 28,859 files /
2,328,979,767 bytes and enumerated 2,290 directories. The second retained request
hashed zero files/bytes, enumerated zero directories, reused six snapshots and
made 154,145 metadata observations. Steady one-shot and initial retained requests
made 594,173 metadata observations; the first one-shot made 738,564 while restoring
preparation after the incompatible-launch attempt described above.

Fresh gate execution occupied 41.333–43.800 seconds within these windows.
These nested durations are not added to request elapsed time. The 11 always-fresh
contracts cover component validation, input/environment discovery, SPEC history,
host/runtime collectors, compiler identity qualification, coverage membership,
guest/language effect eligibility and Guardian. Preserving those checks leaves
complete unchanged verification well above 15 seconds; this is not a measurement
of the narrower ordinary-edit target. Profile those fresh groups before proposing
further reductions, preserving their execution-time authority.

The forced primer and unchanged complete requests use one explicit 1800-second
after-admission measurement exception, justified by prior complete-gate costs.
This is a bounded qualification window, not a newly calibrated production hard
deadline. Queue time is recorded separately. One-shot and retained requests are
reported separately; their small sample counts cannot establish population p95.

The final compiler also completed one private-cache cold request and 40 distinct
imported-helper/public-test edits. Each revision passed a real semantic check and
exactly two forced fresh named tests: 82 tests total, 80 in the warm cohort, with
none failed, skipped or served from test receipts. Warm edit/check/test completion
median was **365.503 ms**, with nearest-rank empirical p95 **425.486 ms**.
First semantic feedback had empirical p95 81.629 ms and maximum 82.121 ms. The
single cold request took 3.062513 seconds. These observations meet the proposed
5-second feedback and 15-second completion targets for this named two-test
workload. They do not qualify all ordinary edits or a stable population p95.

That cohort used the final Debug compiler and verified all five frozen bundle
artifacts before and after execution, its own explicit S10 launcher environment,
private project/runtime caches and the warm shared Zig global cache. The
300-second timing window excluded its 5-second admission wait. Cumulative child
high-water RSS was 175,165,440 bytes; aggregate concurrent memory is unknown.
Native test cache reasons were `force`, distinct from the older uncacheable-host
cohort. No before/after speedup is inferred across these different host contexts.
See [S10 qualification](S10/qualification.md) and
[final edit records](S10/raw/final-helper-isolated/rows.jsonl).

Earlier, separately frozen measurements remain scoped to their own manifests:

| Workload | Observed result | Interpretation |
| --- | --- | --- |
| 40 paired planning requests | Median 2.078 to 1.869 seconds; empirical p95 4.876 to 4.176 seconds | Planning slice on prior frozen inputs with reviewed namespace normalization; not final whole-loop latency |
| 40 repaired guest edit requests | First-check empirical p95 82.052 ms; full narrow loop median 5.831 seconds, empirical p95 6.110 seconds | Real check plus two forced fresh tests per request; earlier `5e618068` compiler with uncacheable native-host context, not the final candidate |
| 40 paired scalar edits | Median 1.041 to 1.210 seconds; empirical p95 2.644 to 2.090 seconds | Median worsened while observed tail improved; no blanket speedup |
| Same scalar edits, supported whole-root PASS feedback | Median 0.544 to 0.524 seconds; empirical p95 1.109 to 1.002 seconds | Complete selected-root feedback, not first-test body timing |
| Same scalar edits, median maximum process RSS | 180,470 to 158,436 KiB | Per-process observation, not aggregate concurrent memory |
| Two cold whole-unit preparation pairs | 65.794/64.793 seconds and 64.838/64.451 seconds | Descriptive order-balanced pairs with fresh private local/global caches; tools and OS page cache excluded |

The scalar boundary adds 11.58% installed unit-artifact bytes; cold maximum
process RSS rises 4.06% and 3.28% in the two pairs. The existing single scalar boundary is retained for independent reuse and the
observed tail/RSS benefit. No further splitting was introduced or justified by
these samples; the median and cold costs remain explicit tradeoffs. Historical fallback golden runs were
canceled and retained as incomplete, not relabeled as successful or timed out.

The final matched golden comparison preserved all 222 compiler executions per
run, with zero mismatches across four runs. Two order-balanced C0/B0 pairs took
26.302/24.227 seconds and 26.116/24.288 seconds, descriptive reductions of 7–8%.
Source preparation writes fell from 222 to 165 and bytes from 90,182 to 66,752;
all 222 fresh mutable work directories remained. Maximum process RSS increased
from 163,408 to 169,912 KiB and from 169,876 to 170,020 KiB; the prepared test
artifact grew 55,061 bytes. Each sample used the same final compiler, a fresh
private runtime store and warm shared Zig global cache. Two pairs cannot establish
p95, fully cold performance or a compiler-generation improvement. See
[S03 golden evidence](S03/golden-final-report.md).

## Reviewed configuration, host and seed boundaries

S04 and the coordinator explicitly reviewed configuration consumers and qualified
the 212-file declarative projection at
`4493db3a525705b6f1222c50796175cdff55b2301d5160e8d02297d43942885e`.
The platform source and seed JSON are outside that CONFIG projection and remain
bound by preparation, compiler/component and relevant action identities. The pin
was not automatically refreshed after those changes.

The user approved adopting memory-owner commit `632726724`. Its exact driver
cleanup delta and regression were integrated without editing the memory team's
checkout. The historical seed had the same defect, so the approved delta was
backported and separately qualified as
`1665d74029c406dd5b90807186a752ebac6bcbb8`, with archive SHA256
`2632c3ddd2992a989a08e1a070288901c58391eade2e330af5fb14f291d063d5`.
That exact source object is retained as a parent of integration merge
`02975797051dae5bfb2306ddc439f18af86bd6e8`; future published full clones can
provision it through the existing authenticated archive route. Shallow/source
distributions still require the exact verified archive. No seed ABI, mode, Zig
pin, trust algorithm or active historical artifact changed.

The memory owner's independently committed host qualification was also reviewed
and adopted explicitly: only the loader-cache fingerprint changed, with the
other five declared runtime files and preload absence checked. Production tests
now reject substitution of each runtime input. This does not approve arbitrary
hosts or weaken the unknown-host fallback. S09 transferred its validated private
component cache exclusively to the coordinator at its existing absolute path;
captures record that supported environment override and preserve authentication.

See [S09 seed evidence](S09/native-seed-adoption/README.md),
[S04 host review](S04/native-platform-adoption/README.md), and the coordinator's
archived preparation, manifests and failed-attempt logs. Earlier artifacts and
their uncacheable-host measurements remain immutable historical evidence.

## Outstanding roadmap requirements

- Qualify the complete ordinary-edit matrix on the final compiler. The narrow
  measured guest cohort meets the observed 5-second useful-feedback and
  15-second empirical-p95 targets; it does not establish those targets for every
  edit class.
- Complete supported individual timing for guest/standalone drivers and the
  native full-inventory concurrent-subscriber qualification matrix.
- Gather compatible normal/adverse samples and headroom before enforcing
  action, individual-test, memory or work policies. Advisory values remain
  separate from hard limits.
- Complete remaining long-qualification wall-clock/driver obligations and DL7's
  full correctness/bootstrap chain. Every required self-hosting workload still
  needs median and p95 at most 1.5 times the frozen Zig reference. Partial
  components or instruction samples do not satisfy that acceptance.

| Requirement | Result |
| --- | --- |
| Current complete inventory correctness, source stability and cross-mode identity | Passed for the frozen candidate and five compatible repeats |
| Named final helper workload: observed feedback and empirical completion targets | Passed for 40 warm edits and two forced tests per revision |
| Complete unchanged request within 15 seconds | Failed in all five observations (47.72–56.50 seconds); profile the 11 always-fresh groups next |
| Every ordinary-edit class and stable population p95 | Not qualified; expand the final-compiler edit matrix |
| Calibrated enforced resource policies and full concurrent-subscriber matrix | Not qualified; retain report-only policy and complete adverse-case/headroom evidence |
| Full long qualification and DL7 correctness/bootstrap/performance acceptance | Not qualified; coordinate the remaining owner milestones and rerun DL8 |

See the [ownership ledger](status.md), [final evidence review](coordinator/final-evidence-review.json)
and [coordinator hash manifest](coordinator/evidence-sha256.json) for provenance.
Each session preserves its detailed handoff and raw evidence.
Passed, failed and unqualified observations retain their distinct source, tool,
cache, admission and measurement contexts.
