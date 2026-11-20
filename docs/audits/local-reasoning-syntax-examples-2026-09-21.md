# Syntax for local reasoning — one worked example per proposal

Companion to [the audit](local-reasoning-syntax-audit-2026-09-21.md). Each
section takes one proposal, shows the code a reader meets today and what they
have to open to understand it, then the proposed spelling and what the compiler
says when the new rule is broken. "Today" blocks were run against the installed
compiler on 2026-09-21 and behave as described; "proposed" blocks are
illustrative and their diagnostics are suggested wording. Nothing here is
implemented.

## 1. A call changes exactly its receiver and its `mut` arguments

**Today.** Two helpers take the same object. One changes it, one does not, and
the two call lines are indistinguishable.

```text
# doc: not-mylang
record Item:
    name: str
    count: int

class Inventory:
    items: list[Item]
    total: int

def restock(inv: Inventory, name: str, amount: int) -> None:
    inv.items.append(Item(name=name, count=amount))
    inv.total = inv.total + amount

def report(inv: Inventory, out: Stream) -> None:
    out.print(inv.total, len(inv.items))

def main(out: Stream) -> int:
    inv = Inventory(items=[], total=0)
    restock(inv, "bolt", 5)      # changes inv
    report(inv, out)             # does not
    return 0
```

A reader of `main` has to open `restock` and `report` to learn which line
changed `inv`. The compiler says nothing: `Inventory` is a `class`, and writes
through a class parameter are exempt from `W_MUTATES_MISSING`. Had `inv` been a
list, the author would have been *warned* to add `mutates(inv)` to `restock`,
and the call line would still look the same.

**Proposed.** The parameter says it is written; the call says it is written;
nothing else can be.

```text
# doc: not-mylang
def restock(inv: mut Inventory, name: str, amount: int) -> None:
    inv.items.append(Item(name=name, count=amount))
    inv.total = inv.total + amount

def report(inv: Inventory, out: Stream) -> None:
    out.print(inv.total, len(inv.items))

def main(out: Stream) -> int:
    inv = Inventory(items=[], total=0)
    restock(mut inv, "bolt", 5)
    report(inv, out)
    return 0
```

The reader of `main` now knows, without opening anything, that the `restock`
line is the only one that can change `inv`. The reader of `report` knows from
its first line that `inv` is read-only inside it. The trailing
`effects(mutation) mutates(inv)` clause is gone because it is derived from
`mut`.

Method calls need no marker, because a receiver may always be changed by its
own method — that is the Python reader's prior and it stays true:

```text
# doc: not-mylang
inv.items.append(item)      # receiver: may change, no marker
counts.sort()               # receiver: may change, no marker
restock(mut inv, "nut", 2)  # argument: marker required
```

**What the compiler says when the rule is broken.** Each rejection carries a
paste, in both directions.

```text
main.my:17:13: error[E_MUTATION_MARKER]: `restock` writes `inv`; write `restock(mut inv, "bolt", 5)`
main.my:9:5: error[E_MUTATION_MARKER]: this function writes `inv` (parameter 1); declare it `inv: mut Inventory`
main.my:13:12: error[E_MUTATION_MARKER]: `inv` is declared `mut` but never written; remove `mut`
```

The third one matters as much as the first two: a `mut` that is not needed is
a lie the reader would otherwise believe.

## 2. The signature is the whole contract; an unused capability is an error

**Today.** The schematic guest's `text.equal` takes a `Host` it never uses (the
parameter is a fossil of a byte-compare intrinsic), and `layout_graph.rail`
restates its parameters as an effect clause.

```text
# doc: not-mylang
public def equal(host: Host, a: Span, b: Span) -> bool effects():
public def rail(host: Host, span: text.Span) -> bool effects(host, managed_allocation):
```

A reader of a call to `equal(host, a, b)` believes it may reach C. The only
way to learn otherwise is `list-interfaces`, which prints `effects()` beside
`ceiling(host)` — a fact the source never states.

**Proposed.** Effects are read off the parameter list; a capability that is not
used is rejected; narrowings are the only clauses left.

```text
# doc: not-mylang
public def equal(a: Span, b: Span) -> bool:
public def rail(host: Host, span: text.Span) -> bool:
```

Every signature then reads by one rule. Four from a made-up module:

