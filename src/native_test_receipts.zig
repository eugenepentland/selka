//! Verified positive test receipts; missing or damaged entries are cache misses.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const same = @import("native_test_snapshot.zig").equivalent;
/// Filesystem and serialization failures while recording a successful result.
pub const Error = fs.Error || std.Io.Writer.Error || std.Io.Dir.DeleteFileError;
/// Reported result and its semantic invalidation evidence.
pub const Result = struct {
    name: []const u8,
    status: []const u8,
    actual: std.json.Value = .null,
    expected: std.json.Value = .null,
    reason: []const u8 = "",
    key: []const u8 = "",
    dependencies: []const []const u8 = &.{},
    cacheable: bool = false,
    reasons: []const []const u8 = &.{},
    steps: u64 = 0,
};
/// A receipt is valid only when its full payload and expectation agree.
pub fn hit(context: fs.Context, filename: []const u8, key: []const u8, name: []const u8, expected: std.json.Value) bool {
    const bytes = context.read(filename) catch return false;
    const parsed = std.json.parseFromSlice(std.json.Value, context.allocator, bytes, .{}) catch return false;
    const payload = v.text(v.get(parsed.value, "payload"));
    const digest = fs.hash(context.allocator, payload) catch return false;
    if (!std.mem.eql(u8, digest, v.text(v.get(parsed.value, "sha256")))) return false;
    const item = std.json.parseFromSlice(std.json.Value, context.allocator, payload, .{}) catch return false;
    return std.mem.eql(u8, v.text(v.get(item.value, "key")), key) and
        std.mem.eql(u8, v.text(v.get(item.value, "name")), name) and
        std.mem.eql(u8, v.text(v.get(item.value, "status")), "passed") and
        same(v.get(item.value, "actual"), expected) and same(v.get(item.value, "expected"), expected);
}
/// A rerun must remove any old success before it can fail or be interrupted.
pub fn invalidate(context: fs.Context, filename: []const u8) Error!void {
    std.Io.Dir.cwd().deleteFile(context.io, filename) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
}
/// Publish only successful deterministic executions, after source integrity checks.
pub fn write(context: fs.Context, directory: []const u8, result: Result) Error!void {
    if (!result.cacheable or !std.mem.eql(u8, result.status, "passed")) return;
    const payload = try std.json.Stringify.valueAlloc(context.allocator, result, .{});
    const bytes = try std.json.Stringify.valueAlloc(context.allocator, .{ .payload = payload, .sha256 = try fs.hash(context.allocator, payload) }, .{});
    try context.atomic(try path(context, directory, result.key), bytes);
}
/// Content-addressed result entry, separate from native object artifacts.
pub fn path(context: fs.Context, directory: []const u8, key: []const u8) Error![]const u8 {
    return std.fs.path.join(context.allocator, &.{ directory, try std.fmt.allocPrint(context.allocator, "{s}.json", .{key}) });
}

test "positive receipts reject corruption mismatched expectations and failures" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const result: Result = .{ .name = "test_ok", .status = "passed", .actual = .{ .bool = true }, .expected = .{ .bool = true }, .key = "abc", .cacheable = true };
    const filename = try path(context, directory, result.key);
    try std.testing.expect(!hit(context, filename, "abc", result.name, result.expected));
    try write(context, directory, result);
    try std.testing.expect(hit(context, filename, "abc", result.name, result.expected));
    try std.testing.expect(!hit(context, filename, "abc", result.name, .{ .bool = false }));
    try context.write(filename, "{\"payload\":\"bad\",\"sha256\":\"bad\"}");
    try std.testing.expect(!hit(context, filename, "abc", result.name, result.expected));
    try write(context, directory, result);
    try invalidate(context, filename);
    var failed = result;
    failed.status = "failed";
    try write(context, directory, failed);
    try std.testing.expect(!hit(context, filename, "abc", result.name, result.expected));
}
