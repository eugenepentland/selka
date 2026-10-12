# Capabilities and effects

Authority in this language is carried by values: an entry point that wants to
touch the filesystem declares a `Filesystem` parameter, and the command line
decides whether to grant it. Effects are the other half of that story. Every
function has an inferred set of the capability-shaped things it can do, and the
signature itself is the ceiling on that set.

## Capability effects

The signature is the whole contract: a `Stream` parameter permits `output`, a
`Filesystem` parameter `filesystem`, `Network` `network`, `Clock` `clock`,
`Entropy` `random`, `Environment` `environment`, `Host` `host`, a `mut`
parameter `mutation`, a callback parameter the bounded ceiling its own type
declares, and `managed_allocation` is always permitted. A parameter or result
whose type carries an owned resource contributes that resource's effect too. A
body that exceeds that ceiling is rejected in that body, and the diagnostic names
the parameter to add.

`noio` and an explicit `effects(...)` list go after the return type
and narrow that derived ceiling. `noalloc` uses the same position and is a
Core allocation warning contract, described below. A clause that permits exactly what the
parameters imply — `effects(host, managed_allocation)` on a function whose only
capability parameter is `Host` — is `W_DERIVED_EFFECTS` and says to remove it; a
clause that names an effect no parameter can supply is `E_DERIVED_EFFECTS` at the
clause, because it can never be satisfied. A capability parameter the body never
reads is `E_UNUSED_CAPABILITY`: the signature claims authority the body cannot
use, so the fix is to pass it on or drop it.

Because the ceiling follows from the signature, it is what the interfaces
publish: `list-interfaces` prints `ceiling(...)` for a declaration whose body was
never checked, the contract manifest and public schema publish it, and it is part
of `interface_sha256` while the inferred body set is not. A foreign declaration
(`extern func`) has no body to derive from, so its `effects(...)`
clause stays its ceiling as written.

A compile-time `str` literal is an immutable constant, not an allocation:
`print("hi")` under `effects(output)` and `len("abc")` under `noalloc` are
accepted. A computed string — `"a" + "b"`, a slice, or a conversion — still
contributes `managed_allocation`, and so does a `list`, `dict` or `bytes`
literal.

```mylang
# doc: expect 42
func area(width: int, height: int) -> int:
    return width * height

func report(width: int, height: int) -> int noalloc:
    return area(width, height)

func main(out: Stream) -> int effects(output):
    out.print(report(6, 7))
    return 0
```

## The signature is the ceiling

Every function is held to the ceiling its parameter list implies, so a body that
reaches an effect no parameter supplies is rejected where the effect happens, and
the rejection names the parameter to add. Here `emit` takes the stream it prints
through, and `relay` must take one too before it can call it.

```mylang
# doc: expect 7
func emit(out: Stream, value: int) -> Unit:
    out.print(value)

func relay(out: Stream, value: int) -> Unit:
    emit(out, value)

func main(out: Stream) -> int:
    relay(out, 7)
    return 0
```

A capability parameter the body never reads is `E_UNUSED_CAPABILITY`, because the
signature claims authority the body cannot use:

```mylang
# doc: expect-error E_UNUSED_CAPABILITY
func equal(host: Host, a: int, b: int) -> bool:
    return a == b

func main(host: Host) -> int:
    if equal(host, 1, 1):
        return 0
    return 1
```

## The vocabulary

There are nine effects. `effects(...)` names the allowed set exactly; an empty
list allows none, order carries no meaning, and an unknown or repeated name is a
source error.

| Effect | Contributed by |
| --- | --- |
| `managed_allocation` | creating or growing a list, dictionary, string or byte string; a compile-time `str` literal is an immutable constant and is not an allocation |
| `filesystem` | `open` and the whole-path file helpers |
| `network` | the network capability surface |
| `clock` | reading wall-clock time |
| `random` | drawing from the entropy stream |
| `environment` | reading process environment variables |
| `output` | `print` |
| `host` | calling a host-provided implementation, such as an `extern func` |
| `mutation` | writing caller-owned managed state reachable from an input, subject to the declared `mut` parameter set |

