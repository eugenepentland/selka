# Direct C imports

An `extern func` calls a fixed-arity C function from a native build: scalars, text and bytes lent as a pointer and a
length, opaque handles and out-parameters. The C code is compiled with the program through `--link`:

```selka
# doc: check
# Calling libc needs a native build; `selka build main.selka --run` links and runs it.
extern func labs(host: Host, value: i64) -> i64


extern func floor(host: Host, value: float) -> float


func main(host: Host) -> i64:
    return labs(host, -42)
```

```sh
selka build main.selka --run
```

The build links libc and libm. On the supported Linux x86-64 target:

| Language | C |
|---|---|
| `i8`, `i16`, `i32`, `i64` | `int8_t`, `int16_t`, `int32_t`, `int64_t` |
| `u8`, `u16`, `u32`, `u64` | Corresponding unsigned fixed-width types |
| `bool` | `_Bool` / `bool` |
| `float` | `double` |
| `unit` result | `void` result |
| `str` or `bytes` parameter | two arguments, `const uint8_t *data, int64_t length`, lent for the call |
| `-> bytes` result | returns `const uint8_t *` and takes a trailing `int64_t *length`; the runtime copies |
| `extern type T` | an opaque pointer (`T *`, `void *`); `T()` is NULL |
| `mut` integer, `bool`, `float` or `extern type` parameter | a pointer to that type, valid until the function returns |

Use `i32` for C `int`. `unit` parameters are rejected; a declaration whose only parameter is `host` calls a C function
taking no arguments.

The declaration name is the C symbol. An `extern func` named like a prelude function (`abs`) cannot be called bare: declare
it in a module that never calls it bare and call it as `libc.abs(...)` (`E_BUILTIN_FUNCTION_NAME`). Imports of one C symbol
must agree on the signature. There are no aliased symbol names and no automatic header imports. Names starting with
`myl_` or `selka_` are reserved.

## Text and bytes

A `str` or `bytes` parameter, or a slice of one, crosses as two C arguments: a pointer to its octets and their count. The
octets are lent for the call and are not NUL-terminated. A `-> bytes` function returns a pointer and stores the length
through one extra trailing `int64_t *`; the runtime copies the octets before the call returns, so C may free them. A null
pointer with length 0 is the empty value. C text may be invalid UTF-8, so a function cannot return `str`: return `bytes`
and call `strings.decode(data)`.

```selka
# doc: check
# The C side, compiled with `--link`:
#   int64_t count_spaces(const uint8_t *data, int64_t length);
#   const uint8_t *greeting(int64_t *length);
import strings

extern func count_spaces(host: Host, text: str) -> i64


extern func greeting(host: Host) -> bytes


func main(host: Host) -> int:
    const words = count_spaces(host, "a b c") + 1
    match strings.decode(greeting(host)):
        case Ok(text):
            return int(words) + len(text)
        case Err(_):
            return 1
```

A C API that wants a NUL-terminated string needs a one-line C wrapper; a `byte_buffer` crosses as its snapshot
`bytes(buffer)`.

## Opaque handles

`extern type Database` declares a type for a C pointer. A handle crosses unchanged; `Database()` is the null handle, and `==`
and `!=` compare handles. Handles copy like integers and may be stored in records, lists, options, dictionaries and sets.

- Arithmetic on a handle, ordering, converting to or from a number, printing, matching and passing one to a `parallel` task
  are `E_EXTERN_TYPE`. Two `extern type` declarations are different types.
- An `extern type` is private to its module: a `public` record or function that names it needs `public extern type Database`
  (else `E_PRIVATE_INTERFACE`).

```selka
# doc: check
# The C side: sqlite3 *open_db(const uint8_t *name, int64_t length); void close_db(sqlite3 *db);
extern type Database


extern func open_db(host: Host, name: str) -> Database


extern func close_db(host: Host, db: Database) -> Unit


func main(host: Host) -> int:
    const db = open_db(host, "app.db")
    if db == Database():
        return 1
    close_db(host, db)
    return 0
```

