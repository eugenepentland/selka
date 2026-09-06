//! Finite packed value layouts for the experimental C backend, never a public ABI.
const std = @import("std");
const typed = @import("typed.zig");
/// Computed native storage support and representation metadata for nominal schemas.
pub const Layout = struct {
    allocator: std.mem.Allocator,
    records: []const typed.Record,
    widths: []u8,
    supported: []bool,
    /// Compute native layouts from checked schemas using the supplied allocator.
    pub fn init(allocator: std.mem.Allocator, records: []const typed.Record) std.mem.Allocator.Error!Layout {
        const widths = try allocator.alloc(u8, records.len);
        errdefer allocator.free(widths);
        @memset(widths, 0);
        const supported = try allocator.alloc(bool, records.len);
        errdefer allocator.free(supported);
        @memset(supported, false);
        const states = try allocator.alloc(u2, records.len);
        defer allocator.free(states);
        @memset(states, 0);
        var stack: std.ArrayList(LayoutFrame) = .empty;
        defer stack.deinit(allocator);
        var layout: Layout = .{ .allocator = allocator, .records = records, .widths = widths, .supported = supported };
        for (records, 0..) |_, root| {
            if (states[root] == 2) continue;
            try stack.append(allocator, .{ .index = root });
            try layout.resolvePending(states, &stack);
        }
        return layout;
    }
    fn resolvePending(self: *Layout, states: []u2, stack: *std.ArrayList(LayoutFrame)) !void {
        const allocator = self.allocator;
        const records = self.records;
        const widths = self.widths;
        const supported = self.supported;
        while (stack.items.len != 0) {
            const frame = &stack.items[stack.items.len - 1];
            const index = frame.index;
            const record = records[index];
            states[index] = 1;
            if (record.shape.domain) |backing| {
                widths[index] = self.width(backing);
                supported[index] = self.supports(backing);
            } else if (record.shape.buffer) |element| {
                if (unvisitedChild(element, states)) |child_index| {
                    try stack.append(allocator, .{ .index = child_index });
                    continue;
                }
                supported[index] = self.supports(element);
            } else if (!record.shape.hasRuntimeIdentity()) {
                const child_count = if (record.shape.variants) |v| v.cases.len else if (record.shape.array != null) @as(usize, 1) else record.fields.len;
                if (frame.next < child_count) {
                    const child = childType(record, frame.next);
                    frame.next += 1;
                    if (unvisitedChild(child, states)) |child_index| {
                        try stack.append(allocator, .{ .index = child_index });
                    }
                    continue;
                }
                self.pack(index, child_count);
            }
            states[index] = 2;
            _ = stack.pop();
        }
    }
    fn pack(self: *Layout, index: usize, child_count: usize) void {
        const record = self.records[index];
        self.supported[index] = true;
        var payload_bits: u8 = 0;
        var packable = true;
        for (0..child_count) |child_index| if (childType(record, child_index)) |ty| {
            if (!self.supports(ty)) self.supported[index] = false;
            const bits = self.width(ty);
            if (bits == 0) packable = false;
            payload_bits = @max(payload_bits, bits);
        };
        if (record.shape.variants) |variants| {
            const total = @as(u16, payload_bits) + tagBits(variants.cases.len);
            if (self.supported[index] and packable and total <= 127) self.widths[index] = @intCast(total);
        }
    }
    pub fn deinit(self: *Layout) void {
        self.allocator.free(self.widths);
        self.allocator.free(self.supported);
    }
    /// Check whether the native backend can represent the supplied type.
    pub fn supports(self: Layout, ty: typed.Type) bool {
        if (ty.isInteger() or ty == .bool or ty == .allocator) return true;
        return ty.isAggregate() and self.supported[ty.recordIndex()];
    }
    /// Return the native integer representation width for a supported type.
    pub fn width(self: Layout, ty: typed.Type) u8 {
        if (ty.integer()) |integer| return integer.bits;
        if (ty == .bool) return 1;
        return if (ty.isAggregate()) self.widths[ty.recordIndex()] else 0;
    }
    /// Return the signedness of a supported native integer representation.
    pub fn signed(self: Layout, ty: typed.Type) bool {
        const scalar = if (ty.isAggregate()) self.records[ty.recordIndex()].shape.domain orelse return false else ty;
        return if (scalar.integer()) |integer| integer.signed else false;
    }
};
/// Choose the integer width needed to encode the declared number of variant cases.
pub fn tagBits(count: usize) u8 {
    return if (count <= 2) 1 else @intCast(@bitSizeOf(usize) - @clz(count - 1));
}

fn childType(record: typed.Record, index: usize) ?typed.Type {
    if (record.shape.variants) |variants| return variants.cases[index].payload;
    if (record.shape.array) |array| return array.element;
    return record.fields[index].ty;
}

fn unvisitedChild(child: ?typed.Type, states: []const u2) ?usize {
    const ty = child orelse return null;
    if (!ty.isAggregate()) return null;
    const index = ty.recordIndex();
    return if (states[index] == 0) index else null;
}

const LayoutFrame = struct { index: usize, next: usize = 0 };
