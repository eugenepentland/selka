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

A test case may set `providers` to an object mapping existing dependency `.my`
paths to deterministic replacement source strings. The runner copies a bounded
source snapshot, replaces those modules, checks it, and pins the resulting schema
before invoking the test in a fresh VM. For example, replace a dependency's
`host fn sample(x:i64)->i64 effects(host);` with
`fn sample(x:i64)->i64{return x+35;}` while preserving its module/export declarations.
This tests application behavior through ordinary guest dependency injection; it
is not a test of the real host callback ABI or provider implementation.

Provider fixtures cannot replace the test entry, introduce unknown source paths,
change its parameter/result contracts or alter exported data layouts. The report
includes `provider_snapshot_sha256`; original source files remain unchanged.
Different fixtures can model deterministic success, failure and boundary values
without a custom Zig test host. The fixture and test must themselves check; an
invalid fixture is an infrastructure failure, never an application test failure.
