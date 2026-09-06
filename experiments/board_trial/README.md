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

Implementation exposed two abstraction costs: nominal IDs require explicit
`same` helpers because aggregate equality is unsupported, and fixed optional
slots require separate component/net membership helpers without parameterized
composite types. These are concrete candidates for later language experiments.
The snapshot wrapper keeps host conversion and VM allocation outside ordinary
application code; trusted wrappers still require independent review and tests.

This is development acceptance evidence. No blinded or matched agent repair
attempts have been collected, no relative reliability claim is justified, and
the tiny geometry kernel provides no meaningful routing-performance comparison.
Next prepare equivalent repair tasks and fresh held-out cases, retaining failed
attempts and raw diagnostics/patches. Native guest compilation remains deferred.
