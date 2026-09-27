# Unresolved ordinary snapshot from a live mapping field

This is an observed GC/RC parity difference, not an accepted behavior change.
The source creates a live dictionary-values view and then a record containing
both that view and an ordinary dictionary field initialized directly from
`view.mapping`. It changes the record's ordinary dictionary field, then the
original mapping. Output columns are the live values, record snapshot value,
and original mapping value.

| Compiler / mode | QBE output | LLVM O3/full-LTO output |
| --- | --- | --- |
| accepted `f6bea5d9`, GC | `[13] 13 13` | `[13] 13 13` |
| before publication slice `6f7a3a94`, GC | `[13] 13 13` | `[13] 13 13` |
| before publication slice `6f7a3a94`, counting RC | `[13] 11 13` | `[13] 11 13` |
| direct-publication candidate, counting RC | `[13] 11 13` | `[13] 11 13` |

All exits are zero. The before/after RC counters are included in raw stderr;
the snapshot discrepancy predates direct constructor publication. Accepted GC
was built with Debug compiler SHA-256
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.
Every binary's backend was checked in its manifest. Both original sources,
commands, compiler/binary hashes and raw observations are retained.

The initial boolean regression only established a mismatch. An early
interpretation that its live view remained at 7 because of a sticky shared
mark was incorrect: this observable probe shows that GC's ordinary record
field also changes to 13. The likely missing ordinary-snapshot marking at a
direct projected constructor input requires a separate compiler investigation.
No historical-sharing runtime policy follows from this evidence alone.

The constructor-publication regression now keeps an explicit named ordinary
snapshot before building the record, so its H-containing result and projected
input handoff can be tested independently. That isolates the new optimization;
it does not resolve or waive the direct-input discrepancy preserved here.
