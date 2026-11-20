//! Decode temporary character strings once when every use needs only their scalar.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");

/// A character read: the text it reads, its octet offset, and whether the text is a view. A `str_char`
/// reads a block; a `myl_core_view_char` call reads a plain `str` parameter's view (C9 S1), and decodes
/// in place the same way.
const Read = struct { source: ir.Ref, offset: ir.Ref };

/// Preserve the original checked read; rewrite only comparisons and character appends.
pub fn run(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    var changed: u32 = 0;
    const original_len = f.insts.items.len;
    for (0..original_len) |index| {
        const character = f.insts.items[index];
        const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(index)));
        const read = readOf(module, f, character) orelse continue;
        if (!eligible(module, f, ref, read)) continue;
        try rewrite(arena, module, f, ref, read);
        changed += 1;
    }
    return changed;
}

fn readOf(module: *const ir.Module, f: *const ir.Function, character: ir.Inst) ?Read {
    if (character.op == .str_char) return .{ .source = character.a, .offset = character.b };
    if (character.op != .call or character.ty != .str or character.a.index() >= module.functions.items.len) return null;
    if (!std.mem.eql(u8, module.functions.items[character.a.index()].name, "myl_core_view_char")) return null;
    const args = f.operands(character.data);
    if (args.len != 2) return null;
    return .{ .source = args[0], .offset = args[1] };
}

fn eligible(module: *const ir.Module, f: *const ir.Function, ref: ir.Ref, read: Read) bool {
    var found = false;
    for (f.insts.items) |inst| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |index| {
            if (f.resolve(operands.get(index)) != ref) continue;
            if (!appendUse(f, inst, ref, read) and comparison(module, f, inst, ref) == null) return false;
            found = true;
        }
    }
    return found;
}

fn appendUse(f: *const ir.Function, inst: ir.Inst, ref: ir.Ref, read: Read) bool {
    return inst.op == .str_append and f.resolve(inst.b) == ref and
        f.resolve(inst.a) != ref and f.resolve(inst.a) != f.resolve(read.source);
}

fn comparison(module: *const ir.Module, f: *const ir.Function, inst: ir.Inst, ref: ir.Ref) ?u32 {
    if (inst.op != .call or inst.ty != .bool or inst.a.index() >= module.functions.items.len) return null;
    const callee = module.functions.items[inst.a.index()];
    const signature = callee.signature;
    if (signature.linkage != .runtime_c or signature.ret != .bool) return null;
    if (!signature.passing.eql(.{})) return null;
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

fn rewrite(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, ref: ir.Ref, read: Read) std.mem.Allocator.Error!void {
    const original_len = f.insts.items.len;
    const span = f.insts.items[ref.index()].span;
    // str_char emits its located bounds check even when its IR check is absent.
    f.insts.items[ref.index()] = .{ .op = .str_code, .ty = .u32, .a = read.source, .b = read.offset, .check = .exact, .span = span };
    for (f.insts.items) |*inst| {
        if (inst.op == .copy and f.resolve(inst.a) == ref) inst.ty = .u32;
    }
    for (0..original_len) |index| {
        const inst = f.insts.items[index];
        if (appendUse(f, inst, ref, read)) {
            const extra: u32 = @intCast(f.extra.items.len);
            try f.extra.append(arena, read.offset);
            f.insts.items[index] = .{ .op = .str_append_char, .ty = .str, .a = inst.a, .b = read.source, .data = (ir.ExtraSlice{ .start = extra, .len = 1 }).pack(), .span = inst.span };
        } else if (comparison(module, f, inst, ref)) |point| {
            const constant: ir.Ref = @fromBackingInt(@as(u32, @intCast(f.insts.items.len)));
            try f.insts.append(arena, .{ .op = .iconst, .ty = .u32, .data = point });
            f.insts.items[index] = .{ .op = .cmp, .ty = .bool, .a = ref, .b = constant, .data = @backingInt(ir.Predicate.eq), .span = inst.span };
        }
    }
}
