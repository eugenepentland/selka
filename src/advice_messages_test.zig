//! A diagnostic that advises a spelling advises one the compiler accepts (lane W8). Each test here is one program
//! the compiler refuses and the code and advice its first diagnostic gives: the logical operators of C and the
//! words that replace them, a `try` before an operator, a reserved word after `mut`, a method call on a value,
//! and the source spelling of the types a method signature names. The advice for a lent value stored in a set
//! is a Core refusal and is tested in `src/core/single_owner_test.zig`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const fixture = @import("stdlib_fixture.zig");

/// Check `source` (a single unit), which must be refused, and require its first diagnostic to carry `code` and a
/// message that contains `advice`.
fn expectRefusal(source: []const u8, code: []const u8, advice: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "advice.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const first = c.diagnostics.items[0];
    try t.expectEqualStrings(code, first.code);
    try t.expect(std.mem.indexOf(u8, first.message, advice) != null);
}

/// The head of the programs about `try`: a function that fails on an odd number.
const half =
    \\func half(x: int) -> int fails str:
    \\    if x % 2 != 0:
    \\        fail "odd"
    \\    return x // 2
    \\
    \\
;

/// The head of the programs about a method call on a value: a record and a function that takes it.
const point =
    \\record Point:
    \\    x: int
    \\    y: int
    \\
    \\func scale(p: Point, by: int) -> int:
    \\    return p.x * by
    \\
    \\
;

test "&& is answered with and, || with or and ! with not" {
    const two = "func main() -> int:\n    const a = True\n    const b = False\n";
    try expectRefusal(two ++ "    if a && b:\n        return 1\n    return 0\n", "E_REMOVED_SPELLING", "`&&` is not an operator; write `and`");
    try expectRefusal(two ++ "    if a || b:\n        return 1\n    return 0\n", "E_REMOVED_SPELLING", "`||` is not an operator; write `or`");
    try expectRefusal(two ++ "    if !a:\n        return 1\n    return 0\n", "E_REMOVED_SPELLING", "`!` is not an operator; write `not`");
    try expectRefusal(two ++ "    if (!a) and b:\n        return 1\n    return 0\n", "E_REMOVED_SPELLING", "write `not`");
}

test "a lone ampersand before an argument is still the removed call marker, and a conversion bang is no negation" {
    const marker = "func bump(mut items: int[]) -> int:\n    return len(items)\n\nfunc main() -> int:\n    mut xs: int[] = []\n    return bump(&xs)\n";
    try expectRefusal(marker, "E_REMOVED_SPELLING", "`&` before an argument was removed; write `mut` before it, as in `mut value`");
    const conversion = "func main() -> int:\n    const x = 1\n    const s = f\"{x!r}\"\n    return len(s)\n";
    try expectRefusal(conversion, "E_TOKEN", "unexpected character");
}

test "a try over an operator expression is the position rule's error, not a type error (TRY-2)" {
    const sum = half ++ "func total(x: int) -> int fails str:\n    mut sum = 0\n    sum += try (half(x) + 1)\n    return sum\n\nfunc main() -> int:\n    return 0\n";
    try expectRefusal(sum, "E_TRY_POSITION", "write the operator outside it (`try f() + 1`, `-try f()`)");
    const negated = half ++ "func total(x: int) -> int fails str:\n    return try -half(x)\n\nfunc main() -> int:\n    return 0\n";
    try expectRefusal(negated, "E_TRY_POSITION", "`try` takes a call (or a name, field or element), not an operator expression");
}

test "a try that covers a whole value is accepted, with the operator outside it" {
    const bound = half ++ "func total(x: int) -> int fails str:\n    const h = try half(x)\n    const k = try half(h)\n    return k + 1\n\nfunc main() -> int:\n    return 0\n";
    var accepted = try language.Compilation.init(t.allocator, "advice.selka", bound);
    defer accepted.deinit();
    try accepted.check();
    try t.expectEqual(@as(usize, 0), accepted.diagnostics.items.len);
}

/// Check `source` (a single unit), which must be accepted with no diagnostic.
fn expectAccepted(source: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "advice.selka", source);
    defer c.deinit();
    try c.check();
    try t.expectEqual(@as(usize, 0), c.diagnostics.items.len);
}

test "a try in a call's argument is accepted in each kind of call and statement (TRYARG)" {
    try expectAccepted(half ++
        \\record Row:
        \\    size: int
        \\    name: str
        \\
        \\func three(a: int, b: int, c: int) -> int:
        \\    return a + b + c
        \\
        \\func keyed(name: str, named size: int) -> int:
        \\    return size + len(name)
        \\
        \\func text(x: int) -> str fails str:
        \\    const h = try half(x)
        \\    return f"{h}"
        \\
        \\func total(x: int) -> int fails str:
        \\    mut sum = three(1, try half(x), 3)
        \\    sum += keyed("k", size=try half(x))
        \\    const row = Row(size=try half(x), name=try text(x))
        \\    sum = sum + row.size + len(try text(x)) + keyed(try text(x), size=1)
        \\    sum += abs(three(1, abs(try half(x)), 3))
        \\    mut n = 0
        \\    while abs(try half(x + n)) < 4:
        \\        n += 2
        \\    if n > 100:
        \\        return 0
        \\    elif abs(try half(x)) > 0:
        \\        sum += 1
        \\    for i in range(try half(x)):
        \\        sum += i
        \\    _ = abs(try half(x))
        \\    return three(sum, n, try half(x))
        \\
        \\func main() -> int:
        \\    return 0
        \\
    );
}

test "a try is an operand anywhere a value is computed at run time, and the operator after it takes its value (TRY-2)" {
    try expectAccepted(half ++
        \\record Row:
        \\    size: int
        \\    name: str
        \\
        \\func ok(x: int) -> bool fails str:
        \\    return try half(x) > 0
        \\
        \\func pick(xs: int[], x: int) -> int fails str:
        \\    mut sum = 0
        \\    sum += try half(x) + 1
        \\    sum = sum * try half(x) - abs(try half(x) + 1) + -try half(x)
        \\    const ys = [try half(x), 1]
        \\    const m = {"k": try half(x)}
        \\    const s = f"{try half(x)}-{x}"
        \\    const row = Row(size=1 + try half(x), name=f"{try half(x)}")
        \\    sum += xs[try half(x)] + len(xs[0:try half(x)]) + len(ys) + m["k"] + len(s) + row.size
        \\    if x > 5 and try ok(x):
        \\        sum += 1
        \\    elif not try ok(x) or x < 0:
        \\        sum -= 1
        \\    while try half(x + sum) != 0 and sum < 10:
        \\        sum += 2
        \\    assert try half(x) == x // 2, f"half of {x} is {try half(x)}"
        \\    match try half(x):
        \\        case 0:
        \\            return 0
        \\        case _:
        \\            sum += 1
        \\    for i in range(try half(x) + 1):
        \\        sum += i
        \\    return try half(x) + sum
        \\
        \\func main() -> int:
        \\    return 0
        \\
    );
}

test "a try in a value computed when the program is compiled is refused with the form to write (TRY-2)" {
    const tail = "\nfunc main() -> int:\n    return 0\n";
    try expectRefusal(half ++ "const LIMIT: int = try half(4);\n" ++ tail, "E_TRY_POSITION", "a module constant is computed when the program is compiled");
    try expectRefusal(half ++ "func f(n: int = try half(4)) -> int:\n    return n\n" ++ tail, "E_TRY_POSITION", "give the parameter or field no default");
    try expectRefusal(half ++ "record R:\n    n: int = 1 + try half(4)\n" ++ tail, "E_TRY_POSITION", "a default is computed when the program is compiled");
}

test "a try in an operand meets a linear owner, a pending result, an on fail clause and a contract as in an argument (TRY-2)" {
    const token =
        \\@linear
        \\record Token:
        \\    id: int
        \\
        \\func close(own t: Token):
        \\    _ = own t.id
        \\
        \\func both(own t: Token, n: int) -> int:
        \\    close(own t)
        \\    return n
        \\
        \\func taken(r: Result[int, str], n: int) -> int:
        \\    match r:
        \\        case Ok(v):
        \\            return v + n
        \\        case Err(_):
        \\            return n
        \\
        \\func run(x: int) -> int fails str:
        \\    const t = Token(id=1)
        \\
    ;
    const main = "\n\nfunc main() -> int:\n    return 0\n";
    try expectRefusal(half ++ token ++ "    return both(own t, 1 + try half(x))" ++ main, "E_LINEAR_UNCONSUMED", "an earlier argument gives away");
    try expectRefusal(half ++ token ++ "    close(own t)\n    return taken(half(x), 1 + try half(x))" ++ main, "E_RESULT_PROPAGATION", "pending result temporary");
    const armed = half ++ token ++ "    on fail: close(own t)\n";
    const operand_message = "`try` is not a call's argument or an operand";
    try expectRefusal(armed ++ "    const n = 1 + try half(x)\n    close(own t)\n    return n" ++ main, "E_ON_FAIL", operand_message);
    try expectRefusal(armed ++ "    if try half(x) > 1:\n        close(own t)\n        return 1\n    close(own t)\n    return 0" ++ main, "E_ON_FAIL", operand_message);
    try expectRefusal(armed ++ "    if x > 1:\n        close(own t)\n        return 0\n    elif try half(x) > 1:\n        close(own t)\n        return 1\n    close(own t)\n    return 0" ++ main, "E_ON_FAIL", operand_message);
    try expectRefusal(armed ++ "    const s = f\"{try half(x)}\"\n    close(own t)\n    return len(s)" ++ main, "E_ON_FAIL", operand_message);
    try expectRefusal(half ++ "@requires(try half(x) > 0)\nfunc g(x: int) -> int:\n    return x" ++ main, "E_CONTRACT_EFFECT", "cannot return early with `try`");
}

test "a try in a call's argument meets a linear owner, an on fail clause and a contract with their own refusals (TRYARG)" {
    const token =
        \\@linear
        \\record Token:
        \\    id: int
        \\
        \\func use(own token: Token, n: int) -> int:
        \\    const id = own token.id
        \\    return id + n
        \\
        \\func close(own token: Token):
        \\    _ = own token.id
        \\
        \\
    ;
    const main = "\n\nfunc main() -> int:\n    return 0\n";
    const run = "func run(x: int) -> int fails str:\n    const token = Token(id=x)\n";
    const given = "    return use(own token, try half(x))";
    try expectRefusal(half ++ token ++ run ++ given ++ main, "E_LINEAR_UNCONSUMED", "the `@linear` `Token` an earlier argument gives away is not consumed");
    try expectRefusal(half ++ token ++ run ++ "    on fail: close(own token)\n" ++ given ++ main, "E_ON_FAIL", "`try` is not a call's argument");
    try expectRefusal(half ++ "@ensures(abs(try half(result)) > 0)\nfunc run(x: int) -> int fails str:\n    return x" ++ main, "E_CONTRACT_EFFECT", "cannot return early with `try`");
}

test "a try is the value of an assignment to a field, an element or a nested place, for = and the compound forms (TRYFIELD)" {
    try expectAccepted(half ++
        \\record Inner:
        \\    v: int = 0
        \\
        \\record R:
        \\    a: int = 0
        \\    name: str = ""
        \\    inner: Inner
        \\    xs: int[]
        \\
        \\enum Slot:
        \\    empty
        \\    full(value: R)
        \\
        \\func text(x: int) -> str fails str:
        \\    const h = try half(x)
        \\    return f"{h}"
        \\
        \\func fill(mut r: R, mut rows: R[], mut grid: int[][], mut d: dict[str, int], x: int) -> Unit fails str:
        \\    r.a = try half(x)
        \\    r.name = try text(x)
        \\    r.inner.v = try half(x)
        \\    r.xs[0] = try half(x)
        \\    r.a += try half(x)
        \\    r.xs[0] *= try half(x)
        \\    rows[0].inner.v = try half(x)
        \\    rows[len(rows) - 1].xs[0] -= try half(x)
        \\    grid[0][1] = try half(x)
        \\    d["k"] = try half(x)
        \\
        \\func slot(mut slots: Slot[], x: int) -> Unit fails str:
        \\    match mut slots[0]:
        \\        case full(value=payload):
        \\            payload.a = try half(x)
        \\            payload.inner.v += try half(x)
        \\        case empty:
        \\            return
        \\
        \\func main() -> int:
        \\    return 0
        \\
    );
}

