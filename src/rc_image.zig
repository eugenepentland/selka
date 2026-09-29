//! Canonical per-shape startup recipes, independent of catalog ordinals.
const std = @import("std");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const descriptors = @import("native_descriptors.zig");
const semantics = @import("value_semantics.zig");
const always = std.math.maxInt(u32);

/// A semantic type or its separately allocated body, with its physical layout.
pub const Target = struct { ty: typed.Type, name: []const u8, layout: native.Layout, unique_body: bool = false };
const Depth = struct { owners: u64 = 0, inline_drop: u64 = 1 };

/// Memoized graph facts keyed by compiler types; emitted identity stays symbolic.
pub const Analyzer = struct {
    catalog: *native.Catalog,
    depths: []?Depth,

    /// Reserve one cache slot for each physical catalog type.
    pub fn init(a: std.mem.Allocator, catalog: *native.Catalog) native.Error!Analyzer {
        const depths = try a.alloc(?Depth, typed.Type.record_base + catalog.records.len);
        @memset(depths, null);
        return .{ .catalog = catalog, .depths = depths };
    }

    /// Release the temporary graph-fact cache.
    pub fn deinit(self: *Analyzer, a: std.mem.Allocator) void {
        a.free(self.depths);
    }

    fn get(self: *Analyzer, ty: typed.Type) native.Error!Depth {
        const index = @backingInt(ty);
        if (self.depths[index]) |known| return known;
        const result = try self.of(ty, try self.catalog.layout(ty));
        self.depths[index] = result;
        return result;
    }

    fn of(self: *Analyzer, ty: typed.Type, layout: native.Layout) native.Error!Depth {
        if (pointer(self.catalog, ty, layout)) return .{ .owners = 1 };
        var result: Depth = .{};
        if (layout.kind != .record and layout.kind != .domain and layout.kind != .variant and layout.kind != .array) return result;
        if (layout.kind == .array and layout.count == 0) return result;
        for (layout.fields) |field| {
            const child = try self.get(field.ty);
            result.owners = @max(result.owners, child.owners);
            result.inline_drop = @max(result.inline_drop, child.inline_drop + 1);
        }
        if (result.owners != 0) result.owners += 1;
        return result;
    }
};
const Leaf = struct { offset: u64, word: u64 = always, tag: u64 = 0 };
const Walk = struct {
    leaves: [16]Leaf = undefined,
    count: usize = 0,
    inspected: usize = 0,
    loanable: bool = true,
    conditional: bool = false,
};
const Flat = struct {
    count: usize = 17,
    loanable: bool = false,
    conditional: bool = false,
    word: u64 = 0,
    masks: struct { all: u16 = 0, unconditional: u16 = 0, arms: [32]u16 = @splat(0) } = .{},
    offsets: [16]u16 = @splat(0),
};

/// Emit immutable image facts alongside the original ownership shape block.
pub fn emit(a: std.mem.Allocator, writer: *std.Io.Writer, analyzer: *Analyzer, target: Target) native.Error!void {
    const catalog = analyzer.catalog;
    const depths = try analyzer.of(target.ty, target.layout);
    writer.writeAll("/* mylang-rc-image-block-v1 */\n") catch return error.OutOfMemory;
    try fields(a, writer, catalog, target);
    writer.print("const myl_rc_shape_entry {s}_rc_image_entry = {{.source=&{s}_rc,.shape=", .{ target.name, target.name }) catch return error.OutOfMemory;
    try shape(a, writer, catalog, target, depths.owners);
    writer.print(",.depth={d},.inline_depth={d}}};\n#define {s}_RC_IMAGE_DEPTH {d}\n", .{ depths.owners, depths.inline_drop, target.name, depths.inline_drop }) catch return error.OutOfMemory;
    const flat = try plan(analyzer, target);
    writer.print("#define {s}_RC_IMAGE_BINDING {{.descriptor={{.type=&{s},.shape=&{s}_rc_image_entry.shape,.finalize={s}}},.flat=", .{
        target.name, target.name, target.name, if (target.unique_body) "myl_rc_finalize_unique" else "NULL",
    }) catch return error.OutOfMemory;
    try writeFlat(writer, target.layout.size, flat);
    writer.writeAll("}\n") catch return error.OutOfMemory;
}

