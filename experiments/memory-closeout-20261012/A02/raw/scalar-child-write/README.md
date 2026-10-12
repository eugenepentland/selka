# Scalar child writes after nested owned updates

The unchanged A03 `v_nested.my` oracle and its reduced sequence previously passed
source checking but failed native compilation in all five modes. At the scalar
field write, two reads of the same parent field occupied different blocks. The
exact element-field rewrite could not prove matching list references before the
existing field-read merge ran. Later store narrowing left a stale whole-record
reconstruction, which introduced a retain and `E_ZERO_RC_LOWERING`.

The production patch is three lines in `own.functionWithScratch`: run the existing
`mergeFieldReads` before `elements.fieldStores` for checked zero-RC mode. Its parent,
field, dominance, reachability, and borrow proofs are unchanged. The later merge
remains because borrow forwarding can introduce new record reads. No new equality
rule, ownership waiver, source migration or COW fallback was added. A07 reviewed
this exact ordering change. A08 was notified of the extra normalization pass so
final compilation measurements consume the changed compiler.

The root-authored test registration selects `a02_scalar_child_test.zig`. It runs the
byte-for-byte frozen original oracle (`302 2`, then `550278 1 1`), the unchanged
reduced sequence (exit0), and an independent dynamic-index/snapshot control in all
five modes. Durable native evidence also checks compiler/binary/LLVM hashes,
RC0/live0, symbols, invalid-index trap ordering, and an overlapping-borrow source
refusal. The dynamic control prints `rhs` before `R_LIST_BOUNDS` in both checked
and ordinary modes; its explicit old snapshot stays independent after mutation.
Ordinary controls are release/debug semantic and leak checks, not RC0 claims.

`registered.json` identifies the integrated base, tested source hashes, exact
compiler binary, focused commands, pinned Zig, and independently owned Support6
component directory. `summary.json` gives totals; compressed native JSON preserves
all raw commands, counters and output. Admission logs record bounded per-mode
leases. This local qualification does not substitute for the coordinator's final
integration gate or qualify C2/C3 packaging/default selection.

No speed, allocation-saving, RSS, or compiler-time claim is made. The first local
control source used the wrong conditional syntax; that test-only typo was corrected
and the focused suite rerun. Production remained the same three-line patch.
