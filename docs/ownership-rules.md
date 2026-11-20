# Ownership rules

Every ownership refusal names the rule it enforces, in terminal output and in the `rule` field of `diagnostic-v1` JSON.
`selka reference --query CODE` lists the rules behind a code. The [memory guide](managed-memory.md) introduces the model;
this page states the 54 rules, each with a runnable example.

## The model

Every use of a managed value (text, bytes, a collection, or a record that holds one) is one of four verbs:

| Verb | In an expression | In a signature |
| --- | --- | --- |
| lend | the bare name: `size(values)` | a plain parameter; a result under `from values` |
| lend for writing | `mut name`: `append(mut values, 3)` | a `mut` parameter |
| give | `own name`: `keep(own values)` | an `own` parameter; a result without `from` |
| duplicate | `copy(name)`: `mut next = copy(values)` | none: the copy is fresh |

Three rules say what they may do. **Escape**: a lent value cannot be stored or given anywhere that outlives its lender.
**Exclusion**: a lender cannot change or be given away while something it lent is in use, and a loan for writing is the
only loan. **Gone**: after `own`, the name cannot be used until it is assigned again.

A value built from lent parts is itself lent: a record of borrowed places (B9), a slice (V1), a result under `from` (R3). A named managed value moves only with `own`, except a bare return or fail. Resources, task groups and pending Results apply the same rules ([Applications](#applications)).

All four verbs in one program:

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

A first program meets each rule as a refusal: Escape, Exclusion, Gone.

```selka
# doc: expect-error E_SINGLE_OWNER_BORROW
func retain(values: int[]) -> int:
    mut retained = own values
    return len(retained)
func main() -> int:
    return retain([1, 2])
```

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
func main() -> int:
    mut values = [1]
    const alias = values
    append(mut values, 2)
    return len(alias)
```

```selka
# doc: expect-error E_SINGLE_OWNER_MOVED
func main() -> int:
    const values = [1]
    const kept = own values
    return len(kept) + len(values)
```

Repair Escape with `copy(name)`, or `own name` when the owner can give the value; a plain parameter can only be copied.

## Keeping pieces of a buffer

How long a piece of a buffer must live, compared with the buffer, picks the form; `copy` is the last. The example is a tar-style header in a `bytes` block: name in octets 0 to 7 (NUL padded), size in
8 to 11 (decimal), kind in 12, link in 13 to 20.

**1. Use it and let it go.** Bind a slice to a local, compare it, loop over it, pass it to a plain parameter: no `copy`, no
marker. The buffer cannot change while the view is read later (`E_SLICE_ESCAPES`, V3).

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

Gathering slices into a record is refused:

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

To share where the pieces are, use a local record of borrows ([B9](#b9--const-place-bindings-borrow)): pass it, list it
locally, but do not return it, store it in a `mut` parameter or give it with `own` (`E_OWN_MARKER`; `copy(block)` makes it
an owner). Over a plain `bytes` parameter it copies the block once per call, and `--stats` counts it.

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

**2. Return one piece.** `-> bytes from block` returns a view of the argument and copies nothing. The caller may read it,
pass it on, return it under its own `from` and keep several. Storing it in a record or list is `E_SLICE_ESCAPES`, returning
it without `from` is `E_BORROW_UNDECLARED`, giving it with `own` is `E_SINGLE_OWNER_BORROW`, and changing the block while
the view is read later is `E_SINGLE_OWNER_OVERLAP`. A `from` function returns views or a literal such as `""`, never a
computed value (`E_BORROW_MIXED`). Copying a slice of a parameter on every return gets `W_COPY_MOVE`.

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

**3. Keep where it is.** A [`spans.Span`](standard-library.md#spans) is three integers (file, start, length), so records of
spans are stored and returned with no copy of the text. The text lives in an add-only `spans.Sources` table, and
`spans.text(sources, span)` reads it back as a view `from sources`. A span outside the table traps.

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

**4. Keep it for good.** Give it away: a move copies nothing. `strings.decode` returns a `str` the function owns; store it
with `Header(name=own name)`, an `own` parameter, `take(mut header.name)`, or `for part in own parts:` with
`append(mut kept, own part)`. A name that repeats is kept once: `symbols.intern` returns a one-integer `Symbol` and copies the text only the first time (`L_COPY_IN_LOOP` points here).
`E_OWN_MARKER` says write `own name`; `E_SINGLE_OWNER_BORROW` says the parameter lends the value, so declare it `own` if
callers are finished with it, else `copy`.

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

**5. Copy last.** `copy(x)` is one allocation of the piece, not of the block. A copy that carries nothing is
`W_NEEDLESS_COPY`, which names the edit that deletes it (`selka fix FILE --warnings`; `selka lint` says `L_NEEDLESS_COPY`).

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

## How the reference is organised

The 54 rules (T1 to Z3) keep the ids that diagnostics and `selka reference` name. Each is filed under one heading below, in the order T, B, R, M, W, V, X, P, K, L, C, Z.

## Checking layers

Core decides move, loan, place-overlap and lifetime predicates for each checked function instance; the frontend decides
type and source-mode predicates. Frontend rules (B1 included)
check every generic body even if it is never called; Core rules check concrete instances, so an uncalled template has no
Core ownership proof. `# doc: build` marks a refusal found during native lowering after a successful check.

## Proof coverage

A Debug compiler checks the final Core IR of every function with the ownership validator, and a Lean proof shows that a function passing the same checks never faults. It covers the run-time property a rule protects, not whether the source
checker enforces the rule. Of the 54 rules, 36 are safety rules the proof covers, 12 are clarity rules and 6 are type rules
the model takes as given ([ownership certificates](https://github.com/eugenepentland/selka/blob/main/docs/tooling/ownership-certificates.md)).

## Rule 1: Escape

A lent value cannot be stored or given anywhere that outlives its lender.

A plain parameter, a `const` alias of a place, a loop variable, a field or element read, a slice and the result of a `from`
call are all lent. Storing one in an owning local, record, list or dictionary, passing it as `own`, or returning it past its
lender is refused under `E_OWN_MARKER` (B2, B9, W2), `E_SINGLE_OWNER_BORROW` (B7, B9, R1, R3, R4, R6, M1),
`E_SLICE_ESCAPES` (V2, V4, V5, W4) or `E_BORROW_UNDECLARED` (R4). Each refusal names what is lent, who lends it and the repairs `selka fix` makes
([fix](tooling/fix.md)): `own NAME` where the lender can give the value, `copy(NAME)` to keep both, `from` at a return.

```text
retain.selka:2:20: error[E_SINGLE_OWNER_BORROW]: `own values` cannot give the plain parameter `values`, which only lends it, and the `mut` local `retained` needs its own value; write `copy(values)` to keep both
```

A written `own` that takes nothing is refused too:

```text
read.selka:5:17: error[E_OWN_MARKER]: `own values` gives `values`, but this argument is only read; remove `own`
```

### B2 — Moves

Layer: Core.

Codes: `E_OWN_MARKER`.

Write `own` when a named managed value moves into a binding, assignment, constructor, container or owning argument; the
source becomes unavailable. A bare `return value` or `fail value` needs none (`return own value` is refused), but a
returned constructor still marks its named inputs. Returning a managed field needs `own record.field`, which consumes the
record (B8). Scalars and fresh call, literal, operator or `copy(...)` results need no marker. `own` is a marker only when
an identifier follows it on the same line; write a grouped move as `(own value)`.

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

### B7 — No moving out of a container

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

Reading a managed element or dictionary value borrows it, so it cannot initialize owning storage: read it in place, bind a
borrowed `const`, write `copy(...)`, or extract it with `pop`, `exchange` or `take`. An option narrowed to `Some` by
`if x is None: return` gives its payload with `own x` (B9). An element of a new list (a literal, or a call result not
declared `from`) moves out where a value is taken: `strings.split(text, sep)[1]` drops the rest of the list.

```selka
# doc: expect 3
import strings
func main() -> int:
    const middle = strings.split("a,bbb,c", ",")[1]
    return len(middle)
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

`const alias = place` borrows any managed place read-only (a local, an `own` parameter, a field, an element) until the
alias's last use. An owning store, owned return or `mut`/`own` argument cannot take it: write `const alias = own owner` or
`copy(place)`.

A `mut` local whose every assignment reads a place without `own` borrows the same way (`mut net = port.name`, then
`net = port.net` in an `if`). Writing through it is refused at the write, naming `mut net = own place` and
`mut net = copy(place)`; it cannot be moved or stored, and is returned only under `from`.

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

After `if x is None: return` (or `fail`, `break`, `continue`), `x` reads as its payload in place, and where the function
owns `x`, `own x` moves the payload out and consumes `x`. A plain or `mut` parameter, a loop variable and a `match` binding
only lend: `own x` of one is refused (B2) and `selka fix` writes `copy(x)`.

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

A record constructor whose managed fields all read places without `own` is a borrowed value: `RailSpot(net=b.power, x=1)`
copies nothing. It may be a read-only argument, a `const`, a `mut` local whose assignments all borrow, or a `from` result.
Storing it in a list, dictionary, owned field or `mut` parameter, moving it, returning it without `from`, passing it to a
task, changing an owner while it lives, or mixing a borrow with a fresh value is refused, with the repair on the field.

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

A borrowed record may hold `None` and `Some(p)` of a read-only record parameter, so a recursive walk passes context down with
no copy (`walk(Scope(block=sb.block, parent=Some(scope)))`). A value holding a recursive field's box cannot be returned, even
under `from`, unless the box is an ancestor's (`bridged(self)` below). `Some(...)` of a record built in place or of a local
keeps its copy.

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

A local list or dictionary whose every element store is a borrow owns its buffer, lends its elements and holds what they
borrow until its last use. A `mut` local made empty (`[]`, `{}`) whose `append`, `xs[i] = v` or `d[k] = v` stores borrows
qualifies, as does a list literal of such values. Refused: changing a source while it lives; moving, storing, returning or
passing it `mut` or to a task; an element mixing a borrow with a fresh value; a set. The refusal lands on an earlier
`append`, with a `cause` note at the later line. `selka dump-typed FILE.selka` shows what each local is.

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

### R1 — Plain parameters borrow

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

A plain managed parameter borrows its argument read-only; the callee cannot move it into owning storage. Use `copy`, `own`
in the declaration, or a `from` result. A record built from a plain text, bytes or list parameter holds a frame block
([B9](#b9--const-place-bindings-borrow)): storing it past the call needs `copy(...)` of the field.

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

### R3 — Borrowed call results

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

A call with a `from` result borrows every corresponding argument owner; callers use the signature, not the body. Read the
result in place, bind it with `const`, or return it under R4; storing it or passing it `mut`/`own` needs a copy. A fallible result is the same: `match` reads the `Ok` payload in place, `const part = try call(...)`
borrows, `return try call(...)` forwards under the same `from`, and a `mut` argument `from` does not name is written back,
not borrowed. Store the success with `mut kept = try copy(call(...))` or `copy(part)` (`selka fix` adds it).

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

### R4 — Borrowed returns

Layer: Core.

Codes: `E_BORROW_SOURCE`, `E_BORROW_UNDECLARED`, `E_SINGLE_OWNER_BORROW`.

`-> T from a, b` declares a read-only result borrowed from the named plain or `mut` managed parameters, any number. Every
value return must refer to them, optionally through `Some` or a `fails` success (slices: V4). Write `from` before `fails`;
function types cannot declare it. `E_BORROW_UNDECLARED` marks the first return using an undeclared source;
`E_BORROW_SOURCE` an unknown or ineligible source, a duplicate (the fix removes it), or a clause no source can satisfy (the
fix removes it). A source lends only storage it holds: a plain text or bytes parameter is a view that lends only its own
kind.

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

### R6 — Borrowed selections

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

A managed selection borrows its selected input, and every possible input owner stays held while it is live: dictionary
lookups with a default, optional defaults, text `min`/`max`. Read it in place, or copy before storing, moving or changing
it. A literal default (`b""`, `"none"`, a number, `None`, `[]`) has no owner, so `r.name.unwrap_or(b"")` and
`dicts.get(d, key, "")` borrow only their option or dictionary, and a `from r` accessor can return them.
`options.take_or(own value, own default)` takes an owned option's payload, or the default, without a copy.

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

A `mut` parameter exclusively borrows its caller's storage: the callee may read, change or replace it, but not take it into
owning storage. A resource that must transfer belongs in an `own` parameter.

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

Write `own` when a named managed place transfers into an owning argument; fresh calls, literals, copies and scalars need no
marker. The frontend checks that `mut`, `own` or plain spelling matches the called mode, Core that the source may move. B2
covers transfers outside calls.

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

A slice borrows its source, so an `own` parameter cannot take it, even through a named slice binding. Pass `copy(slice)`, or
make the parameter plain; `selka fix` writes the copy.

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

### V2 — Views are never stored

Layer: Core.

Codes: `E_SLICE_ESCAPES`.

A borrowed slice cannot enter an owning local, record, list or dictionary; `const` or `own` does not make it independent.
Use `copy`; for a bound slice the repair puts the copy at its initializer.

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

A slice may return as a borrow only under a `from` signature naming its source parameters (plain or `mut`, any number;
`Some` and a `fails` success allowed). A local source needs `copy`. A function with a borrowed result cannot be a function
value: wrap it in one that returns a copy.

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

Slice views of one source can merge across branches. Joining slices of different sources makes the binding unavailable:
copy at each branch initialization when the result must own its storage.

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

Dictionary `keys`, `values` and `items` are ephemeral views: use them as iteration sources or with `len`, membership,
`list`, `set` or `sorted`. Binding, storing, returning or passing one to a user function is `E_VIEW_STORED`; `list(...)`
makes a snapshot. A recursive stored type cannot hide a live view cycle (`E_LIVE_VIEW_CYCLE`).

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

Write an independent copy as `copy(value)`, or use a conversion whose contract creates one; a move, borrow or read never
clones silently. Matching a projected text or bytes field against literals needs a hidden copy (`E_LITERAL_ARM`): bind an
explicit copy first. Core also verifies its lowered copies (`E_CORE_HIDDEN_COPY`).

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

A lender cannot change or be given away while something it lent is in use, and a loan for writing is the only loan.

A loan lasts from the line that makes it to its last use and holds the place it names, not the whole owner (R2). Changing or moving the lender meanwhile is `E_SINGLE_OWNER_OVERLAP` (R2, R7, X1, M5, M6), or `E_SLICE_ESCAPES` for a slice (V3). Writing needs a `mut` binding or parameter (B1, M2), a call that spells `mut name` (M3) and an owner or exclusive loan as the target (M4).

### T3 — No shared mutable identity

Layer: Frontend.

Codes: `E_CELL_ELEMENT`, `E_VALUE_CELL`, `E_VALUE_CLASS`.

`class` and builtin `Cell` are refused. Use records for values, and explicit ids or pool handles for identity.

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

`mut` makes a binding writable; assigning to a `const` is refused. Parameter writes also need M2's modes, and iteration
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

While a read loan is live, its owner and overlapping places cannot move or change. Loans arise from arguments, borrowed
constants, matches, iteration and expression evaluation, and end at the last use. `copy(alias)` is a read like any other:
take the snapshot before the owner changes. F-string holes evaluate left to right like arguments, so an earlier managed hole
stays borrowed through later holes.

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

A `const` holds the place it names, not its whole owner: `const item = self.items[i]` holds `self.items`, so writing another
field of `self` (`self.links`, `self.count`, `self.inner.n`) is allowed while `item` is live. Writing the borrowed field, the
whole record, an element of the borrowed list or anything inside it overlaps, and so does passing the record `mut`. Two
elements of one list are never told apart. Only a direct `const` binding of a place is read this way; a binding of a
binding, a slice, an iteration binding and a borrowed call result hold the whole owner.

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

### R7 — Iteration

Layer: Frontend and Core.

Codes: `E_SINGLE_OWNER_OVERLAP`, `E_VALUE_BINDING_WRITE`.

Iteration bindings are read-only. Core refuses changes to a dynamically sized collection held by its iteration loan,
same-length element replacement included; direct fixed-array iteration allows them. The loan is on the place iterated:
`for root in tree.roots` borrows `tree.roots`, so a sibling path may change in the body, while the iterated field, a prefix
of it and anything inside it stay borrowed. A call that takes the owner `mut` is refused with the repair: walk by position and copy the element read each
time (`copy(st.names[k])`).

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

### M2 — Declared mutation

Layer: Frontend.

Codes: `E_MUTATION_MARKER`, `E_MUTATION_PERMISSION`.

Writes to caller storage need parameters declared `mut`; writes to an `own` parameter affect only the callee. Mutable record
and fixed-array parameters need copyable contents without pending Results. A write whose possible targets exceed the
declared set is refused.

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

Pass a writable argument as `mut place` exactly where the signature declares `mut`; missing and extra markers are refused,
and the marked expression must name an assignable place. Collection and text operations follow the same rule.

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

A mutation needs a writable owning local, an owned parameter or an exclusive `mut` borrow. Writing into a value a call
returns is `E_VALUE_TEMPORARY_WRITE`: bind the result to a `mut` local first.

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

An exclusive `mut` argument must be disjoint from the other arguments whose borrows stay live in that call. Scalar reads
finish before the call mutates; arguments still evaluate left to right.

| Disjoint | Not shown disjoint |
| --- | --- |
| different record fields | a field inside an element (`rows[0].tags`) |
| different literal list indices after any equal field prefix (`tree.nodes[0]`, `tree.nodes[1]`) | dynamic or equal indices, overlapping prefixes |

A read argument that makes a value of its own (an operator's result, a format string, `copy(...)`) finishes before the call,
so it may read a record another argument passes `mut` (`emit(mut work, "x" + target(work))`). The diagnostic names both
arguments and the remedies: copy the read element first, pass a value of its own (`copy(state.stack)`), or pass the
container `mut` and index inside the callee. For separate writable storage, `mut part = copy(a[0])`, then `a[0] = own part`
after the call. There is no automatic fix.

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

### M6 — No self-source

Layer: Core.

Codes: `E_SINGLE_OWNER_OVERLAP`.

Writing a byte buffer from its own borrowed octets is refused; `bytes(buffer)` supplies a snapshot. List extension refuses
an overlapping ancestor or ambiguous borrowed source; same-depth list self-extension is supported.

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

A source must stay available and unchanged while a slice view still needs it: moving, changing or replacing a live source is
refused, and the view's last read releases it. The refusal names the write, call or move, and offers repairs in the order
that copies nothing first: read the view earlier, keep the span and slice again after the write, copy the binding last.

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

Matching a named, non-affine value or projected place borrows its payload until the arm's last use of a payload binding; a
conflicting move or change is refused. Matching a fresh owned call, constructor or `copy` consumes it and transfers the
payload, as does `match own name` of an owned local or `own` parameter, whose payload bindings then own their values. A
borrowed or `mut` parameter, a borrowed local and a field or element place cannot be consumed this way. A `from` call still borrows (R3).

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

A `match mut` scrutinee names a writable local, record field or supported list element. Its payload bindings write through
to that place and cannot move or escape into owning storage. A dictionary element cannot be the place (`E_MATCH_MUT`): match
it read-only and assign the whole updated value back.

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

A moved name cannot be read, written through or moved again (B3), at every loop back edge too (B6). Assigning a whole new value makes it available again (B4); after an `if` or `match` it is available only if every continuing path left it so (B5), both in the [appendix](#appendix-accepted-behaviour-and-retired-restrictions).

### B3 — Use after move

Layer: Core.

Codes: `E_SINGLE_OWNER_MOVED`.

A moved binding cannot be read, written through or moved again. Reinitialize a writable whole binding (B4), or take `copy`
before transferring. A later argument of the same call that only reads a number or `bool` from the value (`len(x)`) or is a
literal needs no copy: write the read first, `Source(total=len(plain), mem=own plain)`, and it reads before it moves. `selka fix` writes that form where it applies.

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

An owner available when a loop starts must stay available at every back edge, `break` and `continue`: a move in a continuing
iteration needs whole-binding reinitialization before that edge.

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

Core destroys each owned value after its last use on every path, early returns and checked propagation included.
`@noalloc` is checked against lowered ownership operations, required copies and cleanup included, so returning a fresh
collection from a `@noalloc` function fails the build-time contract.

```selka
# doc: expect 2
@noalloc
func size(values: int[]) -> int:
    return len(values)
func main() -> int:
    const values = [1, 2]
    return size(values)
```

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

These refusals come from what the checker can do, not from the model. R5, B8 and Z3 are rules below.

| Limit | Until then |
| --- | --- |
| R5: a `from` function returns only borrows (and static empties), `E_BORROW_MIXED` | copy the borrowed returns and remove `from` |
| B8: no partial record moves across statements | move the fields in one statement (`total(own p.lo, own p.hi)`), or `copy(record.field)` |
| a view (a slice or `from` call result) stored in a local record, list, dictionary or option, `E_SLICE_ESCAPES` | `copy(...)`; a field read directly, or a slice in a `mut` local (B9), is accepted |
| X2: a mutable match on a dictionary element, `E_MATCH_MUT` | match it read-only, assign the updated value back |
| Z3: a shape `check` accepts and `build` cannot place, `E_CORE_UNSUPPORTED` | see Z3 |

### B8 — No partial record moves

Layer: Core.

Codes: `E_SINGLE_OWNER_BORROW`.

`own record.field` consumes the whole record: it becomes unavailable and its other fields are destroyed there. A record that
stays usable supplies a field by a read borrow or `copy`; a field of a borrowed record cannot be taken. One statement may
move several fields of one owned record, each once: `total(own p.lo, own p.hi)`. Moves in a branch, another statement, the
right operand of `and`/`or` or inside another operation count separately, and the record is gone by then. A field of a
`match` binding or of a plain or `mut` parameter is lent, never moved. `selka fix` joins two `const` moves into the next
statement's call when that is their only use.

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

A `from` function cannot return a fresh owned value on another path. `None`, literals that add no owned storage and the
empty list literal `[]` (static; `[1]` or a named list is new storage) are compatible. Failure payloads keep ordinary
ownership. To make the function owning, copy its borrowed returns and remove the clause.

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

Some lowering and scheduling shapes remain build-time limits. A build reports `E_CORE_UNSUPPORTED` with rule Z3 when it
cannot place a required ownership operation although `check` succeeded: a gap in the scheduler, not a rule. Other ABI, type
or backend limits use the same code without a rule. The refusal names the statement and the conflicting place:

```text
main.selka:12:5: error[E_CORE_UNSUPPORTED]: the ownership pass cannot schedule a call in child (inlined into main): it takes ownership of `ctx.block.rules` (line 12), which is a borrowed part of `ctx` at that point, not an owner; this shape has no safe destruction schedule
  note: ownership rule Z3
  note: main.selka:12:27: `ctx.block.rules` is read here as a borrow of `ctx`
```

`check` itself reports one limit: a function that `fails` with a managed error type (such as `str`) cannot return a borrow of
its `mut` parameter. Use a copy without `from`, a scalar error, or split the update from the read. To lend a slice of bytes
to a task, bind an explicit owned copy first.

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

Resources, task groups and pending Results follow the three rules. A **resource** cannot be duplicated, so `copy` does not apply: T2, T4 and W3 say how parameters, containers and function types spell it, and P1 to P4 where it comes from and how long it lives (a `with` scope lends it to its body, so it cannot leave). A **task group** is a scope that borrows (K1 to K3). A **pending Result** must be consumed (L1).

### T2 — Move-only types

Layer: Frontend.

Codes: `E_LIST_TYPE`, `E_OWN_PARAMETER`, `E_RESULT_OPERATION`.

Resources and the records that hold them are move-only: `copy` cannot duplicate them. A parameter that takes one must say
`own`; an exclusive loan says `mut`. A capability is a shareable handle, copied like an integer, so it is not move-only.

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

Lists, dictionaries and sets cannot hide resource owners: lists may carry pending Results (L1 still applies), other
containers need copyable elements, and recursive boxed values cannot contain resources or pending Results. A capability is a
scalar handle, so any container may hold one. Text and bytes are immutable (`E_TEXT_IMMUTABLE`).

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

Function types keep each parameter's plain, `mut` or `own` mode. A move-only parameter position must say `own`, also inside
a record field or another callable type; a plain one is refused at its declaration.

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

Acquire a resource from a provider held by a named binding, and open a dependent scope directly from that provider or a
named record that holds it. A resource carrier has one provider origin; it cannot combine providers.

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

A resource, or a Result or record that contains one, cannot outlive the `with` scope it was opened in: consume it before the
scope ends. A capability provider lives until the process ends, so rebinding the variable that names it while a dependent
resource is live is accepted.

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

A function returning a resource has exactly one input the result can come from: its origin. The result must depend on it,
also inside a Result or carrier record; a local provider cannot supply an escaping resource, and two possible origins are
ambiguous. The inputs counted are resource parameters and a provider of the result's kind (a `Filesystem` for a file, a
`Network` for a `network` resource); `Clock`, `Entropy`, `Environment`, `Process`, `Stream`, `Input` and `Stop` are not. A
count other than one is `E_RESOURCE_ORIGIN` at the function's name, listing the counted inputs: keep the one the result
comes from, and put work needing the others in a function returning a `bool` or `int`. A body that drops the origin and
returns a resource made from another input is `E_RESOURCE_ESCAPE`.

```selka
# doc: expect 0
resource Ticket: filesystem
func forward(own token: Ticket) -> Ticket:
    return token
func main() -> int:
    return 0
```

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

An open file belongs to its named scope: read it or lend it `mut` to a helper, but do not store it, pass it as `own` or
return it. A record, list, variant or callback type that would hold a file owner is refused where it is declared; a
fallible result may carry a direct file payload. A narrowed capability (`fs.dir(path)`, `env.only(...)`) is a new handle
that a `with` scope may bind but does not need.

```selka
# doc: expect 0
func read_one(fs: Filesystem) -> int:
    with fs.open("sample", "rb") as file:
        return len(file.read(1))
func main() -> int:
    return 0
```

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

A task reads its lent arguments until the group closes, after its result is read too. A `const` alias lends its owner for
that whole time. Declare lent owners before the group or at the top level of its block, and change them after it. Passing
`mut`, an owned resource, `Host` or any capability (or a value holding one) to a task is refused. Bind a list element before
lending it. An explicit owned argument gives the task its own value. A function with a borrowed result cannot be submitted
(V4).

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

Open a group with `with parallel.group() as group`. The group and its handles stay inside the block. A submitted task
initializes a `const` handle, each `result()` is read once, and every result is read before the group exits.

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

`parallel.map(values, function, ARGS)` lends its input and trailing arguments to every item call until it returns, a slice
or plain parameter as the view itself. Trailing `mut` or `own` arguments are refused; at most five; a fallible function takes
none.

```selka
# doc: expect 9
import parallel
func add(value: int, extra: int) -> int:
    return value + extra
func main() -> int:
    const answers = parallel.map([1, 2], add, 3)
    return answers[0] + answers[1]
```

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

Handle, return, transfer or explicitly discard every pending Result before its scope ends. It cannot be overwritten, used
after transfer, silently copied or implicitly discarded; continuing paths and loop back edges must agree, and propagation
must not abandon another pending temporary. A bare Result statement needs an explicit discard (no automatic repair).

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

```selka
# doc: expect-error E_RESULT_UNHANDLED
func answer() -> int fails str:
    return 7
func main() -> int:
    const pending = answer()
    return 0
```

## Appendix: accepted behaviour and retired restrictions

These entries describe accepted behaviour or a restriction the language no longer has. T1, B4, B5, W1, V1, V7, P5, Z1 and Z2
have no refusal of their own.

### T1 — Managed types

Layer: Frontend.

Codes: none.

A managed type owns storage: text, bytes, a collection, a resource, an owning provider, or an aggregate containing any.
Other values are scalar and copy on use. Moving a managed aggregate transfers the storage inside it.

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

Assigning a whole new value to a `mut` binding makes it available again after a move. Updating one field of an unavailable
record does not.

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

After an `if` or `match`, a binding is available only if it is available on every path that continues. A later use of an
unavailable one is B3.

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

An `own` parameter takes its argument; the caller's binding is then unavailable (B3). The callee may change, store, transfer
or return it, else it is destroyed after its final use.

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

A slice used as a read-only view borrows its source through its final use and allocates nothing. Views are read in place;
storage, invalidation and return restrictions are V2 to V4.

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

Slice views support their type's read operations: slicing, indexing, `len`, comparison, printing and explicit copying. The `TextView` and `ByteView` spellings are
`E_BORROW_VIEWS_REMOVED`: use a slice.

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

Capabilities are shareable handles, so a record of them is an ordinary value: returned, stored, copied, passed `mut`. An
optional capability is an ordinary option.

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

`old(expression)` in an `@ensures` clause captures its entry value. A managed value is captured by a written copy:
`old(copy(values))`; a bare `old(values)` is `E_CONTRACT_OLD_COPY` (`selka fix` writes the copy), and `old(len(values))`
copies nothing. A resource cannot be copied: `E_CONTRACT_OLD_SHARED`.

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

Arguments evaluate left to right in source order, named arguments included; no ownership refusal remains for the temporaries
this needs. Here `right` runs first, so the recorded order is `[2, 1]`, while the named values still give `12`.

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

Mutation and borrowed-result summaries come from the declared `mut` and `from` signatures, even through a chain of helpers;
there is no whole-program analysis budget.

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

A code may enforce several rules; an ownership diagnostic names the one that caused its refusal. `E_CORE_UNSUPPORTED` also
covers ordinary backend limits, which carry no rule; its ownership limits carry Z3.

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

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/ownership-rules.md).
