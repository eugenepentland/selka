//! Type graph descriptors for iterative recursive equality and hashing.
const std = @import("std");
const ir = @import("ir.zig");
const emit_render = @import("emit_render.zig");
const equality = @import("build_equality.zig");
const type_ids = @import("type_ids.zig");
const Out = std.ArrayList(u8);
/// Compiler-generated independent block copy adapters terminate recursive type expansion.
pub const copy_prefix = @import("emit_owned_copy.zig").prefix;
/// Allocation or an unsupported representation stops this stage.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Whether a key needs the structural worklist instead of the frozen scalar helpers.
pub fn dynamic(module: ir.Module, raw: ir.Type) bool {
    const ty = module.storageType(raw);
    if (ty == .f64 or ty == .f32) return true;
    return switch (module.kind(ty) orelse return false) {
        .box, .list, .dict, .list_view => true,
        .record => blk: {
            for (module.compound(ty).record) |field| if (dynamic(module, field)) break :blk true;
            break :blk false;
        },
        .@"union" => blk: {
            for (module.compound(ty).@"union") |field| if (dynamic(module, field)) break :blk true;
            break :blk false;
        },
        .array => dynamic(module, module.compound(ty).array.elem),
        .@"fn" => false,
        .borrowed => false,
    };
}

/// Replace a typed recursive adapter declaration with its LLVM definition.
pub fn adapter(a: std.mem.Allocator, out: *Out, ids: type_ids.Table, function: *const ir.Function) Error!bool {
    return adapterNamed(a, out, ids, function, .{ .symbol = function.name, .linkage = "internal" });
}

/// Whether compiler-authorized lowering supplied a copy or rendering adapter. (An equality adapter is a borrowed-equality marker,
/// `build_equality.prefix`, which the call sites render; there is no adapter function named by a type's ordinal.)
pub fn generated(function: *const ir.Function) bool {
    if (function.signature.linkage != .runtime_c) return false;
    return std.mem.startsWith(u8, function.name, copy_prefix) or std.mem.startsWith(u8, function.name, "myl_core_show_");
}

/// Emit an authorized adapter with the unit's stable symbol and linkage.
pub fn adapterNamed(a: std.mem.Allocator, out: *Out, ids: type_ids.Table, function: *const ir.Function, names: emit_render.AdapterNames) Error!bool {
    if (try emit_render.adapterNamed(a, out, function, names)) return true;
    if (function.signature.linkage != .runtime_c) return false;
    if (!std.mem.startsWith(u8, function.name, copy_prefix)) return false;
    // The name holds the copied type's key; the type is the helper's result.
    try out.print(a, "define {s} fastcc ptr @{s}(ptr %source) nounwind {{\nentry:\n" ++
        "  %result = call ptr @myl_core_values_copy_generated(ptr @myl.copy.{s}, ptr %source)\n  ret ptr %result\n}}\n", .{ names.linkage, names.symbol, ids.text(function.signature.ret) });
    return true;
}

/// Per-key wrappers invoke the same explicit worklists as source equality.
pub fn key(comptime Context: type, c: Context, out: *Out, ty: ir.Type, symbol: []const u8) Error!void {
    const id = c.state.local.ids.text(ty);
    try out.print(c.a(), "define internal i64 {s}.hash(ptr %key) nounwind {{\nentry:\n" ++
        "  %hash = call i64 @myl_core_values_hash(ptr @myl.value.{s}, ptr %key)\n  ret i64 %hash\n}}\n" ++
        "define internal zeroext i1 {s}.same(ptr %left, ptr %right) nounwind {{\nentry:\n" ++
        "  %same = call zeroext i1 @myl_core_values_equal(ptr @myl.value.{s}, ptr %left, ptr %right)\n  ret i1 %same\n}}\n", .{ symbol, id, symbol, id });
}

fn needed(m: *const ir.Module) bool {
    for (m.functions.items) |*f| if (std.mem.startsWith(u8, f.name, equality.prefix)) return true;
    for (m.functions.items) |f| {
        if (f.signature.linkage == .runtime_c and std.mem.startsWith(u8, f.name, "myl_core_show_")) return true;
    }
    for (m.compounds.items) |shape| if (shape == .dict and dynamic(m.*, shape.dict.key)) return true;
    return false;
}

/// Emit the finite descriptor graph without recursively walking boxed type cycles.
pub fn descriptors(a: std.mem.Allocator, m: *const ir.Module, out: *Out) Error!void {
    return descriptorsWith(a, m, type_ids.Table.build(a, m) catch return error.UnsupportedInstruction, out);
}