test "a try that is a place's value meets a linear owner, an on fail clause and a read-only place as the two-statement form does (TRYFIELD)" {
    const token =
        \\@linear
        \\record Token:
        \\    id: int
        \\
        \\record Box:
        \\    token: Token
        \\    n: int
        \\
        \\func close(own token: Token):
        \\    _ = own token.id
        \\
        \\func fresh(x: int) -> Token fails str:
        \\    return Token(id=try half(x))
        \\
        \\
    ;
    const main = "\n\nfunc main() -> int:\n    return 0\n";
    const run = "func run(mut b: Box, x: int) -> int fails str:\n    const token = Token(id=x)\n";
    // A `@linear` name held across the `try`: the failure path would lose it, as with `const n = try half(x)`.
    try expectRefusal(half ++ token ++ run ++ "    b.n = try half(x)\n    close(own token)\n    return 0" ++ main, "E_LINEAR_UNCONSUMED", "`@linear` owner `token` is not consumed");
    // Replacing a `@linear` field: refused at the write, as `const t = try fresh(x)` then `b.token = t` is.
    try expectRefusal(half ++ token ++ run ++ "    close(own token)\n    b.token = try fresh(x)\n    return 0" ++ main, "E_LINEAR_USE", "would end the `@linear` owner it replaces");
    // In the reach of an `on fail:` the clause would not run on this `try`: refused like `x = try f()`.
    const armed = half ++ token ++ run ++ "    on fail: close(own token)\n";
    try expectRefusal(armed ++ "    b.n = try half(x)\n    close(own token)\n    return 0" ++ main, "E_ON_FAIL", "declare the value first, then use it");
    try expectRefusal(armed ++ "    mut xs = [0]\n    xs[0] += try half(x)\n    close(own token)\n    return xs[0]" ++ main, "E_ON_FAIL", "declare the value first, then use it");
    const read_only = half ++ "record R:\n    a: int\n\nfunc run(r: R, x: int) -> Unit fails str:\n";
    try expectRefusal(read_only ++ "    r.a = try half(x)" ++ main, "E_IMMUTABLE", "read-only");
    // TRY-2: the operator after `try` takes the call's value, so the place's value may be an operand too.
    try expectAccepted(half ++ "func run(mut xs: int[], x: int) -> Unit fails str:\n    xs[0] = try half(x) + 1" ++ main);
}

test "mut before a reserved word names the word, as const does" {
    try expectRefusal("func main() -> int:\n    mut domain = 1\n    return 0\n", "E_SYNTAX", "`domain` is a reserved word and cannot be used as one");
    try expectRefusal("func main() -> int:\n    mut arena: int = 1\n    return 0\n", "E_SYNTAX", "`arena` is a reserved word and cannot be used as one");
    try expectRefusal("func main() -> int:\n    const domain = 1\n    return 0\n", "E_SYNTAX", "`domain` is a reserved word and cannot be used as one");
}

test "a method call on a value says the value has no methods and names the function form" {
    const head = point ++ "func main() -> int:\n    const p = Point(x=1, y=2)\n";
    try expectRefusal(head ++ "    return p.scale(2)\n", "E_UNKNOWN_TYPE", "a record has no methods; write the function form `scale(p, 2)`");
    try expectRefusal(head ++ "    return p.scale(by=3)\n", "E_UNKNOWN_TYPE", "write the function form `scale(p, by=3)`");
    const scalar = "func main() -> int:\n    const n = 3\n    return n.shift(1)\n";
    try expectRefusal(scalar, "E_UNKNOWN_TYPE", "a value of type `int` has no methods; write the function form `shift(n, 1)`");
}

test "a method call whose function form names no function in scope says so, and a Stream names print (B2)" {
    // A lane was told to write `write_line(out, ...)`, a function nothing declares.
    const stream = "func main(out: Stream) -> int:\n    out.write_line(\"hi\")\n    return 0\n";
    try expectRefusal(stream, "E_UNKNOWN_TYPE", "a value of type `Stream` has no methods and no function `write_line` is in scope; write to a Stream with `print(out, ...)`");
    const head = point ++ "func main() -> int:\n    const p = Point(x=1, y=2)\n";
    try expectRefusal(head ++ "    return p.norm()\n", "E_UNKNOWN_TYPE", "write the function form `norm(p)`; no function `norm` is declared or in the prelude, so declare it first");
    // A declared function and a prelude function keep the plain advice.
    try expectRefusal(stream ++ "func write_line(out: Stream, text: str) -> int:\n    return 0\n", "E_UNKNOWN_TYPE", "a value of type `Stream` has no methods; write the function form `write_line(out, \"hi\")`");
    try expectRefusal("func main(out: Stream) -> int:\n    out.flush()\n    return 0\n", "E_UNKNOWN_TYPE", "write the function form `flush(out)`");
}

test "a method call through a field or an element says the value has no methods, as a local does" {
    const head = point ++ "record Box:\n    p: Point\n    n: int\n\nfunc main() -> int:\n    const b = Box(p=Point(x=1, y=2), n=3)\n    const ps = [Point(x=1, y=2)]\n";
    try expectRefusal(head ++ "    return b.p.scale(2)\n", "E_COLLECTION_METHOD", "a record has no methods; write the function form `scale(b.p, 2)`");
    try expectRefusal(head ++ "    return ps[0].scale(by=3)\n", "E_CALL_ARGUMENT", "a record has no methods; write the function form `scale(ps[0], by=3)`");
    try expectRefusal(head ++ "    return b.n.shift(1)\n", "E_COLLECTION_METHOD", "a value of type `int` has no methods; write the function form `shift(b.n, 1)`");
    try expectRefusal(head ++ "    const xs = [1, 2]\n    return xs[0].shift()\n", "E_COLLECTION_METHOD", "a value of type `int` has no methods; write the function form `shift(xs[0])`");
    try expectRefusal(head ++ "    return b.p.norm()\n", "E_COLLECTION_METHOD", "a record has no methods; write the function form `norm(b.p)`");
}

test "a method call through a field on a text or a list keeps its own accepted-methods advice" {
    const head = "record Box:\n    name: str\n    items: int[]\n\nfunc main() -> int:\n    const b = Box(name=\"a\", items=[1])\n";
    try expectRefusal(head ++ "    return len(b.name.shout())\n", "E_COLLECTION_METHOD", "unknown method for a str receiver; it has no methods: its operations are functions of the `strings` module");
    try expectRefusal(head ++ "    return len(b.items.shout())\n", "E_COLLECTION_METHOD", "unknown method for a int[] receiver; it has no methods: its operations are functions of the `lists` module");
}

/// Require the source spelling of the internal type name `raw` to be `expected`.
fn expectSpelling(raw: []const u8, expected: []const u8) !void {
    const spelled = try typed.sourceTypeSpelling(t.allocator, raw);
    defer t.allocator.free(spelled);
    try t.expectEqualStrings(expected, spelled);
}

test "an internal type name in a test-runner message is spelled as source spells it" {
    try expectSpelling("i64", "int");
    try expectSpelling("f64", "float");
    try expectSpelling("List<i64>", "int[]");
    try expectSpelling("List<List<f64>>", "float[][]");
    try expectSpelling("Option<i64>", "int?");
    try expectSpelling("std_result::Option<str>", "str?");
    try expectSpelling("List<main::Box>", "main.Box[]");
    try expectSpelling("func(i64) -> i64", "func(int) -> int");
    try expectSpelling("def(i64, str) -> bool", "func(int, str) -> bool");
    try expectSpelling("dict<str,i64>", "dict[str, int]");
    try expectSpelling("dict<str,List<i64>>", "dict[str, int[]]");
    try expectSpelling("[2]main::Box", "FixedArray[main.Box, 2]");
    try expectSpelling("List<[3]i64>", "FixedArray[int, 3][]");
    try expectSpelling("Simd[4]f32", "Simd[f32, 4]");
    try expectSpelling("host_cap", "Host");
    try expectSpelling("Result<bool,str>", "Result[bool, str]");
    try expectSpelling("MyList<i64>", "MyList[int]");
    try expectSpelling("m::Option<i64>", "m.Option[int]");
    try expectSpelling("u8", "u8");
}

test "a method signature in a message spells its types as source does" {
    const parse = "func main() -> int:\n    const s = \"12\"\n    const n = s.parse_int(1)\n    return 0\n";
    try expectRefusal(parse, "E_ARITY", "`str.parse_int() -> int?` takes 0 arguments");
    const lines = "func main() -> int:\n    const s = \"a b\"\n    const parts = s.splitlines(1)\n    return len(parts)\n";
    try expectRefusal(lines, "E_ARITY", "`str.splitlines() -> str[]` takes 0 arguments");
    const append = "func main() -> int:\n    mut xs: bool[] = []\n    xs.append(True, False)\n    return len(xs)\n";
    try expectRefusal(append, "E_ARITY", "`bool[].append(value: bool) -> Unit` takes 1 argument");
    const decode = "func main() -> int:\n    const b = b\"abc\"\n    const s = b.decode(1)\n    return 0\n";
    try expectRefusal(decode, "E_ARITY", "`bytes.decode() -> str fails str` takes 0 arguments");
}

/// The entry every program below ends with, so its first diagnostic is the one under test.
const with_main = "\n\nfunc main() -> int:\n    return 0\n";

test "every message that reaches a conditional value names the if/else statement, and the colon form is the removed conditional (F-50)" {
    // `if c: a else: b` on one line is read as the removed conditional, whose refusal carries the statement repair.
    try expectRefusal("func flag(on: bool) -> str:\n    const word = if on: \"true\" else: \"false\"\n    return word\n" ++ with_main, "E_CONDITIONAL_EXPRESSION_REMOVED", "use an if or match statement assigning a named result");
    try expectRefusal("func flag(on: bool) -> str:\n    const word = if on then \"true\" else \"false\"\n    return word\n" ++ with_main, "E_CONDITIONAL_EXPRESSION_REMOVED", "use an if or match statement assigning a named result");
    // Any other spelling names the statement form, never `then`.
    const statement = "a condition cannot choose a value inside an expression: declare the result first";
    try expectRefusal("func flag(on: bool) -> str:\n    const word = if on \"true\" else \"false\"\n    return word\n" ++ with_main, "E_CONDITIONAL", statement);
    try expectRefusal("func flag(on: bool) -> str:\n    const word = if on: \"true\"\n    return word\n" ++ with_main, "E_CONDITIONAL", statement);
}

test "messages about comprehensions, generators, yield arms, lambdas and tuples name forms that are accepted (F-50)" {
    const loop = "comprehensions were removed; use a typed accumulator and explicit for/if statements";
    try expectRefusal("func f(xs: int[]) -> int[]:\n    return [for x in xs: x + 1]\n" ++ with_main, "E_COMPREHENSION", loop);
    try expectRefusal("func f(xs: int[]) -> int[]:\n    return sorted(x for x in xs, reverse=True)\n" ++ with_main, "E_SYNTAX", "generator arguments were removed");
    const arms = "match expressions were removed; use a match statement whose arms assign a named result or return";
    try expectRefusal("func f(x: int?) -> int:\n    const v = match x:\n        case Some(n):\n            yield n\n        case None:\n            pass\n    return v\n" ++ with_main, "E_MATCH_YIELD", arms);
    try expectRefusal("func f() -> int:\n    const g = lambda _: 2\n    return 1\n" ++ with_main, "E_LAMBDA_PARAMETER", "lambdas were removed; declare a named top-level function");
    const two_names = "func f(xs: int[]) -> int:\n    mut n = 0\n    for a, b in xs:\n        n = n + a\n    return n\n";
    try expectRefusal(two_names ++ with_main, "E_ITERATION", "two iteration names require `enumerate(values)`, `zip(left, right)` or `dicts.items(mapping)`");
    try expectRefusal("func f() -> int:\n    x, y\n    return 0\n" ++ with_main, "E_SYNTAX", "tuples were removed, so write one statement per value or use a record with named fields");
}

