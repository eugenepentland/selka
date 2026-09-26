# Augmented list-field writeback

The frontend's list-field `+=` special case captured its record, extended the
captured field and emitted no store back. That assumed shared reference behavior;
a physically independent receiver left the destination unchanged. The ordinary
`field_augmented` test exposed this in RC, while a record-snapshot control also
required the corrected writeback in GC value mode.

Value-mode lowering now captures the field before the RHS, extends that list,
saves the resulting value before refreshing the destination, and uses the same
record rebuild/storeback as other augmented assignments. The saved result owns
its value across refresh, which may drop the earlier record temporary. Legacy
sharing keeps its previous lowering.

All six field-augmentation tests pass on GC/QBE with native GC stress, RC/QBE,
and RC/LLVM ReleaseFast (18 fresh executions). New cases cover record snapshots
and an RHS that replaces the field while changing a sibling scalar: the original
captured list wins the augmented assignment, while the sibling change survives.
The focused structural test passes (one named plus eleven imported), and
Guardian passes all 88 checks. Raw output is committed beside this report.

After the independent plain-projection fix was merged, all 22 array-place tests
also passed in each of those three configurations. No additional array lowering
change was necessary. The serialized integration gate remains outstanding.
