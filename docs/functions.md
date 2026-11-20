# Functions and calls

`func` declares every callable in the language. There are no methods, no
inheritance, no nested definitions and no closures, so a call's meaning follows
entirely from the declaration its name resolves to. This page covers how a call
supplies its arguments, what a function may return, and the one form — a function
value — that lets the target of a call be decided while the program runs.
[Statements and bindings](statements.md) covers what goes inside a body, and
[Python-style application code](python-syntax.md) is the wider tour of the
surface.

## Keyword arguments and defaults

A call passes arguments positionally, by keyword, or both, with every positional
argument before the first keyword. Keywords may name the parameters in any order,
and the arguments are evaluated exactly once in the order they are *written*,
not in parameter order, so a call whose arguments have effects behaves the way it
reads. A parameter may carry a default, which must be an immutable scalar
literal — a number, `True` or `False`, a string, or `None` — so no two calls can
ever share a mutable default; required parameters must precede every parameter
that has one, and the other order reports `E_DEFAULT_ARGUMENT`. An enum case, a record
value or an empty collection is not a parameter default, and the same code refuses it;
a record *field* may default to those (see [Enum and record
defaults](records-and-unions.md#enum-and-record-defaults)), and the parameter can take
the value as an ordinary argument instead. Unknown,
duplicate, missing, excess and misplaced arguments are all rejected, and a
default's declared type is checked even in a function nothing calls. Intrinsics such as `len` have their own argument rules. A callable type may
include `named` labels; calls through the value honor those labels and its exact
`mut` parameter positions.

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

Record construction reads the same way — `Point(x=1, y=2)` binds fields by name
through the same rules — and generic calls infer their type arguments from the
values they are given unless the [explicit
list](#explicit-call-type-arguments) is written out.

### Keyword-only parameters

Mark each parameter that requires a label with `named`: `named amount: int`.
Positional parameters come first, then named parameters. Repeat the modifier for
each named parameter; a bare `*` separator is not part of the canonical grammar.
Named parameters may be supplied in any order. Required and defaulted named
parameters may appear in either order, while positional parameters retain the
required-before-defaulted rule. Arguments evaluate once in their written order.
A missing label reports `E_KEYWORD_ONLY` with the labelled call.

Combine permissions as `named mut points: Point[]` and call it with
`points=mut points`. The name and mutation permission are both part of the contract.

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

So `io.issue(host, 13, 0, span.start)` reports
`` `code` is keyword-only; write `io.issue(host, code=13, file=0, position=span.start)` ``.
Rendered interfaces repeat `named` and prefix `mut` so a reader can see the
same call contract as in the source declaration.

### Owned parameters

A parameter has one of three modes, visible at the declaration and at every
call: a plain parameter reads its argument; `mut` writes the caller's value;
`own` takes the value, so the caller's binding is unusable after the line and
the callee may store, return or move it without a copy.

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

The marker belongs at every move of a named managed value, including inside the
callee. Write `State(keys=own keys)` to store its owned parameter, and
`const saved = own keys` to transfer it to another binding. Without `own`,
`const saved = keys` borrows read-only, including when `keys` is an `own` parameter.
A bare `return keys` needs no marker; `return own keys` is refused. Named inputs
inside a returned constructor still need markers: `return State(keys=own keys)`.

At a call, `own` is required where an owning parameter takes a named managed
value. Fresh values (call results, constructors, literals, `copy(value)` and
operator results) and scalars never take the marker. `make([1, 2])` carries none,
while `order_by_key(own samples)` does. Missing or misplaced markers report
`E_OWN_MARKER`. `own` and `mut` do not combine, and a function type spells the mode:
`func(own int[]) -> int`.

A managed field such as `own state.keys` transfers by consuming the whole record.
`state` becomes unavailable, and its remaining fields are destroyed at that point.
Use `copy(state.keys)` to keep an independent field value while retaining `state`.

The element of `append` takes the marker, and it is required there when the element
is a named binding the caller owns: a `const` or `mut` local, or an `own` parameter.
`append(mut rows, row)` is refused with the repair that writes `own row`, so the
caller gives `row` away. The library's storing functions take their element `own` the
same way: `sets.add(mut seen, own word)` and `dicts.append_to(mut groups, key, own item)`. The stores that copy a
key only when it is new take it borrowed instead: `groups[key] = items`, `sets.include(mut seen, word)`,
`dicts.add(mut counts, word, 1)` and the key of `dicts.append_to`. An `own` marker on one of those keys is refused
(`selka fix` removes it). That copy of a new key is the language's one documented implicit copy: no `copy(` is
written, by the decision of 12 November 2026, and `selka cost FILE --sites` labels the store's row
"implicit (dictionary key)" ([cost](tooling/cost.md#allocation-and-copy-sites)). In `sets.include` the copy is the
`copy(value)` the library writes in `sets.selka`.
A name that only borrows is not given away. A plain parameter, a loop variable, a match payload, an element read or a
slice binding is refused with `copy(...)` instead, and the program writes that copy,
so the storing function receives an independent value and the borrowed name stays
usable.

Every type has the three modes, including resources. A plain parameter reads its
argument, so it may not take a move-only value (a resource such as
`network.Listener`, or a record holding one) without saying so: that is the error
`E_OWN_PARAMETER`, and its repair writes `own` before the name. A function type,
wherever it is written (a parameter, a return, a local, a record field or an enum
payload), refuses a move-only plain position the same way, in the type: write
`func(own network.Listener) -> int`. A call site then writes `own listener`
(`E_OWN_MARKER`), so `selka fix` takes both steps with no hand edit.

Inside the callee an `own` parameter owns its value: it destroys it at scope end
when nothing else uses it, and the callee may write and rebind it as it does a
`mut` local. Those writes stay in the callee, because the caller gave the value
away:

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

A `mut` parameter is an exclusive borrow for every type, resources included, so
an accept loop can pass its listener `mut` and use it again; a resource the callee
keeps must be declared `own`.

### Wide signatures

A function may take scalar or managed parameters at any position. A borrowed
result declares its possible sources with `from`, including parameters beyond
position 64. Mutable parameters and declared result sources have no 64-position
limit.

## Unit procedures

A procedure produces `Unit`. Write `-> Unit` or omit the return annotation.
`Unit` is a builtin scalar type name, like `int` and `bool`; choose a different
name for an application record, because a nominal declaration cannot override
its meaning in type annotations.
The unit value is `()`. Falling off the body or a bare `return` succeeds with
unit, and ordinary cleanup runs on both paths. A fallible procedure writes
`func save(...) fails SaveError:` and uses `fail error` for failure.

A standalone call statement must produce unit. Use `_ = work(...)` to explicitly
discard an ordinary non-unit result; checked results still require handling.
Unit flows through generic functions, callbacks, bindings and result payloads.
`try save(...)` propagates a fallible procedure's error at a statement boundary.
Unit remains unsuitable for ordinary wire data and has its existing C ABI rules.

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

`add` returns early for the negative value, `bump` falls off the end, and neither
needs a return annotation to say so. Both write through `values`, so both declare
`mut values: int[]` and every caller marks the argument.

## Entry point signatures

`main` may return `int`, `Unit`, `int fails E`, or unit with `fails E`.
A successful integer becomes the process exit status, truncated to its low eight
bits; successful unit exits zero. An integer error supplies its status, and
another error exits one. Errors are printed to standard error with their
[error return trace](results-and-options.md#error-return-traces).
`selka run --print-result` additionally prints a successful integer.
Capability parameters remain available on the entry point; runtime arguments
use the existing command conventions.

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

A generic call may state its type arguments in square brackets between the
function name and the argument list: `identity[int](2)`. Explicit arguments and [inferred
ones](generic-inference.md) reach the same instance, so the choice is about
readability rather than behaviour — except where inference has nothing to work
from, such as a type parameter no value argument mentions, where the explicit
list is required. The list is all or nothing: a partial list is not completed by
inference, the return context never supplies a missing argument, and the wrong
count or an undeclared base name is rejected. In call position a square-bracket
application names a function when the base is a declared function and a generic
record otherwise, so `Box[int](item=0)` remains record construction.

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

The name of a declared function, written without a call, is a function value. Its
type is spelled `func(parameters) -> result`, with the parameter
types, the result type all written out, and a value of
that type can be stored in a local, passed as an argument and returned. A
function value captures nothing. There are no closures and no nested `func`, so
the value is an immediate function identity and everything it needs arrives
through its parameters; an attempt to capture the enclosing environment is
rejected rather than boxed. Function values are ordinary copied values with no
ownership of their own, and a call through one validates the target and keeps the
ordinary result and ownership obligations. They have no rendering, so passing one
to `print` is rejected with `E_IO_ARGUMENT`.

A function declaring a borrowed result with `from`, such as
`-> str from text` returning `text[0:4]`, keeps that borrow when called directly.
Its name used as a function value is refused with `E_VIEW_FUNCTION_VALUE`, because
a `func` value must return an owned managed result. `selka fix` writes a copying wrapper (`head_copy`, which returns
`copy(head(text))`) beside the function, or at the end of the importing module, and
names the wrapper at the use.

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

A function value may also be stored in a record field. Read the field into a local
and call that local. A direct call through the field (`handler.callback(value)`) is
not a method and is refused with `E_COLLECTION_METHOD`, which names the binding
spelling:

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

`same_function(left, right)` compares two compatible function values without
calling them. It returns `True` for the same callable and `False` for different
callables. Passing values with different call signatures, or a non-function,
is a type error. The comparison itself contributes no effects.

This identity lasts only within the running program. It is useful for separating
entries in an application memo cache. It supplies no persistent code digest:
after recompilation or process restart, persistent reuse needs validated
implementation, dependency, argument and result-schema identities.

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

A callback declares its parameter and result types. Authority arrives through
capability parameters, so a callback that prints takes a `Stream`. Parameter
and result types remain invariant, mutation positions must match, and the
return-origin bound may be narrower. Generic helpers may use
parameter-dependent callback signatures. Function values capture no context;
pass any context explicitly.

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

A sort key may allocate. Its callback type is `func(T) -> K`, and any authority
it needs appears explicitly in its parameters.

```selka
# doc: expect 3
import sort

func negate(value: int) -> int:
    return 0 - value

func main() -> int:
    mut ordered = sort.sort_by_key([1, 3, 2], negate)
    return ordered[0]
```

## Mutating callbacks

A callable signature declares the `mut` parameters it writes just as a declared
function does, and a call through the value substitutes the actual argument
origin, so the caller still needs permission for the mutation:

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

A positional binder name is a documentation label. A `named` binder requires
that call label, and its name participates in callable identity. An implementation may write fewer inputs than the
destination footprint permits, and a call through a stored or returned callback
uses the destination's mutation footprint.
A call through a function value follows the same exclusivity rule as a direct
call: Core checks that its `mut` arguments name disjoint places, so
`f(mut xs, mut xs)` is `E_SINGLE_OWNER_OVERLAP` (M5) there too
([value semantics](value-semantics.md#the-rules)).
An overlap during receiver evaluation is a separate R2 conflict; the compiler
can offer a [split repair](tooling/fix.md#structured-fixes-in-diagnostics) for
simple unconditional direct calls that return a scalar when their evaluation
can safely move first.

## Attributes

A declaration may carry a fixed-vocabulary attribute on the line directly above
it. `@deprecated("reason")` marks a callable that callers should stop using:
a call from another module reports `W_DEPRECATED` with the reason, and the
attribute is part of the declaration's interface fingerprint. `@test` makes a
function a discovered test regardless of its name or `export` flag, so
`selka test` and the `selka lint` test rules see the same set. `@allow("rule",
reason="...")` waives one lint rule for findings on that declaration, replacing
the `# lint: allow` comment; a missing `reason=` is still `L_WAIVER_REASON` and
always blocks. The vocabulary is fixed: any other `@name` is
`E_UNKNOWN_ATTRIBUTE`, and repeating one kind on a declaration is
`E_DUPLICATE_ATTRIBUTE`. Attributes attach to function declarations and
round-trip through `fmt`.

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

The call inside `square_of_three` and `main` is same-module, so `@deprecated`
reports nothing here; a caller in another module would see the warning.

## Freestanding functions

`@freestanding` above a function promises that it needs nothing from the
runtime, so it can run where the runtime cannot: before the runtime is up (a
device's reset), while it cannot be entered (a fault, an interrupt, a signal on
Linux) or while the flash it lives in cannot be read. The check verifies the
promise over the whole body, as `@noalloc` is verified over a call graph; no
block switches a check off. A freestanding function may be called from ordinary
code freely. The rules, each refused with `E_FREESTANDING` at the place that
breaks it, the message naming the rule:

- **Unmanaged data only**, in the parameters, the result, every local and every
  expression: integers, floats, `bool`, enums, records, unions, options and
  `FixedArray`s made only of those, `extern type` handles, and the capabilities
  `Registers` and `Host`. No `str`, `bytes`, list, dictionary, set, buffer,
  `Stream`, function value or other capability.
- **Calls only** of other `@freestanding` functions, of `extern func`s (C is
  trusted native code, and must keep the same promise: it may not call back into
  the runtime) and of the built-ins that become inline code: the `registers`
  reads and writes (`read8` to `write32`), one volatile load or store on a device,
  and the `cpu` functions that act on the machine (`wait_for_event`,
  `wait_for_interrupt`, `send_event`, `barrier`, `breakpoint`, `interrupts_off`
  and `interrupts_restore`), each its instruction inline. A `@linear`
  `InterruptState` held and restored inside one freestanding function checks as
  it does elsewhere. The simulated bank's readers (`cpu.event_count`,
  `cpu.interrupts_are_off` and the rest of its log) are not built-ins here: a
  freestanding function that calls one is refused by name. No `print`, `debug`, format string, `parallel`, and no call through a function
  value, whose type cannot carry the promise.
- It may declare `fails E` with an unmanaged `E` and use `try`, `match`, loops and
  `assert CONDITION`; an `assert` takes no message. A `try` in it records no
  error trace.

A failed check inside a freestanding function (an index out of range, an integer
overflow, a division by zero, a failed `assert`, an `unwrap` of `None`) calls
nothing and builds no text, in every build mode: its code goes in the first
argument register, the address of its source path in the second and its line in
the third, and the target's trap instruction runs (`udf #83` on
`thumbv6m-none`, `ud2` on x86-64). The code's low byte is the trap kind the
runtime numbers, and an assertion's clause is the next byte. On a device the bare
runtime's fault handler (linked only into an image whose program has a freestanding
fault; every other image keeps the plain handler) reads them from the stacked registers and reports
`error[R_LIST_BOUNDS] PATH:LINE` and status 1, the form of a `--release` device
build's traps. On x86-64 Linux the `ud2` is followed by the bytes `MYLF`, and
a program that holds freestanding code installs a handler for `SIGILL` before
`main`: it flushes the program's output as a trap does, prints
`error[R_LIST_BOUNDS] PATH:LINE` on standard error with the trap's record, and
exits with status 1, as a trap does; under `selka test` the test fails with the
code. Any other illegal instruction keeps the default action, and a program with
no freestanding code installs nothing, so its executable is unchanged.

A freestanding function may call C, by name or through an address
([calls through an address](c-ffi.md#calls-through-an-address)), as flash
routines call a boot ROM. Such a call records no place and calls nothing before
the jump: the `Host` token is compared inline with the value both runtimes give
it, a mismatch being the fault `R_CAPABILITY`, and a null address is the fault
`R_FOREIGN_TARGET`. A public freestanding function may be called from a
freestanding function of a module that imports it; removing the attribute
refuses that caller at its next check. Under `selka test` on Linux the
`registers` reads and writes and the `cpu` functions of a freestanding function go to
the simulated bank (`registers.simulated()`), as a device library is tested.

After lowering, the emitted code of
each freestanding function is checked to name no runtime symbol, counter or trap
record; a compiler change that broke that is an internal error naming the
function and the symbol.

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

Flash cannot be read while it is being erased or written, so the code that
does it must run from RAM and touch nothing in flash while it runs.
`@freestanding(ram)` places a freestanding function there; `ram` is the only
placement, and any other word is refused with `E_FREESTANDING`.

- **On a device** (`--target thumbv6m-none`) the function's code goes to the
  section `.ramfunc`, with no jump table. The device's linker script must load
  that section into RAM: put `*(.ramfunc*)` first in the output section of the
  initialised data, which start-up copies from flash
  (`.data : { __data_start = .; *(.ramfunc*) *(.data*) ... } > RAM AT > FLASH`),
  as the library's scripts do (`scripts/bare/qemu/link.ld`). A device image
  without any `ram` function links exactly as before.
- **On the host** the placement changes nothing (code runs from RAM there), so
  library code written for the device builds and is tested on Linux.
- **The rule at check time**: a `ram` function calls only other `ram`
  functions, `extern func`s and the inline built-ins (the `registers` reads and
  writes, the `cpu` functions). A call of a plain `@freestanding` function, whose code is in flash,
  is refused with `E_FREESTANDING`. An `extern func` is trusted: its C must make
  the same promise, placed in RAM by its author
  (`__attribute__((section(".ramfunc")))`) and reaching nothing in flash. Any
  function may call a `ram` one.
- **The proof on the image.** The check cannot see what the code generator adds:
  a call of a library routine (this CPU has no divide instruction, so `//` and
  `%` by a variable call `__aeabi_uidiv`; a 64-bit multiply calls
  `__aeabi_lmul`; a large record copy calls `memcpy`), a table or a constant it
  placed in read-only data. So after every device link the build reads the
  image: every address the code of a `ram` function refers to (a call, a branch,
  a literal it loads, an address it holds) must be in RAM (the function itself,
  the data, another `ram` function, C in `.ramfunc`) or outside the image's
  flash (a peripheral, the ROM). A violation fails the build with
  `E_FREESTANDING_RAM`, names the Selka function, the symbol it reached and the
  operation that needed it, and removes the image. The image of a `ram` function
  the linker script left in flash is refused the same way. One exception: a
  failed check passes the address of its source path in `r1` and never reads it.

The image check tells code from data by the ARM mapping symbols (`$t`, `$d`)
every Arm linker keeps, and decodes the Thumb instructions in the code. It is
conservative: a word of the function's literal data whose value lies in flash is
taken for an address, so an integer constant equal to a flash address (on the
RP2040, between `0x10000000` and the end of the image) is refused too. What a
caller passes by reference is not the function's own reference: a record or
array parameter is read where the caller keeps it, so pass a `ram` function
values in RAM (a local, not a constant array the caller's code holds in flash).
On QEMU the whole image is in RAM, and the check treats `.text` and `.rodata` as
a device's flash, so a program proved there keeps the promise on a device.

What counts as RAM is a section that is writable, that is loaded elsewhere than it
runs (the device that copies its `.data` from flash), or that lies between
`__data_start` and `__data_end`, the initialised data's extent every bare linker
script defines. The last rule is for an image that runs from RAM, which the boot
ROM loads straight into RAM: with no initialised variable its `.data` holds only
`.ramfunc` code, which is neither writable nor loaded elsewhere. A script that
puts `.ramfunc` in `.text`, or leaves it where the flash is, is still refused.

A program with `ram` functions may start the second core
([`registers.start_core1`](io.md)): the two-core runtime is linked and the
image check runs as for any other program. The second core's entry may be a
`ram` function, started by value from code that is not freestanding (a
freestanding function cannot take a function value, nor start a core). A `ram`
function's own faults (`udf #83`) and its calls of `extern func`s, whose `Host`
token is compared inline, call nothing in flash.

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

A string literal that is the first statement of a function body is that function's
docstring. A module's docstring is the string literal that follows its imports and
precedes its first declaration; in a file with no imports it is the first statement.
Write it with the ordinary `"..."` or `'...'`
spelling, or with a triple-quoted `"""..."""` that spans lines; either way it is
inert, so it contributes no value, no binding and no effect, and the statements
after it behave exactly as they would without it. A string later in a body is not
a docstring and stays an ordinary standalone expression. A record, union or enum
may document itself the same way, with the string as the first line of its
body.

Imports come first, so a module docstring written above them is `E_SYNTAX`
(`unexpected token; expected func`), as is a second string literal among the
top-level declarations. A `#` comment may sit anywhere above the imports and is
the place for a file overview that precedes them.

`list-interfaces` prints a declaration's first docstring line after its
signature. `selka lint`'s `undocumented-export` rule reports an exported
function, record or union whose docstring is missing, is shorter than
`min_chars` non-whitespace characters (12 by default, configurable as the
top-level `lint.min_chars` key in `selka.json`), or merely restates the
declaration's own name; it reports under the `agent` profile and blocks under
`strict` and `safety`.

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

```selka
# doc: expect-error E_SYNTAX
"""A module docstring above the imports is rejected."""
import math

func main() -> int:
    return math.clamp(99, 0, 42)
```

### Runnable examples

`selka test` executes `>>> ` examples inside function docstrings. A `... ` line
continues the preceding statement. The following lines, up to a blank line, the
next prompt or the end of the docstring, are the exact expected output.
`<BLANKLINE>` represents an empty output line; there is no elision or whitespace
normalization.

An expression displays its value after anything it writes to `out`. Strings and
bytes use `repr`, so `"1"` displays as `'1'`; other values use their ordinary
printed form. Statements and unit expressions display no value. One docstring
runs as one case, `module::function.example`, with shared local state and access
to private helpers. The names `fs`, `net`, `clock`, `entropy`, `env` and `out` are
bound to the runner's deterministic capability stand-ins.

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

An example can leave its case early with `return`. The generated function
returns `bool`, so write `return True` or `return False`; a bare `return` or any
other type is refused by the ordinary check. The case ends there: the output
written up to the `return` is compared with the expected output of the prompt it
returned in, a later prompt never ran and fails as not reached, and
`return False` fails the case. So `const value = f() else Err(_):` with
`return False` in its block unwraps a result and fails the example if the call
fails, and `print(out, message)` then `return True` shows what a failing call
reports. `fail`, `try` and a `break` or `continue` outside a loop of the example
are refused as in any function with no `fails` clause or loop.

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

Use `selka test FILE.selka --filter .example` to select documentation cases.
An example that fails to check is a failed case; other valid cases still run.
A directory run discovers modules with examples even when they have no test
functions, and each imported module's examples run once.

`release check` requires module and public declaration docstrings and an example
on each public function. Entry points, tests, `*_test.selka` modules and public
constants are exempt. A reasoned `# lint: allow missing-example reason="..."`
comment or `@allow("missing-example", reason="...")` waives the example rule.
The `missing-example` and `undocumented-module` lint rules are off under `agent`
and report under `strict` and `safety`; the release documentation step blocks
on all three documentation rules. A module waiver goes immediately before its
first declaration, after imports.

## Persistent function identity

`function_digest(callback) -> str` returns a compiler-issued identity for the
actual callable, its reachable implementation and source schemas, and relevant
compiler, runtime, toolchain, target and build settings. It contributes managed
allocation. It does not invoke the callback. A same-name function or a manually
chosen version string cannot substitute for this identity.

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

An empty string means the compiler cannot establish complete persistent
authority, including unsupported external linking or an unqualified tool.
Consumers must execute without persistent reuse or reject the durable request.
Unknown indirect targets conservatively widen dependencies. Compiler and
execution-context changes can invalidate all identities; this favors correctness
over retaining results across an unqualified migration. Pure callback signatures
remain a separate requirement: an identity alone does not make effects replayable.

Tests that reach `function_digest` execute fresh rather than reuse an individual
test receipt. The query can observe broader compilation dependencies than the
ordinary rooted test key represents. Ordinary tests retain their existing reuse;
application `persistent_memo` and `durable` still use the qualified identities.
