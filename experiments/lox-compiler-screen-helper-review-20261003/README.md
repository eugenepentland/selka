# Independent review of compiler-only preparation helpers

The reviewed helpers preserve the distinction between rebuilding a guest and
measuring a qualified guest. Preparation requires the selected 37-file AST
source map for both arms. It retains fresh candidate rebuilds and compares ELF
entry/header fields, program headers and every allocated section's bytes and
layout. Other reported section differences must be debug or symbol metadata.
This comparison is reproduction evidence for these native artifacts, rather
than a general executable-equivalence proof.

Performance paths receive the exact original qualified RC ELF bytes and their
sidecars. The original ELF, manifest, receipt and referenced runtime hashes
are captured before rebuilding, each sidecar copy is checked against that
initial digest, and final guards recheck the originals. Baseline/reference
guests are copied and remain bound to their original whole-file hashes. The
external QBE path is passed only to QBE builds, preserving LLVM selection.

The initial review identified missing upfront original-sidecar/runtime guards.
The reviewed revision fixes that gap. Earlier preparation receipts remain
historical; they are not evidence for this revision. The analyzer requires
complete case/arm/round coverage, successful status, exact output hashes,
empty stderr and all four PMU running percentages at 100. Cycles use the same
counter dataset and paired calculation as instructions.

This is a static helper review. Compiler qualification is separately reviewed;
no preparation, build, guest, counter or timing command was rerun here, and no
measurement result is certified by this receipt. `verify.py` checks only the
four retained helper snapshots and their current source identities.
