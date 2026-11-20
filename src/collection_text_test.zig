//! `str(x)` and `repr(x)` of a list, a set, a dictionary, an option, a record, a result or a fixed array (F-38 and F-38b, 14
//! November 2026, `collection_text.zig`): the
//! programs that now check, and the refusals that stay with the sentences that are true after the change. What the text is,
//! byte for byte, is tested in `tests/lang/text_of_collections.selka` against `print`; this file tests only what the checker
//! accepts and refuses.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const diagnostic_codes = @import("diagnostic_codes.zig");

const unit_main = "\nfunc main() -> int:\n    return 0\n";
const shapes = "record Point:\n    x: int\n    y: int\n\nenum Kind:\n    alpha\n    beta\n\nenum Shape:\n    circle(value: int)\n    dot\n\n" ++
    "func pick(n: int) -> int fails str:\n    if n < 0:\n        fail \"no\"\n    return n\n\n";

/// Require `source` to check without a diagnostic of error rank.
fn accepts(source: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "collection_text.selka", source);
    defer c.deinit();
    try c.check();
}

/// Require the first diagnostic of `source` to carry `code` and a message containing `words`.
fn refuses(source: []const u8, code: []const u8, words: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "collection_text.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    const first: diagnostic.Diagnostic = c.diagnostics.items[0];
    try t.expectEqualStrings(code, first.code);
    try t.expect(std.mem.indexOf(u8, first.message, words) != null);
}

/// A function `f` whose body is `body` (one statement on `out`), then the shapes the tests share and an unused `main`.
fn program(body: []const u8) ![]const u8 {
    return std.fmt.allocPrint(t.allocator, "{s}func f(out: Stream):\n    {s}\n{s}", .{ shapes, body, unit_main });
}

fn acceptsBody(body: []const u8) !void {
    const source = try program(body);
    defer t.allocator.free(source);
    try accepts(source);
}

fn refusesBody(body: []const u8, code: []const u8, words: []const u8) !void {
    const source = try program(body);
    defer t.allocator.free(source);
    try refuses(source, code, words);
}

test "F-38 str and repr take a list of plain values" {
    try acceptsBody("print(out, str([3, 1, 2]), repr([3, 1, 2]))");
    try acceptsBody("print(out, str([1.5]), str([True]), str([\"a\"]), repr([\"a\"]), str([b\"a\"]))");
    try acceptsBody("print(out, str([[1], [2, 3], []]), str([[[1]]]))");
    try acceptsBody("const empty: int[] = []\n    print(out, str(empty), repr(empty))");
}

test "F-38 str and repr take a set, a dictionary and an option" {
    try acceptsBody("const seen: set[int] = {3, 1}\n    print(out, str(seen), repr(seen))");
    try acceptsBody("const table: dict[str, int] = {\"a\": 1}\n    print(out, str(table), repr(table))");
    try acceptsBody("const found: int? = Some(3)\n    print(out, str(found), repr(found))");
    try acceptsBody("const lists: dict[str, int[]] = {\"a\": [1]}\n    print(out, str(lists))");
}

test "F-38 the parts of a collection are anything print shows" {
    try acceptsBody("print(out, str([Point(x=1, y=2)]), str([Kind.alpha]), str([Shape.circle(value=1), Shape.dot]))");
    try acceptsBody("const found: int? = None\n    print(out, str([found]), str([FixedArray[int, 2]([1, 2])]))");
    try acceptsBody("const tree: Point? = Some(Point(x=1, y=2))\n    print(out, str(tree), repr(tree))");
}

test "F-38 a format string's hole takes what str takes" {
    try acceptsBody("const order = [3, 1, 2]\n    print(out, f\"{order}\", str(order))");
}

test "F-38 a generic body takes str of a list; each instance checks its own parts" {
    const generic = "func show[T](items: T[]) -> str:\n    return str(items)\n\nfunc concrete[T](value: T) -> str:\n    return str([1, 2]) + repr([\"x\"])\n";
    const source = try std.fmt.allocPrint(t.allocator, "{s}\nfunc f(out: Stream):\n    print(out, show([1, 2]), concrete(3))\n{s}", .{ generic, unit_main });
    defer t.allocator.free(source);
    try accepts(source);
    const refused = try std.fmt.allocPrint(t.allocator, "{s}\nfunc f(out: Stream):\n    print(out, show([out]))\n{s}", .{ generic, unit_main });
    defer t.allocator.free(refused);
    try refuses(refused, "E_TEXT_CONVERSION", "`str` of `Stream[]` is refused: it holds a `Stream`, which has no text");
    // A bare type parameter still needs the declared integer support it always did.
    const bare = "func show[T](item: T) -> str:\n    return str(item)\n" ++ unit_main;
    try refuses(bare, "E_GENERIC_OPERATION", "operation requires declared integer support");
}

