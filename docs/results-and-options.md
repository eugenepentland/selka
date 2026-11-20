# Results and options

A fallible function declares its success type and error separately: `func parse(text: str) -> Point fails ParseError`. `return point` succeeds, `fail error` returns the declared failure, and a call answers a checked result that must be handled, stored or passed on. `try parse(text)` extracts the success and propagates a compatible failure.

An optional `T?` is a value or `None`. Absence is ordinary data with no handling obligation; return or assign a `T` directly where `T?` is expected. A stored result may be typed `Result[T, E]`; a nominal `result` declaration is rare and keeps its own identity.

## Flow-sensitive Option guards

`value is None` and `value is not None` test an Option's tag. In a branch that establishes a local Option is present, reads use its payload type, and an early return from the absent branch keeps it available afterwards. `value is Some` and `result is Ok` work alike, and `if value is Some(item):` binds the payload ([testing one case with `is`](match-expressions.md#testing-one-case-with-is)).

`const value = lookup(key) else:` plus a block that returns, fails, breaks or continues unwraps an Option or Result and leaves on the failing case. Use it when the exit does more than `try` can ([bind or else](statements.md#bind-or-else)).

```selka
# doc: expect 42
record Node:
    width: int

func width(node: Node?) -> int:
    if node is None:
        return 0
    return node.width

func positive(value: int?) -> bool:
    return value is not None and value > 0

func main() -> int:
    if positive(Some(42)):
        return width(Some(Node(width=42)))
    return 0
```

- Facts follow `if`/`else`, `not` and short-circuit `and`/`or`, in generic functions too; `while value is not None` establishes presence in its body.
- After a join a fact survives only if every continuing branch keeps it. Reassigning the binding invalidates it, and a loop that might never run establishes nothing afterwards.
- The binding stays an Option: assign `None` or a payload to replace it.
- Only locals are refined, not `box.item`; copy a copyable Option into a local first.
- A presence test on a wrapper carrying an owned value or a checked `Result` is rejected; use `match`.

## Option methods

`T?` has one intrinsic method, `unwrap_or(default: T) -> T` (also `unwrap_or(value, default)`): the payload, or the default. It is pure and allocates nothing, so a `noalloc` ceiling accepts it, and it works in a generic body whose parameter is a `T?`. An integer literal default adopts the payload type (`unwrap_or(7)` on a `u8` is a `u8`); a mismatch is `E_TYPE`. An Option carrying an owned value or a checked `Result` needs `match`.

| Python habit | Selka |
|---|---|
| `value == None`, `value != None` | `E_OPTION_COMPARISON_REMOVED`: write `value is None`, `value is not None` |
| `value.is_none()`, `value.is_some()` | `E_OPTION_METHOD_REMOVED`: write the same test |

`selka fix` rewrites a standalone comparison or call; inside a comparison chain it stays a hand migration. The `sentinel-int` lint flags a function that returns `-1` on one path whose caller tests a negative literal.

```selka
# doc: expect 47
func parse(text: str) -> int?:
    return parse_int(text)

func head[T: copy + storable](values: T[]) -> T? from values:
    if len(values) == 0:
        return None
    return Some(values[0])

@noalloc
func width(text: str) -> int:
    return parse(text).unwrap_or(0)

func main() -> int:
    mut total = parse("nope").unwrap_or(7)
    total = total + head([40, 1]).unwrap_or(0)
    if parse("2") is None:
        total = total + 100
    if head([1]) is not None:
        total = total + width("0")
    return total
```

## Checked results

`Result[T, E]` has `Ok(value)` and `Err(payload)`; the payload is any value type. A result-bearing value may not be dropped: every path out of a scope must match it exhaustively, return it, pass it on, or release it with `_ = value`, or it is `E_RESULT_UNHANDLED` (pointing at the binding and the exit that left it pending). The obligation travels with the value, and a record or union field holding a result keeps it for the whole wrapper.

```selka
# doc: expect-error E_RESULT_UNHANDLED
func divide(numerator: int, denominator: int) -> int fails str:
    if denominator == 0:
        fail "division by zero"
    return numerator // denominator

func main(out: Stream) -> int:
    match divide(21, 3):
        case Ok(value):
            print(out, value)
        case Err(message):
            print(out, message)
    mut ignored = divide(1, 0)
    return 0
```

`ignored` reaches the end of `main` unhandled; `_ = divide(1, 0)` would accept it. `assert`, arithmetic overflow and host failures trap and never become an `Err`.

A call of a `fails` function answers a `Result`, not the success value, so `2 + parse("1")` and `mut n: int = parse("333")` are `E_TYPE`. The message names the ways out: `try parse(...)` (the enclosing function declares the same `fails`; `selka fix` writes it) or ``const n = parse(...) else Err(e):``. A `Result` held in a variable, and a call where `try` is refused (a contract condition, a lambda, a `detach` loop, a function with an `on fail:` clause), get the plain message.

### Explicit results across module boundaries

When the error is an enum from another module, the annotation and the pattern use the imported name and the constructor names its case, as a standard module's fallible API does.

```selka
# doc: expect 42
import strings

func positive(text: str) -> int fails strings.Error:
    match parse_int(text):
        case Some(value):
            if value > 0:
                return value
            fail strings.Error.Invalid(value="positive integer required")
        case None:
            fail strings.Error.Invalid(value="not an integer")


func main() -> int:
    match positive("42"):
        case Ok(value):
            return value
        case Err(error):
            match error:
                case Invalid(value=reason):
                    return strings.char_count(reason)
                case Overflow(value=reason):
                    return 0 - strings.char_count(reason)
```

## Postfix error propagation

`try operation()` works wherever a value is computed at run time: a declaration initializer, an assignment value (a name, field, element or nested place; `=` or a compound form), a `return` or `fail` value, a standalone operation, a resource head (`with try open(...) as file:`, see [printing, files and command-line authority](io.md)), a call argument, or an operand ([`try` in an operand](#try-in-an-operand)). It takes the call after it with its `.`, `[]` and call suffixes, and an operator after it takes the call's value: `try f() + 1` is `(try f()) + 1`. `return try other()` forwards the value and a compatible failure.

`E_TRY_POSITION`: a `try` over an operator expression (`try (a + b)`, `try -f()`; write the operator outside), and a `try` in a compile-time value (a module constant, a parameter or field default).

The enclosing function must declare a compatible failure type. An error of another type converts into the enclosing union when exactly one case can carry it (a case whose payload is that type, or one with a single named field of it); two or more is `E_ERROR_CASE_AMBIGUOUS` ([converting into one case](#converting-into-one-case)). Unrelated errors do not widen. Propagation releases the scopes it exits, open files included. The `?` suffix belongs to optional types.

```selka
# doc: expect 37
import strings

func divide(n: int, d: int) -> int fails str:
    if d == 0:
        fail "division by zero"
    return n // d

func average(total: int, parts: int) -> int fails str:
    mut share = try divide(total, parts)
    return share + 1

func report(total: int, parts: int) -> int:
    match average(total, parts):
        case Ok(value):
            return value
        case Err(message):
            return strings.char_count(message)

func main() -> int:
    return report(40, 2) + report(40, 0)
```

### `try` in an operand

`try CALL` may be the value of an assignment to a place (`r.a = try f()`, `xs[i] = try f()`, `total.count += try f()`), an argument of any call at any depth, or an operand of any expression computed at run time (arithmetic, comparisons, `and`/`or`/`not`, an index or slice bound, a literal element, a format string hole, a condition, a `match` subject, the list a `for` walks).

The order is that of the expression without `try`:

- Operands evaluate left to right, and values left of the `try` are held before its call runs. For `=` to a place the call runs first, then the place's index and key expressions; for a compound form the place's expressions run first.
- If the call fails, the function leaves with its error there: nothing to its right is evaluated, the enclosing call does not happen, the place is not written, and what the operands to its left made is destroyed once. What a `mut` argument already wrote stays written.
- Under `and` and `or` a `try` on the unevaluated side does not run. One in a `while` condition runs on every test, in an `elif` only when that condition is tested, in an `assert` message only on failure. A `try` that begins `a if p else b` covers the whole conditional.

| Held at the `try` | Result |
|---|---|
| a name passed `own` before the `try` | not given away (the call does not happen); destroyed once on exit |
| a `mut` argument | only lent; nothing happens to it |
| a `@linear` owner given away before the `try` (`use(own token, try check(n))`) or still held when it fails | `E_LINEAR_UNCONSUMED`: declare the value first and end the owner with `on fail:` |
| a `@linear` field the assignment would replace | `E_LINEAR_USE` |
| an armed `on fail:` clause | `E_ON_FAIL`: declare the value first ([cleanup on failure](#cleanup-on-failure)) |
| a `Result` an earlier argument made and nothing handled | `E_RESULT_PROPAGATION` |
| a contract condition (`@requires`, `@ensures`) | `E_CONTRACT_EFFECT` |

```selka
# doc: expect 12
record Header:
    id: int = 0
    sizes: int[]

func read(data: int[], at: int) -> int fails str:
    if at >= len(data):
        fail "truncated"
    return data[at]

func decode(data: int[], mut h: Header) -> Unit fails str:
    h.id = try read(data, 0)
    h.sizes[0] = try read(data, 1)
    h.sizes[0] += try read(data, 2)

func main() -> int:
    mut whole = Header(sizes=[0])
    _ = decode([4, 5, 2], mut whole)
    mut cut = Header(sizes=[0])
    _ = decode([1], mut cut)
    return whole.id + whole.sizes[0] + cut.id + cut.sizes[0]
```

```selka
# doc: expect 9
func note(mut log: int[], n: int) -> int:
    append(mut log, n)
    return n

func checked(mut log: int[], n: int) -> int fails str:
    append(mut log, 10 + n)
    if n > 1:
        fail "too big"
    return n

func run(n: int, mut log: int[]) -> int fails str:
    if n > 0 and try checked(mut log, n) == 1:
        return note(mut log, 1) + try checked(mut log, n) * note(mut log, 3)
    return 0

func main() -> int:
    mut log: int[] = []
    mut total = 0
    match run(1, mut log):
        case Ok(value):
            total += value
        case Err(_):
            pass
    # `n > 0` is false, so `checked` does not run and nothing is noted.
    match run(0, mut log):
        case Ok(value):
            total += value
        case Err(_):
            pass
    # The condition's `checked` notes 12 and fails: the `return` line does not run.
    match run(2, mut log):
        case Ok(_):
            pass
        case Err(_):
            total += len(log)
    return total
```

### Converting into one case

When exactly one case of the enclosing error union can carry the propagated type, that case is the conversion:

```selka
# doc: expect 20
import strings

result Inner:
    ok: int,
    err: str


enum AppError:
    Detail(value: str)
    Missing(value: int)


func load(flag: bool) -> Inner:
    if flag:
        return Err("no value")
    return Ok(20)


func convert(flag: bool) -> int fails AppError:
    mut value = try load(flag)
    return value


func rate(flag: bool) -> int:
    match convert(flag):
        case Ok(value):
            return value - 8
        case Err(error):
            match error:
                case Detail(value=text):
                    return strings.char_count(text)
                case Missing(value=code):
                    return code


func main() -> int:
    return rate(False) + rate(True)
```

`convert(True)` propagates `Err("no value")` with no helper: the `str` becomes the payload of `AppError.Detail`. A type that is no case payload of the union is `E_TYPE`.

`fail value` converts the same way. When two or more cases fit, neither `try` nor `fail` picks one (reordering cases would change the reported error): `E_ERROR_CASE_AMBIGUOUS`, listing the cases that fit in declaration order:

```selka
# doc: expect-error E_ERROR_CASE_AMBIGUOUS
enum AppError:
    Parse(value: str)
    Io(message: str)


func parse(text: str) -> int fails str:
    if len(text) == 0:
        fail "empty"
    return len(text)


func load(text: str) -> int fails AppError:
    const size = try parse(text)
    return size
```

Name the case instead: `fail AppError.Parse(value="empty")`, which `selka fix` writes for you, naming the first case that fits. A `try` has no certain edit: match the result and fail with the case in the `Err` arm.

## Cleanup on failure

`on fail: STATEMENT`, or `on fail:` and an indented block, registers cleanup for the failure exits after it, to the end of the block that holds it (nested blocks, loops and `match` arms included): each `try` whose error leaves the function, and each `fail`. On such an exit the armed clauses run, latest first, then the error leaves. Nothing runs on success, and a trap runs no clause.

```selka
# doc: expect 3
@linear
record Token:
    id: int


func close(own token: Token, mut log: int[]):
    append(mut log, own token.id)


func step(n: int) -> int fails str:
    if n > 1:
        fail "step"
    return n


func run(n: int, mut log: int[]) -> int fails str:
    const token = Token(id=n)
    on fail: close(own token, mut log)
    const value = try step(n)
    close(own token, mut log)
    return value


func main() -> int:
    mut log: int[] = []
    mut total = 0
    match run(1, mut log):
        case Ok(value):
            total += value
        case Err(_):
            pass
    # The second run fails at `step`: its clause closes the token, so the log holds both ids.
    match run(2, mut log):
        case Ok(_):
            pass
        case Err(_):
            total += len(log)
    return total
```

- **Only a function that fails holds one.** `on fail:` without `fails`, or one no failure exit reaches, is `E_ON_FAIL`.
- **A clause is armed until its owner is consumed.** Each name after `own` in the clause is an owner it consumes. From a statement outside the clause that consumes it, the clause no longer runs (after `sqlite.finalize(host, own insert)` a later failure does not finalize again). A branch that consumes it and falls through disarms the clause after the `if` or `match`; a branch that leaves does not. An owner consumed on one branch only is the `@linear` rule's refusal.
- **A clause cannot leave or fail.** `try`, `fail`, `return`, a `break` or `continue` that leaves it, and a nested `on fail:` are `E_ON_FAIL`. Handle a fallible call inside: `on fail: _ = sqlite.close(host, own conn)`. The error that started the exit is the one that leaves.
- **A clause sees the values at the exit**, as Zig's `errdefer` does and Go's `defer` does not. Consuming an owner declared after the clause is `E_ON_FAIL`, one already consumed `E_LINEAR_CONSUMED`, and a new `@linear` owner left live at its end `E_LINEAR_UNCONSUMED`.
- **In a clause's reach, `try` is a declaration's value or a statement**: `const value = try f()`, `mut value = try f()`, `try f()` and `_ = try f()`. `return try f()`, `x = try f()`, `r.a = try f()`, a `try` in a call's argument and the other positions are `E_ON_FAIL`: declare the value first. A `fail value` runs the clauses before it evaluates `value`.
- **Any statement may be cleanup**, `@linear` or not.

`on fail:` is Go's `defer` limited to the failure exits, so the success path closes explicitly and sees the close's error. Each failure exit is checked as the bind-or-else it stands for, so ownership, `@linear` and error types follow that form's rules ([records](records-and-unions.md#linear-records), [C interop](c-ffi.md#opaque-handles)).

## Propagating an absent Option

In a function that returns `T?`, `const name = try expression` binds the payload when present and returns `None` from the function when absent, the exit a `case None: return None` arm makes. It stands at the same positions as the other form; in a function not returning `T?` it is `E_TRY_RETURN`. In a function declared `-> T? fails E`, `try` passes on a failure; handle an absent value with `const found = lookup(key) else:` and `return None` in its block.

```selka
# doc: expect Some(21) True
func first(values: int[]) -> int?:
    if len(values) == 0:
        return None
    return values[0]


func second(values: int[]) -> int?:
    if len(values) < 2:
        return None
    return values[1]


func sum_of_two(values: int[]) -> int?:
    const a = try first(values)
    const b = try second(values)
    return a + b


func main(out: Stream) -> int:
    print(out, sum_of_two([9, 12]), sum_of_two([9]) is None)
    return 0
```

Prefer `try` when the absent case only returns `None`; match when it must do more. `selka lint` reports a match whose `None` arm only returns `None` as `L_OPTION_TRY`, and `selka fix` rewrites it.

## Error return traces

An `Err` that reaches the end of `main`, or fails a test, says where it came from. Constructing `Err(...)` starts a trace at that construction, and a runtime operation that answers `Err` (reading a missing file) starts one at its call. Each `try` that passes the error on adds its site, and the union case it converted into; a `return` of an `Err` the statement did not construct adds the `return`. Handling with `match` or `_ =` adds nothing, so the trace describes the most recent `Err` the program made. Every build mode keeps it.

```selka
# doc: expect reading the configuration
import strings

enum AppError:
    Config(value: str)
    Usage(value: int)


func parse_port(text: str) -> int fails str:
    if strings.char_count(text) == 0:
        fail "empty port"
    return strings.char_count(text)


func read_config(text: str) -> int fails str:
    mut port = try parse_port(text)
    return port + 1


func load(text: str) -> int fails AppError:
    return try read_config(text)


func main(out: Stream) -> int fails AppError:
    print(out, "reading the configuration")
    mut port = try load("")
    return port
```

When `main` returns the `Err`, the program writes `error:` and the error as `print` renders it, then one site per line, origin first:

```console
$ selka run app.selka
reading the configuration
error: AppError.Config('empty port')
  app.selka:9:16   parse_port   Err(...) created
  app.selka:14:12  read_config  ? propagated
  app.selka:19:15  load         ? converted to AppError.Config
  app.selka:24:12  main         ? propagated
$ echo $?
1
```

`main` may fail with any error type `print` can render; an `int` error is the exit status, others exit 1. `selka test` prints the trace under a test whose value is an `Err`, and a test declared `-> Result[bool, E]` expects `Ok(True)`. A trap reports its call stack instead. The trace keeps the origin and the last 32 sites; a deeper chain reports `... 9 more entries dropped ...`. Only the error path records, so an `Ok` through `try` costs nothing extra.

## Option constructors

`Some(value)` builds the present case and a bare `None` the absent one; both take their `T?` type from context: a binding annotation, a parameter, a record field or the enclosing function's return type. `Some(value)` with no context is `E_OPTION_INFERENCE`; outside an Option context `None` is the unit value a procedure returns. Take an option apart with `case Some(value)` and `case None`.

An option of ordinary data may be ignored, unlike a `Result`: the standard library returns `T?` for a lookup that found nothing and `Result[T, E]` for an operation that failed. `parse_int(text)` and `parse_float(text)` return options (`None` unless the text is exactly one number).

```selka
# doc: expect 47
func lookup(values: int[], index: int) -> int?:
    if index < 0 or index >= len(values):
        return None
    return Some(values[index])

func main() -> int:
    mut values = [10, 20, 30]
    mut total = 0
    match lookup(values, 1):
        case Some(value):
            total = total + value
        case None:
            total = total - 1
    mut missing: int? = lookup(values, 9)
    match missing:
        case Some(value):
            total = total + value
        case None:
            total = total + 5
    mut parsed = parse_int("22")
    match parsed:
        case Some(value):
            total = total + value
        case None:
            total = total - 1
    return total
```

## Contextual empty constructors

An empty `[]`, an empty `{}`, `Ok(...)` and `Err(...)` take their type from where they are written: an annotated binding, a record field, a list element, a concrete call argument or the function's declared result. So `Batch(names=[], counts={})` builds a record of a `str[]` and a `dict[str, int]`, and `return Err("empty")` names no types. An expected `int[][]` pushes its element type into an inner `[]`. With no expected type, `[]` is `E_LIST_INFERENCE` and `Ok` or `Err` is `E_RESULT_INFERENCE`.

```selka
# doc: expect 9
import strings

record Batch:
    names: str[]
    counts: dict[str, int]

func empty_batch() -> Batch:
    return Batch(names=[], counts={})

func first(values: int[]) -> int fails str:
    if len(values) == 0:
        fail "empty"
    return values[0]

func main() -> int:
    mut batch = empty_batch()
    append(mut batch.names, "alpha")
    batch.counts["alpha"] = 3
    mut pending: int[] = []
    mut total = 0
    match first(pending):
        case Ok(value):
            total = total + value
        case Err(message):
            total = total + strings.char_count(message)
    return total + len(batch.names) + batch.counts["alpha"]
```

A module's own function named `Ok` or `Err` is called instead; contextual constructors never shadow it. A bare `len(...)`, `sum(...)` or `abs(...)` is always the builtin: a module function with such a name is `E_BUILTIN_FUNCTION_NAME` (its repair renames it) when its own module calls it bare, and accepted when other modules reach it only by qualified name (`zipfile.write(...)`).

## Comparing with a constructor

The operand beside `==` or `!=` supplies a type: `Some(...)`, `Ok(...)` and `Err(...)` take the type of the other operand, in either order. It is checked first, so `lookup(values, 1) == Some(20)` needs no temporary. `None` is not a comparison operand: use `value is None` (`value == None` is `E_OPTION_COMPARISON_REMOVED`). Two operands that both wait for a type, such as `Some(1) == Some(1)`, are `E_OPTION_INFERENCE`. Chains use the same inference; shared operands evaluate once, left to right, and a false link skips the rest.

```selka
# doc: expect 4
func lookup(values: int[], index: int) -> int?:
    if index < 0 or index >= len(values):
        return None
    return Some(values[index])

func main() -> int:
    mut values = [10, 20, 30]
    mut score = 0
    if lookup(values, 1) == Some(20):
        score += 1
    if lookup(values, 2) is not None:
        score += 1
    if lookup(values, 9) is None and parse_int("5") == Some(5):
        score += 1
    if Some(20) == lookup(values, 1) == Some(20):
        score += 1
    return score
```

## Builtin list and result types

`T[]` and `Result[T, E]` are part of the prelude: no declaration, no import. They work in annotations, fields, parameters, return types, exported signatures and generic type parameters. A module that declares its own `List` or `Result` keeps that identity inside the module; other modules resolve the prelude one.

```selka
# doc: expect 12
import strings

func head[T](values: T[]) -> T fails str:
    if len(values) == 0:
        fail "empty"
    return copy(values[0])

func main() -> int:
    mut numbers: int[] = [7, 8, 9]
    mut words: str[] = ["alpha"]
    mut total = 0
    match head[int](numbers):
        case Ok(value):
            total = total + value
        case Err(message):
            total = total - strings.char_count(message)
    match head(words):
        case Ok(word):
            total = total + strings.char_count(word)
        case Err(message):
            total = total - strings.char_count(message)
    return total
```

`head[int](numbers)` gives the type argument explicitly and `head(words)` infers it.

## Canonical prelude types

`list`, `dict`, `str`, `bytes`, `Option` and `Result` have one nominal identity across a project's modules: a `Result[str, str]` returned by an imported module is the same type as one built locally, and no module is imported to line signatures up. A module-local type with one of these names shadows the prelude type inside that module only. A bare call `list(...)` or `str(...)` is always the prelude function (`E_BUILTIN_FUNCTION_NAME` for a module function of that name that its own module calls bare). Calling `strings.encode(text)` without ever writing `bytes` is `E_COLLECTION_METHOD` until an annotation or signature names the type.

```selka
# doc: expect 6
import dicts
import strings

func summarise(counts: dict[str, int]) -> str fails str:
    if len(counts) == 0:
        fail "no counts"
    mut names: str[] = list(dicts.keys(counts))
    return copy(names[0])

func main() -> int:
    mut counts: dict[str, int] = {"lang": 4}
    mut total = 0
    match strings.find("selka", "lka"):
        case Some(index):
            total = total + index
        case None:
            total = total - 1
    match summarise(counts):
        case Ok(name):
            mut raw: bytes = strings.encode(name)
            total = total + len(raw)
        case Err(message):
            total = total - strings.char_count(message)
    return total
```

## The one fallible signature

A function that can fail declares it with `fails`: `-> T fails E`. `Result[T, E]` is a value type (a local, parameter or field), not a return clause. Writing `-> Result[T, E]` is `E_RESULT_RETURN_REMOVED`; `selka fix` rewrites the clause and each `return Ok(...)`/`return Err(...)` to `return ...`/`fail ...`.

```selka
# doc: expect 3
func count(text: str) -> int fails str:
    if text == "":
        fail "empty"
    return len(text)

func main() -> int:
    mut size = 0
    match count("abc"):
        case Ok(value):
            size = value
        case Err(_):
            size = -1
    return size
```

## Related pages

[Records, unions and enums](records-and-unions.md), [Python-style application code](python-syntax.md), [Standard library](standard-library.md), [Printing, files and command-line authority](io.md), [Managed byte strings](bytes.md).

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/results-and-options.md).
