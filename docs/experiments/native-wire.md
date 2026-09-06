# Native ordinary-value calls

`mylang_native_call_values_v1` adds ordinary aggregate inputs and results to
module shared libraries. Include `native_providers.h` and `native_embed.h`, and
build with `scripts/native.py --project --library` as for scalar native calls.
Only resolved public function roots are callable.

`MylangWireNode` contains a type name, 64 scalar/tag bits and a direct-child count.
Nodes form a preorder forest, with one root per function argument. Each subtree
is contiguous. Records use declaration field order; arrays use index order and
enum tables use enum declaration order. Their root bits must be zero. Variants
use the declared case index in bits and zero or one payload child. Integers use
the scalar ABI's unsigned or sign-extended two's-complement representation;
Booleans use 0/1. Every node's type name must match the expected builtin or
qualified nominal/array schema name, with exact counts, tags and ranges.

For a `main::Point` record with fields `x:i64, y:i64`, an argument is:

```c
MylangWireNode argument[] = {
    {"main::Point", 0, 2},
    {"i64", 3, 0},
    {"i64", 4, 0},
};
MylangWireNode output[3];
MylangWireResult result;
int status = mylang_native_call_values_v1(
    "main::shift", argument, 3, output, 3, NULL, &result);
```

The host must use the library's matching schema and declaration order; nominal
names alone are not a schema-version fingerprint. Generated native bindings and
automatic schema pinning remain subsequent work.

Input data is copied into guest storage. Output is copied into caller-provided
nodes before guest cleanup, so no guest allocation escapes. Only type/diagnostic
strings borrow library storage and expire when the library unloads. Input,
output, result and options/provider storage must not alias, and every pointer
must be valid for its declared extent throughout the synchronous invocation.

The result's `execution` contains the existing status, bounded diagnostics and
step count. `node_count` is the output tree length on success. On
`OutputTooSmall`, it reports the required capacity and the output remains
unchanged. The guest function has already executed; the runtime does not retry
it. Other failures leave `node_count` zero. A null output pointer with zero
capacity can obtain the required count, subject to the same execution rule.
A null result pointer returns status 2.

Both input and output are limited to 100,000 nodes and 128 levels including the
root. Oversized buffers/inputs or a deeper tree return `WireLimit`. Scalar,
record, fixed-array/table, enum, packed/boxed union and typed-result shapes are
supported when all children are ordinary supported values. The complete
signature is checked before copying input or executing guest code. Domain
construction, resources, buffers, pools/handles, references and capability
parameters remain opaque and return `UnsupportedSignature`; raw wire values
cannot forge those identities. Domain codecs need a separate native contract.

The API shares the native entry lock, budgets, trap reporting and cleanup.
Failures release partially copied inputs, in-flight variant payloads, guest
frames and results. Subsequent calls begin with fresh guest state.

## Acceptance

`tests/native_wire.py` is wired into `zig build test`. Independent host trees
exercise record snapshots and array replacement, empty arrays, enum tags,
nested packed variants with negative scalar payloads, boxed payloads and empty
cases, typed-result values, malformed types/counts/tags/ranges, partial input
failure, unchanged insufficient output, traps and allocation-failure sweeps.
Address/undefined-behavior sanitizer runs cover -O0/-O2. Separate public-header
hosts link Debug/ReleaseFast shared libraries. Exact 128-level and 100,000-node
calls pass; deeper input/output and oversized input are rejected with recovery.
Compiler allocation-failure coverage includes ordinary and opaque schema output.

The first packed-variant test exposed use of the guest-frame stack-pop helper
while copying inputs before frame creation. Input conversion now consumes its
own newly copied payload directly; the sanitizer regression passes. This was
runtime-test evidence, not a Guardian-discovered bug.
