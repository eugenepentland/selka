# Prepared interior mutable calls

A checked interior mutable argument now transfers its selected child to the callee
and reattaches the returned child through the exact parent path captured before the
call. This fixes source-admitted calls such as `clone_during(mut original[0], source)`
that previously produced `retain` and failed `E_ZERO_RC_LOWERING`. The prior failure
and reduced sources remain in `../mut-dictionary-diagnosis/`.

Production changes are isolated to `src/core/build.zig`: `callTarget`, `writeBack`,
and two small prepared-path helpers. The path is prepared only for zero-RC interior
arguments with an unchanged root version. Captured parent references, normalized
list indices and dictionary entry ordinals are reused for reconstruction. Managed
child reads carry the existing transfer flag so replacement does not destroy the
already-transferred slot. Preparation and reconstruction each traverse only the
selected path. Ordinary mode, refreshed/orphaned capture behavior, and source
checker overlap rules retain their existing branches. This does not claim support
for a root-version-changing zero-RC path.

A07 reviewed the exact production diff as matching the audited prepared receiver
path. The focused test covers a side-effecting negative index evaluated once, deep
record/dictionary/list paths, direct/callback calls, two distinct roots, growth,
replacement and early return, managed results surviving parent clear, and repeated
replacement. A missing key or invalid child index traps before callee effects.
Two mutable sibling arguments with one parent root still refuse at source checking;
the fix does not accept them and risk overwriting a prior sibling writeback.

`registered.json` pins the exact source hashes, compiler binary, pinned Zig, component
path and focused commands. `summary.json` records qualification totals. The exact
`rc_plain_update_paths.my`, `mut_dictionary_arguments.my` plus harness main, and the
eight-line child-call reproducer are frozen under `sources/`; per-mode files preserve
all compiler argv, native output, counters, binary/LLVM identities and symbol audits.
Direct-destruction `release_unique` sites are classified separately from RC events.
Ordinary-mode controls are semantic/leak checks and may execute legacy RC.

The installed Support6 component directory is an interim legacy packaging boundary.
These results qualify the local guest compiler change; they do not mark C1/C2/C3,
whole-package RC retirement, or the coordinator's final gate complete. No runtime
speed, RSS, allocation-saving, or compiler-timing claim is made.

Shared changes: root authored the `NEW-CORE-ZERO-RC-OWNED-MUT-CALL-1` SPEC clause
and `a02_mut_call_test.zig` import in `src/core/root_test.zig`. The only new test
files are `a02_mut_call_fixture.my` and `a02_mut_call_test.zig`. Root retains the
integration `build.zig` reservation and consumes this focused patch without
replacing its unrelated provider or tuple changes.
