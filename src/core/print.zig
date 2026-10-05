//! Textual Core IR (`mylang-core dump-ir`, and the unit tests' expected shapes).
//!
//! One line per block instruction: `%N = op type operands`, with constants,
//! parameters and undefined values printed inline at their use (`7:i64`,
//! `param0`, `undef`), and forwarding copies followed to their target.
const std = @import("std");
const ir = @import("ir.zig");

/// Render every function of `module`.
pub fn module(allocator: std.mem.Allocator, m: *const ir.Module) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (m.functions.items) |*f| try function(allocator, &out, m, f);
    return out.toOwnedSlice(allocator);
}

/// The spelling of a type.
pub fn typeName(allocator: std.mem.Allocator, m: *const ir.Module, ty: ir.Type) std.mem.Allocator.Error![]const u8 {
    if (!ty.isCompound()) return @tagName(ty);
    return switch (m.compound(ty)) {
        .list => |element| std.fmt.allocPrint(allocator, "list[{s}]", .{try typeName(allocator, m, element)}),
        .option => |payload| std.fmt.allocPrint(allocator, "option[{s}]", .{try typeName(allocator, m, payload)}),
    };
}

/// Append one function's listing to `out`.
pub fn function(allocator: std.mem.Allocator, out: *std.ArrayList(u8), m: *const ir.Module, f: *const ir.Function) std.mem.Allocator.Error!void {
    try out.print(allocator, "fn {s}(", .{f.name});
    for (f.signature.params, 0..) |param, i| try out.print(allocator, "{s}{s}", .{ if (i == 0) "" else ", ", try typeName(allocator, m, param) });
    try out.print(allocator, ") -> {s}{s}\n", .{ try typeName(allocator, m, f.signature.ret), if (f.signature.linkage == .extern_c) " extern" else "" });
    for (f.blocks.items, 0..) |block, b| {
        try out.print(allocator, "b{d}:", .{b});
        if (block.preds.items.len != 0) {
            try out.appendSlice(allocator, " ; preds");
            for (block.preds.items) |pred| try out.print(allocator, " b{d}", .{@backingInt(pred)});
        }
        try out.appendSlice(allocator, "\n");
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op == .copy) continue;
            try instruction(allocator, out, m, f, ref, inst);
        }
    }
}

fn operand(allocator: std.mem.Allocator, out: *std.ArrayList(u8), m: *const ir.Module, f: *const ir.Function, raw: ir.Ref) std.mem.Allocator.Error!void {
    const ref = f.resolve(raw);
    if (ref == .none) return out.appendSlice(allocator, "_");
    const inst = f.inst(ref);
    switch (inst.op) {
        .iconst => {
            const value: i64 = @bitCast(inst.data);
            try out.print(allocator, "{d}:{s}", .{ value, try typeName(allocator, m, inst.ty) });
        },
        .fconst => try out.print(allocator, "{d}:f64", .{@as(f64, @bitCast(inst.data))}),
        .param => try out.print(allocator, "param{d}", .{inst.data}),
        .undef => try out.appendSlice(allocator, "undef"),
        .str_const => try out.print(allocator, "str{d}", .{inst.data}),
        else => try out.print(allocator, "%{d}", .{ref.index()}),
    }
}

fn instruction(allocator: std.mem.Allocator, out: *std.ArrayList(u8), m: *const ir.Module, f: *const ir.Function, ref: ir.Ref, inst: ir.Inst) std.mem.Allocator.Error!void {
    try out.appendSlice(allocator, "  ");
    if (inst.ty != .void) try out.print(allocator, "%{d} = ", .{ref.index()});
    try out.appendSlice(allocator, @tagName(inst.op));
    switch (inst.op) {
        .cmp, .fcmp => try out.print(allocator, ".{s}", .{@tagName(@as(ir.Predicate, @fromBackingInt(@intCast(inst.data))))}),
        else => {},
    }
    if (inst.check != .none) try out.print(allocator, ".{s}", .{@tagName(inst.check)});
    if (inst.ty != .void) try out.print(allocator, " {s}", .{try typeName(allocator, m, inst.ty)});
    switch (inst.op) {
        .phi, .print => {
            for (f.operands(inst.data), 0..) |item, i| {
                try out.appendSlice(allocator, if (i == 0) " " else ", ");
                try operand(allocator, out, m, f, item);
            }
        },
        .call => {
            try out.print(allocator, " {s}(", .{m.functions.items[inst.a.index()].name});
            for (f.operands(inst.data), 0..) |item, i| {
                if (i != 0) try out.appendSlice(allocator, ", ");
                try operand(allocator, out, m, f, item);
            }
            try out.appendSlice(allocator, ")");
        },
        .jump => try out.print(allocator, " b{d}", .{inst.data}),
        .iconst => try out.print(allocator, " {d}", .{@as(i64, @bitCast(inst.data))}),
        .branch => {
            const targets = ir.unpackTargets(inst.data);
            try out.appendSlice(allocator, " ");
            try operand(allocator, out, m, f, inst.a);
            try out.print(allocator, ", b{d}, b{d}", .{ @backingInt(targets.then), @backingInt(targets.otherwise) });
        },
        .union_make, .union_payload => {
            try out.print(allocator, " tag{d}", .{inst.data});
            if (inst.a != .none) {
                try out.appendSlice(allocator, " ");
                try operand(allocator, out, m, f, inst.a);
            }
        },
        else => {
            if (inst.a != .none) {
                try out.appendSlice(allocator, " ");
                try operand(allocator, out, m, f, inst.a);
            }
            if (inst.b != .none) {
                try out.appendSlice(allocator, ", ");
                try operand(allocator, out, m, f, inst.b);
            }
        },
    }
    try out.appendSlice(allocator, "\n");
}
