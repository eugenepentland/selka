//! Pin inherited build inputs without exposing environment values in receipts.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
/// Allocation and canonical environment serialization failures.
pub const Error = fs.Error;
/// Canonical fingerprint and eligibility for persistent successful results.
pub const Fingerprint = struct { hash: []const u8, cacheable: bool };
/// Dynamic loader overrides can read mutable external libraries, so cannot reuse passes.
pub fn capture(context: fs.Context) Error!Fingerprint {
    var pairs: std.ArrayList([2][]const u8) = .empty;
    defer pairs.deinit(context.allocator);
    var entries = context.environ.iterator();
    var cacheable = true;
    while (entries.next()) |entry| {
        try pairs.append(context.allocator, .{ entry.key_ptr.*, entry.value_ptr.* });
        if (std.mem.startsWith(u8, entry.key_ptr.*, "LD_") and entry.value_ptr.len != 0) cacheable = false;
    }
    std.mem.sort([2][]const u8, pairs.items, {}, less);
    const bytes = try std.json.Stringify.valueAlloc(context.allocator, pairs.items, .{});
    return .{ .hash = try fs.hash(context.allocator, bytes), .cacheable = cacheable };
}
fn less(_: void, a: [2][]const u8, b: [2][]const u8) bool {
    return std.mem.lessThan(u8, a[0], b[0]);
}
test "environment fingerprints ignore insertion order and reject mutable loader overrides" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    try environment.put("B", "2");
    try environment.put("A", "1");
    const first = try capture(context);
    var reordered: std.process.Environ.Map = .init(std.testing.allocator);
    defer reordered.deinit();
    try reordered.put("A", "1");
    try reordered.put("B", "2");
    context.environ = &reordered;
    try std.testing.expectEqualStrings(first.hash, (try capture(context)).hash);
    context.environ = &environment;
    try environment.put("A", "changed");
    try std.testing.expect(!std.mem.eql(u8, first.hash, (try capture(context)).hash));
    try environment.put("LD_LIBRARY_PATH", "/mutable");
    try std.testing.expect(!(try capture(context)).cacheable);
}
