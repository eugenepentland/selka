# Native lexical arenas
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

The C backend now emits lexical arena entry/exit and typed reset operations for
root and nested allocator capabilities. Each arena owns aligned backing chunks;
buffer growth keeps its original region. Ordinary aggregate values use independent
storage, allowing snapshots to survive the arena that produced them.

The native registry supports 256 simultaneously active regions, matching the VM
default. Reused registry slots receive fresh identities. Parent scopes cannot reset
while children remain active (status 2), and live owners—including empty buffers—
prevent reset (status 1). Root or invalid reset authority returns status 3. Growth
with a different allocator traps with R_CAPABILITY. Reset releases unused chunks
without changing authority; closing the scope invalidates it.

Normal scope exit releases owned values before backing. Function return and
propagation unwind the frame's remaining arena scopes after its values. Traps and
host allocation failures free registered objects and all arena chunks. Existing
source escape checks remain mandatory before native emission.

Debug and ReleaseFast pass all 28 build steps: 530 core tests reused after fresh
successful runs, 60 CLI tests, and 2,568 VM/native comparisons. Parity includes
reset, region limits, zero-capacity ownership, and mismatched allocator behavior.
Sanitizer tests pass 380 injected allocation failures, covering reset, returned
snapshots, propagation, and a bounded 20,000-iteration arena allocation/reset loop.
Formatting and all 88 Guardian checks pass without frozen violations.

[Native pools](native-pools.md) now support root/arena storage and checked handles.
External resources remain unsupported. The broader native track
and the other pending roadmap requirements remain open.
