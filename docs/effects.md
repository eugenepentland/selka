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

There are eight effects. `effects(...)` names the allowed set exactly; an empty
list allows none, order carries no meaning, and an unknown or repeated name is a
source error.

| Effect | Contributed by |
| --- | --- |
| `managed_allocation` | creating or growing a list, dictionary, string or byte string, including `escape` out of an arena |
| `filesystem` | `open` and the whole-path file helpers |
| `network` | the network capability surface |
| `clock` | reading wall-clock time |
| `random` | drawing from the entropy stream |
| `environment` | reading process environment variables |
| `output` | `print` |
| `host` | calling a host-provided implementation, such as an `extern def` |

`noalloc` and `noio` are shorthands for the two common ceilings. `noalloc`
excludes `managed_allocation` and permits everything else. `noio` excludes
`filesystem`, `network` and `output` together, and permits allocation, the clock,
randomness and the environment. Neither promises determinism, termination, bounded
memory or freedom from traps, and local mutation of fixed storage is not an
effect at all. A function that needs one effect and no others writes it out, as
in `def present(fs: Filesystem, path: str) -> bool effects(filesystem):`.

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

## Related pages

- [Printing, files and command-line authority](io.md) — the capability values and the grants that provision them
- [Managed arenas](arenas.md) — why allocation inside an arena still contributes `managed_allocation`
- [Transitive effect bounds](experiments/effects.md) — the dated checkpoint this contract grew from
