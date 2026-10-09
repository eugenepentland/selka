//! Incremental parse reuse keeps diagnostics, semantic invalidation, and ownership fresh.
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
const Cache = @import("compiler.zig").syntax_cache.Cache;
const Files = struct {
    main: []const u8 =
        \\import data
        \\
        \\
        \\func main() -> i64:
        \\    return data.value()
    ,
    data: []const u8 = initial,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        const bytes = if (std.mem.eql(u8, path, "main.my")) self.main else if (std.mem.eql(u8, path, "data.my")) self.data else return error.NotFound;
        if (bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, bytes);
    }
    fn provider(self: *Files) graph.Provider {
        return .{ .context = self, .read = read };
    }
};
const initial =
    \\
    \\
    \\record Pair:
    \\    n: i64
    \\
    \\
    \\public func value() -> i64 effects():
    \\    mut x = Pair(n=7)
    \\    return x.n
;
const changed =
    \\
    \\
    \\record Pair:
    \\    n: i64
    \\
    \\
    \\public func value() -> i64 effects():
    \\    mut x = Pair(n=9)
    \\    return x.n
;
fn execute(allocator: std.mem.Allocator, files: *Files, cache: *Cache, clear: bool) !i64 {
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.buildWithCache(&project, cache, null);
    if (clear) cache.clear();
    var compilation = try @import("project_compile.zig").Compilation.init(&index);
    try compilation.check();
    const result = try @import("native_execute.zig").run(&compilation);
    return result.value;
}
fn scenario(allocator: std.mem.Allocator) !void {
    var cache = Cache.init(allocator, .{});
    defer cache.deinit();
    var files: Files = .{};
    try t.expectEqual(@as(i64, 7), try execute(allocator, &files, &cache, false));
    try t.expectEqual(@as(usize, 2), cache.statistics.misses);
    try t.expectEqual(@as(usize, 2), cache.statistics.stored);
    try t.expect(cache.statistics.retained_bytes > 0);
    try t.expectEqual(@as(i64, 7), try execute(allocator, &files, &cache, false));
    try t.expectEqual(@as(usize, 2), cache.statistics.hits);
    files.data = changed;
    try t.expectEqual(@as(i64, 9), try execute(allocator, &files, &cache, false));
    try t.expectEqual(@as(usize, 3), cache.statistics.hits);
    try t.expectEqual(@as(usize, 3), cache.statistics.misses);
    try t.expectEqual(@as(i64, 9), try execute(allocator, &files, &cache, true));
    try t.expectEqual(@as(usize, 5), cache.statistics.hits);
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
}
// spec: CACHE-1
test "buildWithCache lookup remember and clone preserve changed results and independent storage under allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "syntax cache eviction and zero retention obey limits without changing execution" {
    var cache = Cache.init(t.allocator, .{ .max_entries = 1 });
    defer cache.deinit();
    var files: Files = .{};
    try t.expectEqual(@as(i64, 7), try execute(t.allocator, &files, &cache, false));
    try t.expectEqual(@as(usize, 1), cache.entries.items.len);
    try t.expectEqual(@as(usize, 1), cache.statistics.evicted);
    try t.expect(cache.statistics.retained_bytes <= cache.limits.max_bytes);
    cache.clear();
    cache.limits.max_bytes = 1;
    try t.expectEqual(@as(i64, 7), try execute(t.allocator, &files, &cache, false));
    try t.expectEqual(@as(usize, 2), cache.statistics.bypassed);
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
    cache.limits.max_bytes = files.main.len + files.data.len;
    try t.expectEqual(@as(i64, 7), try execute(t.allocator, &files, &cache, false));
    try t.expectEqual(@as(usize, 4), cache.statistics.bypassed);
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
}
test "cached syntax never suppresses fresh interface or semantic errors" {
    var cache = Cache.init(t.allocator, .{});
    defer cache.deinit();
    var files: Files = .{};
    _ = try execute(t.allocator, &files, &cache, false);
    files.data =
        \\
        \\
        \\public func value() -> bool effects():
        \\    return True
    ;
    try t.expectError(error.SourceError, execute(t.allocator, &files, &cache, false));
    const hits = cache.statistics.hits;
    try t.expectError(error.SourceError, execute(t.allocator, &files, &cache, false));
    try t.expectEqual(hits + 2, cache.statistics.hits);
    files.data =
        \\
        \\
        \\func value() -> i64:
        \\    return 7
    ;
    try t.expectError(error.SourceError, execute(t.allocator, &files, &cache, false));
    files.data = initial;
    try t.expectEqual(@as(i64, 7), try execute(t.allocator, &files, &cache, false));
}
test "failed parseModule and moduleSyntax results are never remembered" {
    var cache = Cache.init(t.allocator, .{});
    defer cache.deinit();
    var files: Files = .{ .data = "module data;public def value()->i64{return +;}" };
    try t.expectError(error.SourceError, execute(t.allocator, &files, &cache, false));
    try t.expectError(error.SourceError, execute(t.allocator, &files, &cache, false));
    try t.expectEqual(@as(usize, 0), cache.statistics.stored);
    files.data = initial;
    try t.expectEqual(@as(i64, 7), try execute(t.allocator, &files, &cache, false));
}

test "incremental source provider preserves TooLarge and missing-file failures" {
    var files: Files = .{};
    try t.expectError(error.TooLarge, Files.read(&files, t.allocator, "main.my", 0));
    try t.expectError(error.NotFound, Files.read(&files, t.allocator, "absent.my", 1024));
}

test "cached quoted byte arrays survive source relocation and cache eviction" {
    var cache = Cache.init(t.allocator, .{});
    defer cache.deinit();
    var files: Files = .{ .data =
        \\
        \\
        \\public func value() -> i64 effects(managed_allocation):
        \\    mut s = b"a\x00b"
        \\    return i64(s[2])
    };
    try t.expectEqual(@as(i64, 98), try execute(t.allocator, &files, &cache, false));
    try t.expectEqual(@as(i64, 98), try execute(t.allocator, &files, &cache, true));
    try t.expectEqual(@as(usize, 2), cache.statistics.hits);
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
}

// spec-case: FRONTEND-CACHE-3
test "in-memory syntax cache preserves expression lambdas across a hit" {
    var cache = Cache.init(t.allocator, .{});
    defer cache.deinit();
    var files: Files = .{ .main =
        \\
        \\
        \\func apply(f: func(int) -> int effects(), value: int) -> int:
        \\    return f(value)
        \\
        \\
        \\func main() -> int:
        \\    return apply(lambda value: value * 2, 21)
    };
    try t.expectEqual(@as(i64, 42), try execute(t.allocator, &files, &cache, false));
    try t.expectEqual(@as(i64, 42), try execute(t.allocator, &files, &cache, false));
    try t.expectEqual(@as(usize, 1), cache.statistics.stored);
    try t.expectEqual(@as(usize, 1), cache.statistics.hits);
}
