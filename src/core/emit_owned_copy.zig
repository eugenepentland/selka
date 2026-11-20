//! Finite generated copy callbacks; container edges use the runtime worklist.
const std = @import("std");
const ir = @import("ir.zig");
const type_ids = @import("type_ids.zig");
const Out = std.ArrayList(u8);

/// Compiler-authorized independent block copy adapter names.
pub const prefix = @import("stable_names.zig").owned_copy_prefix;
/// Unsupported resource duplication or allocation stops emission.
pub const Error = error{ OutOfMemory, UnsupportedInstruction };

fn symbol(a: std.mem.Allocator, m: *const ir.Module, ids: type_ids.Table, raw: ir.Type) Error![]const u8 {
    const ty = m.storageType(raw);
    if (!m.managed(ty)) return "null";
    return std.fmt.allocPrint(a, "@myl.copy.{s}", .{ids.text(ty)});
}

fn enqueue(a: std.mem.Allocator, m: *const ir.Module, types: *std.ArrayList(ir.Type), raw: ir.Type) !void {
    const ty = m.storageType(raw);
    if (!m.managed(ty) or std.mem.indexOfScalar(ir.Type, types.items, ty) != null) return;
    try types.append(a, ty);
}

/// Emit only the managed type graph reached by actual copy adapters.
pub fn emit(a: std.mem.Allocator, m: *const ir.Module, ids: type_ids.Table, out: *Out) Error!void {
    var types: std.ArrayList(ir.Type) = .empty;
    defer types.deinit(a);
    for (m.functions.items) |f| {
        if (f.signature.linkage != .runtime_c or !std.mem.startsWith(u8, f.name, prefix)) continue;
        if (m.containsBorrow(f.signature.ret)) return error.UnsupportedInstruction;
        try enqueue(a, m, &types, f.signature.ret);
    }
    if (types.items.len == 0) return;
    try out.appendSlice(a, "declare ptr @myl_core_values_copy_generated(ptr, ptr) nounwind\n" ++
        "declare void @myl_core_owned_copy_leaf(ptr, ptr) nounwind\n" ++
        "declare void @myl_core_owned_copy_items(ptr, ptr, ptr, ptr, i64, i1 zeroext) nounwind\n" ++
        "declare void @myl_core_owned_copy_array(ptr, ptr, ptr, ptr, i64, i64) nounwind\n" ++
        "declare void @myl_core_owned_copy_dictionary(ptr, ptr, ptr, ptr, ptr) nounwind\n");
    var index: usize = 0;
    while (index < types.items.len) : (index += 1) {
        const ty = types.items[index];
        try definition(a, m, ids, out, ty);
        if (!ty.isCompound()) continue;
        switch (m.compound(ty)) {
            .record, .@"union" => |fields| for (fields) |field| try enqueue(a, m, &types, field),
            .list_view => |element| try enqueue(a, m, &types, element),
            .list, .box => |element| try enqueue(a, m, &types, element),
            .array => |array| try enqueue(a, m, &types, array.elem),
            .dict => |dict| {
                try enqueue(a, m, &types, dict.key);
                try enqueue(a, m, &types, dict.value);
            },
            .@"fn" => {},
            .borrowed => return error.UnsupportedInstruction,
        }
    }
}

const Scope = struct { a: std.mem.Allocator, m: *const ir.Module, ids: type_ids.Table };

fn child(scope: Scope, out: *Out, raw: ir.Type, offset: u32, index: usize) !void {
    const a = scope.a;
    const m = scope.m;
    const ids = scope.ids;
    const ty = m.storageType(raw);
    if (!m.managed(ty)) return;
    try out.print(a, "  %source.{d} = getelementptr inbounds i8, ptr %source, i64 {d}\n" ++
        "  %target.{d} = getelementptr inbounds i8, ptr %target, i64 {d}\n" ++
        "  call void {s}(ptr %work, ptr %source.{d}, ptr %target.{d})\n", .{ index, offset, index, offset, try symbol(a, m, ids, ty), index, index });
}

fn definition(a: std.mem.Allocator, m: *const ir.Module, ids: type_ids.Table, out: *Out, ty: ir.Type) Error!void {
    try out.print(a, "define internal void {s}(ptr %work, ptr %source, ptr %target) nounwind {{\nentry:\n", .{try symbol(a, m, ids, ty)});
    if (ty == .str or ty == .bytes or ty == .byte_buffer) {
        try out.appendSlice(a, "  call void @myl_core_owned_copy_leaf(ptr %source, ptr %target)\n");
    } else if (ty.isCompound()) switch (m.compound(ty)) {
        // A view borrows; it has no owned copy and no storable layout.
        .list_view => return error.UnsupportedInstruction,
        .list, .box => |element| {
            const copy = try symbol(a, m, ids, element);
            try out.print(a, "  call void @myl_core_owned_copy_items(ptr %work, ptr %source, ptr %target, ptr {s}, i64 {d}, i1 zeroext {d})\n", .{ copy, m.size(element), @intFromBool(m.kind(ty) == .box) });
        },
        .record => |fields| for (fields, 0..) |field, index| try child(.{ .a = a, .m = m, .ids = ids }, out, field, m.fieldOffset(ty, index), index),
        .array => |array| try out.print(a, "  call void @myl_core_owned_copy_array(ptr %work, ptr %source, ptr %target, ptr {s}, i64 {d}, i64 {d})\n", .{ try symbol(a, m, ids, array.elem), array.n, m.size(array.elem) }),
        .dict => |dict| try out.print(a, "  call void @myl_core_owned_copy_dictionary(ptr %work, ptr %source, ptr %target, ptr {s}, ptr {s})\n", .{ try symbol(a, m, ids, dict.key), try symbol(a, m, ids, dict.value) }),
        .@"union" => {
            try unionBody(a, m, ids, out, ty);
            return;
        },
        .@"fn" => return error.UnsupportedInstruction,
        .borrowed => return error.UnsupportedInstruction,
    } else return error.UnsupportedInstruction;
    try out.appendSlice(a, "  ret void\n}\n");
}

fn unionBody(a: std.mem.Allocator, m: *const ir.Module, ids: type_ids.Table, out: *Out, ty: ir.Type) Error!void {
    const cases = m.compound(ty).@"union";
    const layout = m.unionLayout(ty);
    if (layout.form == .niche) {
        try out.appendSlice(a, "  %payload = load ptr, ptr %source, align 8\n  %empty = icmp eq ptr %payload, null\n  br i1 %empty, label %done, label %value\nvalue:\n");
        try child(.{ .a = a, .m = m, .ids = ids }, out, cases[1 - layout.empty_case], 0, 0);
        try out.appendSlice(a, "  br label %done\ndone:\n  ret void\n}\n");
        return;
    }
    try out.appendSlice(a, "  %tag = load i64, ptr %source, align 8\n  switch i64 %tag, label %invalid [");
    for (cases, 0..) |_, index| try out.print(a, " i64 {d}, label %case.{d}", .{ index, index });
    try out.appendSlice(a, " ]\ninvalid:\n  unreachable\n");
    for (cases, 0..) |payload, index| {
        try out.print(a, "case.{d}:\n", .{index});
        try child(.{ .a = a, .m = m, .ids = ids }, out, payload, 8, index);
        try out.appendSlice(a, "  ret void\n");
    }
    try out.appendSlice(a, "}\n");
}
