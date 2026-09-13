# Guest test workflow

Run native guest tests directly with the compiler:

```sh
mylang test examples/testing/main.my
mylang test path/to/main.my --qbe /path/to/qbe --filter '*test_*'
mylang test path/to/main.my --cases cases.json --json
```

The command checks the project and discovers exported `test_` functions in its
reachable schema. Each selected case executes QBE native code in a fresh process.
Parameter-free Boolean tests assert `true`; other result types require explicit
expected typed JSON. Tests may call ordinary private helpers. Types appearing in
exported test signatures must also be exported. Python is not a runtime dependency
of this command; the existing `scripts/test_project.py` remains a VM comparison
runner with its original report format.

## Inputs and assertions

`--cases` accepts an object keyed by qualified test name:

```json
{
  "checks::test_pair": {
    "arguments": {"seed": "17"},
    "expected": {"number": "17", "valid": true}
  },
  "checks::test_optional": {"skip": "requires a hardware fixture"}
}
```

Values use typed JSON: integer strings, tagged unions, and record objects.
Expected values compare structurally; object key order does not matter. Booleans
and integer values remain distinct. Named arguments must match the declaration.
A nonempty `skip` reason retains the case in the report without executing it.
Unknown configuration names fail even when a filter would exclude them.
`--filter` matches qualified names case-sensitively with `*`, `?`, and bracket
classes. An empty selection or a selection containing only skips is not a green
run.

## Reusing passed tests

The command retains successful results under `.mylang-cache/tests`; change the
location with `--cache-dir`. An unchanged successful case can report `cached`
without executing again. Cache identities include the case settings, compiler
and native build environment, execution limits, and the semantic dependencies
used by the test. Changing a called helper invalidates its affected tests;
changing an unrelated function can retain their results. Failed tests and traps
execute again. `--force` executes every selected, unskipped case.

This reuses test results and native function objects. The frontend still checks
the project on each invocation; it is not a persistent incremental frontend.
Compilation reads a private copy of the captured sources. Source inventories and
compiler identity are checked before results are published. The inherited
environment is fingerprinted; dynamic-loader overrides disable result reuse.
A failed forced rerun removes its previous successful receipt.

## Provider fixtures

A case may set `providers` to an object mapping existing dependency `.my` paths
to replacement source strings. For example, replace a dependency's
`host fn sample(x:i64)->i64 effects(host);` with
`fn sample(x:i64)->i64{return x+35;}` while retaining its module and exports.

The command copies a bounded source inventory into a private directory, applies
the replacements, checks the resulting project, and verifies the selected test's
parameter/result contract and exported data layouts. Original source files are
never modified. Fixtures cannot replace the test entry or introduce unknown
paths. Source snapshots reject symbolic links and are bounded to 16 MiB; provider
snapshots additionally allow at most 128 source files. Generated directories
(`.mylang-cache`, `.zig-cache`, `zig-out`, `.git`) and the configured result cache
are excluded from source inventories.

These fixtures test guest application behavior through dependency substitution.
They do not register or validate real native host callbacks. Invalid fixture
source or changed public contracts cause setup failures. Fixture settings form
part of the cache identity, so changing an injected value reruns the case.

## Results and controls

`--json` emits a `native-tests-v1` report containing individual test rows and
`passed`, `failed`, `skipped`, `cached`, and `executed` counts. Rows distinguish
`passed`, `cached`, `failed`, and `skipped`, retaining expected/actual values or a
reason and diagnostics when relevant. Exit status is:

- `0`: every selected runnable test passed, including cached successes.
- `1`: at least one test failed or trapped.
- `2`: configuration, checking, compilation, or execution setup failed.
- `3`: no tests matched, or every selected test was skipped.

Use `--qbe`, `--zig`, and `--mode Debug|ReleaseFast` to select native tools and
build mode. `--max-steps`, `--max-frames`, `--max-calls`, and `--timeout-ms` bound
execution. The runner grants no implicit effects or external resources.

`zig build test-native-tests -Dqbe=/path/to/qbe` runs the native CLI acceptance
suite: discovery, typed assertions, traps, filtering, skips, successful-result
reuse, affected helper edits, and provider isolation. `tests/guest_tests.py`
continues to exercise the original VM runner.