// F-72 (it was F-52's refusal): the message of an `assert` is any `str` expression, so a quoted text with an operator
// after it is accepted, and what is refused names the `assert`.
test "an assert's message is any text expression, and a second comma or a message of another type names the assert (F-72)" {
    const joined = "func f(key: str) -> int:\n    assert len(key) == 2, \"a range key: \" + key\n    return 0\n";
    var c = try language.Compilation.init(t.allocator, "advice.selka", joined ++ with_main);
    defer c.deinit();
    try c.check();
    const second = "func f(key: str) -> int:\n    assert len(key) == 2, \"a key\", key\n    return 0\n";
    try expectRefusal(second ++ with_main, "E_SYNTAX", "an assert takes a condition and one message, and the message is one text; a second comma does not add a third operand: join the texts with `+`");
    const number = "func f(key: str) -> int:\n    assert len(key) == 2, len(key)\n    return 0\n";
    try expectRefusal(number ++ with_main, "E_TYPE", "expected str, found int: the message of an `assert` is one text; a format string shows another value");
}

// FR19 item 1: a message names a scalar the way the source spells it (`int`), not by the checker's tag (`i64`). The checker
// has a tag and a record name for each type, and a message that printed one of them said `i64` for `int` and `Box<i64>`
// for `Box[int]`. Each program is a different message that printed the tag or name.
test "a message names int as the source does, not as the checker's internal i64" {
    const parse = "func parse(text: str) -> int fails str:\n    if text == \"\":\n        fail \"empty\"\n    return 1\n\n\n";
    try expectRefusal(
        parse ++ "func main() -> int:\n    match parse(\"x\"):\n        case Ok:\n            return 1\n        case Err(r):\n            return len(r)\n",
        "E_PATTERN_PAYLOAD",
        "`case Ok` names a case that carries int, so",
    );
    const pair = "enum Shape:\n    pair(left: int, right: float)\n    none\n\n\n";
    try expectRefusal(
        pair ++ "func main() -> int:\n    match Shape.none:\n        case pair:\n            return 1\n        case none:\n            return 2\n",
        "E_NAMED_PATTERN",
        "the fields `left: int` and `right: float`",
    );
    const fails_int = "func parse(text: str) -> int fails int:\n    if text == \"\":\n        fail 3\n    return 1\n\n\n";
    try expectRefusal(
        fails_int ++ "func main() -> int:\n    const v = parse(\"x\") else:\n        return 2\n    return v\n",
        "E_PATTERN_PAYLOAD",
        "can fail with int, so the `else`",
    );
    try expectRefusal(
        "func main() -> int:\n    const n = 3\n    match n:\n        case \"a\":\n            return 1\n        case _:\n            return 2\n",
        "E_LITERAL_ARM",
        "the matched value, which is `int`",
    );
    try expectRefusal(
        "func main() -> int:\n    const n = 3\n    match n:\n        case 1:\n            return 1\n    return 2\n",
        "E_INCOMPLETE_MATCH",
        "a match on `int` must end with `case _`",
    );
    try expectRefusal(
        "func same[T](a: T, b: T) -> T:\n    return a\n\n\nfunc main() -> int:\n    const x = same(1, 2.5)\n    return 0\n",
        "E_GENERIC_INFERENCE",
        "inferred as int from the argument `1` and as float from the argument `2.5`",
    );
}

test "a message inside a generic body names the concrete scalars it holds as the source does" {
    const parse = "func parse(text: str) -> int fails str:\n    return 1\n\n\n";
    try expectRefusal(
        parse ++ "func shim[T](value: T) -> int:\n    match parse(\"x\"):\n        case Ok:\n            return 1\n        case Err(r):\n            return len(r)\n",
        "E_PATTERN_PAYLOAD",
        "`case Ok` names a case that carries int, so",
    );
    const fails_int = "func parse(text: str) -> int fails int:\n    return 1\n\n\n";
    try expectRefusal(
        fails_int ++ "func shim[T](value: T) -> int:\n    const v = parse(\"x\") else:\n        return 2\n    return v\n",
        "E_PATTERN_PAYLOAD",
        "can fail with int, so the `else`",
    );
}

// FR19 item 2: the removed `.contains(value)` method is refused with the sentence for the receiver's type (the one sentence
// that said "removed for dictionaries" was false for a set, text, bytes and a list), in a concrete body, in a generic body
// and on a text constant, and a receiver that is no collection gets the sentence for a value with no methods.
test "the removed contains method is worded for each receiver type, in concrete and generic bodies" {
    const tail = "\n\nfunc main() -> int:\n    return 0\n";
    try expectRefusal(
        "func f(seen: set[str], name: str) -> bool:\n    return seen.contains(name)" ++ tail,
        "E_REMOVED_SPELLING",
        "`seen.contains(name)` was removed for sets; use `name in seen`",
    );
    try expectRefusal(
        "func f(m: dict[str, int], name: str) -> bool:\n    return m.contains(name)" ++ tail,
        "E_REMOVED_SPELLING",
        "`m.contains(name)` was removed for dictionaries; use `name in m`",
    );
    try expectRefusal(
        "func f(text: str, part: str) -> bool:\n    return text.contains(part)" ++ tail,
        "E_REMOVED_SPELLING",
        "`text.contains(part)` was removed for text; use `part in text`, which tests for a substring",
    );
    try expectRefusal(
        "func f(data: bytes, part: bytes) -> bool:\n    return data.contains(part)" ++ tail,
        "E_REMOVED_SPELLING",
        "`data.contains(part)` was removed for bytes; use `part in data`, which tests for a byte or a run of bytes",
    );
    try expectRefusal(
        "func f(xs: int[], value: int) -> bool:\n    return xs.contains(value)" ++ tail,
        "E_REMOVED_SPELLING",
        "`xs.contains(value)` was removed for lists, which have no `in`; use `lists.contains(xs, value)`",
    );
    try expectRefusal(
        "func shim[T](value: T, seen: set[str]) -> bool:\n    return seen.contains(\"a\")" ++ tail,
        "E_REMOVED_SPELLING",
        "`seen.contains(\"a\")` was removed for sets; use `\"a\" in seen`",
    );
    try expectRefusal(
        "record Holder:\n    names: str[]\n\nfunc shim[T](value: T, h: Holder) -> bool:\n    return h.names.contains(\"a\")" ++ tail,
        "E_REMOVED_SPELLING",
        "`h.names.contains(\"a\")` was removed for lists, which have no `in`; use `lists.contains(h.names, \"a\")`",
    );
    try expectRefusal(
        "const WORD: str = \"abc\"\n\nfunc f() -> bool:\n    return WORD.contains(\"a\")" ++ tail,
        "E_REMOVED_SPELLING",
        "`WORD.contains(\"a\")` was removed for text; use `\"a\" in WORD`",
    );
    try expectRefusal("record Point:\n    x: int\n\nfunc f(p: Point) -> bool:\n    return p.contains(1)" ++ tail, "E_UNKNOWN_TYPE", "a record has no methods");
}

test "the removed contains method is reported at the method's name, as the removed spelling always was (FR19)" {
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", "func main() -> int:\n    const seen: set[str] = {\"a\"}\n    if seen.contains(\"a\"):\n        return 1\n    return 0\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_REMOVED_SPELLING", item.code);
    try t.expectEqualStrings("contains", compilation.src.text(item.span));
    try t.expectEqualStrings("seen.contains(\"a\")", compilation.src.text(item.provenance.fix.?.edit.span));
    try t.expectEqualStrings("\"a\" in seen", item.provenance.fix.?.edit.text);
}

/// Check `source`, which must be refused, and require its first diagnostic to be `E_GENERIC_INFERENCE` with exactly `message`; the
/// repair is the one edit that replaces `fix[0]` with `fix[1]`, or none when `fix` is null.
fn expectListsContainsRefusal(source: []const u8, message: []const u8, fix: ?[2][]const u8) !void {
    // Checked as a project, which may `import` a standard module (a single unit cannot).
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), try std.fmt.allocPrint(arena.allocator(), "{s}\n\nfunc main() -> int:\n    return 0\n", .{source}));
    try t.expect(!report.passed);
    const item = report.diagnostics[0];
    try t.expectEqualStrings("E_GENERIC_INFERENCE", item.code);
    try t.expectEqualStrings(message, item.message);
    const wanted = fix orelse {
        try t.expect(item.provenance.fix == null);
        return;
    };
    try t.expectEqualStrings(wanted[0], report.text(item.provenance.fix.?.edit.span));
    try t.expectEqualStrings(wanted[1], item.provenance.fix.?.edit.text);
    try t.expectEqual(@as(usize, 0), item.provenance.fix.?.more.len);
}

// MSG-B 1: `lists.contains(data, 10)` on bytes or text was told only that the argument shape does not match, which names no repair. The
// answer is the operator `in`, with the operands swapped: the message says so, and the call is rewritten when both operands are plain.
test "lists.contains of text, bytes, a set or a dictionary is told to write the operator in, and rewritten when its operands are plain" {
    const head = "import lists\n\nfunc f(text: str, data: bytes, seen: set[str], table: dict[str, int], name: str) -> bool:\n";
    try expectListsContainsRefusal(
        head ++ "    return lists.contains(text, \"ell\")\n",
        "`lists.contains` is only for lists, and its first argument is text: whether text holds a part is the operator `in`: write `\"ell\" in text`",
        .{ "lists.contains(text, \"ell\")", "\"ell\" in text" },
    );
    try expectListsContainsRefusal(
        head ++ "    return not lists.contains(data, 10)\n",
        "`lists.contains` is only for lists, and its first argument is bytes: whether bytes hold a byte or a run of bytes is the operator `in`: write `10 in data`",
        .{ "not lists.contains(data, 10)", "10 not in data" },
    );
    try expectListsContainsRefusal(
        head ++ "    return lists.contains(seen, name) == True\n",
        "`lists.contains` is only for lists, and its first argument is a set: whether a set holds a value is the operator `in`: write `name in seen`",
        .{ "lists.contains(seen, name)", "(name in seen)" },
    );
    try expectListsContainsRefusal(
        head ++ "    return lists.contains(table, name)\n",
        "`lists.contains` is only for lists, and its first argument is a dictionary: whether a dictionary has a key is the operator `in`: write `name in table`",
        .{ "lists.contains(table, name)", "name in table" },
    );
    // A generic body is checked the same way.
    try expectListsContainsRefusal(
        "import lists\n\nfunc shim[T](value: T, text: str) -> bool:\n    return lists.contains(text, \"e\")\n",
        "`lists.contains` is only for lists, and its first argument is text: whether text holds a part is the operator `in`: write `\"e\" in text`",
        .{ "lists.contains(text, \"e\")", "\"e\" in text" },
    );
    // An operand that is more than a name, a field or a literal, and a keyword argument, keep the
    // sentence with the placeholders of the type, and no edit.
    try expectListsContainsRefusal(
        head ++ "    return lists.contains(text, name + \"x\")\n",
        "`lists.contains` is only for lists, and its first argument is text: whether text holds a part is the operator `in`: write `part in text`",
        null,
    );
    try expectListsContainsRefusal(
        head ++ "    return lists.contains(values=data, value=10)\n",
        "`lists.contains` is only for lists, and its first argument is bytes: whether bytes hold a byte or a run of bytes is the operator `in`: write `part in data`",
        null,
    );
}

// FR26 item 6: a message names an option type as the source writes it, `T?`, and the way out of a recursive record names a `T?` field.
test "a message writes an option type as T? and not as Option[T]" {
    const boxed = "record Box[T]:\n    value: T\n\n\nfunc make[T](x: T) -> Box[T]:\n    return Box[T](value=x)\n\n\n";
    try expectRefusal(boxed ++ "func main() -> int:\n    const o: int? = Some(2)\n    const b = make(o)\n    const n: int = b\n    return n\n", "E_TYPE", "expected int, found Box[int?]");
    try expectRefusal(boxed ++ "func main() -> int:\n    const o: int? = Some(2)\n    const m: Box[int?] = 3\n    return len(m.value)\n", "E_TYPE", "expected Box[int?], found int");
    try expectRefusal("record Node:\n    next: Node\n\n\nfunc main() -> int:\n    return 0\n", "E_RECURSIVE_RECORD", "such as a `T?` field, a payload-free union case or a `T[]`");
}

