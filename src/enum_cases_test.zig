//! The refusals of `case_name`, `Kind.cases()` and `Kind.from_name(text)`; the behavior is `tests/lang/enum_case_names.selka`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

const kind = "enum Kind:\n    alpha\n    beta\n\nenum Shape:\n    empty\n    radius(value: int)\n\n";

fn reject(body: []const u8, code: []const u8) !void {
    const complete = try std.mem.concat(t.allocator, u8, &.{ kind, body });
    defer t.allocator.free(complete);
    var c = try language.Compilation.init(t.allocator, "enum-cases.selka", complete);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

test "case_name takes an enum or tagged union value and nothing else" {
    try reject("func main(out: Stream) -> int:\n    print(out, case_name(5))\n    return 0\n", "E_ENUM_CASES");
    try reject("func main(out: Stream) -> int:\n    print(out, case_name(\"alpha\"))\n    return 0\n", "E_ENUM_CASES");
    try reject("func main(out: Stream) -> int:\n    const x: int? = None\n    print(out, case_name(x))\n    return 0\n", "E_ENUM_CASES");
    try reject("func main(out: Stream) -> int:\n    print(out, case_name(Kind.alpha, Kind.beta))\n    return 0\n", "E_ARITY");
}

test "case_name of a type parameter's value is refused where its type is unknown" {
    try reject("func name[T](value: T) -> str:\n    return case_name(value)\n\nfunc main(out: Stream) -> int:\n    return 0\n", "E_ENUM_CASES");
}

test "str of an enum stays refused: the case name is case_name" {
    try reject("func main(out: Stream) -> int:\n    print(out, str(Kind.alpha))\n    return 0\n", "E_TEXT_CONVERSION");
}

test "cases and from_name need an enum without payloads" {
    try reject("func main(out: Stream) -> int:\n    print(out, len(Shape.cases()))\n    return 0\n", "E_ENUM_CASES");
    try reject("func main(out: Stream) -> int:\n    const s = Shape.from_name(\"empty\")\n    return 0\n", "E_ENUM_CASES");
}

test "cases takes no argument and from_name one text" {
    try reject("func main(out: Stream) -> int:\n    print(out, len(Kind.cases(1)))\n    return 0\n", "E_ARITY");
    try reject("func main(out: Stream) -> int:\n    const k = Kind.from_name()\n    return 0\n", "E_ARITY");
    try reject("func main(out: Stream) -> int:\n    const k = Kind.from_name(5)\n    return 0\n", "E_ENUM_CASES");
    try reject("func main(out: Stream) -> int:\n    const k = Kind.from_name(\"a\", \"b\")\n    return 0\n", "E_ARITY");
}

test "from_name in a generic body refuses a name that is not text" {
    try reject("func parse[T](value: T) -> bool:\n    return Kind.from_name(value) is Some\n\nfunc main(out: Stream) -> int:\n    return 0\n", "E_ENUM_CASES");
}
