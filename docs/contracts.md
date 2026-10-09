# Contracts

A contract states what a function expects, what it promises, and what stays
true of a type. selka writes contracts as attributes on the declaration and
checks them in every build: debug and `--release`, `selka run` and
`selka test`. No mode removes them.

| clause | attaches to | checked | sees | trap |
|---|---|---|---|---|
| `@requires(cond[, "message"])` | a `func` | at entry, before the body | the parameters | `R_REQUIRES` |
| `@ensures(cond[, "message"])` | a `func` | at every normal return | the parameters, `result`, `old(...)` | `R_ENSURES` |
| `@invariant(cond[, "message"])` | a `record` or `domain` | where a value is built or changed | `self` | `R_INVARIANT` |

Each clause may repeat, and the clauses of one kind are checked in source order.
The optional message is a plain string literal.

## Preconditions and postconditions

```selka
# doc: expect 5
@requires(amount > 0, "amount must be positive")
@requires(len(accounts) > 0)
@ensures(result <= amount)
@ensures(len(log) == old(len(log)) + 1)
func withdraw(accounts: int[], mut log: str[], amount: int) -> int:
    log.append("withdraw")
    if accounts[0] < amount:
        return accounts[0]
    return amount


func main() -> int:
    mut log: str[] = []
    mut taken = withdraw([3], mut log, 5) + withdraw([10], mut log, 1)
    return taken + len(log) - 1
```

A `@requires` condition runs after the parameters are bound and before the
body. It sees the parameters and module-level constants and functions, never a
body local. When it is false the program stops with `R_REQUIRES` at the clause,
and the report names the caller that broke it, which is the next frame out:

```console
$ selka run bank.selka
bank.selka:1:11: error[R_REQUIRES]: precondition violated: withdraw requires `amount > 0`: amount must be positive; broken by the caller main at bank.selka:14:13
  in withdraw at bank.selka:1:11
  in main at bank.selka:14:13
```

