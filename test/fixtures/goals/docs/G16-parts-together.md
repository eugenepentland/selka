# G16 to G18. Parts that work alone work together: pinned examples

## G16. A protocol between calls can be a type

**G16-H1.** A `@linear` value cannot be duplicated.

```selka
# doc: expect-error E_LINEAR_USE
@linear
record Draft:
    id: int

record Sent:
    id: int

func send(own d: Draft) -> Sent:
    return Sent(id=own d.id)

func main() -> int:
    const d = Draft(id=7)
    const twin = copy(d)
    const a = send(own d)
    const b = send(own twin)
    return a.id + b.id
```

**G16-H2.** A `@linear` value cannot be dropped.

```selka
# doc: expect-error E_LINEAR_UNCONSUMED
@linear
record Draft:
    id: int

func main() -> int:
    const d = Draft(id=7)
    return 0
```

**G16-H3.** Consumed once, it is accepted.

```selka
# doc: expect 7
@linear
record Draft:
    id: int

record Sent:
    id: int

func send(own d: Draft) -> Sent:
    return Sent(id=own d.id)

func main(out: Stream) -> int:
    const d = Draft(id=7)
    const s = send(own d)
    print(out, s.id)
    return 0
```

**G16-H4 (formerly G16-X1; sealed types, W11).** Only the module that declares a `@sealed` state builds one: another module
cannot make a `Sent` without sending. With `@linear` beside it the draft cannot be copied or dropped either, so the call
order is a type.

```selka
# doc: project sealed-protocol
# doc: file mail.selka
@linear
@sealed
public record Draft:
    id: int

@sealed
public record Sent:
    id: int

public func draft(id: int) -> Draft:
    return Draft(id=id)

public func send(own d: Draft) -> Sent:
    return Sent(id=own d.id)
```

```selka
# doc: project sealed-protocol
# doc: file main.selka
# doc: expect-error E_SEALED_RECORD
import mail

func main() -> int:
    const real = mail.send(own mail.draft(7))
    const forged = mail.Sent(id=0)
    return real.id + forged.id
```

**G16-H5 (a `match mut` lends a linear owner; FX8, decision LIN).** A state machine keeps its owner in a union's arm,
uses it in place through `match mut`, and must still end the union afterwards: the lend is not a consumption, so a
program whose only use of the owner is a `match mut` is refused.

```selka
# doc: expect 41
@linear
record Lease:
    id: int

enum Slot:
    busy(held: Lease)
    idle

func renew(mut lease: Lease):
    lease.id = lease.id + 1

func release(own slot: Slot) -> int:
    match own slot:
        case busy(held):
            return own held.id
        case idle:
            return 0

func main(out: Stream) -> int:
    mut slot = Slot.busy(held=Lease(id=40))
    match mut slot:
        case busy(held):
            renew(mut held)
        case idle:
            pass
    print(out, release(own slot))
    return 0
```

## G17. A failed call says what it did to its arguments

**G17-X1 (a failed call leaves its `mut` argument half-updated; W15).**

```selka
# doc: expect failed: insufficient funds balance now -15 log entries 1
record Account:
    balance: int
    log: str[]

func withdraw(mut a: Account, amount: int) -> int fails str:
    append(mut a.log, "withdraw")
    a.balance = a.balance - amount
    if a.balance < 0:
        fail "insufficient funds"
    return a.balance

func main(out: Stream) -> int:
    mut a = Account(balance=10, log=[])
    match withdraw(mut a, 25):
        case Ok(v):
            print(out, "ok", v)
        case Err(e):
            print(out, "failed:", e, "balance now", a.balance, "log entries", len(a.log))
    return 0
```

## G18. An identity belongs to its owner

**G18-H1.** One-field records give distinct identities at no cost: they do not mix.

```selka
# doc: expect-error E_TYPE
record NetId:
    index: int

record PartId:
    index: int

func name_of(names: str[], id: NetId) -> str from names:
    return names[id.index]

func main() -> int:
    const names = ["GND", "VCC"]
    const p = PartId(index=1)
    return len(name_of(names, p))
```

**G18-X1 (a pool handle reads another pool's slot, and a hand-built handle works; W17).**

```selka
# doc: expect C1 R1
import pool

func main(out: Stream) -> int:
    mut nets = pool.create(["GND", "VCC"])
    mut parts = pool.create(["R1", "C1"])
    const hs = pool.handles(nets)
    const h = hs[1]
    const wrong = pool.get(parts, h)
    const forged = pool.Handle[str](index=0, generation=0)
    const f = pool.get(parts, forged)
    print(out, wrong.unwrap_or("none"), f.unwrap_or("none"))
    return 0
```
