# Ownership rules

These are Selka's ownership rules. Each ownership refusal names the rule it enforces
in terminal output and in the `rule` field of `diagnostic-v1` JSON. Use
`selka reference --query CODE` to see the rules associated with a diagnostic code.
The [memory guide](managed-memory.md) introduces the model; this reference states
its rules and executable examples.

## The model

Every use of a managed value (text, bytes, a collection, or a record that holds one) is
one of four verbs:

| Verb | In an expression | In a signature |
| --- | --- | --- |
| lend | the bare name: `size(values)`, `const view = values` | a plain parameter; a result under `from values` |
| lend for writing | `mut name`: `append(mut values, 3)` | a `mut` parameter |
| give | `own name`: `keep(own values)`, `mut next = own values` | an `own` parameter; a result without `from` |
| duplicate | `copy(name)`: `mut next = copy(values)` | none: the copy is a fresh value |

Three rules say what those verbs may do:

1. **Escape.** A lent value cannot be stored or given anywhere that outlives its lender.
2. **Exclusion.** A lender cannot change or be given away while something it lent is in
   use, and a loan for writing is the only loan.
3. **Gone.** After `own`, the name cannot be used until it is assigned again.

A value built from lent parts is itself lent: a record whose managed fields all read
places without `own` borrows those places (B9), a slice borrows its source (V1) and a
result under `from` borrows the arguments it names (R3). Resources, task groups and
pending Results are the same rules applied to a value that cannot be duplicated, a scope
that borrows, and a value that must be consumed ([Applications](#applications)).

A named managed value transfers only with `own`, except a bare return or fail. A `const`
initialized from a place borrows read-only unless its initializer explicitly moves
that value. A function returning a borrow declares its sources with `from`, for
example `-> Json from doc`. Callers use that signature, not the function body.
Arguments evaluate left to right in source order, including named arguments; see Z1.

All four verbs in one program. `grow` borrows its argument for writing, `size` only
reads it, `copy` leaves two independent values, and `own` hands the original to `keep`:

```selka
# doc: expect 9
func size(values: int[]) -> int:
    return len(values)

func grow(mut values: int[]):
    append(mut values, 3)

func keep(own values: int[]) -> int[]:
    return values

func main() -> int:
    mut values = [1, 2]
    grow(mut values)
    const twin = copy(values)
    const count = size(values)
    const kept = keep(own values)
    return count + len(twin) + len(kept)
```

Each rule has a refusal that a first program meets. A plain parameter is lent for the
call, so it cannot be stored in an owner that outlives the call (Escape):

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
func retain(values: int[]) -> int:
    mut retained = own values
    return len(retained)
func main() -> int:
    return retain([1, 2])
```

A lender cannot change while something it lent is still used later (Exclusion):

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
func main() -> int:
    mut values = [1]
    const alias = values
    append(mut values, 2)
    return len(alias)
```

A name that was given away is gone (Gone):

```selka
# doc: expect-error E_SINGLE_OWNER_MOVED
func main() -> int:
    const values = [1]
    const kept = own values
    return len(kept) + len(values)
```

An Escape refusal is repaired with `copy(name)`, which keeps both values, or with
`own name`, which gives the value away when its owner can give it. A plain parameter
cannot give its argument away, so its only repair is the copy.

## Keeping pieces of a buffer

A reader or a parser handles values that are all pieces of one buffer: the name, the size and the link of a header are
octets of the block it was read from. The question each time is how long the piece must live, compared with the buffer.
The answer picks the form, and `copy` is the last one. This section follows one example from start to end: a fixed-size
header in a `bytes` block, with the name in octets 0 to 7 (padded with NUL), the size in 8 to 11 (decimal digits), the kind in 12
and the link in 13 to 20. It is the shape of a tar header.

| I want to | Write | The refusal that sends you here |
| --- | --- | --- |
| read a field, use it and be done | a slice in a local (`const name = block[0:8]`) or as an argument; several together: a local record of borrows (1) | `E_SLICE_ESCAPES` when a slice is stored in a record or a list |
| hand one field to my caller | `-> bytes from block`, the result is a view of the argument (2) | `E_BORROW_UNDECLARED`; the warning `W_COPY_MOVE` |
| keep where a field is, for as long as the buffer lives | a `spans.Span`, read back with the buffer in hand (3) | `E_SLICE_ESCAPES` |
| keep the text for good, and I am finished with it | `own`: an `own` parameter, `Header(name=own name)`, `take(mut header.name)` (4) | `E_OWN_MARKER`, `E_SINGLE_OWNER_BORROW` |
| keep the same name from many places | `symbols.intern`, then keep the `Symbol` (4) | `L_COPY_IN_LOOP` |
| keep both, independent of each other | `copy(x)` (5) | the four above offer it as their repair; `W_NEEDLESS_COPY` says when it was not needed |

**1. Use it and let it go.** A slice is a view of its buffer, and a view needs nothing to be read: bind it to a local, compare
it, loop over it and pass it to any plain parameter. No `copy`, no marker. The buffer cannot be changed while a
view of it is read later (`E_SLICE_ESCAPES`, rule V3), and that is the whole cost.

```selka
# doc: expect 5 42 5 True
const HEADER: bytes = b"a.txt\x00\x00\x000042lb.txt\x00\x00\x00"

# The length of a field without its NUL padding.
func trimmed(field: bytes) -> int:
    mut end = len(field)
    while end > 0 and field[end - 1] == 0:
        end -= 1
    return end

func number(digits: bytes) -> int:
    mut value = 0
    for digit in digits:
        value = value * 10 + digit - 48
    return value

func main(out: Stream) -> int:
    const block = HEADER
    const name = block[0:8]
    const link = block[13:21]
    print(out, trimmed(name), number(block[8:12]), trimmed(link), name == b"a.txt\x00\x00\x00")
    return 0
```

Gathering the slices into one record does not work: a record's field takes a whole value, a place or a plain parameter, never a
view, and the slice is refused where it is stored.

```selka
# doc: expect-error E_SLICE_ESCAPES
record Pieces:
    name: bytes
    link: bytes

func lengths(block: bytes) -> int:
    const pieces = Pieces(name=block[0:8], link=block[13:21])
    return len(pieces.name) + len(pieces.link)

func main() -> int:
    return lengths(b"a.txt\x00\x00\x000042lb.txt\x00\x00\x00")
```

What several functions can share is where the pieces are: a *local record of borrows* ([B9](#b9--const-place-bindings-borrow)) that holds
the block itself and two integers. It copies nothing, it is read through a helper that is declared `from` it, and a list of
such records is a *collection of borrows* ([below](#collections-of-borrows)).

```selka
# doc: expect 8 16 False
const HEADER: bytes = b"a.txt\x00\x00\x000042lb.txt\x00\x00\x00"

# Where a field is: the block it is in, and where in it.
record Piece:
    block: bytes
    start: int
    length: int

func view(piece: Piece) -> bytes from piece:
    return piece.block[piece.start:piece.start + piece.length]

func total(pieces: Piece[]) -> int:
    mut sum = 0
    for piece in pieces:
        sum += len(view(piece))
    return sum

func main(out: Stream) -> int:
    const block = HEADER
    const name = Piece(block=block, start=0, length=8)
    mut all: Piece[] = []
    append(mut all, name)
    append(mut all, Piece(block=block, start=13, length=8))
    const first: Piece? = Some(name)
    print(out, len(view(name)), total(all), first is None)
    return 0
```

Such a record may be passed as a plain argument, put in a local list or a local option and read through `view`, as above. It
may not leave the function that built it: not returned, not returned inside `Some(...)` or a list, not stored in a field of a
`mut` parameter, not given with `own`, and its block cannot be changed or given away while it is read later. Each of these is
`E_OWN_MARKER` at the field `block=block`, with a note on the line that made the record need its own value; `copy(block)` there
repairs it by making the record an owner, which is a copy of the whole block. A record built over a local, or over a field of one,
copies nothing. A record built over a plain `bytes` parameter copies the block once per call, because `bytes` carries no owner
to point at (`--stats` counts the site as a frame block); over a plain `str` or list parameter that was passed whole it copies
nothing.

```selka
# doc: expect-error E_OWN_MARKER
record Piece:
    block: bytes
    start: int
    length: int

func first_field() -> Piece:
    const block = b"a.txt\x00\x00\x000042lb.txt\x00\x00\x00"
    const piece = Piece(block=block, start=0, length=8)
    return piece

func main() -> int:
    return first_field().length
```

**2. Return one piece.** A function that answers a slice of its argument says so with `from`: `-> bytes from block`, or
`-> str from path` for text. The result is a view of the argument, nothing is copied, and each caller decides how long it
needs it. The caller may read it, compare it, pass it to a plain parameter, return it again under its own `from`, and
keep several at once: the block is only read. It may not store it in a record or a list (`E_SLICE_ESCAPES`), return it
without a `from` of its own (`E_BORROW_UNDECLARED`), give it with `own` (`E_SINGLE_OWNER_BORROW`) or change the block while it
reads the view later (`E_SINGLE_OWNER_OVERLAP`); all of these name `copy(...)` as the repair, and the section below says when
that is the right one. A function that copies a slice of its parameter on every return gets the warning `W_COPY_MOVE`, which names the same
declaration.

```selka
# doc: expect b'a.txt' b'b.txt' 10 True
const HEADER: bytes = b"a.txt\x00\x00\x000042lb.txt\x00\x00\x00"

# A field of the block without its NUL padding: a view of the block itself.
func field(block: bytes, start: int, width: int) -> bytes from block:
    mut end = start + width
    while end > start and block[end - 1] == 0:
        end -= 1
    return block[start:end]

func name_of(block: bytes) -> bytes from block:
    return field(block, 0, 8)

func link_of(block: bytes) -> bytes from block:
    return field(block, 13, 8)

func same_name(block: bytes, other: bytes) -> bool:
    const name = name_of(block)
    return name == name_of(other)

func main(out: Stream) -> int:
    const block = HEADER
    const name = name_of(block)
    const link = link_of(block)
    print(out, name, link, len(name) + len(link), same_name(block, HEADER))
    return 0
```

A function declared `from` returns views of its arguments, or a literal such as `""` for the case with nothing to show, and
never a value it computed: `return text + "!"` beside `return text[0:3]` is `E_BORROW_MIXED`, and the computed branch is the one
that needs `copy` or a function of its own.

```selka
# doc: expect-error E_BORROW_MIXED
func shown(text: str, plain: bool) -> str from text:
    if plain:
        return text[0:3]
    return text + "!"

func main() -> int:
    return len(shown("abcdef", True))
```

**3. Keep it longer than the buffer's borrow, but not longer than the buffer.** A record that outlives the function cannot hold a view, and it need not:
keep where the piece is, not what it is. A [`spans.Span`](standard-library.md#spans) is a file number, a start and a length, three
integers, so a record of spans is stored, returned and put in lists with no copy of the text. The text lives in a `spans.Sources`
table, which owns it for as long as the program keeps the table, and a span is read back with the table in hand:
`spans.text(sources, span)` is `-> bytes from sources`, a view that the caller uses and drops. Write the helper that turns a
field into a view once, `from sources`, as `name_of` below does.

```selka
# doc: expect 2 49
# doc: expect b'c.txt\x00\x00\x00' True
import spans

# Where a header's fields are, not what they are: integers, so the record can be stored and returned.
record Header:
    name: spans.Span
    link: spans.Span
    size: int
    kind: int

func number(digits: bytes) -> int:
    mut value = 0
    for digit in digits:
        value = value * 10 + digit - 48
    return value

# The header that starts at `at` in a file of the table.
func parse(sources: spans.Sources, file: int, at: int) -> Header:
    const size = number(spans.text(sources, spans.of(file, at + 8, 4)))
    const kind = spans.text(sources, spans.of(file, at + 12, 1))[0]
    return Header(name=spans.of(file, at, 8), link=spans.of(file, at + 13, 8), size=size, kind=kind)

# A field, read back with the table in hand: a view of the table's own text.
func name_of(sources: spans.Sources, header: Header) -> bytes from sources:
    return spans.text(sources, header.name)

func read_all(sources: spans.Sources, file: int) -> Header[]:
    mut headers: Header[] = []
    mut at = 0
    while at + 21 <= len(spans.file_text(sources, file)):
        append(mut headers, parse(sources, file, at))
        at += 21
    return headers

func main(out: Stream) -> int:
    mut sources = spans.create()
    mut data = b"a.txt\x00\x00\x000042lb.txt\x00\x00\x00" + b"c.txt\x00\x00\x000007ld.txt\x00\x00\x00"
    const file = spans.add(mut sources, "archive", own data)
    const headers = read_all(sources, file)
    print(out, len(headers), headers[0].size + headers[1].size)
    print(out, name_of(sources, headers[1]), spans.equals(sources, headers[0].name, b"a.txt\x00\x00\x00"))
    return 0
```

The table is only ever added to, so a span never goes stale, and a span outside the table traps instead of reading other text.
Two spans compare by place, not by text: `==` asks whether they are the same place, and `spans.same(sources, a, b)` asks whether
the texts are equal.

**4. Keep it for good.** When the text must outlive the buffer and the code that has it is finished with it, give it away: a
move copies nothing. A `str` that `strings.decode` returns is a new value the function owns, and `Header(name=own name)`
stores it. A caller that is done with its text passes it to an `own` parameter with `own`. A field of a record that nothing reads
again leaves it with `take(mut header.name)`, and a list nobody reads again gives up its elements one by one with
`for part in own parts:` and `append(mut kept, own part)`. The refusals that point here are `E_OWN_MARKER` (a bare `name` only lends the local, and
the field needs `own name`) and `E_SINGLE_OWNER_BORROW` (the value is lent by a plain parameter, so the function cannot give it
away: declare the parameter `own` if its callers are finished with the value, and `copy` if they are not).

```selka
# doc: expect Z.TXT b.txt
# doc: expect True 5
import strings

record Header:
    name: str
    link: str
    size: int

# The text is decoded into a new `str` that the function owns; `own` moves it into the record: no copy.
func parse(block: bytes) -> Header fails str:
    const name = try strings.decode(block[0:5])
    const link = try strings.decode(block[13:18])
    return Header(name=own name, link=own link, size=42)

# A caller that is finished with its text gives it away.
func rename(mut header: Header, own name: str):
    header.name = own name

# A field nothing reads again moves out of the record, leaving an empty text behind.
func name_length(mut header: Header) -> int:
    const name = take(mut header.name)
    return len(name)

func main(out: Stream) -> int:
    mut header = parse(b"a.txt\x00\x00\x000042lb.txt\x00\x00\x00") else Err(why):
        print(out, why)
        return 1
    const fresh = strings.upper("z.txt")
    rename(mut header, own fresh)
    print(out, header.name, header.link)
    const length = name_length(mut header)
    print(out, header.name == "", length)
    return 0
```

A name that repeats, in many headers or many files, is better kept once. [`symbols.intern`](standard-library.md#symbols)
answers a `Symbol`, one integer, and copies the text only the first time it sees it: interning a name the table already holds
allocates nothing. The `Symbol` is stored, compared with `==` and used as a dictionary key; `symbols.name(table, symbol)` reads
the text back as a view of the table. What it costs is a hash of the name at each `intern` and a table that grows with the
distinct names and never shrinks; what it gives is that equal names are equal numbers. A million uses of one 34-octet name held
about 12 MB at its peak where a million copies held about 104 MB (a `--release` run, 17 November 2026).

```selka
# doc: expect True False 2 b'b.txt'
import symbols

func main(out: Stream) -> int:
    mut table = symbols.create()
    const first = symbols.intern(mut table, b"a.txt")
    const again = symbols.intern(mut table, b"a.txt")
    const other = symbols.intern(mut table, b"b.txt")
    print(out, first == again, first == other, symbols.count(table), symbols.name(table, other))
    return 0
```

**5. Copy last.** When both must live on, independent of each other (the entry outlives the block, and the block is read again),
`copy(x)` is the form, and the copy is one allocation of the piece, not of the block. Every refusal above offers it as
the repair because it always works; reach for it after the forms above have not fitted.

```selka
# doc: expect b'abcdefgh'
record Entry:
    name: bytes

func name_of(block: bytes) -> bytes from block:
    return block[0:8]

# The entry outlives the block, and the caller reads the block again: both live on.
func keep(block: bytes) -> Entry:
    return Entry(name=copy(name_of(block)))

func main(out: Stream) -> int:
    const entry = keep(b"abcdefghijkl")
    print(out, entry.name)
    return 0
```

A copy that carries nothing is the warning `W_NEEDLESS_COPY`, which names the edit that deletes it: the use only reads the
value (`length(copy(name))`), or the copy is the value's last use (`Entry(name=copy(name))` of a local nothing reads
again). `selka fix FILE --warnings` applies it, and `selka lint` reports the same as `L_NEEDLESS_COPY`.

```text
# doc: not-selka
warning[W_NEEDLESS_COPY]: `length` only reads `name`, so pass `name` itself rather than a copy
warning[W_NEEDLESS_COPY]: `name` is never used again, so pass `own name` and the copy becomes a move
```

## How the reference is organised

The 54 numbered rules below (T1 to Z3) keep the ids that diagnostics, `selka reference`
and other pages name. Each is filed under exactly one of these headings, and a test holds
that (`src/ownership_reference_test.zig`). Within a heading the rules keep the order they
had when the reference was one list, by the letters of their ids: T, B, R, M, W, V, X, P,
K, L, C, Z.

| Heading | What it holds |
| --- | --- |
| [Rule 1: Escape](#rule-1-escape) | what stops a lent value from being stored, given or returned past its lender; most refusals are here |
| [Rule 2: Exclusion](#rule-2-exclusion) | what may not change while something is lent, and what writing needs |
| [Rule 3: Gone](#rule-3-gone) | what happens to a name after `own` |
| [Current limits](#current-limits) | refusals that come from the checker or the representation, not from the model, each with what would remove it |
| [Applications](#applications) | the rules applied to resources, task groups and pending Results, and the types that cannot be duplicated |
| [Appendix](#appendix-accepted-behaviour-and-retired-restrictions) | entries that describe accepted behaviour or a retired restriction; they keep their ids |

## Checking layers

Core decides move, loan, place-overlap and lifetime predicates for every checked
function instance. The frontend decides type and source-mode predicates. Five rules
have separate predicates in both layers; no predicate is checked twice.

Frontend rules, including B1 writability, check every generic body even when it is
never called. Core move, borrow and lifetime rules check each concrete instance;
an uncalled template has no Core ownership proof.

| Layer | Rules or predicates |
| --- | --- |
| Frontend | T1–T4, B1, M2, M3, W3, V6, K2–K3, L1, C2 |
| Core | B2–B9, R1–R6, M1, M5, M6, W1, W4, V1–V5, V7, X1, P1–P5, C1, C3, Z1–Z3 |
| Frontend and Core | M4: temporary target shape / writable owner; R7: iteration binding writes / collection loans; W2: parameter-mode spelling / ownership transfer; X2: match place shape / owner mutability and overlap; K1: task argument kinds and lender scope / group-long loan conflicts |

Rules with `Codes: none` describe accepted behavior and have no independent refusal.
Every rule below has a runnable accepted example. Refused examples assert their
code, and compiler tests additionally assert their actual rule ID. The explicit
`# doc: build` modifier marks a refusal discovered during native lowering after a
successful check.

## Proof coverage

Since 26 October 2026 a Debug compiler checks the final Core IR of every function with the
ownership validator (checks J1 to J8, `src/core/validate_ownership.zig`), and a Lean proof
(`proofs/ownership`, `Own.check_sound`) shows that a function that passes the same
checks never faults: no read or destruction of a dead allocation, no second
destruction, no consumption of a borrowed value, no stack value escaping, and no leak
at a normal return. `Own.runs_sound` and `Own.main_no_leak` extend that to a whole
program. The proof covers the run-time property a rule protects. It does not prove
that the source checker enforces the rule's predicate. The optimizer's fact checks
(F1 to F7, `docs/tooling/fact-certificates.md`) concern value ranges and the
overflow, division, shift and bounds checks a release build drops, so none of the 54 rules
is proved by them. The design is
ownership certificates (`docs/design/ownership-certificates.md`) (the classification is its
section 7); the guide is `docs/tooling/ownership-certificates.md`;
the totals, the assumptions and the costs are in the
report (`docs/audits/ownership-certificates-report-2026-10-26.md`).

The kind column says what the proof can say about a rule:

- **safety** (36 rules): a run-time property that J1 to J8 check in the final IR and the
  proof covers. The three task-group rules K1 to K3 were stage 2 in the design and are
  covered since C6.
- **clarity** (12 rules): a source discipline the proof does not need. Where a clarity
  rule is the spelling of a move or a transfer, the move itself is proved and the
  marker is not.
- **type** (6 rules): a type-level rule the model takes as given.

| Rule | Kind | Proved by | Lean lemmas (`Own.`) | Rests on |
| --- | --- | --- | --- | --- |
| T1 | type | none: the model takes the type split as given | - | A1 |
| T2 | type | none: owned and borrowed states are the model's | - | A1 |
| T3 | type | none: model assumption (the heap is a forest of owner trees, `wf` and `apart` in the contract) | - | A2 |
| T4 | type | none: the model takes containment as given | - | A1 |
| B1 | clarity | none | - | - |
| B2 | clarity | the move itself: J2 | consumeLive_ok, consumeOnce_ok | A3, A4, A10 |
| B3 | safety | J2, J3 | consumeLive_ok, consumeOnce_ok, readsAlive_ok | A3, A4, A10 |
| B4 | safety | J2 | consumeLive_ok, consumeOnce_ok, post_core | A3, A4, A10 |
| B5 | safety | J2 | edge_inv, post_core | A3, A4, A10 |
| B6 | safety | J2 | edge_inv, post_core | A3, A4, A10 |
| B7 | safety | J5, J8 | notBorrowed_ok, transferOk_ok, closeOk_ok, noStale_ok | A8 |
| B8 | safety | J2 (`record_take`) | consumeLive_ok, post_core | A3, A4, A10 |
| B9 | safety | J4 | readsAlive_ok, loansLive_ok | A12; gaps A13-A15 |
| R1 | safety | J1, J5 | inst_step, notBorrowed_ok | A3 |
| R2 | safety | J4 | readsAlive_ok, loansLive_ok | A12; gaps A13-A15 |
| R3 | safety | J1, J4 | inst_step, readsAlive_ok, loansLive_ok | A3, A12; gaps A13-A15 |
| R4 | safety | J5 | notBorrowed_ok, post_core | - |
| R5 | safety | J1 | inst_step, edge_inv | A3 |
| R6 | safety | J1 (phi) | edge_inv | A3 |
| R7 | safety | J4 | readsAlive_ok, loansLive_ok | A12; gaps A13-A15 |
| M1 | safety | J1, J2 | inst_step, consumeLive_ok, post_core | A3, A4, A10, A16 |
| M2 | clarity | none | - | - |
| M3 | clarity | none | - | - |
| M4 | clarity | none | - | - |
| M5 | safety | J6 | separate_ok | - |
| M6 | safety | J6 | separate_ok | - |
| W1 | safety | J2 | consumeLive_ok, consumeOnce_ok, post_core | A3, A4, A10 |
| W2 | clarity | the transfer: J2 | consumeLive_ok, consumeOnce_ok | A3, A4, A10 |
| W3 | type | none: the signature's states are the model's | - | A1 |
| W4 | safety | J5 | notBorrowed_ok | - |
| V1 | safety | J1, J4 | inst_step, readsAlive_ok | A3, A12; gaps A13-A15 |
| V2 | safety | J5 | notBorrowed_ok | - |
| V3 | safety | J4 | readsAlive_ok, loansLive_ok | A12; gaps A13-A15 |
| V4 | safety | J5 | notBorrowed_ok, post_core | - |
| V5 | safety | J1 (phi) | edge_inv | A3 |
| V6 | safety | J4, J5 | readsAlive_ok, notBorrowed_ok | A12; gaps A13-A15 |
| V7 | type | none: the class table gives each view operation's state | - | A1 |
| X1 | safety | J1, J4 | inst_step, readsAlive_ok | A3, A12; gaps A13-A15 |
| X2 | safety | J4, J6 | readsAlive_ok, separate_ok | A12; gaps A13-A15 |
| P1 | clarity | none | - | - |
| P2 | safety | J2, J4 | consumeLive_ok, post_core, readsAlive_ok | A3, A4, A10, A12 |
| P3 | safety | J5 | notBorrowed_ok, post_core | - |
| P4 | safety | J4 | readsAlive_ok, loansLive_ok | A12; gaps A13-A15 |
| P5 | safety | J4, J5 | readsAlive_ok, notBorrowed_ok | A12; gaps A13-A15 |
| K1 | safety | J4 (`loan-outlives-root`) | lentSafe_ok, root_consumed | A7.1, A7.2, A7.5, A7.7 |
| K2 | safety | J2 (`group-join`), J3 | consumeLive_ok, consumeOnce_ok, readsAlive_ok | A7.3-A7.6, A7.7 |
| K3 | safety | none of its own: `myl_core_owned_map*` is an ordinary call that joins | - | A7.8 |
| L1 | clarity | leaks: J2 | post_core | A3, A4, A10 |
| C1 | clarity | none (checked at run time by `--verify-written-copies`) | - | - |
| C2 | clarity | none | - | - |
| C3 | safety | J2 | consumeOnce_ok, post_core | A3, A4, A10 |
| Z1 | safety | J2 | consumeLive_ok, post_core | A3, A4, A10 |
| Z2 | clarity | none | - | - |
| Z3 | clarity | none | - | - |

The lemmas are in `proofs/ownership` and are all consequences of the one per-function
theorem `Own.check_sound`; each is the step that rules out one fault of the model
(`Fault` in `Semantics.lean`) from one check:

| Lemma | Check | What it says for a function that passes the checks |
| --- | --- | --- |
| `inst_step`, `edge_inv` | J1 | one instruction and one phi edge keep the invariant that relates the checker's state (live set, roots, loans, open takes) to the machine state |
| `consumeLive_ok`, `consumeOnce_ok` | J2 | every consumed tree is live and no tree is consumed twice by one instruction (`consumeDead`, `destroyTwice`) |
| `post_core`, `ret_some_facts` | J2, J5, J8 | at a `ret` nothing the call allocated or was given to own is left live, nothing is pending, and a borrowed result lies inside the trees its `from` set names |
| `abandon_inv` | J2 | an edge into a trap region that abandons owners keeps the invariant, so a leak is allowed on a path to a trap and on no other |
| `readsAlive_ok` | J3, J4 | every operand an instruction reads is live (`readDead`) |
| `loansLive_ok` | J4 | the cells an owned value points into are live where it is read (`dangling`) |
| `lentSafe_ok`, `root_consumed` | J4 | a cell lent to a live group is not destroyed before the group ends (`lentGone`) |
| `notBorrowed_ok` | J5 | no consumed operand is a borrowed value (`takeBorrowed`) |
| `separate_ok` | J6 | an instruction does not consume a tree another operand still reads into (`overlap`) |
| `noEscape_ok` | J7 | a stack value is consumed only by a filling push and is never returned (`escape`) |
| `transferOk_ok`, `closeOk_ok`, `noStale_ok` | J8 | a take reads a live owned slot that is not already taken, a closing update agrees with the open slots, and a container with an open take is consumed only by its closing update (`stranded`) |

J7 has no source rule: it checks the compiler's own stack promotion (the S1 pass).

Every safety row also rests on A1 (the operation-class table describes the emitter and the
runtime), A2 (`drop` frees exactly its operand's tree and allocation returns disjoint
storage), A5 (external functions meet their contracts), A6 (LLVM emission keeps the
instruction order for ownership effects) and A9 (the entry function's scalar parameters
receive immediates; inside the program J1 checks it at each call). Calls through function
values rest on A17 (a function value points to a function with the signature of its type).
The last column adds what the row's own checks need: A3 (`undef` of a managed type is the
null owner), A4 (immortals are never freed), A8 (a repeated pure comparison gives the same
answer; the guards of J8), A10 (a closing update through a null owner returns a null owner),
A11 (the `stack` state is exactly a stack list of this activation), A12 (the parents the
certificate lists cover everything an owned value points into), A16 (the storage of an
`emptied` call result is what the caller takes out at once) and A7.1 to A7.8 (the runtime
contracts of task groups). "Gaps A13-A15" marks the three loan assumptions the validator and
the Lean checker enforce but the theorem does not cover: A13 (a take marked `noloans`
carries no loans, and a view into itself does not survive an update), A14 (the slot-level
end of a loan) and A15 (a view written before the take that owns its storage). The list,
and what would close each assumption, is in
`proofs/ownership/AXIOMS.md`; the layer table above says
where the compiler decides a rule, and this table says what the proof covers in the final IR.

## Rule 1: Escape

A lent value cannot be stored or given anywhere that outlives its lender.

A plain parameter, a `const` alias of a place, a loop variable, a field or element read, a
slice and the result of a `from` call are all lent. Putting one into an owning local, a
record, a list or dictionary, an `own` argument or a return that its lender does not cover
would leave it pointing at storage that can be freed or changed first. Most refusals a
program meets are this rule. They are reported under four codes, and the rule that found
each is named in the diagnostic: `E_OWN_MARKER` (B2, B9, W2), `E_SINGLE_OWNER_BORROW` (B7,
B9, R1, R3, R4, R6, M1), `E_SLICE_ESCAPES` (V2, V4, V5, W4) and `E_BORROW_UNDECLARED` (R4).
Two more rules enforce it under codes of their own: V6 for dictionary views
(`E_VIEW_STORED`) and C1 for copies the source did not write (`E_LITERAL_ARM`,
`E_CORE_HIDDEN_COPY`). B8, filed under [Current limits](#current-limits), also refuses with
`E_SINGLE_OWNER_BORROW` a field taken out of a borrowed record, which is an Escape refusal
too.

Every Escape refusal says the same four things in the same order, on one line: what is lent,
as the source spells it; who lends it; where the value would outlive its lender, or what the
place it goes into needs; and the repairs. The repairs are the edits `selka fix` makes where
it has a fix: `own NAME` gives the value away, and only where its lender is an owner that can
give it; `copy(NAME)` keeps both; and at a return no `from` clause covers, the result is
declared `from` its source. A plain parameter, or a field of one, stored bare is told the form
without a copy first (declare the parameter `own` and write `own NAME` at the store) when a
recheck proves that form, and the copy second; `selka fix` still writes the copy, because it
touches no caller.

```text
retain.selka:2:20: error[E_SINGLE_OWNER_BORROW]: `own values` cannot give the plain parameter `values`, which only lends it, and the `mut` local `retained` needs its own value; write `copy(values)` to keep both
```

A written `own` that takes nothing is refused in the verbs' words instead:

```text
read.selka:5:17: error[E_OWN_MARKER]: `own values` gives `values`, but this argument is only read; remove `own`
```

### B2 — Moves

Layer: Core.

Codes: `E_OWN_MARKER`.

Write `own` whenever a named managed value moves into a binding, assignment,
constructor, container or owning argument. The source becomes unavailable. A bare
`return value` or `fail value` transfers without `own`; `return own value` and
`fail own value` are refused. A returned or failed constructor still marks its named
inputs. Returning or failing with a managed field requires `own record.field` and
consumes the record under B8. Scalars and fresh call, literal, operator or `copy(...)`
results need no marker. A generic move may specialize to a scalar copy.

In expressions, `own` is a marker only when separated from a following identifier
on the same logical line (an open group permits continuation).
Before any other token it is an ordinary name: `own - 1` subtracts from a binding
named `own`, and `own (value)` calls it. Write a grouped move as `(own value)`;
a fresh identifier-led call such as `own make()` is refused because it needs no
marker.

```selka
# doc: expect 42
func main() -> int:
    const source = [42]
    const destination = own source
    return destination[0]
```

```selka
# doc: expect-error E_OWN_MARKER
func keep(own values: int[]) -> int:
    return values[0]
func main() -> int:
    const source = [42]
    mut destination = source
    return keep(own destination)
```

A bare error name transfers just like a bare successful return:

```selka
# doc: expect 7
func answer() -> int fails str:
    const message = "error-" + str(7)
    fail message
func main() -> int:
    match answer():
        case Ok(value):
            return value
        case Err(message):
            return len(message)
```

```selka
# doc: expect-error E_OWN_MARKER
func answer() -> int fails str:
    const message = "error-" + str(7)
    fail own message
func main() -> int:
    return 0
```

### B7 — No moving out of a container

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

Reading a managed element or dictionary value borrows it; the read cannot initialize
owning storage. Read it in place, bind a borrowed `const`, request `copy(...)`, or use
an extraction operation such as `pop`, `exchange` or `take` that returns ownership. An
option local narrowed to `Some` by `if x is None: return` gives its payload with `own x`
(B9, after the narrowing paragraph).

An element of a new list is the exception: when the list is the result of a call that
lends nothing (its result is not declared `from` a parameter) or a list literal, nothing
else can name it, so `strings.split(text, sep)[1]` in a position that takes a value (a
binding, an assignment, a `return`, a store, an `own` argument, a constructor's field, a
list literal's element, `Some`) moves the element out and drops the rest of the list. The
index's bounds check and its trap are unchanged. A new dictionary's `TEMP[key]` moves its
value out the same way. A read in a borrowing position still borrows, and a list lent by
a call, a field of an element (`rows()[1].tags`) and a slice still need `copy(...)`.

```selka
# doc: expect 3
import strings
func main() -> int:
    const middle = strings.split("a,bbb,c", ",")[1]
    return len(middle)
```

```selka
# doc: expect 4
import lists
func main() -> int:
    mut values = ["kept"]
    const taken = lists.pop(mut values)
    return len(taken)
```

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
func main() -> int:
    const values = ["kept"]
    mut retained = values[0]
    retained = retained + "!"
    return len(retained)
```

### B9 — Const place bindings borrow

Layer: Core.

Codes: `E_OWN_MARKER`, `E_SINGLE_OWNER_BORROW`.

`const alias = place` borrows every managed place read-only, including a bare local or
an `own` parameter, until the alias's last use in its block. An owning store, owned
return or `mut`/`own` argument cannot take the alias. Use `const alias = own owner` to
transfer a bare owner, or `copy(place)` for independence. A certain repair changes the
initializer only when safe. Declared borrowed returns still follow R3 and R4.

A `mut` local whose every assignment, its initializer included, reads a place without
`own` borrows the same way, whether it is assigned once or more: `mut net = port.name`
then `if ...: net = port.net` needs no copy, and neither does `mut net = port.name` read
alone. A write through such a local stored once (`append(mut net, ...)`, `net.f = v`,
`net[i] = v`, a `mut` argument) is refused at the write, which names the binding and both
repairs at it, `mut net = own place` to give a bare owner and `mut net = copy(place)` to
keep both; `selka fix` writes the copy. A local assigned more than once and written keeps
its refusal at the store that needs the copy. Its loans are the union of every assignment's places, held to its last use, so
changing any of those owners while it is live is refused, across loop iterations too;
the local itself cannot be changed, moved or stored, may be returned only under `from`,
and cannot borrow an owner that a loop makes again in each iteration while the local
lives past it. Such a refusal names the store that needs `copy(...)`, with its repair.
Beside those places, an assignment may also be a result that borrows (a call with a `from`
contract, `atom_of(x).unwrap_or(b"")`), and, when every place it reads is the caller's
storage (a plain parameter, a loop variable over one, or a `const` alias of either), a text
or bytes literal: `mut suffix = raw` then `suffix = b"R"`, or `mut mpn = b""` then
`mpn = p.value` in a loop over a parameter.

A slice of such a place reads it the same way, for text, bytes and lists: `mut head = p[0:2]`, then
`if ...: head = port.name`, copies nothing, and neither does a local rebound to its own tail. A list slice is
a view of the elements. Writing through it, storing it or changing its owner while it is live keeps the
slice's refusal (V2) at the store, with `copy(...)` around the slice.

```selka
# doc: expect 3
func count_tail(p: str) -> int:
    mut rest = p[0:]
    mut steps = 0
    while len(rest) > 0:
        rest = rest[1:]
        steps = steps + 1
    return steps


func main() -> int:
    return count_tail("abc")
```

After `if x is None: return` (or `fail`, `break`, `continue`), a read of `x` is its payload
read in place, as `x.unwrap_or(d)` of an option local is: `const id = x.unwrap_or(b"")`
borrows `x`, so `x` cannot change while `id` is live. A loop variable names an element of
the place it iterates, so `for pn in ledger.pins: remember(mut ledger.names, pn.net)` passes
a disjoint field, and the loop variable is read again after the write. A `match` arm whose
payload owns no storage (a number, a flag, a record of those) is copied when bound, fielded
or not, so the arm may change the place it matched, or the list or record that holds it
(`case Some(sec): attach[i] = None`, `case num(v=n): t.keys[at] = Key.other`), and `n` keeps the
value it had. A payload that holds text, bytes, a list, a dictionary or a resource is not copied,
and `match mut` writes its place: both hold the place until the arm's last use of a binding.

Where the function owns `x` (a `const` or `mut` local, or an `own` parameter), `own x` after
such a test (or in the `else:` of `if x is None:`) moves the payload out and consumes `x`, as
`const p = own x else:` does, with no copy; a bare `return x` or `fail x` gives it the same
way. A later read of `x` is then a use after the move, a `mut` `x` may be assigned again, and a
move in a loop `x` was declared outside of is refused as any such move is. A bare `x` stored
where a value is kept is refused (B7) with `own x` offered first and `copy(x)` second, and
`selka fix` writes the `own` where nothing reads `x` after it and no loop runs it again. A
plain or `mut` parameter, a loop variable and a `match` binding only lend: `own x` of one is
refused (B2) naming the lender, and `selka fix` writes `copy(x)` in its place.

```selka
# doc: expect 2
func find(name: str) -> str[]?:
    if name == "a":
        return Some(["x", "y"])
    return None

func keep(own items: str[]) -> int:
    return len(items)

func main() -> int:
    const found = find("a")
    if found is None:
        return 0
    return keep(own found)
```

A record constructor whose managed fields all borrow is a borrowed value too, as a `from`
result is: `RailSpot(net=b.power, x=1)` copies nothing. At least one managed field must
borrow, and every managed field must be one of these.

**Sources** (each read bare, with no `own`):
- a place: a field, an element or a dictionary value of a named binding;
- a bare owner, an `own` or `mut` parameter, a loop variable or a binding of a record;
- a plain parameter (not `own`, not `mut`) of a record, dictionary or set type, which is
  the caller's storage;
- a plain text, bytes or list parameter. It arrives as a view, so the record holds a
  *frame block*: the caller's own text or list when the argument was a whole value, else
  one copy this call makes the first time it builds such a record and frees when it
  returns. Bytes carry no owner, so a bytes argument is always copied this way, and so is
  a slice. `--stats` counts these sites;
- `Some(place)` of a place above (a field, an element, a dictionary value) whose payload
  is not boxed, and `Some(p)` of a read-only record parameter (see *Borrowed parents*);
- the record a `from` function returns (`first_of(shelf)` under `-> Item from shelf`), whose
  owners are the call's sources: it goes where the field it returns would go;
- a nested borrowed record, a text or bytes literal, or `None`.

**Positions:**
- a read-only argument of a call;
- a `const` local, and `Some(...)` of one bound to a `const` local (below);
- a `mut` local whose every assignment borrows;
- a value returned under a `from` contract, `Some(...)` of one too. A record holding a
  frame block never leaves its call, even under `from`.

Its loans are its fields' owners, held to its last use.

**What stays refused**, with the repair named on the field that needs `own` or
`copy(...)`, as before records could borrow:
- storing the record in a list, a dictionary or an owned field that owns its elements
  (a local collection of borrows, below, may hold it), or into a `mut` parameter;
- moving it, changing it, or returning it without `from`;
- submitting it to a task;
- changing one of its owners while it is live;
- a slice, or a `const` that borrows a text, bytes or list parameter, which are views;
- a record that mixes a borrow with a fresh value, which is an owner.

```selka
# doc: expect 8
record Spot:
    net: bytes
    x: int


record Bank:
    power: bytes
    gnd: bytes


func spot_len(spot: Spot) -> int:
    return len(spot.net) + spot.x


func main() -> int:
    const bank = Bank(power=b"VCC", gnd=b"GND")
    const ground = Spot(net=bank.gnd, x=1)
    return spot_len(Spot(net=bank.power, x=1)) + spot_len(ground)
```

A dictionary parameter is the caller's storage, so a record may lend it and a `from`
contract may return that record:

```selka
# doc: expect 5
record Table:
    counts: dict[bytes, int]
    tag: bytes


record Inner:
    a: bytes
    b: int


func table_of(counts: dict[bytes, int], inner: Inner) -> Table from counts, inner:
    return Table(counts=counts, tag=inner.a)


func main() -> int:
    mut counts: dict[bytes, int] = {}
    counts[b"a"] = 1
    const inner = Inner(a=b"xyz", b=0)
    const t = table_of(counts, inner)
    return len(t.counts) + len(t.tag) + t.counts[b"a"]
```

`Some(place)` lends the place, here elements of a list:

```selka
# doc: expect 5
record Opt:
    ref: bytes?


func olen(o: Opt) -> int:
    match o.ref:
        case None:
            return 0
        case Some(r):
            return len(r)


func main() -> int:
    const names = [b"ab", b"cde"]
    return olen(Opt(ref=Some(names[0]))) + olen(Opt(ref=Some(names[1])))
```

An option is the same: `const s: T? = Some(source)` of a source above, with an unboxed
payload, is an option of a borrow. It copies nothing and holds the source's owner until its
last use, and it is refused where a borrowed record would be: a store into something that
leaves, an `own` argument, a return without `from`, a change of the owner while it is live.

```selka
# doc: expect 7
record Shelf:
    label: bytes
    tags: bytes[]


func length(value: bytes?) -> int:
    match value:
        case Some(found):
            return len(found)
        case None:
            return 0


func main() -> int:
    const shelf = Shelf(label=b"left", tags=[b"abc"])
    const label: bytes? = Some(shelf.label)
    const first: bytes? = Some(shelf.tags[0])
    return length(label) + length(first)
```

A plain text, bytes or list parameter is held as a frame block. The whole text below is
lent with no copy; the slice is copied once for the call, not once per record:

```selka
# doc: expect 42
record Line:
    text: str
    n: int


func line_len(l: Line) -> int:
    return len(l.text) + l.n


func total(text: str) -> int:
    mut sum = 0
    for i in range(3):
        sum += line_len(Line(text=text, n=i))
    return sum


func main() -> int:
    const words = "hello world"
    return total(words) + total(words[0:1])
```


```selka
# doc: expect 3
func main() -> int:
    mut values = [1]
    const alias = values
    const observed = alias[0]
    append(mut values, 2)
    return observed + len(values)
```

```selka
# doc: expect 5
record Port:
    name: str
    net: str


func net_of(port: Port) -> str from port:
    mut net = port.name
    if len(port.net) > 0:
        net = port.net
    return net


func main() -> int:
    return len(net_of(Port(name="vcc", net=""))) + len(net_of(Port(name="io", net="IO")))
```

```selka
# doc: expect-error E_OWN_MARKER
func keep(own values: int[]) -> int:
    return values[0]
func main() -> int:
    const owner = [42]
    const alias = owner
    mut retained = alias
    return keep(own retained)
```

#### Borrowed parents

A borrowed record may also hold `None` beside its borrows (a payload-less case owns
nothing, as a literal does) and `Some(p)` of a read-only record parameter: a plain
parameter, not `own` and not `mut`, read bare without `own`. A recursive walk then passes
its context down with no copy: `walk(Scope(block=sb.block, parent=Some(scope)))`. The
parameter is the caller's storage, which cannot change during the call, so the record
holds it in place. When the option's payload is boxed (a recursive field such as
`parent: Scope?`), the box is a slot of this call's frame, made once when the call
starts. A callee reads it like any box, a `copy(...)` of the record copies it into an
owned box, and nothing destroys it.

Such a record follows every rule above, and one more: a value that holds a frame box its
own call made cannot be returned, even under `from`, because the slot ends with the
call. That covers the record itself, a `const` of it, a field read from it and a `from`
call result that borrows it (R4 has the example). A box an ancestor's call made is the caller's storage, so a
function may return it `from` the parameter that holds it: `bridged(self)` below returns
a scope read out of `self.parent`. `Some(...)` of a record built in place, or of a local,
keeps its copy: its value differs at each evaluation, so one slot cannot hold it.

```selka
# doc: expect 3
record Block:
    name: bytes
    subs: Block[]


record Scope:
    block: Block
    parent: Scope? = None


func bridged(self: Scope) -> Scope? from self:
    match self.parent:
        case None:
            return None
        case Some(parent):
            return Some(parent)


func depth(scope: Scope) -> int:
    match bridged(scope):
        case None:
            return 0
        case Some(up):
            return 1 + depth(up)


func deepest(scope: Scope) -> int:
    mut best = depth(scope)
    for sub in scope.block.subs:
        const d = deepest(Scope(block=sub, parent=Some(scope)))
        if d > best:
            best = d
    return best


func main() -> int:
    const leaf = Block(name=b"c", subs=[])
    const mid = Block(name=b"b", subs=[own leaf])
    const top = Block(name=b"a", subs=[own mid])
    return deepest(Scope(block=top)) + 1
```

#### Collections of borrows

A local list or dictionary whose every element store is a borrow is a *collection of
borrows*: it owns its buffer (and a dictionary its keys) and lends its elements, so
nothing is copied, and it holds what its elements borrow until its last use. It is:
- a `mut` local made empty (`[]`, `{}`), each `append`, `xs[i] = v` or `d[k] = v`
  storing a borrowed record, a place, `Some(place)`, `Some` of a borrowed record, a bare
  plain text, bytes or list parameter, `None` or a text literal, at least one of them a
  borrow;
- a list literal of such values: a `const`, or an argument built for one call;
- a field of a borrowed record that lends it (`Names(names=xs)`).

A dictionary key written as a place is copied when its entry is new, as before. Its
elements are read in place: an element, a `for` loop, `len`, `in`, and a read-only
argument (a library helper such as `dicts.find` reads it too).

**What stays refused**, with the diagnostic, location and repair each refusal had
before, because the collection then owns its elements:
- changing a source while the collection lives, or a source a loop makes again in
  each iteration while the collection lives past it;
- moving the collection, storing it, or passing it `mut` (a library call that stores
  into it, `lists.insert`, `sets.add`); a `mut` out-parameter; a task;
- returning it, even under `from`: a list returned under `from` is a view of its
  sources, so a new collection of borrows keeps its copies;
- an element that mixes a borrow with a fresh value;
- a set, and an owned record that takes the collection with `own`.

**Which line made it own.** Each of these makes the whole collection an owner, so the
refusal lands on an earlier `append` of a borrow, not on the line that changed the
decision. That refusal keeps its code, position and repair, and carries a note at the
other line, for example "`hits` owns its elements because this line stores a new value
in it, so the earlier line needs `copy(...)` or `own`" on the later `append`. A record of
borrows (B9) gets the same note when a later line moves or stores it, and when a managed
field the constructor leaves out takes a default that is a new value, the note sits on
that field's declaration in the record. In `--diagnostics=json` the note has the role
`cause`. `selka dump-typed FILE.selka` shows what was decided for each local: `owns`,
`borrows from all`, `borrows elements from all` or `borrows fields from names`.

```selka
# doc: expect 12
record Spot:
    net: bytes
    x: int


record Board:
    nets: bytes[]
    spots: Spot[]


func total(spots: Spot[]) -> int:
    mut n = 0
    for s in spots:
        n += len(s.net) + s.x
    return n


func main() -> int:
    const board = Board(nets=[b"vcc"], spots=[Spot(net=b"gnd", x=2)])
    mut spots: Spot[] = []
    append(mut spots, Spot(net=board.nets[0], x=1))
    mut by_net: dict[bytes, bytes] = {}
    by_net[b"first"] = board.nets[0]
    return total(spots) + len(by_net[b"first"]) + len(board.spots) + total([Spot(net=board.nets[0], x=1)])
```

A bare plain text, bytes or list parameter is held as its *frame block*, as a borrowed
record holds one (B9's sources): the caller's own text or list when the argument was a
whole value, else one copy this call makes the first time it stores the parameter and
frees when it returns, however many times it stores it, in a loop too. Bytes carry no
owner, so a bytes argument is always copied this way, and so is a slice. `--stats` counts
these sites. The collection never leaves its call (above), so neither does the frame block.

```selka
# doc: expect 12
func total(names: str[]) -> int:
    mut n = 0
    for name in names:
        n += len(name)
    return n


func repeated(name: str, times: int) -> int:
    mut names: str[] = []
    for i in range(times):
        append(mut names, name)
    mut by_index: dict[int, str] = {}
    by_index[0] = name
    return total(names) + len(by_index[0])


func main() -> int:
    return repeated("abc", 3)
```

### R1 — Plain parameters borrow

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

A plain managed parameter borrows its argument read-only for the call. The callee may
inspect it, but cannot move it into owning storage. Use `copy` for an independent value,
`own` in the declaration to take ownership, or a declared `from` result to return a
borrow.

```selka
# doc: expect 4
func size(values: int[]) -> int:
    return len(values)
func main() -> int:
    const values = [1, 2]
    return size(values) + len(values)
```

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
func retain(values: int[]) -> int:
    mut retained = own values
    return len(retained)
func main() -> int:
    return retain([1, 2])
```

A plain text, bytes or list parameter arrives as a view. A record built from it holds a
frame block ([B9](#b9--const-place-bindings-borrow)), so it may be an argument, a
`const` or an element of a local collection of borrows, but storing it where it
outlives the call, as here in a returned list, needs `copy(...)` of the field:

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
record Spot:
    net: bytes
    x: int


func keep(net: bytes) -> Spot[]:
    mut spots: Spot[] = []
    append(mut spots, Spot(net=net, x=0))
    return spots


func main() -> int:
    return len(keep(b"VCC"))
```

### R3 — Borrowed call results

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

A call with a declared `from` result borrows every corresponding argument owner; callers
use the signature, not the callee's body. Read the result in place, bind it with
`const`, or return it under R4. Owning storage and `mut`/`own` arguments require an
explicit copy. There is no fixed owner-count limit. Text, bytes and list results also
obey the view rules.

```selka
# doc: expect 2
record Item:
    name: str
func borrowed(value: Item) -> Item from value:
    return value
func main() -> int:
    const owner = Item(name="ok")
    const result = borrowed(owner)
    return len(result.name)
```

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
record Item:
    name: str
func borrowed(value: Item) -> Item from value:
    return value
func main() -> int:
    const owner = Item(name="ok")
    mut retained = borrowed(owner)
    retained = Item(name="other")
    return len(retained.name)
```

A fallible borrowed result obeys the same rule. `match` reads the `Ok` payload in place, and
`const part = try call(...)` binds the success as a borrow with the call's sources, held
until the last use of `part`; `return try call(...)` in a function that declares the same
borrow forwards it. A `mut` argument that is not named by `from` is written back to the
caller and is not borrowed by the result, so the result lends `data` while the position
advances.

```selka
# doc: expect 46
func tail(data: bytes, mut position: int) -> bytes from data fails str:
    if position > len(data):
        fail "past the end"
    const rest = data[position:]
    position = len(data)
    return rest
func measure(data: bytes) -> int fails str:
    mut at = 2
    const rest = try tail(data, mut at)
    return len(rest) * 10 + at
func main() -> int:
    match measure(b"abcdef"):
        case Ok(value):
            return value
        case Err(_):
            return 0
```

Storing or changing the success of `try` needs the copy, as for any borrowed result:
`mut kept = try copy(call(...))`, or `copy(part)` of the `const` binding. `selka fix` adds it.

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
func tail(data: bytes, start: int) -> bytes from data fails str:
    if start > len(data):
        fail "past the end"
    return data[start:]
func measure(data: bytes) -> int fails str:
    mut kept = try tail(data, 1)
    kept = kept + b"!"
    return len(kept)
func main() -> int:
    return 0
```

### R4 — Borrowed returns

Layer: Core.

Codes: `E_BORROW_SOURCE`, `E_BORROW_UNDECLARED`, `E_SINGLE_OWNER_BORROW`.

`-> T from a, b` declares a read-only result borrowed from the named plain or `mut`
managed parameters. There may be any number of sources. Every value return must refer to
those parameters, optionally through `Some` or a `fails` success; their slices are
covered by V4. `E_BORROW_UNDECLARED` points to the first return using an undeclared source.
An unknown or ineligible source is `E_BORROW_SOURCE`. Each source must appear once;
duplicates report the same code with a fix removing the duplicate. A nongeneric
function whose successful result contains no managed storage cannot declare `from`;
its fix removes the clause. A source lends only storage it holds: text or bytes for a text or
bytes result, a list of the result's element type for a list, and a record or one of its managed
fields for a record result. A plain (not `mut`) text or bytes parameter arrives as a view,
which lends only a text or bytes result of its own kind. A nongeneric clause in which no
source can lend its result is `E_BORROW_SOURCE` with the same fix; a source that cannot lend
beside one that can is dropped. A generic declaration is judged at each instance: an instance
whose sources cannot lend its result is `E_BORROW_SOURCE` at the call that made it, and the
clause's removal is its fix when no source's type names a type parameter (such a source cannot
reach a result a type parameter makes). Concrete scalar generic instances retain the declaration
and ignore borrowing. Formatting orders names by parameter position. Write `from`
before `fails`; function types cannot declare borrowed results.

```selka
# doc: expect 42
record Item:
    code: int
    name: str
func choose(a: Item, b: Item, c: Item, which: int) -> Item from a, b, c:
    if which == 0:
        return a
    if which == 1:
        return b
    return c
func main() -> int:
    const first = Item(code=1, name="first")
    const second = Item(code=2, name="second")
    const third = Item(code=42, name="third")
    const result = choose(first, second, third, 2)
    return result.code
```

```selka
# doc: expect-error E_BORROW_UNDECLARED
record Item:
    name: str
func borrowed(value: Item) -> Item:
    return value
func main() -> int:
    const owner = Item(name="ok")
    return len(borrowed(owner).name)
```

A borrowed record that holds `Some(p)` of a recursive field keeps `p`'s box in this
call's frame ([borrowed parents](#borrowed-parents)), so it is not returned, even under
`from`:

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
record Scope:
    name: bytes
    parent: Scope? = None


func child(scope: Scope) -> Scope from scope:
    return Scope(name=scope.name, parent=Some(scope))


func main() -> int:
    return len(child(Scope(name=b"top")).name)
```

### R6 — Borrowed selections

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

A managed selection borrows its selected input. Dictionary lookups with a default,
optional defaults and text `min`/`max` are read-only selections. Every possible input
owner stays held while the selection is live. Read it in place or copy it before
storing, moving or changing it. A literal default (`b""`, `"none"`, a number, `None` or
the empty list `[]`) is a static constant with no owner, so `r.name.unwrap_or(b"")`,
`r.items.unwrap_or([])` and `dicts.get(d, key, "")` borrow only their option or
dictionary: a `from r` accessor can return them. `options.take_or(own value, own default)` takes an owned option's
payload, or the default, without a copy.

`unwrap_or` on an option nobody else holds is the exception (F-71): when the option is the result of a call that lends
nothing (its result is not declared `from` a parameter) and the default is a value of its own (a literal, a new value
such as a call, a joined text or a constructor, or a name given with `own`), `maybe().unwrap_or("")` in a position that
takes a value (a `const` binding, an assignment, a `return`, a `fail`, a store, an `own` argument, a constructor's
field, a list literal's element, `Some`) gives an owned value: the payload moves out on `Some`, the default on `None`,
and the other is dropped. A read in a borrowing position still borrows for its statement, and so does a `mut` binding
(which may later borrow a place beside it). An option that is a local, a parameter, a field or a lent call, and a default
that is a place (`maybe().unwrap_or(self.name)`), keep the borrow: there the refusal names `options.take_or(own o, d)`
when the option is a local the function owns, and `copy(...)` otherwise.

```selka
# doc: expect 2
record Name:
    text: str


func maybe() -> str?:
    return Some("xy")


func main() -> int:
    const text = maybe().unwrap_or("")
    const name = Name(text=own text)
    return len(name.text)
```

```selka
# doc: expect 3 0
record Part:
    name: bytes?


func name_of(part: Part) -> bytes from part:
    return part.name.unwrap_or(b"")


func main(out: Stream) -> int:
    print(out, len(name_of(Part(name=Some(b"R10")))), len(name_of(Part(name=None))))
    return 0
```

```selka
# doc: expect 2
func main() -> int:
    const first = "a" + str(1)
    const second = "z" + str(2)
    const selected = min(first, second)
    return len(selected)
```

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
func main() -> int:
    const first = "a" + str(1)
    const second = "z" + str(2)
    mut retained = min(first, second)
    retained = retained + "!"
    return len(retained)
```

### M1 — Mut parameters

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

A `mut` parameter exclusively borrows its caller’s storage. The callee may read, change
or replace that value. Taking the borrowed owner into owning storage is refused; a
returned borrow follows the function’s declared `from` contract. A resource that must
transfer belongs in an `own` parameter.

```selka
# doc: expect 42
func reset(mut values: int[]):
    values = [42]
func main() -> int:
    mut values = [1]
    reset(mut values)
    return values[0]
```

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
func keep(mut values: int[]) -> int[][]:
    return [own values]
func main() -> int:
    return 0
```

### W2 — Own argument markers

Layer: Frontend and Core.

Codes: `E_OWN_MARKER`.

Write `own` when a named managed place transfers into an owning argument. Fresh calls,
literals and explicit copies transfer without a marker; concrete scalars have no managed
storage to give away. Core decides whether the operation takes storage and whether the
source may move. Frontend’s three call-mode spelling predicates only reconcile `mut`,
`own` and plain argument spelling with the called mode. Source-dependent generic scalar
instances retain the marker’s no-op interpretation. B2 covers the same written transfer
in non-call positions.

```selka
# doc: expect 2
func width(own values: int[]) -> int:
    return len(values)
func main() -> int:
    const values = [20, 22]
    return width(own values)
```

```selka
# doc: expect-error E_OWN_MARKER
func width(own values: int[]) -> int:
    return len(values)
func main() -> int:
    const values = [20, 22]
    return width(values)
```

### W4 — No slice to own

Layer: Core.

Codes: `E_SLICE_ESCAPES`.

A text, bytes or list slice borrows its source. An owning parameter cannot acquire that
borrowed storage, including through a named slice binding. Pass `copy(slice)` for an
independent value, or make the parameter plain when it only reads the argument;
`selka fix` writes the copy. Text and bytes slices are refused here since 10 November
2026 (D8); before, the check accepted them and the build copied them without a written
`copy(...)`.

```selka
# doc: expect 2
func width(own values: int[]) -> int:
    return len(values)
func main() -> int:
    const values = [1, 2, 3]
    return width(copy(values[0:2]))
```

```selka
# doc: expect-error E_SLICE_ESCAPES
func width(own values: int[]) -> int:
    return len(values)
func main() -> int:
    const values = [1, 2, 3]
    return width(values[0:2])
```

```selka
# doc: expect-error E_SLICE_ESCAPES
func keep(own name: str) -> int:
    return len(name)
func main() -> int:
    const name = "abcd" + "ef"
    return keep(name[0:2])
```

### V2 — Views are never stored

Layer: Core.

Codes: `E_SLICE_ESCAPES`.

A borrowed slice cannot enter an owning local, record, list, dictionary or other owning
storage. Binding it with `const` or writing `own` does not create independent storage.
Use an explicit `copy`; a bound slice’s repair can place that copy at its original
initializer.

```selka
# doc: expect 2
record Window:
    values: int[]
func main() -> int:
    const values = [1, 2, 3, 4]
    const part = copy(values[1:3])
    const window = Window(values=own part)
    return len(window.values)
```

```selka
# doc: expect-error E_SLICE_ESCAPES
record Window:
    values: int[]
func main() -> int:
    const values = [1, 2, 3, 4]
    const part = values[1:3]
    const window = Window(values=own part)
    return len(window.values)
```

### V4 — Returned views

Layer: Core.

Codes: `E_SLICE_ESCAPES`, `E_VIEW_FUNCTION_VALUE`.

A text, bytes or list slice may return as a borrow only under an explicit `from`
signature naming its source parameters. Declared sources can include mutable parameters
and more than one owner; permitted wrappers include `Some` and a `fails` success. The
caller keeps those sources alive through the borrowed result’s final use. A local source
needs an explicit copy. A function with a borrowed result cannot be used as a function
value; use a wrapper that returns an owned copy.

```selka
# doc: expect 2
func head(text: str) -> str from text:
    return text[0:2]
func main() -> int:
    return len(head("abcd"))
```

```selka
# doc: expect-error E_SLICE_ESCAPES
func head() -> bytes:
    const data = copy(b"local bytes")
    return data[0:2]
func main() -> int:
    return 0
```

### V5 — Joins of views

Layer: Core.

Codes: `E_SLICE_ESCAPES`.

Slice views of the same source can merge across branches. Joining incompatible slice
sources makes the view binding unavailable. Write an explicit copy at each branch
initialization when the joined result must own independent storage.

```selka
# doc: expect 4
func width(text: str, first: bool) -> int:
    const part: str
    if first:
        part = text[0:2]
    else:
        part = text[1:3]
    return len(part)
func main() -> int:
    return width("abcd", True) + width("abcd", False)
```

```selka
# doc: expect-error E_SLICE_ESCAPES
func head(text: str) -> str from text:
    return text[0:2]
func width(first: bool) -> int:
    const left = "abcd"
    const right = "wxyz"
    const part: str
    if first:
        part = head(left)
    else:
        part = right[0:2]
    return len(part)
func main() -> int:
    return width(True)
```

### V6 — Dictionary views

Layer: Frontend.

Codes: `E_LIVE_VIEW_CYCLE`, `E_VIEW_STORED`.

Dictionary `keys`, `values` and `items` projections are ephemeral views. Use them
directly as iteration sources or with supported immediate consumers such as `len`,
membership, `list`, `set` and `sorted`. Binding, storing, returning or passing a
projection to a user function is refused. Materialize a snapshot with `list`; recursive
stored types cannot hide a live view cycle.

```selka
# doc: expect 4
import dicts
func main() -> int:
    const mapping = {"a": 20, "b": 22}
    const keys = list(dicts.keys(mapping))
    return len(keys) + len(dicts.values(mapping))
```

```selka
# doc: expect-error E_VIEW_STORED
import dicts
func main() -> int:
    const mapping = {"a": 20, "b": 22}
    const keys = dicts.keys(mapping)
    return len(keys)
```

### C1 — Written copies

Layer: Core.

Codes: `E_CORE_HIDDEN_COPY`, `E_LITERAL_ARM`.

Write an independent runtime copy as `copy(value)` or use a conversion whose documented contract creates a copy. A move, borrow or ordinary read does not silently clone owned storage. Matching a projected text or bytes field against literals would require a hidden copy, so bind an explicit copy first. Core also verifies its own lowered copy operations.

The explicit copy below survives replacement of the source field.

Accepted:

```selka
# doc: expect 1
record Entry:
    text: str
func main() -> int:
    mut entry = Entry(text="yes")
    const text = copy(entry.text)
    entry.text = "no"
    match text:
        case "yes":
            return 1
        case _:
            return 0
```

Refused:

```selka
# doc: expect-error E_LITERAL_ARM
record Entry:
    text: str
func main() -> int:
    const entry = Entry(text="yes")
    match entry.text:
        case "yes":
            return 1
        case _:
            return 0
```

## Rule 2: Exclusion

A lender cannot change or be given away while something it lent is in use, and a loan for
writing is the only loan.

A loan lasts from the line that makes it to its last use, and it holds the place it names,
not the whole owner (R2). Changing or moving the lender in between is
`E_SINGLE_OWNER_OVERLAP` (R2, R7, X1, M5, M6), or `E_SLICE_ESCAPES` when the loan is a
slice (V3). A loan for writing excludes every other loan of the same place: two `mut`
arguments, or a `mut` and a read argument, must name disjoint places (M5), and a
`match mut` holds its place through the arm (X2). Writing is allowed only through a binding
or parameter declared `mut` (B1, M2), the call spells `mut name` where the signature says
`mut` (M3), and the target is an owner or an exclusive loan, not a temporary or a read loan
(M4). T3 closes the one other way two names could write the same storage: `class` and
`Cell` do not exist.

### T3 — No shared mutable identity

Layer: Frontend.

Codes: `E_CELL_ELEMENT`, `E_VALUE_CELL`, `E_VALUE_CLASS`.

Values do not provide shared mutable identity: `class` and builtin `Cell` are refused.
Use records for values and explicit ids or pool handles when a program needs identity.

```selka
# doc: expect 42
record Item:
    id: int
    name: str
func main() -> int:
    const item = Item(id=7, name="value")
    mut independent = copy(item)
    independent.id = 35
    return item.id + independent.id
```

```selka
# doc: expect-error E_VALUE_CLASS
class Item:
    value: int
func main() -> int:
    return 0
```

### B1 — Writability

Layer: Frontend.

Codes: `E_IMMUTABLE`.

`mut` makes a binding writable; `const` does not. Assigning to a `const` binding is
refused. Parameter writes also require the declaration modes in M2, and iteration
bindings obey R7.

```selka
# doc: expect 42
func main() -> int:
    mut total = 1
    total = 42
    return total
```

```selka
# doc: expect-error E_IMMUTABLE
func main() -> int:
    const total = 1
    total = 42
    return total
```

### R2 — Loans block changes

Layer: Core.

Codes: `E_SINGLE_OWNER_OVERLAP`.

While a read loan is live, its owner and overlapping places cannot move or change. Loans
arise from arguments, borrowed constants, matches, iteration and expression evaluation.
A borrowed constant stops holding its owner after its last use, so later mutation is
allowed.

F-string holes evaluate left to right like call arguments. An earlier managed
hole stays borrowed through later holes. When `print` renders a format directly,
those loans also cover later print arguments, separators and terminators.
Materialized text owns its storage independently of the values it rendered.

```selka
# doc: expect 3
func main() -> int:
    mut values = [1]
    const alias = values
    const observed = len(alias)
    append(mut values, 2)
    return observed + len(values)
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
func main() -> int:
    mut values = [1]
    const alias = values
    append(mut values, 2)
    return len(alias)
```

`copy(alias)` is a read of the alias like any other, so it ends the alias's hold only after it runs: take the snapshot
before the owner changes. (Until 5 November 2026 `check` accepted a `copy` of the alias after the change and only the
build refused it, with `E_CORE_UNSUPPORTED`.)

```selka
# doc: expect 3
func main() -> int:
    mut values = [1]
    const alias = values
    const snapshot = copy(alias)
    append(mut values, 2)
    return len(snapshot) + len(values)
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
func main() -> int:
    mut values = [1]
    const alias = values
    append(mut values, 2)
    const snapshot = copy(alias)
    return len(snapshot)
```

A `const` binding holds the place it names, not its whole owner. `const item = self.items[i]` holds `self.items`: a
write to another field of `self` (`self.links`, `self.count`, `self.inner.n`) may happen while `item` is live, and `item`
may be read after it. The same holds for nested records (`self.a.b` against `self.a.c`) and for a local record. The
fields next to the owner decide: a write to the borrowed field, to the whole record, to an element of the borrowed list
(`self.items[j]`) or to anything inside it overlaps, and so does passing the whole record `mut` to a call. A binding
holds the container its value lies in, not the element, so two elements of one list are never told apart. Only a
direct `const` binding of a place is read this way; a binding of a binding, a slice, an iteration binding and a borrowed call
result hold the whole owner, as before. The compiler reads such a binding's place again from the record after a write, so the
borrow never outlives the update of the record it was read from.

```selka
# doc: expect 23
record Builder:
    items: str[]
    links: str[]
    count: int
func link_all(mut self: Builder) -> int:
    for i in range(len(self.items)):
        const item = self.items[i]
        append(mut self.links, copy(item))
        self.count = self.count + len(item)
    return len(self.links) * 10 + self.count
func main() -> int:
    mut builder = Builder(items=["a", "bb"], links=[], count=0)
    return link_all(mut builder)
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
record Builder:
    items: str[]
    links: str[]
func link_all(mut self: Builder) -> int:
    const item = self.items[0]
    append(mut self.items, "x")
    return len(item)
func main() -> int:
    mut builder = Builder(items=["a"], links=[])
    return link_all(mut builder)
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
record Builder:
    items: str[]
    links: str[]
func touch(mut self: Builder):
    append(mut self.links, "x")
func link_all(mut self: Builder) -> int:
    const item = self.items[0]
    touch(mut self)
    return len(item)
func main() -> int:
    mut builder = Builder(items=["a"], links=[])
    return link_all(mut builder)
```

### R7 — Iteration

Layer: Frontend and Core.

Codes: `E_SINGLE_OWNER_OVERLAP`, `E_VALUE_BINDING_WRITE`.

Iteration bindings are read-only. Core refuses changes to a dynamically sized collection
held by its iteration loan, including same-length element replacement. Direct
fixed-array iteration uses a separate fixed-length path, as the accepted example shows.
The runtime retains `R_LIST_ITERATION_MUTATION` as a backstop.

The loan is on the place that is iterated, not on its owner: `for root in tree.roots` borrows
`tree.roots`. A sibling path may change in the body, through `append(mut ...)` or a `mut`
argument (`tree.nodes[root].children`, another field of `tree`); the iterated field, a prefix
of it (`tree`) and anything inside it (an element, a field of an element) stay borrowed.
A place the checker cannot name (a call result, a dictionary value) borrows its whole owner.

```selka
# doc: expect 2
func main() -> int:
    mut values = FixedArray[int, 2]([1, 2])
    for value in values:
        values[0] = value
    return values[0]
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
func main() -> int:
    mut values = [1, 2]
    for value in values:
        append(mut values, value)
    return len(values)
```

```selka
# doc: expect 2
record Node:
    children: int[]
record Tree:
    nodes: Node[]
    roots: int[]
func main() -> int:
    mut tree = Tree(nodes=[Node(children=[]), Node(children=[])], roots=[0, 1])
    for root in tree.roots:
        append(mut tree.nodes[root].children, root)
    return len(tree.nodes[0].children) + len(tree.nodes[1].children)
```

A call that takes the owner of the iterated list `mut` (`touch(mut st, name)` inside `for name in st.names:`) is refused,
and the refusal names the repair: walk the list by position. The loop holds no borrow between its visits, and the one element
read each time is copied (`copy(st.names[k])`), which costs one element, not the list. A scalar element needs no copy
(`const id = st.ids[k]`).

```selka
# doc: expect 3
record Store:
    names: str[]
    count: int
func touch(mut st: Store, name: str):
    st.count += len(name)
func main() -> int:
    mut st = Store(names=["a", "bb"], count=0)
    mut k = 0
    while k < len(st.names):
        const name = copy(st.names[k])
        touch(mut st, name)
        k += 1
    return st.count
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
record Tree:
    roots: int[]
func grow(mut tree: Tree):
    append(mut tree.roots, 0)
func main() -> int:
    mut tree = Tree(roots=[0])
    for root in tree.roots:
        grow(mut tree)
    return len(tree.roots)
```

### M2 — Declared mutation

Layer: Frontend.

Codes: `E_MUTATION_MARKER`, `E_MUTATION_PERMISSION`.

Writes to caller storage require parameters declared `mut`. The declaration’s mutable
positions are its mutation contract; writes to an `own` parameter affect the callee’s
storage. Mutable record and fixed-array parameters require copyable contents without
pending Results. A write whose possible external targets exceed the declared set is
refused.

```selka
# doc: expect 42
func grow(mut values: int[]):
    append(mut values, 42)
func main() -> int:
    mut values: int[] = []
    grow(mut values)
    return values[0]
```

```selka
# doc: expect-error E_MUTATION_MARKER
func grow(values: int[]):
    append(mut values, 42)
func main() -> int:
    return 0
```

### M3 — Call markers

Layer: Frontend.

Codes: `E_MUTATION_MARKER`.

Pass a writable argument as `mut place` exactly where the called signature declares
`mut`. Missing and extra markers are refused. The marked expression must name an
assignable place. Intrinsic collection and scalar-text operations obey the same
call-mode spelling rule.

```selka
# doc: expect 42
func grow(mut values: int[]) -> int:
    append(mut values, 41)
    return values[0] + values[1]
func main() -> int:
    mut values = [1]
    return grow(mut values)
```

```selka
# doc: expect-error E_MUTATION_MARKER
func grow(mut values: int[]):
    append(mut values, 41)
func main() -> int:
    mut values = [1]
    grow(values)
    return 0
```

### M4 — Writable targets

Layer: Frontend and Core.

Codes: `E_SINGLE_OWNER_BORROW`, `E_VALUE_TEMPORARY_WRITE`.

A mutation requires a writable owning local, an owned parameter, or an exclusive `mut`
borrow. Core checks the owner’s permission and active loans. Frontend rejects writes
into a value returned by a call: bind that result to a mutable local before changing it.

```selka
# doc: expect 42
record Box:
    items: int[]
func make() -> Box:
    return Box(items=[1])
func main() -> int:
    mut box = make()
    append(mut box.items, 41)
    return box.items[0] + box.items[1]
```

```selka
# doc: expect-error E_VALUE_TEMPORARY_WRITE
record Box:
    items: int[]
func make() -> Box:
    return Box(items=[1])
func main() -> int:
    append(mut make().items, 41)
    return 0
```

### M5 — Disjoint arguments

Layer: Core.

Codes: `E_SINGLE_OWNER_OVERLAP`.

An exclusive mutable argument must be disjoint from the other arguments whose borrows
remain live in that call. Different record fields are disjoint. Different literal list
indices are disjoint, whether the other argument is mutable or read-only, and after any
equal field prefix (`tree.nodes[0]` and `tree.nodes[1]`). A record field inside an element
(`rows[0].tags`), dynamic indices, equal indices and overlapping prefixes do not establish
disjointness. Scalar argument reads finish before the call mutates storage; argument
expressions still evaluate left to right.

Two payload bindings of one `match mut` arm name different fields of the payload inside the
matched place (X2), so passing both `mut` is disjoint (`put(mut keys, mut vals)` in
`case pairs(keys, vals)`, or `mut p.keys, mut p.vals` of a record payload `p`) when the
matched place is a local, a parameter, a path of record fields of one, or an enclosing
arm's binding (`match mut x:` in `case both(x, y):`, where `fill(mut u, mut v)` in
`case two(u, v):` and `fill(mut u, mut y)` both separate); inside a list element it is not
(`match mut ts[0]`). A binding passed beside the matched place (`mut u, mut x`), beside a
field path under itself, or read beside a `mut` sibling binding still overlaps.

A read argument that makes a value of its own finishes before the call the same way, so it may
read a record another argument passes `mut` (`emit(mut work, "x" + target(work))`,
`link(mut self, self.design + suffix)`): an operator's result, a format string, `copy(...)` or
a call whose result is not declared `from` that record. This holds when the `mut` argument is a
local or a path of fields of one (`mut work`, `mut work.inner`), with no list element in the
path, and no other argument takes the record `mut` or `own`. An argument that lends a part of the
record to the call (`work.targets[0]`, a call declared `from work`) stays refused, and the
message names it and the copy that frees it. The same holds for such a value given to an `own`
parameter (`keep(mut work, copy(work.targets[0]))`, `keep(mut work, "a" + target(work))`): the
read ends when the value is made, and the callee owns a value that shares nothing with the record.
A `match mut` payload binding passed `mut` is such a path too (`emit(mut held, copy(held.targets[0]) + "?")`,
`put(mut keys, mut vals, keys[0] + "!", vals[0])`): Core makes every argument's value before it takes the
payload out of its case for the `mut` one.
A move of a part of the record (`own work.lines`, `own work`) and an argument that lends a part of
it to the `own` parameter (`work.targets[0]`, a call declared `from work`) stay refused with the
message of an argument that reads the record; a resource keeps the earlier rule.

The diagnostic names both overlapping arguments and points to the earlier one. For two
list elements it says that they are separate storage only when both indices are distinct
literals, and names the remedies: bind a copy of the read element first, or pass the list
`mut` and index both elements inside the callee. When one argument passes a record `mut` and
another lends a part of it (`rebuild(mut state, state.stack)`), the message names both arguments,
says that the callee may change what the other reads, and gives the remedies: pass a value of its
own (`copy(state.stack)`), or pass the record `mut` and read it inside the callee.
If separate writable storage is intended, write `mut part = copy(a[0])`, pass
`mut part`, then write `a[0] = own part` after the call. Scalar write-back uses
plain `part`. Move-only values cannot use this copy rewrite. Choosing separate
storage requires a deliberate decision, so this message has no automatic fix.

```selka
# doc: expect 42
record Pair:
    left: int[]
    right: int[]
func fill(mut left: int[], mut right: int[]):
    append(mut left, 20)
    append(mut right, 22)
func main() -> int:
    mut pair = Pair(left=[], right=[])
    fill(mut pair.left, mut pair.right)
    return pair.left[0] + pair.right[0]
```

```selka
# doc: expect 1
record Work:
    lines: str[]
    targets: str[]
func target(work: Work) -> str:
    return copy(work.targets[0])
func emit(mut work: Work, statement: str):
    append(mut work.lines, copy(statement))
func main() -> int:
    mut work = Work(lines=[], targets=["out"])
    emit(mut work, "append(mut " + target(work) + ")")
    return len(work.lines)
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
func both(values: int[], mut destination: int[]) -> int:
    append(mut destination, 1)
    return len(values)
func main() -> int:
    mut values = [1]
    return both(values, mut values)
```

```selka
# doc: expect 2
record Node:
    kind: int
    children: int[]
record Tree:
    nodes: Node[]
func link(mut parent: Node, child: Node):
    append(mut parent.children, child.kind)
func main() -> int:
    mut tree = Tree(nodes=[Node(kind=1, children=[]), Node(kind=2, children=[])])
    link(mut tree.nodes[0], tree.nodes[1])
    return tree.nodes[0].children[0]
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
record Node:
    kind: int
    children: int[]
record Tree:
    nodes: Node[]
func link(mut parent: Node, child: Node):
    append(mut parent.children, child.kind)
func main() -> int:
    mut tree = Tree(nodes=[Node(kind=1, children=[]), Node(kind=2, children=[])])
    const parent = 0
    const child = 1
    link(mut tree.nodes[parent], tree.nodes[child])
    return 0
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
record Builder:
    design: str
    links: str[]
func link(mut self: Builder, file: str):
    append(mut self.links, copy(file))
func main() -> int:
    mut builder = Builder(design="d", links=[])
    link(mut builder, builder.design)
    return len(builder.links)
```

### M6 — No self-source

Layer: Core.

Codes: `E_SINGLE_OWNER_OVERLAP`.

Writing a byte buffer from its own borrowed octets is refused: `bytes(buffer)`
explicitly supplies an independent snapshot. List extension also refuses an overlapping
ancestor or an ambiguous borrowed source. Same-depth list self-extension is supported;
its runtime operation handles self-identity without treating a prefix overlap as
independent storage.

```selka
# doc: expect 5
import buffers
func main() -> int:
    mut buffer = byte_buffer([65, 66, 67])
    _ = buffers.append_range(mut buffer, bytes(buffer), 0, 2)
    return len(buffer)
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
import buffers
func main() -> int:
    mut buffer = byte_buffer([65, 66, 67])
    _ = buffers.append_range(mut buffer, buffer, 0, 2)
    return len(buffer)
```

### V3 — View sources stay put

Layer: Core.

Codes: `E_SLICE_ESCAPES`.

A source must remain available and unchanged while a slice view still needs it. Moving,
mutating or replacing a live source is refused with an explicit-copy repair. A view’s
completed final read releases that restriction. Loop invalidation can be reported at the
later view use; the retired typed-view loop restriction no longer exists.

The refusal names the line and column of the write, call or move that changed the source, and
what it wrote (a write to any field of a record changes the whole record, so a view of `r.buf`
does not survive `r.pos = n`). Its repairs come in the order that copies nothing first: read the
view before that line; after a write, keep the span (start and length) and slice again where it is
read; and the copy of the slice's binding last. A repair that does not apply is left out: no
reorder where the change does not lie between the binding and the read, no re-slicing after a move.

```selka
# doc: expect 6
func main() -> int:
    mut text = "abc"
    const part = text[0:2]
    const width = len(part)
    text += "d"
    return width + len(text)
```

```selka
# doc: expect-error E_SLICE_ESCAPES
func main() -> int:
    mut text = "abc"
    const part = text[0:2]
    text += "d"
    return len(part)
```

### X1 — Matching a name borrows

Layer: Core.

Codes: `E_SINGLE_OWNER_OVERLAP`.

Matching an ordinary, non-affine named value or projected place borrows its payload.
The source stays held until the active arm’s final use of a payload binding; a
conflicting move or mutation is refused. Matching a fresh owned call, constructor or
explicit copy consumes that temporary and transfers its immediate payload, and so does
`match own name` for an owned local or an `own` parameter: the owner is moved, so a
payload binding owns its value and `own payload.field` takes a field under B8 (several
in one statement). A
borrowed or `mut` parameter, a borrowed local and a field or element place cannot be
consumed this way. A declared `from` call still borrows under R3. Nested non-affine
patterns continue to borrow their intermediate value. A resource-bearing move-only
scrutinee is consumed instead: matching a named owner requires `match own value` under B2.

```selka
# doc: expect 44
func fresh() -> int[]?:
    return Some([20, 22])
func width(saved: int[]?) -> int:
    match saved:
        case Some(payload):
            return len(payload)
        case None:
            return 0
func main() -> int:
    const saved = fresh()
    const before = width(saved)
    match fresh():
        case Some(payload):
            const kept = own payload
            return before + kept[0] + kept[1]
        case None:
            return 0
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
func main() -> int:
    const saved: int[]? = Some([1])
    match saved:
        case Some(payload):
            const moved = own saved
            return len(payload)
        case None:
            return 0
```

### X2 — Mutable matches

Layer: Frontend and Core.

Codes: `E_MATCH_MUT`, `E_SINGLE_OWNER_BORROW`, `E_SINGLE_OWNER_OVERLAP`.

A `match mut` scrutinee names a writable local, record field or supported list element.
Its payload bindings write through to that place; they cannot move or escape into owning
storage. Frontend checks the source place’s supported shape, and Core checks the
writable owner and exclusive loans. Current limit: dictionary elements cannot be the
place of a mutable match. Match the element read-only and assign the complete updated
value back to the dictionary instead.

```selka
# doc: expect 42
func main() -> int:
    mut saved: int[]? = Some([1])
    match mut saved:
        case Some(payload):
            append(mut payload, 41)
        case None:
            pass
    match saved:
        case Some(payload):
            return payload[0] + payload[1]
        case None:
            return 0
```

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
func main() -> int:
    const saved: int[]? = Some([1])
    match mut saved:
        case Some(payload):
            append(mut payload, 41)
        case None:
            pass
    return 0
```

```selka
# doc: expect-error E_MATCH_MUT
func main() -> int:
    mut mapping: dict[str, int[]?] = {"one": Some([1])}
    match mut mapping["one"]:
        case Some(payload):
            append(mut payload, 41)
        case None:
            pass
    return 0
```

## Rule 3: Gone

After `own`, the name cannot be used until it is assigned again.

A moved name cannot be read, written through or moved again (B3, `E_SINGLE_OWNER_MOVED`),
and that holds at every back edge of a loop (B6, `E_SINGLE_OWNER_LOOP`). Assigning a whole
new value makes the name available again (B4), and after an `if` or `match` a name is
available only if every continuing path left it so (B5); both are in the
[appendix](#appendix-accepted-behaviour-and-retired-restrictions), because they refuse
nothing of their own. C3 says where the value goes: Core destroys each owned value after its
last use, on every path.

### B3 — Use after move

Layer: Core.

Codes: `E_SINGLE_OWNER_MOVED`.

A moved binding is unavailable: it cannot be read, written through or moved again.
Reinitialize a writable whole binding under B4, or request an independent `copy` before
transferring its source. A read that comes after the move in the same call or constructor, in an
argument written after the one that gives the value, and only gives a number or a `bool`
(`len(x)` of a text, bytes, list, dictionary or set, a comparison or arithmetic over it), or is a literal, needs no copy: the arguments are evaluated from
left to right as they are written, so the call written with the read first
(`Source(total=len(plain), mem=own plain)`) reads the value and then moves it. The refusal names
that form before the copy, and `selka fix` writes it where the function checks with the call so
written (a later statement that reads the value, a read that keeps part of it, a positional
argument and a comment between the arguments keep the copy). Pending Results have their separate consumption obligations
under L1.

```selka
# doc: expect 84
func main() -> int:
    const source = [42]
    const independent = copy(source)
    const destination = own source
    return destination[0] + independent[0]
```

```selka
# doc: expect-error E_SINGLE_OWNER_MOVED
func main() -> int:
    const source = [42]
    const destination = own source
    return destination[0] + source[0]
```

### B6 — Loops

Layer: Core.

Codes: `E_SINGLE_OWNER_LOOP`.

An owner available when a loop starts must remain available at every back edge, `break`
and `continue`. A move inside a continuing iteration therefore needs whole-binding
reinitialization before that edge.

```selka
# doc: expect 3
func main() -> int:
    mut values = [1]
    for index in range(2):
        const taken = own values
        values = [taken[0] + 1]
    return values[0]
```

```selka
# doc: expect-error E_SINGLE_OWNER_LOOP
func main() -> int:
    const values = [1]
    for index in range(2):
        const taken = own values
        assert taken[0] == 1
    return 0
```

### C3 — Destruction

Layer: Core.

Codes: `E_NOALLOC_ALLOCATES`.

Core destroys each owned value after its last use on every path, including early returns and checked propagation. An explicit copy has its own lifetime. `@noalloc` is checked against lowered ownership operations, including required copies and cleanup; source syntax alone does not prove an allocation-free function.

A read-only helper can be allocation-free while its caller owns a collection. Returning a freshly allocated collection from a `@noalloc` function fails the build-time contract.

Accepted:

```selka
# doc: expect 2
@noalloc
func size(values: int[]) -> int:
    return len(values)
func main() -> int:
    const values = [1, 2]
    return size(values)
```

Refused:

```selka
# doc: build
# doc: expect-error E_NOALLOC_ALLOCATES
@noalloc
func make() -> int[]:
    return [1, 2]
func main() -> int:
    return len(make())
```

## Current limits

These refusals come from what the checker or the representation of values can do today, not
from the model. Removing one removes a refusal and changes no verb and none of the three
rules. R5, B8 and Z3 are rules below. The other limits belong to rules filed elsewhere, so
they are described here with what would remove them.

| Limit | Where it shows | What would remove it |
| --- | --- | --- |
| R5: a `from` function returns only borrows (and static empties) | R5, `E_BORROW_MIXED` | A returned value that is a borrow on one path and a fresh owner on another needs one run-time shape for both. Nothing is decided. Until then copy the borrowed returns and remove `from`. |
| B8: no partial record moves across statements | B8, `E_SINGLE_OWNER_BORROW`, `E_SINGLE_OWNER_MOVED` | The checker and the drop plans tracking which fields of a record are gone after a statement ends. Within one statement several fields already move out together (lane FR91); moves spread over statements are not planned. Until then move the fields in one statement (`total(own p.lo, own p.hi)`; `selka fix` joins two `const` moves the next call takes), or `copy(record.field)`. |
| A text, bytes or list view stored in a local record, list, dictionary or option (`Some(view)`): a slice (`p[0:2]`) or the result of a `from` call (`first_text(r)`). These are 24 of the ownership matrix's 312 function-local cells, 6 of them the option form, and the only ones where a bare name is refused | V2, `E_SLICE_ESCAPES` | A representation in which a view can sit where a field or an element expects a block. Frame blocks, which hold a whole parameter (B9, collections of borrows), would take these only by a copy the compiler inserts, which was decided against. One value shape that is either a view or an owner, for local aggregates only, would take them all without a copy (estimated 23 to 49 lane-hours); such an aggregate could not be passed whole to a function. For a local record alone, a view kept as a field of the record's value would do (3 to 6 hours). None is chosen. Until then write `copy(...)`; a record result of a `from` call goes where its field would (B9's sources), and the field read directly or a slice in a `mut` local (B9) is accepted. |
| X2: a mutable match on a dictionary element | X2, `E_MATCH_MUT` | `take` and `exchange` reaching dictionary elements. Until then match the element read-only and assign the complete updated value back. |
| Z3: a shape `check` accepts and `build` cannot place | Z3, `E_CORE_UNSUPPORTED` | `check` running the placement of ownership operations that `build` runs; what that costs is being measured. A shape that is valid is a gap in the scheduler and is fixed there. |

The test-loop plan (`docs/audits/test-loop-plan-2026-11-09.md`), Part B, prices and orders the work that would remove these limits.

### B8 — No partial record moves

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

`own record.field` transfers a managed field by consuming its whole owning record. The
record becomes unavailable and its other fields are destroyed at that point. A record
that remains usable supplies a field by a read borrow or an explicit copy; assigning its
fields new values remains possible. A field of a borrowed record cannot be taken this
way.

One statement may move several fields of one owned record, each field once:
`total(own p.lo, own p.hi)` or `Graph(ids=own t.ids, nodes=own t.nodes)`. The record is an
`own` parameter, a `const` or `mut` local, or a binding that owns what it names (a `match own`
payload, the payload of `own x else:`, the element of `for x in own xs:`). It is consumed
once, at the first move the statement makes, and the fields no move names are destroyed
there, as with one move. The moves count together only where the statement runs every one
of them in order: call arguments, constructor fields, `try`, arithmetic, `print` and f-string
holes. A move in the right operand of `and` or `or`, in a branch, in another statement or
inside another operation (`append(mut xs, f(own p.a, own p.b))`) is a move of its own, and
the record is gone by then; so is a read of the record after the first move, which is read
into a local before the statement instead. A field of a `match mut` or read-only `match`
binding or of a plain or `mut` parameter is lent, never moved. Each refusal names the way out
in the program's own words, and `selka fix` joins `const a = own p.x` and `const b = own p.y`
into the call or constructor of the next statement when that is their only use.

```selka
# doc: expect 42
record Pair:
    taken: int[]
    spare: str
func main() -> int:
    const pair = Pair(taken=[42], spare="finished")
    const values = own pair.taken
    return values[0]
```

```selka
# doc: expect 21
record Piece:
    order: func(int, int) -> int
    items: int[]
record Pair:
    lo: Piece
    hi: Piece
    tag: str
func cmp(a: int, b: int) -> int:
    return a - b
func total(own a: Piece, own b: Piece) -> int:
    return len(a.items) * 10 + len(b.items)
func main() -> int:
    const p = Pair(lo=Piece(order=cmp, items=[1, 2]), hi=Piece(order=cmp, items=[3]), tag="t")
    return total(own p.lo, own p.hi)
```

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
record Pair:
    taken: int[]
    spare: str
func consume(pair: Pair) -> int:
    mut values = own pair.taken
    return values[0]
func main() -> int:
    return consume(Pair(taken=[42], spare="kept"))
```

### R5 — One kind of return

Layer: Core.

Codes: `E_BORROW_MIXED`.

A `from` function cannot return a fresh owned value on another path. Empty alternatives
such as `None` are compatible with borrowing; literals and constants that introduce no
new owned storage are also allowed, and so is the empty list literal `[]`, which is the
runtime's static empty list (a non-empty `[1]` or a named list is new storage). Failure
payloads keep ordinary ownership. To make the function owning, copy its borrowed returns
and remove the clause.

```selka
# doc: expect 42
func maybe(values: int[], present: bool) -> int[]? from values:
    if present:
        return Some(values)
    return None
func main() -> int:
    const values = [42]
    match maybe(values, True):
        case Some(found):
            return found[0]
        case None:
            return 0
```

```selka
# doc: expect 2
record Shelf:
    labels: str[]?
func labels_of(shelf: Shelf) -> str[] from shelf:
    match shelf.labels:
        case Some(labels):
            return labels
        case None:
            return []
func main() -> int:
    const full = Shelf(labels=Some(["a", "b"]))
    const empty = Shelf(labels=None)
    return len(labels_of(full)) + len(labels_of(empty))
```

```selka
# doc: expect-error E_BORROW_MIXED
record Item:
    name: str
func choose(value: Item, fresh: bool) -> Item from value:
    if fresh:
        return Item(name="new-" + str(1))
    return value
func main() -> int:
    const owner = Item(name="old")
    return len(choose(owner, True).name)
```

### Z3 — Build-time ownership limits

Layer: Core.

Codes: `E_CORE_UNSUPPORTED`.

Some lowering and ownership scheduling shapes remain build-time limits. A build reports `E_CORE_UNSUPPORTED` with rule Z3 when it cannot place a required ownership operation, even if source checking succeeded. A shape that is valid is a gap in the scheduler, not a rule: it is fixed there, and one that is invalid is reported by `check` with its own code (the cases the stage-2 EDA port found are in `src/core/check_build_agree_test.zig`, and the G3 redo's in `test/check_build_agree_redo_cli_test.zig`). The gate builds every function of every language-suite file
the check accepts (`src/core/check_build_corpus_test.zig`), so a new disagreement there fails it. Other ABI, type or backend limits can use the same code without an ownership rule.

The refusal names its statement: the call or store the scheduler could not place, at its line, in the function that holds it (`child (inlined into main)` when inlining moved it), with a sentence that says how it conflicts with the other place, and a note at that place:

```text
main.selka:12:5: error[E_CORE_UNSUPPORTED]: the ownership pass cannot schedule a call in child (inlined into main): it takes ownership of `ctx.block.rules` (line 12), which is a borrowed part of `ctx` at that point, not an owner; this shape has no safe destruction schedule
  note: ownership rule Z3
  note: main.selka:12:27: `ctx.block.rules` is read here as a borrow of `ctx`
```

One limit is reported by `check` itself, with this code and rule: a function that `fails` with a managed error type (such as `str`) cannot return a borrow of its `mut` parameter (`func next(mut self: Cursor) -> Entry? from self fails str`). The ownership certificate cannot yet state a borrow of the parameter's final value inside a `Result` that owns its error. Without `fails`, or with an `int` error, the borrow builds. The repair is a copy without `from`, a scalar error, or a split of the update (`advance(mut self)`) from the read (`current(self) -> Entry? from self`).

For example, bind an explicit owned bytes copy before lending a slice of bytes to a task. A plain `bytes` parameter given to a task whole is lent as it is (FR58); a slice of bytes or text written at the submit itself is not yet (a slice of a list there is copied into a new list). The first program has that owner; the second requests the still-unsupported loan of the slice. Its refusal is checked at build time without running an artifact.

Accepted:

```selka
# doc: expect 2
import parallel
func measure(value: bytes) -> int:
    return len(value)
func go(value: bytes) -> int:
    with parallel.group() as group:
        const owned = copy(value[0:2])
        const job = group.submit(measure, owned)
        return job.result()
func main() -> int:
    return go(b"abc")
```

Refused:

```selka
# doc: build
# doc: expect-error E_CORE_UNSUPPORTED
import parallel
func measure(value: bytes) -> int:
    return len(value)
func go(value: bytes) -> int:
    with parallel.group() as group:
        const job = group.submit(measure, value[0:2])
        return job.result()
func main() -> int:
    return go(b"abc")
```

## Applications

Resources, task groups and pending Results follow the three rules. The rules below say how,
for a value that cannot be duplicated, a scope that borrows, and a value that must be
consumed.

- A **resource** cannot be duplicated, so `copy` does not apply and it is only lent, lent
  for writing or given. T2 says which parameter mode takes one, T4 where one may be stored
  and W3 how function types spell it. P1 to P4 say where a resource comes from and how long
  it lives: a `with` scope lends it to its body, so it cannot leave the scope (Escape).
- A **task group** is a scope that borrows. K1 to K3 say what is lent to its tasks until the
  group closes, and that the group and its handles stay inside the block.
- A **pending Result** must be consumed. L1 says that every one is handled, returned,
  transferred or explicitly discarded before its scope ends.

### T2 — Move-only types

Layer: Frontend.

Codes: `E_LIST_TYPE`, `E_OWN_PARAMETER`, `E_RESULT_OPERATION`.

Resources and the records that hold them are move-only: `copy` cannot duplicate them. A
parameter that takes such an owner must say `own`; an exclusive loan says `mut`.
A capability is not move-only: it is a shareable handle (5C), copied like an integer,
and a record that holds one is as copyable as its other fields allow.

```selka
# doc: expect 42
import filesystem
resource Ticket: filesystem
result Open:
    ok: Ticket,
    err: int
func open_ticket(fs: Filesystem) -> Open:
    return acquire_resource[Open](fs, FixedArray[u8, 0]([]))
func main() -> int:
    const opened = open_ticket(filesystem.memory())
    const next = own opened
    _ = own next
    return 42
```

```selka
# doc: expect-error E_OWN_PARAMETER
resource Ticket: filesystem
func keep(ticket: Ticket) -> int:
    return 0
func main() -> int:
    return 0
```

### T4 — Containment

Layer: Frontend.

Codes: `E_DICT_TYPE`, `E_LIST_ELEMENT`, `E_LIST_TYPE`, `E_RECURSIVE_RECORD`, `E_SET_ELEMENT`, `E_TEXT_IMMUTABLE`.

Container elements must satisfy their storage rules: lists, dictionaries and sets cannot
hide resource owners. Lists may carry pending Results while preserving L1
obligations; other ordinary containers require copyable elements. Recursive boxed values
cannot contain resources or pending Results. A capability is a scalar handle (5C), so a
list, dictionary, option, union payload or recursive box may hold one. Text and bytes
are immutable. File-owner containment is P4.

```selka
# doc: expect 2
import filesystem
func main() -> int:
    const fs = filesystem.memory()
    const providers = [fs, fs.read_only()]
    return len(providers)
```

```selka
# doc: expect-error E_RECURSIVE_RECORD
record OpenChain:
    file: TextFile
    next: OpenChain?

func main() -> int:
    return 0
```

### W3 — Function types

Layer: Frontend.

Codes: `E_OWN_PARAMETER`.

Function types preserve each parameter’s plain, `mut` or `own` mode. A move-only
parameter position must say `own` when it takes the value, including inside a record
field or another callable type. A plain move-only position is refused at its
declaration.

```selka
# doc: expect 42
import network
func consume(own listener: network.Listener) -> int:
    _ = own listener
    return 1
func accept(callback: func(own network.Listener) -> int) -> int:
    _ = callback
    return 42
func main() -> int:
    return accept(consume)
```

```selka
# doc: expect-error E_OWN_PARAMETER
import network
func accept(callback: func(network.Listener) -> int) -> int:
    return 42
func main() -> int:
    return 0
```

### P1 — Resource origin

Layer: Core.

Codes: `E_RESOURCE_ORIGIN`.

Acquire a resource from a provider held by a named binding. Open a dependent scope directly from that provider or a named record that contains it. A resource carrier has one provider origin; it cannot combine resources from different providers. Receiver-type errors are ordinary type errors, not origin refusals.

The helper below names its provider. Its entry point does not acquire a resource or access the filesystem.

Accepted:

```selka
# doc: expect 0
resource Ticket: filesystem
result Open:
    ok: Ticket,
    err: int
func open_ticket(fs: Filesystem) -> Open:
    return acquire_resource[Open](fs, FixedArray[u8, 0]([]))
func main() -> int:
    return 0
```

Refused:

```selka
# doc: expect-error E_RESOURCE_ORIGIN
import filesystem
resource Ticket: filesystem
result Open:
    ok: Ticket,
    err: int
func open_ticket(fs: Filesystem) -> Open:
    return acquire_resource[Open](fs, FixedArray[u8, 0]([]))
func unnamed(_fs: Filesystem) -> Open:
    return acquire_resource[Open](filesystem.memory(), FixedArray[u8, 0]([]))
func main() -> int:
    return 0
```

### P2 — Resource lifetime

Layer: Core.

Codes: `E_RESOURCE_ESCAPE`.

A resource, including a Result or record that contains it, cannot outlive the dependent `with` scope it was opened in. A capability provider is a handle the runtime keeps until the process ends (5C), so rebinding or moving the variable that names it while a dependent resource is live is accepted: the resource keeps the provider it came from. Consume or finish the resource before its `with` scope ends.

The accepted helper releases its resource-bearing Result within the provider invocation. The runnable entry point performs no acquisition.

Accepted:

```selka
# doc: expect 0
resource Ticket: filesystem
result Open:
    ok: Ticket,
    err: int
func open_ticket(fs: Filesystem) -> Open:
    return acquire_resource[Open](fs, FixedArray[u8, 0]([]))
func within(fs: Filesystem) -> int:
    const live = open_ticket(fs)
    _ = own live
    return 0
func main() -> int:
    return 0
```

Refused:

```selka
# doc: expect-error E_RESOURCE_ESCAPE
import filesystem
resource Ticket: filesystem
result Open:
    ok: Ticket,
    err: int
func open_ticket(fs: Filesystem) -> Open:
    return acquire_resource[Open](fs, FixedArray[u8, 0]([]))
func main() -> int:
    const fs = filesystem.memory()
    mut saved: Open = Err(0)
    _ = own saved
    with fs.read_only() as readonly:
        saved = open_ticket(readonly)
    _ = own saved
    return 0
```

### P3 — Returned resources

Layer: Core.

Codes: `E_RESOURCE_ESCAPE`, `E_RESOURCE_ORIGIN`.

A function returning a resource has exactly one input in its signature that the result can come from, its origin. The returned resource must depend on that input, including when it is wrapped in a Result or carrier record. A local provider cannot supply an escaping resource, and two possible input origins are ambiguous.

The count is every parameter that is a resource (an open `File` or `TextFile`, a `resource` type, a record that holds one) or a provider of the result's kind: a `Filesystem` for a file or a `filesystem` resource, a `Network` for a `network` resource (a `Poller`, a `Connection`, a `Listener`). A `Clock`, an `Entropy`, an `Environment` and a `Process` acquire no resource, and a provider of the other kind cannot supply this one, so neither is counted; a `Stream`, an `Input` and a `Stop` are handles and are not counted. When exactly one parameter is an `own` resource of the result's type (or of its Result's payload), it is the origin and no provider beside it is counted; another resource still is. A function whose count is not one is refused with `E_RESOURCE_ORIGIN` at its name, and the message lists the inputs it counted, in source order, with their types: `` `two` returns a resource, so it takes exactly one input the result can come from (a `Network` or a resource), and it takes 2: `net: Network`, `other: Network` ``. Keep the one the result comes from; the work that needs the others beside it goes in a function that returns a `bool` or an `int`, which may take any number of inputs, a file as `mut` and any other resource as `own` (the operations on a `Poller` take it `own`). (A function that takes only inputs that are not counted keeps the origin it had before this narrowing, its one provider or resource input, so nothing accepted before is refused.)

So `func step(own live: network.Poller, root: Filesystem) -> network.Poller`, `func on_event(own live: network.Poller, clock: Clock) -> network.Poller`, `func dial_slot(own live: network.Poller, net: Network) -> network.Poller` and `func open_server(net: Network, fs: Filesystem) -> network.Polling` are accepted; their origins are `live`, `live`, `live` and `net`. A body that drops `live` and returns a poller made from `net` is refused at its `return` with `E_RESOURCE_ESCAPE`, because the caller ties the result to `live`.

Forwarding an owned resource preserves its one input origin; this example checks the helper without acquiring a resource.

Accepted:

```selka
# doc: expect 0
resource Ticket: filesystem
func forward(own token: Ticket) -> Ticket:
    return token
func main() -> int:
    return 0
```

Refused:

```selka
# doc: expect-error E_RESOURCE_ORIGIN
resource Ticket: filesystem
result Open:
    ok: Ticket,
    err: int
func open_ticket(fs: Filesystem) -> Open:
    return acquire_resource[Open](fs, FixedArray[u8, 0]([]))
func ambiguous(first: Filesystem, _second: Filesystem) -> Open:
    return acquire_resource[Open](first, FixedArray[u8, 0]([]))
func main() -> int:
    return 0
```

### P4 — Scoped handles

Layer: Frontend and Core.

Codes: `E_SINGLE_OWNER_BORROW`, `E_WITH_RESOURCE`.

An open file binding belongs to its named scope. Read it or lend it as `mut` to a helper; do not store it, pass it as `own`, or return it from that scope. File owners cannot be nested in aggregate storage or callback signatures, and a record, list, variant or callback type that would hold one is refused where it is declared (the front end), whether or not a function uses it; a fallible result may carry a direct file payload. A narrowed capability (`fs.dir(path)`, `env.only(...)`) is a new handle since 5C: a `with` scope may bind one, and it needs none.

The accepted helper keeps the handle inside its scope. Its entry point does not open the file.

Accepted:

```selka
# doc: expect 0
func read_one(fs: Filesystem) -> int:
    with fs.open("sample", "rb") as file:
        return len(file.read(1))
func main() -> int:
    return 0
```

Refused:

```selka
# doc: expect-error E_WITH_RESOURCE
func escape(fs: Filesystem) -> File:
    with fs.open("sample", "rb") as file:
        return file
func main() -> int:
    return 0
```

### K1 — Lent task arguments

Layer: Frontend and Core.

Codes: `E_TASK_CAPABILITY`, `E_TASK_HOST`, `E_TASK_LOAN`, `E_TASK_MUT`, `E_TASK_RESOURCE`.

A task reads its lent arguments until the task group closes, including after its result has been read. A `const` alias lends its underlying owner for that entire time, whether the alias is declared inside or outside the group. Declare lent owners before the group or at the top level of its block, and change or move them after the group. Core checks these loan conflicts. The frontend checks argument kinds and lexical lender scope: passing `mut`, an owned resource, `Host` or any other capability (or a value that holds one) to a task is refused. Bind a managed list element before lending it. An explicit owned argument gives the task its own eligible value instead of lending the caller's value. A function declaring a borrowed result cannot be submitted (V4).

Accepted:

```selka
# doc: expect 2
import parallel
func size(values: int[]) -> int:
    return len(values)
func main() -> int:
    mut values = [1, 2]
    with parallel.group() as group:
        const job = group.submit(size, values)
        return job.result()
```

Refused:

```selka
# doc: expect-error E_TASK_LOAN
import parallel
func size(values: int[]) -> int:
    return len(values)
func main() -> int:
    mut values = [1, 2]
    with parallel.group() as group:
        const job = group.submit(size, values)
        append(mut values, 3)
        return job.result()
```

### K2 — Scoped groups and handles

Layer: Frontend.

Codes: `E_TASK_ESCAPE`, `E_TASK_GROUP`, `E_TASK_HANDLE`, `E_TASK_RESULT_UNREAD`.

Open a task group with `with parallel.group() as group`. A group and its handles stay inside that block; neither can be stored, passed or returned. A submitted task initializes a `const` handle, each handle's `result()` is read once, and every result is read before the group exits.

Accepted:

```selka
# doc: expect 6
import parallel
func twice(value: int) -> int:
    return value * 2
func main() -> int:
    with parallel.group() as group:
        const first = group.submit(twice, 1)
        const second = group.submit(twice, 2)
        return first.result() + second.result()
```

Refused:

```selka
# doc: expect-error E_TASK_RESULT_UNREAD
import parallel
func twice(value: int) -> int:
    return value * 2
func main() -> int:
    with parallel.group() as group:
        const job = group.submit(twice, 1)
        return 0
```

### K3 — Parallel map

Layer: Frontend.

Codes: `E_PARALLEL_MAP_ARGS`, `E_SLICE_ESCAPES`, `E_TASK_MUT`.

`parallel.map(values, function, ARGS)` lends its input and trailing arguments to every item call until the map returns. A slice, or a plain text, bytes or list parameter, is lent as the view itself, with no copy. Trailing `mut` or `own` arguments are refused; there are at most five trailing arguments, and a fallible function takes no trailing arguments.

Accepted:

```selka
# doc: expect 9
import parallel
func add(value: int, extra: int) -> int:
    return value + extra
func main() -> int:
    const answers = parallel.map([1, 2], add, 3)
    return answers[0] + answers[1]
```

Refused:

```selka
# doc: expect-error E_PARALLEL_MAP_ARGS
import parallel
func add(value: int, extra: int) -> int:
    return value + extra
func main() -> int:
    const extra = 3
    return parallel.map([1], add, own extra)[0]
```

### L1 — Linear Results

Layer: Frontend.

Codes: `E_EXPLICIT_DISCARD_REQUIRED`, `E_RESULT_CONSUMED`, `E_RESULT_DISCARD`, `E_RESULT_LOOP`, `E_RESULT_OPERATION`, `E_RESULT_OVERWRITE`, `E_RESULT_PATH`, `E_RESULT_PROPAGATION`, `E_RESULT_UNHANDLED`.

Handle, return, transfer or explicitly discard every pending Result before its scope ends. A pending Result cannot be overwritten, used after transfer, silently copied or implicitly discarded. Continuing paths and loop backedges must agree about its obligation. Propagation must not abandon another pending temporary. A bare Result statement requires an explicit discard and has no automatic discard repair. These obligations also apply when a Result contains an owned resource.

Accepted:

```selka
# doc: expect 7
func answer() -> int fails str:
    return 7
func main() -> int:
    match answer():
        case Ok(value):
            return value
        case Err(_):
            return 0
```

Refused:

```selka
# doc: expect-error E_RESULT_UNHANDLED
func answer() -> int fails str:
    return 7
func main() -> int:
    const pending = answer()
    return 0
```

## Appendix: accepted behaviour and retired restrictions

These entries describe accepted behaviour or a restriction the language no longer has. Nine
of them (T1, B4, B5, W1, V1, V7, P5, Z1, Z2) have `Codes: none` and no refusal of their own.
C2 is about contracts (`old(...)` in `@ensures`), not about lending, so it is filed here
although it keeps its code, `E_CONTRACT_OLD_SHARED`. Every entry keeps its id, and the rules
above and other pages still link to them.

### T1 — Managed types

Layer: Frontend.

Codes: none.

A managed type owns storage: text, bytes, a collection, a resource, an owning provider,
or an aggregate containing managed storage. Other values are scalar and copy on use.
Moving a managed aggregate transfers the storage inside it too.

```selka
# doc: expect 42
func main() -> int:
    const count = 21
    const duplicate = count
    const values = [count, duplicate]
    const transferred = own values
    return transferred[0] + transferred[1]
```

### B4 — Reinitialization

Layer: Core.

Codes: none.

Assigning a whole new value to a `mut` binding makes it available again after a move.
Updating one field of an unavailable record does not reinitialize the whole record.

```selka
# doc: expect 42
func main() -> int:
    mut source = [1]
    const destination = own source
    source = [41]
    return destination[0] + source[0]
```

### B5 — Joins

Layer: Core.

Codes: none.

After an `if` or `match`, a binding is available only if it is available on every path
that continues. Returning paths do not participate in the join. Different move states
are allowed when the binding is never used afterward; a later unavailable use is B3.

```selka
# doc: expect 5
func choose(take: bool) -> int:
    mut value = [1]
    if take:
        const taken = own value
        assert taken[0] == 1
        value = [2]
    else:
        value = [3]
    return value[0]
func main() -> int:
    return choose(True) + choose(False)
```

### W1 — Taking parameters

Layer: Core.

Codes: none.

An `own` parameter takes ownership of its argument. After a named argument transfers,
the caller’s binding is unavailable (B3). The callee may change, store, transfer or
return the value; otherwise Core destroys it after its final use. Rebinding and
constructor children follow B2, and exact bare-local returns and failures keep their
marker exemption. This operational rule has no separate refusal code.

```selka
# doc: expect 42
func finish(own values: int[]) -> int[]:
    append(mut values, 40)
    return values
func main() -> int:
    const values = [2]
    const kept = finish(own values)
    return kept[0] + kept[1]
```

### V1 — Slices are views

Layer: Core.

Codes: none.

A text, bytes or list slice used as a read-only view borrows its source through its
final use. Creating the view allocates no independent storage. Views may be read in
place; storage, invalidation and return restrictions belong to V2–V4. This
representation rule has no separate refusal code.

```selka
# doc: expect 6
func main() -> int:
    const text = "abcd"
    const octets = b"abcd"
    const values = [10, 20, 30, 40]
    const letters = text[1:3]
    const bytes_part = octets[1:3]
    const middle = values[1:3]
    return len(letters) + len(bytes_part) + len(middle)
```

### V7 — View operations

Layer: Core.

Codes: none.

Ordinary slice views support their underlying type’s read operations: slicing, indexing,
`len`, comparison, printing and explicit copying where that operation exists for the
type. Plain helper arguments read views without acquiring their storage. Views remain
read-only under the ordinary borrow and mutation rules. The removed `TextView` and
`ByteView` types impose no separate operator, byte-printing or signature restrictions,
and their old refusal codes are retired.

```selka
# doc: expect bc b'bc' 2 20 True 2
func width(text: str) -> int:
    return len(text)
func main(out: Stream) -> int:
    const text = "abcd"
    const raw = b"abcd"
    const values = [10, 20, 30, 40]
    const part = text[1:3]
    const octets = raw[1:3]
    const middle = values[1:3]
    print(out, part, octets, len(middle), middle[0], part == "bc", width(part))
    return 0
```

### P5 — Retired provider contexts

Layer: Core.

Codes: none.

A flat local context assembled from borrowed provider parameters was once the only record a borrowed capability could
form, and it was read-only. Capabilities are shareable handles since 5C, so a record of capabilities is an ordinary
value: it may be returned, stored, copied and passed `mut`, and an optional capability is an ordinary option.

Accepted:

```selka
# doc: expect 1
record Services:
    clock: Clock
    label: int
func inspect(clock: Clock) -> Services:
    const services = Services(clock=clock, label=1)
    return services
func main(clock: Clock) -> int:
    mut services = inspect(clock)
    const twin = copy(services)
    services.label = services.label + twin.label
    return services.label - twin.label
```

### C2 — Old captures

Layer: Frontend.

Codes: `E_CONTRACT_OLD_COPY`, `E_CONTRACT_OLD_SHARED`.

`old(expression)` in an `@ensures` clause captures its entry value. A managed value is captured by a copy made at every call, and that copy is written: `old(copy(values))`. A bare `old(values)` of a managed value is refused with `E_CONTRACT_OLD_COPY`, and `selka fix` writes the `copy(...)`. A scalar projection, `old(len(values))`, copies nothing. Capture a copyable value or a scalar projection rather than a whole resource-bearing aggregate with writable storage that cannot be independently copied.

Accepted:

```selka
# doc: expect 2
@ensures(len(values) == len(old(copy(values))) + 1)
func push(mut values: int[]):
    append(mut values, 2)
func main() -> int:
    mut values = [1]
    push(mut values)
    return len(values)
```

Refused, because the copy of `values` is not written:

```selka
# doc: expect-error E_CONTRACT_OLD_COPY
@ensures(len(values) == len(old(values)) + 1)
func push(mut values: int[]):
    append(mut values, 2)
func main() -> int:
    mut values = [1]
    push(mut values)
    return len(values)
```

Refused, because a resource cannot be copied:

```selka
# doc: expect-error E_CONTRACT_OLD_SHARED
resource Ticket: filesystem
record State:
    ticket: Ticket
    values: int[]
@ensures(len(old(state).values) >= 0)
func size(own state: State) -> int:
    return len(state.values)
func main() -> int:
    return 0
```

### Z1 — Evaluation temporaries

Layer: Core.

Codes: none.

The former argument-evaluation restriction is lifted. Arguments are evaluated left to right in source order, including named arguments whose order differs from the parameter declaration. Lowering retains the necessary evaluation temporaries for direct and callback calls. No ownership refusal remains for needing those temporaries; `E_SINGLE_OWNER_UNSUPPORTED` is retired.

Here `right` is evaluated first, so the recorded order is `[2, 1]`, while the named values still produce `12`.

Accepted:

```selka
# doc: expect 1212
func mark(mut seen: int[], value: int) -> int:
    append(mut seen, value)
    return value
func pair(named left: int, named right: int) -> int:
    return left * 10 + right
func main() -> int:
    mut seen: int[] = []
    const answer = pair(right=mark(mut seen, 2), left=mark(mut seen, 1))
    return answer + seen[0] * 100 + seen[1] * 1000
```

### Z2 — Retired analysis budget

Layer: Core.

Codes: none.

The former whole-program ownership-analysis budget is retired. Mutation and borrowed-result summaries come from declared `mut` and `from` signatures, without a whole-program origin fixed point or its budget. Calls use those declarations even through a chain of helpers.

Accepted:

```selka
# doc: expect 1
func first(values: int[]) -> int[] from values:
    return values
func second(values: int[]) -> int[] from values:
    return first(values)
func main() -> int:
    const values = [4]
    return len(second(values))
```

## Refusal codes mapped to rules

A code may enforce several rules; an individual ownership diagnostic identifies the
one that caused its refusal. `E_CORE_UNSUPPORTED` is also used for ordinary backend
limits and invalid internal shapes. Those non-ownership instances carry no ownership
rule; its ownership limits carry Z3.

| Code | Rules |
| --- | --- |
| `E_BORROW_MIXED` | R5 |
| `E_BORROW_SOURCE` | R4 |
| `E_BORROW_UNDECLARED` | R4 |
| `E_CELL_ELEMENT` | T3 |
| `E_CONTRACT_OLD_COPY` | C2 |
| `E_CONTRACT_OLD_SHARED` | C2 |
| `E_CORE_HIDDEN_COPY` | C1 |
| `E_CORE_UNSUPPORTED` | Z3 |
| `E_DICT_TYPE` | T4 |
| `E_EXPLICIT_DISCARD_REQUIRED` | L1 |
| `E_IMMUTABLE` | B1 |
| `E_LIST_ELEMENT` | T4 |
| `E_LIST_TYPE` | T2, T4 |
| `E_LITERAL_ARM` | C1 |
| `E_LIVE_VIEW_CYCLE` | V6 |
| `E_MATCH_MUT` | X2 |
| `E_MUTATION_MARKER` | M2, M3 |
| `E_MUTATION_PERMISSION` | M2 |
| `E_NOALLOC_ALLOCATES` | C3 |
| `E_OWN_MARKER` | B2, B9, W2 |
| `E_OWN_PARAMETER` | T2, W3 |
| `E_PARALLEL_MAP_ARGS` | K3 |
| `E_RECURSIVE_RECORD` | T4 |
| `E_RESOURCE_ESCAPE` | P2, P3 |
| `E_RESOURCE_ORIGIN` | P1, P3 |
| `E_RESULT_CONSUMED` | L1 |
| `E_RESULT_DISCARD` | L1 |
| `E_RESULT_LOOP` | L1 |
| `E_RESULT_OPERATION` | T2, L1 |
| `E_RESULT_OVERWRITE` | L1 |
| `E_RESULT_PATH` | L1 |
| `E_RESULT_PROPAGATION` | L1 |
| `E_RESULT_UNHANDLED` | L1 |
| `E_SET_ELEMENT` | T4 |
| `E_SINGLE_OWNER_BORROW` | B7, B8, B9, R1, R3, R4, R6, M1, M4, X2, P4 |
| `E_SINGLE_OWNER_LOOP` | B6 |
| `E_SINGLE_OWNER_MOVED` | B3 |
| `E_SINGLE_OWNER_OVERLAP` | R2, R7, M5, M6, X1, X2 |
| `E_SLICE_ESCAPES` | V2, V3, V4, V5, W4, K3 |
| `E_TASK_CAPABILITY` | K1 |
| `E_TASK_ESCAPE` | K2 |
| `E_TASK_GROUP` | K2 |
| `E_TASK_HANDLE` | K2 |
| `E_TASK_HOST` | K1 |
| `E_TASK_LOAN` | K1 |
| `E_TASK_MUT` | K1, K3 |
| `E_TASK_RESOURCE` | K1 |
| `E_TASK_RESULT_UNREAD` | K2 |
| `E_TEXT_IMMUTABLE` | T4 |
| `E_VALUE_BINDING_WRITE` | R7 |
| `E_VALUE_CELL` | T3 |
| `E_VALUE_CLASS` | T3 |
| `E_VALUE_TEMPORARY_WRITE` | M4 |
| `E_VIEW_FUNCTION_VALUE` | V4 |
| `E_VIEW_STORED` | V6 |
| `E_WITH_RESOURCE` | P4 |

## History and migration

The 24 October draft (`docs/design/ownership-rules-2026-10-24.md`) records the previous
compiler. This reference includes the decisions and implementations from the
ownership plan (`docs/audits/ownership-rules-plan-2026-10-24.md`). `selka fix` supplies
certain `from` and `own` migrations; [the fix guide](tooling/fix.md) describes the
review and application workflow.

| Previous code or machinery | Current disposition |
| --- | --- |
| `E_ZERO_RC_RESOURCE_ESCAPE` | Renamed `E_RESOURCE_ESCAPE` (P2, P3). |
| `E_ZERO_RC_RESOURCE_ORIGIN` | Renamed `E_RESOURCE_ORIGIN` (P1, P3). |
| `E_ZERO_RC_UNSUPPORTED` | Retired. Real rules use `E_WITH_RESOURCE`, `E_OWN_PARAMETER` or `E_RESOURCE_ORIGIN`; malformed typed programs use compiler-defect diagnostics. |
| `E_ZERO_RC_VIEW_SIGNATURE`, `E_ZERO_RC_VIEW_UNSUPPORTED`, `E_ZERO_RC_VIEW_INVALIDATED` | Retired with unreachable typed-view paths. Source spellings `TextView` and `ByteView` remain retired under `E_BORROW_VIEWS_REMOVED`; ordinary slices obey V1–V7. |
| `E_OWNED_CONSUMED`, `E_OWNED_LOOP`, `E_OWNED_PATH` | Retired frontend move checks. Core implements B3, B5 and B6; pending Results retain L1's separate codes. |
| `E_MUTATION_OVERLAP` | Retired duplicate overlap analysis. Core place-path rules use `E_SINGLE_OWNER_OVERLAP`. |
| `E_MUTATION_LIMIT` | Retired whole-program mutation-summary budget. Mutation and borrow summaries come from signatures. |
| `E_OWN_ARGUMENT` | Replaced by `E_OWN_MARKER` for missing or misplaced moves in all positions. |
| `E_SINGLE_OWNER_UNSUPPORTED` | Retired unused argument-evaluation representation; Core binds ordered operands directly (Z1). |
| Inferred result borrows and `inferred.view_source` | Replaced by declared `from` sources, checked with `E_BORROW_SOURCE`, `E_BORROW_UNDECLARED` and `E_BORROW_MIXED`. Migration advice derives missing parameter roots while checking returns; the separate inference pass is removed. |

The former borrowed-result owner-count limits and field-carrier sibling and
straight-line limits are lifted. Dictionary-element mutable matching retains X2's
limit because dictionary element exchange was absent when this package began.
The runtime `R_LIST_ITERATION_MUTATION` trap remains as a backstop; ordinary checked
dynamic-collection iteration is protected by R7's loans.
