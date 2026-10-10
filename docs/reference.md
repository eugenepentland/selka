# The compiler-derived reference

> **Status: shipped.** `src/reference.zig` (facts), `src/reference_command.zig`
> (flags, output, exit status) and the `reference` route in `src/main.zig`'s
> dispatch are all in the tree, exercised by `src/reference_test.zig` and by the
> registered `zig build test-agent-usefulness` step. `mylang reference --query
> TERM` answers from an installed binary today; the other compiler-derived
> surfaces remain `mylang --features`, `mylang list-declarations`,
> `mylang list-interfaces` and `mylang schema-project`.

The reference answers questions about *the executable that runs it*. Nothing on this
page is a copy of a list the compiler keeps somewhere else: feature status, boundaries,
exclusions, standard-library signatures, builtin spellings and collection-method
arities are read at run time from data embedded in the binary — `src/features.json`,
the twelve modules behind `src/standard_library.zig`, the checker's own builtin
tables, and the versioned `module interfaces v1` listing it publishes. The curated
prose that no table can derive lives in `src/reference_text.zig`, is versioned with
the executable, and every guest example it carries is a fenced `mylang` block on this
page, so `mylang doctest .` executes it against the same binary that reports it.

## What it answers

| Category | Reported from | A query such as |
| --- | --- | --- |
| `syntax` | `src/reference_text.zig` | `stream-output` |
| `feature` | `src/features.json` `implemented` | `standard-sort` |
| `limit` | `src/features.json` `limits` | `floating_point` |
| `exclusion` | `src/features.json` `unsupported`, `native_exclusions`, `removed` | `capturing-closures`, `legacy-syntax` |
| `declaration` | the embedded standard modules, listed by the compiler | `sort_ints` |
| `builtin` | `io_builtins.zig`, `prelude_builtins.zig`, `prelude.zig`, `float_intrinsics.zig` | `print`, `sorted` |
| `method` | `buffer_operations.zig` | `split`, `pop` |

## Fact status

F1 of the agent-usefulness plan asks for declared ceilings, inferred summaries and
analysis status to be separated everywhere they are reported. The envelope carries
them in different fields, and an unavailable fact is `null` rather than an empty set
presented as a fact.

| Field | Meaning |
| --- | --- |
| `library.status` | `checked` — the embedded modules' bodies were checked; `declaration-only` — only declarations were parsed (the reason says why); `unavailable` — no standard-library fact is available at all. |
| `declarations` | `null` when the analysis is `unavailable`; the matched declaration records otherwise, possibly none. |
| `analysis` (per declaration) | `checked` — the inferred `effects` are the checker's own for a checked instantiation; `template` — the declaration is generic and nothing instantiated it here, so no inferred set is published (its `ceiling` still is); `declaration-only` — bodies were not checked; `declared` — a type, resource or constraint declaration, which has no body. |
| `effects` | The checked inferred effect set. `null` whenever `analysis` is not `checked`; `[]` means "inferred: no effects", which is a fact, not a gap. |
| `ceiling` | The ceiling the signature implies — one effect per capability parameter, `mutation` per `mut` parameter, a callback parameter's bounded ceiling, and `managed_allocation`, which is always permitted — narrowed by an explicit `noalloc`, `noio` or `effects(...)` clause. It follows from the declaration alone, so it is published whether or not bodies were checked. |
| `mutates` | The declaration's mutation footprint: the zero-based positions of its `mut name: T` parameters, or `null` for a declaration with no parameter list of its own. |

The conservative full effect vocabulary the compiler falls back to when it could not
infer anything is deliberately **not** published as an inference: a generic template
reports `effects: null` with `analysis: "template"`, which is the difference between a
fact and a fallback that the baseline report singled out.

`effects` and `ceiling` answer different questions. `effects` is what the checked body
does; `ceiling` is what the signature permits, and it is the one an interface
fingerprint carries, so a body edit inside the ceiling changes `body_sha256` and leaves
`interface_sha256` alone. `list-interfaces` prints `ceiling(...)` for every function
and `effects(...)` only when a body was checked.

## Query, format and exit status