fn pointer(catalog: *const native.Catalog, ty: typed.Type, layout: native.Layout) bool {
    return semantics.isLiveView(catalog.records, ty) or layout.kind == .managed or layout.kind == .niche;
}

fn fields(a: std.mem.Allocator, writer: *std.Io.Writer, catalog: *native.Catalog, target: Target) native.Error!void {
    const layout = target.layout;
    if (pointer(catalog, target.ty, layout) or layout.fields.len == 0) return;
    if (layout.kind != .record and layout.kind != .domain and layout.kind != .variant) return;
    writer.print("static const myl_rc_field {s}_rc_image_fields[] = {{\n", .{target.name}) catch return error.OutOfMemory;
    for (layout.fields) |field| writer.print(" {{.offset={d},.shape=&{s}_rc_image_entry.shape,.tag={d}}},\n", .{ field.offset, try descriptors.symbol(a, catalog, field.ty), field.tag orelse 0 }) catch return error.OutOfMemory;
    writer.writeAll("};\n") catch return error.OutOfMemory;
}

fn shape(a: std.mem.Allocator, writer: *std.Io.Writer, catalog: *native.Catalog, target: Target, owners: u64) native.Error!void {
    const layout = target.layout;
    const hold = semantics.isLiveView(catalog.records, target.ty);
    const kind = if (owners == 0) "NONE" else if (hold) "HOLD_POINTER" else switch (layout.kind) {
        .managed, .niche => "POINTER",
        .record, .domain => "RECORD",
        .array => "ARRAY",
        .variant => "VARIANT",
        else => "NONE",
    };
    writer.print("{{.size={d},.kind=MYL_RC_SHAPE_{s}", .{ layout.size, kind }) catch return error.OutOfMemory;
    if (!pointer(catalog, target.ty, layout)) switch (layout.kind) {
        .record, .domain, .variant => {
            const member = if (layout.kind == .variant) "variant" else "record";
            const list = if (layout.fields.len == 0) "NULL" else try std.fmt.allocPrint(a, "{s}_rc_image_fields", .{target.name});
            writer.print(",.as.{s}={{.fields={s},.count={d}", .{ member, list, layout.fields.len }) catch return error.OutOfMemory;
            if (layout.kind == .variant) writer.writeAll(",.tag_offset=0") catch return error.OutOfMemory;
            writer.writeAll("}") catch return error.OutOfMemory;
        },
        .array => {
            if (layout.fields.len != 1) return error.InvalidType;
            writer.print(",.as.array={{.element=&{s}_rc_image_entry.shape,.count={d},.stride={d}}}", .{ try descriptors.symbol(a, catalog, layout.fields[0].ty), layout.count, layout.stride }) catch return error.OutOfMemory;
        },
        else => {},
    };
    writer.writeAll("}") catch return error.OutOfMemory;
}

fn plan(analyzer: *Analyzer, target: Target) native.Error!Flat {
    var flat: Flat = .{};
    if (target.unique_body) return flat;
    var walk: Walk = .{};
    if (!try visit(analyzer, &walk, target, .{ .offset = 0 }, 1)) return flat;
    const leaves = walk.leaves[0..walk.count];
    if (!disjoint(leaves)) return flat;
    var word: u64 = always;
    var unconditional: u16 = 0;
    for (leaves, 0..) |leaf, index| {
        if (leaf.word == always) {
            unconditional |= @as(u16, 1) << @intCast(index);
            continue;
        }
        if (word == always) word = leaf.word;
        if (leaf.word != word or leaf.tag >= 32) return flat;
    }
    // Mirror the runtime's ordered mask publication, including generic plans
    // that keep the already-validated prefix of an out-of-range offset array.
    for (leaves, 0..) |leaf, index| {
        if (leaf.offset > std.math.maxInt(u16) - 8) return flat;
        flat.offsets[index] = @intCast(leaf.offset);
    }
    flat.count = walk.count;
    flat.loanable = walk.loanable;
    flat.conditional = walk.conditional;
    flat.word = word;
    flat.masks.all = @intCast((@as(u32, 1) << @intCast(walk.count)) - 1);
    flat.masks.unconditional = unconditional;
    flat.masks.arms = @splat(unconditional);
    for (leaves, 0..) |leaf, index| if (leaf.word != always) {
        flat.masks.arms[@intCast(leaf.tag)] |= @as(u16, 1) << @intCast(index);
    };
    return flat;
}

