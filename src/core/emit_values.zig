//! Type graph descriptors for iterative recursive equality and hashing.
const std = @import("std");
const ir = @import("ir.zig");
const emit_render = @import("emit_render.zig");
const Out = std.ArrayList(u8);
/// The name prefix of a structural equality adapter: `myl_core_equal_<IR type index>`.
/// Compiler-generated independent block copy adapters terminate recursive type expansion.
pub const copy_prefix = "myl_core_owned_copy_";
pub const equal_prefix = "myl_core_equal_";
/// Allocation or an unsupported representation stops this stage.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// Whether a key needs the structural worklist instead of the frozen scalar helpers.
pub fn dynamic(module: ir.Module, ty: ir.Type) bool {
    if (ty == .f64) return true;
    return switch (module.kind(ty) orelse return false) {
        .box, .list, .dict => true,
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
    };
}

/// Replace a typed recursive adapter declaration with its LLVM definition.
pub fn adapter(a: std.mem.Allocator, out: *Out, function: *const ir.Function) Error!bool {
    return adapterNamed(a, out, function, .{ .symbol = function.name, .linkage = "internal" });
}

/// Whether compiler-authorized lowering supplied an equality or rendering adapter.
pub fn generated(function: *const ir.Function) bool {
    if (function.signature.linkage != .runtime_c) return false;
    return std.mem.startsWith(u8, function.name, copy_prefix) or std.mem.startsWith(u8, function.name, equal_prefix) or std.mem.startsWith(u8, function.name, "myl_core_show_");
}

/// Emit an authorized adapter with the unit's stable symbol and linkage.
pub fn adapterNamed(a: std.mem.Allocator, out: *Out, function: *const ir.Function, names: emit_render.AdapterNames) Error!bool {
    if (try emit_render.adapterNamed(a, out, function, names)) return true;
    if (function.signature.linkage != .runtime_c) return false;
    if (std.mem.startsWith(u8, function.name, copy_prefix)) {
        const number = function.name[copy_prefix.len..];
        try out.print(a, "define {s} fastcc ptr @{s}(ptr %source) nounwind {{\nentry:\n" ++
            "  %result = call ptr @myl_core_values_copy_box(ptr @myl.value.{s}, ptr %source)\n  ret ptr %result\n}}\n", .{ names.linkage, names.symbol, number });
        return true;
    }
    const prefix = equal_prefix;
    if (!std.mem.startsWith(u8, function.name, prefix)) return false;
    const number = function.name[prefix.len..];
    try out.print(a, "define {s} fastcc zeroext i1 @{s}(ptr %left, ptr %right) nounwind {{\nentry:\n" ++
        "  %l = getelementptr inbounds i8, ptr %left, i64 32\n  %r = getelementptr inbounds i8, ptr %right, i64 32\n" ++
        "  %same = call zeroext i1 @myl_core_values_equal(ptr @myl.value.{s}, ptr %l, ptr %r)\n  ret i1 %same\n}}\n", .{ names.linkage, names.symbol, number });
    return true;
}

/// Per-key wrappers invoke the same explicit worklists as source equality.
pub fn key(comptime Context: type, c: Context, out: *Out, ty: ir.Type, symbol: []const u8) Error!void {
    try out.print(c.a(), "define internal i64 {s}.hash(ptr %key) nounwind {{\nentry:\n" ++
        "  %hash = call i64 @myl_core_values_hash(ptr @myl.value.{d}, ptr %key)\n  ret i64 %hash\n}}\n" ++
        "define internal zeroext i1 {s}.same(ptr %left, ptr %right) nounwind {{\nentry:\n" ++
        "  %same = call zeroext i1 @myl_core_values_equal(ptr @myl.value.{d}, ptr %left, ptr %right)\n  ret i1 %same\n}}\n", .{ symbol, @backingInt(ty), symbol, @backingInt(ty) });
}

