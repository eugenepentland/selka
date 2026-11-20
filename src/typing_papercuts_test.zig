//! Rejections and traps behind the typing papercuts: the discard name, `Option`
//! equality, float and method-carrying module constants, and float-to-integer
//! conversion. The accepted behaviour lives in `tests/lang`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

/// Require `text` to fail checking with `code` as its first diagnostic.
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "papercut.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

/// Require `text` to check and `main` to return `expected`.
fn evaluates(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "papercut.selka", text);
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(expected, (try native.run(&compilation)).value);
}

/// Require `text` to check as an embedded project and `main` to return
/// `expected`. A single-unit compilation cannot carry an `import`, so a program
/// that names a module function outside the single-file helpers needs this one.
fn evaluatesProject(text: []const u8, expected: i64) !void {
    const Entry = struct {
        text: []const u8,
        pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
            if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
            return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
        }
    };
    var entry: Entry = .{ .text = text };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &entry, .read = Entry.read });
    defer program.deinit();
    try t.expectEqual(expected, (try native.run(&program.compilation)).value);
}

// spec-case: DISCARD-NAME-1
test "a loop variable that is not the discard name still may not reuse an active name" {
    try reject(
        \\func main() -> int:
        \\    mut total = 0
        \\    for i in range(2):
        \\        for i in range(3):
        \\            total += 1
        \\    return total
    , "E_SHADOWING");
    try reject(
        \\func main() -> int:
        \\    mut total = 0
        \\    for total in range(2):
        \\        pass
        \\    return total
    , "E_SHADOWING");
    try reject(
        \\func main() -> int:
        \\    mut x = 1
        \\    mut ys = [for x in [1, 2] yield x]
        \\    return len(ys)
    , "E_SHADOWING");
    try reject(
        \\func main() -> int:
        \\    for a, a in enumerate([1]):
        \\        pass
        \\    return 0
    , "E_SHADOWING");
}

// spec-case: DISCARD-NAME-1
test "the discard name is not readable after its scope and a discarded assignment binds nothing" {
    try reject(
        \\func main() -> int:
        \\    for _ in range(2):
        \\        pass
        \\    return _
    , "E_UNKNOWN_NAME");
    try reject(
        \\func main() -> int:
        \\    _ = 5
        \\    return _
    , "E_UNKNOWN_NAME");
    try evaluates(
        \\func main() -> int:
        \\    _ = 5
        \\    for _ in range(2):
        \\        pass
        \\    return 3
    , 3);
}

// spec-case: DISCARD-NAME-1
test "nested discard names hand each enclosing scope its own binding back, however deep" {
    // Three nested `for _ in range(n)` loops used to end a middle scope's `_` early; its own end then found
    // nothing to restore (a trap in Debug, an endless check in ReleaseFast).
    try evaluates(
        \\func main() -> int:
        \\    mut total = 0
        \\    for _ in range(2):
        \\        for _ in range(2):
        \\            for _ in range(2):
        \\                total += _
        \\            total += _
        \\        total += _
        \\    return total
    , 7);
    try reject(
        \\func main() -> int:
        \\    for _ in range(2):
        \\        for _ in range(2):
        \\            for _ in range(2):
        \\                for _ in range(2):
        \\                    pass
        \\    return _
    , "E_UNKNOWN_NAME");
}

// spec-case: OPTION-EQ-1
test "an equality with two operands that await a type, or a wrong payload, is still rejected" {
    try reject(
        \\func main() -> int:
        \\    if Some(1) == Some(1):
        \\        return 1
        \\    return 0
    , "E_OPTION_INFERENCE");
    try reject(
        \\func half(value: int) -> int?:
        \\    return Some(value)
        \\
        \\
        \\func main() -> int:
        \\    if half(4) == Some("a"):
        \\        return 1
        \\    return 0
    , "E_TYPE");
    try reject(
        \\func whole(value: int) -> int:
        \\    return value
        \\
        \\
        \\func main() -> int:
        \\    if whole(4) == Some(4):
        \\        return 1
        \\    return 0
    , "E_TYPE");
    try reject(
        \\func main() -> int:
        \\    if Ok(1) == Ok(1):
        \\        return 1
        \\    return 0
    , "E_RESULT_INFERENCE");
}

// spec-case: CONST-METHOD-1
test "a method on a str or bytes constant keeps the receiver's diagnostics and effects" {
    try reject(
        \\const NAME: str = "hello"
        \\
        \\
        \\func main() -> int:
        \\    return len(NAME.frobnicate())
    , "E_COLLECTION_METHOD");
    try reject(
        \\const NAME: str = "hello"
        \\
        \\
        \\func main() -> int:
        \\    return len(NAME.upper(1))
    , "E_ARITY");
    try reject(
        \\const DATA: bytes = b"a,b"
        \\
        \\
        \\func main() -> int effects():
        \\    return DATA.find(b",")
    , "E_EFFECTS_REMOVED");
    try reject(
        \\const LIMIT: int = 4
        \\
        \\
        \\func main() -> int:
        \\    return LIMIT.bit_length()
    , "E_UNKNOWN_TYPE");
    try evaluatesProject(
        \\import strings
        \\
        \\const NAME: str = "hello"
        \\
        \\
        \\func main() -> int:
        \\    return strings.char_count(strings.upper(NAME)) + strings.text_index(NAME, "l")
    , 7);
}
