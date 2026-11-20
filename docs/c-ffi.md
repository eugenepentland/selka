# Direct C imports

An `extern func` calls a fixed-arity C function directly from a native build: scalar
arguments, text and bytes lent as a pointer and a length, opaque handles and
out-parameters. No adapter or registration is needed; the C code is compiled with the
program through `--link`:

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

The build links libc and libm. On the supported Linux x86-64 target, the mappings
are:

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

Use `i32` for C `int` on this target. `unit` parameters are rejected; a declaration
whose only parameter is `host` calls a C function taking no arguments.

The declaration name is the C symbol. In a module, `math::floor` still links to
`floor`. So an `extern func` named like a prelude function (`abs`) cannot be renamed:
a bare `abs(...)` always reads as the builtin, so declare it in a module that never
calls it bare and call it as `libc.abs(...)` from the others
(`E_BUILTIN_FUNCTION_NAME`, `examples/c-ffi`). Imports of the same C symbol must agree on the signature. Aliased symbol
names and automatic C header imports are not implemented. Runtime names starting
with `myl_` or `selka_` are reserved.

## Text and bytes

A `str` or `bytes` parameter, or a slice of one, crosses as two C arguments: a pointer to
its octets and their count. The octets are lent for the call; they are not NUL-terminated.
A `-> bytes` function returns a pointer and stores the length through one extra trailing
`int64_t *` argument; before the call returns, the runtime copies that many octets into a
new `bytes` value, so C may free or reuse its memory afterwards. A null pointer with length
0 is the empty value. C text may be invalid UTF-8, so a function cannot return `str`:
return `bytes` and call `strings.decode(data)`.

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

A C API that wants a NUL-terminated string needs a one-line C wrapper that copies the
octets into a terminated buffer; a `byte_buffer` crosses as its snapshot `bytes(buffer)`.

## Opaque handles

`extern type Database` declares a type for a C pointer. A handle crosses unchanged in both
directions; `Database()` is the null handle, and `==` and `!=` compare handles. Handles are
copied like integers and may be stored in records, lists, options, dictionaries (as keys
and values) and sets; `take` leaves `Database()`, and a record field may default to it.
Selka code cannot do arithmetic on a handle, order handles, turn one into a number or a
number into one, print it, match it or pass it to a `parallel` task (`E_EXTERN_TYPE`).
Two `extern type` declarations are different types, so a `Statement` cannot be passed
where a `Database` is expected. An `extern type` is private to its module like any other
declaration: a `public` record or function that names it in a field or a signature needs
`public extern type Database`, or the check says `E_PRIVATE_INTERFACE` at that field, with a
note at the `extern type` line.

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

