# S10 wave2 independent qualification

Frozen C1 Debug compiler (`a9a3208a4f3edbf17170cfc18d57f5f999af49c3`, executable SHA256 `e018f4dc02cba5020dcdb9c74a8bdd4354d11b49d2dfaacf5030b0aa82f176f3`) completed two real semantic-feedback cohorts. Each cohort contains one private frontend-cache cold request followed by forty unique source edits. Shared timing admission used `~/.cache/mylang/slots`, tickets 27/28; queue waits 0s/35s are excluded from edit-clock durations. The harness SHA256 is `6688f100802f183025f611646f1a04fe7a49825cb287e669d60e4f862ab971ca`.

| Cohort | Warm samples | Median edit loop | Empirical p95 edit loop | Empirical p95 first check | Maximum first check | Observed status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Imported helper value + matching public test | 40 | 82.103ms | 86.534ms | 86.255ms | 406.075ms | All semantic checks passed; observed partial feedback 5s target passed |
| Public test expression only | 40 | 104.107ms | 146.738ms | 145.967ms | 288.257ms | All semantic checks passed; observed partial feedback 5s target passed |

Cold first-check observations were 81.846ms and 104.054ms. These are single observations of a private frontend cache; they are not cold compiler-build costs. The check-only path does not use a native runtime object store. Zig global cache remains shared and unwiped. Recorded cumulative child high-water RSS maxima were23,617,536 and23,310,336 bytes; concurrent aggregate and pure test-body memory are unknown.

The loop clock starts before editing both source files and includes content hashes, the real supervised semantic check, output-status checks, and manifest/row reporting. First feedback stops after the semantic check. Tool hashing and initial manifest setup occur outside that loop clock. These clocks do not match S07's admitted-action or individual-test policy clocks. No policy deadline is qualified. Forty observations establish empirical cohort percentiles, not a stable population tail.

In these original C1 check-only cohorts, native completion was **not qualified**. The original two-test operational qualification failed: host loader cache changed from the compiler-reviewed identity, correctly selecting uncacheable toolchain handling; the driver deleted uncacheable unit objects before link. Actual native JSON reports two failures, zero passes. Source fixes and new compiler preparation belong to the coordinator. The failed collector's constant `completed_tests: 2` field is erroneous and explicitly excluded as evidence; original raw logs are preserved. A redundant queued C0 attempt was canceled before launch (status 143) after the shared fallback cause was established.

At that initial evidence stage, full ordinary-edit verification 15s, unchanged complete verification 15s, whole-root cold-build no-regression, native scalar/golden fixture speed and memory deltas, independent current full-gate equivalence, and strict DL7 median/p95 ratios were **not qualified by those check-only cohorts**. Parent and peer evidence may qualify narrower rows later. No comparison improvement is inferred from the previous two operational warm gate requests.

Raw cohort manifests, individual command outputs, source hashes, CPU/RSS counters, run/context IDs and SHA256 inventories are under `raw/check-helper-isolated` and `raw/check-test-isolated`. Operational and failed attempts are separately retained. No production verification receipt is created by this direct harness.

The isolated planning comparison completed forty balanced baseline/candidate pairs, each constructing payloads, keys and dependency summaries for all 46 groups on the immutable previous integration input tree. Four snapshots (tools/config/source/artifacts) reject input changes before/after every pair; the source snapshot contains 4639 records. Exact semantic equality holds after only the declared action-domain v4/v5 and receipt-version 1/2 comparison normalization; actual production keys remain separately recorded and differ.

Baseline median/p95 planning-row time was 2.077760/4.875942s; loaded candidate was 1.869006/4.175622s (ratios 0.89953/0.85637). Initial snapshot setup 30.788s and per-pair validation are outside the planning-row clock. Total 220.761s, shared timing ticket 31 after 5s queue. Candidate source file SHA256 `553427e97aafc3e77c8fa507d4328f4746428acba5dfde7e2fbd5712320ea0ef` matched after completion; it was loaded once from the active integration tree, whose implementation files are not covered by those four input snapshots. Therefore this is explicitly a loaded-function comparison on frozen old inputs, not final frozen-candidate qualification. No whole verification latency or planning RSS improvement is inferred. Raw `planning-paired40.json` SHA256 `24bec9af35db529573bef6e1c28745e15007786bf6c3125d8555f0e8158882ba` and its summary/context are retained.