test "F-38 a collection with a part that has no text is refused, naming the part" {
    const words = "`Stream`, which has no text; capabilities, open files, owned resources and callbacks cannot be shown";
    try refusesBody("print(out, str([out]))", "E_TEXT_CONVERSION", "`str` of `Stream[]` is refused: it holds a " ++ words);
    try refusesBody("print(out, repr([out]))", "E_REPR_TYPE", "`repr` of `Stream[]` is refused: it holds a " ++ words);
    try refusesBody("const found: Stream? = Some(out)\n    print(out, str(found))", "E_TEXT_CONVERSION", "`str` of `Stream?` is refused: it holds a " ++ words);
    try refusesBody("const table: dict[str, Stream] = {\"a\": out}\n    print(out, str(table))", "E_TEXT_CONVERSION", "it holds a " ++ words);
    try refusesBody("const lists = [[out]]\n    print(out, repr(lists))", "E_REPR_TYPE", "`repr` of `Stream[][]` is refused: it holds a " ++ words);
}

test "F-38 a value with no text of its own is refused as it was, with a sentence that is true" {
    try refusesBody("print(out, str(out))", "E_TEXT_CONVERSION", "`str` of `Stream` is refused: it has no text");
    try refusesBody("print(out, repr(out))", "E_REPR_TYPE", "`repr` of `Stream` is refused: it has no text");
}

test "F-38b str and repr take a record, a result and a fixed array on their own" {
    try acceptsBody("print(out, str(Point(x=1, y=2)), repr(Point(x=1, y=2)))");
    try acceptsBody("const p = Point(x=1, y=2)\n    print(out, str(p), repr(p), f\"{p}\")");
    try acceptsBody("print(out, str(pick(1)), repr(pick(-1)))");
    try acceptsBody("print(out, str(FixedArray[int, 2]([1, 2])), repr(FixedArray[str, 2]([\"a\", \"b\"])))");
    try acceptsBody("const nested = FixedArray[Point, 1]([Point(x=1, y=2)])\n    print(out, str(nested), str([nested]))");
}

test "F-38b a generic body takes str of a record, a result or a fixed array and each instance checks its parts" {
    const generic = "record Box[T]:\n    value: T\n\nfunc show[T](box: Box[T]) -> str:\n    return str(box)\n\n" ++
        "func shown[T](items: FixedArray[T, 2]) -> str:\n    return repr(items)\n\n";
    const source = try std.fmt.allocPrint(t.allocator, "{s}func f(out: Stream):\n    print(out, show(Box[int](value=1)), shown(FixedArray[int, 2]([1, 2])))\n{s}", .{ generic, unit_main });
    defer t.allocator.free(source);
    try accepts(source);
    const refused = try std.fmt.allocPrint(t.allocator, "{s}func f(out: Stream):\n    print(out, show(Box[Stream](value=out)))\n{s}", .{ generic, unit_main });
    defer t.allocator.free(refused);
    try refuses(refused, "E_TEXT_CONVERSION", "which has no text");
}

test "F-38b a record that holds a capability, a callback or a function is refused, naming the part" {
    const holder = "record Holder:\n    stream: Stream\n\nfunc f(out: Stream):\n    print(out, str(Holder(stream=out)))\n" ++ unit_main;
    try refuses(holder, "E_TEXT_CONVERSION", "`str` of `Holder` is refused: it holds a `Stream`, which has no text");
    try refusesBody("print(out, repr(FixedArray[Stream, 1]([out])))", "E_REPR_TYPE", "which has no text");
}

test "F-38b an enum, a union and bytes keep their refusals, and the sentence says what shows them" {
    try refusesBody("print(out, str(Kind.alpha))", "E_TEXT_CONVERSION", "`case_name(value)` is the name of its case");
    try refusesBody("print(out, repr(Shape.dot))", "E_REPR_TYPE", "`case_name(value)` is the name of its case");
    try refusesBody("print(out, str(Shape.circle(value=1)))", "E_TEXT_CONVERSION", "`case_name(value)` is the name of its case");
    try refusesBody("print(out, str(b\"ab\"))", "E_TEXT_CONVERSION", "bytes are not text; `repr(value)` is the `b'...'` spelling `print` shows");
    // A bare `Stream` and a value with no text of its own keep the sentence that names what has none.
    try refusesBody("print(out, str(out))", "E_TEXT_CONVERSION", "`str` of `Stream` is refused: it has no text");
}

