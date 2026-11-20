The proposed final source `188da41681162db93c6783bd3bbc7a63ca87bfd6`
failed the unchanged benchmark's qualification and is superseded. Its
ReleaseFast host compiler SHA256 is
`0318af7ee3a913732ab4c44ed13e96ebbb15faa684350a8bd0546224f47ade55`.
All 24 builds completed (eight new RF MyLang guests, sixteen hash-verified
reference copies), and emitted backend receipts confirmed all eight MyLang
backends: LLVM O3/full LTO and QBE non-LTO.

The ordinary full runner stopped on `branch_predictable` before calibration,
warmups or acceptance measurement. Both MyLang guests exit 2 with empty stdout
and stderr at every edge input: size/iterations/seed 2/1/1, 3/7/42 and
17/31/999983 (expected checksums 127, 5859 and 627184). All four unchanged
reference arms pass those three inputs. No complete candidate report was
created, and these binaries have no final acceptance status.

A supplemental numeric-checksum screen of every MyLang edge cell found exactly
six failures out of 240, all for branch_predictable. The remaining 234 numeric
checksums pass; this ad-hoc screen does not independently establish the full
clock protocol or milestone coverage. A same-input compute screen against the
prior `1ec716ce` source passes all twelve compute cases on both backends.

The frozen compute source routes kind2 and kind3 through the same short-circuit
`or` condition. Kind2 fails while kind3 passes. Root's subsequent investigation
identified an unsound P2 comparison fold when a control-flow edge enters the
shared final conditional jump without executing the immediately preceding
comparison. The repair and its regression tests require a new source identity;
this archive records the pre-repair failure, not evidence for that repair.

The archive preserves compiler source/build/assets receipts and logs, all guest
build commands/source/binary hashes, emitted backend/archive hashes, the failed
full-run log and exact failure commands/raw streams. An initial unsupported
runner `--qbe` flag was rejected during CLI parsing and is separately preserved;
it made no guest builds or measurements. All supplemental guest invocations
used CPU2 and the global timing flock, and are correctness diagnostics only.
Frozen ports, 80 historical targets and baseline results were unchanged.

Archive SHA256: `22152cdefaa6130592734ffb37bc6fc5371ad8a5cbc71bd01b37b0194dab9a89`.
