//! Release builds inline small leaf functions before the fact pass, so the facts
//! (and the vector lowering) see through helpers such as `affine_a(x) = x*3+7`.
//!
//! A callee qualifies when it is internal, has exactly one block, ends in
//! `ret value`, and contains no call, print or phi. Its instructions are cloned
//! into the caller in front of the call, its parameters replaced by the call's
//! arguments, and the call becomes a forwarding `copy` of the returned value.
//! Spans stay the callee's, so a trap still names the line inside the helper.
const std = @import("std");
const ir = @import("ir.zig");

/// Inlining only allocates.
pub const Error = std.mem.Allocator.Error;

/// Inline every qualifying call in `module`'s internal functions; returns how many.
pub fn inlineLeaves(arena: std.mem.Allocator, module: *ir.Module) Error!u32 {
    var count: u32 = 0;
    for (module.functions.items, 0..) |*caller, index| {
        if (caller.signature.linkage != .internal) continue;
        for (caller.blocks.items) |*block| {
            var at: usize = 0;
            while (at < block.insts.items.len) : (at += 1) {
                const ref = block.insts.items[at];
                const call = caller.insts.items[ref.index()];
                if (call.op != .call or call.a.index() == index) continue;
                const callee = &module.functions.items[call.a.index()];
                const result = leaf(callee) orelse continue;
                const cloned = try splice(arena, caller, callee, .{ .block = block, .at = at, .call = ref, .result = result });
                at += cloned;
                count += 1;
            }
        }
    }
    return count;
}

/// The returned value of a qualifying leaf, or null.
fn leaf(callee: *const ir.Function) ?ir.Ref {
    if (callee.signature.linkage != .internal or callee.blocks.items.len != 1 or callee.signature.ret == .void) return null;
    const insts = callee.blocks.items[0].insts.items;
    if (insts.len == 0) return null;
    const last = callee.inst(insts[insts.len - 1]);
    if (last.op != .ret or last.a == .none) return null;
    for (insts[0 .. insts.len - 1]) |ref| switch (callee.inst(ref).op) {
        .call, .print, .phi, .jump, .branch, .ret, .@"unreachable" => return null,
        else => {},
    };
    return last.a;
}

/// Where one call is replaced.
const Site = struct { block: *ir.Block, at: usize, call: ir.Ref, result: ir.Ref };

/// Clone the callee's body into the caller before `site.at`; returns the number of instructions inserted.
fn splice(arena: std.mem.Allocator, caller: *ir.Function, callee: *const ir.Function, site: Site) Error!usize {
    const arguments = caller.operands(caller.insts.items[site.call.index()].data);
    const map = try arena.alloc(ir.Ref, callee.insts.items.len);
    @memset(map, .none);
    // Parameters become the arguments; block-less constants are cloned on demand.
    for (callee.insts.items, 0..) |inst, i| {
        map[i] = switch (inst.op) {
            .param => arguments[@intCast(inst.data)],
            .iconst, .fconst, .undef, .str_const => try append(arena, caller, inst),
            else => .none,
        };
    }
    var inserted: std.ArrayList(ir.Ref) = .empty;
    const body = callee.blocks.items[0].insts.items;
    for (body[0 .. body.len - 1]) |old| {
        var inst = callee.inst(old);
        inst.a = remap(callee, map, inst.a);
        inst.b = remap(callee, map, inst.b);
        const ref = try append(arena, caller, inst);
        map[old.index()] = ref;
        try inserted.append(arena, ref);
    }
    try site.block.insts.insertSlice(arena, site.at, inserted.items);
    caller.insts.items[site.call.index()] = .{ .op = .copy, .ty = caller.insts.items[site.call.index()].ty, .a = remap(callee, map, site.result) };
    return inserted.items.len;
}

fn remap(callee: *const ir.Function, map: []const ir.Ref, raw: ir.Ref) ir.Ref {
    if (raw == .none) return .none;
    return map[callee.resolve(raw).index()];
}

fn append(arena: std.mem.Allocator, function: *ir.Function, inst: ir.Inst) Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(function.insts.items.len));
    try function.insts.append(arena, inst);
    return ref;
}
