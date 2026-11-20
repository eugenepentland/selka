# Frontend syntax redesign for readable code

Status: **implemented on 9 October 2026.**
The agreed surface uses `func`, including callable types. The concrete decisions
below guide the compiler, migration diagnostics, and current language reference.

The frontend should make a function and its changes understandable from the
surrounding code: which values can change, which calls can fail, what arguments
mean, and what a function returns. Human readability and review are the primary
criteria. Better agent performance is a hypothesis to measure against realistic
editing tasks.

Keep Python's indented layout, familiar control flow, and ordinary expressions.
Introduce explicit declarations and use words for mutation, named parameters,
and failure. Everyday function signatures should describe their successful result
directly, with a separate failure clause.

This changes the Python-first surface direction in the
[6 October frontend proposal](frontend-plan-after-new-core-2026-10-06.md).
Its compiler architecture work remains relevant; its language-deletion rows need
reconciliation with the decisions below. The
[values and keys plan](values-keys-trap-search-plan-2026-10-07.md) remains the
separate home for identity, storage, trap testing, and its pending effect and
contract decisions. This redesign does not decide those pending items or change
the existing sequencing around the new-core transition.

The language examples below are checked by `mylang doctest`. The HTTP example
remains a library sketch and is explicitly skipped.

## Agreed surface

| Concern | Target spelling | Meaning |
| --- | --- | --- |
| Immutable local | `const point = origin` | Introduce an immutable ordinary data value. |
| Writable local | `mut points: Point[] = []` | Introduce a value that can be reassigned or updated. |
| Writable parameter | `mut points: Point[]` | Permit the function to update the caller's argument. |
| Writable argument | `translate(mut points, dx=5)` | Make that permission visible at the call. |
| Named parameter | `named dx: int` | Require the caller to write `dx=...`. |
| Growable array | `Point[]` | A variable-length array value. |
| Optional value | `Point?` | A point or `None`. |
| Fallible function | `-> Point[] fails LoadError` | Return an array on success or a declared error on failure. |
| Successful return | `return points` | Return the successful value. |
| Failure return | `fail LoadError.empty_file` | Return a declared error. |
| Failure propagation | `const point = try parse(text)` | Extract success or return the error immediately. |
| Conditional value | `if compact then 80 else 120` | Read the condition before its alternatives. |
| Comprehension | `[for point in points if visible(point) yield point]` | Read the source, filter, and output in that order. |

The target has one canonical spelling for each of these forms. `let`, `var`, the
bare `*` parameter separator, and postfix expression `?` are not alternative
spellings in the redesigned surface. The `?` suffix belongs to optional types.

Use `func`, `public`, `record`, `import`, four-space indentation, `#` comments,
`True`, `False`, `None`, `and`, `or`, `not`, explicit function returns, and familiar
arithmetic. Statements end at newlines; semicolon-separated statements are removed.

## Bindings and mutation

`const` describes mutability. Its initializer can execute at runtime. It does not
require compile-time evaluation. For ordinary data, immutability includes nested
collections: a `const` record cannot have one of its arrays changed through that
binding. A mutation that requires a writable value needs `mut`.

Declarations introduce names; ordinary assignment updates an existing writable
binding. A misspelled assignment target is an error instead of a new variable.
Local types remain inferred when the initializer supplies enough information.
An ambiguous empty array needs an annotation, as in `mut points: Point[] = []`.

Locals have block scope. Reject declarations that shadow an active local or
parameter. Loop and pattern bindings are local to their blocks and read-only by
default. A name created in a branch cannot be used after that branch. To carry a
changing value out, declare it in the enclosing block; to select a single value,
use an expression when possible.

This deliberately changes the function scope documented in
[the current binding rules](../statements.md) and
[the existing scope decision](../adr/D1-block-scope.md). Migration needs scope
analysis, especially for names initialized separately in different branches.

Ordinary data parameters are read-only unless marked `mut`. A function that
wants to edit a private copy introduces a local `mut` value. A function that
updates the caller's value declares a `mut` parameter and requires a `mut`
argument. A receiver update such as `points.append(point)` requires a writable
receiver; it remains the collection operation's ordinary spelling.