// FX17: a slice of a `byte_buffer` is a buffer, and a `bytes` parameter takes its octets through `bytes(...)`.
test "a byte_buffer given where bytes is expected is told to write bytes(...) of it (FX17)" {
    const head = "func takes_bytes(data: bytes) -> int:\n    return len(data)\n\nfunc main(out: Stream) -> int:\n    const buf = byte_buffer([97, 98, 99])\n";
    try expectRefusal(head ++ "    print(out, takes_bytes(buf[1:3]))\n    return 0\n", "E_TYPE", "expected bytes, found byte_buffer; write `bytes(buf[1:3])` for its octets");
    // Where the span is not the value (a typed binding points at its type), the advice does not quote it.
    try expectRefusal(head ++ "    const b: bytes = buf\n    print(out, takes_bytes(b))\n    return 0\n", "E_TYPE", "expected bytes, found byte_buffer; write `bytes(...)` of the value for its octets");
}

// FR31 item 1: the entry names its Streams `out` and `err` (E_MAIN), so an unused one is deleted, not renamed `_out`; the
// diagnostic offers no rename there (FR35: its one edit is the deletion). Every other capability parameter keeps the rename advice
// and its repair.
test "an unused Stream parameter of main is told to be deleted and offers no rename (FR31)" {
    const delete = "capability parameter `out` is never used; delete the parameter (an entry Stream parameter must be named `out` or `err`, so it cannot be renamed `_out`)";
    try expectRefusal("func main(out: Stream) -> int:\n    return 0\n", "E_UNUSED_CAPABILITY", delete);
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", "func main(args: str[], err: Stream) -> int:\n    return len(args)\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_UNUSED_CAPABILITY", item.code);
    try t.expect(std.mem.indexOf(u8, item.message, "delete the parameter") != null);
    try t.expect(std.mem.indexOf(u8, item.message, "rename it") == null);
    const edit = item.provenance.fix.?.edit;
    try t.expectEqualStrings("", edit.text);
    try t.expectEqualStrings(", err: Stream", compilation.src.text(edit.span));
}

/// `text` after the first edit that one of its diagnostics carries, and null when it checks or none carries one.
fn withFirstEdit(text: []const u8) !?[]u8 {
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", text);
    defer compilation.deinit();
    compilation.check() catch for (compilation.diagnostics.items) |item| {
        const fix = item.provenance.fix orelse continue;
        const span = fix.edit.span;
        const edited = try std.mem.concat(t.allocator, u8, &.{ text[0..span.start], fix.edit.text, text[span.end..] });
        return edited;
    };
    return null;
}

/// `text` repaired the way `selka fix` does, a round at a time (a repair that collides with another waits for the next round).
fn repairedByRounds(text: []const u8) ![]u8 {
    var current = try t.allocator.dupe(u8, text);
    for (0..4) |_| {
        const next = try withFirstEdit(current) orelse return current;
        t.allocator.free(current);
        current = next;
    }
    return current;
}

/// A program of `entry` as the signature of `main`, with a body that reads `err` or `args` when the signature has them.
fn entryProgram(entry: []const u8, body: []const u8) ![]u8 {
    const text = try std.mem.concat(t.allocator, u8, &.{ "func main(", entry, ") -> int:\n", body });
    return text;
}

// FR35: the message's one certain edit is carried: the parameter goes, with the comma that separates it, and the file checks.
test "an unused Stream parameter of main is deleted with its comma by its repair, in each shape of the list (FR35)" {
    const reads_err = "    print(err, \"x\")\n    return 0\n";
    const reads_args = "    return len(args)\n";
    const shapes = [_][3][]const u8{
        .{ "out: Stream", "", "    return 0\n" },
        .{ "out: Stream, err: Stream", "err: Stream", reads_err },
        .{ "args: str[], out: Stream, err: Stream", "args: str[], err: Stream", "    print(err, \"x\")\n    return len(args)\n" },
        .{ "err: Stream, out: Stream", "err: Stream", reads_err },
        .{ "args: str[], out: Stream", "args: str[]", reads_args },
        .{ "out: Stream, err: Stream", "", "    return 0\n" },
        .{ "args: str[], out: Stream, err: Stream", "args: str[]", reads_args },
        .{ "\n    args: str[],\n    out: Stream,\n    err: Stream,\n", "\n    args: str[],\n    err: Stream,\n", "    print(err, \"x\")\n    return len(args)\n" },
        .{ "\n    args: str[],\n    out: Stream,\n    err: Stream\n", "\n    args: str[]\n", reads_args },
        .{ "\n    out: Stream,\n", "", "    return 0\n" },
    };
    for (shapes) |shape| {
        const before = try entryProgram(shape[0], shape[2]);
        defer t.allocator.free(before);
        const after = try entryProgram(shape[1], shape[2]);
        defer t.allocator.free(after);
        const repaired = try repairedByRounds(before);
        defer t.allocator.free(repaired);
        try t.expectEqualStrings(after, repaired);
    }
}

test "the repair of an unused Stream parameter of main edits the parameter and the comma beside it, and nothing else (FR35)" {
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", "func main(args: str[], out: Stream, err: Stream) -> int:\n    return len(args)\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.len);
    const out = compilation.diagnostics.items[0].provenance.fix.?.edit;
    const err = compilation.diagnostics.items[1].provenance.fix.?.edit;
    try t.expectEqualStrings("out: Stream, ", compilation.src.text(out.span));
    try t.expectEqualStrings(", err: Stream", compilation.src.text(err.span));
    try t.expectEqualStrings("", out.text);
    try t.expectEqualStrings("", err.text);
}

// FR35: a deletion that is not certain leaves the message and carries no edit.
test "an unused Stream parameter of main that something else names or a comment sits beside has no repair (FR35)" {
    const unrepaired = [_][]const u8{
        // `main` is called: the call would keep its argument.
        "func helper(out: Stream) -> int:\n    print(out, \"x\")\n    return main(out)\n\nfunc main(out: Stream) -> int:\n    return 0\n",
        // A comment between the parameters would be taken with the edit.
        "func main(\n    out: Stream,  # the output\n    err: Stream,\n) -> int:\n    print(err, \"x\")\n    return 0\n",
    };
    for (unrepaired) |text| {
        try t.expect(try withFirstEdit(text) == null);
        try expectRefusal(text, "E_UNUSED_CAPABILITY", "delete the parameter");
    }
    // A mention of `main` in a comment line is no call.
    const mention = "# main takes the output\nfunc main(out: Stream) -> int:\n    return 0\n";
    const repaired = try repairedByRounds(mention);
    defer t.allocator.free(repaired);
    try t.expectEqualStrings("# main takes the output\nfunc main() -> int:\n    return 0\n", repaired);
}

test "an unused capability parameter that may be named with an underscore keeps the rename advice and its repair (FR31)" {
    const rename = "capability parameter `out` is never used; rename it to `_out` to retain the callback signature, or remove it";
    const callback = "func callback(out: Stream, value: int) -> int:\n    return value + 1\n\nfunc main() -> int:\n    return 0\n";
    try expectRefusal(callback, "E_UNUSED_CAPABILITY", rename);
    // `main`'s other capabilities accept an underscore name, so the advice stands for them.
    const host = "capability parameter `host` is never used; rename it to `_host` to retain the callback signature, or remove it";
    try expectRefusal("func main(host: Host) -> int:\n    return 0\n", "E_UNUSED_CAPABILITY", host);
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", callback);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("_out", compilation.diagnostics.items[0].provenance.fix.?.edit.text);
}

// FR31 item 2: a parameter without `named` may not follow one that has it, and the message says so, names both and says what the repair
// writes (`selka fix` marks the later one `named`). The same pass words the `*` separator and the old place of `mut`.
test "a parameter after a named one is told what it follows and what to write (FR31)" {
    const head = "func f(named factor: int, items: int[]) -> int:\n    return factor + len(items)\n\nfunc main() -> int:\n    return f(factor=1, items=[1])\n";
    try expectRefusal(head, "E_FRONTEND_SYNTAX", "`items` follows the `named` parameter `factor`, and a parameter without `named` cannot follow one that has it: write `named items`, or move `items` before `factor`");
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", head);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const edit = compilation.diagnostics.items[0].provenance.fix.?.edit;
    try t.expectEqualStrings("items", compilation.src.text(.{ .start = edit.span.start, .end = edit.span.start + 5 }));
    try t.expectEqualStrings("named items: ", edit.text);
    try expectRefusal("func f(a: int, *, b: int) -> int:\n    return a + b\n\nfunc main() -> int:\n    return f(1, b=2)\n", "E_FRONTEND_SYNTAX", "`b` follows the `*` separator, so it is a `named` parameter: write `named b`");
    try expectRefusal("func f(a: mut int[]) -> int:\n    return len(a)\n\nfunc main() -> int:\n    return 0\n", "E_FRONTEND_SYNTAX", "write `mut` before the parameter name, as in `mut a`, and not before its type");
}

