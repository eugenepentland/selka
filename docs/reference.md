# The compiler-derived reference

> **Status: shipped.** `src/reference.zig` (facts), `src/reference_command.zig`
> (flags, output, exit status) and the `reference` route in `src/main.zig`'s
> dispatch are all in the tree, exercised by `src/reference_test.zig` and by the
> registered `zig build test-agent-usefulness` step. `selka reference --query
> TERM` answers from an installed binary today; the other compiler-derived
> surfaces remain `selka --features`, `selka list-declarations`,
> `selka list-interfaces` and `selka schema-project`.

The reference answers questions about *the executable that runs it*. Nothing on this
page is a copy of a list the compiler keeps somewhere else: feature status, boundaries,
exclusions, standard-library signatures, builtin spellings and collection-method
arities are read at run time from data embedded in the binary — `src/features.json`,
the modules behind `src/standard_library.zig` (their source text too: the call forms
and descriptions below are read from it), the checker's own builtin tables, and the
versioned `module interfaces v1` listing it publishes. The curated
prose that no table can derive lives in `src/reference_text.zig`, is versioned with
the executable, and every guest example it carries is a fenced `selka` block on this
page, so `selka doctest .` executes it against the same binary that reports it.

## Looking up a function

Ask for a name and get the call a program writes, a one-line description and the guide to read, in
at most eight lines. The answer is read from the embedded standard library itself, so it needs no
copy of the source and cannot disagree with it.

```bash
selka reference --query strings.split
selka reference --query len
selka reference --query strings
selka reference --query strings.isdigit
```

```text
reference-v1 query="strings.split" match=exact facts=1
language: 0.1.0 primary_backend=llvm
standard library: checked (38 modules, 647 exported declarations)

strings.split(text: str, separator: str) -> str[]
  Split on `separator`, keeping every piece including empty ones.
  guide: selka docs text
```

- A **module-qualified name** (`strings.split`, `lists.index_of`, `process.SIGINT`, `strings.Error`) answers with
  the declaration as its source spells it: parameters with their types and defaults, the result, a `fails` or
  `from` clause, and the first sentence of the comment above it. A type answers with its keyword
  (`enum strings.Error`); a constant with its type and value (`process.SIGINT: int = 2`).
- A **bare prelude name** (`len`, `sorted`, `parse_int`, `append`) answers the same way. The compiler keeps the
  prelude's names but no signatures, so these rows are curated in `src/reference_text.zig`, and a test holds each
  name against `prelude_names.zig` and each guide against `selka docs`.
- A **module's name** (`strings`) lists its exported declarations, one call per line, in source order, under the
  module's guide: `text` for `strings`, `bytes` for `bytes`, `sets` for `sets`, `io` for `filesystem`, and
  `stdlib` for every other module. A name that is both a prelude function and a module (`sort`) answers with both.
- A **qualified name no module declares** (`strings.isdigit`, `strings.splitlines`) answers with the nearest
  declared names of that module, at most three (`strings.is_digit`; `strings.lines`, `strings.split`), and the
  command that lists the whole module.

In these answers the text leaves out the substring search, so the header counts what the answer shows. The
JSON envelope carries the same answers as an `answers` array (below) and every fact it had: a bare prelude name or a
module name still lists its substring matches, and `strings.split` is searched as the listing's `strings::split`.
Any other term is the substring search it always was.

## What it answers

| Category | Reported from | A query such as |
| --- | --- | --- |
| `syntax` | `src/reference_text.zig` | `stream-output` |
| `feature` | `src/features.json` `implemented` | `standard-sort` |
| `limit` | `src/features.json` `limits` | `floating_point` |
| `exclusion` | `src/features.json` `unsupported`, `native_exclusions`, `removed` | `capturing-closures`, `legacy-syntax` |
| `declaration` | the embedded standard modules, listed by the compiler, with the call form and description read from their source | `sort_ints`, `strings.split` |
| `builtin` | `io_builtins.zig`, `prelude_builtins.zig`, `prelude.zig`, `float_intrinsics.zig` | `print`, `sorted` |
| `method` | `buffer_operations.zig`; each is listed as an operation whose method spelling is refused (`E_METHOD_REMOVED`) | `split`, `pop` |
| `diagnostic` | `diagnostic_codes.zig` | `E_TRY_POSITION`, `shadowing` |

## Fact status

Reference declarations report how their facts were obtained. An unavailable
fact stays distinct from an empty checked declaration set.

| Field | Meaning |
| --- | --- |
| `library.status` | `checked` when embedded module bodies were checked, `declaration-only` when only declarations were parsed, or `unavailable` when no library facts are available. |
| `declarations` | Matched declaration records, or `null` when analysis is unavailable. |
| `analysis` (per declaration) | `checked` for a checked body, `template` for an uninstantiated generic, `declaration-only` when bodies were not checked, or `declared` for a noncallable declaration. |
| `mutates` | The parameter names in the declared `mutates(...)` clause, or `null` when no clause was written. |