```mylang
# doc: check
record Point:
    x: int
    y: int

func translate(
    mut points: Point[],
    named dx: int,
    named dy: int,
):
    for i in range(len(points)):
        points[i].x += dx
        points[i].y += dy

func example() -> Point[]:
    const original = [Point(x=10, y=20)]
    mut moved = original

    translate(mut moved, dx=5, dy=-2)

    return moved
```

`original` still contains `(10, 20)` and `moved` contains `(15, 18)`. The guarantee
is value independence; it does not require an eager physical copy on every
assignment. Storage sharing and copy elision are implementation choices that
must preserve the guarantee. This relies on the target value model, rather than
the shared mutable collections described by older language-guide examples.

Capabilities and resource handles need their own authority and lifetime rules.
Declaring a capability binding immutable does not revoke its permission to
perform I/O. `mut` describes writes to ordinary caller data; it is not a lock or
a general marker for every external effect.

## Collections and optional values

`Point[]` means a growable array of points. It has value semantics, supports
indexing, iteration, and updates through writable bindings, and carries its
length at runtime. It is neither a fixed-length array nor an implicit borrowed
view. An array literal always constructs a growable array; an expected fixed
array type must not silently change its meaning.

Keep three concepts distinct:

| Concept | Contract |
| --- | --- |
| Growable array | `Point[]`; its length can change through a writable binding. |
| Fixed array | `FixedArray[T, N]`; construct it explicitly with `FixedArray[T, N]([...])`. |
| Slice or view | Refers to a region of another value's storage; requires an explicit type and operation if provided. |

`points[2:5]` produces an independent array value. The compiler may optimize its
storage, but later writes to either value cannot change the other. A view that
observes another value's storage needs a separate contract for lifetime and
mutation. This proposal does not introduce borrowed views as an everyday
requirement.

`Point?` means a point or `None`. A point can initialize or be returned into that
optional type directly. A presence check narrows the local value on the paths
where it is present. Assignment or a call that can update a writable local must
invalidate any presence fact it can break.

```mylang
# doc: check
record Point:
    x: int
    y: int

func first(points: Point[]) -> Point?:
    if len(points) == 0:
        return None
    return points[0]

func first_x(points: Point[]) -> int:
    const point = first(points)
    if point is None:
        return 0
    return point.x
```

Absence is ordinary data. Expected failure uses `fails`. An API should choose
between them deliberately: an empty collection can have no first element,
whereas malformed input can carry a useful error.

## Functions and named parameters

Every parameter marked `named` must be supplied using its name. The modifier
applies to that parameter individually. Write positional parameters first, then
named parameters; repeat `named` for each one instead of using a bare `*` to
change the interpretation of the rest of the list.

```mylang
# doc: check
func offset(
    value: int,
    named amount: int,
    named scale: int = 1,
) -> int:
    return value * scale + amount

func example() -> int:
    return offset(20, amount=2, scale=2)
```

`offset(20, 2, 2)` is rejected with a diagnostic showing the labelled call.
Defaults retain the existing restrictions on safe default values. Arguments
evaluate once in their written order, including when names reorder parameters.

Record construction always names its fields. For ordinary functions, use named
parameters for flags, options, and arguments that are easy to swap. A primary
input can remain positional. Requiring labels is part of the declared contract;
the checker does not guess which arguments are ambiguous from their types.

Parameter types and successful return types remain explicit at function
boundaries. Procedures can omit the return annotation. Named constraints remain
available to keep substantial generic requirements readable; this reverses the
earlier proposal to remove them solely in favor of inline requirements.

## Typed failure without nested return notation

The declaration `func parse(text: str) -> Point fails ParseError` describes the
successful result and its possible returned error separately. It still produces
a checked result at a call site. The simpler header does not add exception
unwinding or implicit error propagation.

