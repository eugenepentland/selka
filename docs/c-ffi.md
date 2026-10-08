# Direct C imports

An `extern def` calls a fixed-arity C function with scalar arguments directly from a
native build. No adapter or registration is needed; the C code is compiled with the
program through `--link`:

```mylang
# doc: check
# Calling libc needs a native build; `mylang build main.my --run` links and runs it.
extern def abs(host: Host, value: i32) -> i32 effects(host)


extern def floor(host: Host, value: float) -> float effects(host)


def main(host: Host) -> i64:
    return i64(abs(host, -42))
```

```sh
mylang build main.my --run
```

The build links libc and libm. On the supported Linux x86-64 target, the mappings
are:

| Language | C |
|---|---|
| `i8`, `i16`, `i32`, `i64` | `int8_t`, `int16_t`, `int32_t`, `int64_t` |
| `u8`, `u16`, `u32`, `u64` | Corresponding unsigned fixed-width types |
| `bool` | `_Bool` / `bool` |
| `float` | `double` |
| `unit` result | `void` result |

Use `i32` for C `int` on this target. `unit` parameters are rejected; a declaration
whose only parameter is `host` calls a C function taking no arguments.

The declaration name is the C symbol. In a module, `math::floor` still links to
`floor`. Imports of the same C symbol must agree on the signature. Aliased symbol
names and automatic C header imports are not implemented. Runtime names starting
with `myl_` or `mylang_` are reserved.

## The host parameter

Every `extern def` takes `host: Host` as its first parameter and declares
`effects(host)`, and may declare more effects; omitting either is
`E_HOST_CAPABILITY` or `E_HOST_EFFECTS`. The checker verifies the `host` argument at
each call, and the C ABI drops it before the foreign call, so the C function sees
only the remaining arguments. The effects propagate through callers and keep the
call out of compile-time evaluation. `main` receives `host` like any capability:
`mylang run` grants it, and under `--restrict` it needs `--allow-host`:

```console
$ mylang run main.my --link helpers.c --restrict
mylang: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-host, or drop --restrict to grant every capability
$ mylang run main.my --link helpers.c --restrict --allow-host
```

Arguments follow the SysV x86-64 C calling convention exactly as a C caller passes
them: an `i8` or `i16` argument is sign-extended and a `u8`, `u16` or `bool`
argument zero-extended to the full register, so a C callee that reads the widened
register sees the value. Wider integers, `float` and results pass unchanged.

A `float` argument that is any NaN reaches C as the canonical quiet NaN
(`0x7ff8000000000000`), so foreign code that reads a double's sign or payload
(`copysign`, `signbit`, a byte copy) sees one value; a NaN a foreign function returns
enters the program unchanged, like any produced NaN
([NaN payloads](floating-point.md#nan-payloads)).

## Linking your code

`build`, `build --run`, `run` and `test` accept repeatable `--link FILE.c`:

```sh
mylang build main.my --run --link helpers.c
mylang build main.my -o app --link helpers.c --link vendor/crc.c
mylang test main.my --link helpers.c
```

Each `--link` names a C source, relative to the invocation directory; it is compiled
with the build's toolchain (`zig cc -c`, at the build's optimization level and CPU)
and linked after the program's objects, in command-line order. Object files,
archives, shared libraries and library search paths are not link inputs:
`--link-library` and `--library-path` were retired with host functions.

The compiled object is cached in the build's `foreign-v1` store and reused only
while the source and every header its compiler depfile listed keep their bytes; a
file that changes while it compiles pins nothing. A build that replays its last
identical build rechecks the same files ([native builds](tooling/native-build.md#the-caches)).
A test run with `--link` never reuses a recorded result.

## Boundary contract

C code is trusted native code. The handwritten declaration must match the actual C
prototype; a linker cannot verify C types. Foreign calls bypass capability grants
other than `host`, and step and frame budgets do not count time spent inside them;
`--timeout` and a test's `--timeout-ms` still apply.

A test cannot call an `extern def`: no test is ever handed a `Host`.

This covers scalar calls. Aggregate parameters and results (records, arrays, unions,
`str`, collections, capabilities) and `mut` parameters are rejected by the checker
(`E_EXTERN_SIGNATURE`, `E_MUTATION_MARKER`); raw pointers, C strings, variadic
functions, C callbacks and automatic binding generation remain future work.

`host def` declarations, registered host adapters, `--library`, `--provider` and
the host applications built on them were retired in S5 (2026-10); `extern def` with
`--link` is the C interop that remains. A `host def` is refused at check time with
`E_HOST_RETIRED`: declare the function `extern def` and link its C implementation.
