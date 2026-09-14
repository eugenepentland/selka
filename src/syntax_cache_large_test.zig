//! Larger-project parse reuse keeps fresh semantic behavior and diagnostic outcomes.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const File = language.embedded_project.File;
const Files = struct {
    entries: []File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};
fn outcome(files: *Files, cache: *language.syntax_cache.Cache) ![]u8 {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.buildWithCache(&project, cache);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.emit() catch |err| {
        if (err != error.SourceError) return err;
        return std.fmt.allocPrint(t.allocator, "diagnostic:{s}", .{compilation.diagnostics.items.items[0].code});
    };
    const result = try language.vm.run(t.allocator, compilation.code.?);
    return std.fmt.allocPrint(t.allocator, "value:{d}", .{result.value});
}
fn largeProject(allocator: std.mem.Allocator) ![]File {
    const entries = try allocator.alloc(File, 97);
    const imports = try allocator.alloc([]const u8, 96);
    const calls = try allocator.alloc([]const u8, 96);
    for (entries[1..], imports, calls, 0..) |*entry, *import_, *call, i| {
        entry.* = .{
            .path = try std.fmt.allocPrint(allocator, "m{d}.my", .{i}),
            .bytes = try std.fmt.allocPrint(allocator, "module m{d}\nexport value\n\n\ndef value() -> i64:\n    return 1\n", .{i}),
        };
        import_.* = try std.fmt.allocPrint(allocator, "import m{d}\n", .{i});
        call.* = try std.fmt.allocPrint(allocator, "m{d}.value()", .{i});
    }
    entries[0] = .{
        .path = "main.my",
        .bytes = try std.fmt.allocPrint(allocator, "module main\n{s}\n\ndef main() -> i64:\n    return {s}\n", .{ try std.mem.join(allocator, "", imports), try std.mem.join(allocator, "+", calls) }),
    };
    return entries;
}
// spec: INCREMENTAL-CAPACITY-1
test "default syntax retention survives 97 modules and matches fresh execution and errors after leaf edits" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const entries = try largeProject(allocator);
    var files: Files = .{ .entries = entries };
    var cache = language.syntax_cache.Cache.init(t.allocator, .{});
    defer cache.deinit();
    var fresh = language.syntax_cache.Cache.init(t.allocator, .{ .max_entries = 0 });
    defer fresh.deinit();
    const sources = [_][]const u8{
        \\module m0
        \\export value
        \\
        \\
        \\def value() -> i64:
        \\    return 1
        ,
        \\module m0
        \\export value
        \\
        \\
        \\def value() -> i64:
        \\    return 2
        ,
        \\module m0
        \\export value
        \\
        \\
        \\def value() -> i64:
        \\    return True
        ,
        \\module m0
        \\export value
        \\
        \\
        \\def value() -> i64:
        \\    return 1
        ,
    };
    for (sources, 0..) |source, i| {
        entries[1].bytes = source;
        const before = cache.statistics.hits;
        const reused = try outcome(&files, &cache);
        defer t.allocator.free(reused);
        const cold = try outcome(&files, &fresh);
        defer t.allocator.free(cold);
        try t.expectEqualStrings(cold, reused);
        if (i == 0) try t.expectEqualStrings("value:96", reused);
        if (i == 1) try t.expectEqualStrings("value:97", reused);
        if (i == 2) try t.expect(std.mem.startsWith(u8, reused, "diagnostic:"));
        if (i > 0) try t.expect(cache.statistics.hits - before >= 96);
        try t.expectEqual(@as(usize, 0), cache.statistics.evicted);
        try t.expect(cache.statistics.retained_bytes <= cache.limits.max_bytes);
    }
}