`noio` excludes input/output effects. `noalloc` asks the build to inspect the
ownership-expanded Core body for managed heap and runtime scratch allocation,
before optimization. Every callee and cold path contributes. A violation reports
`W_NOALLOC_ALLOCATES` without failing the build, run or test. `check` and
`check-project` do not compute this contract. `mylang lint --gate` turns the same
witness into the blocking `noalloc-allocates` rule (`L_NOALLOC_ALLOCATES`).
Explicit `effects(...)` lists retain their guest-level effect ceilings.
`noio` excludes `filesystem`, `network` and `output` together, and permits allocation, the clock,
randomness and the environment. Neither promises determinism, termination, bounded
memory or freedom from traps. Writing definitely-fresh local storage or fixed
scalar/record storage is not an observable effect; writing caller-owned managed
state is the separate `mutation` effect described below. A function that needs one effect and no others writes it out, as
in `func present(fs: Filesystem, path: str) -> bool effects(filesystem):`.

Callback parameters follow the same rule directionally: a callable whose
declared ceiling is a subset of the destination contract's ceiling may fill that
slot, but a call through a stored or returned callback uses the destination
ceiling, not the concrete target's smaller ceiling.

## What a bound rejects

Exceeding a bound is `E_EFFECT_BOUND`. With an explicit clause it is reported at
the annotation, and with a signature-derived ceiling it is reported at the
operation or call that reaches the effect. Either way the diagnostic names the
shortest path it found from the bounded function to the origin — here
`count -> labels` — and attaches a related span at the operation that first
contributes the effect, so a bound broken three calls down still points at the
line responsible. Suppressing or discarding a result does not erase its effects,
and syntactically present branches count even when they cannot be taken.

```mylang
# doc: expect-error E_EFFECT_BOUND
func labels() -> str[]:
    mut names: str[] = []
    names.append("alpha")
    return names

func count() -> int effects():
    return len(labels())

func main() -> int:
    return count()
```

## Limits

- A function takes at most one effect annotation. `noio` and `effects(...)`
  constrain inferred guest effects; `noalloc` is a separate Core warning promise.
- Frontend effect facts remain available to capabilities, generic checking and
  interface summaries. `check` and `check-project` do no whole-program Core
  allocation work, including after a bounded body changes.
- `build`, `run`, `build --run` and `test` report `W_NOALLOC_ALLOCATES` at the
  allocation site, naming the bounded function and callee. Explicit independent copies and
  runtime scratch count even on cold paths. Unresolved callbacks and foreign
  calls count conservatively. An unsupported concrete body warns with its reason.
  Concrete generic instances receive the same check; no annotation is required
  on callees. These warnings do not change the command's success status.
- `lint` reports `L_NOALLOC_ALLOCATES`; its `noalloc-allocates` rule defaults to
  block mode in every profile, making `lint --gate` exit 3. A reasoned waiver
  uses the ordinary lint mechanism. `cost` continues to show static allocation
  sites. Stack storage is permitted; compiler allocation and process startup
  are outside this function contract.
- The bound is not an authority grant. A function annotated `effects(filesystem)`
  still needs a `Filesystem` value to do anything with the filesystem, and that
  value comes from the entry point's parameters — which `mylang run` provisions
  by default and `--restrict` withholds until a matching `--allow-*` grants it.
