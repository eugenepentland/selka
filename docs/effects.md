# Capabilities and allocation contracts

Authority is carried by values. A function that prints takes a `Stream`, one that reads a file takes a `Filesystem`, one
that calls C takes a `Host`. The command line provisions the entry point's capability parameters
([printing, files and command-line authority](io.md) lists them and the grants).

- A capability parameter the body never reads is `E_UNUSED_CAPABILITY`: remove it, pass it on, or name it with a leading `_`
  (`_out: Stream`) when the signature must stay. A body that still holds a typed hole (`todo[T]()`) is exempt
  ([typed holes](typed-holes.md#running-with-holes)).
- A task (`g.submit`, `parallel.map`) takes no capability, `E_TASK_CAPABILITY`: it computes and returns
  ([concurrency](concurrency.md#tasks-take-values)).
- A `Stop` on `main` grants nothing: with it SIGTERM and SIGINT turn `process.stop_requested(stop)` true instead of ending
  the program. It needs no grant, `--restrict` keeps it, and a test gets a stand-in ([hearing a stop](io.md#hearing-a-stop)).
- A callback that prints takes a `Stream` parameter, as in `func(Stream, int) -> int`; its parameter and result types,
  mutation positions and return-origin contract decide compatibility.

## Allocation contracts

Write `@noalloc` above a function and the build checks that its body allocates nothing. Managed heap and runtime scratch
allocations count, in callees and cold paths too; an unresolved callback or foreign call counts as allocating. Stack
storage, compiler allocation and process startup do not.

```selka
# doc: expect 42
@noalloc
func area(width: int, height: int) -> int:
    return width * height

func main(out: Stream) -> int:
    print(out, area(6, 7))
    return 0
```

Parameters are borrowed views, so `text[i]`, a slice of a parameter passed to another `@noalloc` function and a loop over a
`bytes` parameter keep the promise; a call that must copy borrowed text into an owned block breaks it. Debug and release
builds accept the same programs.

| Where | What happens |
| --- | --- |
| `build`, `run`, `build --run`, `test` | `E_NOALLOC_ALLOCATES`, exit 1, naming the declaration and the allocating site |
| `check`, `check-project` | the check does not run |
| `lint --gate` | the blocking rule `noalloc-allocates` (`L_NOALLOC_ALLOCATES`); a waiver does not override the build error |

The clauses `effects(...)`, `noio` and a trailing `noalloc` are `E_EFFECTS_REMOVED`; `selka fix` deletes the first two and
writes `@noalloc` for the third. A contract condition may allocate but cannot mention a capability, pass a `mut` argument,
update a receiver, assign or `try` ([contracts](contracts.md#conditions-are-pure)).

## Mutation contracts

A parameter `mut name: T` names caller storage, and the caller marks the argument: `restock(mut inventory, "bolt", 5)`.
Call sites mark exactly the declared `mut` positions. A receiver is not marked: `append(mut values, 1)` writes its
binding and says so.

- `mut` parameters take scalars, text, bytes, fixed arrays and collections; rebinding, field writes and element writes reach
  the caller's place. An argument is a writable variable, field or indexed slot.
- The guarantee covers the whole value, managed descendants included. Ordinary parameters borrow; `copy(value)` gives an
  independent value.
- A `mut` argument cannot overlap a live read-only borrow, and two overlapping `mut` arguments (`f(mut a, mut a)`) are
  rejected ([value semantics](value-semantics.md#the-rules)).
- A returned value is independent of the callee's input. A write through a read-only parameter is `E_MUTATION_MARKER`.

```selka
# doc: expect 7
func replace_first(mut values: int[], replacement: int) -> Unit:
    values[0] = replacement

func main(out: Stream) -> int:
    mut values = [1]
    replace_first(mut values, 7)
    print(out, values[0])
    return 0
```

An assignment keeps an independent value; a helper changes its caller's value only through a marked `mut` argument:

```selka
# doc: expect 1
# doc: expect 5
func set_first(mut values: int[], replacement: int) -> Unit:
    values[0] = replacement


func main(out: Stream) -> int:
    mut original = [1, 2]
    mut copy = copy(original)
    set_first(mut copy, 5)
    print(out, original[0])
    print(out, copy[0])
    return 0
```

## Capability method narrowing

`fs.read_only()` derives a read-only `Filesystem`. The result is an ordinary handle: bind it with or without `with`, pass,
return, copy or store it, and every copy stays as narrow. The bracket spelling `restrict_resource[...]` is
`E_REMOVED_SPELLING`.

```selka
# doc: check
func main(fs: Filesystem) -> int:
    with fs.read_only() as read_only:
        return 0
```

## Capabilities in record fields

A capability in a record field takes method syntax through the field, as a local does: `ctx.fs.read_text(path)`,
`ctx.env.get("HOME")`, `ctx.net.host("127.0.0.1:8000")`, `print(ctx.err, ...)`. `Clock` and `Entropy` have no methods:
pass them on (`time.now(ctx.clock)`). An unknown method on a capability field is `E_COLLECTION_METHOD`.

```selka
# doc: check
import strings

record Context:
    fs: Filesystem
    env: Environment

func read_note(ctx: Context, path: str) -> int:
    match ctx.fs.read_text(path):
        case Ok(text):
            return strings.char_count(text)
        case Err(_):
            return -1

func main(fs: Filesystem, env: Environment) -> int:
    mut ctx = Context(fs=fs, env=env)
    return read_note(ctx, "note.txt") + len(ctx.env.names())
```

## Declaration-site mutation errors

Writing a parameter that is not `mut` is `E_IMMUTABLE`, at the write. A `mut` parameter may go unused and need not be
written on every return path. The `mutates(...)` clause and the `&` argument marker are rejected with a diagnostic that names `mut`.

```selka
# doc: expect-error E_IMMUTABLE
func touch(values: int[]) -> Unit:
    values[0] = 1


func main() -> int:
    mut values = [1]
    touch(values)
    return 0
```

## Filesystem dir

`fs.dir(path)` derives a filesystem rooted at a string-literal path under the receiver's root; every call through it joins
the prefix and rejects a request that could leave the subtree. It follows no symbolic link in any run, with or without
`--restrict`: a link on the way, at the end or in the narrowing's own prefix is refused (the unnarrowed `Filesystem` of an
unrestricted run still follows links). `canonical_path` and `stat_follow_path` follow a link only while it stays inside.

The path must be a literal, so the checker can see it stays inside the root. A dynamic one is `E_FILESYSTEM_DIR`, whose
message names `filesystem.dir_at(fs, path) -> Filesystem fails str`, the call for a folder learned at run time
([a folder named at run time](io.md#a-folder-named-at-run-time-filesystemdir_at)).

```selka
# doc: check
resource File: filesystem

result Open:
    ok: File,
    err: int

func main(fs: Filesystem) -> int:
    with fs.dir("data") as scoped:
        mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([42u8])
        match acquire_resource[Open](scoped, request):
            case ok(file):
                _ = own file
                return 0
            case err(code):
                return -code
```

## Network host

`net.host(name)` narrows a `Network` to the one string-literal endpoint `name`; every call through it asks for exactly that
endpoint, so `network.connect(scoped)` takes no address. An endpoint outside `--allow-endpoint` is still denied.
`network.listen(scoped)` and `network.open_poller(scoped)` ([the event loop](standard-library.md#event-loop)) bind only when
the same literal is in `--allow-listen`, a separate grant. A program that only connects out uses
`network.open_client_poller(net)`, which needs no listen grant
([a client with no listener](standard-library.md#a-client-with-no-listener)).

- The match is verbatim. `--allow-listen=127.0.0.1:0` permits only `net.host("127.0.0.1:0")` (a kernel-chosen port that a
  `Poller` reports with `network.port`), not `127.0.0.1:8080`, and an `:8080` grant does not permit port 0.
- `--allow-endpoint=IP:0` is a usage error, and a blocking `network.listen` refuses a port-0 narrowing with `err(2)`.
- A function handed a narrowed `Network` reaches only that endpoint: `network.connect_to` and the other run-time-address
  calls refuse any other address through it (`err(2)`). On an un-narrowed `Network` the address comes from the launch and,
  under `--restrict`, is checked verbatim against the grants. `connect_to`, `connect_within_to`, `listen_at`,
  `open_poller_at` and `dial_to` mark every run-time address
  ([addresses given at run time](standard-library.md#addresses-given-at-run-time)).

```selka
# doc: check
import network

func main(net: Network) -> int:
    # The narrowed capability pins the endpoint, so `connect` takes no address.
    with net.host("127.0.0.1:8000") as scoped:
        match network.connect(scoped):
            case ok(socket):
                _ = network.close(own socket)
                return 0
            case err(code):
                return code
```

## Deterministic stand-ins

`time.simulated_clock`, `random.seeded_entropy`, `filesystem.memory`, `environment.fixed`, `network.denied`,
`network.memory` and `process.simulated_stop` build a `Clock`, `Entropy`, `Filesystem`, `Environment`, `Network` or `Stop`
that grants no real authority. A simulated clock reads its instant until `time.advance` moves it; a seeded stream is
reproducible; the filesystem lives in memory; the environment holds fixed pairs; `network.denied` refuses every connection
and `network.memory` connects only to listeners in the same memory; a simulated stop is requested only by
`process.request_stop`.

Building one needs no capability, so a function with no `Clock` can build a simulated one; `fs.dir(...)`, `read_only()`,
`env.only(...)` and `net.host(...)` on a stand-in derive stand-ins. `selka test` hands the same stand-ins to a test that
declares a capability parameter ([capability parameters](tooling/guest-tests.md#capability-parameters)).

```selka
# doc: expect 1 True
import filesystem
import time

func uptime(clock: Clock, boot: time.Instant) -> int:
    match time.now(clock):
        case Ok(current):
            match time.elapsed(boot, current):
                case Ok(span):
                    return time.to_milliseconds(span) // 1000
                case Err(_):
                    return -1
        case Err(_):
            return -1

func remember(fs: Filesystem, note: str) -> bool:
    _ = fs.write_text("note.txt", note)
    return fs.exists("note.txt")

func check() -> int:
    mut boot = time.from_unix_nanoseconds(0)
    mut clock = time.simulated_clock(boot)
    _ = time.advance(clock, time.nanoseconds(1000000000))
    return uptime(clock, boot)

func main(out: Stream) -> int:
    print(out, check(), remember(filesystem.memory(), "hi"))
    return 0
```

`check` and `main` declare no `Clock` or `Filesystem`, yet read a clock and write a file: both are stand-ins.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/effects.md).
