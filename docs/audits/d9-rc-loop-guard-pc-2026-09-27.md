# Loop guards use their own instruction context

Loop-version guard generation previously inherited the preceding emitted PC.
`headerLabel(head)` writes the guest position but does not update `self.pc`;
`emitInstructions` calls version emission before `emitAt(head)`, and COW entry
emission restores its incoming PC. A speculative body then leaves `self.pc`
at its last emitted operation. New byte-loop operand guards consult physical
proofs indexed by that PC, including dictionary reset-to-backedge refusal.

The correction scopes `self.pc` to the actual loop head before any certificate
or guard work, and restores its incoming value on success, conservative refusal
and error. The production wrapper and mocked guard use the same scoped helper.
No dictionary assertions or optional proof boundaries were weakened. The sole
caller uses only the returned bool to select the original header, then calls
`emitAt(pc)`, which sets the actual instruction PC before physical lowering.
Its preceding header/step emissions do not consult `self.pc`. There is no caller
reliance on the leaked speculative end PC.

This is an actual emitter-context invariant correction, not a claim that the
unchanged benchmark previously failed. A source-only immediate while/while
probe did not establish the dictionary certificate and is retained as a
negative investigation. The permanent adjacent for-loop guest admits five
dictionary empty-drop markers and one byte-loop guard in the same function.
Normal range setup separates those loops; the mock supplies the adversarial
incoming PC directly and verifies head observation and restoration for true,
false and OutOfMemory outcomes.

Source begins with real two-parent merge `1f885cfa` of stable `bca4ac31` and
integration `d1436ed5`. Stable performance artifacts remain unchanged. Candidate
Debug compiler `.tmp-rc/install-loop-guard-pc/bin/mylang` has SHA256
`4897e476a4b56af33dc18a040d60635563bdd90a6f1ba7061bb84eb6040d7393`.

Validation is deliberately focused:

- Twelve PC-filter tests pass (one named invariant test and eleven existing
  always-run blocks);17 byte-filter tests pass (six named plus eleven blocks).
- Full `dict_count` main IL is byte-identical to immutable dictionary-empty
  compiler c5728347; full `bytes_scan` main IL is byte-identical to immutable
  byte-final compiler769ba5b1. These are distinct documented source bases,
  not a claimed combined-predecessor identity or new performance measurement.
- The actual adjacent guest runs on QBE and LLVM O3/full LTO in both GC and RC,
  prints220, and passes its normal/zero/inherited-arena assertions. RC totals
  match across backends:42 heap allocations/retirements,11 arena allocations,
  O11/53, H0, clone0 and uniqueness115.
- Whole-tree Guardian88 passes. This means the88 quality checks; the parent's
  full four-command integration gate was not rerun in this tree.

The merged byte guard mock initially lacked the `pc` field and initialized
neither dictionary proofs nor the new context. Its two fixture initializations
were corrected; the failure log is preserved. The first PC-filter run correctly
refused zero named tests because the module lacked a direct root-test import;
adding that import made the test reachable without an allow-empty override.

Evidence and a read-only verifier are in
`experiments/d9-rc-loop-guard-pc-20260927`. No performance timing or full corpus
was run for this correction. CPU11 remains available for the next approved
measurement. All focused build and guest processes are terminal.
