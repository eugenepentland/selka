# Printing, files and command-line authority

`stream.print` and the file surface give application code the I/O a Python
programmer expects. The entry point declares `out: Stream`/`err: Stream`, and the
runtime always supplies them, so printing itself needs no host grant. Touching
the filesystem, the clock, entropy or the environment does, and the entry point
names each one it needs — but `mylang run` grants them all by default, so an
ordinary program just runs. Pass `--restrict` when you want the command to
withhold authority instead.

## print

```mylang
# doc: expect hello 42 True None
# doc: expect ['a', 'b'] {'k': 1} b'\x00\xff'
def main(out: Stream) -> int:
    out.print("hello", 42, True, None)
    out.print(["a", "b"], {"k": 1}, b"\x00\xff")
    return 0
```

Arguments are separated by single spaces and followed by one newline. `sep=` and
`end=` replace either, and both accept any `str` expression:

```mylang
# doc: expect 1-2-3!
def main(out: Stream) -> int:
    out.print(1, 2, 3, sep="-", end="!\n")
    return 0
```

Every ordinary value renders the way Python spells it. `str` prints raw at the
top level and `repr`-quoted inside a container; `bytes` prints as a `b'...'`
literal; `float` keeps a `.0` when it has no fractional digits; records print as
`Name(field=value)`, enum and union cases as `Name.case`, and checked results and
optionals as `Ok(...)`, `Err(...)`, `Some(...)` and `None`:

```mylang
# doc: expect Point(x=1, y=2) Colour.green
# doc: expect Ok(3) Err('nope') Some(4) None
record Point:
    x: int
    y: int

enum Colour:
    red,
    green


def pick(n: int) -> Result[int, str]:
    if n < 0:
        return Err("nope")
    return Ok(n)

def main(out: Stream) -> int:
    out.print(Point(x=1, y=2), Colour.green)
    found: Option[int] = Some(4)
    missing: Option[int] = None
    out.print(pick(3), pick(-1), found, missing)
    return 0
```

Nesting deeper than 24 levels renders as `...`, so a cyclic managed graph still
terminates. Capabilities, open files and callback values have no rendering and
are rejected while checking.

`stream.print` contributes the `output` effect, which `noio` withholds along
with `filesystem` and `network`:

```mylang
# doc: expect-error E_EFFECT_BOUND
def main(out: Stream) -> int noio:
    out.print("not allowed here")
    return 0
```

Write `effects(output)` to permit printing under an explicit bound. `stream.print`
runs on the QBE native backend, the only runtime.

The bare `print(...)` and `eprint(...)` spellings are gone. They report
`E_OUTPUT_CAPABILITY` with the fix "add `out: Stream` to this function and pass
one from main"; `debug(...)` remains the only way to write without a capability.

```mylang
# doc: expect-error E_OUTPUT_CAPABILITY
def main() -> int:
    print("no stream")
    return 0
```

`err.print` is the standard-error spelling. It accepts the same values and
`sep=`/`end=` keywords, writes only standard error, and contributes the same
`output` effect. The two streams are buffered and flushed independently, so an
`out.print` line never mixes with an `err.print` line even when both are used
together. Byte-exact stream separation is covered by the native CLI tests.

## Stream

`stream.write(data: bytes)` writes bytes directly, including NUL and non-UTF-8
octets, and returns the byte count. It adds no quotes or newline. This is useful
for binary protocols and UTF-8 output built as bytes; it avoids converting the
output to `str` and encoding it again. The `str` overload still returns its
Unicode scalar count. Both flush the selected stream and trap `R_OUTPUT` if the
write or flush fails.

