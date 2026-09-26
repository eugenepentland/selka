# Borrowed mutation projections

An immediate list-element read into a compiler mutation receiver now borrows
from the parent when the existing inert receiver proof succeeds. The new check
requires the exact physical parent, base read and immediately following fill,
with no alternate entry to that fill. The complete bounded interval must keep
the parent alive, contain no callbacks or publication, and finish in a plain
element mutation. Fill still makes the element unique and refreshes the pointer
before writing. Named row snapshots and unproved paths retain ownership.

Both compilers are Debug builds. The before compiler is the scalar-store
candidate, SHA256 `567c2e3142503825e7c1bf87755b46b4b411d5cc52893640a87f984ef03f9bd2`.
After SHA256 is `253363861a6b5af378bb04215ad8ff47d388e77a7f524ee69a8a69e086234ad8`.
Actual QBE and LLVM O3/full-LTO guests pass 89 receiver, snapshot, aggregate
and lifetime assertions per backend. Their counters balance and match.
A three-level shared-list regression preserves the original cube and an
explicit named row while updating separate descendants. Both backend bounds
traps retire all six allocations. The structural selection passes 13 tests;
whole-tree Guardian passes 88 checks.

For the unchanged n12 matrix diagnostic, owner acquisitions fall from 1,831
to 103 and releases from 1,963 to 235. All other counters are identical:
132 allocations/retirements, one clone, 482 uniqueness checks and no holds.
Median-of-three user instructions on CPU 10 fall from 1,935,887 to 1,027,928
on QBE (0.5310×) and from 1,338,031 to 745,292 on LLVM (0.5570×).
Every run prints exactly `41383` and `485891` on separate lines.

[Raw evidence](evidence/d9-rc-inert-projection.json.gz) preserves all commands,
hashes, drivers, outputs and samples. The diagnostic changes only the mandated
matrix dimension from 500 to 12; it is not the full RC performance acceptance.
Root integration owns that measurement and the full gate.