fn inspect(walk: *Walk, level: usize) bool {
    if (level > 8) walk.loanable = false;
    walk.inspected += 1;
    return walk.inspected <= 192;
}

fn visit(analyzer: *Analyzer, walk: *Walk, target: Target, condition: Leaf, level: usize) native.Error!bool {
    if (!inspect(walk, level)) return false;
    const catalog = analyzer.catalog;
    const layout = target.layout;
    const owners = (try analyzer.of(target.ty, layout)).owners;
    // Live views have a native RECORD representation but one H edge. Flat
    // ownership recipes support O only, so retain their generic visitor.
    if (semantics.isLiveView(catalog.records, target.ty)) return false;
    if (@import("numeric_surface.zig").isFloat(target.ty, catalog.records)) return owners == 0;
    switch (layout.kind) {
        .scalar, .handle, .pool_handle, .callable => return owners == 0,
        .managed, .niche => {
            var ty = target.ty;
            if (layout.kind == .niche) ty = layout.fields[0].ty;
            if (ty.isAggregate() and catalog.records[ty.recordIndex()].collection.box) walk.loanable = false;
            if (walk.count == walk.leaves.len or condition.offset > std.math.maxInt(u32) - 8) return false;
            walk.leaves[walk.count] = condition;
            walk.count += 1;
            return true;
        },
        .record, .domain, .variant, .array => {},
        else => return false,
    }
    const count = if (layout.kind == .array) layout.count else layout.fields.len;
    for (0..count) |index| {
        const field = layout.fields[if (layout.kind == .array) 0 else index];
        const child_layout = try catalog.layout(field.ty);
        var child: Leaf = condition;
        if (layout.kind == .variant and owners != 0) {
            if (condition.word != always or condition.offset > std.math.maxInt(u32) - 4) return false;
            child.word = condition.offset;
            child.tag = field.tag orelse 0;
            walk.conditional = true;
        }
        const offset = if (layout.kind == .array) index * layout.stride else field.offset;
        if (level == 16 or offset > layout.size or child_layout.size > layout.size - offset) return false;
        child.offset += offset;
        if (!try visit(analyzer, walk, .{ .ty = field.ty, .name = "", .layout = child_layout }, child, level + 1)) return false;
        if (!inspect(walk, level)) return false;
    }
    return true;
}

fn overlap(a: u64, a_size: u64, b: u64, b_size: u64) bool {
    return if (a < b) b - a < a_size else a - b < b_size;
}

fn disjoint(leaves: []const Leaf) bool {
    for (leaves, 0..) |a, i| for (leaves, 0..) |b, j| {
        const coexist = a.word == always or b.word == always or a.word != b.word or a.tag == b.tag;
        if (i < j and coexist and overlap(a.offset, 8, b.offset, 8)) return false;
        if (b.word != always and overlap(a.offset, 8, b.word, 4)) return false;
    };
    return true;
}

fn writeFlat(writer: *std.Io.Writer, size: u64, flat: Flat) native.Error!void {
    writer.print("{{.count={d},.loanable={d},.conditional={d},.arm_offset={d},.size={d},.all={d},.always={d},.arms={{", .{
        flat.count, @intFromBool(flat.loanable), @intFromBool(flat.conditional), flat.word, size, flat.masks.all, flat.masks.unconditional,
    }) catch return error.OutOfMemory;
    for (flat.masks.arms) |mask| writer.print("{d},", .{mask}) catch return error.OutOfMemory;
    writer.writeAll("},.offsets={") catch return error.OutOfMemory;
    for (flat.offsets) |offset| writer.print("{d},", .{offset}) catch return error.OutOfMemory;
    writer.writeAll("}}") catch return error.OutOfMemory;
}
