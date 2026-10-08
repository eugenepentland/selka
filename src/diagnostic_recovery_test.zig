//! Independent function diagnostics remain stable without publishing partial code.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn faults(allocator: std.mem.Allocator) !void {
    const text =
        \\def first() -> i64:
        \\    return missing_first
        \\
        \\
        \\def second() -> i64:
        \\    return missing_second
        \\
        \\
        \\def main() -> i64:
        \\    return first() + second()
    ;
    var compilation = try language.Compilation.init(allocator, "faults.my", text);
    defer compilation.deinit();
    compilation.check() catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.len);
    for (compilation.diagnostics.items, [_][]const u8{ "missing_first", "missing_second" }) |item, name| {
        try t.expectEqualStrings("E_UNKNOWN_NAME", item.code);
        try t.expectEqualStrings(name, compilation.src.text(item.span));
        try t.expectEqual(std.mem.indexOf(u8, text, name).?, item.span.start);
    }
    try t.expectError(error.SourceError, native.run(&compilation));
    try t.expect(compilation.program == null);
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.len);
    for ([_][]const u8{ "missing_first", "missing_second" }) |repair| {
        // Equal-length repairs preserve the unaffected function's byte offsets.
        const replacement = if (repair.len == 13) "1_000_000_000" else "10_000_000_000";
        const fixed = try std.mem.replaceOwned(u8, allocator, text, repair, replacement);
        defer allocator.free(fixed);
        var partially_fixed = try language.Compilation.init(allocator, "faults.my", fixed);
        defer partially_fixed.deinit();
        partially_fixed.check() catch |err| switch (err) {
            error.SourceError => {},
            else => return err,
        };
        try t.expectEqual(@as(usize, 1), partially_fixed.diagnostics.items.len);
        const remaining = partially_fixed.diagnostics.items[0];
        const original = compilation.diagnostics.items[if (repair.len == 13) 1 else 0];
        try t.expectEqual(original.span.start, remaining.span.start);
        try t.expectEqual(original.span.end, remaining.span.end);
        try t.expectEqualStrings(original.code, remaining.code);
    }
}
// spec: DIAGNOSTIC-RECOVERY-1
test "independent body faults survive either repair and forbid execution under allocation failures" {
    try faults(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), faults, .{});
}
test "generic and ordinary function failures are recovered at separate boundaries" {
    var compilation = try language.Compilation.init(t.allocator, "generics.my",
        \\def first[T](x: T) -> T:
        \\    return missing_first
        \\
        \\
        \\def second[T](x: T) -> T:
        \\    return missing_second
        \\
        \\
        \\def ordinary() -> i64:
        \\    return missing_third
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqual(@as(usize, 3), compilation.diagnostics.items.len);
    for (compilation.diagnostics.items) |item| try t.expectEqualStrings("E_UNKNOWN_NAME", item.code);
}
test "dependent signature failures collapse to one source diagnostic" {
    var compilation = try language.Compilation.init(t.allocator, "signature.my",
        \\def broken(x: Unknown) -> i64:
        \\    return 0
        \\
        \\
        \\def first() -> i64:
        \\    return broken(1)
        \\
        \\
        \\def second() -> i64:
        \\    return broken(2)
        \\
        \\
        \\def main() -> i64:
        \\    return first() + second()
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    try t.expectEqualStrings("Unknown", compilation.src.text(compilation.diagnostics.items[0].span));
}

test "project diagnostics retain each module location and reject repeated lowering" {
    const Files = struct {
        fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
            if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
                \\module main
                \\import helper
                \\
                \\
                \\def main() -> i64:
                \\    return missing_main
            );
            if (std.mem.eql(u8, path, "helper.my")) return allocator.dupe(u8,
                \\module helper
                \\
                \\
                \\def broken() -> i64:
                \\    return missing_helper
            );
            return error.NotFound;
        }
    };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.items.len);
    for (compilation.diagnostics.items.items, [_][]const u8{ "main.my", "helper.my" }) |item, path| {
        const location = compilation.src.locate(item.span.start);
        try t.expectEqualStrings(path, location.path);
    }
    try t.expectError(error.SourceError, compilation.check());
    try t.expect(compilation.program == null);
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.items.len);
}
