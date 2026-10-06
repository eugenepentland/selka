> Historical checkpoint: the user resolved this hold in plan §2 at `e50e508a4` and authorized resumption. C and the property runner are now qualified and integrated as `f1319a774`; its 254 core tests and all 1,518 conformance cases in each mode pass. M package qualification, Wave C applications and S3-X continue. The final §7 exit report will supersede the outstanding-work list below.

# S3 checkpoint: held for the §2 old-answer decision

Integration source is `fb9bff998fb1d31f056ad0fe0ace9230bd033391` on `codex/new-core-s3-integration`. Qualified text evidence `0b48e9217` merged as `2e4f0f512`; qualified number evidence `5d2849ff5` merged as `fb9bff998`. The requested default core-shards change from four to eight was committed first as `8918de747`. No push or mylang main merge occurred.

## Required review

S3-C evidence `60257ebd5` records an old-runtime implementation accident on source `8e52a2129`. A valid ABI7 Environment adapter supplies an opaque callback context containing CUSTOM. With three controlled process variables, old env.names() reports one name by interpreting that callback context as an allowlist; Core reports three using its explicit grant state. Both executable statuses are zero and stderr is empty. See `stop/context-implementation-accident.md`, the minimal source/provider, and separate logs. Plan §2 requires stop/report rather than an agent behavior decision. The user was asked whether to preserve the legacy behavior or correct both runtimes and requalify; no answer or authorization is inferred from time passing.

Further implementation, qualification and integration are held. C and runner have no active jobs. Root's M qualification was canceled for source review corrections, with its logs retained. Only this evidence checkpoint and required Guardian feedback are being saved.

## Integration checks completed

| Merge | Core tests | Held core-test time | Longest shard | Installed rebuild | Conformance per mode |
|---|---:|---:|---:|---:|---|
| T1 | 221/221 | 75.67 s | 71.68 s | 0.87 s cached | 1310 match / 0 mismatch / 208 refused |
| T2 | 228/228 | 80.98 s | 71.16 s | 3.42 s | 1405 match / 0 mismatch / 113 refused |

See `integration-checkpoint.json` for measured shard maxima and exact scope. T1 conformance run01 used the obsolete installed Wave A binary and is explicitly excluded; run02 followed a fresh install and qualifies the merged source. T2's full run01 had old-compiler DiskQuota setup failures for two files, with no claimed pass for that run alone. On unchanged source, the focused run02 passed all 23 missing comparisons at debug and release; the table combines the full sweep's completed files and those replacement results. No further gate needs repeating solely to hide the retained failed logs.

The T1/T2 package reports retain 50-case feature fuzz, own-file strict leak/verify checks, unchanged 35 definitions and passing affected row ratios. The Zig float runtime unit cold compilation is 0.96559 s, the whole fresh program 3.11696 s, and a distinct second program reuses it in 0.11394 s. Its key includes runtime-source content, executing Zig version and compile/target options; simulated version invalidation is labeled as simulated.

## Outstanding work

- C: resolve the old-answer decision; qualify final capability/I/O/Host/resources/grants source together with the property runner. Runner worktree HEAD `f58da8e37` is a Guardian-green dependency checkpoint; implementation remains uncommitted, with a collection decoder phi defect and complete old-report comparison/stand-in-reset/signal/full gates still owed.
- M: HEAD `681e84cf1` is unqualified. Source-aware rendering/unit fixes are pending in its worktree. A new captured-place probe also demonstrates an unqualified old/new mismatch after a later scalar ancestor update. Its HOLD.md and exact source patch preserve current state. Existing 41 mutation-place tests and 50-case S0/S1/functions fuzz had passed earlier checkpoints; they do not settle that new probe.
- Wave C: start S3-A only after C, T1 and T2 have qualified and merged. Implement stdlib/application admission, word_count first, and measure every application size against old core and Zig ReleaseSafe on CPU 10.
- S3-X: final full old gate, strict 200 cases of every fuzz kind, complete leak/verify sweeps, all 40 rows including inner-loop count audit, coverage and exact S4-only/arena exceptions, dev-loop times and every remaining limit.

This is a stop checkpoint, not the §7 S3 exit report. The S4 decision is not reached. Estimated remaining active work remains roughly 6–10 hours after the required behavior decision, with application performance and property-runner qualification the largest uncertainty.