| Source operation | Meaning |
| --- | --- |
| `return value` in a function returning `T fails E` | Check `value` as `T`, wrap success, and exit. |
| `fail error` | Check the error against the declared failure type, wrap failure, and exit. |
| `try operation()` | Extract success; otherwise return a compatible error from the enclosing function. |
| `const outcome = operation()` | Keep the checked result for explicit handling or transfer. |
| `match outcome` with `Ok` and `Err` | Handle the result's alternatives. |

`try` requires an enclosing fallible function with a compatible error type.
Normal scope cleanup runs on both `return` and `fail`, including propagation by
`try`. Preserve the existing compatible-error conversion rules initially; there
is no arbitrary widening between unrelated errors.

Use `return try other_function(...)` to forward a fallible operation's successful
value and its failure. `return other_function(...)` must not silently unwrap a
result. Nested result values need deliberate typing so an already wrapped
outcome cannot accidentally become a second success wrapper.

```mylang
# doc: check
enum DivisionError:
    zero_denominator

func divide(
    numerator: int,
    named denominator: int,
) -> float fails DivisionError:
    if denominator == 0:
        fail DivisionError.zero_denominator
    return numerator / denominator

func percentage(
    part: int,
    named total: int,
) -> float fails DivisionError:
    const fraction = try divide(part, denominator=total)
    return fraction * 100

func percentage_label(part: int, named total: int) -> str:
    match percentage(part, total=total):
        case Ok(value):
            return f"{value}%"
        case Err(DivisionError.zero_denominator):
            return "No total available"
```

Checked results retain their handling obligations, including when stored inside
other values. Omitting `try` does not make a failed call ignorable. The separate
values-and-keys proposal's possible changes to result obligations are not adopted
by this syntax change.

A fallible procedure can omit the successful return annotation and write
`func save(...) fails SaveError:`. Its bare return or normal completion succeeds
with unit. The unit type is `Unit`, its value is `()`, and optional absence is `None`.

Expected failures are returned values. Existing traps for bugs, such as violated
assertions or checked arithmetic overflow, remain traps; `try` does not catch them.
Give text parsing explicit names such as `parse_int(text)`, while numeric
conversions keep spellings such as `float(count)`. Individual parsing APIs must
declare whether they return absence or a typed error.

## Control flow and data declarations

Keep `if`, `elif`, `else`, `for`, `while`, `break`, `continue`, and `match`.
Conditions require `bool`; there is no implicit truthiness. The conditional
expression evaluates the condition first and exactly one of its alternatives.

```mylang
# doc: check
func width(named compact: bool) -> int:
    return if compact then 80 else 120

func nonnegative(values: int[]) -> int[]:
    return [
        for value in values
        if value >= 0
        yield value
    ]
```

A comprehension has one generator, an optional filter, and an output expression.
It eagerly builds a growable array. `yield` identifies the element being emitted;
it does not introduce generator functions or suspended execution. Preserve the
source, filter, and output as distinct nodes for diagnostics and formatting.

Use `record` for named fields and one `enum` form for a closed set of alternatives,
with or without payloads. Cases are separated by newlines. Construction and
patterns identify payload fields by name. Payload-free cases need no parentheses.

```mylang
# doc: check
enum Shape:
    empty
    circle(radius: float)
    rectangle(width: float, height: float)

func area(shape: Shape) -> float:
    match shape:
        case Shape.empty:
            return 0.0
        case Shape.circle(radius=r):
            return 3.14159 * r * r
        case Shape.rectangle(width=w, height=h):
            return w * h

func window() -> Shape:
    return Shape.rectangle(width=120.0, height=80.0)
```

`match` is exhaustive unless an explicit wildcard covers the remaining cases.
Adding a variant makes matches without appropriate coverage fail checking.
The `Ok` and `Err` patterns used for checked results remain available, including
nested patterns such as `Err(DivisionError.zero_denominator)`.

Matches produce values without mutable temporaries: each continuing expression
arm ends with `yield value`. Ordinary function bodies still require explicit
returns. Migration of nominal `union` and `result`
declarations must preserve type identity and checked-result obligations.

Keep explicit imports and `public` declarations. The file path supplies the
module name, following the existing frontend proposal, so the new examples have
no redundant `module` header. Use one canonical formatter for declarations,
multiline calls, expressions, and trailing commas.

