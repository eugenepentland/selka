# Printing, files and command-line authority

`print` and the file surface give application code the I/O a Python programmer
expects. Printing needs no capability; touching the filesystem, the clock,
entropy or the environment does, and the command line grants it explicitly.

## print

```mylang
# doc: expect hello 42 True None
# doc: expect ['a', 'b'] {'k': 1} b'\x00\xff'
def main() -> int:
    print("hello", 42, True, None)
    print(["a", "b"], {"k": 1}, b"\x00\xff")
    return 0
```

Arguments are separated by single spaces and followed by one newline. `sep=` and
`end=` replace either, and both accept any `str` expression:

```mylang
# doc: expect 1-2-3!
def main() -> int:
    print(1, 2, 3, sep="-", end="!\n")
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
class Point:
    x: int
    y: int

enum Colour { red, green }

def pick(n: int) -> Result[int, str]:
    if n < 0:
        return Err("nope")
    return Ok(n)

def main() -> int:
    print(Point(x=1, y=2), Colour.green)
    found: Option[int] = Some(4)
    missing: Option[int] = None
    print(pick(3), pick(-1), found, missing)
    return 0
```

Nesting deeper than 24 levels renders as `...`, so a cyclic managed graph still
terminates. Capabilities, open files and callback values have no rendering and
are rejected while checking.

`print` contributes the `output` effect, which `noio` withholds along with
`filesystem` and `network`:

```mylang
# doc: expect-error E_EFFECT_BOUND
def main() -> int noio:
    print("not allowed here")
    return 0
```

Write `effects(output)` to permit printing under an explicit bound. Standard
output is a VM-only surface: the QBE native backend rejects `print` with
`E_QBE_UNSUPPORTED`.

## What `mylang run` prints

`mylang run` streams program output to standard output as it happens and does
**not** print the entry point's `int` result. Pass `--print-result` when you want
the old behaviour — the result line is then written after the program's own
output:

```text
$ mylang run hello.my
hello
$ mylang run hello.my --print-result
hello
0
```

`run-project` follows the same rule.

## Capabilities

The entry point declares the authority it needs by parameter type. `Filesystem`,
`Network`, `Clock`, `Entropy` and `Environment` are Python spellings of the
existing `filesystem_cap`, `network_cap`, `clock_cap`, `random_cap` and
`environment_cap` types, and name exactly the same checked types. They resolve
only when no declared or imported type claims the name, so a module with its own
`class Clock` still gets its own type.

The command line grants them:

| Flag | Grant |
| --- | --- |
| `--allow-read=DIR` | read the directory tree at `DIR` (repeatable) |
| `--allow-write=DIR` | read and write that tree, including create, truncate, `mkdir` and `remove` |
| `--allow-clock` | wall-clock time in Unix-epoch nanoseconds |
| `--allow-random[=SEED]` | a pseudorandom stream, reproducible when `SEED` is given |
| `--allow-env[=NAME,...]` | the process environment, restricted to the named variables |
| `--allow-all` | clock, entropy, every environment name, and read/write on the working directory |

Running a program whose `main` requests an ungranted capability fails before the
first guest instruction, naming the flag:

```text
$ mylang run report.my
mylang: the entry point requests a capability this command line did not grant; pass --allow-read=DIR
```

Helpers receive authority as ordinary arguments; nothing is ambient, and no cast
or copy mints a capability.

**These grants are an authority boundary for guest source, not a sandbox.** The
providers run inside the compiler process, the host filesystem tree is trusted,
directory handles keep their authority across renames, and directory scoping does
not distinguish hard links to the same inode. A compromised compiler, or a host
that edits the adapters, is outside this boundary.

## Files

File functions take the capability as their first argument, so authority is
visible at every call site rather than hidden in a global.

```mylang
# doc: allow-read notes
# doc: expect Ok('hello from a granted directory\n')
# doc: expect True False
def main(fs: Filesystem) -> int:
    print(read_text(fs, "greeting.txt"))
    print(exists(fs, "greeting.txt"), exists(fs, "absent.txt"))
    return 0
```

`open(fs, path, mode)` returns `Result[File, str]` for a binary mode and
`Result[TextFile, str]` for a text mode. The mode is a literal: `"r"`, `"w"` or
`"a"` with an optional `"b"` or `"t"`. A binary handle reads `bytes`; a text
handle reads `str`.

`with open(...) as f:` opens the file and **traps** with a located `R_FILE` error
if it cannot, the way Python's `open` raises. Writing `with open(...)? as f:`
propagates the failure instead, in a function that returns a compatible
`Result`:

```mylang
# doc: allow-read notes
# doc: expect b'hello from a granted directory\n'
# doc: expect 3
def count(fs: Filesystem) -> Result[int, str]:
    total = 0
    with open(fs, "lines.txt", "r")? as f:
        for line in f.readlines():
            total = total + 1
    return Ok(total)

def main(fs: Filesystem) -> int:
    with open(fs, "greeting.txt", "rb") as f:
        print(f.read())
    match count(fs):
        case Ok(value):
            print(value)
        case Err(message):
            print(message)
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

The whole-path helpers are:

| Call | Result |
| --- | --- |
| `read_file(fs, path)` | `Result[bytes, str]` |
| `read_text(fs, path)` | `Result[str, str]` |
| `write_file(fs, path, data)` | `Result[None, str]` |
| `write_text(fs, path, text)` | `Result[None, str]` |
| `exists(fs, path)` | `bool` |
| `listdir(fs, path)` | `Result[list[str], str]` |
| `mkdir(fs, path)` | `Result[None, str]` |
| `remove(fs, path)` | `Result[None, str]` |

Their error text names the operation, the path and a readable reason, for example
`read 'absent.txt': failed: the path does not exist or could not be used`.

Paths are relative and are resolved against each granted directory in order; the
first root where the operation succeeds wins. A path with an empty, `.`, `..`,
NUL or backslash component is denied before anything is opened, as is any writing
mode against a directory granted read-only:

```mylang
# doc: allow-read notes
# doc: expect Err('read \'../escape\': denied: outside the granted directories, or the mode needs a write grant')
# doc: expect Err('write \'new.txt\': denied: outside the granted directories, or the mode needs a write grant')
def main(fs: Filesystem) -> int:
    print(read_text(fs, "../escape"))
    print(write_text(fs, "new.txt", "x"))
    return 0
```

File operations contribute the `filesystem` effect, so `noio` rejects them:

```mylang
# doc: expect-error E_EFFECT_BOUND
def main(fs: Filesystem) -> int noio:
    _ = exists(fs, "notes.txt")
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

Generic function bodies reject file operations, and the QBE native backend
rejects them with `E_QBE_UNSUPPORTED`; the file surface runs on the VM only.

## Related pages

- [Managed arenas](arenas.md) — the other `with` resource kind
- [Scoped providers](experiments/scoped-providers.md) — the adapter these grants configure
- [Byte application I/O](byte-io-bulk.md) — the separate copied-block runner