// FR31 item 2: since FR29 `named` before a colon is a parameter's name, so `named = 3` is a parameter called `named` that has no type;
// it reads as `count = 3` does, and the spellings that are accepted stay accepted.
test "a parameter written without its type is told it needs one (FR31)" {
    const no_default = "parameter `count` has no type; a parameter needs its type after a colon, as in `count: int`";
    try expectRefusal("func f(named = 3) -> int:\n    return 0\n\nfunc main() -> int:\n    return f()\n", "E_SYNTAX", "parameter `named` has no type; a parameter needs its type after a colon, as in `named: int = 3`");
    try expectRefusal("func f(count = 3) -> int:\n    return 0\n\nfunc main() -> int:\n    return f()\n", "E_SYNTAX", "parameter `count` has no type; a parameter needs its type after a colon, as in `count: int = 3`");
    try expectRefusal("func f(count) -> int:\n    return 0\n\nfunc main() -> int:\n    return 0\n", "E_SYNTAX", no_default);
    try expectRefusal("func f(a: int, count, b: int) -> int:\n    return a + b\n\nfunc main() -> int:\n    return 0\n", "E_SYNTAX", no_default);
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", "func f(named: int = 3, named limit: int = 4) -> int:\n    return named + limit\n\nfunc main() -> int:\n    return f(limit=2) - 5\n");
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

// FR34 item 2: `nosuch.f(1)` was `E_UNKNOWN_TYPE: type is not declared`, which says nothing about a call or about the qualifier. The
// qualifier is no local, parameter, type or imported module, and no module file of the project has its name (the session's FR32
// pass answers a name that is a module file with the import, and keeps this message for one that is not).
test "a call whose qualifier names nothing says the name is not in scope (FR34)" {
    const nothing = "`nosuch` is not a name in scope here: it is no local, parameter, type or imported module, and no module file of this project has that name";
    try expectRefusal("func main(out: Stream) -> int:\n    print(out, nosuch.f(1))\n    return 0\n", "E_UNKNOWN_TYPE", nothing);
    try expectRefusal("func main(out: Stream) -> int:\n    nosuch.f(1)\n    return 0\n", "E_UNKNOWN_TYPE", nothing);
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", "func main(out: Stream) -> int:\n    print(out, nosuch.f(1))\n    return 0\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("nosuch", compilation.src.text(item.span));
    try t.expect(std.mem.indexOf(u8, item.message, "did you mean") == null);
    try t.expect(item.provenance.fix == null);
}

test "a qualifier that is nothing names the locals and types in scope that are close to it (FR34)" {
    const typo = "func f(count: int) -> int:\n    return cuont.f(count)\n\nfunc main(out: Stream) -> int:\n    print(out, f(1))\n    return 0\n";
    try expectRefusal(typo, "E_UNKNOWN_TYPE", "`cuont` is not a name in scope here: it is no local, parameter, type or imported module, and no module file of this project has that name; did you mean `count`?");
    const head = point ++ "func main() -> int:\n";
    try expectRefusal(head ++ "    const p = Pont.make(1)\n    return p.x\n", "E_UNKNOWN_TYPE", "`Pont` is not a name in scope here");
    try expectRefusal(head ++ "    const p = Pont.make(1)\n    return p.x\n", "E_UNKNOWN_TYPE", "did you mean `Point`?");
    // A local keeps the advice of a value, and a type keeps its own refusals.
    try expectRefusal(head ++ "    const p = Point(x=1, y=2)\n    return p.scale(2)\n", "E_UNKNOWN_TYPE", "a record has no methods");
}

// FR34 item 1: `clock.now()` was told to write `now(clock)`, with "no function `now` is declared", which points at a function that does
// not exist. The function is `time.now(clock)`, after `import time`: when exactly one standard module declares a function of that name
// for the receiver's type, the answer names it and its import, and the repair carries the rewrite and the import.
test "a method call on a Clock names the standard module's function and its import (FR34)" {
    const head = "func main(out: Stream, clock: Clock) -> int:\n    print(out, clock.now())\n    return 0\n";
    try expectRefusal(head, "E_UNKNOWN_TYPE", "a value of type `Clock` has no methods; write the function form `time.now(clock)`, from the standard module `time`, and add `import time`");
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", head);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    try t.expect(std.mem.indexOf(u8, item.message, "declare it first") == null);
    const fix = item.provenance.fix.?;
    try t.expectEqualStrings("clock.now()", compilation.src.text(fix.edit.span));
    try t.expectEqualStrings("time.now(clock)", fix.edit.text);
    try t.expectEqual(@as(usize, 1), fix.more.len);
    try t.expectEqualStrings("import time\n\n", fix.more[0].text);
    try t.expectEqual(@as(usize, 0), fix.more[0].span.start);
}

test "a method call keeps its plain advice where no standard module declares the function for the receiver, and a real method stays accepted (FR34)" {
    // No module declares `shout` of a `Clock`. (Two modules declare `decode` of `bytes`, which is also a real method, so the
    // two-candidate rule is tested on the library search itself in `standard_library_test.zig`.)
    const shout = "func main(out: Stream, clock: Clock) -> int:\n    print(out, clock.shout())\n    return 0\n";
    try expectRefusal(shout, "E_UNKNOWN_TYPE", "write the function form `shout(clock)`; no function `shout` is declared or in the prelude, so declare it first");
    // A function the program declares is the one meant, whatever a module declares.
    const own = "func now(clock: Clock) -> int:\n    return 0\n\nfunc main(out: Stream, clock: Clock) -> int:\n    print(out, clock.now())\n    return 0\n";
    try expectRefusal(own, "E_UNKNOWN_TYPE", "a value of type `Clock` has no methods; write the function form `now(clock)`");
    // A record's own type may share a library type's spelling: it is never looked up.
    const record = "record Duration:\n    n: int\n\nfunc main(out: Stream) -> int:\n    const d = Duration(n=1)\n    print(out, d.add(d))\n    return 0\n";
    try expectRefusal(record, "E_UNKNOWN_TYPE", "a record has no methods; write the function form `add(d, d)`; no function `add` is declared or in the prelude, so declare it first");
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", "func main(out: Stream, fs: Filesystem) -> int:\n    print(out, fs.read_text(\"a\"))\n    return 0\n");
    defer compilation.deinit();
    try compilation.check();
}

test "a Stream and an Entropy name the standard module's function for the method written (FR34)" {
    const stream = "func main(out: Stream) -> int:\n    print(out, out.text())\n    return 0\n";
    try expectRefusal(stream, "E_UNKNOWN_TYPE", "write the function form `streams.text(out)`, from the standard module `streams`, and add `import streams`");
    const entropy = "func main(out: Stream, rng: Entropy) -> int:\n    print(out, rng.from_entropy())\n    return 0\n";
    try expectRefusal(entropy, "E_UNKNOWN_TYPE", "a value of type `Entropy` has no methods; write the function form `random.from_entropy(rng)`, from the standard module `random`, and add `import random`");
}

/// Check `source`, which must be refused with `E_COLLECTION_METHOD` and exactly the message `unknown method for a <receiver type> receiver;
/// <advice>`; its repair must be the call `written` replaced by `rewritten` with `import_line` as the one more edit, or no repair at all
/// when `rewritten` is null.
fn expectCapabilityAnswer(source: []const u8, advice: []const u8, written: []const u8, rewritten: ?[]const u8, import_line: ?[]const u8) !void {
    // Checked as a project, which may `import` a standard module (a single unit cannot).
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), source);
    try t.expect(!report.passed);
    const item = report.diagnostics[0];
    try t.expectEqualStrings("E_COLLECTION_METHOD", item.code);
    try t.expect(std.mem.startsWith(u8, item.message, "unknown method for a "));
    try t.expectEqualStrings(advice, item.message[std.mem.indexOf(u8, item.message, "receiver; ").? + "receiver; ".len ..]);
    const text = rewritten orelse return t.expect(item.provenance.fix == null);
    const fix = item.provenance.fix.?;
    try t.expectEqualStrings(written, report.text(fix.edit.span));
    try t.expectEqualStrings(text, fix.edit.text);
    try t.expectEqual(@as(usize, if (import_line == null) 0 else 1), fix.more.len);
    if (import_line) |line| try t.expectEqualStrings(line, fix.more[0].text);
}

/// What a message says after the function form when the file lacks the module: `, from the standard module `time`, and add `import time``.
fn lackingText(comptime module: []const u8) []const u8 {
    return ", from the standard module `" ++ module ++ "`, and add `import " ++ module ++ "`";
}
const lacking_time = lackingText("time");
const lacking_random = lackingText("random");
const lacking_process = lackingText("process");

/// A program whose function `stamp` makes `call` on a capability held in a record field: `ctx.clock`, or `holder.ctx.clock`. `before`
/// is what the file starts with: an import, or a function of its own.
fn stamping(comptime before: []const u8, comptime call: []const u8) []const u8 {
    return before ++ "record Ctx:\n    clock: Clock\n    rng: Entropy\n    proc: Process\n    stop: Stop\n\nrecord Holder:\n    ctx: Ctx\n\n" ++
        "func stamp(ctx: Ctx, holder: Holder) -> int:\n    return " ++ call ++ "\n\n" ++
        "func main(out: Stream, clock: Clock, rng: Entropy, proc: Process, stop: Stop) -> int:\n" ++
        "    const ctx = Ctx(clock=clock, rng=rng, proc=proc, stop=stop)\n    print(out, stamp(ctx, Holder(ctx=ctx)))\n    return 0\n";
}

// FR37: `ctx.clock.now()` said "a Clock has no methods; read it with time.now(clock)", a value the writer does not have, with no
// import and no repair. The answer now names the call with the receiver as written and carries the repair for a plain field path.
test "a method call on a capability reached through a field names the module function with the receiver as written (FR37)" {
    const answer = "a Clock has no methods; write the function form `time.now(ctx.clock)`";
    try expectCapabilityAnswer(stamping("", "ctx.clock.now()"), answer ++ lacking_time, "ctx.clock.now()", "time.now(ctx.clock)", "import time\n\n");
    // A two-deep path and an operand keep the writer's text.
    try expectCapabilityAnswer(
        stamping("", "holder.ctx.clock.sleep(3)"),
        "a Clock has no methods; write the function form `time.sleep(holder.ctx.clock, 3)`" ++ lacking_time,
        "holder.ctx.clock.sleep(3)",
        "time.sleep(holder.ctx.clock, 3)",
        "import time\n\n",
    );
    // A file that imports the module is told the function only, and the repair is the rewrite alone.
    try expectCapabilityAnswer(stamping("import time\n\n", "ctx.clock.now()"), answer ++ ", from the standard module `time`", "ctx.clock.now()", "time.now(ctx.clock)", null);
}

test "a method that is not the module's function is told how the capability is read, without a repair (FR37)" {
    try expectCapabilityAnswer(stamping("", "ctx.clock.tick()"), "a Clock has no methods; read it with time.now(ctx.clock), and add `import time`", "", null, null);
    try expectCapabilityAnswer(stamping("import time\n\n", "ctx.clock.tick()"), "a Clock has no methods; read it with time.now(ctx.clock)", "", null, null);
}

test "the same capability keeps today's text where the file renames the module, and a function of the program's own is the one meant (FR37)" {
    try expectCapabilityAnswer(stamping("import time as t\n\n", "ctx.clock.now()"), "a Clock has no methods; read it with time.now(clock)", "", null, null);
    const own = "func now(clock: Clock) -> int:\n    return 0\n\n";
    try expectCapabilityAnswer(stamping(own, "ctx.clock.now()"), "a Clock has no methods; read it with time.now(ctx.clock), and add `import time`", "", null, null);
}

test "an Entropy, a Process and a Stop reached through a field are told their module's function (FR37)" {
    try expectCapabilityAnswer(
        stamping("", "ctx.rng.from_entropy()"),
        "an Entropy has no methods; write the function form `random.from_entropy(ctx.rng)`" ++ lacking_random,
        "ctx.rng.from_entropy()",
        "random.from_entropy(ctx.rng)",
        "import random\n\n",
    );
    try expectCapabilityAnswer(
        stamping("", "ctx.stop.stop_requested()"),
        "a Stop has no methods; write the function form `process.stop_requested(ctx.stop)`" ++ lacking_process,
        "ctx.stop.stop_requested()",
        "process.stop_requested(ctx.stop)",
        "import process\n\n",
    );
    try expectCapabilityAnswer(stamping("", "ctx.proc.run(1)"), "a Process has no methods; write the function form `process.run(ctx.proc, 1)`" ++ lacking_process, "ctx.proc.run(1)", "process.run(ctx.proc, 1)", "import process\n\n");
    // Another method of theirs is told how each is read, with the import.
    try expectCapabilityAnswer(stamping("", "ctx.stop.requested()"), "a Stop has no methods; read it with process.stop_requested(ctx.stop), and add `import process`", "", null, null);
    try expectCapabilityAnswer(stamping("", "ctx.proc.spawn(1)"), "a Process has no methods; start a program with process.run(ctx.proc, request), and add `import process`", "", null, null);
    try expectCapabilityAnswer(stamping("", "ctx.rng.next()"), "an Entropy has no methods; read it with random.from_entropy(ctx.rng), and add `import random`", "", null, null);
}

test "a call with a line break in it, or a receiver that is not a field path, is named without a repair (FR37)" {
    try expectCapabilityAnswer(stamping("", "ctx.clock.sleep(\n        3)"), "a Clock has no methods; write the function form `time.sleep(ctx.clock, 3)`" ++ lacking_time, "", null, null);
    try expectCapabilityAnswer(stamping("", "(ctx.clock).now()"), "a Clock has no methods; write the function form `time.now((ctx.clock))`" ++ lacking_time, "", null, null);
}

/// The program of the FR45 tests: every place a pattern binds a name that its body does not read, in the spellings the language
/// has (a bare field, a labelled field, a single payload, a nested case, `is`, `while ... is` and a bind-or-else's failure).
const unread_forms =
    \\enum Json:
    \\    number(n: int, lit: str)
    \\    text(value: str)
    \\    pair(left: int, right: int)
    \\
    \\enum Outer:
    \\    inner(w: Json)
    \\    plain(k: int)
    \\
    \\result Read:
    \\    ok: int,
    \\    err: int
    \\
    \\func score(j: Json) -> int:
    \\    match j:
    \\        case number(n, lit):
    \\            return n
    \\        case text(value=v):
    \\            return 1
    \\        case pair(left, right=r):
    \\            return left
    \\
    \\func read(r: Read) -> int:
    \\    match r:
    \\        case ok(v):
    \\            return 1
    \\        case err(code):
    \\            return code
    \\
    \\func nested(o: Outer) -> int:
    \\    match o:
    \\        case inner(w=number(n=a, lit=b)):
    \\            return 1
    \\        case inner(w=text(value=_)):
    \\            return 2
    \\        case inner(w=pair(left=_, right=_)):
    \\            return 3
    \\        case plain(k=_):
    \\            return 5
    \\
    \\func option_is(v: int?) -> int:
    \\    if v is Some(x):
    \\        return 1
    \\    return 0
    \\
    \\func result_is(r: Result[int, str]) -> int:
    \\    if r is Err(e):
    \\        return 2
    \\    return 0
    \\
    \\func result_else(r: Result[int, str]) -> int:
    \\    const y = r else Err(m):
    \\        return 3
    \\    return y
    \\
    \\func option_while(v: int?) -> int:
    \\    mut cursor = v
    \\    while cursor is Some(c):
    \\        cursor = None
    \\    return 0
    \\
    \\func main() -> int:
    \\    return score(Json.pair(left=1, right=2)) + read(Read.ok(1)) + nested(Outer.plain(k=1)) + option_is(None) + result_is(Ok(1)) + result_else(Ok(1)) + option_while(None)
    \\