## Webserver example

This example is a proposed HTTP library used to exercise the language design.
The `http` module and its server implementation are separate library work. Routing,
JSON decoding, and HTTP status conversion are library behavior, not new grammar.

`GET /todos` lists values. `POST /todos` accepts an object such as
`{"title": "Read the parser"}` and creates a todo. The server retains the same
application value between requests and invokes handlers serially.

```mylang
# doc: skip frontend syntax and illustrative HTTP library proposal
import http

record Todo:
    id: int
    title: str
    done: bool

record NewTodo:
    title: str

record App:
    todos: Todo[]

func create_todo(
    mut app: App,
    named title: str,
) -> Todo fails http.Error:
    const clean_title = title.strip()

    if clean_title == "":
        fail http.Error.bad_request(message="A title is required")

    const todo = Todo(
        id=len(app.todos) + 1,
        title=clean_title,
        done=False,
    )

    app.todos.append(todo)
    return todo

func handle(
    mut app: App,
    request: http.Request,
) -> http.Response fails http.Error:
    if request.path != "/todos":
        fail http.Error.not_found

    match request.method:
        case http.Method.get:
            return http.json(app.todos)

        case http.Method.post:
            const input: NewTodo = try http.read_json(request)
            const todo = try create_todo(mut app, title=input.title)
            return http.json(todo, status=http.Status.created)

        case _:
            fail http.Error.method_not_allowed(
                allowed=[http.Method.get, http.Method.post],
            )

func main(network: Network) -> int fails http.ServerError:
    mut app = App(todos=[])

    try http.serve(
        network,
        mut app,
        host="127.0.0.1",
        port=8080,
        handler=handle,
    )

    return 0
```

The library contracts assumed by the example are:

