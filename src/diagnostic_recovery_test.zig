//! Independent function diagnostics remain stable without publishing partial code.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn faults(allocator: std.mem.Allocator) !void {
    const text =
        \\func first() -> i64:
        \\    return missing_first
        \\
        \\
        \\func second() -> i64:
        \\    return missing_second
        \\
        \\
        \\func main() -> i64:
        \\    return first() + second()
    ;
    var compilation = try language.Compilation.init(allocator, "faults.selka", text);
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
        var partially_fixed = try language.Compilation.init(allocator, "faults.selka", fixed);
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
    var compilation = try language.Compilation.init(t.allocator, "generics.selka",
        \\func first[T](x: T) -> T:
        \\    return missing_first
        \\
        \\
        \\func second[T](x: T) -> T:
        \\    return missing_second
        \\
        \\
        \\func ordinary() -> i64:
        \\    return missing_third
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqual(@as(usize, 3), compilation.diagnostics.items.len);
    for (compilation.diagnostics.items) |item| try t.expectEqualStrings("E_UNKNOWN_NAME", item.code);
}
test "dependent signature failures collapse to one source diagnostic" {
    var compilation = try language.Compilation.init(t.allocator, "signature.selka",
        \\func broken(x: Unknown) -> i64:
        \\    return 0
        \\
        \\
        \\func first() -> i64:
        \\    return broken(1)
        \\
        \\
        \\func second() -> i64:
        \\    return broken(2)
        \\
        \\
        \\func main() -> i64:
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
            if (std.mem.eql(u8, path, "main.selka")) return allocator.dupe(u8,
                \\import helper
                \\
                \\
                \\func main() -> i64:
                \\    return missing_main
            );
            if (std.mem.eql(u8, path, "helper.selka")) return allocator.dupe(u8,
                \\
                \\
                \\func broken() -> i64:
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
    for (compilation.diagnostics.items.items, [_][]const u8{ "main.selka", "helper.selka" }) |item, path| {
        const location = compilation.src.locate(item.span.start);
        try t.expectEqualStrings(path, location.path);
    }
    try t.expectError(error.SourceError, compilation.check());
    try t.expect(compilation.program == null);
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.items.len);
}

/// The source lines and codes of a failed check's errors, `line CODE` per error in the order reported.
fn bodyErrors(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(allocator, "body.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (compilation.diagnostics.items) |item| {
        if (item.severity != .err) continue;
        try out.print(allocator, "{d} {s}\n", .{ std.mem.count(u8, text[0..item.span.start], "\n") + 1, item.code });
    }
    return out.toOwnedSlice(allocator);
}

test "every statement error of one body is reported in one check, in source order (statementBlock goes on, F-RC-214)" {
    const found = try bodyErrors(t.allocator,
        \\func f(n: int) -> int:
        \\    const label: int = b"x"
        \\    mut total = n
        \\    if n > 0:
        \\        total = total + b"y"
        \\    const flag: bool = 3
        \\    return n + missing
        \\
        \\
        \\func main() -> int:
        \\    return f(1)
    );
    defer t.allocator.free(found);
    try t.expectEqualStrings("2 E_TYPE\n5 E_TYPE\n6 E_TYPE\n7 E_UNKNOWN_NAME\n", found);
}

test "a failed statement poisons the names it binds: a later failure that mentions one is not reported" {
    const found = try bodyErrors(t.allocator,
        \\func f(n: int) -> int:
        \\    const total: int = b"x"
        \\    const doubled = total * 2
        \\    const flag: bool = 3
        \\    return doubled + n
        \\
        \\
        \\func main() -> int:
        \\    return f(1)
    );
    defer t.allocator.free(found);
    try t.expectEqualStrings("2 E_TYPE\n4 E_TYPE\n", found);
}

test "a failed return ends its block: what follows it in the block is not checked, and the next statement is" {
    const found = try bodyErrors(t.allocator,
        \\func f(n: int) -> int:
        \\    if n > 0:
        \\        return b"x"
        \\        missing_after()
        \\    return n + True
        \\
        \\
        \\func main() -> int:
        \\    return f(1)
    );
    defer t.allocator.free(found);
    try t.expectEqualStrings("3 E_TYPE\n5 E_TYPE\n", found);
}

test "one body reports at most the recovery limit of failed statements, nested ones included" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(t.allocator);
    try text.appendSlice(t.allocator, "func f(n: int) -> int:\n");
    for (0..@import("sema_recovery.zig").limit + 5) |index| try text.print(t.allocator, "    const v{d}: int = b\"x\"\n    if n > {d}:\n        const w{d}: int = b\"y\"\n", .{ index, index, index });
    try text.appendSlice(t.allocator, "    return n\n\n\nfunc main() -> int:\n    return f(1)\n");
    const found = try bodyErrors(t.allocator, text.items);
    defer t.allocator.free(found);
    try t.expectEqual(@as(usize, @import("sema_recovery.zig").limit), std.mem.count(u8, found, "E_TYPE"));
}