;

/// `text` with every edit its W_UNUSED_BINDING warnings carry applied, the last one first so the offsets hold.
fn withUnreadRepairs(text: []const u8, found: []const diagnostic.Diagnostic) ![]u8 {
    var edited = try t.allocator.dupe(u8, text);
    var index = found.len;
    while (index > 0) {
        index -= 1;
        const edit = found[index].provenance.fix.?.edit;
        const next = try std.mem.concat(t.allocator, u8, &.{ edited[0..edit.span.start], edit.text, edited[edit.span.end..] });
        t.allocator.free(edited);
        edited = next;
    }
    return edited;
}

// spec-case: FR45
test "an unread pattern binding is told what to write in its place and carries that edit, and the repaired program checks clean (FR45)" {
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", unread_forms);
    defer compilation.deinit();
    try compilation.check();
    const expected = [_][3][]const u8{
        .{ "lit", "binding `lit` is never read; write `lit=_` in its place to ignore this field", "lit=_" },
        .{ "v", "binding `v` is never read; write `_` in its place to ignore this field", "_" },
        .{ "r", "binding `r` is never read; write `_` in its place to ignore this field", "_" },
        .{ "v", "binding `v` is never read; write `_` in its place to ignore the payload", "_" },
        .{ "a", "binding `a` is never read; write `_` in its place to ignore this field", "_" },
        .{ "b", "binding `b` is never read; write `_` in its place to ignore this field", "_" },
        .{ "x", "binding `x` is never read; write `_` in its place to ignore the payload", "_" },
        .{ "e", "binding `e` is never read; write `_` in its place to ignore the payload", "_" },
        .{ "m", "binding `m` is never read; write `_` in its place to ignore the payload", "_" },
        .{ "c", "binding `c` is never read; write `_` in its place to ignore the payload", "_" },
    };
    const found = compilation.diagnostics.items;
    try t.expectEqual(expected.len, found.len);
    for (expected, found) |want, item| {
        try t.expectEqualStrings("W_UNUSED_BINDING", item.code);
        try t.expectEqualStrings(want[0], compilation.src.text(item.span));
        try t.expectEqualStrings(want[1], item.message);
        try t.expectEqualStrings(want[2], item.provenance.fix.?.edit.text);
        try t.expectEqual(item.span.start, item.provenance.fix.?.edit.span.start);
    }
    const repaired = try withUnreadRepairs(unread_forms, found);
    defer t.allocator.free(repaired);
    var again = try language.Compilation.init(t.allocator, "advice.selka", repaired);
    defer again.deinit();
    try again.check();
    try t.expectEqual(@as(usize, 0), again.diagnostics.items.len);
    try t.expect(std.mem.indexOf(u8, repaired, "case number(n, lit=_):") != null);
    try t.expect(std.mem.indexOf(u8, repaired, "case pair(left, right=_):") != null);
    try t.expect(std.mem.indexOf(u8, repaired, "if v is Some(_):") != null);
    try t.expect(std.mem.indexOf(u8, repaired, "const y = r else Err(_):") != null);
}

// spec-case: FR45
test "a binding that is not a pattern's, one the arm writes, one in an alternative list and one of an ambiguous case keep the plain message (FR45)" {
    const plain = "binding is never read; use it or remove it, preserving initializer effects with `_ =` when needed";
    const text =
        \\enum Cell:
        \\    up(n: int, tag: str)
        \\    down(n: int, tag: str)
        \\
        \\enum Pick:
        \\    ok(x: int)
        \\
        \\result Take:
        \\    ok: int,
        \\    err: int
        \\
        \\func param(count: int) -> int:
        \\    return 0
        \\
        \\func decl() -> int:
        \\    const x = 3
        \\    for i in range(3):
        \\        pass
        \\    return 0
        \\
        \\func alternatives(c: Cell) -> int:
        \\    match c:
        \\        case up(n, tag) | down(n, tag):
        \\            return n
        \\
        \\func ambiguous(a: Pick) -> int:
        \\    match a:
        \\        case ok(x):
        \\            return 1
        \\
        \\func writes(mut c: Cell) -> int:
        \\    match mut c:
        \\        case up(n, tag):
        \\            n = 9
        \\            return 1
        \\        case down(n, tag):
        \\            return n
        \\
        \\func main() -> int:
        \\    mut c = Cell.up(n=1, tag="t")
        \\    return param(1) + decl() + alternatives(c) + ambiguous(Pick.ok(x=1)) + writes(mut c)
        \\
    ;
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", text);
    defer compilation.deinit();
    try compilation.check();
    var plain_count: usize = 0;
    var repaired_count: usize = 0;
    for (compilation.diagnostics.items) |item| {
        if (!std.mem.eql(u8, item.code, "W_UNUSED_BINDING")) continue;
        if (item.provenance.fix == null) {
            try t.expectEqualStrings(plain, item.message);
            plain_count += 1;
        } else repaired_count += 1;
    }
    // Plain: `count`, the constant `x`, both alternatives' `tag`, the ambiguous `x` and the `n` that is only written. Repaired: the `tag`
    // of each arm of the `match mut` that nothing touches.
    try t.expectEqual(@as(usize, 6), plain_count);
    try t.expectEqual(@as(usize, 2), repaired_count);
}

// spec-case: FR45
test "the repair of an unread pattern binding is found in the body that holds it, when two bodies spell the same pattern (FR45)" {
    const text =
        \\enum Shape:
        \\    circle(r: int)
        \\    square(side: int)
        \\
        \\func first(s: Shape) -> int:
        \\    match s:
        \\        case circle(r):
        \\            return 1
        \\        case square(side):
        \\            return side
        \\
        \\func second(s: Shape) -> int:
        \\    match s:
        \\        case circle(r):
        \\            return r
        \\        case square(side):
        \\            return 2
        \\
        \\func main() -> int:
        \\    return first(Shape.circle(r=1)) + second(Shape.square(side=1))
        \\
    ;
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", text);
    defer compilation.deinit();
    try compilation.check();
    const found = compilation.diagnostics.items;
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqual(std.mem.indexOf(u8, text, "circle(r):").? + "circle(".len, found[0].span.start);
    try t.expectEqual(std.mem.lastIndexOf(u8, text, "square(side):").? + "square(".len, found[1].span.start);
    try t.expectEqualStrings("r=_", found[0].provenance.fix.?.edit.text);
    try t.expectEqualStrings("side=_", found[1].provenance.fix.?.edit.text);
    const repaired = try withUnreadRepairs(text, found);
    defer t.allocator.free(repaired);
    try t.expect(std.mem.indexOf(u8, repaired, "case circle(r=_):\n            return 1") != null);
    try t.expect(std.mem.indexOf(u8, repaired, "case square(side=_):\n            return 2") != null);
}

const range_lead = "`range` is a loop source (`for i in range(a, b):`), not a collection, so `in` cannot test against it";

/// Check `func f(...)` whose `if` tests `condition`, one unit, and require its first diagnostic to be the unknown
/// function `range` at the name `range`, with exactly `message`. `repair` is the text its one edit writes over the
/// whole `in` expression, or null for no edit; a repair is applied and the program must then check.
fn expectRangeAnswer(condition: []const u8, message: []const u8, repair: ?[]const u8) !void {
    const head = "func f(x: int, hi: int, lo: int) -> bool:\n    if ";
    const tail = ":\n        return True\n    return False\n\n\nfunc main() -> int:\n    return 0\n";
    const program = try std.mem.concat(t.allocator, u8, &.{ head, condition, tail });
    defer t.allocator.free(program);
    var c = try language.Compilation.init(t.allocator, "advice.selka", program);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const first = c.diagnostics.items[0];
    try t.expectEqualStrings("E_UNKNOWN_FUNCTION", first.code);
    try t.expectEqualStrings("range", c.src.text(first.span));
    try t.expectEqualStrings(message, first.message);
    const fix = first.provenance.fix orelse return t.expect(repair == null);
    try t.expectEqualStrings(repair.?, fix.edit.text);
    try t.expectEqual(@as(usize, 0), fix.more.len);
    try t.expectEqualStrings(condition, c.src.text(fix.edit.span));
    const fixed = try std.mem.concat(t.allocator, u8, &.{ head, repair.?, tail });
    defer t.allocator.free(fixed);
    var again = try language.Compilation.init(t.allocator, "advice.selka", fixed);
    defer again.deinit();
    try again.check();
}

// SP3-F-11: `x in range(a, b)` names the comparison with the bounds as written, and repairs it when the needle and every
// bound is a name or a number and there is no step. The refusal keeps its code and its place at `range`.
test "checkMembership names the comparison for x in range(a, b) and repairs a plain one (SP3-F-11)" {
    try expectRangeAnswer("x in range(0, hi)", range_lead ++ ": write the comparison `0 <= x < hi`", "0 <= x < hi");
    try expectRangeAnswer("x in range(lo, hi)", range_lead ++ ": write the comparison `lo <= x < hi`", "lo <= x < hi");
    try expectRangeAnswer("x in range(hi)", range_lead ++ ": write the comparison `0 <= x < hi`", "0 <= x < hi");
    try expectRangeAnswer("x in range(-1, 5)", range_lead ++ ": write the comparison `-1 <= x < 5`", "-1 <= x < 5");
    try expectRangeAnswer("x not in range(0, hi)", range_lead ++ ": write the comparison `x < 0 or hi <= x`", "(x < 0 or hi <= x)");
}

test "checkMembership names x in range(...) with a call, a step or a long operand without a repair (SP3-F-11)" {
    try expectRangeAnswer("x in range(0, len([1, 2]))", range_lead ++ ": write the comparison `0 <= x < len([1, 2])`", null);
    try expectRangeAnswer("abs(x) in range(lo, hi)", range_lead ++ ": write the comparison `lo <= abs(x) < hi`", null);
    try expectRangeAnswer("x in range(lo, hi, 2)", range_lead ++ "; with a step, write the bounds and the step's remainder out as comparisons", null);
    try expectRangeAnswer(
        "x in range(0, hi + hi + hi + hi + hi + hi + hi + hi + hi + hi + hi)",
        range_lead ++ ": write the comparison `a <= x < b`",
        null,
    );
}

// SP3-F-11: the refusal is the one a project reports (`E_UNKNOWN_SYMBOL`, `this module declares no`), and a module that
// declares its own `range` is not refused, so the new text never answers a call that resolves.
test "checkMembership keeps the project code for x in range(a, b), and a declared range is no refusal (SP3-F-11)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const refused = try fixture.check(a, "func f(x: int, hi: int) -> bool:\n    if x in range(0, hi):\n        return True\n    return False\n\n\nfunc main() -> int:\n    return 0\n");
    const found = refused.firstError().?;
    try t.expectEqualStrings("E_UNKNOWN_SYMBOL", found.code);
    try t.expectEqualStrings(range_lead ++ ": write the comparison `0 <= x < hi`", found.message);
    try t.expectEqualStrings("range", refused.text(found.span));
    try t.expectEqualStrings("0 <= x < hi", found.provenance.fix.?.edit.text);
    const own = try fixture.check(a, "func range(a: int, b: int) -> int[]:\n    return [a, b]\n\n\nfunc f(x: int) -> bool:\n    return x in range(0, 5)\n\n\nfunc main() -> int:\n    return 0\n");
    try t.expect(own.firstError() == null or std.mem.indexOf(u8, own.firstError().?.message, "loop source") == null);
}

