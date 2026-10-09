# Suite build reuse and EDA repair calibration — 2026-09-07

The verifier now builds each frozen Zig suite once. The next three-agent trial
also completed: Python, `.selka`, and Zig all repaired the exact-clearance regression
and passed every common private group. This remains exploratory evidence, not a
language ranking or the scored pilot.

## Cold-build fix

`BuildReuse` keeps a verified executable in coordinator memory for one public,
practice, or private-grading suite. Its key includes the frozen source hash and
full adapter identity, including tools, Guardian policy and limits. Live source
and tool identities are checked before and after evaluation. Failed prerequisites
are not cached, and changed source/adapter or a new suite needs another build.

Guardian, Debug tests and ReleaseSafe compilation run before publishing a main
Zig artifact. Every input still gets a fresh namespace/process, source workspace
and private cache. Reused executables are copied from coordinator-held bytes, so
an earlier input cannot overwrite the executable or runtime state of later inputs.
The cache contains no expected answers or behavioral pass results. Deadlines
still apply to every actual execution. Logs distinguish executed prerequisites
from artifact reuse and retain the executable hash and originating build record.

This is suite-local reuse, not a persistent/global cache or cross-agent scheduler.
Historical frozen grading plans cannot silently resume under the changed policy.
The sandbox also suppresses generated Python bytecode, and the new trial baseline
copies omit old bytecode and inherited Guardian caches. Explicit public document
paths are supplied to all new participants.

The same previously repaired Zig practice source passed all 21 inputs:

| Measurement | Earlier verifier | Updated verifier |
|---|---:|---:|
| Compile executions | 21 | 1 |
| Compilation time | 260.0 s | 11.7 s |
| Application executions | 21 | 21 |
| Verified build reuses | 0 | 20 |

The updated complete verification suite took 25.7 s, including identity hashing,
isolation and output checks; application executions themselves totaled 1.66 s.
These are single before/after measurements of the harness, not agent productivity.
The 51 targeted tests across 13 modules passed, covering isolation, source/tool
invalidation, failed prerequisites, deadlines, executable corruption between
inputs, public/private suite reuse, grading resume and coordinator integration.

[Implementation and measurement evidence](../../experiments/application_comparison/evidence/build-reuse-20260907.json)
records the exact changed-source hashes and validation scope. The historical
141-test report was not rerun or relabeled as covering these edits.

## Next trial: exact-clearance repair

Three fresh participants used the same public contract, seeded equivalent defect,
stdlib-only dependency rule, 20-minute practice limit and 30-minute task limit.
Zig used Guardian; `.selka` used the installed bytecode host and compiler/navigation
mounts. No API key or language/compiler change was needed.

| Participant | Preparation | Repair task | Public submissions | Private result |
|---|---:|---:|---:|---|
| Python | 24.2 s | 67.5 s | 1 | 9/9 groups passed |
| `.selka` | 22.1 s | 89.6 s | 1 | 9/9 groups passed |
| Zig + Guardian | 59.1 s | 97.4 s | 1 | 9/9 groups passed |

Times are observed wall time including participant tool/check waits. Private
checks ran after every participant sealed and are excluded from repair time.
They covered 142 EDA cases and four malformed requests, including integer
geometry, exact/near clearance, unit equivalence and original behavior.

All repairs replaced the inclusive squared-distance comparison with a strict
comparison while preserving positive-area overlap detection and integer
arithmetic. Each participant added regression coverage. The agent-reported
initial behavioral failures reproduced the seeded bug; this was not a bug found
by Guardian or a `.selka` static diagnostic. An independent static review found no
new correctness defects or application dependency violations. It noted that the
new `.selka` CLI tests hardcode trial paths, while Zig's added internal-report tests
do not themselves cover transport or unit conversion. The common suite supplies
additional coverage; sealed sources were not edited after review or grading.

The actual Zig session recorded:

| Suite | Guardian runs | Debug runs | Builds | Input executions | Build reuses |
|---|---:|---:|---:|---:|---:|
| Practice | 0 | 0 | 1 | 21 | 20 |
| Public | 1 | 1 | 1 | 2 | 1 |
| Private | 1 | 1 | 1 | 9 | 8 |

Guardian passed all 88 checks with zero blockers and 17 existing report-only
line-length findings; no policy changes or freezes. Nine Zig Debug tests passed.
Guardian feedback commit: `f634dec` in guardian-zig, whose commit hook also passed.
No current ROI subjects were available in the cleaned snapshot: preserving gate
telemetry outside disposable execution directories remains a follow-up.

## Interpretation and next work

This adds a small repair task in a second application to the earlier feature task:
six actual exploratory sessions across two blocks now have private results.
Keep the first block's timing separate because it used the old build policy.
One-character repairs provide little evidence about large-project maintenance,
ownership diagnostics, navigation or iteration on shared APIs. Exact model ID,
token/cost data and whole-agent enforced isolation remain unavailable; agents
were instructed to use their own isolated gateway on a shared host.

Remaining friction included unavailable `rg` inside the runtime, checkout-specific
baseline test paths, and two premature Zig practice-finish calls while the check
held its lock. These are recorded as workflow costs, not application defects.
No generated Python bytecode appeared in the new sealed submissions.

Next run the remaining shared-contract/feature families with fresh repetitions
under this fixed policy, then decide whether to invest in medium/large maintenance
trials. No productivity or defect-reduction advantage has been established yet.

[Trial summary and source receipts](../../experiments/application_comparison/evidence/direct-agent-clearance-20260907.json)
include phase clocks, retries, command metrics, artifact reuse and deviations.
Full sources, patches, public/private logs, frozen configurations, coordinator
source inventory and independent review notes remain under
`/home/epentland/ai/canopy/application-trials/direct-20260907-clearance`.
