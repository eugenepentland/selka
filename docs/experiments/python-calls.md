# Generated Python calls

Status: removed. `scripts/bindings.py` is gone, and its example consumer
`examples/domain-codecs/use_calls.py` was deleted on 2026-09-24 because nothing
could generate the module it imports. `selka invoke` is the native way to call
one exported function ([invoking an export](../tooling/invocation.md)). This page
is the design record.

`scripts/bindings.py` now generates typed Python functions for exported effect-free
language functions whose complete parameter/result graphs have wire representations.
The generated module remains standalone for data operations. Calling language code
requires an explicitly selected compiler executable and source project; this is a
subprocess bridge over `invoke-project`, not a native ABI.

Run the checked-in domain example:

```sh
python3 scripts/bindings.py examples/domain-codecs/main.selka --output .zig-cache/domain_bindings.py
PYTHONPATH=.zig-cache python3 examples/domain-codecs/use_calls.py --compiler zig-out/bin/selka
```

Generate bindings with the existing `--compiler` and `--output` options. The module
exposes `CALLS` (qualified function name to generated function), `FUNCTION_NAMES`,
and `UNSUPPORTED_FUNCTIONS` (qualified name to rejection reason). Generated function
names use an `F_` prefix and the existing reversible identifier encoding. Parameters
use a `p_` prefix so language names cannot collide with the positional-only client.
`Client.call(qualified_name, **arguments)` accepts the original language names.

```python
client = generated.Client('/absolute/path/to/selka', '/project/main.selka')
answer = generated.CALLS['math::sum'](client, p_left=20, p_right=22)
# Equivalent: client.call('math::sum', left=20, right=22)
```

`CALL_TYPES`, `CALL_CASES`, and `CALL_FIELDS` include nominal wire representations
needed by calls. A domain with a declared codec gets a frozen class with one `wire`
field, typed as that codec's wire value. Constructing this Python object does not
validate the domain: the compiler executes its declared decoder on every incoming
call argument. Results execute declared encoders before Python reconstructs the
wire objects. Ordinary standalone `dumps`/`loads` continue to reject opaque domains;
there is no bypass exposing or constructing their private language representation.

Each request includes the complete generated public schema SHA-256. Every call
freshly checks the project and rejects a changed schema before running argument
codecs. A body-only source change with the same schema executes the new body.
The selected compiler and sources are trusted inputs; schema compatibility is not
an implementation identity or authentication mechanism.

Language result `err` cases are successful Python result objects. Argument decoder
rejections, guest traps, and compiler failures raise `CallError`, retaining stderr
and exit status. An optional diagnostics callback receives stderr. Host value/JSON
validation raises `CodecError` with a code and JSON path.

`CallLimits` configures shared guest steps, frames, calls, live memory, and traversal
work through the existing compiler flags. Its `json` limits validate request/output
bytes, values, tokens, and depth in Python; the compiler's own JSON limits also
apply independently. Increasing a Python limit does not raise the CLI's defaults.
Timeout and combined stdout/stderr capture thresholds terminate and reap the direct
compiler process. Output goes to temporary files and is polled; the capture limit
is an observed threshold, not a hard disk quota. No shell is used. Temporary request
and capture files are removed on success or failure.

[Declared input manifests](call-inputs.md) can be supplied through `Client.inputs`
and the generator's repeated `--inputs` options. Values are freshly loaded on each
call; generation records their source provenance.

Reference boundaries, effects, resources, and unavailable wire representations
are reported as unsupported instead of generating callable wrappers. Native ABI
bindings, callbacks, and source serialization operations remain pending.

`tests/python_calls.py` exercises generated functions through a real compiler,
nominal domain/result objects, u64 extremes, wrong arguments, typed rejection,
traps, shared budgets, schema/body edits, timeout/capture limits, diagnostic delivery,
missing executables, and wrong output types. Existing data-codec and cache suites
continue to verify standalone use, determinism, cache integrity, and source receipts.
