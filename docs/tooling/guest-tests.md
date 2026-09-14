# Guest tests

`mylang test` is the compiler's own runner for tests written in the language. It
checks the project, finds the exported functions whose names begin with `test_`,
builds them natively and runs each one in its own process. Cases are configured
with one JSON file rather than with a framework inside the language, and the
runner needs no Python. The design record is
[the guest test workflow](../experiments/guest-tests.md); `tests/guest_tests.py`
still exercises the older VM comparison runner.

## `mylang test`

The command discovers `test_` functions in the project's reachable public
schema. A parameter-free test returning `bool` asserts `true`; any other result
type needs an explicit expected typed JSON value, so an undeclared expectation is
a configuration error rather than a silent pass. `--cases FILE` supplies
arguments, expectations and skip reasons keyed by qualified test name, and
`--filter GLOB` selects qualified names case-sensitively. Each selected case runs
as a fresh native process bounded by `--max-steps`, `--max-frames`, `--max-calls`
and `--timeout-ms`, with no implicit clock, entropy, filesystem, network or
environment grants. `--json` prints a `native-tests-v1` report instead of the text
summary. Exit status is 0 when every selected runnable case passed, 1 on a
failure or trap, 2 on a setup failure, and 3 when the selection was empty or
entirely skipped — a filter that matches nothing is not a green run.

```console
$ mylang test examples/testing/main.my
passed main::test_square
passed main::test_sum
2 passed, 0 cached, 0 failed, 0 skipped
$ mylang test examples/testing/main.my --filter 'main::test_nothing'
0 passed, 0 cached, 0 failed, 0 skipped
$ echo $?
3
```

## Reusing unaffected results

A successful deterministic case leaves a receipt under `.mylang-cache/tests`, or
under `--cache-dir DIR`. The receipt's identity covers the case settings, the
call signature, the execution limits, the semantic dependency closure the test
actually used, and the compiler and native build environment, so a later run can
report `cached` instead of executing. Editing a helper invalidates the tests that
reach it and leaves the others reusable; whitespace and unrelated edits keep
results valid. Failures, traps and corrupt receipts are always re-executed, and
`--force` re-executes every selected unskipped case. This reuses results and
native objects only: the frontend still checks the whole project on every
invocation.

```console
$ mylang test app/main.my --cache-dir /tmp/test-cache
passed main::test_square
passed main::test_sum
2 passed, 0 cached, 0 failed, 0 skipped
$ sed -i 's/return left + right/return right + left/' app/main.my
$ mylang test app/main.my --cache-dir /tmp/test-cache
cached main::test_square
passed main::test_sum
1 passed, 1 cached, 0 failed, 0 skipped
```

## Isolated source provider fixtures

A case may carry a `providers` object mapping existing dependency `.my` paths to
replacement source text. The runner copies a bounded inventory of the project's
sources into a private directory, applies the replacements there, checks the
result, and verifies that the selected test's parameters, result type and
exported data layouts are unchanged. The original files are never modified. A
fixture cannot replace the test entry or introduce a path the project does not
already have; source snapshots reject symbolic links and are bounded to 16 MiB,
with at most 128 files for a provider snapshot. Invalid fixture source or a
changed public contract is a setup failure, and the fixture settings are part of
the receipt identity, so changing an injected value re-executes the case.

```console
$ mylang test app/main.my
failed main::test_reading: actual value does not match expected value
0 passed, 0 cached, 1 failed, 0 skipped
$ cat cases.json
{
  "main::test_reading": {
    "providers": {"reading.my": "module reading\nexport sample\n\ndef sample() -> int:\n    return 42\n"}
  }
}
$ mylang test app/main.my --cases cases.json
passed main::test_reading
1 passed, 0 cached, 0 failed, 0 skipped
```

## Deterministic provider fixtures

The native runner registers no host callbacks and grants no ambient authority, so
a test that reaches a clock, an entropy source or the environment through a
`host def` declaration fails with `HostMissingRegistration` rather than reading
the real machine. A case makes such a dependency deterministic by replacing the
module that declares it with ordinary guest source returning a fixed value. The
substitution lives in the private snapshot, is captured in the receipt identity,
and is therefore stable across runs and reusable. These are source-level
replacements, not registered native providers: they change what the guest
computes, and they do not validate a real host implementation of the same
declaration.

```console
$ mylang test app/main.my
failed main::test_stamp: HostMissingRegistration

0 passed, 0 cached, 1 failed, 0 skipped
$ cat cases.json
{
  "main::test_stamp": {
    "providers": {"clock.my": "module clock;export now;fn now() -> i64 effects(host) { return 1700000000; }"}
  }
}
$ mylang test app/main.my --cases cases.json
passed main::test_stamp
1 passed, 0 cached, 0 failed, 0 skipped
```
