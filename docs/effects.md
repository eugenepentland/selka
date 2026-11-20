# Capabilities and allocation contracts

Authority is carried by values. A function that prints takes a `Stream`; a
function that reads a file takes a `Filesystem`; a function that calls C takes a
`Host`. The command line provisions the entry point's capability parameters.
A capability parameter the body never reads is `E_UNUSED_CAPABILITY`: remove it,
pass it to the operation that needs it, or prefix its name with `_` when its
signature must be retained, such as `_out: Stream` in a callback implementation.
A body that still holds a typed hole (`todo[T]()`) is exempt until the hole is
filled, because the code that fills it may use the capability
([typed holes](typed-holes.md#running-with-holes)).

A task (`g.submit`, `parallel.map`) takes no capability at all, `E_TASK_CAPABILITY`: authority stays with the
calling thread, and a task computes and returns ([concurrency](concurrency.md#tasks-take-values)).

A `Stop` on `main` is the one capability that grants nothing: it changes how the program ends. With it SIGTERM and
SIGINT turn `process.stop_requested(stop)` true instead of ending the program, so a reader of `main`'s signature knows
the program has a goodbye; without it they end the program as always. It needs no grant, `--restrict` keeps it, and a
test gets a stand-in it can trigger ([hearing a stop](io.md#hearing-a-stop)).

Callbacks use the same rule. A callback that prints has a parameter such as
`func(Stream, int) -> int`. Its parameter and result types, mutation positions,
and return-origin contract determine compatibility. Interfaces and hashes carry
these declared contracts without inferred effect sets.

## Allocation contracts

Write `@noalloc` above a function to request a build-time check of its
ownership-expanded Core body before optimization. Managed heap and runtime
scratch allocations count, including allocations in callees and cold paths.
An unresolved callback or foreign call is treated conservatively. Stack storage,
compiler allocation, and process startup are outside the function contract.

A promise is judged on the body the build emits for the function, not on a
simplified copy of it. A function that something else calls runs over borrowed
views of its `str`, `bytes` and list parameters, so `text[i]`, a slice of a
parameter handed to another `@noalloc` function, and a loop over the bytes of a
`bytes` parameter keep the promise, while a call that has to copy the borrowed
text into an owned block (a runtime helper with no span form) breaks it. The
check lowers the function as such a callee and runs the same lowering passes and
ownership expansion a debug build runs; the optimizing passes of `--release` and
`--optimize-debug` only remove allocations from it, so debug and release builds
accept the same programs.

```selka
# doc: expect 42
@noalloc
func area(width: int, height: int) -> int:
    return width * height

func main(out: Stream) -> int:
    print(out, area(6, 7))
    return 0
```

`build`, `run`, `build --run`, and `test` reject a violation with
`E_NOALLOC_ALLOCATES` and exit status 1. The diagnostic identifies the declaration
and allocating site.
`check` and `check-project` check source types without running this Core check.
`lint --gate` promotes the same witness to the blocking `noalloc-allocates`
rule, `L_NOALLOC_ALLOCATES`. A lint waiver does not override the build error.

The former source clauses `effects(...)`, `noio`, and trailing `noalloc` are
rejected with `E_EFFECTS_REMOVED`. `selka fix` deletes the former authority
clauses and replaces a function's trailing `noalloc` with `@noalloc`.

A contract condition may allocate, but cannot mention a capability parameter,
pass a `mut` argument, update a receiver, assign, or return early with `try`.
See [contracts](contracts.md#conditions-are-pure).

## Mutation contracts

A parameter declared `mut name: T` names caller storage. A caller marks the
corresponding argument, as in `restock(mut inventory, "bolt", 5)`, making the
update capability visible in the signature and call. Call sites mark exactly
the declared mut positions. A declared capability may be unused or used only
on some paths; callers and callback contracts still preserve it.

Mut parameters accept ordinary scalar and aggregate values, including text,
bytes, fixed arrays and collections. Whole-value rebinding, field writes and
element writes update the captured caller place. Arguments may be writable
variables, fields or indexed slots rooted in writable storage. A receiver is
not marked: the prelude `append(mut values, 1)` updates its writable binding
directly, and the call says so with the marker.

The guarantee covers the complete value, including managed descendants of records,
arrays, options, unions and collections. Assignment moves managed ownership, and
ordinary parameters borrow. A `mut` argument marks the caller's place to update;
a live read-only borrow may not overlap it. Use an explicit `copy(value)` before the
call when an independent prior value is needed. Two overlapping `mut` arguments
also violate exclusivity. Fresh local storage may be built and mutated.

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

A write through a parameter that is not declared `mut` is rejected at the write
site with `E_IMMUTABLE`:

```selka
# doc: expect-error E_IMMUTABLE
func overwrite(values: int[]) -> Unit:
    values[0] = 42

func main() -> int:
    mut values = [1]
    overwrite(values)
    return 0
```

### Values and caller mutation

Assignment preserves an independent value. A helper changes its caller's value
only through a `mut` parameter and a marked argument:

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

The same rule applies to nested managed values. A copy of an outer list keeps
its inner lists independent when one of them is changed. `copy(value)` creates the
independent owned contents before either value is changed:

```selka
# doc: expect 1
# doc: expect 9
func main(out: Stream) -> int:
    mut original = [[1]]
    mut copy = copy(original)
    copy[0][0] = 9
    print(out, original[0][0])
    print(out, copy[0][0])
    return 0
```

An exclusive `mut` borrow cannot overlap a live read-only borrow of the same
value. Make an independent read-only snapshot before the call if the callee must
read the old contents while changing the caller's value. Two overlapping `mut`
arguments are rejected too, such as `f(mut a, mut a)` or `f(mut a, mut a[0])`
(see [value semantics](value-semantics.md#the-rules)):

```selka
# doc: expect 23
func touch(mut target: int[], source: int[]) -> int:
    append(mut target, len(source))
    return len(source)


func main() -> int:
    mut a = [1, 2]
    const before = copy(a)
    mut seen = touch(mut a, before)
    return seen * 10 + len(a)
```

### Return values

Returning a managed value, or wrapping it in another value, does not give the
caller write access to the callee's input. The returned value is independent;
a caller can update its own copy. A write through a read-only parameter itself
remains `E_MUTATION_MARKER`.

```selka
# doc: expect 1
# doc: expect 9
func identity(values: int[]) -> int[]:
    return copy(values)


func main(out: Stream) -> int:
    mut original = [1]
    mut picked = identity(original)
    picked[0] = 9
    print(out, original[0])
    print(out, picked[0])
    return 0
```

Private helpers derive a return-origin bound from their bodies for ownership
optimization; it does not change the value rule seen by callers.

### Fresh local mutation

Definitely-fresh storage may be built, filled and mutated locally. A caller can
also write a returned value without changing the input:

```selka
# doc: expect 1
# doc: expect 9
func doubled(values: int[]) -> int[]:
    mut out: int[] = []
    for value in values:
        append(mut out, value * 2)
    return out


func main(out: Stream) -> int:
    mut values = [1, 2]
    mut extra = doubled(values)
    extra[0] = 9
    print(out, values[0])
    print(out, extra[0])
    return 0
```

## Capability method narrowing

`fs.read_only()` derives a read-only `Filesystem` from an existing one by
intersecting its permission mask. The derived capability is an ordinary typed
value, a new handle: it can be bound with or without a `with` scope, passed,
returned, copied and stored in a record field or a list, and every copy stays as
narrow as it was made. It performs no I/O when it is created and contributes no
effect of its own. The old
bracket spelling `restrict_resource[...]` is removed and reports
`E_REMOVED_SPELLING` naming the replacement.

```selka
# doc: check
func main(fs: Filesystem) -> int:
    with fs.read_only() as read_only:
        return 0
```

## Capabilities in record fields

A capability stored in a record field takes method syntax through the field
expression exactly as a bound local does: `ctx.fs.read_text(path)`,
`ctx.fs.open(path, "rb")`, `ctx.fs.dir("data")`, `ctx.env.get("HOME")` and
`ctx.net.host("127.0.0.1:8000")` check and lower like `fs = ctx.fs` followed by
`fs.read_text(path)`, with the same effects, permissions and traps. `Stream`
does the same for `print` and `write`. `Clock` and `Entropy` have no methods
whichever way they are held; pass them to `time.now(ctx.clock)` or
`random.from_entropy(ctx.entropy)`. An unknown method on a capability field is
`E_COLLECTION_METHOD` and names the methods that receiver does have.

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

Ordinary parameters borrow readonly values. A parameter the body
writes with no `mut` is rejected at the write with `E_IMMUTABLE`:

```selka
# doc: expect-error E_IMMUTABLE
func touch(values: int[]) -> Unit:
    values[0] = 1


func main() -> int:
    mut values = [1]
    touch(values)
    return 0
```

A declared mut parameter may be unused and need not be written on every return
path. Scalars, `str` and `bytes` can be reassigned through mut parameters too.
The retired `mutates(...)` clause and the opt-in `&` argument marker are removed
spellings that name `mut` in their diagnostics.

## Filesystem dir

`fs.dir(path)` derives a filesystem rooted at a string-literal path under the
receiver's root. It records the scope without touching the filesystem, so it
contributes no effect; every acquisition through the derived capability joins
the prefix and rejects any request that could leave the subtree. No symbolic link
is followed through the derived handle, in any run: a link on the way to a path,
at its end or as the narrowing's own prefix is refused as a `--restrict` grant
refuses it (an append through a final link included, which writes and creates
nothing), even without `--restrict` (the unnarrowed `Filesystem` of such a run
still follows links). `canonical_path` and `stat_follow_path` follow a link only
while it stays inside the narrowing.

The path is a literal so the checker can see that it stays inside the root; a
dynamic one is `E_FILESYSTEM_DIR`, whose message names
`filesystem.dir_at(fs, path) -> Filesystem fails str`, the library call for a
folder the program learns at run time (a command-line argument). It reads the
path as `fs` reads one, requires an existing directory reached without a link,
and returns the same narrowed handle ([A folder named at run
time](io.md#a-folder-named-at-run-time-filesystemdir_at)). Nothing else depends on
the literal: no report or manifest lists the folders a program narrows to, and
neither form contributes an effect.

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

`net.host(name)` narrows a `Network` to the single string-literal endpoint
`name`. Like `fs.dir`, it records the scope without touching the network, so it
contributes no effect; every acquisition through the derived capability requests
exactly that endpoint, so a `connect` wrapper needs no separate request string.
An endpoint outside the active `--allow-endpoint` grant is still denied.
`net.host(...)` also narrows a listener: `network.listen(scoped)` binds only when
the same literal endpoint appears in `--allow-listen=IP:PORT`, which is a
separate grant from an outbound connection. `network.open_poller(scoped)` takes
the same grant and serves many connections on one thread (see
[the event loop](standard-library.md#event-loop)); a program that only connects out opens
`network.open_client_poller(net)` instead, which needs no listen grant
([a client with no listener](standard-library.md#a-client-with-no-listener)).

A listen grant may name port 0, as in `--allow-listen=127.0.0.1:0`, so a program
binds a port the kernel chooses (and a `Poller` reports it with `network.port`)
instead of a fixed one. The match is verbatim: the `:0` grant permits only
`net.host("127.0.0.1:0")` and does not permit `127.0.0.1:8080`, and an `:8080`
grant does not permit port 0. `--allow-endpoint=IP:0` remains a usage error,
because dialing port 0 reaches nothing, and a blocking `network.listen` refuses a
port-0 narrowing with `err(2)` since a `Listener` cannot report its port.

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

### What a reader can tell about where a program connects

A function that narrows with `net.host("IP:PORT")` names the endpoint in its source, and a function handed a narrowed
Network reaches only that endpoint: `network.connect_to` and the other operations that take an address at run time
refuse any other address through it (`err(2)`), rather than reaching the narrowing's. A function that calls those
operations on an un-narrowed Network shows only where its address comes from (an environment variable, an argument, a
file): the address itself is in the launch, and under `--restrict` in its `--allow-endpoint` and `--allow-listen`
grants, which the runtime checks verbatim when the operation runs. Without `--restrict` the program reaches any address
its configuration names, as `fs` reaches any path. A search for `connect_to`, `connect_within_to`, `listen_at`,
`open_poller_at` and `dial_to` finds every place a run-time address is used; `acquire_resource` on a Network, which could
build a request at run time, is the standard library's own (`E_INTERNAL_NAME` in a program). See [addresses given at
run time](standard-library.md#addresses-given-at-run-time).

## Deterministic stand-ins

`time.simulated_clock`, `random.seeded_entropy`, `filesystem.memory`,
`environment.fixed`, `network.denied`, `network.memory` and `process.simulated_stop` build a `Clock`, `Entropy`,
`Filesystem`, `Environment`, `Network` or `Stop` that grants no real authority (a simulated stop is one no signal
reaches, requested only by `process.request_stop`): a
simulated clock reads the instant it was given until `time.advance` moves it, a
seeded entropy stream is reproducible, the filesystem lives in memory, the
environment holds fixed pairs and the network either refuses every connection
(`network.denied`) or connects only to listeners in the same memory
(`network.memory`). Building
one needs no capability and contributes no effect, and the runtime keeps every
stand-in apart from host-granted authority, so it can never reach a real
resource; `fs.dir(...)`, `read_only()`, `env.only(...)` and `net.host(...)` on
a stand-in derive stand-ins.

Real authority reaches a body through its parameters. A function without a
`Clock` input can build a simulated clock. Tests receive deterministic stand-ins
for supported capability parameters; a possible live `Host` input prevents
persistent test receipt reuse. A test with unresolved callback targets also
executes without persistent reuse.

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

`check` and `main` declare no `Clock` or `Filesystem`, yet they read a clock
and write a file: both are stand-ins, and neither function reads live clock or filesystem inputs. `selka test` hands the same stand-ins to a test that
declares a capability parameter; see
[capability parameters](tooling/guest-tests.md#capability-parameters).

## Related pages

- [Contracts](contracts.md) — why a `@requires`, `@ensures` or `@invariant` condition must be effect-free
- [Printing, files and command-line authority](io.md) — the capability values and the grants that provision them
- Transitive effect bounds (`docs/experiments/effects.md`) — the dated checkpoint this contract grew from
