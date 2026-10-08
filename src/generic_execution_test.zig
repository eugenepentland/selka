//! Concrete generics preserve universal contracts while using ordinary checked backends.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const text =
    \\def id[T](x: T) -> T:
    \\    return x
    \\
    \\
    \\def sum[T: integer](x: T) -> T:
    \\    if x == T(0):
    \\        return x
    \\    return x + sum[T](x - T(1))
    \\
    \\
    \\def forward[U: integer](x: U) -> U:
    \\    return id[U](sum[U](x))
    \\
    \\
    \\def main() -> i64:
    \\    small = forward[u8](4u8)
    \\    wide = forward[i64](5)
    \\    if id[bool](True):
    \\        return i64(small) + wide + sum[i64](2)
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "specialized.my", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 28), (try native.run(&compilation)).value);
    // main plus two forward, two sum, and three id specializations.
    try t.expectEqual(@as(usize, 8), compilation.program.?.functions.len);
}
// spec: GENERIC-EXECUTION-1
test "generic execution specializes widths forwarding recursion and shared instances" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "generic execution preserves nominal values through copy contracts" {
    var compilation = try language.Compilation.init(t.allocator, "nominal.my",
        \\record A:
        \\    x: i64
        \\
        \\
        \\record B:
        \\    x: i64
        \\
        \\
        \\def id[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    a = id[A](A(x=3))
        \\    b = id[B](B(x=4))
        \\    return a.x + b.x
    );
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 7), (try native.run(&compilation)).value);
    try t.expectEqual(@as(usize, 3), compilation.program.?.functions.len);
    try t.expectEqualStrings("id[A]", compilation.program.?.functions[1].name);
    try t.expectEqualStrings("id[B]", compilation.program.?.functions[2].name);
}

fn declarations(count: usize) !void {
    var text_buffer: std.Io.Writer.Allocating = .init(t.allocator);
    defer text_buffer.deinit();
    for (0..count) |index| try text_buffer.writer.print("def g{d}[T]() -> i64:\n    return 0\n\n\n", .{index});
    try text_buffer.writer.writeAll("def main() -> i64:\n");
    for (0..count) |index| try text_buffer.writer.print("    _ = g{d}[i64]()\n", .{index});
    try text_buffer.writer.writeAll("    return g0[i64]()\n");
    var compilation = try language.Compilation.init(t.allocator, "limit.my", text_buffer.written());
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(count + 1, compilation.program.?.functions.len);
}
// spec-case: GENERIC-INSTANCE-BUDGET-1
test "polymorphic recursion in one declaration still stops at a generic limit" {
    var compilation = try language.Compilation.init(t.allocator, "recursion.my",
        \\def grow[T](x: T) -> i64:
        \\    return grow[list[T]]([x])
        \\
        \\
        \\def main() -> i64:
        \\    return grow[i64](1)
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_GENERIC_LIMIT", compilation.diagnostics.items[0].code);
}
// spec-case: GENERIC-INSTANCE-BUDGET-1
test "generic execution reuses instances and counts them per declaration, not per program" {
    // 4,097 generic declarations each instantiated once: past what one
    // program-wide budget of 4,096 allowed, within each declaration's own.
    try declarations(4097);
}

// spec: GENERIC-DIAGNOSTIC-1
test "generic diagnostics name concrete types independently of discovery order" {
    const cases = [_][]const u8{
        \\def id[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return id[i64](2)
        ,
        \\def id[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\def extra() -> bool:
        \\    return id[bool](True)
        \\
        \\
        \\def main() -> i64:
        \\    return id[i64](2)
        ,
    };
    for (cases) |source_text| {
        var compilation = try language.Compilation.init(t.allocator, "names.my", source_text);
        defer compilation.deinit();
        try compilation.check();
        var found = false;
        for (compilation.program.?.functions) |function| {
            if (!std.mem.eql(u8, function.name, "id[i64]")) continue;
            found = true;
            try t.expectEqualSlices(@import("typed.zig").Type, &.{.i64}, function.type_arguments);
        }
        try t.expect(found);
    }
}
test "generic diagnostics retain instantiated names in runtime traces" {
    var compilation = try language.Compilation.init(t.allocator, "trace.my",
        \\def divide[T: integer](x: T) -> T:
        \\    return divtrunc(x, T(0))
        \\
        \\
        \\def forward[U: integer](x: U) -> U:
        \\    return divide[U](x)
        \\
        \\
        \\def main() -> i64:
        \\    return i64(forward[u8](1u8))
    );
    defer compilation.deinit();
    const result = try native.run(&compilation);
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", result.trap.code);
    try t.expectEqual(@as(usize, 3), result.trap.frames.len);
    try t.expectEqualStrings("divide[u8]", result.trap.frames[0].function);
    try t.expectEqualStrings("forward[u8]", result.trap.frames[1].function);
}

test "generic execution rejects concrete requirement and arity violations" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source =
        \\def f[T: integer](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    _ = f[bool](True)
        \\    return 0
        , .code = "E_GENERIC_ARGUMENT" },
        .{ .source =
        \\def f[T, U](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return f(1)
        , .code = "E_GENERIC_INFERENCE" },
        .{ .source =
        \\def f[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return f[i64](True)
        , .code = "E_TYPE" },
        .{ .source =
        \\def main[T]() -> i64:
        \\    return 0
        , .code = "E_MAIN" },
        .{ .source =
        \\def bad[T](x: T) -> T:
        \\    return x + x
        \\
        \\
        \\def main() -> i64:
        \\    return bad[i64](2)
        , .code = "E_GENERIC_OPERATION" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "rejected.my", case.source);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}
