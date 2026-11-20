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

test "review: extract actual scope pin-entry conditional without memory accesses" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var actual: Emitter = .{ .allocator = std.testing.allocator };
    defer actual.bytes.deinit(actual.allocator);
    try std.testing.expect(try scope.pin(Emitter, &actual, 0, 1));
    const branch_start = std.mem.indexOf(u8, actual.bytes.items, " jnz ") orelse return error.TestUnexpectedResult;
    const branch_end = std.mem.indexOfScalarPos(u8, actual.bytes.items, branch_start, '\n') orelse return error.TestUnexpectedResult;
    var parts = std.mem.splitScalar(u8, actual.bytes.items[branch_start + 5 .. branch_end], ',');
    _ = parts.next() orelse return error.TestUnexpectedResult;
    const yes = std.mem.trim(u8, parts.next() orelse return error.TestUnexpectedResult, " ");
    const no = std.mem.trim(u8, parts.next() orelse return error.TestUnexpectedResult, " ");
    try std.testing.expect(std.mem.startsWith(u8, yes, "@rcspinmark"));
    try std.testing.expect(std.mem.startsWith(u8, no, "@rcspindone"));
    const actual_branch = actual.bytes.items[0 .. branch_end + 1];
    try std.testing.expect(std.mem.indexOf(u8, actual_branch, " load") == null);
    try std.testing.expect(std.mem.indexOf(u8, actual_branch, " store") == null);
    var probe: Emitter = .{ .allocator = std.testing.allocator };
    defer probe.bytes.deinit(probe.allocator);
    try probe.print("export function w $review_pin_entry_truth(l %v1) {{\n@start\n{s}{s}\n ret 1\n{s}\n ret 0\n}}\n", .{ actual_branch, yes, no });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = ".tmp/abi5-truth/790-after/pin-emission.txt", .data = actual.bytes.items });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = ".tmp/abi5-truth/790-after/truth.ssa", .data = probe.bytes.items });
}
