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

`noalloc`, `noio` and an explicit `effects(...)` list go after the return type
and only ever narrow that derived ceiling. A clause that permits exactly what the
parameters imply — `effects(host, managed_allocation)` on a function whose only
capability parameter is `Host` — is `W_DERIVED_EFFECTS` and says to remove it; a
clause that names an effect no parameter can supply is `E_DERIVED_EFFECTS` at the
clause, because it can never be satisfied. A capability parameter the body never
reads is `E_UNUSED_CAPABILITY`: the signature claims authority the body cannot
use, so the fix is to pass it on or drop it.

Because the ceiling follows from the signature, it is what the interfaces
publish: `list-interfaces` prints `ceiling(...)` for a declaration whose body was
never checked, the contract manifest and public schema publish it, and it is part
of `interface_sha256` while the inferred body set is not. A host declaration
(`host def`, `extern def`) has no body to derive from, so its `effects(...)`
clause stays its ceiling as written.

A compile-time `str` literal is an immutable constant, not an allocation:
`print("hi")` under `effects(output)` and `len("abc")` under `noalloc` are
accepted. A computed string — `"a" + "b"`, a slice, or a conversion — still
contributes `managed_allocation`, and so does a `list`, `dict` or `bytes`
literal.

```mylang
# doc: expect 42
def area(width: int, height: int) -> int:
    return width * height

def report(width: int, height: int) -> int noalloc:
    return area(width, height)

def main(out: Stream) -> int effects(output):
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
def emit(out: Stream, value: int) -> None:
    out.print(value)

def relay(out: Stream, value: int) -> None:
    emit(out, value)

def main(out: Stream) -> int:
    relay(out, 7)
    return 0
```

A capability parameter the body never reads is `E_UNUSED_CAPABILITY`, because the
signature claims authority the body cannot use:

```mylang
# doc: expect-error E_UNUSED_CAPABILITY
def equal(host: Host, a: int, b: int) -> bool:
    return a == b

def main(host: Host) -> int:
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
| `managed_allocation` | creating or growing a list, dictionary, string or byte string, including `escape` out of an arena; a compile-time `str` literal is an immutable constant and is not an allocation |
| `filesystem` | `open` and the whole-path file helpers |
| `network` | the network capability surface |
| `clock` | reading wall-clock time |
| `random` | drawing from the entropy stream |
| `environment` | reading process environment variables |
| `output` | `print` |
| `host` | calling a host-provided implementation, such as an `extern def` |
| `mutation` | writing caller-owned managed state reachable from an input, subject to the declared `mut` parameter set |

`noalloc` and `noio` are shorthands for the two common ceilings. `noalloc`
excludes `managed_allocation` and permits everything else. `noio` excludes
`filesystem`, `network` and `output` together, and permits allocation, the clock,
randomness and the environment. Neither promises determinism, termination, bounded
memory or freedom from traps. Writing definitely-fresh local storage or fixed
scalar/record storage is not an observable effect; writing caller-owned managed
state is the separate `mutation` effect described below. A function that needs one effect and no others writes it out, as
in `def present(fs: Filesystem, path: str) -> bool effects(filesystem):`.

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
def labels() -> list[str]:
    names: list[str] = []
    names.append("alpha")
    return names

def count() -> int noalloc:
    return len(labels())

def main() -> int:
    return count()
```

## Limits

- A function takes at most one effect annotation, and it is a ceiling on the
  inferred set rather than a signature the callee must match exactly.
- `managed_allocation` is a guest-level classification. It says nothing about the
  host allocations the runtime makes for frames, stack slots or result wrappers,
  so a `noalloc` function is not a promise of an allocation-free process.
- The bound is not an authority grant. A function annotated `effects(filesystem)`
  still needs a `Filesystem` value to do anything with the filesystem, and that
  value comes from the entry point's parameters — which `mylang run` provisions
  by default and `--restrict` withholds until a matching `--allow-*` grants it.
- The bytecode validator recomputes every summary from the emitted instructions
  and rejects a forged annotation, so an effect cannot be hidden by editing
  metadata.

## Mutation contracts

