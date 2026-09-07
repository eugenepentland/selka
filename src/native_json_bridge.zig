//! Native JSON support reuses the normative parser without linking an interpreter.
const std = @import("std");
const document = @import("json_document.zig");
comptime {
    if (!@import("builtin").is_test) @export(&parseDocumentC, .{ .name = "mylang_native_json_document_v1" });
}
const Result = struct { words: []i64 = &.{}, status: c_int = 0 };
fn parse(allocator: std.mem.Allocator, bytes: []const u8) Result {
    var bounded: @import("codec_memory.zig").Memory = .{ .parent = allocator, .limit = 128 * 1024 * 1024 };
    const words = document.parse(bounded.allocator(), bytes) catch |err| return .{ .status = switch (err) {
        error.OutOfMemory => if (bounded.limit_failure) 2 else -1,
        error.CodecByteLimit, error.CodecDepthLimit, error.CodecTokenLimit => 2,
        else => 1,
    } };
    return .{ .words = words };
}
// The C caller owns successful output and frees it with the C allocator.
fn parseDocumentC(memory: *const NativeAllocator, bytes: [*]const u8, length: usize, output: *?[*]i64, count: *usize) callconv(.c) c_int {
    const result = parse(memory.allocator(), bytes[0..length]);
    output.* = if (result.status == 0) result.words.ptr else null;
    count.* = result.words.len;
    return result.status;
}
// spec: NATIVE-JSON-1
test "native JSON bridge preserves malformed and allocation errors and owned output" {
    const t = std.testing;
    const parsed = parse(t.allocator, "{\"n\":42}");
    defer t.allocator.free(parsed.words);
    try t.expectEqual(@as(c_int, 0), parsed.status);
    try t.expectEqual(@as(i64, 42), parsed.words[23]);
    try t.expectEqual(@as(c_int, 1), parse(t.allocator, "{\"x\":0,\"x\":1}").status);
    try t.expectEqual(@as(c_int, 1), parse(t.allocator, "\"\xc0\x80\"").status);
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    try t.expectEqual(@as(c_int, -1), parse(failing.allocator(), "[]").status);
}

const NativeAllocator = extern struct {
    allocate: *const fn (usize) callconv(.c) ?*anyopaque,
    reallocate: *const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    release: *const fn (?*anyopaque) callconv(.c) void,
    fn allocator(self: *const NativeAllocator) std.mem.Allocator {
        return .{ .ptr = @constCast(self), .vtable = &.{ .alloc = allocateBytes, .resize = resizeBytes, .remap = remapBytes, .free = freeBytes } };
    }
    fn allocateBytes(context: *anyopaque, length: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *const NativeAllocator = @ptrCast(@alignCast(context));
        if (std.mem.Alignment.compare(alignment, .gt, .of(std.c.max_align_t))) return null;
        return @ptrCast(self.allocate(length) orelse return null);
    }
    fn resizeBytes(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }
    fn remapBytes(context: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, length: usize, _: usize) ?[*]u8 {
        const self: *const NativeAllocator = @ptrCast(@alignCast(context));
        if (std.mem.Alignment.compare(alignment, .gt, .of(std.c.max_align_t))) return null;
        return @ptrCast(self.reallocate(bytes.ptr, length) orelse return null);
    }
    fn freeBytes(context: *anyopaque, bytes: []u8, _: std.mem.Alignment, _: usize) void {
        const self: *const NativeAllocator = @ptrCast(@alignCast(context));
        self.release(bytes.ptr);
    }
};
