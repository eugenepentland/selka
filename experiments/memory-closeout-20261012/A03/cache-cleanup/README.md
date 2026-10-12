# Completed-run cache reclamation

At the coordinator's explicit request, A03 reclaimed 1,810,354,176 allocated bytes
from its own local `.zig-cache` and 30 completed-run cache directories. None was
an active build or timing control. A08 explicitly confirmed that it no longer
needed `C0-batched/cache` for an artifact-transition fixture.

All raw commands/stdout/LLVM/counter reports, native output binaries, sources,
frozen compiler installations and pending-reproducer caches remain. The manifest
records each deleted directory and its allocated size, plus SHA-256 identities
for 1,189 disposable cached executables. No LLVM files existed inside these cache
directories; the empty preservation archive records that scan. Baseline strings,
Support7 strings and supplemental Result-list native output hashes were checked
after cleanup against their existing qualification reports.

No shared cache, user cache, other worktree or historical evidence was deleted.
Future qualification creates fresh private run directories through the unchanged
shared admission queue. Cache state from this completed qualification was not a
controlled warm scaling or runtime baseline; it is not reused as such.