A handle is not an owner: nothing closes what it points to. A library that must close it wraps it in a
[`@linear` record](records-and-unions.md#linear-records), whose every owner must be consumed, and ends the owner in its
closing function with `own conn.handle`.

A binding for a C library is a module you write, one file holding the `extern` declarations and the few functions its
callers use. Its opening function returns the `@linear` record and fails when C answers the null handle; its closing
function takes `own conn`. A caller closes on failure with `on fail:`
([cleanup on failure](results-and-options.md#cleanup-on-failure)). A helper that only reads takes its owner plain (`run`
below); `mut conn` writes it, `own conn` closes it.

```selka
# doc: check
# The C side: sqlite3 *open_db(const uint8_t *name, int64_t length); int32_t close_db(sqlite3 *db);
#             int32_t run_db(sqlite3 *db, const uint8_t *sql, int64_t length);
public extern type Database


extern func open_db(host: Host, name: str) -> Database


extern func close_db(host: Host, db: Database) -> i32


extern func run_db(host: Host, db: Database, sql: str) -> i32


@linear
public record Connection:
    db: Database


# The binding's own functions: what a caller imports as `sqlite.open`, `sqlite.run` and `sqlite.close`.
public func open(host: Host, path: str) -> Connection fails str:
    const db = open_db(host, path)
    if db == Database():
        fail "cannot open " + path
    return Connection(db=db)


public func run(host: Host, conn: Connection, sql: str) -> int fails str:
    if run_db(host, conn.db, sql) != 0:
        fail "failed: " + sql
    return 0


public func close(host: Host, own conn: Connection) -> i32:
    const db = own conn.db
    return close_db(host, db)


# A caller: if `run` fails, the clause closes the connection before the error leaves.
func load(host: Host, path: str) -> int fails str:
    mut conn = try open(host, path)
    on fail: _ = close(host, own conn)
    try run(host, conn, "create table t (a)")
    return int(close(host, own conn))


func main(host: Host) -> int:
    const status = load(host, "app.db") else Err(_):
        return 1
    return status
```

## Out-parameters

A `mut` parameter of an integer, `bool`, `float` or `extern type` is a C out-parameter: C receives a pointer to a temporary
holding the place's value, and after the call the place takes the temporary's value. The place may be a local, a record
field or a list element. A function that returns `bytes` takes no `mut` parameter; `mut` text, bytes or aggregates are
`E_EXTERN_SIGNATURE`. A call cannot lend a place's octets and write another part of the same value:
`rows[i].payload[1:]` with `mut rows[i].sum` is `E_SINGLE_OWNER_OVERLAP`; give the call a local `mut` and store it in the
field afterwards.

```selka
# doc: check
# The C side: int32_t open_db(const uint8_t *name, int64_t length, sqlite3 **out);
extern type Database


extern func open_db(host: Host, name: str, mut out: Database) -> i32


func main(host: Host) -> int:
    mut db = Database()
    const status = open_db(host, "app.db", mut db)
    return int(status)
```

## Calls through an address

An `extern func` marked `@address` calls a function with no symbol to link against: a function pointer C handed back, or an
address read at run time. Its target is the value of its parameter after `host`: an `extern type` handle, or a `u32` or
`u64` address. A `u32` works on every target; a `u64` is refused when the target's addresses are 32 bits. Any other type, a
missing target or a `mut` one is `E_EXTERN_ADDRESS`. The other parameters and the result follow a plain `extern func`.

- The call is indirect under the target's C convention with the declared signature, the target not passed. Nothing is
  linked for it.
- A null handle or the address 0 traps `R_FOREIGN_TARGET` before any jump (in a `@freestanding` function, the
  freestanding fault with that code: [freestanding functions](functions.md#freestanding-functions)). Any other value is used
  as given; on `thumbv6m-none` it is a Thumb address with its low bit set.
- A Selka function cannot be handed to C as a callback.

```selka
# doc: check
# The C side: int64_t (*find_op(const uint8_t *name, int64_t length))(int64_t, int64_t);
#             uint64_t op_address(int32_t slot);
extern type Operation


extern func find_op(host: Host, name: str) -> Operation


extern func op_address(host: Host, slot: i32) -> u64


@address
extern func apply(host: Host, op: Operation, a: i64, b: i64) -> i64


@address
extern func apply_at(host: Host, address: u64, a: i64, b: i64) -> i64


func main(host: Host) -> int:
    const sum = apply(host, find_op(host, "add"), 2, 3)
    return int(sum + apply_at(host, op_address(host, 1), 4, 5))
```

## Tests that call C

`selka test --allow-host --link FILE.c` hands the live `Host` to each test that declares a `host: Host` parameter. Without
`--allow-host` such a test fails before it is built, naming the flag. A test with a live `Host` never reuses a recorded
result; its other capabilities keep their stand-ins.

```sh
selka test tests --allow-host --link vendor/sqlite3.c --link shim.c
```

## The host parameter

Every `extern func` takes `host: Host` first (omitting it is `E_HOST_CAPABILITY`); the C ABI drops it. `main` receives `host`
like any capability: `selka run` grants it, and under `--restrict` it needs `--allow-host`:

```console
$ selka run main.selka --link helpers.c --restrict
selka: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-host, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`host: Host?`)
$ selka run main.selka --link helpers.c --restrict --allow-host
```

Arguments follow the SysV x86-64 C calling convention: an `i8` or `i16` argument is sign-extended and a `u8`, `u16` or
`bool` zero-extended to the full register; wider integers, `float` and results pass unchanged. A `float` argument that is
any NaN reaches C as the canonical quiet NaN (`0x7ff8000000000000`); a NaN C returns enters the program unchanged
([NaN payloads](floating-point.md#nan-payloads)).

## Linking your code

`build`, `build --run`, `run` and `test` accept repeatable `--link FILE.c`:

```sh
selka build main.selka --run --link helpers.c
selka build main.selka -o app --link helpers.c --link vendor/crc.c
selka test main.selka --link helpers.c
```

Each `--link` names a C source, relative to the invocation directory, compiled with the build's toolchain and linked after
the program's objects, in command-line order. Object files, archives, shared libraries and library search paths are not
link inputs. A device build (`--target thumbv6m-none`) calls C the same way
([C interop on a device](tooling/native-build.md#c-interop-on-a-device)).

The compiled object is reused only while the source and every header it includes keep their bytes. A source that names a
header through a macro (`#include HEADER`, as SQLite's amalgamation does) is preprocessed on every build. `--verify-cache`
compiles every served `--link` object again and fails when the bytes differ. A test run with `--link` never reuses a
recorded result.

### Project links

A project names its C sources once, in `selka.json`, instead of on every command:

```console
$ cat selka.json
{"version": 1, "links": ["vendor/sqlite3.c", "lib/shim.c"]}
$ selka build examples/hello.selka --run
$ selka test tests --allow-host
```

Each entry is relative to the directory of the `selka.json` (or absolute). `build`, `run`, `run-project` and `test` link the
listed sources first, in order, then any `--link` files (a file named twice is linked once). `check` compiles no C. A listed
file that does not exist stops the build with status 2 and `E_PROJECT_CONFIG`. Listing C grants nothing: a program still
needs `host: Host`, and `--restrict` still withholds it. A package's own C is used only when the application allows it
([packages](tooling/packages.md#c-sources-in-a-package)).

**Known limit.** `__DATE__` and `__TIME__` in a source that names its headers plainly keep the value of the compile that made
the object; `--no-cache` compiles it again. A source that names a header through a macro has no such limit.

## Boundary contract

C code is trusted native code. The handwritten declaration must match the actual C prototype; a linker cannot verify C
types. Foreign calls bypass capability grants other than `host`, and step and frame budgets do not count time spent inside
them; `--timeout` and a test's `--timeout-ms` still apply.

- C must not write through, keep or NUL-scan a `str` or `bytes` pointer, or keep a `mut` pointer: both end when the call
  returns. A `-> bytes` pointer and length must describe readable memory; a negative length, or a null pointer with a
  positive length, traps `R_FOREIGN_RESULT`.
- C must accept any handle it returned, and the null handle wherever its API allows NULL. Selka does not stop a program from
  using a handle after C freed it.

Records, lists, options and unions across the boundary, `str` results, `byte_buffer` arguments, `mut` text, variadic
functions and Selka callbacks are not supported (`E_EXTERN_SIGNATURE`).

A `host func` declaration is `E_HOST_RETIRED`: declare the function `extern func` and link its C implementation.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/c-ffi.md).
