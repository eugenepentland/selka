# Recovery of missing expected-output files

At 2026-10-13 01:42 UTC, the final VM trees RSS block lost access to
`trees.vm.out` under another worktree's `.mylang-cache/lox/bench/expected/`.
The complete expected-output directory had disappeared. The original cause of
that external deletion is unknown; this run did not remove it.

The journal preserves one full RSS round and a second candidate observation,
then `FileNotFoundError` failures while reading the expected output. The final
identity check also failed, so no successful receipt was emitted. Both runtime
and counter drivers stopped rather than silently retrying. Their logs and the
partial block are preserved under `interrupted-attempt/`, with the prior harness
versions. No completed timing receipt was changed.

All 26 expected outputs have byte-identical copies in the tracked historical
full-size counter inputs. `manifest.json` pins each original logical path, its
preexisting SHA256, the historical copy and the recovered file under `expected/`.
All 24 missing paths already used in this run also match the hashes in its fresh
completed receipts; the two not-yet-run VM cases match their frozen historical
input pins. No expected values were inferred from a new candidate execution.

`input_recovery.py` resolves only those 26 explicitly pinned paths and rechecks
the replacement hash on every read. A recreated original must also match its
pin. Missing unlisted files and changed bytes still fail. Runtime specs keep
their original logical identities so all previous wall chunks remain unchanged;
new receipts explicitly identify the recovery manifest and resolver. New counted
specs relocate only the expected-output path and its matching identity entry,
recording the original spec hash. No other worktree was written.

The frozen `measure.py` and its wrapper are part of the original input identity set. An
initial resume correctly refused its changed hash before launching any guest;
that journal is also preserved. Its bytes are restored unchanged, and the
recovery implementation lives separately in `measure_recovered.py` and
`measure_cell_recovered.py`. The recovered wrapper
dispatches the explicit new harness, whose own hash and recovery metadata are
recorded in new receipts. The report accepts and validates the two named harness
versions; it does not relabel either version's measurements.

The entire incomplete VM trees three-round RSS block is repeated for every
eligible arm. The nine existing wall samples are retained exactly, no runtime
sample is replaced, and the previous checked arm's inherited timeout remains.
This is an explicit infrastructure recovery, not a selective timing rerun.
The original partial RSS observations stay available but are excluded from the
three-observation final RSS summary.

`resolver-checks.json` covers pinned recovery, replacement tampering, changed
originals and missing unlisted paths. The eight deadline tests are rerun after
the harness change; see `recovered-deadline-tests.log`. Source, compiler and guest binaries
are unchanged, so the existing application and registered qualification still
apply. The final report discloses this recovery.
