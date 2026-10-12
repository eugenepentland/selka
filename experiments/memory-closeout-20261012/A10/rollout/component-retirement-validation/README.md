# Unapplied package retirement route

`../C3-component-retirement.patch` removes the historical seed fallback from the
component builder. It requires an explicit independent compiler pin whose
`memory_mode` is `zero-rc-v1`, `ownership_selection` is `checked-default-v1`, and
recipe is the native ReleaseFast `seed-compiler` step. A C1 opt-in pin without
the new selection marker is refused before invoking a compiler. The recipe and
marker become part of seed, component cache and installed artifact identities.

Both component build and native qualification use ordinary compiler commands;
neither forwards an experimental selector. Native qualification also rejects an
installed manifest without both owned memory mode and default-selection markers.
The fake compiler traps on either retired selector, so positive tests verify the
actual child arguments rather than merely inspecting a flag in an output report.

The draft builder compiles independently with ReleaseSafe and LLVM. All 27
fake-tool tests pass, preserving prior cache, archive, installation, failed-build,
digest and reproducibility assertions. New negatives cover absent pin, old opt-in
selection and malformed selection. The previous dual-mode cache positive becomes
an ordinary-owned route positive and explicit historical-fallback refusal.
Patch application and Zig formatting checks pass. Raw logs and exact source and
binary hashes are in this directory.

The patch is **unapplied**. It creates no real manifest and does not modify the
immutable historical seed. At Stage4 the coordinator must provide a real pin for
the qualified ordinary-owned compiler and change root build forwarding to select
it. Those changes must land with this patch: an omitted pin now deliberately
fails. A manifest marker is a selection guard, not proof of generated ABI,
protocol behavior, absence of RC, or successful installed-package qualification.
Those checks must use the actual pinned compiler and installed component outputs.