// The argument-count message of a whole-path file helper prints the spelling that works, the method of the Filesystem, and the
// `Unit` in it is the spelling the compiler reads (`Result[None, str]` is refused as a type). The free `write_text(fs, ...)` is a
// removed spelling, so a message that printed it offered the author a second refusal.
test "the arity message of a file helper prints the method that works, with types that check" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const free = try fixture.check(a, "func f(fs: Filesystem) -> bool:\n    _ = write_text(fs, \"a\")\n    return True\n\n\nfunc main() -> int:\n    return 0\n");
    try t.expectEqualStrings("E_ARITY", free.firstError().?.code);
    const removed = "`write_text(fs, ...)` is a second spelling and was removed; write `fs.write_text(path: str, text: str) -> Result[Unit, str]`";
    try t.expectEqualStrings(removed ++ ", which takes 2 arguments (the Filesystem is its receiver); this call passes 2 in all", free.firstError().?.message);
    const method = try fixture.check(a, "func f(fs: Filesystem) -> bool:\n    _ = fs.mkdir()\n    return True\n\n\nfunc main() -> int:\n    return 0\n");
    try t.expectEqualStrings("`fs.mkdir(path: str) -> Result[Unit, str]` takes 1 argument, but this call passes 0", method.firstError().?.message);
    const input = try fixture.check(a, "func f(input: Input) -> bool:\n    _ = input.read()\n    return True\n\n\nfunc main() -> int:\n    return 0\n");
    try t.expectEqualStrings("`input.read(max: int) -> bytes` takes 1 argument, but this call passes 0", input.firstError().?.message);
    const channel = try fixture.check(a, "func f(fs: Filesystem) -> bool:\n    _ = run_process(fs, b\"a\")\n    return True\n\n\nfunc main() -> int:\n    return 0\n");
    try t.expectEqualStrings("E_ARITY", channel.firstError().?.code);
    try t.expectEqualStrings("`run_process` is the standard library's own channel, which only the library may call; use the `process` module's functions", channel.firstError().?.message);
}

/// One helper of the Filesystem as its message prints it: the name, its parameters, its answer, a call that passes them and the
/// type that call is declared with. `open` is the binary mode's, the answer the guide gives it.
const Helper = struct { name: []const u8, parameters: []const u8, answer: []const u8, call: []const u8 };
const helpers = [_]Helper{
    .{ .name = "open", .parameters = "path: str, mode: str", .answer = "Result[File, str]", .call = "\"a\", \"rb\"" },
    .{ .name = "read_file", .parameters = "path: str", .answer = "Result[bytes, str]", .call = "\"a\"" },
    .{ .name = "read_text", .parameters = "path: str", .answer = "Result[str, str]", .call = "\"a\"" },
    .{ .name = "write_file", .parameters = "path: str, data: bytes", .answer = "Result[Unit, str]", .call = "\"a\", b\"x\"" },
    .{ .name = "write_text", .parameters = "path: str, text: str", .answer = "Result[Unit, str]", .call = "\"a\", \"x\"" },
    .{ .name = "exists", .parameters = "path: str", .answer = "bool", .call = "\"a\"" },
    .{ .name = "listdir", .parameters = "path: str", .answer = "Result[str[], str]", .call = "\"a\"" },
    .{ .name = "mkdir", .parameters = "path: str", .answer = "Result[Unit, str]", .call = "\"a\"" },
    .{ .name = "remove", .parameters = "path: str", .answer = "Result[Unit, str]", .call = "\"a\"" },
    .{ .name = "atomic_write_file", .parameters = "path: str, data: bytes", .answer = "Result[Unit, str]", .call = "\"a\", b\"x\"" },
    .{ .name = "lock_directory", .parameters = "path: str", .answer = "Result[File, str]", .call = "\"a\"" },
    .{ .name = "sync_directory", .parameters = "path: str", .answer = "Result[Unit, str]", .call = "\"a\"" },
    .{ .name = "read_regular_file", .parameters = "path: str, max_bytes: int", .answer = "Result[bytes, str]", .call = "\"a\", 10" },
    .{ .name = "rename_path", .parameters = "from: str, to: str", .answer = "Result[Unit, str]", .call = "\"a\", \"b\"" },
    .{ .name = "stat_path", .parameters = "path: str", .answer = "Result[bytes, str]", .call = "\"a\"" },
    .{ .name = "lock_file", .parameters = "path: str", .answer = "Result[File, str]", .call = "\"a\"" },
    .{ .name = "try_lock_file", .parameters = "path: str", .answer = "Result[File, str]", .call = "\"a\"" },
    .{ .name = "canonical_path", .parameters = "path: str", .answer = "Result[str, str]", .call = "\"a\"" },
    .{ .name = "chmod_path", .parameters = "path: str, mode: int", .answer = "Result[Unit, str]", .call = "\"a\", 1" },
    .{ .name = "touch_path", .parameters = "path: str", .answer = "Result[Unit, str]", .call = "\"a\"" },
    .{ .name = "set_modified_path", .parameters = "path: str, nanoseconds: int", .answer = "Result[Unit, str]", .call = "\"a\", 1" },
    .{ .name = "atomic_write_file_mode", .parameters = "path: str, data: bytes, mode: int", .answer = "Result[Unit, str]", .call = "\"a\", b\"x\", 1" },
    .{ .name = "stat_follow_path", .parameters = "path: str", .answer = "Result[bytes, str]", .call = "\"a\"" },
    .{ .name = "list_entries_path", .parameters = "path: str", .answer = "Result[bytes, str]", .call = "\"a\"" },
    .{ .name = "replace_file", .parameters = "path: str, data: bytes", .answer = "Result[Unit, str]", .call = "\"a\", b\"x\"" },
    .{ .name = "replace_file_mode", .parameters = "path: str, data: bytes, mode: int", .answer = "Result[Unit, str]", .call = "\"a\", b\"x\", 1" },
    .{ .name = "replace_file_synced", .parameters = "path: str, data: bytes", .answer = "Result[Unit, str]", .call = "\"a\", b\"x\"" },
    .{ .name = "replace_file_synced_mode", .parameters = "path: str, data: bytes, mode: int", .answer = "Result[Unit, str]", .call = "\"a\", b\"x\", 1" },
    .{ .name = "symlink_path", .parameters = "target: str, path: str", .answer = "Result[Unit, str]", .call = "\"a\", \"b\"" },
    .{ .name = "statfs_path", .parameters = "path: str", .answer = "Result[bytes, str]", .call = "\"a\"" },
    .{ .name = "read_at_path", .parameters = "path: str, offset: bytes, max_bytes: int", .answer = "Result[bytes, str]", .call = "\"a\", b\"x\", 1" },
    .{ .name = "read_link_path", .parameters = "path: str", .answer = "Result[str, str]", .call = "\"a\"" },
    .{ .name = "link_path", .parameters = "target: str, path: str", .answer = "Result[Unit, str]", .call = "\"a\", \"b\"" },
    .{ .name = "mkdir_mode", .parameters = "path: str, mode: int", .answer = "Result[Unit, str]", .call = "\"a\", 1" },
    .{ .name = "create_mode", .parameters = "path: str, mode: int", .answer = "Result[File, str]", .call = "\"a\", 1" },
    .{ .name = "list_directory", .parameters = "path: str, max_entries: int", .answer = "Result[str[], str]", .call = "\"a\", 1" },
};

// Every helper of the Filesystem, each tried on the compiler: called with no arguments the message prints its method with the
// count it takes, and the call written as the message prints it checks with the answer the message names.
test "the arity message of every Filesystem helper prints a method that checks with the answer it names" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (helpers) |helper| {
        const wrong = try std.fmt.allocPrint(a, "func f(fs: Filesystem) -> bool:\n    _ = fs.{s}()\n    return True\n\n\nfunc main() -> int:\n    return 0\n", .{helper.name});
        const refused = try fixture.check(a, wrong);
        const count = std.mem.count(u8, helper.parameters, ",") + 1;
        const expected = try std.fmt.allocPrint(a, "`fs.{s}({s}) -> {s}` takes {d} argument{s}, but this call passes 0", .{ helper.name, helper.parameters, helper.answer, count, if (count == 1) "" else "s" });
        try t.expectEqualStrings(expected, refused.firstError().?.message);
        const right = try std.fmt.allocPrint(a, "func f(fs: Filesystem) -> bool:\n    const made: {s} = fs.{s}({s})\n    _ = made\n    return True\n\n\nfunc main() -> int:\n    return 0\n", .{ helper.answer, helper.name, helper.call });
        try t.expect((try fixture.check(a, right)).firstError() == null);
    }
}

/// The files of a project of user modules, read through the project loader by path.
const Modules = struct {
    files: []const language.embedded_project.File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Modules = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.files, path, limit);
    }
};