- A contract condition (`@requires`, `@ensures`, `@invariant` and each `old(...)`)
  is held to the empty ceiling apart from `managed_allocation`, judged by the
  same inference: any other effect it or a function it calls has is
  `E_CONTRACT_EFFECT` ([contracts](contracts.md#conditions-are-pure)).

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
not marked: `values.append(1)` updates its writable binding directly.

The guarantee covers the complete value, including managed descendants of records,
arrays, options, unions and collections. Assignment can move ownership; ordinary
parameters borrow. A `mut` argument exclusively borrows the caller's place to
update. An overlapping read-only argument must use an explicit independent copy.
Multiple mutable child arguments rooted in the same collection are conservatively
rejected, even for distinct constant indices. Definitely-fresh local storage may
always be built and mutated.

```mylang
# doc: expect 7
func replace_first(mut values: int[], replacement: int) -> Unit effects(mutation):
    values[0] = replacement

func main(out: Stream) -> int effects(managed_allocation, output):
    mut values = [1]
    replace_first(mut values, 7)
    out.print(values[0])
    return 0
```

A write through a parameter that is not declared `mut` is rejected at the write
site with `E_IMMUTABLE`:

```mylang
# doc: expect-error E_IMMUTABLE
func overwrite(values: int[]) -> Unit effects(mutation):
    values[0] = 42

func main() -> int:
    mut values = [1]
    overwrite(values)
    return 0
```

### Values and caller mutation

Use `.copy()` to preserve an independent value. A helper changes its caller's
value only through a `mut` parameter and a marked argument:

```mylang
# doc: expect 1
# doc: expect 5
func set_first(mut values: int[], replacement: int) -> Unit effects(mutation):
    values[0] = replacement


func main(out: Stream) -> int effects(managed_allocation, output):
    mut original = [1, 2]
    mut copy = original.copy()
    set_first(mut copy, 5)
    out.print(original[0])
    out.print(copy[0])
    return 0
```

The same rule applies to nested managed values. An explicit copy of an outer
list recursively copies its managed children, keeping both values independent:

```mylang
# doc: expect 1
# doc: expect 9
func main(out: Stream) -> int effects(managed_allocation, output):
    mut original = [[1]]
    mut copy = original.copy()
    copy[0][0] = 9
    out.print(original[0][0])
    out.print(copy[0][0])
    return 0
```

A read-only argument cannot borrow a root that the same call mutably borrows.
Copy before the call when the callee needs the original snapshot while changing
the caller's value. Multiple mutable arguments must also have exclusive roots;
`f(mut a, mut a)` and two children rooted in `a` are rejected (see
[value semantics](value-semantics.md#the-rules)).

```mylang
# doc: expect 23
func touch(mut target: int[], source: int[]) -> int effects(mutation, managed_allocation):
    target.append(len(source))
    return len(source)


func main() -> int:
    mut a = [1, 2]
    const snapshot = a.copy()
    mut seen = touch(mut a, snapshot)
    return seen * 10 + len(a)
```

### Return values

Returning an owned managed value moves it to the caller. A borrowed parameter
cannot become an independent result without `.copy()`. That copy can allocate
and the function's effect ceiling must allow `managed_allocation`. A write
through the borrowed parameter itself remains rejected.

```mylang
# doc: expect 1
# doc: expect 9
func identity(values: int[]) -> int[]:
    return values.copy()


func main(out: Stream) -> int effects(managed_allocation, output):
    mut original = [1]
    mut picked = identity(original)
    picked[0] = 9
    out.print(original[0])
    out.print(picked[0])
    return 0
```

The compiler checks each move and borrow before lowering. A returned owner must
remain valid independently of the caller's later input replacement; no reference
count or implicit copy is added to repair an invalid return.

### Fresh local mutation

Definitely-fresh storage may be built, filled and mutated locally without a
`mutation` effect; the existing `managed_allocation` effect still applies. A
caller can also write a returned value without changing the input:

```mylang
# doc: expect 1
# doc: expect 9
func doubled(values: int[]) -> int[] effects(managed_allocation):
    mut out: int[] = []
    for value in values:
        out.append(value * 2)
    return out


func main(out: Stream) -> int effects(managed_allocation, output):
    mut values = [1, 2]
    mut extra = doubled(values)
    extra[0] = 9
    out.print(values[0])
    out.print(extra[0])
    return 0
```

## Capability method narrowing

`fs.read_only()` derives a read-only `Filesystem` from an existing one by
intersecting its permission mask. Use the dependent capability in a `with`
scope, so its provider stays alive through every use. It can be borrowed by
calls within that scope; storing or returning it beyond the scope is rejected.
Creating it performs no I/O and contributes no effect of its own. The old
bracket spelling `restrict_resource[...]` is removed and reports
`E_REMOVED_SPELLING` naming the replacement.

```mylang
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

```mylang
# doc: check
record Context:
    fs: Filesystem
    env: Environment

func read_note(ctx: Context, path: str) -> int:
    match ctx.fs.read_text(path):
        case Ok(text):
            return len(text)
        case Err(_):
            return -1

func main(fs: Filesystem, env: Environment) -> int:
    mut ctx = Context(fs=fs, env=env)
    return read_note(ctx, "note.txt") + len(ctx.env.names())
```

## Declaration-site mutation errors

Ordinary parameters borrow read-only storage. A parameter the body
writes with no `mut` is rejected at the write with `E_IMMUTABLE`:

```mylang
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
the prefix and rejects any request that could leave the subtree.

```mylang
# doc: check
resource File: filesystem

result Open:
    ok: File,
    err: int

func main(fs: Filesystem) -> int:
    with fs.dir("data") as scoped:
        mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([42u8])
        match acquire_resource[Open](scoped, request):
            case Open.ok(file):
                _ = file
                return 0
            case Open.err(code):
                return -code
```

## Network host

`net.host(name)` narrows a `Network` to the single string-literal endpoint
`name`. Like `fs.dir`, it records the scope without touching the network, so it
contributes no effect; every acquisition through the derived capability requests
exactly that endpoint, so a `connect` wrapper needs no separate request string.
An endpoint outside the active `--allow-endpoint` grant is still denied.

```mylang
# doc: check
resource Socket: network

result Connected:
    ok: Socket,
    err: int

func main(net: Network) -> int:
    # The narrowed capability pins the endpoint; the request below is ignored.
    with net.host("127.0.0.1:8000") as scoped:
        mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([0u8])
        match acquire_resource[Connected](scoped, request):
            case Connected.ok(socket):
                _ = socket
                return 0
            case Connected.err(code):
                return code
```

## Deterministic stand-ins

`time.simulated_clock`, `random.seeded_entropy`, `filesystem.memory`,
`environment.fixed` and `network.denied` build a `Clock`, `Entropy`,
`Filesystem`, `Environment` or `Network` that grants no real authority: a
simulated clock reads the instant it was given until `time.advance` moves it, a
seeded entropy stream is reproducible, the filesystem lives in memory, the
environment holds fixed pairs and the network refuses every connection. Building
one needs no capability and contributes no effect, and the runtime keeps every
stand-in apart from host-granted authority, so it can never reach a real
resource; `fs.dir(...)`, `read_only()`, `env.only(...)` and `net.host(...)` on
a stand-in derive stand-ins.

Real authority reaches a body only through its parameters. A function whose
parameters supply no `clock` can therefore hold only a simulated clock, and
reading it is not an effect of that function: it neither widens the function's
inferred effects nor breaks the ceiling its signature implies. The same holds for
`random`, `filesystem`, `network` and `environment`. A function with a `Host`
parameter and an `extern func` can reach the host by other means,
so for them nothing is contained. That is what lets a caller with no capability
at all test code that takes one:

```mylang
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
    out.print(check(), remember(filesystem.memory(), "hi"))
    return 0
```

`check` and `main` declare no `Clock` or `Filesystem`, yet they read a clock
and write a file: both are stand-ins, and neither function's effects include
`clock` or `filesystem`. `mylang test` hands the same stand-ins to a test that
declares a capability parameter; see
[capability parameters](tooling/guest-tests.md#capability-parameters).

## Related pages

- [Contracts](contracts.md) — why a `@requires`, `@ensures` or `@invariant` condition must be effect-free
- [Printing, files and command-line authority](io.md) — the capability values and the grants that provision them
- [Transitive effect bounds](experiments/effects.md) — the dated checkpoint this contract grew from
