//! Finite packed value layouts for the experimental C backend, never a public ABI.
const std = @import("std");
const typed = @import("typed.zig");
pub const Layout = struct {
    allocator: std.mem.Allocator,
    records: []const typed.Record,
    widths: []u8,
    supported: []bool,
    pub fn init(allocator: std.mem.Allocator, records: []const typed.Record) !Layout {
        const widths = try allocator.alloc(u8, records.len);
        errdefer allocator.free(widths);
        @memset(widths, 0);
        const supported = try allocator.alloc(bool, records.len);
        errdefer allocator.free(supported);
        @memset(supported, false);
        const states = try allocator.alloc(u2, records.len);
        defer allocator.free(states);
        @memset(states, 0);
        const Frame = struct { index: usize, next: usize = 0 };
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(allocator);
        var layout: Layout = .{ .allocator = allocator, .records = records, .widths = widths, .supported = supported };
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
                    supported[index] = layout.supports(backing);
                } else if (!record.move_only and record.pool == null and record.handle_pool == null and record.resource == null and record.buffer == null) {
                    const child_count = if (record.variants) |v| v.cases.len else if (record.array != null) @as(usize, 1) else record.fields.len;
                    if (frame.next < child_count) {
                        const child = childType(record, frame.next);
                        frame.next += 1;
                        if (child) |ty| if (ty.isAggregate() and states[ty.recordIndex()] == 0) {
                            try stack.append(allocator, .{ .index = ty.recordIndex() });
                        };
                        continue;
                    }
                    supported[index] = true;
                    var payload_bits: u8 = 0;
                    var packable = true;
                    for (0..child_count) |child_index| if (childType(record, child_index)) |ty| {
                        if (!layout.supports(ty)) supported[index] = false;
                        const bits = layout.width(ty);
                        if (bits == 0) packable = false;
                        payload_bits = @max(payload_bits, bits);
                    };
                    if (record.variants) |variants| {
                        const total = @as(u16, payload_bits) + tagBits(variants.cases.len);
                        if (supported[index] and packable and total <= 127) widths[index] = @intCast(total);
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
        self.allocator.free(self.supported);
    }
    pub fn supports(self: Layout, ty: typed.Type) bool {
        return ty.isInteger() or ty == .bool or (ty.isAggregate() and self.supported[ty.recordIndex()]);
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

fn childType(record: typed.Record, index: usize) ?typed.Type {
    if (record.variants) |variants| return variants.cases[index].payload;
    if (record.array) |array| return array.element;
    return record.fields[index].ty;
}
