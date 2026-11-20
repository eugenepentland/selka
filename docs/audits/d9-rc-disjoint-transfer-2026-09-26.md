# Elide proven-disjoint RC transfer checks — 2026-09-26

Completed ordinary-owner producers publish scalar values in operand storage and
aggregate values in their stable operand buffers. Both occupy distinct ranges
from pending work storage. Their bounded inline TAKE now uses this fact to omit
its dynamic source/destination overlap branch. Pointer and header checks, pin
handling, arena checks and the fallible runtime fallback remain unchanged.
Guarded transfers retain the overlap test. New loan-producing instructions must
be excluded from the completed-owner proof unless they publish a real owner.

The independent runtime review confirmed the proof for stack and heap frames,
including scalar transfers whose old journal bytes remain behind a cleared guard.
The structural test checks both the elided branch and the guarded counterexample.
An initial draft incorrectly applied the fact to both callers of `prepareOwned`;
the negative test caught it. The final implementation passes the fact explicitly
only from the completed-producer path. Both failed and corrected test logs remain
in the evidence archive.

Validation: 17/17 focused tests; Debug install 19/19 with Guardian88; 131/131
uncached guest assertions from 20 files on each actual backend. Coverage includes
aggregate/recursive values, callbacks, unique resources, arenas, receiver scopes,
held views, journal type reuse, iteration identity and live-view snapshots.
LLVM guests use `--release` (O3/full LTO).

The private depth12 binary-trees diagnostic uses three interleaved instruction
samples per side on CPU3. Both compilers are Debug builds; actual LLVM binaries
use O3/full LTO. This is not the WP-4 corpus acceptance measurement.

| Backend | Before median | After median | After/before |
|---|---:|---:|---:|
| QBE | 1,076,792,627 | 1,053,643,014 | 0.978501 |
| LLVM | 628,523,426 | 610,701,627 | 0.971645 |

Every sample and its outliers are retained. All four counted controls preserve
the expected output and identical counters: 669,060 allocations and retirements,
19 owner acquisitions, 669,079 releases, zero held acquisitions/releases or clones,
and 33 uniqueness checks. The [archive](../../experiments/d9-rc-disjoint-transfer-20260926/identity.json)
contains source/compiler/binary identities, the exact patch, drivers, raw samples
and guest verdicts. The integration branch still owns the required combined gate.
GC remains the default.