Matching is a **case-insensitive substring** of each fact's slug, name, summary,
signature, families or source table, and the answer lists the matches in a fixed
category order, each category sorted by key, so two runs of the same query are
byte-identical. The envelope's `match` field is `exact` when the term equals a fact's
whole key, `substring` when it only appears inside one, and `none` when nothing
matched — an unmatched query is a normal answer that says so, not an error. A malformed
request (a missing or empty `--query`, an unknown flag, a `--format` other than `text`
or `json`) writes the usage line to stderr and exits 2.

The intended invocations are:

```bash
mylang reference --query sort
mylang reference --query standard-sort --format=json
mylang reference --query capturing-closures
```

`--format=text` (the default) prints one labelled block per fact. `--format=json` emits
a `reference-v1` envelope:

```json
{
  "version": "reference-v1",
  "query": "sort_ints",
  "match": "substring",
  "count": 1,
  "language": { "version": "0.1.0", "primary_backend": "llvm" },
  "library": { "status": "checked", "reason": null, "modules": 12, "exports": 168 },
  "declarations": [
    {
      "name": "sort::sort_ints",
      "kind": "function",
      "signature": "func(values:list[i64])->list[i64]",
      "analysis": "checked",
      "effects": ["managed_allocation"],
      "ceiling": ["managed_allocation"],
      "mutates": null
    }
  ]
}
```

The other arrays (`syntax`, `features`, `limits`, `exclusions`, `builtins`, `methods`)
carry the matched records of their categories and are empty when the term matched none
of them.

## Why it works outside a checkout

The engine opens no file and reads no environment variable. Its whole filesystem
surface is one in-memory string: the synthesized entry module that imports the
embedded standard modules, which `project.Project` already answers from
`src/standard_library.zig` before any provider is consulted. `EntryReader.read` returns
`NotFound` for every other path, and a unit test asserts exactly that, so a reference
answer cannot silently depend on the checkout that happens to be nearby. The one thing
the reference *does* read from the checkout is `src/features.json` — embedded at
compile time, so it travels with the binary.

## Curated syntax examples

These are the boundaries where mylang differs from Python most often, and each block
below is executed by the documentation gate. The same text is what
`mylang reference --query <id>` reports, with `python` naming the difference.

Locals have lexical block scope. Declare a binding with `const` or `mut`; assignment
updates a writable binding. Declare shared results before a branch or loop when code
after that block needs them. Active names cannot be shadowed.

```mylang
# doc: expect 6
func main() -> int:
    mut total = 0
    for value in [1, 2, 3]:
        total += value
    return total
```

`range()` is a comprehension source exactly as it is a loop source.

```mylang
# doc: expect 9
func main() -> int:
    mut squares = [for x in range(4) yield x * x]
    return squares[3]
```

There are no tuples: a `record` declares named fields and a top-level function takes
its state as a parameter.

```mylang
# doc: expect 21
record Pair:
    left: int
    right: int

func swap(pair: Pair) -> Pair effects():
    return Pair(left=pair.right, right=pair.left)

func main() -> int:
    mut swapped = swap(Pair(left=1, right=2))
    return swapped.left * 10 + swapped.right
```

Printing goes through a `Stream` parameter rather than an ambient stdout.

```mylang
# doc: expect hello
func main(out: Stream) -> int:
    out.print("hello")
    return 0
```

File access needs a capability parameter, and using it shows up in the effect set.

```mylang
# doc: check
func read_length(fs: Filesystem) -> int effects(filesystem):
    match fs.read_text("answer.txt"):
        case Ok(text):
            return len(text)
        case Err(_):
            return 0 - 1
```

Integers have a fixed width, and character/code-point helpers are not spelled the way
Python spells them.

```mylang
# doc: expect 7
func main() -> int:
    mut big = 9223372036854775807
    return big % 10
```

The bare builtin spellings an agent reaches for first.

```mylang
# doc: expect 9
func main() -> int:
    mut values = [3, 1, 2]
    mut ordered = sorted(values)
    return sum(ordered) + len(ordered)
```

## Related surfaces

`mylang list-interfaces` prints the same declarations as text for a project of your
own, `mylang schema-project --schema-report` prints the checked schema with wire
shapes, `mylang list-declarations` prints parse-only declarations with byte ranges, and
`mylang --features` prints the whole embedded manifest. The
[compiler-derived reference design record](experiments/agent-reference.md) describes
the removed Python generator and is historical, not current tooling.
