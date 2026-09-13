# Direct C imports

QBE native builds support direct calls to fixed-arity C functions. No provider
registration or copied-node adapter is needed:

```mylang
# doc: check
# The interpreter cannot register libc; `mylang build main.my --run` links and runs it.
extern def abs(value: i32) -> i32 effects(host)


extern def floor(value: float) -> float effects(host)


def main() -> i64:
    return i64(abs(-42))
```

```sh
mylang build main.my --run
```

The build driver already links libc and libm. On the supported Linux x86-64
target, the mappings are:

| Language | C |
|---|---|
| `i8`, `i16`, `i32`, `i64` | `int8_t`, `int16_t`, `int32_t`, `int64_t` |
| `u8`, `u16`, `u32`, `u64` | Corresponding unsigned fixed-width types |
| `bool` | `_Bool` / `bool` |
| `float` | `double` |
| `unit` result | `void` result |

Use `i32` for C `int` on this target. `unit` parameters are rejected; an empty
parameter list represents a C function taking no arguments. Foreign floating
NaNs are canonicalized according to the language's ordinary float semantics.

The declaration name is the C symbol. In a module, `math::floor` still links to
`floor`. Imports of the same C symbol must agree on the signature. Aliased symbol
names and automatic C header imports are not implemented. Runtime names starting
with `myl_` or `mylang_` are reserved.

## Linking your code

Both `build` and `test` accept these repeatable flags:

```sh
mylang build main.my --run --link helpers.c
mylang build main.my -o app --link helpers.o --link libhelpers.a
mylang build main.my -o app --library-path ./lib --link-library helpers
mylang test main.my --link helpers.c
```

`--link` accepts C source, object files, archives, or shared libraries. Paths are
relative to the invocation directory. Link inputs retain their command-line
order and follow generated guest objects. Shared libraries must also be
available to the system loader at runtime; `--library-path` controls link-time
search and does not install libraries or add an rpath.

Native function objects remain cached. Every build links again, so changed
external objects and C source are observed. A native test that transitively calls
an extern function always executes; its result is never reused as a cached pass.
Unaffected pure tests can retain their results.

## Boundary contract

Every declaration requires `effects(host)` and may declare additional effects.
These effects propagate through callers and prohibit compile-time execution.
Direct imports work with QBE executable and shared-library builds. The bytecode
VM cannot execute them.

C code is trusted native code. The handwritten declaration must match the actual
C prototype; a linker cannot verify C types. Foreign calls bypass provider grants
and cooperative host-call budgets, and cannot be interrupted by guest instruction
budgets. Native test process timeouts still apply.

This implementation covers scalar calls. Raw pointers, C strings, struct/union
passing, variadic functions, C callbacks, and automatic binding generation remain
future work. Use the existing registered host adapter API for copied structured
data and explicit resource contracts.

Run the focused compiler and native acceptance suite with:

```sh
zig build test-c-ffi -Doptimize=ReleaseFast -Dqbe=/path/to/qbe
```
