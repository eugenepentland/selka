# Contracts

A contract states what a function expects, what it promises, and what stays
true of a type. mylang writes contracts as attributes on the declaration and
checks them in every build: Debug and ReleaseFast, QBE and `--release` (LLVM),
`mylang run` and `mylang test`. No mode removes them.

| clause | attaches to | checked | sees | trap |
|---|---|---|---|---|
| `@requires(cond[, "message"])` | a `def` | at entry, before the body | the parameters | `R_REQUIRES` |
| `@ensures(cond[, "message"])` | a `def` | at every normal return | the parameters, `result`, `old(...)` | `R_ENSURES` |
| `@invariant(cond[, "message"])` | a `record` or `domain` | where a value is built or changed | `self` | `R_INVARIANT` |

Each clause may repeat, and the clauses of one kind are checked in source order.
The optional message is a plain string literal.

## Preconditions and postconditions

```mylang
# doc: expect 5
@requires(amount > 0, "amount must be positive")
@requires(len(accounts) > 0)
@ensures(result <= amount)
@ensures(len(log) == old(len(log)) + 1)
def withdraw(accounts: list[int], log: mut list[str], amount: int) -> int:
    log.append("withdraw")
    if accounts[0] < amount:
        return accounts[0]
    return amount


def main() -> int:
    log: list[str] = []
    taken = withdraw([3], mut log, 5) + withdraw([10], mut log, 1)
    return taken + len(log) - 1
```

A `@requires` condition runs after the parameters are bound and before the
body. It sees the parameters and module-level constants and functions, never a
body local. When it is false the program stops with `R_REQUIRES` at the clause,
and the report names the caller that broke it, which is the next frame out:

```console
$ mylang run bank.my
bank.my:1:11: error[R_REQUIRES]: precondition violated: withdraw requires `amount > 0`: amount must be positive; broken by the caller main at bank.my:14:13
  in withdraw at bank.my:1:11
  in main at bank.my:14:13
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

`list`, `dict`, `class`, `Cell` and `byte_buffer` values are shared on
assignment, so `old(xs)` would see the body's changes to `xs`. It is rejected
with `E_CONTRACT_OLD_SHARED`; capture what you need instead, such as
`old(len(xs))`, or a fresh copy, such as `old(xs.copy())`:

```mylang
# doc: expect-error E_CONTRACT_OLD_SHARED
@ensures(len(items) == len(old(items)) + 1)
def add(items: mut list[int], value: int):
    items.append(value)


def main() -> int:
    items = [1]
    add(mut items, 2)
    return len(items)
```

## Results and `?`

For a function that returns `Result[T, E]`, a postcondition describes success:
it is checked only on an `Ok` return, with `result` naming the `T` payload. An
`Err` return, including one a `?` propagates, skips it.

```mylang
# doc: expect 3
@ensures(result >= 0, "a length is never negative")
def measure(text: str) -> Result[int, str]:
    if text == "":
        return Err("empty")
    return Ok(len(text))


def main() -> int:
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

```mylang
# doc: expect 707
@invariant(self.low <= self.high, "a range never runs backwards")
record Range:
    low: int
    high: int = 100


@invariant(unwrap(self) <= 1000u32)
domain Millimeters: u32:
    def from(value: u32) -> Millimeters:
        return wrap[Millimeters](value)

    def number(value: Millimeters) -> u32:
        return unwrap(value)


def main() -> int:
    span = Range(1, 5)
    span.high = 9
    wider = replace(span, low=0)
    return wider.high - 2 + int(Millimeters.number(Millimeters.from(700u32)))
```

A broken invariant traps `R_INVARIANT` at the construction or write that
produced the value, naming the type and the clause:

```console
$ mylang run ranges.my
ranges.my:12:5: error[R_INVARIANT]: invariant violated: Range invariant `self.low <= self.high`: a range never runs backwards
  in main at ranges.my:12:5
```

Invariants attach to non-generic records and domains. A `class` (shared by
reference, so a write elsewhere could break it unseen), a `union`, an `enum`,
a type alias, a constraint and a generic record carry none, and neither does an
`extern` or `host` def carry `@requires` or `@ensures`: each is
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

```mylang
# doc: expect-error E_CONTRACT_EFFECT
@requires(items.pop() > 0)
def first(items: mut list[int]) -> int:
    return items[0]


def main() -> int:
    items = [1]
    return first(mut items)
```

## Tests

A test's arguments come from the test runner rather than from guest code, so no
constructor checked them. Every `test_` (or `@test`) function therefore checks,
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
$ mylang test ranges.my --cases cases.json
failed ranges::test_span: R_REQUIRES: test_span requires `self.low <= self.high`: parameter span holds a Span that breaks this invariant: a span never runs backwards
  in ranges::test_span at ranges.my:8:22

0 passed, 0 cached, 1 failed, 0 skipped
```

## Reports, interfaces and caches

A violated contract exits with status 1 like any other trap. `mylang test`
prints `R_REQUIRES: ...`, `R_ENSURES: ...` or `R_INVARIANT: ...` beside the
frames, and `--diagnostics=json` adds a `contract` object with `kind`,
`subject`, `clause`, the optional `message` and, for a precondition, the
`caller` location.

Contracts are part of a declaration's interface. `mylang list-interfaces`
prints them after the signature, `list-interfaces --contracts` carries them
as `contracts`, `mylang context` shows them above the signature, and
`mylang api-diff` reports a changed clause as a breaking interface change.
Every cache keys on the clause text, so editing one `@requires` is never
answered by a stale checked body, native object or test receipt.
