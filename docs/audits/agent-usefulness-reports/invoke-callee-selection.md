# `mylang invoke` skipped the target's call closure

Found while building the I2 composition fixture and fixed in the round that added
`INVOKE-11`. Kept as a record of the mechanism, because the failure was reported
as a bare `InternalError` and gave no hint of where to look.

## Symptom

```python
module call


public def twice(value: i64) -> i64:
    return value * 2


public def quad(value: i64) -> i64:
    return twice(twice(value))


def main() -> int:
    return 0
```

```console
$ mylang invoke call.my --function 'call::twice' --input=value.json   # {"value":"3"}
{"status":"completed", ... "value":"6" ...}

$ mylang invoke call.my --function 'call::quad' --input=value.json
mylang: host failure: InternalError
{"status":"setup-failure", "failure":{"kind":"setup-failure",
 "reason":"the selected export could not be built into a native library",
 "diagnostics":"ProjectConfigurationFailed"}}

$ mylang run --print-result call.my
0
```

`--describe` reported `quad` as `eligible: true, wire_supported: true` with an
`i64 -> i64` contract, because the checked schema was correct all along.

## Mechanism

`invoke_execute.build` wrote a selection file naming **only the target**, then ran
the selective emitter. A selective build lowers exactly the functions the file
names, so `twice` was never lowered and the emission of `quad` referenced a
function that did not exist.

The native-test path never had this problem: its planner computes a transitive
closure over the manifest's `test_dependencies` edges and writes every symbol in
it. `mylang invoke` reused the same executor but not the closure, so only the
invoke route was affected — which is why guest tests calling helpers passed
throughout while `invoke` could not build one.

Diagnosis took four probes because the failure is reported twice-removed:

- `emitQbeSelected` maps every non-`OutOfMemory` error from four separate stages
  to `error.InternalError`, so the underlying cause is discarded;
- `native_test_session` maps the child's exit code 2 to
  `ProjectConfigurationFailed`, so the response names a stage rather than a cause.

Instrumenting `validateSelected` (`src/bytecode.zig`) first showed validation
succeeding, with a selected-function loop that printed `call::quad` and never
printed `twice` — which is the observable form of the missing expansion.

## Fix

`invoke_execute.selection` now resolves the target's symbol from the manifest and
runs the same `native_test_plan.plan` closure the test path uses, then writes
every name in it. A target the manifest does not carry is refused rather than
written, because the selection is what the emitter trusts.

Guarded by `tests/invoke/calls.my`, which is deliberately minimal — one helper
called twice from one expression, and a third function that reaches it only
through the second, so a one-level closure fails the fixture as surely as no
closure at all.

## Still worth a look

The four `else => return error.InternalError` sites in `emitQbeSelected`
(`src/project_compile.zig`) discard the underlying error, so this whole class of
failure can only ever be reported as `InternalError`. Nothing here depends on
that being fixed, but it cost most of the time this took.