fn needed(m: *const ir.Module) bool {
    for (m.functions.items) |f| {
        if (f.signature.linkage == .runtime_c and std.mem.startsWith(u8, f.name, copy_prefix)) return true;
        if (f.signature.linkage == .runtime_c and std.mem.startsWith(u8, f.name, equal_prefix)) return true;
        if (f.signature.linkage == .runtime_c and std.mem.startsWith(u8, f.name, "myl_core_show_")) return true;
    }
    for (m.compounds.items) |shape| if (shape == .dict and dynamic(m.*, shape.dict.key)) return true;
    return false;
}

/// Emit the finite descriptor graph without recursively walking boxed type cycles.
pub fn descriptors(a: std.mem.Allocator, m: *const ir.Module, out: *Out) Error!void {
    if (!needed(m)) return;
    try out.appendSlice(a, "%myl.value = type { i32, i32, i32, i32, ptr, ptr, ptr }\n" ++
        "declare zeroext i1 @myl_core_values_equal(ptr, ptr, ptr) nounwind\n" ++
        "declare i64 @myl_core_values_hash(ptr, ptr) nounwind\n" ++
        "declare ptr @myl_core_values_render(ptr, ptr) nounwind\n" ++
        "declare ptr @myl_core_values_copy_box(ptr, ptr) nounwind\n");
    for (0..ir.Type.first_compound) |index| try descriptor(a, m, out, @fromBackingInt(@as(u32, @intCast(index))));
    for (0..m.compounds.items.len) |index| try descriptor(a, m, out, @fromBackingInt(ir.Type.first_compound + @as(u32, @intCast(index))));
    for ([_]ir.Type{ .byte_buffer, .capability, .resource }) |ty| try descriptor(a, m, out, ty);
    try emit_render.descriptors(a, m, out);
}

fn descriptor(a: std.mem.Allocator, m: *const ir.Module, out: *Out, ty: ir.Type) Error!void {
    var kind: u32 = 0;
    var count: u32 = 0;
    var aux: u32 = 0;
    var children: []const ir.Type = &.{};
    var single: [2]ir.Type = undefined;
    if (ty.integer() != null or ty == .bool or ty == .cap) {
        kind = 1;
        aux = if (ty == .bool) 1 else if (ty.integer()) |info| (if (info.signed) @as(u32, 2) else 0) else 0;
    } else if (ty == .f64) {
        kind = 2;
    } else if (ty == .str or ty == .bytes or ty == .byte_buffer) {
        kind = 3;
        aux = if (ty == .str) 0 else 1;
    } else if (ty == .capability or ty == .resource) {
        kind = 10;
    } else if (ty.isCompound()) switch (m.compound(ty)) {
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
    };
    const number = @backingInt(ty);
    if (children.len != 0) {
        try out.print(a, "@myl.value.children.{d} = private constant [{d} x ptr] [", .{ number, children.len });
        for (children, 0..) |child, i| try out.print(a, "{s}ptr @myl.value.{d}", .{ if (i == 0) "" else ", ", @backingInt(child) });
        try out.appendSlice(a, "]\n");
        if (kind == 4) {
            try out.print(a, "@myl.value.offsets.{d} = private constant [{d} x i32] [", .{ number, children.len });
            for (children, 0..) |_, i| try out.print(a, "{s}i32 {d}", .{ if (i == 0) "" else ", ", m.fieldOffset(ty, i) });
            try out.appendSlice(a, "]\n");
        }
    }
    try out.print(a, "@myl.value.{d} = private constant %myl.value {{ i32 {d}, i32 {d}, i32 {d}, i32 {d}, ", .{ number, kind, if (ty == .str_view) 0 else m.size(ty), count, aux });
    if (children.len == 0) try out.appendSlice(a, "ptr null, ") else try out.print(a, "ptr @myl.value.children.{d}, ", .{number});
    if (kind == 4 and children.len != 0) try out.print(a, "ptr @myl.value.offsets.{d}", .{number}) else try out.appendSlice(a, "ptr null");
    // Rendering uses its checked-source graph, never names inferred from strings.
    try out.appendSlice(a, ", ptr null }\n");
}
