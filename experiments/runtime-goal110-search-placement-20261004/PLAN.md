# Search placement diagnostic

Approved diagnostic scope only. No production source or benchmark change,
goal acceptance, or production padding is involved. The original031 source,
Debug compiler, installed runtime assets, 24 guests and G4 controls stay
immutable. Build launch is held until the dictionary timing lane releases.

The wrapper delegates the exact underlying Zig argv, including response
files. It saves full-LTO raw assembly and bitcode/native inputs, annotated
assembly at the normal assembly command, actual argv, complete stdout/stderr,
tool/config/helper hashes and UTC records. It does not alter probe output.
Each invocation has a unique directory to avoid concurrent worker collisions.

1. Build frozen text in a fresh private capture cache using the pinned031
   compiler and original G4 clock, ReleaseFast LLVM O3/full LTO, with the
   wrapper in capture mode. Require the final ELF to reproduce SHA
   892b089c25a316f80d8ad000d93125f59ffa871893d3d15526e7b05bb29319a0.
   An exact reproduction failure stops the counterfactual.
2. Identify the actual assembly label corresponding to caller-loop offset
   0xd60 in kernel symbol
   myl_f_1af80ea2572d9d5f91426ffa7805826aa9a97e2ce757b902d5901fdbfc722f76.
   Use a disposable local-label-preserving object or symbol aliases to map
   assembly labels. Verify the loop's102 instructions, entry offset, scanner
   call and backedge against the archived ELF. Save the label/mapping proof.
3. Build once in a separate fresh private cache with fill32 mode, bound to
   that exact raw-assembly SHA and label. Insert32 bytes of one-byte NOP fill
   immediately before the label, before existing frame-map annotation.
   The branch backedge still targets the label after the fill. No instruction
   sequence within the loop or algorithm changes. Save all raw/final assembly.
4. Inspect whole caller, helpers and loaded constants. Rebase all changed
   code/data addresses and enumerate moved regions; independently verify
   backedges and call-frame tables. Any changed non-padding instruction must
   be reported before timing. Assembly NOPs may execute on the first entry
   fallthrough, but must never execute on the repeated backedge.
5. Retain200 ordinary frozen text oracle outcomes on the counterfactual,
   complete argv/status/stdout/stderr and clock protocol. A final qualification
   artifact binds source, original compiler receipt, wrapper/config, actual
   tool commands and changed guest. Do not call this an official runner guest.
6. Prepare an unchanged-plan three-artifact G4/031/counterfactual paired
   diagnostic for small equality and large search. Timing needs a new explicit
   coordinator START. Placement recovery would show sensitivity to this
   counterfactual, not uniquely prove caller-address causality because later
   code/data placements may shift.

General future loop alignment may use
[llvm.loop.align metadata](https://llvm.org/docs/LangRef.html#llvm-loop-align-metadata),
which requests a positive power-of-two byte alignment from the backend.
[Clang code_align](https://clang.llvm.org/docs/AttributeReference.html#clang-code-align)
is its loop-statement interface. Applying it to all proven natural backedges
would be a separate general-policy candidate with broader layout effects.
