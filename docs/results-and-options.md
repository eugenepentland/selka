# Results and options

A fallible function declares its successful type and error separately:
`func parse(text: str) -> Point fails ParseError`. `return point` succeeds;
`fail error` returns a declared failure. Calling it produces a checked result
that must be handled, stored or transferred according to the result rules.
`try parse(text)` extracts success and propagates compatible failure from the
enclosing fallible function.

An optional value is written `T?` and represents a value or `None`.
Absence is ordinary data; it carries no result handling obligation. Return or
assign a `T` directly where `T?` is expected. Presence guards narrow locals,
and explicit matching remains available for both optional and result values.
Stored results may still be typed as `Result[T, E]`, and rare nominal `result`
declarations preserve their existing identities.

## Flow-sensitive Option guards

`value is None` and `value is not None` test an Option's tag. When a branch establishes
that a local Option is present, reads of that binding use its payload type. An early
return from the absent branch leaves the payload available on the continuing path.
`value is Some` and `result is Ok` test the other cases the same way, and `if value is Some(item):` binds the payload for the
branch's body; see [testing one case with `is`](match-expressions.md#testing-one-case-with-is).

`const value = lookup(key) else:` followed by a block that returns, fails, breaks or continues unwraps an Option or a Result
and leaves when it is the failing case; use it when the exit does something `try` cannot, and `try` when the failure leaves
unchanged. See [bind or else](statements.md#bind-or-else).

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

Facts follow `if`/`else`, `not`, and short-circuit `and`/`or`, in ordinary and generic
functions. A `while value is not None` guard establishes presence inside its body.
After a join, a fact survives only if every continuing branch preserves it. Reassigning
the binding invalidates its fact; loop bodies are checked with assignments from later
iterations in mind, and a loop that might never run establishes no new fact afterwards.

The declared binding remains an Option. Assign `None` or a payload value to replace a writable optional local;
an annotated destination or parameter expecting that same Option type receives the
original wrapper. Repeated `is None` tests and explicit `match` also see the wrapper.
Narrowed record field and collection updates preserve the wrapper.

Only local bindings are refined. A test of `box.item` evaluates that expression once,
but does not establish a fact about later reads of the field. Copy a copyable
Option into a local first when an independent value is needed for refinement. Presence tests on wrappers
carrying an owned value or a checked `Result` are rejected; use `match` to preserve
their handling obligations.

This initial implementation lowers guards and payload reads through existing variant
dispatch, including a defensive trap for an invalidated payload projection. It does
not promise redundant-check elimination or prove integer bounds.

## Option methods

`T?` answers one intrinsic method: `unwrap_or(default: T) -> T` returns the payload or
the default. It is pure and allocates nothing, so a `noalloc` ceiling accepts it, and it
works in a generic body whose parameter is a `T?`. Its default is checked against the
payload type, and an integer literal adopts that type exactly as it does in a binding,
so a `u8` payload makes `unwrap_or(7)` a `u8` default.

Presence has one spelling: `value is None` and `value is not None`. The removed
comparisons `value == None` and `value != None` (`E_OPTION_COMPARISON_REMOVED`) and methods
`value.is_none()` and `value.is_some()` (`E_OPTION_METHOD_REMOVED`) name that test in
their message, and `selka fix` rewrites a standalone comparison or method call to it.
Inside a comparison chain the rewrite would re-parse as a chain, so the diagnostic
stays and the site is a hand migration.

```selka
# doc: expect-error E_OPTION_COMPARISON_REMOVED
func parse(text: str) -> int?:
    return parse_int(text)

func main() -> int:
    if parse("2") == None:
        return 1
    return 0
```

```selka
# doc: expect-error E_OPTION_METHOD_REMOVED
func parse(text: str) -> int?:
    return parse_int(text)

func main() -> int:
    if parse("2").is_none():
        return 1
    return 0
```

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

This returns `47`: the absent parse takes the literal default `7`, the present list head
takes `40`, the `is None` test is false for the present `parse("2")`, and the `is not
None` test adds `width("0")`, which is `0`. The receiver may be a named binding or any
expression, and a binding already narrowed by `is None` answers `unwrap_or` with its
payload.

`unwrap_or` also takes the option as its first argument, as every stage-2 prelude
operation takes its receiver: `unwrap_or(value, default)`. The two spellings mean the
same thing and accept the same default, so a call reads left to right without a
receiver chain.

```selka
# doc: expect 13
func parse(text: str) -> int?:
    return parse_int(text)

func main() -> int:
    mut total = parse("nope").unwrap_or(7)
    total = total + parse("6").unwrap_or(0)
    return total
```

An `Option`
carrying an owned value or a checked `Result` still needs explicit `match`; a mismatched
default is `E_TYPE` and names the payload type it expected. The `sentinel-int` lint
reports the older convention — a function returning `-1` on one path whose result a
caller tests against a negative literal — and names this rewrite.

## Checked results

`Result[T, E]` is a two-case value: `Ok(value)` carries the success payload and
`Err(payload)` carries the failure payload, which may be any value type — a `str`, an
`int`, an enum or a record. A result-bearing value may not simply be dropped. Every path
out of a scope must have matched it exhaustively, returned it, passed it on, or released
it explicitly with `_ = value`; anything else is rejected with `E_RESULT_UNHANDLED`,
which points at the binding that holds the result and notes the scope exit (an early `return`, say)
that left it pending. The obligation
travels with the value, so reading a result-bearing binding transfers the obligation
rather than duplicating it, and a record or union field holding a result keeps the
obligation for the whole wrapper.

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

The `match` above discharges the first result. The program is still rejected, because
`ignored` reaches the end of `main` unhandled; writing `_ = divide(1, 0)` instead accepts
the failure explicitly and checks cleanly. Results describe errors a caller can recover
from. A violated invariant is not one: `assert` traps, and so do arithmetic overflow and
host failures, none of which turn into an `Err`.

A call of a function declared `fails` answers a `Result`, not its success value, so `2 + parse("1")`, `show(parse("22"))` and
`mut n: int = parse("333")` are `E_TYPE` ("expected int, found Result[int, str]"). When the value is a direct call of such a function the
message names it and the two ways out: ``write `try parse(...)` `` to take the value and pass the error on (the enclosing function
declares the same `fails`, and `selka fix` writes the `try `), or ``handle it with `const n = parse(...) else Err(e):` ``. A function
with no `fails` clause gets the second, or the clause to declare. The same holds for a call used as a condition (`if ok("h"):`), under
`not` or `-`, and beside an operator. A `Result` held in a variable keeps the plain message, and so does a call where `try` is refused (a
contract condition, a lambda, a `detach` loop, a function with an `on fail:` clause).

### Explicit results across module boundaries

An explicit `Result[T, E]` is ordinary checked-result syntax. When the error is
an enum from another module, the annotation and the pattern use the imported
name, and the constructor names its case; this is the shape a standard module's
fallible API uses. `Ok` and `Err` are still the only constructors.

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

Use `try operation()` wherever a value is computed at run time: a declaration initializer,
an assignment value (to a name, a field, an element or a nested place, `=` or `+=` and the other compound forms,
see [`try` as the value of an assignment to a place](#try-as-the-value-of-an-assignment-to-a-place)),
a `return` or `fail` value, a standalone operation, a resource
head such as `with try open(...) as file:`, an argument of a call (see
[`try` in a call's arguments](#try-in-a-calls-arguments)), or an operand of any expression (see
[`try` in an operand](#try-in-an-operand)). `try` takes the call after it, with its `.`, `[]` and call
suffixes, and an operator after it takes the call's value: `try f() + 1` is `(try f()) + 1`. A `try` over
an operator expression (`try (a + b)`, `try -f()`) is refused with `E_TRY_POSITION`: write the operator
outside it. So is a `try` in a value computed when the program is compiled, a module constant or a default
of a parameter or field: call the function where the value is needed.
`return try other()` forwards the successful value and compatible failure.

The enclosing function must declare a compatible failure type. An error of
another type converts into the enclosing error union when exactly one of its
cases can carry it: a case whose payload is that type, or a case with one named
field of that type. When two or more cases can, `try` is refused with
`E_ERROR_CASE_AMBIGUOUS`, because the order of the cases would choose the error
the program reports; see [converting into one case](#converting-into-one-case).
Unrelated errors do not widen implicitly. Propagation releases the scopes it exits, including open files,
just as `return` and `fail` do. The `?` suffix belongs to optional types.

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

This returns `37`: `21` from the successful path, and `16` — the length of the propagated
message — from the failing one. `average` never mentions the error case, which is the
point of the form. `with try open(fs, path, mode) as f:` is propagation at a `with`
head; see [printing, files and command-line authority](io.md).

### `try` as the value of an assignment to a place

`r.a = try f()`, `xs[i] = try f()`, `rows[i].inner.name = try f()`, `d[key] = try f()`, a field of a `match mut`
binding and the compound forms (`total.count += try f()`) mean what `const value = try f()` followed by the assignment
means, in the order an ordinary assignment to that place uses:

- for `=`, the call under `try` runs first, then the place's own index and key expressions, left to right;
- for a compound form, the place's index and key expressions run first, then the call under `try`;
- if the call fails, the function leaves with its error there and the place is not written; what a `mut` argument
  of the call already wrote (the record itself, lent to the call) stays written, as in the two-statement form.

A `@linear` owner held across the `try` and a `@linear` field the assignment would replace are refused as in the
two-statement form (`E_LINEAR_UNCONSUMED`, `E_LINEAR_USE`). In the reach of an `on fail:` clause the clauses would not
run on this `try`, so it is `E_ON_FAIL` there, as `x = try f()` is: declare the value first
(see [cleanup on failure](#cleanup-on-failure)).

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

This returns `12`: `4 + 7` from the whole header, and `1 + 0` from the cut one, whose `sizes[0]` the failing `try`
left unwritten.

### `try` in a call's arguments

`try CALL` may be an argument of a call: positional or by keyword; of a function, a record
constructor (`Row(size=try parse(text))`), a builtin (`len(try load())`) or a call on a module,
a handle or an option (`f.write(try encode(x))`); at any depth (`a(b(try c()))`); in any
statement, a `while` or `elif` condition included. The program means what it says, read left to right:

- the arguments written before the `try` are evaluated first, then the call under `try`;
- if that call fails, the function leaves with its error there: the arguments after the `try` are not
  evaluated and the call it is an argument of does not happen;
- whatever the earlier arguments made (a list, a text, a record) is destroyed once, as on any other exit;
- a `try` in a `while` condition runs on every test, and one in an `elif` condition only when that
  condition is tested, as the rest of the condition does.

The values the call would have received meet the failure path this way:

- **A name passed `own`** before the `try` is not given away, because the call does not happen: it is
  destroyed once as the function leaves.
- **A `mut` argument** is only lent to the call, so nothing happens to it; what an earlier argument
  already wrote through a `mut` of its own stays written.
- **A `@linear` owner** given away before the `try` (`use(own token, try check(n))`) would be lost on
  the exit: that is `E_LINEAR_UNCONSUMED` at the `try`, as `const value = try check(n)` written before the
  call is. A `@linear` name still held when the `try` fails is the same refusal. Declare the value
  first and end the owner on the failure path with `on fail:`.
- **An `on fail:` clause** does not run on a `try` in an argument: in the reach of an armed clause that
  `try` is `E_ON_FAIL`, and the value is declared first (see [cleanup on failure](#cleanup-on-failure)).
- **A `Result` an earlier argument made and nothing handled yet** would be dropped: `E_RESULT_PROPAGATION`.

A contract condition (`@requires`, `@ensures`) cannot leave early, so a `try` in one is `E_CONTRACT_EFFECT`.

```selka
# doc: expect 10
func note(mut log: int[], n: int) -> int:
    append(mut log, n)
    return n

func checked(mut log: int[], n: int) -> int fails str:
    append(mut log, 10 + n)
    if n > 1:
        fail "too big"
    return n

func add3(a: int, b: int, c: int) -> int:
    return a + b + c

func run(n: int, mut log: int[]) -> int fails str:
    return add3(note(mut log, 1), try checked(mut log, n), note(mut log, 3))

func main() -> int:
    mut log: int[] = []
    mut total = 0
    match run(1, mut log):
        case Ok(value):
            total += value
        case Err(_):
            pass
    # The second run notes 1, fails in `checked` and leaves: 3 is not noted and `add3` is not called.
    match run(2, mut log):
        case Ok(_):
            pass
        case Err(_):
            total += len(log)
    return total
```

This returns `10`: `5` from the first run, and `5` entries in the log (`1`, `11`, `3` from the
first run, `1`, `12` from the second). The same lines written with each `try` declared on a line of
its own mean the same where nothing before the `try` in the statement has an effect.

### `try` in an operand

`try CALL` may be an operand of any expression computed at run time: arithmetic and comparisons
(`try read(b) + 257`, `try next(r) != 0`), `and`, `or` and `not`, an index or a slice bound, an element
of a list or dictionary literal, a format string's hole, a constructor's field value, the condition of
`if`, `elif`, `while` and `assert` and an `assert`'s message, a `match` subject, the list a `for` walks,
and a `return` or `fail` value. The order is the order of the same expression without `try`:

- the operands are evaluated left to right; the values to the left of a `try` are made and held before
  its call runs;
- if the call fails, the function leaves with its error there: nothing to the right of the `try` is
  evaluated, and what the operands to its left made is destroyed once;
- under `and` and `or` a `try` on the side that is not evaluated does not run; a `try` in a `while`
  condition runs on every test, one in an `elif` condition only when that condition is tested, and one in
  an `assert`'s message only when the assertion fails.

A `try` that begins the value of `a if p else b` covers the whole conditional, as it always has. A
`@linear` owner, a pending `Result`, an armed `on fail:` clause and a `detach` loop meet a `try` in an
operand as they meet one in an argument (above): the same refusals, with the same messages.

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

This returns `9`: `4` from the first run (`1 + 1 * 3`, its log `11`, `1`, `11`, `3`), `0` from the
second, and the `5` entries of the log after the third.

### Converting into one case

When exactly one case of the enclosing error union can carry the propagated error type,
that case is the conversion. The wrapped error keeps its own identity inside the
payload, so a caller can recover the category and the detail:

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

`convert(True)` propagates `Err("no value")` without a translation helper: the `str`
becomes the payload of `AppError.Detail`, so `rate(True)` returns `8` and the program
prints `20`. A propagated error type that is not a case payload of the enclosing union
still fails with `E_TYPE`.

`fail value` converts the same way, and only the same way. When two or more cases can
carry the error, neither `try` nor `fail` picks one: reordering the cases would then
change the error a program reports in another function. Both are refused with
`E_ERROR_CASE_AMBIGUOUS`, whose message lists the cases that fit in declaration order:

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

Name the case instead. For `fail value`, write the constructor, `fail AppError.Parse(value="empty")`;
the diagnostic carries that edit, naming the first case that fits, which is the case the compiler
chose before the rule, so `selka fix` moves old code across and a reader checks that it is the case
meant. A `try` has no certain edit: match the result and fail with the case in the `Err` arm. The
new `fail` starts the error's trace there, where a converting `try` would have appended its site:

```selka
# doc: expect 6
enum AppError:
    Parse(value: str)
    Io(message: str)


func parse(text: str) -> int fails str:
    if len(text) == 0:
        fail "empty"
    return len(text)


func load(text: str) -> int fails AppError:
    match parse(text):
        case Ok(size):
            return size
        case Err(error):
            fail AppError.Parse(value=own error)


func main() -> int:
    match load(""):
        case Ok(size):
            return size
        case Err(error):
            match error:
                case Parse(value=text):
                    return len(text) + 1
                case Io(message=text):
                    return 0
```

### Optional absence

Optional absence is handled with a presence guard or `match`. A local known to
be present exposes its payload type; return `None` explicitly for the absent path.

```selka
# doc: expect 4
record Node:
    value: int
    left: Node?


func left_value(node: Node) -> int?:
    const child = copy(node.left)
    if child is None:
        return None
    return child.value


func main() -> int:
    mut leaf = Node(value=4, left=None)
    mut root = Node(value=1, left=Some(copy(leaf)))
    return left_value(root).unwrap_or(0) + left_value(leaf).unwrap_or(0)
```

## Cleanup on failure

`on fail: STATEMENT`, or `on fail:` and an indented block, registers cleanup for the failure exits after it: each `try`
whose error leaves the function, and each `fail`, to the end of the block that holds the clause (nested blocks, loop bodies
and `match` arms included). On such an exit the clauses that are armed there run, the latest first, and then the error
leaves. Nothing runs on the success path: a `return`, the end of the function or a loop's `break` leaves the clauses
alone, so the ordinary code still ends what it opened. A trap runs no clause; it ends the process.

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

The rules, in the order a reader meets them:

- **Only a function that fails holds one.** `on fail:` in a function without `fails` is `E_ON_FAIL`: it could never run.
  One that no failure exit reaches (none follows it while it is armed) is `E_ON_FAIL` too.
- **A clause is armed until its owner is consumed.** Each name after `own` in the clause is an owner it consumes. From
  the statement that consumes one of them outside the clause, the clause no longer runs: after
  `sqlite.finalize(host, own insert)`, a later failure does not finalize again, and `try sqlite.close(host, own conn)`
  does not close a second time when the close itself fails. A branch that consumes the owner and falls through disarms
  the clause after the `if` or `match`; a branch that leaves (`return`, `fail`, `break`, `continue`) does not. An owner
  consumed on one branch only is the `@linear` rule's refusal, as without a clause.
- **A clause cannot leave or fail.** `try`, `fail`, `return`, a `break` or `continue` that would leave it, and a nested
  `on fail:` are `E_ON_FAIL`. A fallible call is handled in the clause, `on fail: _ = sqlite.close(host, own conn)` or a
  `match` that reports it: the error that started the exit is the one that leaves.
- **A clause sees the values at the exit.** It runs where the exit is, with the current values of the names it reads
  (as Zig's `errdefer` does, unlike Go's `defer`, whose arguments are fixed when it is written). A clause that consumes an
  owner declared after it is `E_ON_FAIL`; one that consumes an owner already consumed is `E_LINEAR_CONSUMED`; a new
  `@linear` owner left live at its end is `E_LINEAR_UNCONSUMED`.
- **In a clause's reach, `try` is a declaration's value or a statement.** `const value = try f()`, `mut value = try f()`,
  `try f()` and `_ = try f()` run the clauses; `return try f()`, `x = try f()`, `r.a = try f()`, `xs[i] = try f()`
  and the other boundary positions are
  `E_ON_FAIL` there: declare the value first. So is a `try` in a call's argument while a clause is armed. A
  `fail value` runs the clauses before it evaluates `value`.
- **It is not only for `@linear` values.** Any statement may be cleanup: a rollback, a log line, a counter.

Next to Python and Go: Python writes `try:` ... `except: conn.close(); raise`, or `with closing(conn):`, which closes on
every exit; Go writes `defer conn.Close()`, which also runs on every exit and usually drops the close's error. `on fail:`
is Go's `defer` limited to the failure exits, so the success path closes explicitly and sees the close's error. Each
failure exit in a clause's reach is checked as the bind-or-else it stands for (`const value = f() else Err(e):`, its
`else` block the clauses and `fail e`), so ownership, `@linear` and the error types follow the rules of that form
([records](records-and-unions.md#linear-records), [C interop](c-ffi.md#opaque-handles)).

## Propagating an absent Option

`try` also unwraps an Option. In a function that returns an Option, `const name = try expression` binds the
payload when the Option holds one and returns `None` from the function when it does not, the same exit a
`case None: return None` arm makes. It stands at the same statement boundaries as the other form (an initializer, an
assignment value, a `return` value or a standalone operation), and the enclosing function must return an Option
(`-> T?`); in any other function `try` on an Option reports `E_TRY_RETURN`. A function that returns a `Result`
propagates failures with the form above. That includes a function declared `-> T? fails E`, whose result is a
`Result` with an Option inside: there `try` passes on a failure, and an absent value is handled with
`const found = lookup(key) else:` and `return None` in its block (`return lookup(key)` when the Option is the result).

A chain of lookups that gives up at the first absent value stays flat. Without `try`, each step nests the rest of the
function one match deeper:

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

Prefer `try` when the absent case only returns `None` from the function, as `sum_of_two` does. When it must do
something else (print a diagnostic and return a status, skip to the next loop iteration), match the Option.
`selka lint` reports a match whose `None` arm only returns `None` as `L_OPTION_TRY`, and `selka fix` rewrites it.

## Error return traces

An `Err` that reaches the end of `main`, or fails a test, says where it came from.
Every program keeps one error return trace, in every build mode and on both
backends: constructing an `Err(...)` value starts a fresh trace at that construction,
and a runtime operation that answers `Err` — reading a missing file, say — starts one
at its call. After that, each `try` that passes the error on adds its site, and says
which union case it converted the error into when it wrapped it; a `return` of an
`Err` the statement did not construct itself — a variable or a call's result —
adds the `return`. Handling an error with `match` or `_ =`
adds nothing, so the trace always describes the most recent `Err` the program made.

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

When `main` returns the `Err`, the program writes `error:` and the error, rendered as
`print` renders it, then one line per site, the origin first:

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

`main` may fail with any error type `print` can render. An `int` error is still the
exit status; any other error exits 1. `selka test` prints the same trace under a
test whose value is an `Err`, and a test declared `-> Result[bool, E]` expects
`Ok(True)`, so it can use `try` and fail with the trace of the error it propagated.
A trap is reported as before, with its call stack instead.

The trace keeps the origin and the last 32 sites after it. A deeper chain, such as
a recursive descent, reports how many sites in between were dropped:
`... 9 more entries dropped ...`. Each site is a function's position table and an
instruction index the compiler already emits, so no text is built while the
program runs. Recording a site is one call to a small runtime recorder, on the
error path only: an `Ok` passing through `try`, and a
`return Ok(...)`, execute nothing extra. A `return` whose value could be either
case tests the returned case once. In an LLVM build the recorder keeps every
register but one intact, so a recording does not make an optimized loop spill
and reload the values it holds in registers.

## Option constructors

`T?` represents a value that may be absent. `Some(value)` builds the present case
and a bare `None` builds the absent one, and both take their `T?` type from the
surrounding context: a binding annotation, a parameter, a record field or the enclosing
function's return type. `Some(value)` with no such context is rejected with
`E_OPTION_INFERENCE`, and outside an `Option` context `None` is the ordinary unit value a
procedure returns, not an empty option. Take an option apart with `case Some(value)` and
`case None`. An option carrying only ordinary data has no handling obligation, so it may
be ignored or discarded; that is the difference from a `Result`, and the reason the
standard library returns `T?` for a lookup that found nothing and `Result[T, E]`
for an operation that failed.

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

This returns `47`. `parse_int(text)` and `parse_float(text)` return options for the same reason: text
that is not exactly one number answers `None` instead of raising.

## Contextual empty constructors

An empty `[]`, an empty `{}`, `Ok(...)` and `Err(...)` carry no type of their own. Each
takes the type it needs from the place it is written: an annotated binding, a record
field, a list element, a concrete call argument, or the enclosing function's declared
result. This is what lets `Batch(names=[], counts={})` construct a record whose fields
are a `str[]` and a `dict[str, int]`, and lets `return Err("empty")` name no types at
all. Where no expected type reaches the expression the compiler says so rather than
guessing: a contextless empty list is rejected with `E_LIST_INFERENCE` and a contextless
`Ok` or `Err` with `E_RESULT_INFERENCE`. Nesting works, so an expected `int[][]`
pushes its element type into an inner `[]`.

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

This returns `9`. A module that declares its own function named `Ok` or `Err` calls that
function instead; the contextual constructors never shadow a declaration you wrote. The
prelude's functions work the other way round: a bare `len(...)`, `sum(...)` or `abs(...)` is
always the builtin. A module function with such a name is refused at its declaration when its
own module calls it bare (`E_BUILTIN_FUNCTION_NAME`, whose repair renames it), and is accepted
when other modules reach it only by its qualified name, such as `zipfile.write(...)`.

## Comparing with a constructor

The operand beside `==` or `!=` is a place that supplies a type too. `Some(...)`,
`Ok(...)` and `Err(...)` take the type of the other operand, in either order, whatever
that operand is: a local, a field, a call, a method call or a `parse_int(text)`
conversion. The other operand is checked first, so `lookup(values, 1) == Some(20)` needs
no temporary binding. `None` is not a comparison operand: presence is the identity test
`value is None`, and `value == None` is `E_OPTION_COMPARISON_REMOVED`. Two operands that both
wait for a type, such as `Some(1) == Some(1)`, still have nothing to infer from and are
rejected with `E_OPTION_INFERENCE`. Each equality link in a comparison chain uses the
same inference, including in generic bodies. Shared operands evaluate once, left to
right, and a false link skips the remaining operands.

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

`T[]` and `Result[T, E]` are part of the prelude. They need no `record` declaration
and no import, they are spellable in annotations, record fields, parameters, return types
and exported module signatures, and they use the same managed-list and checked-result
semantics as everything else on this page. Both work under generic type parameters, so a
generic function can build a `T[]` or an `Ok(value)` whose payload type is still
symbolic. A module that declares its own `List` or `Result` type keeps its own nominal
identity inside that module, and unrelated modules continue to resolve the prelude one.

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

This returns `12`. `head[int](numbers)` supplies the type argument explicitly and
`head(words)` infers it; both reach the same instance.

## Canonical prelude types

`list`, `dict`, `str`, `bytes`, `Option` and `Result` have exactly one nominal identity
across every module of a project. A `Result[str, str]` returned by an imported module is the same type as one
built locally, so no project imports a prelude module to make its signatures line up, and
`case Ok(...)` reads a standard-library result the same way it reads yours. The identity
is shared, not ambient: `bytes` and `float` are registered wherever their names appear in
source, so a program that calls `strings.encode(text)` without ever writing `bytes` is rejected
with `E_COLLECTION_METHOD` until an annotation or signature names the type. A module-local
type declaration with one of these names shadows the prelude type inside that module alone. A
function is different: a bare call `list(...)` or `str(...)` is always the prelude function, so
a module function with that name is refused when its own module calls it bare
(`E_BUILTIN_FUNCTION_NAME`).

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

This returns `6`. `strings.find` returns the prelude `int?` and `summarise`
returns the prelude `Result[str, str]`, and neither declaration nor import mentions a
prelude module.

## The one fallible signature

A function that can fail declares it with `fails`: `-> T fails E`. `Result[T, E]` is a
value type — a result held in a local, a parameter, a field or a record — not a return
clause. Writing `-> Result[T, E]` is `E_RESULT_RETURN_REMOVED`; `selka fix` rewrites
the clause and each `return Ok(...)`/`return Err(...)` to `return ...`/`fail ...`, so
a call answers the same checked result as before.

```selka
# doc: expect-error E_RESULT_RETURN_REMOVED
func broken(text: str) -> Result[int, str]:
    return Ok(1)
```

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

- [Records, unions and enums](records-and-unions.md) — the declared types these wrap
- [Python-style application code](python-syntax.md) — the surrounding syntax
- [Standard library](standard-library.md) — which module functions return `Option` and which return `Result`
- [Printing, files and command-line authority](io.md) — file helpers returning `Result[T, str]`
- [Managed byte strings](bytes.md) — `decode` and `fromhex` as checked results