- `http.read_json` decodes the request into the expected type and returns
  `http.Error` for invalid input. Here `NewTodo` requires a string `title` field.
  The binding annotation supplies the success type through `try`, extending the
  existing [expected-result inference](../generic-inference.md#expected-result-types)
  to the new syntax. It does not require runtime type values or unchecked casts.
- `http.json` serializes the typed value into a response. Its default success
  status is 200; `http.Status.created` selects 201.
- `http.serve` calls `handle(mut app, request)`. Handler errors become responses
  for that request: `bad_request` selects 400, `not_found` selects 404, and
  `method_not_allowed` selects 405 with the supplied methods in the `Allow`
  header. These follow [HTTP semantics](https://www.rfc-editor.org/rfc/rfc9110.html#name-status-codes).
- Listening and server failures use `http.ServerError` and propagate out of
  `main`. A failed request does not terminate the server.
- The server owns request I/O and obtains its authority from `Network`.
  A callback function and an explicit application argument supply everything
  needed here; the example requires neither capturing closures nor global state.

This is an in-memory example with no deletion, so `len(app.todos) + 1` supplies
its IDs. Durable storage, stable IDs across deletion, and concurrent handlers
need additional library contracts. Concurrent writes require an explicit state
ownership or synchronization design; marking a parameter `mut` provides neither.

## Relationship to earlier decisions

| Earlier direction | Change recorded here |
| --- | --- |
| Preserve the spelling a Python-trained agent writes first | Prefer code a human can review locally; retain familiar syntax where it serves that goal. |
| Assignment both declares and reassigns function-scoped locals | Explicit `const` and `mut` declarations with block scope. |
| `list[T]` as the everyday collection spelling | `T[]` with growable array value semantics. |
| `Option[T]` in ordinary signatures | `T?` and presence checks. |
| `Result[T, E]` in routine fallible headers and expression `?` | `-> T fails E`, `return`, `fail`, and prefix `try`. |
| Parameter `name: mut T` | Prefix `mut name: T`, matching declarations and calls. |
| Bare `*` before keyword-only parameters | An individual `named` modifier on every such parameter. |
| Python conditional and comprehension order | Condition-first selection and source-first comprehensions. |
| Separate `enum`, `union`, and nominal `result` declaration forms | One variant declaration direction, subject to preserving nominal identity and handling rules. |
| Remove named constraints in favor of inline requirements | Retain names that make substantial generic contracts readable. |

The source-shaped typed tree, syntax recovery, generic-checking consolidation,
and cache work in Part C of the earlier frontend proposal still provide useful
implementation structure. Reconcile those packages with the new grammar and
scope rules before treating the old language-deletion list as executable work.
Keep unrelated decisions about type aliases, domains, contracts, effect checking,
and allocation assertions with their owning plans.

## Compiler and migration work

Implement this as a versioned language change with a migration path. Temporary
compatibility during migration should have a defined end; the formatter and
reference should teach one target dialect.

1. **Apply the resolved grammar and semantic contracts.** Use the decisions
   recorded below for suffix precedence, callback identity, result wrapping,
   lexical scope, and mutation.
2. **Build source-shaped syntax and diagnostics.** Preserve comments, spans,
   declarations, `try`, `fail`, optional types, and array types until the relevant
   semantic checks. Update syntax hints and removed-spelling diagnostics: the old
   parser's rejection of `try` must not survive as contradictory guidance.
3. **Implement binding and scope semantics.** Enforce immutable values, writable
   arguments, block lifetime, definite assignment, and invalidation of narrowing
   facts. These are semantic changes, not token substitutions.
4. **Lower the new surface to the typed core.** Fallible signatures and returns
   use the checked-result representation; optional types use the option
   representation. Keep error paths, cleanup, and handling obligations intact.
   Preserve ordinary data layout unless a separate semantic change requires it.
5. **Update every public language surface.** The formatter, navigation, schema,
   interface display, `context`, API diff, feature manifest, and documentation
   must agree about named parameters, mutation, successful results, and failures.
   Version caches for the language change and include actual contract changes in
   interface identity.
6. **Migrate real code with type and scope information.** Convert initial bindings
   to `const` or `mut` based on writes through the value as well as reassignment.
   Hoist or restructure branch-local values used later. Preserve argument
   evaluation order, nominal identity, and explicit result handling.
7. **Complete the language reference and retire compatibility.** Update the
   current guides when the implementation lands. Convert each proposal skip into
   executable coverage or move library-only sketches to their library proposal.

Useful mechanical rewrites include `list[T]` to `T[]`, `Option[T]` to `T?`,
`name: mut T` to `mut name: T`, and `*` groups to individual `named` modifiers.
For a fallible function, `return Ok(value)` becomes `return value`,
`return Err(error)` becomes `fail error`, and expression `?` becomes prefix
`try` with parentheses or extracted statements where needed. Forwarding a raw
result becomes `return try outcome` when that preserves the original contract.

These rewrites need typed syntax. A blanket replacement can change nested
results, the precedence of propagation, or the scope and aliasing of values.
Targeted diagnostics should show the replacement at the offending location.

## Resolved implementation decisions

The implementation uses these contracts. The HTTP library and borrowed views
remain separate work.

| Detail | Decision |
| --- | --- |
| Fixed arrays | `FixedArray[T, N]` has a static length. A literal constructor checks length statically. A runtime growable input returns `Result[FixedArray[T, N], FixedArrayLengthError]` with `wrong_length` on mismatch. |
| Views | Ordinary slices are independent values. New borrowed views are deferred. |
| Compound types | Suffixes apply left to right: `T?[]` is an array of optional values; `T[]?` is an optional array. Nested optional layers remain distinct. Stored results keep `Result[T, E]`. Unit is `Unit` / `()`. |
| Mutation | A `mut` parameter updates the caller, including whole-value reassignment. Writable locals, fields, and indexed elements are eligible arguments. Known overlap is rejected; unresolved indexed overlap is checked before entering the function. Ordinary arguments remain independent snapshots. |
| Callable contracts | Named labels and exact writable parameter positions belong to callable identity. Unused writable capability is permitted. |
| Combined modifiers | Write `named mut values: T[]`, and call with `values=mut values`. |
| Match values | Every continuing expression arm supplies `yield value`; `return` exits the enclosing function. Nested named-field patterns must be exhaustive. |
| Propagation | Prefix `try` appears at statement value boundaries. Extract fallible operands before a larger expression. Existing explicit Result and optional-returning helpers retain compatible propagation. |
| Nominal results | Specialized `result` declarations remain where their distinct nominal identity matters. Everyday fallible signatures use `fails`. |
| Constants | Local `const` initializers run normally. Module constants retain compile-time requirements. `const left, right = value` and `mut left, right = value` explicitly declare tuple bindings; bare destructuring updates existing writable bindings. |
| Modules | The path determines module identity. Redundant module headers have deletion fixes. |
| Comprehensions | Eager source-first array comprehensions have one generator and one binder. Use explicit loops for nested generators or destructuring. Existing dictionary, set, and consuming-generator forms remain separate. |
| Text parsing | `parse_int` and `parse_float` return optional numbers. `int` and `float` convert numbers; text calls carry rename fixes. |
| Migration | `mylang fix` applies certain parsed and typed edits. Escaping block locals and embedded propagation require a deliberate rewrite that preserves evaluation order. |
| HTTP library | Server, decoder, response, capability, and callback APIs are separate library work; the earlier sketch does not establish an implemented server. |

The migration covers the compiler, standard library, current examples, active
tests, benchmarks, and the S-expression parser experiment. Frozen historical
application baselines, dated evidence snapshots, and the pinned self-hosting
source keep their original syntax. The live self-hosting comparison migrates a
temporary copy through `mylang fix`, preserving the pinned source as evidence.

## Acceptance evidence

Validation runs use the pinned Zig toolchain through `scripts/build-slot.sh`.
The required final commands are `zig build test --summary all` and
`zig build fmt-check`. The implementation has the following coverage:

- 1,399 frontend/tooling unit tests, 526 Core tests, and 243 CLI tests.
- 1,534 language tests, 140 value-semantics tests, and 42 ported tests in both
  debug and release, with release fact verification and leak checks.
- 338 interface-oracle entries agree; incremental and interface differential
  runs report no mismatches or invariant violations.
- 222 golden cases replay with zero mismatches. The 382 existing skips remain
  accounted for. The intentional payload-display change renders field labels.
- Documentation executes 218 examples and checks another 58. Historical and
  library-only sketches are explicitly marked as such.
- All 45 benchmarks and the active S1 views tool check. The S-expression port
  passes all 114 tests in debug and release with fact and leak checks.
- The frozen legacy Lox project migrates through `mylang fix` with 412 edits
  across nine files, then checks clean and needs no edits on the next fix run.

Regression coverage verifies behavior at the points where a reviewer relies on
the new spelling:

- Updating a `const` value or a nested collection is rejected. Mutating an
  independent `mut` copy leaves the original unchanged, including nested data.
- A call cannot write through an ordinary data parameter; required or misplaced
  `mut` and missing argument labels receive actionable diagnostics.
- Branch and loop scope, shadowing, and definite assignment produce the intended
  bindings. Guard facts do not survive writes that invalidate them.
- Successful returns, explicit failures, propagation, cleanup, nested results,
  and unhandled outcomes behave consistently on every exit path.
- Typed decoding inference passes the expected success type through `try`;
  conflicting or insufficient type information still produces an error.
- Variant matching checks coverage, including nested result patterns and fields
  bound by name. Comprehensions evaluate their source once and preserve the
  specified filter and output order.
- Formatting is canonical and preserves behavior. Diagnostics and all rendered
  interfaces use the same syntax. Cache invalidation respects the changed
  contracts and produces the same verdict as a clean check.

Compare migrated programs with the pinned compiler and core appropriate to the
existing frontend transition plan. Use differential execution for changes that
should preserve behavior; use explicit expected outcomes for changed scope and
mutation semantics. Run the repository's required implementation and Guardian
gates when compiler work lands.

Before expanding the syntax further, rewrite a real parser module, a schematic
routing function, and an I/O workflow. Review edits that swap same-typed
arguments, introduce mutation, omit error handling, or add a variant. Measure
human review accuracy and time alongside agent failed checks and repair rounds.
Familiarity and shorter source are useful signals, but neither alone establishes
that the redesign improves development speed.
