# Functions and calls

`func` declares every callable. There are no methods, inheritance, nested definitions or closures, so a call's meaning follows from the declaration its name resolves to. This page covers how a call supplies arguments, what a function may return, and function values. [Statements and bindings](statements.md) covers bodies; [Python-style application code](python-syntax.md) is the wider tour.

## Keyword arguments and defaults

A call passes arguments positionally, by keyword or both, with every positional argument before the first keyword. Keywords may name parameters in any order, and arguments are evaluated once, in the order they are *written*. A default must be an immutable scalar literal (a number, `True` or `False`, a string or `None`), and required parameters precede defaulted ones; the other order is `E_DEFAULT_ARGUMENT`, and so is an enum case, record value or empty collection as a parameter default (a record *field* may default to those: [enum and record defaults](records-and-unions.md#enum-and-record-defaults)). Unknown, duplicate, missing, excess and misplaced arguments are rejected, and a default's type is checked even in an uncalled function. Intrinsics such as `len` have their own argument rules.

```selka
# doc: expect 42
func offset(value: int, amount: int = 2, scale: int = 1) -> int:
    return value * scale + amount

func main() -> int:
    mut plain = offset(38)
    mut keyword = offset(amount=2, value=38)
    if plain != keyword:
        return 1
    return plain + offset(0, scale=2)
```

Record construction binds fields by name by the same rules (`Point(x=1, y=2)`).

### Keyword-only parameters

Mark each parameter that requires a label with `named`: `named amount: int` (repeat the modifier per parameter; there is no bare `*`). Positional parameters come first, then named ones, which may be supplied in any order; required and defaulted named parameters may mix. A missing label is `E_KEYWORD_ONLY`, and the message writes the labelled call. `named mut points: Point[]` is called with `points=mut points`: name and mutation permission are both part of the contract, and rendered interfaces repeat `named` and prefix `mut`.

```selka
# doc: expect 1204
func issue(host: int, named code: int, named file: int = 0, named position: int = 4) -> int:
    return host * 1000 + code * 100 + file * 10 + position


func main() -> int:
    mut written = issue(1, position=4, code=2)
    mut defaulted = issue(1, code=2)
    if written != defaulted:
        return 0
    return written
```

### Owned parameters

A parameter has one of three modes, visible at the declaration and at every call: a plain parameter reads its argument; `mut` writes the caller's value; `own` takes it, so the caller's binding is unusable after the line and the callee may store, return or move it without a copy.

```selka
# doc: expect 3
record State:
    keys: int[]


func order_by_key(own keys: int[]) -> State:
    return State(keys=own keys)


func main() -> int:
    mut samples = [1, 2, 3]
    const ordered = order_by_key(own samples)
    return len(ordered.keys)
```

The marker belongs at every move of a named managed value, inside the callee too: `State(keys=own keys)`, `const saved = own keys`; `const saved = keys` borrows read-only. A bare `return keys` needs no marker, but named inputs inside a returned constructor do. At a call, `own` is required where an owning parameter takes a named managed value; fresh values (call results, constructors, literals, `copy(value)`, operator results) and scalars never take it. A missing or misplaced marker is `E_OWN_MARKER`. `own` and `mut` do not combine, and a function type spells the mode: `func(own int[]) -> int`. `own state.keys` consumes the whole record; `copy(state.keys)` keeps it.

The library's storing functions take their element `own` (`sets.add(mut seen, own word)`, `dicts.append_to(mut groups, key, own item)`), and `append(mut rows, row)` is refused with a repair that writes `own row`. Stores that copy a key only when it is new take it borrowed (`groups[key] = items`, `sets.include(mut seen, word)`, `dicts.add(mut counts, word, 1)`); an `own` there is refused, and `selka fix` removes it. That is the language's one implicit copy, labelled "implicit (dictionary key)" by `selka cost FILE --sites` ([cost](tooling/cost.md#allocation-and-copy-sites)). A name that only borrows (a plain parameter, loop variable, match payload, element read or slice binding) is not given away: write `copy(...)`.

A plain parameter may not take a move-only value (a resource such as `network.Listener`, or a record holding one): `E_OWN_PARAMETER`, repaired by writing `own` before the name. A function type refuses it the same way, and the call site then writes `own listener` (`E_OWN_MARKER`); `selka fix` takes both steps. Inside the callee an `own` parameter is destroyed at scope end when nothing else uses it, and may be written and rebound like a `mut` local, the writes staying in the callee:

```selka
# doc: expect 2
func with_item(own keys: str[]) -> str[]:
    append(mut keys, "k")
    return keys


func main() -> int:
    mut seed: str[] = ["a"]
    const built = with_item(own seed)
    return len(built)
```

A `mut` parameter is an exclusive borrow for every type, resources included; a resource the callee keeps must be `own`.

### Wide signatures

A borrowed result declares its possible sources with `from`, including parameters beyond position 64; mutable parameters and declared result sources have no 64-position limit.

## Unit procedures

A procedure produces `Unit`: write `-> Unit` or omit the return annotation. `Unit` is a builtin type name, so an application record cannot be named `Unit`; the unit value is `()`. Falling off the body or a bare `return` succeeds with unit, and cleanup runs on both. A fallible procedure writes `func save(...) fails SaveError:` and uses `fail error`; `try save(...)` propagates it. A standalone call statement must produce unit: `_ = work(...)` discards an ordinary non-unit result (checked results still need handling).

```selka
# doc: expect 42
func bump(mut values: int[]):
    append(mut values, 0)

func add(mut values: int[], value: int) -> Unit:
    if value < 0:
        return
    append(mut values, value)

func main() -> int:
    mut values: int[] = []
    add(mut values, 40)
    add(mut values, -1)
    add(mut values, 2)
    bump(mut values)
    mut total = 0
    for value in values:
        total += value
    return total
```

## Entry point signatures

`main` may return `int`, `Unit`, `int fails E` or unit with `fails E`. A successful integer is the exit status (low eight bits); successful unit exits zero. An integer error supplies its status and any other error exits one, printed to standard error with its [error return trace](results-and-options.md#error-return-traces). `selka run --print-result` also prints a successful integer.

```selka
# doc: expect 42
func parse(value: int) -> int fails int:
    if value < 0:
        fail 2
    return value

func main() -> int fails int:
    mut first = try parse(40)
    mut second = try parse(2)
    return first + second
```

## Explicit call type arguments

A generic call may state its type arguments in square brackets, `identity[int](2)`. Explicit and [inferred](generic-inference.md) arguments reach the same instance; the list is required only where inference has nothing to work from, such as a type parameter no value argument mentions. It is all or nothing: inference never completes a partial list, the return context never supplies a missing argument, and a wrong count or an undeclared base name is rejected. `f[T](...)` names a function when the base is a declared function and a generic record otherwise, so `Box[int](item=0)` stays record construction.

```selka
# doc: expect 42
func identity[T](value: T) -> T from value:
    return value

record Box[T]:
    item: T

func main() -> int:
    mut explicit = identity[int](2)
    mut inferred = identity(40)
    mut boxed = Box[int](item=0)
    return explicit + inferred + boxed.item
```

## Function values

The name of a declared function, written without a call, is a function value of type `func(parameters) -> result`, with every type written out; it can be stored, passed and returned. It captures nothing: everything it needs arrives through its parameters, and capturing the environment is rejected. Function values are ordinary copied values; a call through one keeps the ordinary result and ownership obligations. They have no rendering: passing one to `print` is `E_IO_ARGUMENT`.

A function with a borrowed result (`-> str from text`) keeps that borrow when called directly, but its name as a function value is `E_VIEW_FUNCTION_VALUE`: a `func` value must return an owned result. `selka fix` writes a copying wrapper (`head_copy`) and names it at the use.

```selka
# doc: expect 42
func double(value: int) -> int:
    return value * 2

func chosen() -> func(int) -> int:
    return double

func apply(callback: func(int) -> int, value: int) -> int:
    return callback(value)

func main() -> int:
    mut op = chosen()
    return apply(op, 18) + op(3)
```

A function value may be stored in a record field; read it into a local and call that. A direct call through the field (`handler.callback(value)`) is `E_COLLECTION_METHOD`, which names the binding spelling.

```selka
# doc: expect 42
record Handler:
    callback: func(int) -> int

func twice(value: int) -> int:
    return value * 2

func call_stored(handler: Handler, value: int) -> int:
    const callback = handler.callback
    return callback(value)

func main() -> int:
    return call_stored(Handler(callback=twice), 21)
```

## Function identity

`same_function(left, right)` compares two compatible function values without calling them: `True` for the same callable, `False` for different ones; different signatures, or a non-function, is a type error. The identity lasts only within the running program; for a persistent one see [persistent function identity](#persistent-function-identity).

```selka
# doc: expect 42
func increment(value: int) -> int:
    return value + 1

func decrement(value: int) -> int:
    return value - 1

func main() -> int:
    const chosen = increment
    if not same_function(chosen, increment):
        return 1
    if same_function(chosen, decrement):
        return 2
    return 42
```

## Callback authority

A callback's authority arrives through capability parameters: a callback that prints takes a `Stream`. Parameter and result types stay invariant, mutation positions must match, and the return-origin bound may be narrower. Function values capture no context, so pass any context explicitly.

```selka
# doc: expect 40
# doc: expect 2
# doc: expect 42
func announce(value: int, out: Stream) -> int:
    print(out, value)
    return value

func sum_announced(values: int[], report: func(int, Stream) -> int, out: Stream) -> int:
    mut total = 0
    for value in values:
        total += report(value, out)
    return total

func main(out: Stream) -> int:
    print(out, sum_announced([40, 2], announce, out))
    return 0
```

## Mutating callbacks

A callable signature declares the `mut` parameters it writes, and a call through the value substitutes the actual argument origin, so the caller still needs permission to mutate:

```selka
# doc: expect 7
func apply(mut values: int[], f: func(mut values: int[]) -> Unit) -> Unit:
    f(mut values)


func set_first(mut values: int[]) -> Unit:
    values[0] = 7


func main(out: Stream) -> int:
    mut values = [1]
    apply(mut values, set_first)
    print(out, values[0])
    return 0
```

A positional binder name is a documentation label; a `named` binder requires that call label. Its `mut` arguments must name disjoint places, as for a direct call: `f(mut xs, mut xs)` is `E_SINGLE_OWNER_OVERLAP` ([value semantics](value-semantics.md#the-rules)), with a [split repair](tooling/fix.md#structured-fixes-in-diagnostics) for simple direct calls.

## Attributes

A declaration may carry a fixed-vocabulary attribute on the line above it:

| Attribute | Effect |
|---|---|
| `@deprecated("reason")` | a call from another module reports `W_DEPRECATED` with the reason |
| `@test` | makes the function a discovered test whatever its name or `export` flag |
| `@allow("rule", reason="...")` | waives one lint rule on that declaration; a missing `reason=` is `L_WAIVER_REASON` and always blocks |

Any other `@name` is `E_UNKNOWN_ATTRIBUTE`, and repeating one kind on a declaration is `E_DUPLICATE_ATTRIBUTE`. Attributes attach to function declarations.

```selka
# doc: expect 9
@deprecated("use square_v2; removed after api_version 3")
func square(x: int) -> int:
    return x * x


@test
func square_of_three() -> bool:
    return square(3) == 9


@allow("dead-private", reason="kept for the doctest example")
func helper() -> int:
    return 1


func main(out: Stream) -> int:
    print(out, square(3))
    return 0
```

## Freestanding functions

`@freestanding` above a function promises it needs nothing from the runtime, so it can run before the runtime is up (a device's reset), when it cannot be entered (a fault, an interrupt, a Linux signal) or while its flash cannot be read. The check covers the whole body; ordinary code may call it freely. Each rule is `E_FREESTANDING` at the place that breaks it:

- **Unmanaged data only** (parameters, result, locals, expressions): integers, floats, `bool`, enums, records, unions, options and `FixedArray`s of those, `extern type` handles, and the `Registers` and `Host` capabilities. No `str`, `bytes`, list, dictionary, set, buffer, `Stream`, function value or other capability.
- **Calls only** of other `@freestanding` functions, `extern func`s (trusted C that keeps the same promise) and inline built-ins: the `registers` reads and writes (`read8` to `write32`) and the `cpu` functions `wait_for_event`, `wait_for_interrupt`, `send_event`, `barrier`, `breakpoint`, `interrupts_off` and `interrupts_restore`. The simulated bank's readers (`cpu.event_count`, `cpu.interrupts_are_off` and the rest of its log) are refused by name. No `print`, `debug`, format string, `parallel` or call through a function value.
- `fails E` with an unmanaged `E`, `try`, `match`, loops and `assert CONDITION` (no message) are allowed; a `try` records no error trace.

A failed check in one (index out of range, overflow, division by zero, failed `assert`, `unwrap` of `None`) calls nothing and builds no text in any build mode: the target's trap instruction runs (`udf #83` on `thumbv6m-none`, `ud2` on x86-64). A device reports `error[R_LIST_BOUNDS] PATH:LINE` with status 1; on x86-64 Linux a `SIGILL` handler prints the same and exits 1, and under `selka test` the test fails with the code. A freestanding function may call C by name or through an address ([calls through an address](c-ffi.md#calls-through-an-address)); a `Host` token mismatch is `R_CAPABILITY` and a null address `R_FOREIGN_TARGET`. Under `selka test` on Linux its `registers` and `cpu` calls go to the simulated bank (`registers.simulated()`).

```selka
# doc: expect 77
@freestanding
func checksum(words: FixedArray[u32, 4]) -> u32:
    mut total: u32 = 0
    for i in range(4):
        total = total + words[i]
    return bit_and(bit_xor(total, 0xED), 0xFF)


func main() -> int:
    return int(checksum(FixedArray[u32, 4]([0x10, 0x20, 0x30, 0x40])))
```

```selka
# doc: expect-error E_FREESTANDING
func plain(x: int) -> int:
    return x


@freestanding
func twice(x: int) -> int:
    return plain(x) * 2


func main() -> int:
    return twice(21)
```

### Code that runs from RAM

Flash cannot be read while it is erased or written, so that code must run from RAM. `@freestanding(ram)` places a freestanding function there (`ram` is the only placement; any other word is `E_FREESTANDING`).

- **Device** (`--target thumbv6m-none`): the code goes to the section `.ramfunc`, which the device's linker script must load into RAM: put `*(.ramfunc*)` first in the output section of the initialised data (`.data : { __data_start = .; *(.ramfunc*) *(.data*) ... } > RAM AT > FLASH`), as `scripts/bare/qemu/link.ld` does.
- **Host**: placement changes nothing.
- **At check time** a `ram` function calls only other `ram` functions, `extern func`s (whose C must be `__attribute__((section(".ramfunc")))`) and the inline built-ins; calling a plain `@freestanding` function is `E_FREESTANDING`. Any function may call a `ram` one.
- **After every device link** the build reads the image: every address a `ram` function refers to must be in RAM or outside the image's flash, including what the code generator adds (`__aeabi_uidiv`, `__aeabi_lmul`, `memcpy`, read-only tables). A violation, or a `ram` function the script left in flash, is `E_FREESTANDING_RAM` and removes the image.

The check is conservative: an integer constant equal to a flash address (on the RP2040, `0x10000000` to the end of the image) is refused too, and a record or array parameter is read where the caller keeps it, so pass values in RAM. A `ram` function may be the entry of the second core ([`registers.start_core1`](io.md)), started by value from code that is not freestanding.

```selka
# doc: expect 42
@freestanding(ram)
func mix(words: FixedArray[u32, 4]) -> u32:
    mut total: u32 = 0
    for i in range(4):
        total = total + words[i]
    return bit_and(bit_xor(total, 0x80), 0x3F)


func main() -> int:
    return int(mix(FixedArray[u32, 4]([0x11, 0x22, 0x33, 0x44])))
```

```selka
# doc: expect-error E_FREESTANDING
@freestanding
func in_flash(x: u32) -> u32:
    return x + 1


@freestanding(ram)
func erase_step(x: u32) -> u32:
    return in_flash(x)


func main() -> int:
    return int(erase_step(41))
```

## Docstrings

A string literal that is the first statement of a function body is its docstring; a record, union or enum documents itself the same way. A module's docstring is the string literal after its imports and before its first declaration. Write it `"..."`, `'...'` or triple-quoted; it is inert, and a string later in a body is an ordinary expression. A module docstring above the imports is `E_SYNTAX`, as is a second string among the top-level declarations; a `#` comment may sit above the imports for a file overview.

`list-interfaces` prints a declaration's first docstring line after its signature. The `undocumented-export` lint rule reports an exported function, record or union whose docstring is missing, shorter than `min_chars` non-whitespace characters (12; `lint.min_chars` in `selka.json`), or merely restating the declaration's name; it reports under `agent` and blocks under `strict` and `safety`.

```selka
# doc: expect 14
func area(width: int, height: int) -> int:
    """The rectangle's area in square units.

    >>> area(2, 7)
    14
    """
    return width * height


func main() -> int:
    return area(2, 7)
```

```selka
# doc: expect 42
import math

"""The module docstring follows the imports."""

func clamp_answer(value: int) -> int:
    return math.clamp(value, 0, 42)


func main() -> int:
    return clamp_answer(99)
```

### Runnable examples

`selka test` executes `>>> ` examples in function docstrings; a `... ` line continues a statement. The lines after it, up to a blank line, the next prompt or the end of the docstring, are the exact expected output (`<BLANKLINE>` is an empty line; nothing is elided or normalized). An expression displays its value after anything it writes to `out`; strings and bytes use `repr`, and statements and unit expressions display nothing. One docstring is one case, `module::function.example`, with shared local state and private helpers in reach; `fs`, `net`, `clock`, `entropy`, `env` and `out` are the runner's deterministic stand-ins.

```selka
# doc: expect 42
public func answer() -> int:
    """The answer, demonstrated with local state and output.

    >>> mut total = answer()
    >>> total
    42
    >>> print(out, 'answer')
    answer
    >>> '42'
    '42'
    """
    return 42


func main(out: Stream) -> int:
    print(out, answer())
    return 0
```

An example can leave early with `return True` or `return False` (a bare `return` or another type is refused): the output up to the `return` is compared with the prompt's expected output, a later prompt fails as not reached, and `return False` fails the case. So `const value = f() else Err(_):` with `return False` in its block fails the example when the call fails, and `print(out, message)` then `return True` shows what a failing call reports. `fail`, `try` and `break` or `continue` outside a loop of the example are refused.

```selka
# doc: expect 1
public func lookup(key: str) -> int fails str:
    """Fail for any key.

    >>> _ = lookup("y") else Err(message):
    ...     print(out, message)
    ...     return True
    unknown y
    """
    fail "unknown " + key


func main(out: Stream) -> int:
    print(out, 1)
    return 0
```

`selka test FILE.selka --filter .example` selects documentation cases. An example that fails to check is a failed case; other cases still run. A directory run discovers modules with examples even without test functions.

`release check` requires module and public declaration docstrings and an example on each public function (entry points, tests, `*_test.selka` modules and public constants are exempt). A reasoned `# lint: allow missing-example reason="..."` comment or `@allow("missing-example", reason="...")` waives the example rule; a module waiver goes before its first declaration, after imports. `missing-example` and `undocumented-module` are off under `agent` and report under `strict` and `safety`; the release documentation step blocks on all three documentation rules.

## Persistent function identity

`function_digest(callback) -> str` returns a compiler-issued identity for the callable, its reachable implementation and source schemas, and the compiler, runtime, toolchain, target and build settings. It contributes managed allocation and does not invoke the callback; a same-name function or a hand-chosen version string cannot substitute for it.

```selka
# doc: expect 42
import strings

func next(value: int) -> int:
    return value + 1

func main() -> int:
    const identity = function_digest(next)
    if strings.char_count(identity) != 64:
        return 1
    if identity != function_digest(next):
        return 2
    return 42
```

An empty string means the compiler cannot establish complete persistent authority (unsupported external linking, an unqualified tool): consumers must run without persistent reuse or reject the durable request. Compiler or execution-context changes can invalidate all identities. Tests that reach `function_digest` execute fresh rather than reuse a test receipt.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/functions.md).
