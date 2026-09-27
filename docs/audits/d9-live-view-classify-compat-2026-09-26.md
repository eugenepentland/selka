# Preserve legacy read-only class classification

The snapshot correction used its shared-projection predicate too broadly in the
ordinary ownership classifier. That predicate also covers class and Cell
identity, so the existing read-only `Node.children -> kids` explanation changed
from `borrow` to `copy`. The full gate caught the unchanged assertion in
`OWNERSHIP-ANALYSIS-1`.

Only a live-view crossing now forces the early independent-publication copy.
Explicit value-copy analysis retains the broader class/Cell/shared-storage rule.
This restores legacy borrow classification without weakening direct or nested
live-view mapping snapshots. No checker or runtime rule changed.

Validation on base `8511f396`: the existing ownership group passes 19/19 and the
live-view group 18/18. The 45-case view, snapshot, iteration and callback bundle
passes under GC stress and counted RC on both QBE and actual LLVM O3/full-LTO:
180 executed assertions. Both RC runs have the same balanced 5,388 heap
allocations/retirements and 2,320 hold acquisitions/releases. Guardian passes all
88 checks. The parent owns the cumulative full gate.

Full commands, compiler identity, outputs and counts are retained in
[evidence/d9-live-view-classify-compat.json.gz](evidence/d9-live-view-classify-compat.json.gz).
