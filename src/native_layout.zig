//! Finite packed value layouts for the experimental C backend, never a public ABI.
const std = @import("std");
const typed = @import("typed.zig");
pub const Layout = struct {
    allocator: std.mem.Allocator,
    records: []const typed.Record,
    widths: []u8,
    pub fn init(allocator: std.mem.Allocator, records: []const typed.Record) !Layout {
        const widths = try allocator.alloc(u8, records.len);
        errdefer allocator.free(widths);
        @memset(widths, 0);
        const states = try allocator.alloc(u2, records.len);
        defer allocator.free(states);
        @memset(states, 0);
        const Frame = struct { index: usize, next: usize = 0 };
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(allocator);
        var layout: Layout = .{ .allocator = allocator, .records = records, .widths = widths };
        for (records, 0..) |_, root| {
            if (states[root] == 2) continue;
            try stack.append(allocator, .{ .index = root });
            while (stack.items.len != 0) {
                const frame = &stack.items[stack.items.len - 1];
                const index = frame.index;
                const record = records[index];
                states[index] = 1;
                if (record.domain) |backing| {
                    widths[index] = layout.width(backing);
                } else if (record.variants) |variants| {
                    if (!variants.is_union) {
                        widths[index] = tagBits(variants.cases.len);
                    } else if (!record.move_only) {
                        if (frame.next < variants.cases.len) {
                            const payload = variants.cases[frame.next].payload;
                            frame.next += 1;
                            if (payload) |ty| if (ty.isAggregate() and states[ty.recordIndex()] == 0) {
                                try stack.append(allocator, .{ .index = ty.recordIndex() });
                            };
                            continue;
                        }
                        var payload_bits: u8 = 0;
                        var supported = true;
                        for (variants.cases) |case| if (case.payload) |ty| {
                            const bits = layout.width(ty);
                            if (bits == 0) supported = false;
                            payload_bits = @max(payload_bits, bits);
                        };
                        const total = @as(u16, payload_bits) + tagBits(variants.cases.len);
                        if (supported and total <= 127) widths[index] = @intCast(total);
                    }
                }
                states[index] = 2;
                _ = stack.pop();
            }
        }
        return layout;
    }
    pub fn deinit(self: *Layout) void {
        self.allocator.free(self.widths);
    }
    pub fn width(self: Layout, ty: typed.Type) u8 {
        if (ty.integer()) |integer| return integer.bits;
        if (ty == .bool) return 1;
        return if (ty.isAggregate()) self.widths[ty.recordIndex()] else 0;
    }
    pub fn signed(self: Layout, ty: typed.Type) bool {
        const scalar = if (ty.isAggregate()) self.records[ty.recordIndex()].domain orelse return false else ty;
        return if (scalar.integer()) |integer| integer.signed else false;
    }
};
pub fn tagBits(count: usize) u8 {
    return if (count <= 2) 1 else @intCast(@bitSizeOf(usize) - @clz(count - 1));
}