A handle is not an owner: copying one copies the pointer, and nothing closes what it points
to. A library that must close it wraps it in a [`@linear` record](records-and-unions.md#linear-records),
whose every owner must be consumed, and ends the owner in its closing function with
`own conn.handle` (a `mut` parameter and a `match mut` lend the owner without ending it):

```selka
# doc: check
extern type Database


extern func open_db(host: Host, name: str) -> Database


extern func close_db(host: Host, db: Database) -> i32


@linear
record Connection:
    db: Database


func connect(host: Host, name: str) -> Connection:
    return Connection(db=open_db(host, name))


func disconnect(host: Host, own conn: Connection) -> i32:
    const db = own conn.db
    return close_db(host, db)


func main(host: Host) -> int:
    const conn = connect(host, "app.db")
    return int(disconnect(host, own conn))
```


The compiler ships no `sqlite` module or any other binding for a C library: the binding is a module you write, usually
one file (`sqlite.selka`) that holds the `extern` declarations and the few functions its callers use, so that a caller
imports `sqlite` and writes `sqlite.open(host, path)`. Its opening function returns the `@linear` record and fails
with a message when C answers the null handle, and its closing function takes the owner (`own conn`) and ends it
with `own conn.db`, as above. A caller closes the connection on a failure with `on fail:`: after `mut conn = try
sqlite.open(host, path)` it writes `on fail: _ = sqlite.close(host, own conn)`, so a later `try` that fails closes
the connection before its error leaves ([cleanup on failure](results-and-options.md#cleanup-on-failure)). The
binding's module, and a caller below it in one file, look like this (`public` is for a binding in a file of its own):

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

A helper that only reads a handle takes its owner plain, a read-only loan for the call: `run` above, called as
`run(host, conn, sql)` with no marker; `mut conn` is for a helper that writes or replaces it, and `own conn` for the
one that closes it ([linear records](records-and-unions.md#linear-records)).

## Out-parameters

A `mut` parameter of an integer, `bool`, `float` or `extern type` is a C out-parameter: C
receives a pointer to a temporary that holds the place's current value, and after the call
the place takes the temporary's value. The place may be a local, a record field or a list
element, spelled as for any `mut` argument. A function that returns `bytes` takes no `mut`
parameter, and `mut` text, bytes or aggregates are refused (`E_EXTERN_SIGNATURE`). A call
cannot lend a place's octets and write another part of the same value at once: passing
`rows[i].payload[1:]` together with `mut rows[i].sum` is refused by the overlap rule M5
(`E_SINGLE_OWNER_OVERLAP`); give the call a local `mut` and store it in the field afterwards.

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

Some C functions have no symbol to link against: a C library hands back a function pointer
(a callback table, a plug-in's entry), or the address is read from a table at run time (a
boot ROM's routines). An `extern func` marked `@address` calls such a function: its target
is the value of its parameter after `host`, not a symbol of a `--link` file. The target is
either an `extern type` handle, for a function pointer C returned (the pointer carried
unchanged, as for any handle), or an unsigned integer, for an address the program computed:
`u32` or `u64`. A `u32` address works on every target (where addresses are 64 bits it is
zero-extended), so a device library that declares its ROM calls with `u32` still builds and
tests on Linux. Any other type, a missing target or a `mut` one is refused at the declaration
(`E_EXTERN_ADDRESS`); a `u64` target is refused when the program is built for a target whose
addresses are 32 bits. The other
parameters and the result follow the rules of a plain `extern func` exactly (scalars,
handles, `str` and `bytes` spans, a `bytes` result, `mut` out-parameters), and the call
takes the `Host` as a plain one does.

The call is an indirect call under the target's C convention with the declared signature,
the target itself not passed: the C function above is called as `int64_t f(int64_t,
int64_t)`. No symbol of the declared name is referenced, so nothing has to be linked for it,
and two `@address` declarations of one name never conflict. A null handle or the address 0
traps `R_FOREIGN_TARGET` at the call, before any jump (inside a `@freestanding` function, the
freestanding fault with that code, [freestanding functions](functions.md#freestanding-functions)). Any other value is used as given: the
program must pass the address of a function with the declared signature. On `thumbv6m-none`
that is a Thumb address with its low bit set, as a boot ROM's table holds them.

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

The attribute is spelled `@address` because it names what the target is, and because the
language marks what a declaration is with an attribute (`@noalloc`, `@linear`), not a new
keyword. A Selka function cannot be handed to C as a callback: C never calls back into Selka.

## Tests that call C

`selka test --allow-host --link FILE.c` hands the live `Host` to each test that declares
a `host: Host` parameter, so a binding's tests call its C. Without `--allow-host` such a
test fails before it is built, and the message names the flag. A test with a live `Host`
never stores or serves a recorded result; its other capabilities keep their stand-ins.

```sh
selka test tests --allow-host --link vendor/sqlite3.c --link shim.c
```

## The host parameter

Every `extern func` takes `host: Host` as its first parameter. Omitting it is
`E_HOST_CAPABILITY`. The checker verifies the argument at each call, and the C
ABI drops it before the foreign call, so C sees only the remaining arguments.
The Host parameter keeps the call out of compile-time evaluation. `main`
receives `host` like any capability:
`selka run` grants it, and under `--restrict` it needs `--allow-host`:

```console
$ selka run main.selka --link helpers.c --restrict
selka: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-host, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`host: Host?`)
$ selka run main.selka --link helpers.c --restrict --allow-host
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
selka build main.selka --run --link helpers.c
selka build main.selka -o app --link helpers.c --link vendor/crc.c
selka test main.selka --link helpers.c
```

Each `--link` names a C source, relative to the invocation directory; it is compiled
with the build's toolchain (`zig cc -c`, at the build's optimization level and CPU)
and linked after the program's objects, in command-line order. Object files,
archives, shared libraries and library search paths are not link inputs:
`--link-library` and `--library-path` were retired with host functions.

A device build (`--target thumbv6m-none`) calls C the same way: `main` takes `host: Host` (alone or beside
`reg: Registers`), and the C file is a `--link` after the platform's
([C interop on a device](tooling/native-build.md#c-interop-on-a-device)).

The compiled object is cached in the build's `foreign-v1` store, with what the C
compiler printed, and reused only while the source and every header its compiler
depfile listed keep their bytes. A dependency file lists only the headers the compiler
opened, so the store also records each header that a quoted `#include` or a
`__has_include` in those files names beside the file that names it, present with its bytes
or absent, and checks them all again: one that appears (a local `stdbool.h` shadowing the
system one, an `opt.h` a `__has_include` tests for) or goes rebuilds the object. A file that changes while it compiles
pins nothing. A build that replays its last identical build rechecks the same files
([native builds](tooling/native-build.md#the-caches)).

A source that names a header through a macro (`#include HEADER`, as SQLite's amalgamation does), or includes a header
that does, cannot list the names it asks for, so its object is keyed instead by the digest of its preprocessed text
(`zig cc -E` with the compile's own flags), together with everything the key above holds. The text holds every header it
included, the line markers that name each by absolute path, and every macro expanded, `__DATE__` and `__TIME__` included,
so a header that appears and shadows another, a `__has_include` that now finds its file, or a new second is a new key. A
text that still names data it does not hold (`#embed` left as a directive, an `.incbin` in inline assembly) is not
cached, and the object is published only when the text preprocessed after its compile is the text before it. Such a
build preprocesses the source every time and does not replay; for `sqlite3.c` an unchanged build costs about
0.2 to 0.4 CPU-s, against about 4 to 10 CPU-s (debug) or 17 to 41 (`--release`) when it was compiled every time:
the figure depends on the machine and its load (measured: 5.4 and 23 on one, 9.8 and 41 on another), and the first
build on a machine also warms the toolchain's own cache, so allow about 30 s of wall time for it. `--verify-cache` compiles
every served `--link` object again and fails when the bytes differ.
A test run with `--link` never reuses a recorded result.

### Project links

A project names its C sources once, in `selka.json`, instead of on every command:

```console
$ cat selka.json
{"version": 1, "links": ["vendor/sqlite3.c", "lib/shim.c"]}
$ selka build examples/hello.selka --run
$ selka test tests --allow-host
```

Each entry is relative to the directory of the `selka.json` (or absolute). `build`, `build --run`, `run`, `run-project`
and `test` link the listed sources first, in order, then any `--link` files of the command line; a `--link` naming a file
the list already holds is linked once. `check` compiles no C and reads none of it. A listed file that does not exist stops
the build with status 2 and a line naming the configuration and the entry
(`selka.json: error[E_PROJECT_CONFIG]: links entry "lib/shim.c" names no file (...)`). The listed files are inputs exactly
as `--link` files are: an edit to one of them or to the list rebuilds, and an unchanged build replays. Listing C grants
nothing: a program still needs `host: Host` to call it, and `--restrict` still withholds it. A package's own C is used only
when the application allows it ([packages](tooling/packages.md#c-sources-in-a-package)).

**Known limit: `__DATE__` and `__TIME__` in a source the depfile check caches.** A source that names its headers plainly
is served while its files keep their bytes, so a `__TIME__` in it keeps the value of the compile that made the object
(seen on 11 November; nobody has decided whether to change it). With `stamp.c` holding
`int stamp(void) { return __TIME__[7] - 48; }` and a program that prints `stamp(host)`:

```text
selka run main.selka --link stamp.c             # 6: the compile's second
(edit main.selka, a few seconds later) selka run main.selka --link stamp.c   # still 6: the object is served
selka run main.selka --link stamp.c --no-cache  # 1: compiled now
```

A source that names a header through a macro has no such limit: its key holds the expanded time.

## Boundary contract

C code is trusted native code. The handwritten declaration must match the actual C
prototype; a linker cannot verify C types. Foreign calls bypass capability grants
other than `host`, and step and frame budgets do not count time spent inside them;
`--timeout` and a test's `--timeout-ms` still apply.

A `str` or `bytes` argument is lent for the call: C may read `length` octets from `data`
until it returns, and must not write through the pointer, keep it, or expect a NUL
terminator. A `-> bytes` function's pointer and stored length must describe readable memory
until it returns; the runtime copies them before any Selka code runs, so C may free that
memory afterwards. A negative length, or a null pointer with a positive length, traps
`R_FOREIGN_RESULT` at the call. A `mut` parameter points to a temporary that exists until
the function returns; C must not keep the pointer. A handle is C's pointer carried
unchanged: C must accept any handle it returned and the null handle wherever its API allows
NULL. Selka does not stop a program from using a handle after C has freed what it points to,
or from leaving it open. An `@address` call goes to whatever function its target names: a
null handle or the address 0 traps `R_FOREIGN_TARGET` before the jump, and any other value
must be the address of a function with the declared signature.

A test reaches C only under `selka test --allow-host`.

Records, lists, options and unions across the boundary, `str` results, `byte_buffer`
arguments, `mut` text, variadic functions, Selka functions as C callbacks (C calling back
into Selka) and automatic binding generation are not supported (`E_EXTERN_SIGNATURE`).
Calling a C function pointer is supported, through an `@address` extern func.

`host func` declarations, registered host adapters, `--library`, `--provider` and
the host applications built on them were retired in S5 (2026-10); `extern func` with
`--link` is the C interop that remains. A `host func` is refused at check time with
`E_HOST_RETIRED`: declare the function `extern func` and link its C implementation.
