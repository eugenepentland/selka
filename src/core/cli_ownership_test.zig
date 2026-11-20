//! Compatibility and diagnostic contracts for the checked ownership default.
const std = @import("std");
const selectors = @import("cli_ownership.zig");
const allocation = @import("allocation_contract.zig");
const language = @import("selka");

// spec: OWNERSHIP-RETIREMENT-CLI-1
test "retired ownership flags fail while guest arguments are preserved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var report: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.OwnershipSelectorRetired, selectors.normalize(arena.allocator(), &.{ "selka", "check", "main.selka", "--experimental-zero-rc" }, &report));
    try std.testing.expectError(error.OwnershipSelectorRetired, selectors.normalize(arena.allocator(), &.{ "selka", "build", "main.selka", "--experimental-single-owner=true" }, &report));
    try std.testing.expect(std.mem.indexOf(u8, report.items, "reference counting was removed") != null);
    report.clearRetainingCapacity();
    const args = try selectors.normalize(arena.allocator(), &.{ "selka", "run", "main.selka", "--", "--experimental-zero-rc" }, &report);
    try std.testing.expectEqual(@as(usize, 5), args.len);
    try std.testing.expectEqualStrings("--experimental-zero-rc", args[4]);
    try std.testing.expectEqual(@as(usize, 0), report.items.len);
}

// spec: OWNERSHIP-DEFAULT-NOALLOC-1
test "noalloc violations are errors with the source promise as related location" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const diagnostic = try allocation.diagnostic(arena.allocator(), .{ .function = "bounded", .callee = "allocating", .span = 42, .unresolved = false, .bound = .{ .start = 3, .end = 11 } });
    try std.testing.expect(diagnostic.severity == .err);
    try std.testing.expectEqualStrings("E_NOALLOC_ALLOCATES", diagnostic.code);
    try std.testing.expectEqual(@as(u32, 42), diagnostic.span.start);
    try std.testing.expectEqual(@as(u32, 3), diagnostic.related.?.span.start);
    try std.testing.expectEqual(.C3, diagnostic.provenance.rule.?);
    const src = try language.source.Source.init(arena.allocator(), "bounded.selka", "@noalloc\nfunc bounded() -> int:\n    return allocate()\n");
    const text = try diagnostic.render(arena.allocator(), src);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "ownership rule C3"));
    try std.testing.expect(std.mem.indexOf(u8, text, "noalloc promise declared here") != null);
    const json = try language.diagnostic_output.render(arena.allocator(), diagnostic, src, .json);
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), std.mem.trimEnd(u8, json, "\n"), .{});
    try std.testing.expectEqualStrings("C3", parsed.object.get("diagnostic").?.object.get("rule").?.string);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, json, "\"rule\""));
    try std.testing.expect(std.mem.indexOf(u8, json, "noalloc promise declared here") != null);
}
