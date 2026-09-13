# Exported native scalar calls
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Module shared libraries expose `mylang_native_call_v1` in `native_embed.h`.
The compiler passes its resolved public function roots into native emission;
private helpers and internal generic instances are unavailable to the host.
Ordinary exported wrappers can call generic specializations internally.

Build a module entry with:

```sh
python3 scripts/native.py path/to/main.my --project --library -o libguest.so
```

A C host includes `native_providers.h` followed by `native_embed.h` and links the
library. For an exported `fn echo(x:u64)->u64` in module `main`:

```c
MylangScalar argument = {"u64", UINT64_MAX};
MylangCallResult result;
int status = mylang_native_call_v1("main::echo", &argument, 1, NULL, &result);
if (status == 0) {
    /* result.value.type is "u64"; result.value.bits is UINT64_MAX. */
}
```

The scalar representation contains an exact builtin type name and 64 bits.
Unsigned values use ordinary magnitude; signed values use sign-extended
64-bit two's-complement representation. Boolean bits are 0 or 1. The runtime
validates type names, argument counts and ranges before entering the guest
function. A partially copied argument list is released on failure. Returned
bits retain the entire u64 range; use `result.value` for the named-call result,
not the legacy i64 field inside `result.execution`.

The initial ABI supports all eight builtin integer widths and Boolean inputs
and outputs. Unknown or private names return host failure `UnknownFunction`;
public signatures involving nominal aggregates, references or capability
parameters return `UnsupportedSignature`. Malformed scalar input returns
`InvalidArgument`. A null result pointer returns status 2. A zero-argument call
may pass a null argument pointer. Single-file emission has no module export
roots, so named calls are unavailable there.

Execution uses the existing bounded native entry machinery: explicit budgets,
located traps, resource cleanup, allocation-failure recovery and Busy rejection
for overlapping executions of the same generated program. Input pointers are
borrowed for the synchronous call and must remain valid; output storage must
not alias inputs or another active call's output. Diagnostic and returned type
strings borrow library storage. Entry calls and named calls can alternate.

`tests/native_calls.py` checks module visibility (including an exported generic
template whose instances remain private), all scalar boundaries, invalid types
and argument counts, failed partial argument copying, located traps, budgets,
allocation sweeps, recovery and interleaved entry/named calls under -O0/-O2
undefined-behavior sanitization. Separate hosts link against Debug/ReleaseFast
shared libraries using only the public headers. The driver runs under
`zig build test`; compiler allocation-failure tests cover export emission.

This establishes executable public scalar invocation. [Ordinary aggregate values](native-wire.md)
now use a separate bounded wire API. Domain codec invocation at the native boundary,
and borrowed/capability signatures remain unfinished. [Generated native Python
bindings](native-bindings.md) now use the ordinary value ABI with schema checks.
