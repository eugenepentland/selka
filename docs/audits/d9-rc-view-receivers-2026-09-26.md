# Held mapping receiver lowering

`mapping = {1: 7}; snapshot = mapping; view = mapping.values();
view.mapping[1] = 9` previously aborted in RC, while GC kept both ordinary
snapshots at 7 and updated the view to 9. The generic COW cursor treated the
view's held mapping edge as an ordinary owner during detachment.

The compiler now carries the held-field role through typed COW field cursors.
It calls `myl_qbe_rc_unique_held` for that slot, and checks the actual guarded
H role for compiler receiver locals that can carry it. Ordinary owners keep
their existing path. Runtime prerequisite `433b00b3` supplies transactional
H replacement and held-pointer scope traversal: a fresh clone acquires its hold
before publication, then releases the former hold and the fresh ordinary token.
No ordinary snapshot edge is released by this replacement.

The Debug compiler SHA256
`1962f4e9019fd75d2f4248a12bbfbe928d4d25ef7446c5a1e495bc50bf34a88e`
builds both QBE and LLVM ReleaseFast guests. All seven new cases pass on both
backends: unshared identity, shared snapshots, held-only lifetime, a nested
record field, callback snapshot publication, callback rebinding, and a view in
a list slot. Each backend reports exactly 96 heap allocations/retirements,
28 owner acquisitions, 124 releases and 83 acquisitions/releases of holds.
The three existing view cases also pass both backends with identical balanced
counts (48 allocations/retirements and 424 holds). All seven new tests pass
fresh GC tests with explicit native stress. The ownership-plan unit selection
passes 33/33 after joining the corrected ABI-negative fixture.

The C prerequisite separately validates overflow/arena rollback and typed
bridge cleanup. Full joined gates and the broader corpus remain integration
work; this change makes no performance acceptance claim. In particular, the
separate temporary-cleanup receiver-anchor follow-up belongs to the collection
agent and is not altered here.

[Compressed evidence](evidence/d9-rc-view-receivers.json.gz) contains exact
commands, compiler identity, source fixtures, before/after output and counts.
