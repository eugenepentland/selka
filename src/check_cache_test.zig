const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const Cache = language.check_cache.Cache;
const Files = struct {
    bytes: []const u8 =
        \\
        \\
        \\func main() -> i64:
        \\    mut unused = 7
        \\    return 0
    ,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return allocator.dupe(u8, self.bytes);
    }
};
fn load(project: *language.project.Project, files: *Files) !void {
    try project.load(.{ .context = files, .read = Files.read }, "main", .{});
}
fn remember(allocator: std.mem.Allocator, cache: *Cache, files: *Files) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try load(&project, files);
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    try cache.remember(&project, compilation.src, compilation.diagnostics.items.items);
}
fn scenario(allocator: std.mem.Allocator) !void {
    var cache = Cache.init(allocator, 1024 * 1024);
    defer cache.deinit();
    var files: Files = .{};
    try remember(allocator, &cache, &files);
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try load(&project, &files);
    const warnings = cache.lookup(&project).?;
    try t.expect(std.mem.indexOf(u8, warnings, "W_UNUSED_BINDING") != null);
    try t.expect(std.mem.indexOf(u8, warnings, "main.selka:4:") != null);
    const original = project.modules.items[0].src.path;
    project.modules.items[0].src.path = "renamed.selka";
    try t.expect(cache.lookup(&project) == null);
    project.modules.items[0].src.path = original;
    try t.expect(cache.lookup(&project) != null);
    files.bytes =
        \\
        \\
        \\func main() -> i64:
        \\    return 1
    ;
    var changed = language.project.Project.init(allocator);
    defer changed.deinit();
    try load(&changed, &files);
    try t.expect(cache.lookup(&changed) == null);
    try remember(allocator, &cache, &files);
    try t.expectEqualStrings("", cache.lookup(&changed).?);
    try t.expect(cache.lookup(&project) == null);
    cache.clear();
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
    try t.expect(cache.lookup(&changed) == null);
}
// spec: CHECK-CACHE-1
test "successful check cache owns exact sources and warning replay under allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "check cache InvalidVerdict rejects incomplete loads and error diagnostics" {
    var cache = Cache.init(t.allocator, 1024 * 1024);
    defer cache.deinit();
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    const src = try language.source.Source.init(project.arena.allocator(), source_names.entry, "");
    try t.expectError(error.InvalidVerdict, cache.remember(&project, src, &.{}));
    var files: Files = .{};
    try load(&project, &files);
    try t.expectError(error.InvalidVerdict, cache.remember(&project, src, &.{.{ .code = "E_TEST", .message = "rejected", .span = .{ .start = 0, .end = 0 } }}));
}
test "check cache retention limits bypass oversized successful verdicts" {
    var files: Files = .{};
    var cache = Cache.init(t.allocator, 0);
    defer cache.deinit();
    try remember(t.allocator, &cache, &files);
    cache.max_bytes = files.bytes.len;
    try remember(t.allocator, &cache, &files);
    try t.expectEqual(@as(usize, 2), cache.statistics.bypassed);
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
}

test "check cache replacement OutOfMemory preserves the prior successful verdict" {
    var failing = t.FailingAllocator.init(t.allocator, .{});
    var cache = Cache.init(failing.allocator(), 1024 * 1024);
    defer cache.deinit();
    var files: Files = .{};
    try remember(t.allocator, &cache, &files);
    var original = language.project.Project.init(t.allocator);
    defer original.deinit();
    try load(&original, &files);
    failing.fail_index = failing.alloc_index;
    files.bytes =
        \\
        \\
        \\func main() -> i64:
        \\    return 9
    ;
    try t.expectError(error.OutOfMemory, remember(t.allocator, &cache, &files));
    try t.expect(cache.lookup(&original) != null);
    try t.expectEqual(@as(usize, 1), cache.statistics.stored);
}

fn jsonScenario(allocator: std.mem.Allocator) !void {
    var cache = Cache.init(allocator, 1024 * 1024);
    defer cache.deinit();
    cache.format = .json;
    var files: Files = .{};
    try remember(allocator, &cache, &files);
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try load(&project, &files);
    const warnings = cache.lookup(&project).?;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, warnings, .{});
    defer parsed.deinit();
    try t.expectEqualStrings("diagnostic-v1", parsed.value.object.get("version").?.string);
    try t.expectEqualStrings("W_UNUSED_BINDING", parsed.value.object.get("diagnostic").?.object.get("code").?.string);
    cache.format = .text;
    try t.expect(cache.lookup(&project) == null);
    cache.format = .json;
    try t.expectEqualStrings(warnings, cache.lookup(&project).?);
}

test "successful verdict warnings retain JSON format and cannot replay across format changes" {
    try jsonScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), jsonScenario, .{});
}

fn policyIdentityScenario(allocator: std.mem.Allocator) !void {
    var cache = Cache.init(allocator, 1024 * 1024);
    defer cache.deinit();
    var files: Files = .{};
    // The identity lives in a buffer the caller then reuses, as a returning
    // frame's locals are: the cache must key on its own copy.
    var buffer: [64]u8 = @splat('a');
    try cache.setPolicyIdentity(&buffer);
    try remember(allocator, &cache, &files);
    buffer = @splat('z');
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try load(&project, &files);
    try t.expect(cache.lookup(&project) != null);
    try cache.setPolicyIdentity(&buffer);
    try t.expect(cache.lookup(&project) == null);
    try cache.setPolicyIdentity(null);
    try t.expect(cache.lookup(&project) == null);
    buffer = @splat('a');
    try cache.setPolicyIdentity(&buffer);
    try t.expect(cache.lookup(&project) != null);
}

// spec: POLICY-IDENTITY-OWNED-1
test "check cache owns its policy identity so a reused caller buffer cannot change the key" {
    try policyIdentityScenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, policyIdentityScenario, .{});
}
