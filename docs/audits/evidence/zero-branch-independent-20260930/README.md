# Rejected frozen f4 selector review

The independent review rejects frozen `f4b6647d` because the adjacent zero-result
fold can cross a comparison-to-branch tail that materializes an external address
with an add. `report.md` identifies the source lines and conservative repair.

`tail-regression-receipt.json` records the exact before/after commands and actual
outputs: control parent `e66b8035` passes marker23; both rebuilt and installed f4
QBE produce marker17 and exit1. The loaded payload456 remains correct. The original
production130 cases and independent3754 assertions still passed; their receipts
are retained so those green results cannot conceal the missing tail boundary.

`raw-review.tar.gz` retains source fixtures, C oracles, selected assembly, stdout,
stderr, logs and the actual QBE/probe executables used. Candidate/control builds
use identical committed QBE source/header files except the parent's isel.c.
`manifest.json` records each original path, byte length and SHA256. Every member
was decompressed and checked against its manifest before commit. These are native
amd64 Linux verification artifacts, without a performance acceptance claim.

The review worktree has no compiler/QBE source changes and no copy.c changes.
Root owns final combined acceptance and the coordinated Guardian feedback append.
Corrected continuation verification will be recorded separately after its source
is frozen; the rejected evidence stays immutable.