```text
# doc: not-mylang
def area(width: int, height: int) -> int
    # no capability, no mut: a value computed from its arguments, nothing else

def render(out: Stream, shape: Shape) -> None
    # may print; cannot change `shape`

def load(fs: Filesystem, path: str) -> Result[Doc, str]
    # may read files; may fail; the caller handles it with `?` or `match`

def place(rows: mut list[Row], width: int) -> None
    # changes `rows`; touches nothing outside the process

def checksum(data: bytes) -> int noalloc
    # as `area`, and additionally promises not to allocate
```

**What the compiler says.**

```text
text.my:12:18: error[E_UNUSED_CAPABILITY]: `host` is never used, so this signature claims an effect the body cannot have; remove the parameter or use it
graph.my:8:47: warning[W_DERIVED_EFFECTS]: `effects(host, managed_allocation)` is exactly what the parameters imply; remove it (narrowings such as `noalloc` stay)
```

## 3. Retire sentinels: make `Option` as cheap as `-1`

**Today.** Absence is a negative integer, and every reader has to know the
convention from somewhere else.

```text
# doc: not-mylang
def find_pin(pins: list[Pin], name: str) -> int:
    for index, pin in enumerate(pins):
        if pin.name == name:
            return index
    return -1

def wire(pins: list[Pin], name: str) -> int:
    index = find_pin(pins, name)
    if index < 0:          # what does negative mean? open find_pin
        return 0
    return pins[index].net
```

**Already possible today** (this program runs and prints `1 0`): return an
`Option`, test it with `is None`, and use the narrowed value.

```text
# doc: not-mylang
def find_pin(pins: list[Pin], name: str) -> Option[int]:
    for index, pin in enumerate(pins):
        if pin.name == name:
            return Some(index)
    return None

def wire(pins: list[Pin], name: str) -> int:
    index = find_pin(pins, name)
    if index is None:      # the signature said it could be absent
        return 0
    return pins[index].net
```

The reader of `wire` learns from `find_pin`'s *signature* that the result can
be absent, and `is None` reads as what it is. The corpus does not do this
because the second common shape — "absent means use a default" — still costs
four lines.

**Proposed** additions: `unwrap_or`, `is_some`/`is_none` as methods, and a
`None` default on `Option` fields.

```text
# doc: not-mylang
width = parse_width(text).unwrap_or(80)     # one line instead of a match

record Part:
    ref: str
    pin1: Option[int] = None      # instead of `pin1: int` meaning -1
    pin2: Option[int] = None
```

**What the lint says** about the code that stays on sentinels:

```text
layout.my:31:8: warning[L_SENTINEL_INT]: `index` is tested against a negative literal here and in `wire`; return `Option[int]` from `find_pin` and test `is None`
```

## 4. Tuples for multi-value returns

**Today.** Returning two values means declaring a record whose only job is to
carry them.

```text
# doc: not-mylang
record Split:          # exists for one function
    head: str
    rest: str

def split_first(text: str, sep: str) -> Split:
    at = text.find(sep)
    if at < 0:
        return Split(head=text, rest="")
    return Split(head=text[0:at], rest=text[at + 1:len(text)])

def main(out: Stream) -> int:
    parts = split_first("key=value", "=")
    out.print(parts.head, parts.rest)   # what fields does Split have? open it
    return 0
```

**Proposed.** The shape is at the return and at the call.

```text
# doc: not-mylang
def split_first(text: str, sep: str) -> tuple[str, str]:
    at = text.find(sep)
    if at < 0:
        return text, ""
    return text[0:at], text[at + 1:len(text)]

def main(out: Stream) -> int:
    head, rest = split_first("key=value", "=")
    out.print(head, rest)
    return 0
```

The tuple is immutable and fixed-arity, has no indexing and no methods, so it
cannot become an undeclared record; it exists to be taken apart on the next
line. `for key, value in mapping.items()` already destructures today and keeps
working.

**What the compiler says.**

```text
main.my:9:5: error[E_TUPLE_ARITY]: `split_first` returns 2 values; bind 2 names, or `_` for one you do not need
main.my:9:12: error[E_TUPLE_INDEX]: a tuple has no elements to index; bind its values by name
```

## 5. Keyword-only parameters, and a lint on positional literals

**Today.** Every error site in the schematic guest looks like this.

```text
# doc: not-mylang
def issue(host: Host, code: int, file: int, position: int) -> int:
    ...

_ = io.issue(host, 13, 0, span.start)     # which is the code, which the file?
```