/// Check the project `files` (the entry point is `main.selka`), which must be refused, and require its first diagnostic to
/// carry `code` and a message that contains `advice`.
fn expectProjectRefusal(files: []const language.embedded_project.File, code: []const u8, advice: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var modules: Modules = .{ .files = files };
    var project = language.project.Project.init(arena.allocator());
    try project.load(.{ .context = &modules, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    const first = compilation.diagnostics.items.items[0];
    try t.expectEqualStrings(code, first.code);
    try t.expect(std.mem.indexOf(u8, first.message, advice) != null);
}

// R5B-MSGS 1: a bare constant or function value of an imported module (`LIMIT` after `import util`) is `E_UNKNOWN_NAME`, not a miss of the
// interface, and says which module declares it; the qualifier is the repair when one does.
test "a bare constant that an imported module declares names the module and writes its qualifier" {
    const util = "public const LIMIT: int = 7\n\n\nconst HIDDEN: int = 1\n\n\npublic func double(n: int) -> int:\n    return n * 2\n";
    const lead = "name is not defined in this scope";
    const main = "import util\n\n\nfunc main() -> int:\n    return LIMIT + HIDDEN\n";
    try expectProjectRefusal(&.{ .{ .path = "main.selka", .bytes = main }, .{ .path = "util.selka", .bytes = util } }, "E_UNKNOWN_NAME", lead ++ "; the imported module `util` declares it: write `util.LIMIT`");
    // A private constant is not offered.
    const hidden = "import util\n\n\nfunc main() -> int:\n    return HIDDEN\n";
    try expectProjectRefusal(&.{ .{ .path = "main.selka", .bytes = hidden }, .{ .path = "util.selka", .bytes = util } }, "E_UNKNOWN_NAME", lead);
    // Two imported modules that declare it are both named, with no single spelling.
    const both = "import util\nimport other\n\n\nfunc main() -> int:\n    return LIMIT\n";
    const files = [_]language.embedded_project.File{ .{ .path = "main.selka", .bytes = both }, .{ .path = "util.selka", .bytes = util }, .{ .path = "other.selka", .bytes = "public const LIMIT: int = 9\n" } };
    try expectProjectRefusal(&files, "E_UNKNOWN_NAME", "the imported modules `util` and `other` each declare it: write `util.LIMIT` or `other.LIMIT`, whichever you mean");
}

const shapes_module = "public enum Value:\n    array(items: int[])\n    pair(left: int, right: float)\n    none\n";
const shapes_match = "import shapes\n\n\nfunc main() -> int:\n    match shapes.Value.none:\n        case array(elems):\n            return len(elems)\n        case none:\n            return 0\n";

// Round 3, item 1: `case array(elems):` on `array(items: int[])` was refused with a message that did not say the name in a
// pattern is the field's own. Three programs paid seven refused calls. The message of the local enum (`E_FRONTEND_VARIANT`)
// and of an imported one (`E_NAMED_PATTERN`) now names the case's fields and shows the own-name and the renaming forms.
test "a pattern that binds a payload field under another name says the field's own name and the renaming form" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const own = "`array`'s field is `items`: `case array(items):` binds it under its own name, `case array(items=elems):` renames it";
    const local = "enum Value:\n    array(items: int[])\n    pair(left: int, right: float)\n    none\n\n\nfunc main() -> int:\n    const v = Value.array(items=[1])\n    match v:\n";
    const one = (try fixture.check(arena.allocator(), local ++ "        case array(elems):\n            return len(elems)\n        case none:\n            return 0\n")).firstError().?;
    try t.expectEqualStrings("E_FRONTEND_VARIANT", one.code);
    try t.expectEqualStrings(own, one.message);
    try expectProjectRefusal(&.{ .{ .path = "main.selka", .bytes = shapes_match }, .{ .path = "shapes.selka", .bytes = shapes_module } }, "E_NAMED_PATTERN", own);
    const generic = "import shapes\n\n\nfunc unbox[T](b: shapes.Box[T], fallback: T) -> T:\n    match b:\n        case full(x):\n" ++
        "            return x\n        case empty:\n            return fallback\n\n\nfunc main() -> int:\n    return 0\n";
    const generic_files = [_]language.embedded_project.File{
        .{ .path = "main.selka", .bytes = generic },
        .{ .path = "shapes.selka", .bytes = "public enum Box[T]:\n    full(item: T)\n    empty\n" },
    };
    const item = "`full`'s field is `item`: `case full(item):` binds it under its own name, `case full(item=x):` renames it";
    try expectProjectRefusal(&generic_files, "E_NAMED_PATTERN", item);
    const two = (try fixture.check(arena.allocator(), local ++ "        case pair(a, b):\n            return a\n        case _:\n            return 0\n")).firstError().?;
    try t.expectEqualStrings("E_FRONTEND_VARIANT", two.code);
    const several = "`pair`'s fields are `left`, `right`: a bare name in the pattern is a field's own name, and `left=a` binds `left` as `a`";
    try t.expectEqualStrings(several, two.message);
}

// Round 4: `case Failed(_):` was told that `case Failed(message=_):` "renames" the field, when the writer wanted to discard it; and
// an imported case's message named the first unlabelled field only, though `selka fix` labels every one.
test "a pattern that discards a field says the labelled form discards it, and an imported case names each unlabelled field" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const discard = "`Failed`'s field is `message`: `case Failed(message):` binds it under its own name, `case Failed(message=_):` discards it";
    const local = "enum Value:\n    Failed(message: str)\n    pair(left: int, right: float)\n    none\n\n\nfunc main() -> int:\n    const v = Value.none\n    match v:\n";
    const one = (try fixture.check(arena.allocator(), local ++ "        case Failed(_):\n            return 1\n        case _:\n            return 0\n")).firstError().?;
    try t.expectEqualStrings(discard, one.message);
    const two = (try fixture.check(arena.allocator(), local ++ "        case pair(_, y):\n            return 1\n        case _:\n            return 0\n")).firstError().?;
    try t.expectEqualStrings("`pair`'s fields are `left`, `right`: a bare name in the pattern is a field's own name, and `left=_` discards `left`, `right=y` binds `right` as `y`", two.message);
    const module = "public enum Value:\n    Failed(message: str)\n    pair(left: int, right: float)\n    wide(a: int, b: int, c: int, d: int, e: int, f: int)\n    none\n";
    const head = "import shapes\n\n\nfunc main() -> int:\n    match shapes.Value.none:\n";
    const tail = "        case _:\n            return 0\n";
    const imported = [_]struct { []const u8, []const u8 }{
        .{ "        case Failed(_):\n            return 1\n", discard },
        .{ "        case pair(_, y):\n            return 1\n", "`pair`'s fields are `left`, `right`: a bare name in the pattern is a field's own name, and `left=_` discards `left`, `right=y` binds `right` as `y`" },
        .{ "        case pair(a, y):\n            return 1\n", "and `left=a` binds `left` as `a`, `right=y` binds `right` as `y`" },
        // A field bound under its own name is already labelled in effect, and is not named.
        .{ "        case pair(left, y):\n            return 1\n", "and `right=y` binds `right` as `y`" },
        .{
            "        case wide(x1, x2, _, x4, x5, x6):\n            return 1\n",
            "`wide`'s fields are `a`, `b`, `c`, `d` and 2 more: a bare name in the pattern is a field's own name, and `a=x1` binds `a` as `x1`, " ++
                "`b=x2` binds `b` as `x2`, `c=_` discards `c`, `d=x4` binds `d` as `x4` and 2 more",
        },
    };
    for (imported) |case| {
        const main = try std.fmt.allocPrint(arena.allocator(), "{s}{s}{s}", .{ head, case[0], tail });
        try expectProjectRefusal(&.{ .{ .path = "main.selka", .bytes = main }, .{ .path = "shapes.selka", .bytes = module } }, "E_NAMED_PATTERN", case[1]);
    }
}

/// Check `source`, which must be refused, and require its first diagnostic to be `E_TYPE` with exactly `message`, and the repair to be
/// `try ` written before the call at `call` in the source when `call` is given, or none when it is null.
fn expectMissingTry(source: []const u8, message: []const u8, call: ?[]const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "advice.selka", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_TYPE", item.code);
    try t.expectEqualStrings(message, item.message);
    const wanted = call orelse return t.expect(item.provenance.fix == null);
    const edit = item.provenance.fix.?.edit;
    try t.expectEqualStrings("try ", edit.text);
    try t.expectEqual(edit.span.start, edit.span.end);
    try t.expect(std.mem.startsWith(u8, source[edit.span.start..], wanted));
}

// R5B-MSGS 2: `2 + parse("1")`, `show(parse("22"))` and `mut n: int = parse("333")` said only "expected int, found Result[int, str]" to two programs
// in two rounds. A direct call of a function declared `fails` names the call and the two ways out, and carries `try ` as its repair when the
// enclosing function declares the same `fails`.
test "a fails call used as its plain value names try and the else form, and try is the repair when the function can pass the error on" {
    const advice = "expected int, found Result[int, str]; `half` can fail: write `try half(...)` to take its value and pass the error on, " ++
        "or handle it with `const n = half(...) else Err(e):`";
    const show = "func show(n: int) -> int:\n    return n + 1\n\n\n";
    const head = half ++ show ++ "func main() -> int fails str:\n";
    try expectMissingTry(head ++ "    const total = 2 + half(4)\n    return total\n", advice, "half(4)");
    try expectMissingTry(head ++ "    const shown = show(half(2))\n    return shown\n", advice, "half(2)");
    try expectMissingTry(head ++ "    mut n: int = half(6)\n    return n\n", advice, "half(6)");
    try expectMissingTry(head ++ "    mut n = 1\n    n = half(8)\n    return n\n", advice, "half(8)");
    try expectMissingTry(head ++ "    mut n = 1\n    n += half(8)\n    return n\n", advice, "half(8)");
    // The call on the left of the operator lacks the right operand's type, and says the same.
    try expectMissingTry(head ++ "    const total = half(4) + 2\n    return total\n", advice, "half(4)");
    try expectMissingTry(head ++ "    const total = 2 + half(4) * 3\n    return total\n", advice, "half(4)");
    try expectMissingTry(half ++ "func again(x: int) -> int fails str:\n    return half(x)\n\n\nfunc main() -> int:\n    return 0\n", advice, "half(x)");
    // A function that does not declare `fails` cannot use `try`: the message says what it would declare, and there is no repair.
    try expectMissingTry(half ++ show ++ "func main() -> int:\n    return show(half(2))\n", "expected int, found Result[int, str]; `half` can fail: " ++
        "handle it with `const n = half(...) else Err(e):`, or declare `fails str` on this function and write `try half(...)`", null);
    // An error type the enclosing function does not carry: the call is named, and `try` is not offered as the certain repair.
    try expectMissingTry(half ++ show ++ "func main() -> int fails int:\n    return show(half(2))\n", "expected int, found Result[int, str]; `half` can fail: " ++
        "write `try half(...)` to take its value and pass the error on (this function's `fails` must carry `str`), or handle it with `const n = half(...) else Err(e):`", null);
}

test "a Result held in a variable keeps the plain type message, and so does a success type that is not the one expected" {
    const bound = half ++ "func main() -> int fails str:\n    const r = half(2)\n    const total = 2 + r\n    return total\n";
    try expectMissingTry(bound, "expected int, found Result[int, str]", null);
    const other = half ++ "func main() -> int fails str:\n    const text: str = half(2)\n    return 0\n";
    try expectMissingTry(other, "expected str, found Result[int, str]", null);
}

// R5B-MSGS 2 (follow-up): a `fails` call as a condition, under `not`, `-`, or on both sides of an operator needs the same `try`.
test "a fails call used as a condition or an operand of an operator gets the same advice and repair" {
    const tail = "`half` can fail: write `try half(...)` to take its value and pass the error on, or handle it with `const n = half(...) else Err(e):`";
    const odd = "func odd(x: int) -> bool fails str:\n    return x % 2 == 1\n\n\n";
    const odd_tail = "`odd` can fail: write `try odd(...)` to take its value and pass the error on, or handle it with `const n = odd(...) else Err(e):`";
    const head = half ++ odd ++ "func main() -> int fails str:\n";
    try expectMissingTry(head ++ "    if odd(3):\n        return 1\n    return 0\n", "expected bool, found Result[bool, str]; " ++ odd_tail, "odd(3)");
    try expectMissingTry(head ++ "    mut n = 0\n    while odd(n):\n        n += 1\n    return n\n", "expected bool, found Result[bool, str]; " ++ odd_tail, "odd(n)");
    try expectMissingTry(head ++ "    if not odd(3):\n        return 1\n    return 0\n", "expected bool, found Result[bool, str]; " ++ odd_tail, "odd(3)");
    try expectMissingTry(head ++ "    if odd(3) and odd(5):\n        return 1\n    return 0\n", "expected bool, found Result[bool, str]; " ++ odd_tail, "odd(3)");
    try expectMissingTry(head ++ "    const neg = -half(4)\n    return neg\n", "operation requires an integer type; " ++ tail, "half(4)");
    try expectMissingTry(head ++ "    const both = half(4) + half(6)\n    return both\n", "operation requires an integer type; " ++ tail, "half(4)");
    try expectMissingTry(head ++ "    const less = half(4) < half(6)\n    return 0\n", "operation requires an integer type; " ++ tail, "half(4)");
    // The right operand is reached once the left one has its `try`.
    try expectMissingTry(half ++ "func main() -> int fails str:\n    const both = try half(4) + half(6)\n    return both\n", "expected int, found Result[int, str]; " ++ tail, "half(6)");
}

// R5B-MSGS 2 (follow-up): where `try` is refused the refusal names no `try` and carries no repair: a contract condition, a lambda, a `detach`
// loop, a function with an `on fail:` clause, and a function that still holds an unhandled result.
test "a fails call where try is refused keeps the plain text and no repair" {
    const plain = "expected int, found Result[int, str]";
    try expectMissingTry(half ++ "@requires(half(x) > 0)\nfunc guarded(x: int) -> int fails str:\n    return 1\n\n\nfunc main() -> int:\n    return 0\n", "expected Result[int, str], found int", null);
    try expectMissingTry(half ++ "@ensures(result > half(x))\nfunc after(x: int) -> int fails str:\n    return 100\n\n\nfunc main() -> int:\n    return 0\n", plain, null);
    try expectMissingTry(half ++ "@requires(half(x))\nfunc bare(x: int) -> int fails str:\n    return 1\n\n\nfunc main() -> int:\n    return 0\n", "expected bool, found Result[int, str]", null);
    const lambda = half ++ "func apply(f: func(int) -> int, n: int) -> int:\n    return f(n)\n\n\nfunc main() -> int fails str:\n    return apply(lambda n: n + half(2), 2)\n";
    try expectMissingTry(lambda, plain, null);
    const detach = half ++ "func main() -> int fails str:\n    mut xs = [1, 2]\n    mut total = 0\n    for x in detach xs:\n        total = total + half(2)\n    return total\n";
    try expectMissingTry(detach, plain, null);
    const clause = half ++ "func main(out: Stream) -> int fails str:\n    on fail:\n        print(out, \"failed\")\n    const a = try half(2)\n    const total = 2 + half(4)\n    return total + a\n";
    try expectMissingTry(clause, plain, null);
    const handled = "    match r:\n        case Ok(v):\n            print(out, v)\n        case Err(e):\n            print(out, e)\n    return total\n";
    const pending = half ++ "func main(out: Stream) -> int fails str:\n    const r = half(2)\n    const total = 2 + half(4)\n" ++ handled;
    try expectMissingTry(pending, plain, null);
}
