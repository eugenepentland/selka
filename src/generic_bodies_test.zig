//! Abstract contracts are checked without sampling a concrete type or executing templates.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const bodies = @import("generic_bodies.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const pure =
    \\def identity[T](x: T) -> T:
    \\    return x
    \\
    \\
    \\def equal[T: equality](x: T, y: T) -> bool:
    \\    return x == y
    \\
    \\
    \\def arithmetic[T: integer](x: T, y: T) -> T noalloc:
    \\    value = x
    \\    value += y
    \\    while value < T(10):
    \\        value = value + T(1)
    \\    if value == y:
    \\        return -value
    \\    else:
    \\        return value
    \\
    \\
    \\def minimum[T](x: T) -> i8:
    \\    _ = x
    \\    return -128i8
    \\
    \\
    \\def main() -> i64:
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic.my", pure);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try bodies.check(allocator, compilation.src, compilation.syntax.?, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    try compilation.check();
}
// spec: GENERIC-BODY-1
test "generic body contracts check pure control flow without concrete representative types" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
test "generic body contracts preserve original module source locations" {
    var compilation = try language.Compilation.init(t.allocator, "mapped.my", "");
    defer compilation.deinit();
    const allocator = compilation.arena.allocator();
    compilation.src = try source.Source.initMapped(allocator, &.{
        try source.Source.init(allocator, "main.my",
            \\def main() -> i64:
            \\    return 0
        ),
        try source.Source.init(allocator, "library.my",
            \\def bad[T](x: T, y: T) -> T:
            \\    return x + y
        ),
    });
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_GENERIC_OPERATION", failure.code);
    try t.expectEqualStrings("library.my", compilation.src.locate(failure.span.start).path);
    try t.expectEqualStrings("+", compilation.src.text(failure.span));
}

fn checkBound(text: []const u8, failure: bool) !void {
    var compilation = try language.Compilation.init(t.allocator, "bounded.my", text);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    if (failure) {
        try t.expectError(error.SourceError, bodies.check(t.allocator, compilation.src, compilation.syntax.?, &sink));
        try t.expectEqualStrings("E_GENERIC_BODY_LIMIT", sink.items.items[0].code);
    } else try bodies.check(t.allocator, compilation.src, compilation.syntax.?, &sink);
}
test "generic body contracts bound left-deep expression checking" {
    for ([_]usize{ 100, 300 }) |length| {
        var text: std.Io.Writer.Allocating = .init(t.allocator);
        defer text.deinit();
        try text.writer.writeAll("fn f<T:integer>(x:T)->T{return x");
        for (0..length) |_| try text.writer.writeAll("+x");
        try text.writer.writeAll(";}");
        try checkBound(text.written(), length == 300);
    }
}
test "generic body contracts reject top-level and type-parameter shadowing" {
    try reject(
        \\def f[T](x: T) -> T:
        \\    main = x
        \\    return main
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\class T:
        \\    pass
        \\
        \\
        \\def f[T](x: T) -> T:
        \\    return x
    , "E_SHADOWING");
    try reject(
        \\def f[T](x: T) -> T:
        \\    T = x
        \\    return T
    , "E_SHADOWING");
}

test "generic body contracts reject undeclared operations mismatches and invalid control flow" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\def f[T](x: T, y: T) -> T:
        \\    return x + y
        , .code = "E_GENERIC_OPERATION" },
        .{ .text =
        \\def f[T](x: T, y: T) -> bool:
        \\    return x == y
        , .code = "E_GENERIC_OPERATION" },
        .{ .text =
        \\def f[T: equality](x: T, y: T) -> bool:
        \\    return x < y
        , .code = "E_GENERIC_OPERATION" },
        .{ .text =
        \\def f[T: integer, U: integer](x: T, y: U) -> T:
        \\    return x + y
        , .code = "E_GENERIC_TYPE" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    return 1
        , .code = "E_GENERIC_TYPE" },
        .{ .text =
        \\def f[T: integer](x: T) -> T:
        \\    return x + 1
        , .code = "E_GENERIC_TYPE" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    x = x
        \\    return x
        , .code = "E_IMMUTABLE" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    if True:
        \\        y = x
        \\    return y
        , .code = "E_UNKNOWN_NAME" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    x = x
        \\    return x
        , .code = "E_SHADOWING" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    if True:
        \\        return x
        , .code = "E_MISSING_RETURN" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    while True:
        \\        return x
        , .code = "E_MISSING_RETURN" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    return x
        \\    _ = x
        , .code = "E_UNREACHABLE" },
        .{ .text =
        \\def f[T](x: T) -> i8:
        \\    _ = x
        \\    return 128i8
        , .code = "E_INTEGER_RANGE" },
        .{ .text =
        \\def f[T](x: T) -> T:
        \\    return other[T](x)
        , .code = "E_UNKNOWN_FUNCTION" },
    };
    for (cases) |case| try reject(case.text, case.code);
}

test "generic body contracts bound wide statement work without host execution" {
    for ([_]usize{ 49998, 49999 }) |length| {
        var text: std.Io.Writer.Allocating = .init(t.allocator);
        defer text.deinit();
        try text.writer.writeAll("fn f<T:copy>(x:T)->T{");
        for (0..length) |_| try text.writer.writeAll("_ = x;");
        try text.writer.writeAll("{}return x;}");
        try checkBound(text.written(), length == 49999);
    }
}
