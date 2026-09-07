# Guest test workflow

Run `python3 scripts/test_project.py path/to/main.my --filter '*test_*'`.
The tool discovers exported `test_` functions in the checked reachable graph.
Parameter-free Boolean tests assert `true`. Every case executes in a fresh VM;
no resources or effects are granted by this runner. Tests can call ordinary
private helpers. Public types in test signatures must also be exported.

For structured assertions and deterministic inputs, pass `--cases cases.json`:

```json
{
  "checks::test_pair": {
    "arguments": {"seed": "17"},
    "expected": {"number": "17", "valid": true}
  },
  "checks::test_optional": {"skip": "requires a hardware fixture"}
}
```

Values use the existing typed JSON encoding (integer strings, tagged unions,
record objects). Expected values compare structurally; object key order is
irrelevant. Non-Boolean results require an explicit expectation. Skips carry
reasons. Unknown configuration names fail rather than silently disabling tests.
Inject deterministic data as arguments; custom capability provider injection is
not yet supported by this CLI.

The JSON report contains source locations, expected/actual values, compiler
trap diagnostics and the navigation snapshot identity. Exit 0 means at least
one case ran and every executed case passed; 1 means a failed case; 2 means a
runner/setup failure; 3 means an empty selection or all cases skipped. Case
reports distinguish assertion failure, trap, infrastructure failure and skip.
Source/compiler changes invalidate the run. Each invocation has a million-step
VM limit and a 60-second host deadline. Nothing accepts unchecked source.

`tests/guest_tests.py` covers discovery, scalar and structured comparisons,
explicit inputs, filtering, skips, traps, locations, and invalid source.