/// `descriptors` with the type ids a caller has already computed (`type_ids.Table`), named by identity and never by ordinal.
pub fn descriptorsWith(a: std.mem.Allocator, m: *const ir.Module, ids: type_ids.Table, out: *Out) Error!void {
    try @import("emit_owned_copy.zig").emit(a, m, ids, out);
    if (!needed(m)) return;
    const ordinary = try equality.descriptorTypes(a, m);
    defer a.free(ordinary);
    try validateRoots(m, ordinary);
    try out.appendSlice(a, "%myl.value = type { i32, i32, i32, i32, ptr, ptr, ptr }\n" ++
        "declare zeroext i1 @myl_core_values_equal(ptr, ptr, ptr) nounwind\n" ++
        "declare i64 @myl_core_values_hash(ptr, ptr) nounwind\n" ++
        "declare ptr @myl_core_values_render(ptr, ptr) nounwind\n");
    for (0..ir.Type.first_compound) |index| {
        const ty: ir.Type = @fromBackingInt(@as(u32, @intCast(index)));
        if (!m.isView(ty)) try descriptor(a, m, out, ids, ty);
    }
    for (ordinary, 0..) |supported, index| {
        if (supported) try descriptor(a, m, out, ids, @fromBackingInt(ir.Type.first_compound + @as(u32, @intCast(index))));
    }
    for ([_]ir.Type{ .byte_buffer, .capability, .resource }) |ty| try descriptor(a, m, out, ids, ty);
    try emit_render.descriptors(a, m, out);
}

fn requireDescriptor(m: *const ir.Module, ordinary: []const bool, ty: ir.Type) Error!void {
    if (!m.valid(ty) or m.isView(ty)) return error.UnsupportedInstruction;
    if (ty.isCompound() and !ordinary[@backingInt(ty) - ir.Type.first_compound]) return error.UnsupportedInstruction;
}

fn validateRoots(m: *const ir.Module, ordinary: []const bool) Error!void {
    for (m.functions.items) |*function| {
        if (try equality.declaration(m, function)) try requireDescriptor(m, ordinary, function.signature.params[0]);
    }
    for (m.compounds.items) |shape| if (shape == .dict and dynamic(m.*, shape.dict.key)) {
        try requireDescriptor(m, ordinary, shape.dict.key);
    };
    // Rendering references its independently validated source-aware @myl.render
    // graph, never this physical @myl.value catalog.
}

fn descriptor(a: std.mem.Allocator, m: *const ir.Module, out: *Out, ids: type_ids.Table, ty: ir.Type) Error!void {
    if (!m.valid(ty) or m.isView(ty)) return error.UnsupportedInstruction;
    const physical = m.storageType(ty);
    var kind: u32 = 0;
    var count: u32 = 0;
    var aux: u32 = 0;
    var children: []const ir.Type = &.{};
    var single: [2]ir.Type = undefined;
    if (physical.integer() != null or physical == .bool or physical == .cap) {
        kind = 1;
        aux = if (physical == .bool) 1 else if (physical.integer()) |info| (if (info.signed) @as(u32, 2) else 0) else 0;
    } else if (physical == .f64) {
        kind = 2;
    } else if (physical == .f32) {
        kind = 13;
    } else if (physical == .str or physical == .bytes or physical == .byte_buffer) {
        kind = 3;
        aux = if (physical == .str) 0 else 1;
    } else if (physical == .capability or physical == .resource) {
        kind = 10;
    } else if (physical.isCompound()) switch (m.compound(physical)) {
        .list_view => return error.UnsupportedInstruction,
        .record => |fields| {
            kind = 4;
            children = fields;
            count = @intCast(fields.len);
        },
        .@"union" => |cases| {
            kind = 5;
            children = cases;
            count = @intCast(cases.len);
            const layout = m.unionLayout(ty);
            aux = if (layout.form == .niche) layout.empty_case + 1 else 0;
        },
        .box => |child| {
            kind = 6;
            single[0] = child;
            children = single[0..1];
        },
        .list => |child| {
            kind = 7;
            single[0] = child;
            children = single[0..1];
        },
        .array => |shape| {
            kind = 8;
            count = shape.n;
            single[0] = shape.elem;
            children = single[0..1];
        },
        .dict => |shape| {
            kind = 9;
            single = .{ shape.key, shape.value };
            children = &single;
        },
        .@"fn" => {
            kind = 10;
            aux = 1; // Function pointers carry no ownership.
        },
        .borrowed => return error.UnsupportedInstruction,
    };
    const number = ids.text(ty);
    if (children.len != 0) {
        try out.print(a, "@myl.value.children.{s} = private constant [{d} x ptr] [", .{ number, children.len });
        for (children, 0..) |child, i| try out.print(a, "{s}ptr @myl.value.{s}", .{ if (i == 0) "" else ", ", ids.text(child) });
        try out.appendSlice(a, "]\n");
        if (kind == 4) {
            try out.print(a, "@myl.value.offsets.{s} = private constant [{d} x i32] [", .{ number, children.len });
            for (children, 0..) |_, i| try out.print(a, "{s}i32 {d}", .{ if (i == 0) "" else ", ", m.fieldOffset(ty, i) });
            try out.appendSlice(a, "]\n");
        }
    }
    try out.print(a, "@myl.value.{s} = private constant %myl.value {{ i32 {d}, i32 {d}, i32 {d}, i32 {d}, ", .{ number, kind, m.size(ty), count, aux });
    if (children.len == 0) try out.appendSlice(a, "ptr null, ") else try out.print(a, "ptr @myl.value.children.{s}, ", .{number});
    if (kind == 4 and children.len != 0) try out.print(a, "ptr @myl.value.offsets.{s}", .{number}) else try out.appendSlice(a, "ptr null");
    // Rendering uses its checked-source graph, never names inferred from strings.
    try out.appendSlice(a, ", ptr null }\n");
}
