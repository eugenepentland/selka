# Corrected zero-result branch review

**Scoped selector approval:** frozen `279501d17e6eb84b13fa311b7042434a70c2cc5d`
repairs the confirmed `f4b6647d` flag-clobber tail regression. This approves the
reviewed amd64 zero-result branch selection boundary, not the whole runtime,
combined backend gate or performance acceptance.

The guard at corrected `vendor/qbe/amd64/isel.c:610` scans every instruction after
the chosen comparison through the block end and refuses anything other than nop
or dbgloc. It therefore cannot mistake an IR load/copy for a promise about the
flags preserved by its later address materialization. Producer→comparison
adjacency still permits only those same no-code operations. The previous exact
arithmetic result, comparison-derived integer width, literal bit-zero, eq/ne and
single boolean-use checks remain unchanged. Full-width synthetic keepalive remains
in place, and selected arithmetic emits actual add/sub rather than address-only
LEA. Operand swapping is sound for symmetric eq/ne.

Executed independently from committed source with the pinned Zig C compiler:

| Check | Result |
| --- | --- |
| Corrected production fixture, unsigned C assertions and UBSan | 140/140 cases passed |
| Independent 15-function unsigned C oracle, UBSan | 3754/3754 assertions passed; 121 arithmetic input pairs |
| Exact previously failing extern-symbol+8 tail | Exit0, loaded456 and correct branch marker23 |
| Owner's installed corrected QBE on the same exact tail | Exit0, loaded456 and correct marker23 |
| Seven admitted add/sub/word/swapped eq/ne cases | No cmp/test in emitted assembly |
| Independent 24-load pressure case | No cmp/test, 48 stack references; full-width add followed by flag-preserving reload moves before jnz |
| Seven negative/boundary functions | Width mismatch, nonzero comparison, multiple boolean users, intervening call/arithmetic, arithmetic multiuser and address use all retain comparisons |
| Previously failed tail assembly | Both rebuilt and installed corrected artifacts restore cmp after address materialization |

Independent QBE builds use the corrected isel.c blob and every other QBE source
and header from frozen f4. A Git diff verifies isel.c is the only QBE file changed
between those checkpoints. `fixed-receipt.json` records every actual command,
status, stdout and source/artifact SHA256. The owner's installed artifact SHA256
is `df60056d2cdbef23eb6c5dada5249fdaf232bb6e75d4b4799c1626fc67b30819`.
The independent build's different binary hash is recorded with its exact source
paths and C flags; the same failed case also passes the installed owner artifact.

No additional actionable scoped regression was found. The caller condition and
producer result remain live at matching width; integer add/sub wraparound and
high-only bits match unsigned C expectations. Actual spill moves preserve flags,
and allocator edge copies occur in separate blocks. The fixed helper admits only
integer eq/ne, so no signed ordering or floating comparison can reuse these flags.

The rejected parent-control/f4 failure evidence remains unchanged in
`../zero-branch-independent-20260930/`. Initial130 and independent3754 green cases
there did not cover the external-address tail; their recorded success does not
conceal the rejected result. This directory keeps the corrected evidence separate.
The independent review worktree has no tracked compiler/QBE source edits and no
copy.c edits. All builds and executable suites used build-slot admission, and no
reserved timing CPU claim was made. Full combined acceptance remains with root.
