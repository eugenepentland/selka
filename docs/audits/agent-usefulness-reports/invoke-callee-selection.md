# `mylang invoke` cannot execute an export that calls another function

Found while building the I2 composition fixture. Reproduced at `a29e52e8`, before
any of this round's changes, and independent of lists, text or the codec.

## Reproduction

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

$ mylang run --print-result call.my    # the program itself is fine
0
```

`--describe` reports `quad` as `eligible: true, wire_supported: true` with an
`i64 -> i64` contract, because the checked schema is correct. The failure is
entirely in the native build.

## Where it fails

The build lowers only the selected functions. `expandSelection`
(`src/native_test_facts.zig:88`) widens the selection for exactly two reasons:

- an `invoke` expression appears anywhere in a selected body, in which case
  every address-taken function is added; and
- the program declares domain codecs, in which case their methods are added.

It never follows a **direct call**. So for the program above the selection holds
`quad` alone, `twice` is never lowered or emitted, and the emission of `quad`
references a function that is not there.

Traced by instrumenting `lower.zig`'s caller (`validateSelected` at
`src/bytecode.zig:44`) and the four `else => return error.InternalError` sites in
`ProjectCompilation.emitQbeSelected` (`src/project_compile.zig:111`):

- `validateSelected` runs and reports `fn 'call::quad' idx=1 host=false c_abi=false`,
  validates its four instructions and its flow, and returns success;
- the selected loop never prints an entry for `twice`, which is the observable
  form of the missing expansion;
- `emitQbeSelected` fails, and each of its four stages maps every non-`OutOfMemory`
  error to `InternalError`, which is why the report says `InternalError` and
  `ProjectConfigurationFailed` rather than naming the real cause.

## Why it matters

An ordinary exported function that calls a helper is the normal shape of a tool,
so this is not an edge case: it means every composed tool is currently
un-invocable, whatever its types are. It also bounds the two worked examples and
the composition fixture, both of which were written without helper calls as a
result. `tests/invoke/composed.my` says so in its header rather than hiding it.

## Why it was not fixed here

The selection machinery is shared with `mylang test`, whose own suites depend on
it. Following direct callees means walking each selected body's call edges to a
fixpoint, which is a change to a core path that deserves its own round, its own
regression fixture (the program above is the obvious one) and a check that
`mylang test` still selects exactly what it selected before.

The four `else => return error.InternalError` sites are worth a separate look on
their own: they discard the underlying error, so this class of failure can only
ever be reported as `InternalError`.