**Proposed.** Python's bare `*` makes everything after it keyword-only, so the
callee can insist on names.

```text
# doc: not-mylang
def issue(host: Host, *, code: int, file: int, position: int) -> None:
    ...

io.issue(host, code=13, file=0, position=span.start)
```

The reader still does not know what `13` means (§3.9's `Err(int)` lint is for
that), but they know it is the code and that `0` is the file, without opening
`issue`.

**What the compiler and the lint say.**

```text
circuit.my:89:24: error[E_KEYWORD_ONLY]: `code` is keyword-only; write `io.issue(host, code=13, file=0, position=...)`
draw.my:40:5: warning[L_POSITIONAL_LITERAL]: `True` is passed positionally to a 4-argument call; name it: `draw(canvas, x=10, y=20, filled=True)`
```

## 6. Conditional expression

**Today.** A name must be assigned before it is read, so a placeholder value
comes first and the real choice follows.

```text
# doc: not-mylang
edge = 352                      # is 352 meaningful, or a placeholder?
if row.side == 1:
    edge = 532

point = Point(x=-1, y=-1)       # -1 is not a coordinate; it is "not yet"
if row.side == 1:
    point = Point(x=532, y=row.y)
else:
    point = Point(x=352, y=row.y)
```

**Proposed.** Python's spelling, with the language's rules: the condition is
`bool` and both arms have one type.

```text
# doc: not-mylang
edge = 532 if row.side == 1 else 352
point = Point(x=532 if row.side == 1 else 352, y=row.y)
```

Both candidate values are on the line that chooses between them, and no
placeholder exists for a reader to wonder about.

**What the compiler says.**

```text
layout.my:20:12: error[E_TYPE]: conditional arms must agree: `int` here, `str` in the else arm
layout.my:21:15: error[E_TYPE]: expected bool, found int
```

## 7. `requires` on the signature

**Today.** A function's domain is a comment, or a fallback buried in the body.

```text
# doc: not-mylang
# number must be 1 or 2
def part_pin(part: int, number: int, pins: list[Pin]) -> Pin:
    index = -1
    if number == 1:
        index = parts[part].pin1
    elif number == 2:
        index = parts[part].pin2
    ...
    return Pin(part=part, number=number, nc=True, ...)   # placeholder for a bad number
```

A caller passing `3` gets a placeholder pin and no error; a reader of the
caller learns the rule only by reading `part_pin` to its last line.

**Proposed.** The rule goes on the signature and is checked at entry.

```text
# doc: not-mylang
def part_pin(part: int, number: int, pins: list[Pin]) -> Pin requires 1 <= number <= 2:
    if number == 1:
        return pins[parts[part].pin1]
    return pins[parts[part].pin2]
```

It desugars to an `assert` on entry, so it costs what an assert costs. It is
printed by `list-interfaces` and `mylang context` beside the signature, so a
reader who fetches the contract gets the domain with it, and a failing caller
is stopped at the boundary rather than handed a placeholder.

**What it prints when violated.**

```text
layout.my:41:12: error[R_ASSERT]: part_pin requires 1 <= number <= 2 (number = 3)
  called from layout.my:120:9
```

## 8. Records are deep values, or they are classes

**Today.** A `record` copies its own fields but shares a managed field. This
program prints `2 1`: `second.count` is independent of `first.count`, and
`second.seen` is the same list as `first.seen`.

```text
# doc: not-mylang
record Tally:
    count: int
    seen: list[int]

def main(out: Stream) -> int:
    first = Tally(count=2, seen=[])
    second = first
    second.count = 40          # rejected today: E_DEAD_RECORD_WRITE
    second.seen.append(7)      # accepted, and visible through first.seen
    out.print(first.count, len(first.seen))
    return 0
```

The compiler now rejects the first write (a copy nobody reads); it accepts
the second, which is the one a Python reader expects to be local and is not.
To know which is which, the reader has to open `Tally` and know which field
types share.

**Option A (small).** Keep the semantics; say it when it happens.

```text
main.my:10:5: warning[W_SHARED_FIELD_WRITE]: `second` is a copy of `first`, but `seen` is a list both copies share; this append is visible through `first.seen`. Use `class Tally` if sharing is intended.
```

**Option B (larger).** A `record` may hold only values — scalars, `str`,
`bytes`, enums, tuples, other records, fixed arrays. Anything with a shared
mutable field is a `class`.

