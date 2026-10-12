# Independent C1 qualification

Frozen production source **a9a3208a4f3edbf17170cfc18d57f5f999af49c3** passed
complete verification and formatting through the authoritative retained coordinator.
All three responses returned status 0, with stable inputs and exact 46 groups covering
all 101 required members; independent review found no missing or unexpected coverage.
This establishes correctness for that source, not completion of every DL milestone.

| Request | Reused / selected | Total seconds | Queue seconds | Gate admitted seconds | Hash / enumeration |
| --- | --- | --- | --- | --- | --- |
| Forced complete |0 /46 |1012.058 |6.416 |985.953 |28837 files /2283 dirs |
| Unchanged retained 1 |35 /11 |73.310 |0.435 |65.862 |0 /0 |
| Unchanged retained 2 |35 /11 |101.175 |0.512 |91.618 |0 /0 |

Both warm requests made 175816 metadata observations and 6 snapshot reuses. There is
no demonstrated reduction of unchanged warm validation or latency. These are two
operational observations, not stable p95. A parallel admitted ReleaseFast build
is recorded; no causal contention claim is made. The older 28–37 second observation
is historical and cannot establish a paired improvement. Ordinary 5 second feedback
and 15 second p95 targets remain unqualified; unchanged-run floor reduction is not
demonstrated. No final independent one-shot complete run was performed.

C0 complete verification also passed: 45 groups/95 members, 1196.052 seconds including
1.139 seconds queue, 110.060 seconds build admitted and 1034.160 seconds gate admitted.
Its retained startup selected every group after a loaded implementation identity
change; supported cancellation returned 143 and published no new success. C0 warm
qualification was not obtained. S08's read-only marshal reproduction shows equal
Python code objects can hash differently with changed string references; actual
startup contributors remain incompletely reproduced. Conservative extra work is
not an unsound cache success. Same-process final requests retain their assigned
implementation digests.

Native inventories reconcile exactly: broad units 1541→1532 plus scalar 9 (eight
named tests and one wrapper moved), Core 1025, CLI 270, tooling 28, memory 7 and
component-support 10 unchanged. Golden 2→4 adds two fixture-isolation assertions;
its 222 checked/382 explicitly skipped cases are preserved. S03's frozen source/name/
wrapper/oracle audit accompanies these actual execution counts. There are 11 observed
Python telemetry members and 90 unknown members:286 selected cases have 286 timings,
all known members complete. Guest/Guardian per-test timing remains unknown;
per-process RSS is lifetime high-water, never concurrent aggregate memory.

Two real independent v 2 producers (tooling and scalar) are adopted. Actual writer,
provider and caller are qualified under reviewed configuration pin
686631858644a1ce4535ac1f981f3338421ff46e3f0f3ca10d7e5de43c14b655. Missing or
unqualified metadata retains broad fallback. S07 reduces golden source preparation
from 222 writes/90182 bytes to 165 writes/66752 bytes without shrinking live cases.
S08 demonstrates cold-construction/dirty rejection counter reductions in its
fixture; unchanged warm work remains unchanged. S06's candidate is rejected:
isolated 20 repetitions show median candidate/C0 ratios 1.1344 for 8 tests and 1.0385 for
shared 128 roots despite 0.5855 for 16384 synthetic tests. Fixed order and 20 samples do
not establish stable p95 or guest-loop improvement.

The complete 14-row matrix distinguishes passed bounded safety fixtures from
unqualified broader live/performance scenarios. DL8 live cold/warm/edit timing,
paired cold compile/RSS/fd costs and full second-worktree qualification remain
open. DL7 full ownership, authenticated bootstrap stages and every required
median/p95 ratio<=1.5 remain open. Report-only budgets are not calibrated hard
limits. No policy defaults or schedules were introduced.

Source, pinned tools, ABI/modes, commands, raw logs, response statuses, action/
member metadata, timings, test inventories and artifact hashes are archived in
raw/. C0/C1 tool snapshots are byte-identical 20348-file contracts. Debug and
ReleaseFast compiler binaries are separately pinned in the versioned artifact
store and live trees are protected from pruning. C1 RF build status 0 took 463.526 s
including queue (operational only); its private cache moved under ignored.tmp/
after exit, preserving the installed prefix. Prepared artifact bytes are
765518171(C0) and 791425272(C1); this size inventory is not a cold compile/RSS
comparison. Production source stayed C1 throughout qualification; later commits
contain evidence only and require coordinator source-diff validation.