A mutable [`byte_buffer`](bytes.md#writing-octets-in-place) is a byte string for
this purpose too: `stream.write(buffer)` writes the octets the buffer holds right
now, straight out of the buffer's own storage. Nothing is copied and no snapshot
is built, so a program assembled in a buffer can reach the stream without a final
`bytes(buffer)`; it contributes the same `output` effect and returns the same byte
count. Appending to the buffer afterwards cannot change what was already written.

`Stream` is a capability like `Filesystem`: the entry point declares the
standard streams it wants, and a helper may take any `Stream` name and be handed
either one. `stream.print(values..., sep=, end=)` renders Python's `print`
spelling and `stream.write(text) -> int` writes the text and returns its
character count. Both contribute the `output` effect and write to the destination
carried by the receiver value. Streams are granted unconditionally, so
`--restrict` cannot take standard output away.

```mylang
# doc: check
def main(out: Stream, err: Stream) -> int:
    out.print("result:", 42)
    err.print("note", sep=": ")
    written: int = out.write("raw")
    return written
```

## debug

`debug(values...)` writes to standard error without a capability and without
contributing any effect, so it is safe inside a `noio` function. It renders like
`stream.print` and returns unit. Debug builds and `mylang run`/`mylang test` emit
it; a `--mode ReleaseFast` build drops it in lowering.

```mylang
# doc: check
def trace() -> int noio:
    debug("pure function")
    return 0
```

## What `mylang run` prints and returns

`mylang run` streams program output to standard output as it happens and does
**not** print the entry point's `int` result. Pass `--print-result` when you want
the result line written after the program's own output:

```text
$ mylang run hello.my
hello
$ mylang run hello.my --print-result
hello
0
```

The entry's `int` result is the **process exit status**, the way a Python or Go
program returns an exit code, truncated to the low 8 bits (`status = value &
0xFF`). This holds whether or not `--print-result` is passed, so printing the
value and exiting with it are independent:

```text
$ mylang run hello.my; echo "exit $?"
hello
exit 0
```

A runtime trap outranks the return and exits 1, because the program never
reached its `return`. `run-project` and a native executable from `mylang build`
follow the same rule. An entry point may also return `Result[int, str]`:
`Ok(code)` carries the same status rule, while `Err(message)` writes exactly one
`message` line to standard error and exits 1. Exit codes are truncated to the
low eight bits, so `Ok(300)` exits 44. `--print-result` still prints the carried
integer status, independent of the diagnostic on stderr.

## Runtime diagnostics

A native trap keeps its original code, primary location, call stack and omitted
frame count. Where the failing operation already evaluated the values, the trap
also carries a bounded versioned detail: bounds failures report the original
index (negative values preserved) and the receiver length; integer division and
checked overflow report the evaluated operands and width where available. A trap
is sticky: the first trap's detail is retained even if later operations would
also fail.

`mylang run` renders that detail in text and, with `--diagnostics json`, under
`trap_detail` in the structured diagnostic. Both come from the same captured
values, so text does not reparse its own output and no receiver, index or
expression is reevaluated for a diagnostic. Detail-free traps (step and memory
budgets, capability and host failures) omit the field. Guests are separate
native processes, so children emit exactly one newline-terminated record
`\x1eMYLANG-TRAP ` followed by a bounded JSON object on standard error; a host
that sees no record behaves exactly as before, and ordinary standard output,
diagnostics and exit statuses are unchanged.

```text
example.my:2:12: error[R_LIST_BOUNDS]: native execution failed (index 14, length 1)
```

## Arguments

A `main(args: list[str], ...)` entry point receives guest arguments as input
data, never authority. `mylang run` and `build --run` reserve their own compiler
and runtime options before `--` and pass every value after it in order:

```console
$ mylang run report.my -- --format=json "two words" ""
```

The list never contains a synthetic program name. An installed executable
hands `main` every OS argument after `argv[0]` unchanged — `--` and
flag-looking values such as `--gc-stress` included — because it reads its own
runtime options from the `MYLANG_OPTIONS` environment variable instead (see
[the native backend](#the-native-backend)). Every argument is validated as
Unicode before guest execution, and invalid platform bytes fail with a stable
host-boundary diagnostic on stderr.

```mylang
# doc: expect count 0
def main(args: list[str], out: Stream) -> int:
    out.print("count", len(args))
    return 0
```

## Capabilities

The entry point declares the authority it needs by parameter type. `Filesystem`,
`Network`, `Clock`, `Entropy` and `Environment` are Python spellings of the
existing `filesystem_cap`, `network_cap`, `clock_cap`, `random_cap` and
`environment_cap` types, and name exactly the same checked types. They resolve
only when no declared or imported type claims the name, so a module with its own
`record Clock` still gets its own type.

`mylang run` and `run-project` grant every capability by default: the filesystem
with no directory restriction, the clock, entropy and the whole process
environment. Relative paths resolve against the process working directory and
absolute paths name themselves, exactly as they would for any other program.

`--restrict` switches the command to deny-by-default. Only then do these flags
narrow anything:

| Flag | Grant under `--restrict` |
| --- | --- |
| `--allow-read=DIR` | read the directory tree at `DIR` (repeatable, up to eight) |
| `--allow-write=DIR` | read **and** write that tree, including create, truncate, `mkdir` and `remove` |
| `--allow-clock` | wall-clock time in Unix-epoch nanoseconds |
| `--allow-random[=SEED]` | a pseudorandom stream, reproducible when `SEED` is given |
| `--allow-env[=NAME,...]` | the process environment, restricted to the named variables |
| `--allow-all` | clock, entropy, every environment name, and read/write on the working directory |

Without `--restrict` these flags are accepted and narrow nothing, so a command
line written for an older build keeps working. The one exception is
`--allow-random=SEED`, which pins the entropy seed in either mode because it
selects a stream rather than withholding one; an unseeded stream is seeded from
the wall clock.

Running a program whose `main` requests an ungranted capability fails before the
first guest instruction — and that can only happen under `--restrict`:

```text
$ mylang run report.my --restrict
mylang: --restrict is active and this command line did not grant a capability the entry point requests; pass --allow-read=DIR, or drop --restrict to grant every capability
```

The language itself is unchanged: helpers receive authority as ordinary
arguments, nothing is ambient, and no cast or copy mints a capability. What the
default changes is only how generous the command line is.

**Neither mode is a sandbox.** The providers run inside the compiler process, the
host filesystem tree is trusted, directory handles keep their authority across
renames, and directory scoping does not distinguish hard links to the same inode.
A compromised compiler, or a host that edits the adapters, is outside this
boundary. `--restrict` is a way to say what a program is allowed to reach, not a
containment mechanism.

## Environment

Environment access needs an explicit `Environment` entry parameter. On a
capability value, `env.get("NAME")` returns `Option[str]`: `Some(value)` for a
present name and `None` when the provider has no such name, decoded as UTF-8. A
name outside the active `--allow-env` allow-list is a denied authority, which
traps rather than answering `None`. `env.only("HOME", "PATH")` narrows an
`Environment` to the listed literal names, and `env.names()` returns the sorted
allow-list as `list[str]`. `mylang run` and installed executables grant the
process environment (including `MYLANG_OPTIONS`) by default; under `--restrict`, `--allow-env[=NAME,...]`
selects the visible names. All launch paths now report an ungranted capability
with the same stderr line and exit 2.

```mylang
# doc: check
def main(env: Environment) -> int effects(environment):
    home = env.get("HOME")
    narrowed = env.only("HOME")
    _ = home
    _ = narrowed
    return len(env.names())
```

## Files

File functions take the capability as their first argument, so authority is
visible at every call site rather than hidden in a global. Every whole-path
helper is also a method on the `Filesystem` value: `fs.read_text(path)` is the
qualified spelling of `read_text(fs, path)`. Both are accepted; the method form
belongs to the receiver, so a declared function or local named `read_text` still
claims the free spelling.

```mylang
# doc: allow-read notes
# doc: expect Ok('hello from a granted directory\n')
# doc: expect True False
def main(fs: Filesystem, out: Stream) -> int:
    out.print(fs.read_text("greeting.txt"))
    out.print(fs.exists("greeting.txt"), fs.exists("absent.txt"))
    return 0
```

`fs.open(path, mode)` returns `Result[File, str]` for a binary mode and
`Result[TextFile, str]` for a text mode. The mode is a literal: `"r"`, `"w"` or
`"a"` with an optional `"b"` or `"t"`. A binary handle reads `bytes`; a text
handle reads `str`. The free `open(fs, path, mode)` form is equivalent.

`with fs.open(...) as f:` opens the file and **traps** with a located `R_FILE`
error if it cannot, the way Python's `open` raises. Writing
`with fs.open(...)? as f:` propagates the failure instead, in a function that
returns a compatible `Result`:

```mylang
# doc: allow-read notes
# doc: expect b'hello from a granted directory\n'
# doc: expect 3
def count(fs: Filesystem) -> Result[int, str]:
    total = 0
    with fs.open("lines.txt", "r")? as f:
        for line in f.readlines():
            total = total + 1
    return Ok(total)

def main(fs: Filesystem, out: Stream) -> int:
    with fs.open("greeting.txt", "rb") as f:
        out.print(f.read())
    match count(fs):
        case Ok(value):
            out.print(value)
        case Err(message):
            out.print(message)
    return 0
```

A handle supports `f.read()`, `f.read(n)`, `f.readline()`, `f.readlines()`,
`f.write(data)`, `f.flush()` and `f.close()`. `readline` and `readlines` keep
their line terminators. `write` returns the number of bytes written and loops
over partial writes. `flush` exists for familiarity; writes are unbuffered.
Iterate a file with `for line in f.readlines():` — a handle is not itself
iterable.

The scope closes its file exactly once at every exit: falling off the end,
`return`, `?` propagation, `break`, `continue`, an explicit `f.close()`, and a
trap or host allocation failure unwinding through it. A method on a closed handle
traps with `R_FILE`, as does any provider failure during a method, because
`f.read()` yields bytes rather than a result.

An open binding is used only through its own methods; it cannot be stored,
passed or returned.

The whole-path helpers are methods on the `Filesystem` value, and each keeps a
free-function spelling that takes the capability first:

| Method | Free form | Result |
| --- | --- | --- |
| `fs.read_file(path)` | `read_file(fs, path)` | `Result[bytes, str]` |
| `fs.read_text(path)` | `read_text(fs, path)` | `Result[str, str]` |
| `fs.write_file(path, data)` | `write_file(fs, path, data)` | `Result[None, str]` |
| `fs.write_text(path, text)` | `write_text(fs, path, text)` | `Result[None, str]` |
| `fs.exists(path)` | `exists(fs, path)` | `bool` |
| `fs.listdir(path)` | `listdir(fs, path)` | `Result[list[str], str]` |
| `fs.mkdir(path)` | `mkdir(fs, path)` | `Result[None, str]` |
| `fs.remove(path)` | `remove(fs, path)` | `Result[None, str]` |

Their error text names the operation, the path and a readable reason, for example
`read 'absent.txt': failed: the path does not exist or could not be used`.

By default a path resolves the way it would for any other process: relative to
the working directory, or absolutely when it starts with `/`.

Under `--restrict`, paths must be relative and are resolved against each granted
directory in order; the first root where the operation succeeds wins. A path with
an empty, `.`, `..`, NUL or backslash component is denied before anything is
opened, as is any writing mode against a directory granted read-only. A directory
granted with `--allow-write` is always readable too, so write authority is never
narrower than read authority:

```mylang
# doc: allow-read notes
# doc: expect Err('read \'../escape\': denied: outside the granted directories, or the mode needs a write grant')
# doc: expect Err('write \'new.txt\': denied: outside the granted directories, or the mode needs a write grant')
def main(fs: Filesystem, out: Stream) -> int:
    out.print(fs.read_text("../escape"))
    out.print(fs.write_text("new.txt", "x"))
    return 0
```

File operations contribute the `filesystem` effect, so `noio` rejects them:

```mylang
# doc: expect-error E_EFFECT_BOUND
def main(fs: Filesystem) -> int noio:
    _ = fs.exists("notes.txt")
    return 0
```

`with` on anything that is not `arena()` or an open file is rejected with
`E_WITH_RESOURCE`:

```mylang
# doc: expect-error E_WITH_RESOURCE
def main() -> int:
    with 7 as value:
        return 0
```

Generic function bodies reject file operations. The native backend runs them.

## The native backend

`print` and every file operation run on the QBE native backend, so `mylang
build` and `mylang build --run` accept a program that uses them.
A native executable grants every capability by default, exactly as `mylang run`
does. It never reads an option from its own arguments — every one of them is the
program's — so the runtime options `mylang run` takes travel in the
`MYLANG_OPTIONS` environment variable instead: `--restrict` and the `--allow-*`
grants, `--max-steps=N`, `--max-frames=N`, `--timeout=SECONDS`, `--gc-stress`
and `--print-result`, separated by spaces. Wrap an option that contains a space
in double quotes (a backslash inside the quotes escapes the next character). An
unknown or repeated option, or an unterminated quote, exits 2 before the program
runs. `mylang build --run` takes the same options on its own command line,
before `--`, and passes the values after `--` to the program:

```text
$ MYLANG_OPTIONS='--restrict --allow-read=notes' ./report --format=json
$ mylang build report.my --run --restrict --allow-read=notes -- --format=json
```

`mylang run`, `run-project` and `build --run` set `MYLANG_OPTIONS` for the
program from their own command line, replacing any value they inherited.

A native executable exits with the entry point's `int` result (truncated to the
low 8 bits), the way `mylang run` does, and writes that result after the
program's own output only when `MYLANG_OPTIONS` names `--print-result`.

Generic function bodies still reject `print` and the file builtins, with
`E_GENERIC_BODY_UNSUPPORTED`. Write an ordinary function and call it from the
generic one.

## Related pages

- [Managed arenas](arenas.md) — the other `with` resource kind
- [Scoped providers](experiments/scoped-providers.md) — the adapter these grants configure
- [Byte application I/O](byte-io-bulk.md) — the separate copied-block runner
