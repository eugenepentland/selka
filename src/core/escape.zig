//! Copy on escape: until ownership counts references (S1 lane O), a list stored into a
//! record, union, box or another list, or returned, must not stay shared with the variable
//! it came from, because that variable's later `append` or element write runs in place and
//! would change the stored list too (`own.zig` only sees uses of the list's own value).
//!
//! A stored or returned list is moved (no copy) when its storage was made in this function
//! and the store is its only use: a list literal or the result of a push chain. Any other
//! list gets a `list_copy` first. Lists read out of containers are never updated in place
//! (`own.zig` treats them as shared), so only direct list operands need this.
const std = @import("std");
const ir = @import("ir.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// What a function with `mut` parameters hands back unchanged: the caller's own lists
/// come straight back, so storing them in the result is no escape.
pub const Exempt = struct {
    /// The record type the function returns, and the first of its fields that holds a `mut` value.
    record: ir.Type = .void,
    first_field: usize = 0,
    /// The function returns its one `mut` value directly, not in a record.
    direct: bool = false,
};

/// Put a `list_copy` in front of every stored or returned list that may still be shared,
/// except what `exempt` hands back. Returns how many copies it inserted.
pub fn copyEscaping(arena: std.mem.Allocator, f: *ir.Function, module: *const ir.Module, exempt: Exempt) Error!u32 {
    const uses = try arena.alloc(u32, f.insts.items.len);
    @memset(uses, 0);
    for (f.blocks.items) |block| {
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op == .copy) continue;
            const operands = f.valueOperands(inst);
            for (0..operands.len()) |i| uses[f.resolve(operands.get(i)).index()] += 1;
        }
    }
    var inserted: u32 = 0;
    for (0..f.blocks.items.len) |b| {
        var at: usize = 0;
        while (at < f.blocks.items[b].insts.items.len) : (at += 1) {
            const ref = f.blocks.items[b].insts.items[at];
            const inst = f.inst(ref);
            switch (inst.op) {
                .record_make => {
                    const fields = f.operands(inst.data).len;
                    const guarded = if (exempt.record != .void and inst.ty == exempt.record) @min(exempt.first_field, fields) else fields;
                    for (0..guarded) |i| inserted += try guard(arena, f, module, uses, .{ .block = b, .at = &at }, .{ .extra = i });
                },
                .record_set, .list_push => inserted += try guard(arena, f, module, uses, .{ .block = b, .at = &at }, .b),
                .ret => if (!exempt.direct) {
                    inserted += try guard(arena, f, module, uses, .{ .block = b, .at = &at }, .a);
                },
                .union_make, .box_make => inserted += try guard(arena, f, module, uses, .{ .block = b, .at = &at }, .a),
                .list_set => inserted += try guard(arena, f, module, uses, .{ .block = b, .at = &at }, .{ .extra = 0 }),
                else => {},
            }
        }
    }
    return inserted;
}

/// Where a store sits.
const Site = struct { block: usize, at: *usize };

/// Which operand of the store holds the list.
const Operand = union(enum) { a, b, extra: usize };

/// Insert a copy of the stored operand in front of the store when it is a list that is not moved.
fn guard(arena: std.mem.Allocator, f: *ir.Function, module: *const ir.Module, uses: []u32, site: Site, which: Operand) Error!u32 {
    const store_ref = f.blocks.items[site.block].insts.items[site.at.*];
    const store = f.inst(store_ref);
    const operand: ir.Ref = switch (which) {
        .a => store.a,
        .b => store.b,
        .extra => |i| f.operands(store.data)[i],
    };
    if (operand == .none) return 0;
    const value = f.resolve(operand);
    const ty = f.inst(value).ty;
    if (module.kind(ty) != .list) return 0;
    if (moved(f, uses, value)) return 0;
    const copy: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(arena, .{ .op = .list_copy, .ty = ty, .a = value, .span = store.span });
    try f.blocks.items[site.block].insts.insert(arena, site.at.*, copy);
    site.at.* += 1;
    switch (which) {
        .a => f.insts.items[store_ref.index()].a = copy,
        .b => f.insts.items[store_ref.index()].b = copy,
        .extra => |i| f.extra.items[ir.ExtraSlice.unpack(store.data).start + i] = copy,
    }
    return 1;
}

/// Whether the store can take `value` without a copy: its storage was made in this
/// function and the store is its only use.
fn moved(f: *const ir.Function, uses: []const u32, value: ir.Ref) bool {
    if (uses[value.index()] != 1) return false;
    return switch (f.inst(value).op) {
        .list_new, .list_copy, .list_push, .list_set, .list_pop => true,
        else => false,
    };
}
