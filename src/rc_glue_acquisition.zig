//! Bounded physical acquisition: admit every live prefix before taking tokens.
const std = @import("std");
const native = @import("native_types.zig");
const typed = @import("typed.zig");
const shapes = @import("rc_shape.zig");
const semantics = @import("value_semantics.zig");

const Leaf = struct { offset: u64, hold: bool };
const Arm = struct { tag: ?usize, leaves: []const Leaf };
const limit = 8;

/// One physical loan or retain operation to emit.
pub const Value = struct { ty: typed.Type, name: []const u8, size: u64, loan: bool };

/// Emit complete small-value acquisition without owning the caller's arena.
pub fn write(a: std.mem.Allocator, catalog: *native.Catalog, facts: *shapes.Catalog, value: Value, out: *std.Io.Writer) native.Error!bool {
    var generator: Generator = .{ .allocator = a, .catalog = catalog, .facts = facts, .writer = out };
    return generator.write(value.ty, value.name, value.size, value.loan);
}

const Generator = struct {
    allocator: std.mem.Allocator,
    catalog: *native.Catalog,
    facts: *shapes.Catalog,
    writer: *std.Io.Writer,

    fn print(self: *Generator, comptime format: []const u8, arguments: anytype) native.Error!void {
        self.writer.print(format, arguments) catch return error.OutOfMemory;
    }

    fn text(self: *Generator, value: []const u8) native.Error!void {
        self.writer.writeAll(value) catch return error.OutOfMemory;
    }

    /// Emit complete small-value acquisition; leave larger/nested cases to
    /// the general generated walks without emitting any partial statements.
    fn write(self: *Generator, ty: typed.Type, name: []const u8, size: u64, loan: bool) native.Error!bool {
        const a = self.allocator;
        const catalog = self.catalog;
        if (size == 0 or size / @sizeOf(usize) > limit) return false;
        const layout = try catalog.layout(ty);
        var arms: std.ArrayList(Arm) = .empty;
        if (layout.kind == .variant and !semantics.isLiveView(catalog.records, ty)) {
            for (layout.fields, 0..) |field, index| {
                const tag = field.tag orelse 0;
                var first = true;
                for (layout.fields[0..index]) |earlier| if ((earlier.tag orelse 0) == tag) {
                    first = false;
                };
                if (!first) continue;
                var leaves: std.ArrayList(Leaf) = .empty;
                for (layout.fields[index..]) |member| if ((member.tag orelse 0) == tag) {
                    if (!try self.collect(member.ty, member.offset, &leaves)) return false;
                };
                if (leaves.items.len != 0) try arms.append(a, .{ .tag = tag, .leaves = leaves.items });
            }
        } else {
            var leaves: std.ArrayList(Leaf) = .empty;
            if (!try self.collect(ty, 0, &leaves)) return false;
            try arms.append(a, .{ .tag = null, .leaves = leaves.items });
        }
        if (layout.kind == .variant and !semantics.isLiveView(catalog.records, ty)) try self.text("switch (myl_rcg_tag(src)) {\n");
        for (arms.items) |arm| {
            if (arm.tag) |tag| try self.print("case {d}: {{\n", .{tag});
            try self.admission(arm.leaves, name, size, loan);
            if (arm.tag != null) try self.text("break;\n}\n");
        }
        if (layout.kind == .variant and !semantics.isLiveView(catalog.records, ty)) try self.text("default: break;\n}\n");
        if (loan) {
            try self.print("MYL_RCG_CHECK(!myl_rcg_overlap(dst, src, {d}));\nmemcpy(dst, src, {d});\n", .{ size, size });
        } else {
            try self.print("MYL_RCG_CHECK(dst != src && region <= heap->region_depth);\nmemmove(dst, src, {d});\n", .{size});
        }
        return true;
    }

    fn collect(self: *Generator, ty: typed.Type, offset: u64, leaves: *std.ArrayList(Leaf)) native.Error!bool {
        const catalog = self.catalog;
        if (!(try self.facts.get(ty)).counted) return true;
        if (semantics.isLiveView(catalog.records, ty)) return self.leaf(leaves, offset, true);
        const layout = try catalog.layout(ty);
        switch (layout.kind) {
            .managed, .niche => return self.leaf(leaves, offset, false),
            .record, .domain => for (layout.fields) |field| {
                if (!try self.collect(field.ty, offset + field.offset, leaves)) return false;
            },
            .array => {
                if (layout.count > limit or layout.fields.len != 1) return false;
                var index: u64 = 0;
                while (index < layout.count) : (index += 1) {
                    if (!try self.collect(layout.fields[0].ty, offset + index * layout.stride, leaves)) return false;
                }
            },
            .variant => return false,
            else => {},
        }
        return true;
    }

    fn leaf(self: *Generator, leaves: *std.ArrayList(Leaf), offset: u64, hold: bool) native.Error!bool {
        if (leaves.items.len == limit) return false;
        try leaves.append(self.allocator, .{ .offset = offset, .hold = hold });
        return true;
    }

    fn admission(self: *Generator, leaves: []const Leaf, name: []const u8, size: u64, loan: bool) native.Error!void {
        if (!loan) try self.text("uintptr_t any = 0;\n");
        for (leaves, 0..) |entry, index| {
            try self.print("void *p{d} = myl_rcg_load((const unsigned char *)src + {d});\nmyl_rc_object *o{d} = myl_rcg_counted(p{d});\n", .{ index, entry.offset, index, index });
            if (!loan) try self.print("any |= myl_rcg_flags(p{d});\n", .{index});
        }
        try self.text("if (");
        if (loan) try self.text("0") else try self.text("(any & MYL_NATIVE_OBJECT_ARENA)");
        for (leaves, 0..) |entry, index| {
            try self.print(" || (o{d} && o{d}->{s} > MYL_RC_COUNT_MAX - {d})", .{ index, index, if (loan or entry.hold) "holds" else "owners", size / @sizeOf(usize) });
        }
        if (loan) try self.print(") return myl_rc_native_loan(heap, &{s}, dst, src);\n", .{name}) else try self.print(") return myl_rc_native_retain(heap, &{s}, dst, src, region);\n", .{name});
        if (loan) try self.print("MYL_RCG_CHECK(!myl_rcg_overlap(dst, src, {d}));\n", .{size}) else try self.text("MYL_RCG_CHECK(dst != src && region <= heap->region_depth);\n");
        if (loan) for (leaves, 0..) |_, index| try self.print("myl_rcg_loan_check(heap, p{d});\n", .{index});
        for (leaves, 0..) |entry, index| {
            const hold = loan or entry.hold;
            try self.print("if (o{d}) {{ ++o{d}->{s}; MYL_RC_STAT(heap, {s}); }}\n", .{ index, index, if (hold) "holds" else "owners", if (hold) "MYL_RC_STAT_HOLD_ACQUIRE" else "MYL_RC_STAT_OWNER_ACQUIRE" });
        }
    }
};
