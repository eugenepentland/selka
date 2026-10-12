# A01 exact-feature qualification

Source commit: `3c8c494758221d8d1f3dce6f65a05dce3ada5868`.
Compiler SHA256: `a0840db3f813f2bb4dd37447fd3778435ba826ea3d24101c4351c1e73f1beb7f`.
This is the A01 worker compiler, not integrated C1.

All 54 native executions passed: combined maps, stored/nested Result maps, and
precise trapped-item diagnostics, each under six pipelines at 1/2/8 workers.
Thirty normal counted executions have zero RC events and zero exit-live managed
bytes. All eighteen LLVM/symbol audits are RC-free. Nine ThreadSanitizer runs
passed, including the expected fatal trap at item 17. Fatal traps are not claimed
as leak-free normal exits. The unhandled Result list refuses with E_RESULT_UNHANDLED.

The cycle regression was also proved by a controlled mutation: temporarily restoring
unconditional nominal-property memoization makes its Second.requires_handling
assertion fail. Restoring the committed fix passes eight frontend checks. The
private compiler was rebuilt only after restoration; result-source-v4.json records
source hashes, compiler identity and red/green statuses.

`results.json` contains every command, output, checksum and structural result.
`qualify-v4.py` snapshots the consumed harness; its runnable current location is
the parent A01 directory. `finalize-result.py` records the executed mutation, restore,
rebuild and qualification sequence. Gzipped logs/counters preserve their exact bytes
with timestamp 0. sha256.json records all archived artifact identities.

V3's separate 100 release+100 TSan stress repetitions remain in result-evidence-v3;
they are not relabeled as v4. The runtime/task code is unchanged between those
compilers; v4 includes the final symbolic cycle check. Final C1 measurements and
ordinary-command/default/retirement qualification still belong to the coordinator.
