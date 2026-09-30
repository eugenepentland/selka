//! Owned ABI5 review fixture: execute the production scope emitter in a native probe.
const std = @import("std");
const scope = @import("qbe_rc_scope_inline.zig");
const runtime = @import("runtime_mode.zig");
const Error = @import("qbe_rc_unique.zig").Error;
const Emitter = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
    next: usize = 2,
    pub fn temp(self: *Emitter) usize {
        defer self.next += 1;
        return self.next;
    }
    pub fn print(self: *Emitter, comptime format: []const u8, args: anytype) Error!void {
        const text = try std.fmt.allocPrint(self.allocator, format, args);
        defer self.allocator.free(text);
        try self.bytes.appendSlice(self.allocator, text);
    }
    pub fn address(self: *Emitter, base: usize, offset: u64) Error!usize {
        const result = self.temp();
        try self.print(" %v{d} =l add %v{d}, {d}\n", .{ result, base, offset });
        return result;
    }
};

test "review: emit actual scope pin and end code for ABI5 executable probe" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var emitter: Emitter = .{ .allocator = std.testing.allocator };
    defer emitter.bytes.deinit(emitter.allocator);
    try emitter.print("export function w $review_scope_pin(l %ctx, l %heap, l %v0, l %v1) {{\n@start\n", .{});
    try std.testing.expect(try scope.begin(Emitter, &emitter, 0));
    try std.testing.expect(try scope.pin(Emitter, &emitter, 0, 1));
    try emitter.print(" ret 1\n@failure\n ret 0\n}}\n", .{});
    try emitter.print("export function $review_scope_end(l %ctx, l %heap, l %v0) {{\n@start\n", .{});
    try std.testing.expect(try scope.end(Emitter, &emitter, 0));
    try emitter.print(" ret\n}}\n", .{});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = ".tmp/abi5-corrected-790/scope.ssa", .data = emitter.bytes.items });
}