## Final complete and warm verification

Final source `1eea987411a1ac5b42941b2ad26a25052a002460` completed all 46 groups and 106 registered required members with stable inputs and no outstanding work. The original forced primer at `9d1b51f3` passed in a 920.507-second exclusive request; its corrupted native-unit timing observation remains unknown. After the isolated telemetry-test fix, selective complete requalification passed in 123.360 seconds, reusing 33 groups and executing 13. Exactly `verification_cache` and `verification_session` changed keys; the other 44 and common context remained identical.

Three one-shot unchanged requests and two retained unchanged requests passed in the original root launcher context. Every request reused 35 groups and ran the 11 always-fresh groups; all 46 keys and the common budget context match across modes.

| Mode/request | Exclusive request seconds | Outer seconds including queue | Files hashed | Directories enumerated | Metadata observations |
| --- | ---: | ---: | ---: | ---: | ---: |
| One-shot 1 | 56.495513 | 86.908901 | 28,859 | 2,290 | 738,564 |
| One-shot 2 | 52.936049 | 53.272757 | 28,859 | 2,290 | 594,173 |
| One-shot 3 | 50.490209 | 55.844294 | 28,859 | 2,290 | 594,173 |
| Retained first | 51.727107 | 57.252149 | 28,859 | 2,290 | 594,173 |
| Retained second | 47.719876 | 47.830955 | 0 | 0 | 154,145 |

Each hashing request read 2,328,979,767 bytes. The second retained request reused six snapshots. Retained stop and owned-lineage closeout completed successfully. The request clock ends at final report assembly; final report write/output/session startup are excluded. All use the same named 1800-second full-request exception; changing that bound would change action identities. These small per-mode cohorts do not qualify a population p95; every observed exclusive window exceeds the 15-second warm target.

A discarded S10-launcher attempt selected all 46 groups and was cooperatively canceled (status 130), without any accepted warm sample. Independent hash-only comparison proved the sole full normalized inherited-environment difference was `CODEX_THREAD_ID`. This is correct conservative invalidation. The selected environment fields in the capture were insufficient to prove full equality; compatible observations use the original root launcher. Raw failure and both environment-hash manifests are retained under `raw/incompatible-warm-canceled`.

Actual report captures, SHA inventories and cross-mode summaries are in `raw/final-primer-9d1`, `raw/final-requalification-1eea`, `raw/final-warm-root-one-shot`, `raw/final-warm-root-retained` and `raw/final-warm-summary.json`. These establish final full correctness and actual cross-mode receipt compatibility; they do not retroactively qualify old canceled baseline warm evidence or strict compiler-port ratios.


## Final cacheable guest edit cohort

The frozen final Debug compiler `cc827c4e…` and manifest `f11fb105…` completed one private-cache cold request plus forty distinct imported-helper/public-test edits under shared timing ticket 46 (5 seconds queue). All 41 source revisions passed the real semantic check and exactly two forced fresh named tests: 82 completed tests total, 80 in the warm cohort, no cached/failed/skipped tests. The helper and public-test files have distinct content identities for every revision. Compiler, pinned Zig, manifest and all five companion artifacts were checked before and after execution; the unchanged harness SHA is `2c8082f05aa3897a50b70e10a07474f1139a3b9f04200fcdc175bbaaa895af17`.

Warm edit-plus-check-plus-test completion median was 365.503ms; nearest-rank empirical p95 was 425.486ms. First partial semantic feedback empirical p95 was 81.629ms and maximum 82.121ms. The single cold request took 3.062513 seconds. Observed cumulative child high-water RSS was 175,165,440 bytes; concurrent aggregate and pure test-body memory are unknown. Runtime/project caches are private; Zig global cache is shared and unwiped. Native cache reasons are `force`, distinct from the earlier uncacheable fallback cohort. Raw `raw/final-helper-isolated` retains per-command actual native work records, source identities, CPU/RSS observations, output hashes and exact clocks.

For this named two-test imported-helper cohort, observed partial feedback stays below 5 seconds and empirical p95 complete narrow verification below 15 seconds. Forty samples do not establish a stable population p95, an organization-wide editor deadline, or performance for compiler-source, arbitrary ordinary edits, final test-only edits or the complete verification gate. Its S10 launcher context is explicit and makes no cross-actor receipt reuse claim.
