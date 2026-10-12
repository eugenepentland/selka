# Qualified Support6 independent compiler route

This directory records qualification of the independent ReleaseFast compiler at
`5167c588be79dd43d21d5013c36db15110bf239b` and its private owned component installation.
The root integration installation and normal package selection have not changed. `candidate-pin.json` binds the exact full Git tar
archive, pinned Zig version, owned guest mode and independent native ReleaseFast
`seed-compiler` recipe. The archive is retained under A10's private `.tmp`
directory; its hash and size are recorded here instead of committing a second
copy of roughly 1.5 GB of repository history and experiment inputs.

The compiler source commit includes the independent build step and both migrated
component source trees. `preparation.json` pins the relevant source files and
Guardian revision. The new candidate file remains in evidence. The reserved
`selfhost/component-owned-compiler.json` is not created, the historical
`selfhost/component-seed.json` is unchanged, and root build selection is unchanged.

The first three qualification steps below are complete; the integration step remains:

1. A08 qualifies both actual component sources, protocols and ownership/ABI
   behavior with the already-building Debug Support6 compiler. A failure keeps
   this pin a candidate; a source fix requires a new source commit/archive.
2. After that result is accepted, run `qualify.sh FROZEN_SUPPORT6_TREE BUILDER`
   with the corrected independent native component builder. It first verifies
   the source commit, component inputs and archive hash. It then provisions one
   ReleaseFast compiler from the pinned archive, compiles both components with
   explicit zero-RC selection into a private installation and runs the existing
   pure-language and native protocol qualification against that same compiler,
   pin, archive and installed artifact set. Execution is recorded separately in `qualification-state.json`; preparation
   does not establish successful qualification.
3. Record the qualified compiler's local receipt and binary hash, component
   receipts/manifests and binary hashes, complete protocol outputs, counted
   cleanup runs, and emitted LLVM/symbol audits. Native test exit status alone
   does not qualify unsupported tests: the companion script checks every verdict.
4. Integrate only the actual qualified pin, qualify root option forwarding and
   complete installation, and run the complete registered gate. An independent
   component-only build must still work without an installed host compiler.

The corrected builder gives each extracted compiler its own local Zig cache and
temporary directory. It preserves the selected Zig executable, shared global
cache and unrelated environment values. This fixes the inherited outer-checkout
configure-cache conflict. The source archive can remain at the frozen revision:
its `seed-compiler` step never invokes its own embedded component builder.

This is the C1 explicit-selector route. C2 default promotion and C3 retirement
remain separate. C3 requires a new real ordinary-owned compiler pin, the approved
`checked-default-v1` selection guard, selector-free recipes and removal of the
historical fallback. Neither source identity nor a manifest marker substitutes
for qualification of the actual generated component binaries.


The actual independent compiler SHA256 is
`29cfbd13390692757ce3add9cf61d8398eff283760d16cedb3c5b9addaa03e26`.
All four pure-test reports pass (6 + 6 + 15 + 15 = 42 executions, none failed,
skipped, cached or unsupported). Both components pass the native protocol oracle
through fresh verified release builds and the exact installed uninstrumented
binaries. Installed test-index is `251a66b2a8b8fea513e820480bcbd35af43692029822804433d65b64eb072412`;
cache-plan is `c59e0c1705610097ca65c6aa50d2917c5004a2e756e0100655789721f3e162cc`.
Both installed symbol inventories contain direct destruction and no legacy RC helpers.

A08 separately compiled counted binaries with this exact compiler and identical
component source hashes: all 688 protocol executions preserve expected outcomes,
with no RC events, no managed leaks on returning paths, and clean LLVM/symbol
audits. Expected handled errors and two deliberate output-failure traps remain
in that denominator. Counted binary hashes differ from the installed
uninstrumented binaries; the reports identify both sets explicitly.

`qualification-state.json` records the completed scope, report totals and A08
report hash. `provisioned-identities.json`, the copied compiler receipt, installed
manifests, symbol inventories and `native-qualification.log` preserve exact
artifacts and raw evidence. Incidental oracle timings were collected under build
admission for correctness; they are not runtime performance measurements. Queue
waits of 15 and 155 seconds are excluded from any compiler/runtime claim.

The candidate pin is now qualified for these exact inputs. Selecting it for the
root install and full registered qualification remains coordinator work. C2/C3
need their own ordinary-default compiler/pin qualification; this opt-in compiler
still contains active legacy guest selection. The immutable historical seed is
unchanged and no whole-package RC-retirement claim is made.