```text
# doc: not-mylang
record Tally:
    count: int
    seen: list[int]
# main.my:3:5: error[E_RECORD_FIELD]: `seen: list[int]` is shared storage; a record holds only values. Declare `class Tally`, or make the field a value.

class Tally:              # what it is: one object, changed in place
    count: int
    seen: list[int]

record Reading:           # what a record is for: a value with no identity
    sensor: int
    celsius: float
```

Then the copy-or-share question is answered by the declaration keyword alone,
with no exceptions: `record` and scalars copy, everything else shares.

## 9. Lints for what the syntax already offers

Each of these is a construct that exists; the corpus does not use it, and a
reader pays. The lint's job is to name the shorter spelling with the fix.

**Index loop → `for`** (71 sites).

```text
# doc: not-mylang
i = 0
while i < len(pins):          # what is iterated? read the body
    pin = pins[i]
    if pin.rail != 0:
        total += 40
    i += 1
# ---
for pin in pins:              # the header says it
    if pin.rail != 0:
        total += 40
# ---
for i, pin in enumerate(pins):   # when the index is needed for a write
    pins[i].rail = classify(pin)
```

The lint fires only when the body advances `i` by exactly one and reads
`xs[i]`; a walk like `i = s.at(nodes, i).next` is a real `while` and is left
alone.

**Integer kind codes → `enum`** (30 sites). This runs today and prints `2`.

```text
# doc: not-mylang
if part.kind == 0:            # 0 is a chip; 1 a capacitor; 2 ... open circuit.my
    return 41
return 2
# ---
enum Kind:
    chip,
    capacitor,
    resistor

def pin_count(part: Part) -> int:
    match part.kind:
        case Kind.chip:
            return 41
        case _:
            return 2
```

**`Err(int)` → a `union`** (22 sites).

```text
# doc: not-mylang
return Err(13)                              # 13 means "pin without a net" — where is that written?
# ---
union CircuitError:
    missing_net(span: Span),
    duplicate_pin(part: str, number: int)

return Err(CircuitError.missing_net(span))  # the case name is the documentation
```

**`j = len(parts)` → `break`**, and **`_ = f()` on a function that always
returns 0 → `-> None`**.

```text
# doc: not-mylang
while j < len(parts):
    if match(parts[j]):
        offset = branch(j)
        j = len(parts)         # the reader searches for where j is read next
    j += 1
# ---
for j, part in enumerate(parts):
    if match(part):
        offset = branch(j)
        break

_ = placeRows(ordered)         # placeRows returns 0 unconditionally
# ---
placeRows(mut ordered)         # with §1; returns None
```

**Byte codes → `ord`** (already folds to a constant; this line runs today and
prints `True True False`).

```text
# doc: not-mylang
if c == 40u8:                     # 40 is "(" — a reader counts on an ASCII table
# ---
if source[p] == ord("("):
```

## 10. Formatter: `- 1`

```text
# doc: not-mylang
out.append(Part(node=i, ref=ref.span, pin1=- 1, pin2=- 1))   # today's canonical layout
out.append(Part(node=i, ref=ref.span, pin1=-1, pin2=-1))     # proposed
```

`- 1` reads as a binary minus with a missing left operand. The formatter should
print a negated literal without the space.

## The same function, before and after everything

`layout.placeRows` as it is, and as it would read with §1, §2, §6 and §9 applied.
The body's logic is unchanged; what changed is what a reader knows before the
first line of the body.

```text
# doc: not-mylang
# today: returns an int nobody uses; writes rows[i].side and rows[i].y, which
# nothing in the signature says; the caller writes `_ = placeRows(ordered)`.
def placeRows(rows: list[Row]) -> int:
    total = 0
    i = 0
    while i < len(rows):
        row = rows[i]
        total += row.height
        ...
        side = -1
        if i >= split:
            side = 1
        rows[i].side = side
        rows[i].y = y + offset
        y += row.height
        i += 1
    return 0
```

```text
# doc: not-mylang
# proposed: the signature says it writes rows and nothing else; the loop says
# what it walks; the choice of side is one line; the caller writes
# `placeRows(mut ordered)`.
def placeRows(rows: mut list[Row]) -> None:
    total = 0
    for row in rows:
        total += row.height
        ...
    for i, row in enumerate(rows):
        rows[i].side = 1 if i >= split else -1
        rows[i].y = y + offset
        y += row.height
```