test "F-38 str of a list of records that hold a capability is refused where the record is the part" {
    const holder = "record Holder:\n    stream: Stream\n\nfunc f(out: Stream):\n    const held = [Holder(stream=out)]\n    print(out, str(held))\n" ++ unit_main;
    try refuses(holder, "E_TEXT_CONVERSION", "`str` of `Holder[]` is refused: it holds a `Stream`");
}

// PRINT-1 (the user's decision of 14 November 2026): `print`, `str`, `repr` and a format string's hole share one rule, so a value that
// holds a function or a capability is refused at check time wherever it holds it. Before, `print(out, [f])` checked and wrote a
// memory address, and `print(out, [stream])` checked and failed in Core.
const twice = "func twice(n: int) -> int:\n    return n * 2\n\n\n";

test "PRINT-1 print of a list of functions is refused at check, naming the element type and what to write instead" {
    const instead = "capabilities, open files, owned resources and callbacks cannot be shown, so write a name or a count that describes them";
    try refuses(twice ++ "func f(out: Stream):\n    const fns = [twice]\n    print(out, fns)\n" ++ unit_main, "E_IO_ARGUMENT", "`print` of `(func(int) -> int)[]` is refused: it holds a `func(int) -> int`, which has no text; " ++ instead);
    // FR24 item 3: the name of a list or option of functions is parenthesized, so `-> int` cannot be read as a returned list.
    const boxed = "func boxed[T](own v: T) -> T?:\n    return Some(own v)\n\n\nfunc f(out: Stream):\n    const maybe = boxed(twice)\n    print(out, maybe)\n";
    try refuses(twice ++ boxed ++ unit_main, "E_IO_ARGUMENT", "`print` of `(func(int) -> int)?` is refused");
    try refuses(twice ++ "func f(out: Stream):\n    print(out, [twice])\n" ++ unit_main, "E_IO_ARGUMENT", "it holds a `func(int) -> int`");
    try refusesBody("print(out, [out])", "E_IO_ARGUMENT", "`print` of `Stream[]` is refused: it holds a `Stream`, which has no text; " ++ instead);
}

test "PRINT-1 print of a record or an option that holds a capability is refused, and so is every other way to write it" {
    const holder = "record Holder:\n    stream: Stream\n\n";
    try refuses(holder ++ "func f(out: Stream):\n    print(out, Holder(stream=out))\n" ++ unit_main, "E_IO_ARGUMENT", "`print` of `Holder` is refused: it holds a `Stream`");
    try refuses(holder ++ "func f(out: Stream):\n    print(out, [Holder(stream=out)])\n" ++ unit_main, "E_IO_ARGUMENT", "`print` of `Holder[]` is refused: it holds a `Stream`");
    try refusesBody("const found: Stream? = Some(out)\n    print(out, found)", "E_IO_ARGUMENT", "`print` of `Stream?` is refused: it holds a `Stream`");
    try refusesBody("const table: dict[str, Stream] = {\"a\": out}\n    print(out, table)", "E_IO_ARGUMENT", "it holds a `Stream`");
    try refusesBody("debug([out])", "E_IO_ARGUMENT", "`print` of `Stream[]` is refused");
    try refusesBody("print(out, f\"{[out]}\")", "E_TEXT_CONVERSION", "a format string hole of `Stream[]` is refused: it holds a `Stream`, which has no text");
}

test "PRINT-1 a bare function or capability keeps its refusal, and a value print can show is still shown" {
    try refusesBody("print(out, out)", "E_IO_ARGUMENT", "print cannot render this value; capabilities, files, owned resources and callbacks have no Python spelling");
    try acceptsBody("print(out, [1, 2], [Point(x=1, y=2)], [Kind.alpha], FixedArray[int, 2]([1, 2]), pick(1), [pick(2)])");
    try acceptsBody("print(out, f\"{[Point(x=1, y=2)]}\", f\"{pick(3)}\")");
}

/// The code table's meaning of `code`, which `selka reference` and the guides print.
fn meaningOf(code: []const u8) []const u8 {
    for (diagnostic_codes.entries) |entry| if (std.mem.eql(u8, entry.code, code)) return entry.meaning;
    return "";
}

test "F-38 the code table says the two codes take a collection of values print can show" {
    try t.expect(std.mem.indexOf(u8, meaningOf("E_TEXT_CONVERSION"), "a list, set, dictionary, option, record, result or fixed array of values `print` can show") != null);
    try t.expect(std.mem.indexOf(u8, meaningOf("E_REPR_TYPE"), "a list, set, dictionary, option, record, result or fixed array of values `print` can show") != null);
}