A parameter a function writes through is declared `name: mut T`, and those
parameters are the function's mutation footprint: the positions whose reachable
mutable objects the call may write. A caller marks each argument it binds to one
of them — `restock(mut inventory, "bolt", 5)` — so the write is visible on the
call line as well as in the signature. The marker is required exactly where the
callee declares `mut` and rejected where it does not, and a `mut` parameter the
body never writes is an error too, because a stale marker is the lie the spelling
exists to prevent. A receiver is never marked: `values.append(1)` and
`mapping.sort()` need nothing.

`mut` is accepted only on a type that can carry a write back to the caller:
`list`, `dict`, `class`, `Cell`, `[N]T`, `byte_buffer`, and a `record`, union,
option or result holding one. A scalar, `str` or `bytes` parameter declared `mut`
is rejected, because no write through it could be observed. A fixed array is a
value with no reference of its own, so a `mut [N]T` parameter names the caller's
variable itself and its argument must be one; see
[passing an array to be written](records-and-unions.md#passing-an-array-to-be-written).

The guarantee is for the duration of the call and covers lists, dictionaries,
`Cell`, and mutable descendants reached through records, arrays, options, unions,
collections and recursive graphs. A value-record copy does not sever the origin
of its managed descendants, and returning or wrapping an input does not make it
fresh. Definitely-fresh local storage may always be built and mutated. A shallow
`.copy()` severs only the outer container.

If a writable input graph may overlap a read-only input, the call rejects unless
the compiler can prove the two are disjoint; passing the same value twice is the
simplest case. Two writable aliases are permitted and ordinary sequential
ordering applies. Unknown possible overlap is treated as overlap, so a caller
that intends two independent arguments either declares both writable or builds an
independent snapshot.

```mylang
# doc: expect 7
def replace_first(values: mut list[int], replacement: int) -> None effects(mutation):
    values[0] = replacement

def main(out: Stream) -> int effects(managed_allocation, output):
    values = [1]
    replace_first(mut values, 7)
    out.print(values[0])
    return 0
```

A write through a parameter that is not declared `mut` is rejected at the write
site with the declaration to paste:

```mylang
# doc: expect-error E_MUTATION_MARKER
def overwrite(values: list[int]) -> None effects(mutation):
    values[0] = 42

def main() -> int:
    values = [1]
    overwrite(values)
    return 0
```

### Sharing, aliases and snapshots

Mutation follows the managed object, not the variable spelling. Two names bound
to the same list name one writable object, and a `mut` parameter names a
parameter position rather than the caller's variable:

```mylang
# doc: expect 5
def set_first(values: mut list[int], replacement: int) -> None effects(mutation):
    values[0] = replacement


def main(out: Stream) -> int effects(managed_allocation, output):
    shared = [1, 2]
    alias = shared
    set_first(mut alias, 5)
    out.print(shared[0])
    return 0
```

A shallow `.copy()` severs only the copied outer container. Appending to the copy
does not change the original's length, but a managed descendant reached through
the copy is still the same object:

```mylang
# doc: expect 1
# doc: expect 9
def main(out: Stream) -> int effects(managed_allocation, output):
    original = [[1]]
    copy = original.copy()
    copy.append([2])
    copy[0][0] = 9
    out.print(len(original))
    out.print(original[0][0])
    return 0
```

If one argument is writable and another is promised read-only, the compiler must
prove the two input graphs disjoint. Unknown overlap is treated as overlap, so
two parameters of the same managed type reject even when a caller passes
unrelated values:

```mylang
# doc: expect-error E_MUTATION_OVERLAP
def touch(x: mut list[int], y: list[int]) -> None effects(mutation):
    x[0] = 1
    _ = y[0]


def use(a: mut list[int], b: list[int]) -> None effects(mutation):
    touch(mut a, b)


def main() -> int:
    a = [1]
    b = [2]
    use(mut a, b)
    return 0
```

Two writable aliases are permitted, and ordinary sequential ordering applies:

```mylang
# doc: expect 0
def pair(first: mut list[int], second: mut list[int]) -> None effects(mutation):
    first[0] = 1
    second[1] = 2


def use(values: mut list[int]) -> None effects(mutation):
    pair(mut values, mut values)


def main() -> int:
    values = [0, 0]
    use(mut values)
    return values[0] + values[1] - 3
```

The other repair is to build an independent snapshot where the writable and
read-only arguments meet. The snapshot allocation is visible as its own effect:

```mylang
# doc: expect 0
def touch(x: mut list[int], y: list[int]) -> None effects(mutation):
    x[0] = 1
    _ = y[0]


def use(a: mut list[int], b: list[int]) -> None effects(mutation, managed_allocation):
    snapshot = b.copy()
    touch(mut a, snapshot)


def main() -> int:
    a = [1]
    b = [2]
    use(mut a, b)
    return 0
```

### Return aliases

Returning a parameter, or wrapping it in a fresh container, does not make it
fresh. A function that returns an input publishes that alias unless its body
proves otherwise, so a caller that writes through the result still needs the
input's permission:

```mylang
# doc: expect-error E_MUTATION_MARKER
def identity(values: list[int]) -> list[int] effects():
    return values


def overwrite(values: list[int]) -> None effects(mutation):
    picked = identity(values)
    picked[0] = 0


def main() -> int:
    values = [1]
    overwrite(values)
    return 0
```

Declaring the write on the original parameter accepts the same program:

```mylang
# doc: expect 0
def identity(values: list[int]) -> list[int] effects():
    return values


def overwrite(values: mut list[int]) -> None effects(mutation):
    picked = identity(values)
    picked[0] = 0


def main() -> int:
    values = [1]
    overwrite(mut values)
    return 0
```

Private helpers derive a precision return-origin bound from their bodies. The
language currently has no syntax for a narrower declared return-origin, so an
exported declaration defaults to `unknown`, never `fresh`.

### Fresh local mutation

Definitely-fresh storage may be built, filled and mutated locally without a
`mutation` effect; the existing `managed_allocation` effect still applies. A
caller can also write a result the compiler proved fresh even though the same
function borrowed its input:

```mylang
# doc: expect 1
# doc: expect 9
def doubled(values: list[int]) -> list[int] effects(managed_allocation):
    out: list[int] = []
    for value in values:
        out.append(value * 2)
    return out


def main(out: Stream) -> int effects(managed_allocation, output):
    values = [1, 2]
    extra = doubled(values)
    extra[0] = 9
    out.print(values[0])
    out.print(extra[0])
    return 0
```

## Capability method narrowing

`fs.read_only()` derives a read-only `Filesystem` from an existing one by
intersecting its permission mask. The derived capability is an ordinary typed
value: it can be passed, returned and stored in a record or class field, but it
performs no I/O when it is created and contributes no effect of its own. The old
bracket spelling `restrict_resource[...]` is removed and reports
`E_REMOVED_SPELLING` naming the replacement.

```mylang
# doc: check
def main(fs: Filesystem) -> int:
    read_only = fs.read_only()
    return 0
```

## Declaration-site mutation errors

The `mut` spelling is checked in both directions, always. A parameter the body
writes with no `mut` is rejected at its declaration with the parameter to paste:

```mylang
# doc: expect-error E_MUTATION_MARKER
def touch(values: list[int]) -> None:
    values[0] = 1


def main() -> int:
    values = [1]
    touch(values)
    return 0
```

A `mut` parameter the body never writes is rejected too, so a marker cannot go
stale, and a `mut` on a type with nothing to write — a scalar, `str` or `bytes`
— is rejected at the declaration. The retired `mutates(...)` clause and the
opt-in `&` argument marker are removed spellings that name `mut` in their
diagnostics.

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

def main(fs: Filesystem) -> int:
    scoped = fs.dir("data")
    request: [1]u8 = [42u8]
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

def main(net: Network) -> int:
    # The narrowed capability pins the endpoint; the request below is ignored.
    scoped = net.host("127.0.0.1:8000")
    request: [1]u8 = [0u8]
    match acquire_resource[Connected](scoped, request):
        case Connected.ok(socket):
            _ = socket
            return 0
        case Connected.err(code):
            return code
```

## Related pages

- [Printing, files and command-line authority](io.md) — the capability values and the grants that provision them
- [Managed arenas](arenas.md) — why allocation inside an arena still contributes `managed_allocation`
- [Transitive effect bounds](experiments/effects.md) — the dated checkpoint this contract grew from
