//! Decode temporary character strings once when every use needs only their scalar.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");

/// Preserve the original checked read; rewrite only comparisons and character appends.
pub fn run(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    var changed: u32 = 0;
    const original_len = f.insts.items.len;
    for (0..original_len) |index| {
        const character = f.insts.items[index];
        const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(index)));
        if (character.op != .str_char or !eligible(module, f, ref, character)) continue;
        try rewrite(arena, module, f, ref, character);
        changed += 1;
    }
    return changed;
}

fn eligible(module: *const ir.Module, f: *const ir.Function, ref: ir.Ref, character: ir.Inst) bool {
    var found = false;
    for (f.insts.items) |inst| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |index| {
            if (f.resolve(operands.get(index)) != ref) continue;
            if (!appendUse(f, inst, ref, character) and comparison(module, f, inst, ref) == null) return false;
            found = true;
        }
    }
    return found;
}

fn appendUse(f: *const ir.Function, inst: ir.Inst, ref: ir.Ref, character: ir.Inst) bool {
    return inst.op == .str_append and f.resolve(inst.b) == ref and
        f.resolve(inst.a) != ref and f.resolve(inst.a) != f.resolve(character.a);
}

fn comparison(module: *const ir.Module, f: *const ir.Function, inst: ir.Inst, ref: ir.Ref) ?u32 {
    if (inst.op != .call or inst.ty != .bool or inst.a.index() >= module.functions.items.len) return null;
    const callee = module.functions.items[inst.a.index()];
    const signature = callee.signature;
    if (signature.linkage != .runtime_c or signature.ret != .bool) return null;
    if (signature.owned != 0 or signature.views != 0) return null;
    if (!std.mem.eql(ir.Type, signature.params, &.{ .str, .str }) or !std.mem.eql(u8, callee.name, flags.str_eq_symbol)) return null;
    const args = f.operands(inst.data);
    if (args.len != 2) return null;
    const other = if (f.resolve(args[0]) == ref) args[1] else if (f.resolve(args[1]) == ref) args[0] else return null;
    if (other == .none) return null;
    const literal = f.inst(f.resolve(other));
    if (literal.op != .str_const or literal.ty != .str or literal.data >= module.strings.items.len) return null;
    const bytes = module.strings.items[@intCast(literal.data)];
    if (bytes.len == 0 or bytes.len > 4) return null;
    const width = std.unicode.utf8ByteSequenceLength(bytes[0]) catch return null;
    if (width != bytes.len) return null;
    return std.unicode.utf8Decode(bytes) catch null;
}

fn rewrite(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, ref: ir.Ref, character: ir.Inst) std.mem.Allocator.Error!void {
    const original_len = f.insts.items.len;
    // str_char emits its located bounds check even when its IR check is absent.
    f.insts.items[ref.index()] = .{ .op = .str_code, .ty = .u32, .a = character.a, .b = character.b, .check = .exact, .span = character.span };
    for (f.insts.items) |*inst| {
        if (inst.op == .copy and f.resolve(inst.a) == ref) inst.ty = .u32;
    }
    for (0..original_len) |index| {
        const inst = f.insts.items[index];
        if (appendUse(f, inst, ref, character)) {
            const extra: u32 = @intCast(f.extra.items.len);
            try f.extra.append(arena, character.b);
            f.insts.items[index] = .{ .op = .str_append_char, .ty = .str, .a = inst.a, .b = character.a, .data = (ir.ExtraSlice{ .start = extra, .len = 1 }).pack(), .span = inst.span };
        } else if (comparison(module, f, inst, ref)) |point| {
            const constant: ir.Ref = @fromBackingInt(@as(u32, @intCast(f.insts.items.len)));
            try f.insts.append(arena, .{ .op = .iconst, .ty = .u32, .data = point });
            f.insts.items[index] = .{ .op = .cmp, .ty = .bool, .a = ref, .b = constant, .data = @backingInt(ir.Predicate.eq), .span = inst.span };
        }
    }
}