Declared signatures and mutation contracts remain interface facts. Retired
source effect clauses and inferred effect sets are not published as `effects`
or `ceiling` fields.

## Query, format and exit status

Matching is a **case-insensitive substring** of each fact's slug, name, summary,
signature, families, source table or diagnostic code, and the answer lists the matches in a fixed
category order, each category sorted by key, so two runs of the same query are
byte-identical. The envelope's `match` field is `exact` when the term equals a fact's
whole key, `substring` when it only appears inside one, and `none` when nothing
matched — an unmatched query is a normal answer that says so, not an error. A malformed
request (a missing or empty `--query`, an unknown flag, a `--format` other than `text`
or `json`) writes the usage line to stderr and exits 2.

The intended invocations are:

```bash
selka reference --query sort
selka reference --query standard-sort --format=json
selka reference --query capturing-closures
selka reference --query E_TRY_POSITION
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
  "library": { "status": "checked", "reason": null, "modules": 38, "exports": 647 },
  "declarations": [
    {
      "name": "sort::sort_ints",
      "kind": "function",
      "signature": "func(values:i64[])->i64[]",
      "analysis": "checked",
      "mutates": null,
      "call": "sort.sort_ints(values: int[]) -> int[]",
      "summary": "A new ascending list of integers; the input list is not modified."
    }
  ],
  "answers": []
}
```

`answers` is empty for an ordinary term. For a name that earns a short answer it holds one record per answer,
each with a `kind`: `declaration` (`name`, `call`, `summary`, `guide`), `prelude` (the same four), `module`
(`name`, `guide` and `declarations`, each `{ name, call, summary }` in source order) or `nearest` (`name`, `module`,
`guide` and `candidates`, each `{ name, call, summary }`). A `summary` is `null` when the source has no comment
above the declaration. A `method` record carries `method_form: "refused"`.

The other arrays (`syntax`, `features`, `limits`, `exclusions`, `builtins`, `methods`,
`diagnostics`) carry the matched records of their categories and are empty when the term
matched none of them. A `diagnostics` record is `{ "code", "meaning", "guide" }`: the code
as printed in `error[CODE]`, what it means in general, and the `selka docs` topic to read.
Every `E_`, `W_`, `L_` and `R_` code the compiler can print has one, and a unit test fails
when a code is added without its row. The record of an ownership code also carries `rules`,
the numbered rules it can enforce, and `rule_families`, the same rules grouped under the
heading of the [ownership reference](ownership-rules.md#how-the-reference-is-organised) that
files them (`Escape`, `Exclusion`, `Gone`, `Current limits`, `Applications` or `Appendix`);
the text output prints the groups, as in `ownership rules: Escape (B2, B9, W2)` for
`E_OWN_MARKER`.

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

These are the boundaries where selka differs from Python most often, and each block
below is executed by the documentation gate. The same text is what
`selka reference --query <id>` reports, with `python` naming the difference.

Locals have lexical block scope. Declare a binding with `const` or `mut`; assignment
updates a writable binding. Declare shared results before a branch or loop when code
after that block needs them. Active names cannot be shadowed.

```selka
# doc: expect 6
func main() -> int:
    mut total = 0
    for value in [1, 2, 3]:
        total += value
    return total
```

Use `range()` as the source of an explicit loop when collecting values.

```selka
# doc: expect 9
func main() -> int:
    mut squares: int[] = []
    for x in range(0, 4):
        append(mut squares, x * x)
    return squares[3]
```

There are no tuples: a `record` declares named fields and a top-level function takes
its state as a parameter.

```selka
# doc: expect 21
record Pair:
    left: int
    right: int

func swap(pair: Pair) -> Pair:
    return Pair(left=pair.right, right=pair.left)

func main() -> int:
    mut swapped = swap(Pair(left=1, right=2))
    return swapped.left * 10 + swapped.right
```

Printing goes through a `Stream` parameter rather than an ambient stdout.

```selka
# doc: expect hello
func main(out: Stream) -> int:
    print(out, "hello")
    return 0
```

File access needs a capability parameter, and using it shows up in the effect set.

```selka
# doc: check
import strings

func read_length(fs: Filesystem) -> int:
    match fs.read_text("answer.txt"):
        case Ok(text):
            return strings.char_count(text)
        case Err(_):
            return 0 - 1
```

Integers have a fixed width, and character/code-point helpers are not spelled the way
Python spells them.

```selka
# doc: expect 7
func main() -> int:
    mut big = 9223372036854775807
    return big % 10
```

The bare builtin spellings an agent reaches for first.

```selka
# doc: expect 9
func main() -> int:
    mut values = [3, 1, 2]
    mut ordered = sorted(values)
    return sum(ordered) + len(ordered)
```

## Related surfaces

`selka list-interfaces` prints the same declarations as text for a project of your
own, `selka schema-project --schema-report` prints the checked schema with wire
shapes, `selka list-declarations` prints parse-only declarations with byte ranges, and
`selka --features` prints the whole embedded manifest. The
[compiler-derived reference design record](experiments/agent-reference.md) describes
the removed Python generator and is historical, not current tooling.
