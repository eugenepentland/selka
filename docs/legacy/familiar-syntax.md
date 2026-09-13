# Legacy familiar application syntax

> **Removed on 2026-09-13.** This page describes the brace dialect, which the
> compiler no longer accepts. See [the language guide](../python-syntax.md) for
> the surface that replaced it.

New code should use the [Python-style guide](python-syntax.md). This page documents the compatible brace spelling.


The compiler accepts this syntax alongside existing source spellings. GC behavior,
checked errors, and explicit resource ownership are unchanged.

```mylang
// doc: skip known-wrong example: E_SYNTAX rejects the trailing comma after this struct declaration's last field, though calls and record construction accept one; the rest of the example returns 42
struct Node {
    value: i64,
    children: List<Node>,
}

fn make_node(value: i64) -> Node {
    return Node { value: value, children: [] }
}

fn main() -> i64 {
    let nodes: List<Node> = []
    nodes.push(make_node(42))
    let first = nodes[0]
    return first.value
}
```

Imported modules use familiar dot notation: `sexpr.parse(input)` calls a
function and `io.Inputs` names a type. The existing `sexpr::parse(input)` spelling
remains supported. Import aliases determine module qualification, while dots on
local values still access fields or list methods. Visibility checks are identical
for both module spellings.

`List<T>` and `Result<T, E>` are built in and need no import. Lists share mutable
storage; structs are copied values. `let` fixes a binding, while `let mut` permits
rebinding. List mutation does not require a mutable binding.

`[]` constructs an empty managed list using an expected type. Annotate a local
when its initializer alone cannot determine its type. Nonempty literals infer their element type. List methods, indexing, and writes accept expression receivers; negative indexes and copying slices are supported. Existing fixed-array indexing remains supported.

```rust
fn checked(value: i64) -> Result<i64, i64> {
    if value < 0 {
        return Err(1)
    }
    return Ok(value)
}

fn answer() -> Result<i64, i64> {
    let value = checked(42)?
    return Ok(value)
}
```

`Ok(value)` and `Err(error)` use the expected result type. `expression?` has the
same checked error propagation as `try expression`. Error payload types must
match the enclosing result. `()` spells both the unit type and its value; `unit`
and a bare `return` remain available. Matching still accepts named result cases,
for example `type Answer = Result<i64, i64>` with `Answer.ok(value)` and
`Answer.err(error)` arms.

Statements end at a newline, a closing block brace, or the end of the file.
Semicolons remain valid and separate multiple statements on one line. Expressions
continue inside parentheses or brackets, or across a binary operator at either
end of a line. To begin a separate statement with unary minus after an expression,
end the preceding statement with a semicolon. Braces delimit blocks, and returns
are explicit.

```rust
let value = base +
    adjustment
let total = (
    value
    + extra
)
```

Function arguments and record fields accept trailing commas. Construct records
with `Type { field: value }`; `new Type { field: value }` still works. In a
control-flow condition, parenthesize a record construction to distinguish it from
the block that follows.

Try the examples with:

```sh
zig-out/bin/mylang run-project examples/gc-default/main.my --gc-stress
zig-out/bin/mylang run-project examples/gc-default/result-flow/main.my --gc-stress
```

They return 142 and 42 respectively. The migrated schematic application is in
`src/schematic/guest`; its runner instructions are in
[`experiments/schematic/README.md`](../experiments/schematic/README.md).

Imported modules use their declared import alias with a dot: `sexpr.parse(inputs.circuit)` and `io.Inputs`. Generic types and domain methods also work, such as `api.Box<io.Inputs>` and `units.Distance.make(42)`. The existing `alias::name` spelling remains supported. A prefix is treated as a module only when it names a direct import; local list methods and domain methods keep their existing meaning. Imported private symbols remain inaccessible, and locals cannot shadow import aliases.
