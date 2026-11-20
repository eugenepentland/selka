//! Release baselines preserve facade names while tracking their target interfaces.
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
const api = @import("api_diff.zig");
const decisions = @import("release_decisions.zig");

const original =
    \\public record Value:
    \\    amount: int = 1
    \\public func value() -> int fails str:
    \\    return 1
;

const Files = struct {
    implementation: []const u8,

    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        const bytes = if (std.mem.eql(u8, path, "facade.selka"))
            "import bridge\nexport bridge.value\nexport bridge.Value\n"
        else if (std.mem.eql(u8, path, "bridge.selka"))
            "import impl\nexport impl.value\nexport impl.Value\n"
        else if (std.mem.eql(u8, path, "impl.selka"))
            self.implementation
        else
            return error.NotFound;
        if (bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, bytes);
    }
};

fn facadeEntries(allocator: std.mem.Allocator, implementation: []const u8) ![]api.Entry {
    var files: Files = .{ .implementation = implementation };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "facade", .{});
    var index = try interfaces.build(&project);
    // Restrict the snapshot to the facade so the defining module's own row
    // cannot mask an absent fingerprint on the published declaration.
    const facade = project.names.get("facade") orelse return error.TestUnexpectedResult;
    const bytes = try api.snapshotPublic(allocator, &index, &.{facade});
    defer allocator.free(bytes);
    return api.parseBaseline(allocator, bytes);
}

test "release baseline chained facades retain identities and track function and record signatures" {
    const before = try facadeEntries(t.allocator, original);
    defer api.freeEntries(t.allocator, before);
    const after = try facadeEntries(t.allocator,
        \\public record Value:
        \\    amount: int = 2
        \\public func value() -> int fails int:
        \\    return 1
    );
    defer api.freeEntries(t.allocator, after);
    try t.expectEqual(@as(usize, 2), before.len);
    try t.expectEqualStrings("facade::Value", before[0].display);
    try t.expectEqualStrings("facade::value", before[1].display);
    try t.expect(!std.mem.eql(u8, "-", before[0].interface));
    try t.expect(!std.mem.eql(u8, "-", before[1].interface));
    try t.expectEqualStrings(before[0].identity, after[0].identity);
    try t.expectEqualStrings(before[1].identity, after[1].identity);
    const comparison = try api.compareEntries(t.allocator, before, after);
    defer api.freeChanges(t.allocator, comparison);
    try t.expectEqual(@as(usize, 2), comparison.breaking.len);
    try t.expectEqual(@as(usize, 0), comparison.unchanged);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const findings = try decisions.coverage(arena.allocator(), before, after, &.{});
    try t.expectEqual(@as(usize, 2), findings.len);
    try t.expectEqualStrings("facade::Value", findings[0].name.?);
    try t.expectEqualStrings("facade::value", findings[1].name.?);
}

test "release baseline facade body changes need no pending decision" {
    const before = try facadeEntries(t.allocator, original);
    defer api.freeEntries(t.allocator, before);
    const after = try facadeEntries(t.allocator,
        \\public record Value:
        \\    amount: int = 1
        \\public func value() -> int fails str:
        \\    return 2
    );
    defer api.freeEntries(t.allocator, after);
    const comparison = try api.compareEntries(t.allocator, before, after);
    defer api.freeChanges(t.allocator, comparison);
    try t.expectEqual(@as(usize, 0), comparison.breaking.len);
    try t.expectEqual(@as(usize, 1), comparison.compatible.len);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const findings = try decisions.coverage(arena.allocator(), before, after, &.{});
    try t.expectEqual(@as(usize, 0), findings.len);
}
