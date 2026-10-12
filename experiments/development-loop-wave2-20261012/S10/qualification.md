# S10 wave2 independent qualification

Frozen C1 Debug compiler (`a9a3208a4f3edbf17170cfc18d57f5f999af49c3`, executable SHA256 `e018f4dc02cba5020dcdb9c74a8bdd4354d11b49d2dfaacf5030b0aa82f176f3`) completed two real semantic-feedback cohorts. Each cohort contains one private frontend-cache cold request followed by forty unique source edits. Shared timing admission used `~/.cache/mylang/slots`, tickets 27/28; queue waits 0s/35s are excluded from edit-clock durations. The harness SHA256 is `6688f100802f183025f611646f1a04fe7a49825cb287e669d60e4f862ab971ca`.

| Cohort | Warm samples | Median edit loop | Empirical p95 edit loop | Empirical p95 first check | Maximum first check | Observed status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Imported helper value + matching public test | 40 | 82.103ms | 86.534ms | 86.255ms | 406.075ms | All semantic checks passed; observed partial feedback 5s target passed |
| Public test expression only | 40 | 104.107ms | 146.738ms | 145.967ms | 288.257ms | All semantic checks passed; observed partial feedback 5s target passed |

Cold first-check observations were 81.846ms and 104.054ms. These are single observations of a private frontend cache; they are not cold compiler-build costs. The check-only path does not use a native runtime object store. Zig global cache remains shared and unwiped. Recorded cumulative child high-water RSS maxima were23,617,536 and23,310,336 bytes; concurrent aggregate and pure test-body memory are unknown.

The loop clock starts before editing both source files and includes content hashes, the real supervised semantic check, output-status checks, and manifest/row reporting. First feedback stops after the semantic check. Tool hashing and initial manifest setup occur outside that loop clock. These clocks do not match S07's admitted-action or individual-test policy clocks. No policy deadline is qualified. Forty observations establish empirical cohort percentiles, not a stable population tail.

Native completion remains **not qualified**. The original two-test operational qualification failed: host loader cache changed from the compiler-reviewed identity, correctly selecting uncacheable toolchain handling; the driver deleted uncacheable unit objects before link. Actual native JSON reports two failures, zero passes. Source fixes and new compiler preparation belong to the coordinator. The failed collector's constant `completed_tests: 2` field is erroneous and explicitly excluded as evidence; original raw logs are preserved. A redundant queued C0 attempt was canceled before launch (status 143) after the shared fallback cause was established.

Overall full ordinary-edit verification 15s, unchanged complete verification 15s, whole-root cold-build no-regression, native scalar/golden fixture speed and memory deltas, independent current full-gate equivalence, and strict DL7 median/p95 ratios remain **not qualified by this S10 evidence**. Parent and peer evidence may qualify narrower rows later. No comparison improvement is inferred from the previous two operational warm gate requests.

Raw cohort manifests, individual command outputs, source hashes, CPU/RSS counters, run/context IDs and SHA256 inventories are under `raw/check-helper-isolated` and `raw/check-test-isolated`. Operational and failed attempts are separately retained. No production verification receipt is created by this direct harness.
