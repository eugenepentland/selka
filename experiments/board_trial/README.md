# Executable board-validation trial

The ten modules in [`src/board_trial/guest/`](../../src/board_trial/guest/) implement the [fixed contract](contract.md) on the
bytecode VM. `geometry::overlap` is the sole host operation: a handwritten Zig
wrapper accepts copied nominal rectangles and returns a declared contact/error
result. [`baseline.zig`](../../src/board_trial/baseline.zig) independently implements the same traversal and admission
policy in Zig. Both use the small rectangle kernel; the Python oracle uses a
separate interval/set implementation. Neither is a full production EDA DRC.

Run the default interpreter acceptance suite:

```sh
zig build test --summary all
```

For a focused comparison after `zig build`:

```sh
python3 tests/board_trial.py --runner zig-out/bin/board-trial --compiler zig-out/bin/mylang
```

The grader strips expected answers from all inputs before invoking the runner.
It compares VM and Zig outcomes separately with all 87 previously fixed cases,
including callback counts and exact first-violation locations. Another 60 cases
check translation and identity-renaming invariance. Eighteen malformed transports
must fail without emitting a report, including duplicate JSON keys, floats,
booleans in integer positions, unknown fields and oversized collections.
[`tests.zig`](../../src/board_trial/tests.zig) exercises allocation-failure cleanup, fresh callback sessions after
typed failure, nominal/capacity rejection and endpoint checks before arithmetic.
Three seeded source edits assert located identity/unit type errors and an
exhaustiveness error with its related new-variant declaration. These are checker
regressions, not recorded repair attempts. The oracle and its five self-tests
remain unchanged.

The executable accepts a file containing a JSON array of
`{"name": ..., "input": ..., "unavailable": false}` requests. Each output row has
`name`, `guest` and `baseline`; observations contain `outcome` and `calls`.
Input/output definitions are in the contract. A runner error is a failed trial,
not a successful guest report. The runner embeds guest source at build time;
rebuild it after source changes.

## Findings and limits

Distinct IDs and units, exhaustive feature matches, typed failures and explicit
host effects are usable in this bounded application. Input checking runs before
geometry, and a geometry failure discards the partial successful report.

Implementation exposed two abstraction costs. Scalar domains now support ordinary
`==` and `!=`, removing the two nominal-ID `same` helpers while preserving ID
isolation. One `Slot<T:copy>` now replaces five optional unions for component IDs, net IDs,
regions, features and first violations. One `has<T:equality>` helper replaces the
separate component/net membership loops. Concrete slot instances still retain
exact payload identities; the trusted snapshot boundary rejects putting a net ID
in a component slot. This removes 34 guest-source lines while preserving the
fixed contract and independent oracle results. Separate component/net validation
functions retain their distinct factories and error cases.
The snapshot wrapper keeps host conversion and VM allocation outside ordinary
application code; trusted wrappers still require independent review and tests.

This is development acceptance evidence. No blinded or matched agent repair
attempts have been collected, no relative reliability claim is justified, and
the tiny geometry kernel provides no meaningful routing-performance comparison.
The [repair-study harness](repair/README.md) prepares five task pairs, retains
failed checks and patches, and grades shared fresh cases after both submissions
are sealed. Its known-answer fixture restorations validate the harness; actual
agent repair attempts remain pending. Native guest compilation remains deferred.

The optional-slot consolidation passes the same 147 comparisons, 18 malformed
transports and three seeded diagnostic checks. All five Zig boundary tests pass
in Debug and ReleaseFast, and all ten repair-harness fixture tests pass. Guest/Zig
formatting, gated installation and all 88 Guardian checks pass with violation
baselines disabled. Public generic schema exports remain separate compiler work;
the trial's handwritten host boundary uses the checked concrete runtime schemas.
