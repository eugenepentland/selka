# Contracts

A contract states what a function expects, what it promises, and what stays
true of a type. selka writes contracts as attributes on the declaration and
checks them in every build: debug and `--release`, `selka run` and
`selka test`. No mode removes them. A clause the compiler proves can never
fail, and its check is folded away: Core folds a decided comparison to a constant
branch, and LLVM removes the dead trap. `selka cost --clauses` says which
clauses those are ([what the compiler proved](#what-the-compiler-proved)).

| clause | attaches to | checked | sees | trap |
|---|---|---|---|---|
| `@requires(cond[, "message"])` | a `func` | at entry, before the body | the parameters | `R_REQUIRES` |
| `@ensures(cond[, "message"])` | a `func` | at every normal return | the parameters, `result`, `old(...)` | `R_ENSURES` |
| `@invariant(cond[, "message"])` | a `record` | where a value is built or changed | `self` | `R_INVARIANT` |

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
    append(mut log, "withdraw")
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

Under checked ownership, `old(...)` captures an independent value at function
entry, so a later write through `mut xs` does not change the capture. Capturing a
managed value copies it at every call, and that copy is written: `old(copy(xs))`.
A bare `old(xs)` of a list, dictionary, text-bearing record or other managed value
is refused (`E_CONTRACT_OLD_COPY`), and `selka fix` writes the `copy(...)`. A
scalar copies nothing: use `old(len(xs))` when the postcondition needs only the
original length.

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

## Results and `try`

For a function declared `fails` (`-> T fails E`), a postcondition describes success:
it is checked only on a success return, with `result` naming the `T` payload; a
`fail` and a failure a `try` propagates skip it.

```selka
# doc: expect 3
import strings

@ensures(result >= 0, "a length is never negative")
func measure(text: str) -> int fails str:
    if text == "":
        fail "empty"
    return strings.char_count(text)


func main() -> int:
    match measure("abc"):
        case Ok(length):
            return length
        case Err(_):
            return -1
```

## Invariants

An `@invariant` belongs to a `record` and sees only `self`. It is
checked wherever a value of the type is built or changed: every construction
(positional, named, or with default fields), every `replace(...)`, after every
field write (`r.f = v`, `r.f += v`, `take(mut r.f)`, `exchange(mut r.f, v)`, a
destructuring target, and a nested `outer.inner.f = v`, which checks `inner`'s
type), and after every write through a `match mut` payload binding into the
place the record holds (`match mut r.mode:` then `v = x`, `v += x`, `f(mut v)`,
`append(mut items, x)`, `take` or `exchange` of the binding, or a write in a
nested `match mut`), which checks each record with an invariant on the place's
path ([mutable element matches](match-expressions.md#mutable-element-matches)).
Each write is checked on its own: of two writes where the first breaks an
invariant over two fields and the second would repair it, the first traps,
for direct writes and binding writes alike. Build the new value first and write
it once, or use `replace(...)`: compute the new field values into locals first, then
`t = replace(t, free=next_free, count=left)` writes both and is checked once. The trap
of an invariant that reads two fields or more, when a write broke it, says so and names
`replace`. A plain copy is the same
value, so it is not checked again.

Copied JSON and native wire inputs check their invariants before the selected
function runs, including records nested in arrays, lists, dictionaries and
recursive values. A broken input traps `R_INVARIANT` at the invariant clause.

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

A broken invariant traps `R_INVARIANT` at the construction or write that
produced the value, naming the type and the clause:

```console
$ selka run ranges.selka
ranges.selka:12:5: error[R_INVARIANT]: invariant violated: Range invariant `self.low <= self.high`: a range never runs backwards
  in main at ranges.selka:12:5
```

Invariants attach to non-generic records. A `union`, an `enum`, a type alias,
a constraint and a generic record carry none, and an `extern` func cannot carry
`@requires` or `@ensures`: each is `E_CONTRACT_TARGET`. The former `class` and
`host func` forms are retired.

## Conditions are pure

A contract may allocate but must only observe its inputs. The syntactic rule
rejects any mention of a capability parameter, including passing it to a helper,
with `E_CONTRACT_EFFECT`. A condition also cannot use a `mut` call-site marker,
assign, write through a function whose receiver marker is `mut`
(`lists.pop(mut items)`), return early with `try`, or pass away a value the body
still owns, such as a `Result` parameter.
`debug(...)` has no effect and is allowed.

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

A test's arguments come from the test runner rather than from guest code, so no
constructor checked them. The copied-value boundary validates their invariants
first. Every `test_` (or `@test`) function therefore checks,
on entry and before its own `@requires`, the `@invariant` of every record its parameters hold — in fields, collection elements and keys, arrays
and union cases — as a precondition of the test naming the parameter.
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

## What the compiler proved

A clause becomes a test and a trap in the compiled code. When Core's facts
decide the test (they bound every integer and know which branches can run),
the compiler knows the outcome before the program runs. `selka cost
ENTRY.selka --clauses` lists every clause of the program with what the facts made
of it, after the passes of the build mode asked for (release with facts by
default; `--debug` and `--no-facts` compute none, so every clause is kept):

- **proved**: no copy of the check can fail; the facts state every copy's trap
  unreachable;
- **refuted**: the clause fails whenever this program reaches it. The facts are
  whole-program, so this is a statement about this program and its calls, not
  about the function alone;
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

How to read a row: the clause's position, its kind and which clause of that
kind on its function or record it is (`ensures 1`), the function or record, the
condition, the status, then its copies as proved/refuted/kept. A clause is
checked in several places, and each place is a copy: an `@ensures` at every
return, an `@invariant` at every construction and write, a generic function's
clauses once per instance. `own` counts the copies in the function's own body,
`inlined` those the compiler cloned into callers. When every call was inlined,
nothing calls the function's own body any more; its copies never run and are
shown as `unused`. One refuted copy makes the clause refuted; otherwise one kept
copy makes it kept. `clamp` is proved because
each of its three returns is decided; `half` is kept because the facts bound
`value % 2` to `0..1` and no further. A test-runner precondition (the invariant
of a test's parameter) appears as a `requires` row of the test.

A refuted clause reports where it fails, and for a copy cloned into a caller,
the call:

```console
$ selka cost probe.selka --clauses
...
probe.selka:9:10  ensures 1  wrong  `result >= 1`  refuted  own 1/1/0  inlined 0/0/0  fails whenever this program reaches it (in wrong)
```

A refuted clause is not an error and changes no exit status: the build
succeeds and the check traps when the program reaches it (`R_ENSURES` here).
`selka build --stats` and `selka run --stats` print the totals and one
`selka-core: refuted:` line per refuted clause; a program with no clause and no
`assert` prints nothing new. An ordinary build prints no warning (yet): the
debug edit loop serves unchanged functions without loading them, so the
warning would come and go between builds.

`assert` statements are counted in the totals as their own kind; `--asserts`
lists them as rows too. `selka check` computes no facts, so the report needs
`selka cost` or a build with `--stats`. `--json` writes one `cost-clauses-v1`
document ([the cost tool](tooling/cost.md#contract-clauses)).

The status is not a count of trap blocks. A decided check keeps its trap block in
`selka dump-ir` and `--emit-llvm` (a `br i1 true` to the passing side, the dead
trap behind it), and a branch that folds to the trap is not a refutation by
itself: in `a or b` with `b` false, the trap is reached only when `a` fails at run
time, so the clause is kept. A copy is refuted only when the block its check
passes to is unreachable. Core folds a decided comparison of an `and`, `or` or
`not` chain to a constant branch; a chained comparison such as
`0 <= value <= 255` is one boolean, which the facts decide but Core does not
fold, so its branch stays in Core's output for LLVM's optimizer to remove. Its
status is still proved: the facts state its trap unreachable.

A proved clause rests on the fact certificate: the facts state the clause's trap
unreachable, a Debug compiler validates that statement before it emits the
program, and a `--verify-facts` build keeps a fact assertion in every block the
facts call unreachable, so a wrong proof traps `R_CORE_FACT` instead of passing.

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
