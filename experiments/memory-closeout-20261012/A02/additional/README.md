# Additional A02 fixture migration

The additional reservation contains all 21 files from A10's `additional-migrations-A02.md`. Original source files, SHA-256 hashes, test names and source sizes are preserved in `originals/` and `originals.json`. These are in addition to the 51-file library/value-semantics reservation, not a replacement denominator.

The migration makes independent snapshots and borrowed returns explicit. Evaluation order stays observable: `f2_index` computes the existing upper bound before borrowing the list mutably; `v_methods` executes the earlier mutating named argument before the later list argument; the self-appending byte-buffer cases copy their prior input bytes before mutation. Tests, expected values, intentional errors, and bounds/property failures remain present. `ce_appends` gains two lines before its budget trap; the coordinator must update that registered source-location expectation from line 60 to 62, column 17.

Support4 (`66890fbc5135a771e6a423724d13c30018ab717f`, compiler SHA-256 `4cc05e8799be27e86c5efa1083a24d53d36682e60358a9246d15596eb9aac375`) admits all 21 migrated sources. The first check admitted 20; the follow-up admits `f2_index` after the local upper-bound binding. These are source checks, not successful native qualification.

`qualify_additional.py` compares original sources on C0 ordinary mode with migrated sources on the supplied integrated checked-ownership compiler. It preserves all deterministic main-program output and failure codes; guest-test fixtures retain their expected successful tests, property failures, shrunk byte-buffer counterexamples and runtime traps. Counted successful main programs require no RC events, no managed exit-live bytes and clean RC symbols. Native execution of this complete comparison remains pending. Historical RC-specific counter assertions in registered Core tests need coordinator/A09 review; this source migration does not silently replace them.

See `../migrations/current-ledger-draft.json` for the combined source burden and pending qualification status. This is a reviewable migration, not milestone 1, 2, or 3 qualification.
