# Schema-pinned native Python bindings

Generated Python modules now include `NativeClient` alongside the existing
compiler-process `Client`. Both work with the same typed `CALLS` wrappers and
immutable data classes. Ordinary records, arrays, enum tables, variants, results
and full-width integer/Boolean values use the native value ABI.

```sh
python3 scripts/bindings.py path/to/main.my --output bindings.py
python3 scripts/native.py path/to/main.my --project --library -o libguest.so
```

```python
import bindings

client = bindings.NativeClient('./libguest.so')
value = bindings.CALLS['main::make'](client)
changed = bindings.CALLS['main::change'](client, value)
```

`NATIVE_FUNCTION_NAMES` lists wrappers supported by this client. Public functions
with domain codec, reference/capability or resource signatures remain unavailable
through it; the compiler-process client retains its existing domain codec support.
Native calls need neither source files nor a compiler subprocess after the module
and shared library have been built. The library is explicitly selected trusted
native code loaded into the host process.

Before resolving the invocation API, `NativeClient` checks the library's schema
hash and independently hashes its exact schema JSON. Both must match the generated
module's `SCHEMA_SHA256`. Field order/name, scalar type, case order and public
function contract changes are detected before any guest call. This is interface
compatibility, not implementation authentication: compatible body changes and
source relocation can retain the same schema identity.

Native module emission embeds the public schema from the same checked compilation
and export roots used for its code. `mylang_native_schema_json_v1` and
`mylang_native_schema_sha256_v1` return immutable library-owned strings, can be
queried concurrently and execute no guest code. Their hash uses the exact JSON
bytes excluding the terminating NUL. Single-file libraries with no public schema
return NULL; the Python client reports `NativeSchemaUnavailable`.

`NativeLimits` sets instruction/frame budgets and host value limits. Defaults are
1,000,000 steps, 256 frames, 65,536 nodes and 128 levels; native hard limits remain
100,000 nodes and 128 levels. Calls are synchronous. These limits do not provide
the compiler-process client's wall-clock timeout or process isolation. The output
buffer uses `max_nodes`; insufficient capacity raises `CallError('OutputTooSmall')`
with the required node count. The client never retries a completed guest call
implicitly. Native traps and host failures become `CallError` values with their
native code and available location/frame diagnostics. Language `err` results
remain ordinary typed return values.

The client reuses the existing data validator to enforce Python value types,
integer ranges, complete records/tables and nominal identities. Inputs are copied
into bounded preorder nodes, and outputs become independent immutable Python
values. Native scalar and aggregate APIs share scalar range validation. Loading
a stale library raises `NativeSchemaMismatch`; missing versioned API symbols
raise `NativeABIUnavailable`.

Both Python runtime sources participate in the generator digest and artifact-cache
identity. A generated module is standalone and includes its native transport; no
additional project runtime package is required.

## Acceptance

`tests/native_schema.py` independently compares canonical compiler schemas with
library metadata across field/type/case/export changes, body/private edits,
relocation and both optimization modes. Concurrent queries pass, and a trapping
source entry is never executed by metadata queries.

`tests/python_native_calls.py` compares typed compiler-process and native results
for records, variants, tables, full-width integers and Booleans. It checks snapshots,
traps and recovery, budgets, one-call capacity failures, unsupported domains,
stale/missing schemas and successful calls after source removal. Both drivers
run under `zig build test`. Existing schema, binding generation/cache and native
value acceptance remain part of regression validation.

[Internal native codec invocation](native-codec-dispatch.md) now preserves caller
state and shared budgets. Public native domain conversion, borrowed/capability
invocation and the remaining compilation
and language roadmap work are still unfinished.
