Base: `93b48efcc89360b2e04633e1dab865879a7bd784` in the authorized A02-validation tree.
Production proposal is the exact `feature.patch` and source hash in `summary.json`.

Completed: focused tests 2/2; focused native ownership/traps in all five modes;
exact rc_plain_update_paths, mut_dictionary_arguments, and eight-line child-call
reproducer 15/15 zero-RC native cases; ordinary release/debug controls 6/6.
All zero-RC runs preserve expected output, RC0/live0, and LLVM/symbol cleanliness.
Negative same-root sibling mut arguments still reject; separate roots qualify.
No source fixture assertions were removed or weakened. A07 reviewed the patch.

Shared edits were authored by root: SPEC clause and root-test registration.
No runtime/header/source-checker edits are requested. Source root-changing or
orphaned zero-RC calls are not newly claimed supported. Ordinary/refreshed branches
remain existing code. The coordinator must integrate this local patch into its
current build.zig alongside provider/tuple staging and rerun the final gate.

Evidence and exact raw commands are in this directory. Disposable compilers,
programs and caches remain under `.tmp/memory-closeout/A02/mut-call-validation`.
No benchmark or entire-installed-package RC-retirement claim is made.