An `@ensures` condition runs at every normal return, including the implicit
end of a procedure. It sees the parameters as they are at that return (a `mut`
parameter shows the body's writes), `result`, and `old(...)`:

- `result` is the returned value. A function with `@ensures` may not name a
  parameter `result` (`E_CONTRACT_RESULT`), and a procedure, which returns no
  value, has no `result` to name (`E_CONTRACT_RESULT`). A body local called
  `result` is fine: the clause cannot see body locals.
- `old(expr)` is evaluated once at entry, after the preconditions, and the
  postcondition reads that value. It may use only the parameters, cannot nest,
  and is legal only inside `@ensures` (`E_CONTRACT_OLD`).

Under value semantics, `old(xs)` captures an independent value at function
entry, so a later write through `mut xs` does not change the capture. In
compatibility mode, an `old(...)` expression that reaches shared state is
rejected with `E_CONTRACT_OLD_SHARED`; capture a scalar such as `old(len(xs))`
or an explicit copy there.

```selka
# doc: expect 2
@ensures(len(items) == len(old(items)) + 1)
func add(mut items: int[], value: int):
    items.append(value)


func main() -> int:
    mut items = [1]
    add(mut items, 2)
    return len(items)
```

## Results and `?`

For a function that returns `Result[T, E]`, a postcondition describes success:
it is checked only on an `Ok` return, with `result` naming the `T` payload. An
`Err` return, including one a `?` propagates, skips it.

```selka
# doc: expect 3
@ensures(result >= 0, "a length is never negative")
func measure(text: str) -> Result[int, str]:
    if text == "":
        return Err("empty")
    return Ok(len(text))


func main() -> int:
    match measure("abc"):
        case Ok(length):
            return length
        case Err(_):
            return -1
```

## Invariants

An `@invariant` belongs to a `record` or a `domain` and sees only `self`. It is
checked wherever a value of the type is built or changed: every construction
(positional, named, or with default fields), every `replace(...)`, after every
field write (`r.f = v`, `r.f += v`, a destructuring target, and a nested
`outer.inner.f = v`, which checks `inner`'s type), and every `wrap[D](v)` of a
domain. A plain copy is the same value, so it is not checked again. A domain
invariant may read its representation with `unwrap(self)`.

Copied JSON and native wire inputs check their invariants before the selected
function runs, including records nested in arrays, lists, dictionaries and
recursive values. A broken input traps `R_INVARIANT` at the invariant clause.

```selka
# doc: expect 707
@invariant(self.low <= self.high, "a range never runs backwards")
record Range:
    low: int
    high: int = 100


@invariant(unwrap(self) <= 1000u32)
domain Millimeters: u32:
    func from(value: u32) -> Millimeters:
        return wrap[Millimeters](value)

    func number(value: Millimeters) -> u32:
        return unwrap(value)


func main() -> int:
    mut span = Range(low=1, high=5)
    span.high = 9
    mut wider = replace(span, low=0)
    return wider.high - 2 + int(Millimeters.number(Millimeters.from(700u32)))
```

A broken invariant traps `R_INVARIANT` at the construction or write that
produced the value, naming the type and the clause:

```console
$ selka run ranges.selka
ranges.selka:12:5: error[R_INVARIANT]: invariant violated: Range invariant `self.low <= self.high`: a range never runs backwards
  in main at ranges.selka:12:5
```

Invariants attach to non-generic records and domains. A `class` (shared by
reference, so a write elsewhere could break it unseen), a `union`, an `enum`,
a type alias, a constraint and a generic record carry none, and neither does an
`extern` or `host` func carry `@requires` or `@ensures`: each is
`E_CONTRACT_TARGET`.

## Conditions are pure

A contract may allocate but must not do anything else, because it runs in
every build and a program must mean the same thing whether or not a check
fails. The effect pass judges each condition with the same inference it uses
for function bodies (see [effects](effects.md)): output, file, network, clock,
random, environment or host access, and `mutation`, anywhere in the condition
or in a function it calls, is `E_CONTRACT_EFFECT`. So are a `mut` call-site
marker, an assignment, a method that changes its receiver, `?`, and passing
away a value the body still owns, such as a `Result` parameter: a condition
only observes.
`debug(...)` has no effect and is allowed.

```selka
# doc: expect-error E_CONTRACT_EFFECT
@requires(items.pop() > 0)
func first(mut items: int[]) -> int:
    return items[0]


func main() -> int:
    mut items = [1]
    return first(mut items)
```

## Tests

A test's arguments come from the test runner rather than from guest code, so no
constructor checked them. The copied-value boundary validates their invariants
first. Every `test_` (or `@test`) function therefore checks,
on entry and before its own `@requires`, the `@invariant` of every record or
domain its parameters hold — in fields, collection elements and keys, arrays,
tuples and union cases — as a precondition of the test naming the parameter.
A value guest code built already holds its invariants, so a direct call always
passes these checks. A [property test](tooling/guest-tests.md#property-tests)
discards a generated input that breaks one, as it discards one that breaks the
test's own `@requires`; a cases-file argument that breaks one fails the test:

```console
$ cat cases.json
{"ranges::test_span": {"arguments": {"span": {"low": "5", "high": "1"}}}}
$ selka test ranges.selka --cases cases.json
failed ranges::test_span: R_INVARIANT: Span invariant `self.low <= self.high`: a span never runs backwards
  in @invariant:ranges::Span at ranges.selka:1:12

0 passed, 0 cached, 1 failed, 0 skipped
```

## Reports, interfaces and caches

A violated contract exits with status 1 like any other trap. `selka test`
prints `R_REQUIRES: ...`, `R_ENSURES: ...` or `R_INVARIANT: ...` beside the
frames, and `--diagnostics=json` adds a `contract` object with `kind`,
`subject`, `clause`, the optional `message` and, for a precondition, the
`caller` location.

Contracts are part of a declaration's interface. `selka list-interfaces`
prints them after the signature, `list-interfaces --contracts` carries them
as `contracts`, `selka context` shows them above the signature, and
`selka api-diff` reports a changed clause as a breaking interface change.
Every cache keys on the clause text, so editing one `@requires` is never
answered by a stale checked body, native object or test receipt.
