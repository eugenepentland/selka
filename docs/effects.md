# Capabilities and effects

Authority in this language is carried by values: an entry point that wants to
touch the filesystem declares a `Filesystem` parameter, and the command line
decides whether to grant it. Effects are the other half of that story. Every
function has an inferred set of the capability-shaped things it can do, and a
function may declare a ceiling on that set which the checker enforces through the
whole call graph beneath it.

## Capability effects

The annotation goes after the return type: `noalloc`, `noio`, or an explicit
`effects(...)` list. It is a ceiling, not a description — the checker infers each
function's real effect set from its body and its resolved callees, then rejects
any function whose inferred set exceeds its declared bound. Because inference
follows resolved call identities rather than names, a bound on one function
constrains everything it transitively calls, including helpers written in other
modules. An omitted annotation imposes no bound; it does not mean "no effects".
That includes exported functions: the checker freezes the inferred mask as the
published interface ceiling, so a plain `export` is enough and an explicit
`noalloc`, `noio` or `effects(...)` is an opt-in narrowing that is still enforced
as an upper bound.

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

def main() -> int effects(output):
    print(report(6, 7))
    return 0
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
| `mutation` | writing caller-owned managed state reachable from an input, subject to the declared `mutates(...)` footprint |

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

Exceeding a bound is `E_EFFECT_BOUND`, reported at the annotation rather than at
the operation. The diagnostic names the shortest path it found from the bounded
function to the origin — here `count -> labels` — and attaches a related span at
the operation that first contributes the effect, so a bound broken three calls
down still points at the line responsible. Suppressing or discarding a result
does not erase its effects, and syntactically present branches count even when
they cannot be taken.

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

`effects(mutation)` permits externally observable writes to managed state.
A signature may also carry `mutates(a, b)`, naming the parameters whose
reachable mutable objects it may write. Names normalize to parameter positions,
an unknown name is an error at the declaration, and the clause requires the
`mutation` effect. Omitting the clause, or writing `mutates()`, permits no
caller-owned input to be written; a function with no `mutation` effect cannot
modify caller-owned managed state at all.

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
independent snapshot. This is a proof obligation created by a declared
`mutates(...)` clause: an unannotated helper's inferred writes carry no promise,
so forwarding two shared collections through it behaves like Python — sequential,
shared, with no overlap diagnostic.

```mylang
# doc: expect 7
def replace_first(values: list[int], replacement: int) -> None effects(mutation) mutates(values):
    values[0] = replacement

def main() -> int effects(managed_allocation, output):
    values = [1]
    replace_first(values, 7)
    print(values[0])
    return 0
```

An unpermitted write is rejected at the write site and reported against the
declared ceiling:

```mylang
# doc: expect-error E_MUTATION_PERMISSION
def overwrite(values: list[int]) -> None effects():
    values[0] = 42

def main() -> int:
    values = [1]
    overwrite(values)
    return 0
```

### Sharing, aliases and snapshots

Mutation follows the managed object, not the variable spelling. Two names bound
to the same list name one writable object, and a `mutates(...)` clause names the
parameter position rather than the caller's variable:

```mylang
# doc: expect 5
def set_first(values: list[int], replacement: int) -> None effects(mutation) mutates(values):
    values[0] = replacement


def main() -> int effects(managed_allocation, output):
    shared = [1, 2]
    alias = shared
    set_first(alias, 5)
    print(shared[0])
    return 0
```

A shallow `.copy()` severs only the copied outer container. Appending to the copy
does not change the original's length, but a managed descendant reached through
the copy is still the same object:

```mylang
# doc: expect 1
# doc: expect 9
def main() -> int effects(managed_allocation, output):
    original = [[1]]
    copy = original.copy()
    copy.append([2])
    copy[0][0] = 9
    print(len(original))
    print(original[0][0])
    return 0
```

If one argument is writable and another is promised read-only, the compiler must
prove the two input graphs disjoint. Unknown overlap is treated as overlap, so
two parameters of the same managed type reject even when a caller passes
unrelated values:

```mylang
# doc: expect-error E_MUTATION_OVERLAP
def touch(x: list[int], y: list[int]) -> None effects(mutation) mutates(x):
    x[0] = 1
    _ = y[0]


def use(a: list[int], b: list[int]) -> None effects(mutation) mutates(a):
    touch(a, b)


def main() -> int:
    a = [1]
    b = [2]
    use(a, b)
    return 0
```

Two writable aliases are permitted, and ordinary sequential ordering applies:

```mylang
# doc: expect 0
def pair(first: list[int], second: list[int]) -> None effects(mutation) mutates(first, second):
    first[0] = 1
    second[1] = 2


def use(values: list[int]) -> None effects(mutation) mutates(values):
    pair(values, values)


def main() -> int:
    values = [0, 0]
    use(values)
    return values[0] + values[1] - 3
```

The other repair is to build an independent snapshot where the writable and
read-only arguments meet. The snapshot allocation is visible as its own effect:

```mylang
# doc: expect 0
def touch(x: list[int], y: list[int]) -> None effects(mutation) mutates(x):
    x[0] = 1
    _ = y[0]


def use(a: list[int], b: list[int]) -> None effects(mutation, managed_allocation) mutates(a):
    snapshot = b.copy()
    touch(a, snapshot)


def main() -> int:
    a = [1]
    b = [2]
    use(a, b)
    return 0
```

### Return aliases

Returning a parameter, or wrapping it in a fresh container, does not make it
fresh. A function that returns an input publishes that alias unless its body
proves otherwise, so a caller that writes through the result still needs the
input's permission:

```mylang
# doc: expect-error E_MUTATION_PERMISSION
def identity(values: list[int]) -> list[int] effects():
    return values


def overwrite(values: list[int]) -> None effects():
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


def overwrite(values: list[int]) -> None effects(mutation) mutates(values):
    picked = identity(values)
    picked[0] = 0


def main() -> int:
    values = [1]
    overwrite(values)
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


def main() -> int effects(managed_allocation, output):
    values = [1, 2]
    extra = doubled(values)
    extra[0] = 9
    print(values[0])
    print(extra[0])
    return 0
```

## Related pages

- [Printing, files and command-line authority](io.md) — the capability values and the grants that provision them
- [Managed arenas](arenas.md) — why allocation inside an arena still contributes `managed_allocation`
- [Transitive effect bounds](experiments/effects.md) — the dated checkpoint this contract grew from
