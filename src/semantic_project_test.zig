//! Import/export and module relocation remain dependencies of semantic body queries.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const Cache = language.semantic_cache.Cache;
const File = language.embedded_project.File;
const Files = struct {
    entries: []File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};
fn evaluate(files: *Files, cache: ?*Cache) ![]u8 {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.checkWithCache(cache) catch |err| {
        if (err != error.SourceError) return err;
        return language.diagnostic_output.render(t.allocator, compilation.diagnostics.items.items[0], compilation.src, .json);
    };
    try compilation.emit();
    const result = try native.run(&compilation);
    return std.fmt.allocPrint(t.allocator, "value:{d}", .{result.value});
}
fn agree(files: *Files, cache: *Cache) !void {
    const cached = try evaluate(files, cache);
    defer t.allocator.free(cached);
    const fresh = try evaluate(files, null);
    defer t.allocator.free(fresh);
    try t.expectEqualStrings(fresh, cached);
}
// spec: SEMANTIC-CACHE-6
test "semantic project body reuse relocates module spans and invalidates changed imports exports signatures and types" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import data
        \\
        \\
        \\def main() -> i64:
        \\    return data.value()
        },
        .{ .path = "data.my", .bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value() -> i64 effects():
        \\    return 41
        },
        .{ .path = "other.my", .bytes =
        \\module other
        \\export value
        \\
        \\
        \\def value() -> i64 effects():
        \\    return 43
        },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try agree(&files, &cache);
    entries[1].bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value() -> i64 effects():
        \\    return 42
    ;
    try agree(&files, &cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
    entries[1].bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value() -> bool effects():
        \\    return True
    ;
    try agree(&files, &cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
    entries[1].bytes =
        \\module data
        \\
        \\
        \\def value() -> i64:
        \\    return 42
    ;
    try agree(&files, &cache);
    entries[0].bytes =
        \\module main
        \\import other
        \\
        \\
        \\def main() -> i64:
        \\    return other.value()
    ;
    try agree(&files, &cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.reused);
}

// spec: MODULE-DOT-5
test "dotted imported function values keep callback type catalogs fresh across cache requests" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import data as d
        \\
        \\
        \\def main() -> i64:
        \\    helper = d.value
        \\    return helper()
        },
        .{ .path = "data.my", .bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value() -> i64 effects():
        \\    return 41
        },
    };
    var files: Files = .{ .entries = &entries };
    var cache = Cache.init(t.allocator, 4 * 1024 * 1024);
    defer cache.deinit();
    try agree(&files, &cache);
    entries[1].bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value() -> i64 effects():
        \\    return 42
    ;
    try agree(&files, &cache);
    // Callable values stay on the fresh path for C1; the ordinary `data.value`
    // body still publishes a reusable snapshot.
    try t.expectEqual(@as(usize, 0), cache.statistics.reused);
    try t.expectEqual(@as(usize, 0), cache.statistics.bypassed);
}
