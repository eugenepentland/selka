# D9 Lox property assignment RHS preservation, 2026-09-26

The class-free tree interpreter retained an `InstanceObj` snapshot while
running the right-hand side of a property assignment. If that expression
changed another field on the same object, the outer assignment wrote its old
fields table back and lost the inner change. Both native backends reproduced
this migration bug; the original class port preserved the change.

For example, `box.keep = 1; box.value = rhs();`, with `rhs` assigning
`box.keep = 9` and returning 7, incorrectly printed `1, 7` afterward. It now
prints `9, 7`, matching the original tree and VM engines.

The setter still validates the receiver before evaluating the RHS. It then
reads the current instance from the receiver retained on the value stack,
so RHS mutations survive and rebinding the variable used to name the
receiver does not redirect the outer assignment to another object.

## Migration and regression coverage

The fix and two guest regressions are in `lox-value-port.patch`, including
the existing native-clock provider entries required by the driver tests.
`lox-source-perf.patch` is regenerated against that corrected base. Both
`apply-lox.sh WORK` and `apply-lox.sh WORK --optimized` reconstruct their
respective expected source modules and cases byte for byte.

`test_run_set_rhs_keeps_receiver_mutations` checks the lost-field example.
`test_run_set_rhs_keeps_original_receiver` also rebinds the receiver variable
inside the RHS while mutating the original object. Both tests fail against
the pre-fix migrated interpreter and pass after the fix. They pass with
native GC stress in both semantics modes, on both the base and optimized
migrations. Standalone observations additionally check both backends, both
engines, both modes and Lox GC stress on/off with native GC stress throughout:
32 corrected observations and 16 original-baseline observations, all matching.
[Regression evidence](evidence/d9-lox-set-rhs-regressions.json.gz) retains the
negative results, positive test logs, source hashes and observations.

The optimized port also passes all 65 tests in each mode, all 104 smoke runs
(13 scripts × two engines × two backends × two modes), and all 184 stressed
tree error-trace comparisons:
[validation evidence](evidence/d9-lox-set-rhs-runs.json.gz).
Value-mode validation uses frozen Debug compiler `f8dad8e8`; compatibility
uses the prepared default candidate's `--legacy-sharing`. Exact compiler and
guest hashes are retained in the evidence. This is a source migration
correctness fix, not a performance acceptance claim. The joined candidate's
full gate remains the integration task.

## Reproduction

Scratch and logs are retained in worktree `d9-lox-set-rhs/.tmp-rhs/`.
`scripts/build-slot.sh build env TMPDIR="$PWD/.tmp-rhs" python3 .tmp-rhs/build-test.py`
runs the 65-test mode checks, focused native-GC-stress regressions and both
backend builds. `check-runs.py` runs smoke and tree trace comparisons;
`probe-runs.py` runs the 48 standalone observations.

The focused regression command is:

```console
COMPILER test .tmp-rhs/port/driver_tests.my --cases .tmp-rhs/port/driver_cases.json --filter test_run_set_rhs --value-semantics --max-steps=10000000 --gc-stress --cache-dir OWN_CACHE
```

Use `base-port` for the corrected base migration and `before-tests` for the
negative control. The compatibility run substitutes `--legacy-sharing`.
`regression-before.log` records the expected two failures; the corresponding
positive logs record two passes each.
