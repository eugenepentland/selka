# Contracts

A contract states what a function expects, what it promises, and what stays true of a type. Contracts are attributes on the
declaration, checked in every build; no mode removes them. A clause the compiler proves can never fail costs nothing at
run time ([what the compiler proved](#what-the-compiler-proved)).

| clause | attaches to | checked | sees | trap |
|---|---|---|---|---|
| `@requires(cond[, "message"])` | a `func` | at entry, before the body | the parameters | `R_REQUIRES` |
| `@ensures(cond[, "message"])` | a `func` | at every normal return | the parameters, `result`, `old(...)` | `R_ENSURES` |
| `@invariant(cond[, "message"])` | a `record` | where a value is built or changed | `self` | `R_INVARIANT` |

A clause may repeat; clauses of one kind are checked in source order. The message is a plain string literal.

## Preconditions and postconditions

```selka
# doc: expect 5
@requires(amount > 0, "amount must be positive")
@requires(len(accounts) > 0)
@ensures(result <= amount)
@ensures(len(log) == old(len(log)) + 1)
func withdraw(accounts: int[], mut log: str[], amount: int) -> int:
    append(mut log, "withdraw")
    if accounts[0] < amount:
        return accounts[0]
    return amount


func main() -> int:
    mut log: str[] = []
    mut taken = withdraw([3], mut log, 5) + withdraw([10], mut log, 1)
    return taken + len(log) - 1
```

A `@requires` condition sees the parameters and module-level constants and functions, never a body local. When it is false
the program stops with `R_REQUIRES`, and the report names the caller that broke it:

```console
$ selka run bank.selka
bank.selka:1:11: error[R_REQUIRES]: precondition violated: withdraw requires `amount > 0`: amount must be positive; broken by the caller main at bank.selka:14:13
  in withdraw at bank.selka:1:11
  in main at bank.selka:14:13
```

An `@ensures` condition runs at every normal return, the implicit end of a procedure included. It sees the parameters as
they are then (a `mut` parameter shows the body's writes), `result`, and `old(...)`:

- `result` is the returned value. A parameter named `result` in a function with `@ensures`, or `result` in a procedure that
  returns no value, is `E_CONTRACT_RESULT`.
- `old(expr)` is evaluated once at entry. It may use only the parameters, cannot nest, and is legal only inside `@ensures`
  (`E_CONTRACT_OLD`). A bare `old(xs)` of a managed value (list, dictionary, text-bearing record) is `E_CONTRACT_OLD_COPY`:
  write `old(copy(xs))` (`selka fix` does), or `old(len(xs))` for a scalar.
- For a function declared `fails`, a postcondition is checked only on a success return, with `result` naming the `T`
  payload; `fail` and a propagated `try` failure skip it.

```selka
# doc: expect 2
@ensures(len(items) == len(old(copy(items))) + 1)
func add(mut items: int[], value: int):
    append(mut items, value)


func main() -> int:
    mut items = [1]
    add(mut items, 2)
    return len(items)
```

## Invariants

An `@invariant` belongs to a `record` and sees only `self`. It is checked wherever a value of the type is built or changed:

- every construction (positional, named, or with default fields) and every `replace(...)`;
- after every field write: `r.f = v`, `r.f += v`, `take(mut r.f)`, `exchange(mut r.f, v)`, a destructuring target, and a
  nested `outer.inner.f = v` (which checks `inner`'s type);
- after every write through a `match mut` payload binding into the place the record holds
  ([mutable element matches](match-expressions.md#mutable-element-matches)).

Each write is checked on its own: if the first of two writes breaks an invariant over two fields and the second would repair
it, the first traps. Write once with `t = replace(t, free=next_free, count=left)`; the trap names `replace`. A plain copy is
not checked again. Copied JSON and native wire inputs check their invariants, nested records included, before the selected
function runs (`R_INVARIANT`).

```selka
# doc: expect 707
@invariant(self.low <= self.high, "a range never runs backwards")
record Range:
    low: int
    high: int = 100


@invariant(self.value <= 1000u32)
record Millimeters:
    value: u32

func millimeters_from(value: u32) -> Millimeters:
    return Millimeters(value=value)

func number(value: Millimeters) -> u32:
    return value.value


func main() -> int:
    mut span = Range(low=1, high=5)
    span.high = 9
    mut wider = replace(span, low=0)
    return wider.high - 2 + int(number(millimeters_from(700u32)))
```

A broken invariant traps `R_INVARIANT` at the construction or write that produced the value:

```console
$ selka run ranges.selka
ranges.selka:12:5: error[R_INVARIANT]: invariant violated: Range invariant `self.low <= self.high`: a range never runs backwards
  in main at ranges.selka:12:5
```

Invariants attach to non-generic records only; on a `union`, `enum`, type alias, constraint or generic record, or
`@requires`/`@ensures` on an `extern` func, they are `E_CONTRACT_TARGET`.

## Conditions are pure

A contract may allocate but must only observe its inputs. A condition that mentions a capability parameter (even passing it
to a helper), uses a `mut` call-site marker (`lists.pop(mut items)`), assigns, returns early with `try`, or passes away a
value the body still owns (a `Result` parameter) is `E_CONTRACT_EFFECT`. `debug(...)` is allowed.

```selka
# doc: expect-error E_CONTRACT_EFFECT
import lists

@requires(lists.pop(mut items) > 0)
func first(mut items: int[]) -> int:
    return items[0]


func main() -> int:
    mut items = [1]
    return first(mut items)
```

## Tests

A test's arguments come from the test runner, so no constructor checked them. Every `test_` (or `@test`) function checks, on
entry and before its own `@requires`, the `@invariant` of every record its parameters hold. A
[property test](tooling/guest-tests.md#property-tests) discards a generated input that breaks one; a cases-file argument
that breaks one fails the test:

```console
$ cat cases.json
{"ranges::test_span": {"arguments": {"span": {"low": "5", "high": "1"}}}}
$ selka test ranges.selka --cases cases.json
failed ranges::test_span: R_INVARIANT: Span invariant `self.low <= self.high`: a span never runs backwards
  in @invariant:ranges::Span at ranges.selka:1:12

0 passed, 0 cached, 1 failed, 0 skipped
```

## What the compiler proved

`selka cost ENTRY.selka --clauses` lists every clause with what Core's facts made of it (`--debug` and `--no-facts`
compute none, so every clause is kept):

- **proved**: no copy of the check can fail;
- **refuted**: the clause fails whenever this program reaches it (about this program and its calls, not the function alone);
- **kept**: the check still runs at run time.

```selka
# doc: expect 5
@ensures(result >= 0 and result < 3)
func clamp(value: int) -> int:
    if value < 0:
        return 0
    if value > 2:
        return 2
    return value


@requires(value % 2 == 0, "an even count")
func half(value: int) -> int:
    return value // 2


func main() -> int:
    mut total = 0
    for i in range(3):
        total += half(i * 2)
    assert total == 3
    return clamp(7) + total
```

```console
$ selka cost report.selka --clauses --asserts
...
cost-clauses-v1 (contract clauses after Core passes; proved: cannot fail, refuted: fails whenever reached, kept: checked at run time)
clauses 2: 1 proved, 0 refuted, 1 kept; copies: own 3 proved / 0 refuted / 1 kept, inlined 0 / 0 / 0; asserts: 0 proved / 0 refuted / 1 kept
report.selka:1:10  ensures 1  clamp  `result >= 0 and result < 3`  proved  own 3/0/0  inlined 0/0/0
report.selka:10:11  requires 1  half  `value % 2 == 0`  kept  own 0/0/1  inlined 0/0/0
report.selka:19:12  assert  `total == 3`  kept  own 0/0/1  inlined 0/0/0
```

A row gives the clause's position, kind and number (`ensures 1`), the function or record, the condition, the status, then its
copies as proved/refuted/kept. A clause is checked in several places, each a copy (an `@ensures` at every return, an
`@invariant` at every construction and write, a generic function's clauses once per instance); `own` counts those in the
function's own body, `inlined` those cloned into callers. One refuted copy makes the clause refuted; otherwise one kept
copy makes it kept.

A refuted clause reports where it fails, and for a copy cloned into a caller, the call:

```console
$ selka cost probe.selka --clauses
...
probe.selka:9:10  ensures 1  wrong  `result >= 1`  refuted  own 1/1/0  inlined 0/0/0  fails whenever this program reaches it (in wrong)
```

A refuted clause is not an error: the check traps when the program reaches it (`R_ENSURES` here). `selka build --stats` and
`selka run --stats` print the totals and one `selka-core: refuted:` line per refuted clause. `--asserts` lists `assert`
statements as rows. `selka check` computes no facts; `--json` writes one `cost-clauses-v1` document
([the cost tool](tooling/cost.md#contract-clauses)). A `--verify-facts` build makes a wrong proof trap `R_CORE_FACT`.

## Reports, interfaces and caches

A violated contract exits with status 1. `selka test` prints `R_REQUIRES: ...`, `R_ENSURES: ...` or `R_INVARIANT: ...`
beside the frames, and `--diagnostics=json` adds a `contract` object with `kind`, `subject`, `clause`, the optional
`message` and, for a precondition, the `caller` location.

Contracts are part of a declaration's interface. `selka list-interfaces` prints them after the signature,
`list-interfaces --contracts` carries them as `contracts`, `selka context` shows them above the signature, and
`selka api-diff` reports a changed clause as a breaking interface change. Editing a clause is never answered by a stale
checked body, native object or test receipt.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/contracts.md).
