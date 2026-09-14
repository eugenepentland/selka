//! Python string methods: trimming, case, search, classification and parsing.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const values = @import("runtime_values.zig");

const text_type: values.Type = @fromBackingInt(@intCast(32));
const list_type: values.Type = @fromBackingInt(@intCast(33));

fn execute(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "strings.my", source);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "strings.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: PY-STR-1
test "trimming, case mapping and padding copy the receiver without changing it" {
    try execute(
        \\def main() -> int:
        \\    padded = "  value  "
        \\    score = 0
        \\    if padded.strip() == "value":
        \\        score = score + 1
        \\    if padded.lstrip() == "value  ":
        \\        score = score + 2
        \\    if padded.rstrip() == "  value":
        \\        score = score + 4
        \\    if "aB".upper() == "AB" and "aB".lower() == "ab":
        \\        score = score + 8
        \\    if "7".zfill(3) == "007" and "-7".zfill(3) == "-07":
        \\        score = score + 16
        \\    if padded == "  value  ":
        \\        score = score + 11
        \\    return score
    , 42);
}

// spec: PY-STR-2
test "search, replacement and classification follow Python answers" {
    try execute(
        \\def main() -> int:
        \\    text = "a,b,a"
        \\    score = 0
        \\    if text.replace("a", "z") == "z,b,z":
        \\        score = score + 1
        \\    if text.find("b") == 2 and text.find("q") == -1:
        \\        score = score + 2
        \\    if text.count("a") == 2:
        \\        score = score + 4
        \\    if text.startswith("a,") and text.endswith(",a"):
        \\        score = score + 8
        \\    if "42".isdigit() and "ab".isalpha() and " \t".isspace():
        \\        score = score + 16
        \\    if not "".isdigit() and not "4a".isalpha():
        \\        score = score + 11
        \\    return score
    , 42);
}

// spec: PY-STR-3
test "splitlines drops terminators and int/float parse a whole string" {
    try execute(
        \\def main() -> int:
        \\    lines = "a\nb\r\nc".splitlines()
        \\    total = len(lines) * 10
        \\    match int("12"):
        \\        case Some(value):
        \\            total = total + value
        \\        case None:
        \\            total = total - 1
        \\    match int("12x"):
        \\        case Some(value):
        \\            total = total + value
        \\        case None:
        \\            total = total
        \\    match float("0.5"):
        \\        case Some(value):
        \\            total = total + int(value * 2.0)
        \\        case None:
        \\            total = total - 1
        \\    return total - 1
    , 42);
}

// spec-case: PY-STR-2
test "string methods are rejected on lists and empty needles trap" {
    try reject(
        \\def main() -> int:
        \\    values = [1, 2]
        \\    _ = values.strip()
        \\    return 0
    , "E_COLLECTION_METHOD");
    try reject(
        \\def main() -> int:
        \\    counts: dict[str, int] = {}
        \\    _ = counts.upper()
        \\    return 0
    , "E_COLLECTION_METHOD");
    var c = try language.Compilation.init(t.allocator, "strings.my", "def main() -> int:\n    return \"ab\".find(\"\")\n");
    defer c.deinit();
    const result = try native.run(&c);
    try t.expect(result.trapped());
    try t.expectEqualStrings("R_EMPTY_SEPARATOR", result.trap.code);
}
