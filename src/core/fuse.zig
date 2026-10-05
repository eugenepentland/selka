//! Projection fusion (docs/design/new-core-s1.md §3, §4): a record or union read out of a
//! list and then taken apart one field at a time is read field by field instead.
//!
//! `list_get(xs, i)` followed by `record_get`, `union_tag` or `union_payload` of its result
//! (and their chains) becomes one `list_get_field(xs, i, path)` per projection, so an
//! element is never loaded whole to read one field of it, and a `match` on a union element
//! reads its tag, then only the payload of the arm taken. A source is fused only when
//! every use of it is a projection and no instruction that can trap, write a list or
//! have an effect lies between the read and any projection, so no observable order
//! changes and no list is read after a later update (`own.zig` runs after this pass and
//! sees the projections' reads of the list).
const std = @import("std");
const ir = @import("ir.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// Fuse every projection of an element read in `f`; returns how many reads it removed.
pub fn projections(arena: std.mem.Allocator, f: *ir.Function, module: *const ir.Module) Error!u32 {
    var fused: u32 = 0;
    for (0..f.blocks.items.len) |b| {
        var at: usize = 0;
        while (at < f.blocks.items[b].insts.items.len) {
            const source = f.blocks.items[b].insts.items[at];
            if (try fuseSource(arena, f, module, .{ .block = @intCast(b), .at = at, .source = source, .strict = f.inst(source).check == .exact })) {
                // The source's slot now holds the next instruction.
                fused += 1;
                continue;
            }
            at += 1;
        }
    }
    return fused;
}

/// Where a source read sits.
const Site = struct { block: u32, at: usize, source: ir.Ref, strict: bool = false };

/// One projection of a source: the instruction and the step it adds to the path.
const Projection = struct { user: ir.Ref, step: u12 };

/// Whether `inst` may run between a read and a projection of it without changing what the
/// program observes: it does not write, call, print or allocate, and when the read itself
/// can trap (`strict`) it cannot trap either, so the two failures keep their order.
fn inert(inst: ir.Inst, strict: bool) bool {
    if (strict and inst.check == .exact) return false;
    return switch (inst.op) {
        .iconst, .fconst, .undef, .str_const, .copy, .cmp, .fcmp, .not, .bit_and, .bit_or, .bit_xor => true,
        .record_make, .record_get, .record_set, .union_make, .union_tag, .union_payload, .box_get => true,
        .list_len, .str_len, .list_get_field, .list_get, .jump, .branch => true,
        .add, .sub, .mul, .neg, .fadd, .fsub, .fmul, .fneg, .convert, .int_to_float, .div, .rem, .floor_div, .floor_rem => true,
        else => false,
    };
}

/// Fuse the projections of the read at `site` when every use is one and the way to each is inert.
fn fuseSource(arena: std.mem.Allocator, f: *ir.Function, module: *const ir.Module, site: Site) Error!bool {
    const source = f.inst(site.source);
    if (source.op != .list_get and source.op != .list_get_field) return false;
    const element = module.compound(f.inst(f.resolve(source.a)).ty).list;
    if (module.kind(source.ty) == null) return false;
    const base: ir.FieldPath = if (source.op == .list_get_field) ir.FieldPath.unpack(source.data) else .{};
    var projected: std.ArrayList(Projection) = .empty;
    var other_use = false;
    for (f.blocks.items) |block| {
        for (block.insts.items) |ref| {
            const user = f.inst(ref);
            if (ref == site.source or user.op == .copy) continue;
            const operands = f.valueOperands(user);
            for (0..operands.len()) |i| {
                if (f.resolve(operands.get(i)) != site.source) continue;
                const step = stepOf(f, user, site.source) orelse {
                    other_use = true;
                    continue;
                };
                try projected.append(arena, .{ .user = ref, .step = step });
            }
        }
    }
    if (other_use or projected.items.len == 0) return false;
    for (projected.items) |projection| {
        if (!reachedInertly(f, site, projection.user)) return false;
        const path = extend(base, projection.step) orelse return false;
        const target = module.pathTarget(element, path) orelse return false;
        if (target.ty != f.inst(projection.user).ty) return false;
    }
    // The first projection (in program order) keeps the read's check; the rest follow it.
    var first: ir.Ref = projected.items[0].user;
    for (projected.items) |projection| {
        if (before(f, projection.user, first)) first = projection.user;
    }
    for (projected.items) |projection| {
        const path = extend(base, projection.step).?;
        const user = &f.insts.items[projection.user.index()];
        user.* = .{ .op = .list_get_field, .ty = user.ty, .a = source.a, .b = source.b, .data = path.pack(), .check = if (projection.user == first) source.check else .none, .span = if (projection.user == first) source.span else user.span };
    }
    const insts = &f.blocks.items[site.block].insts;
    _ = insts.orderedRemove(site.at);
    return true;
}

/// The path step `user` adds when it projects `source`, or null when it is not a projection.
fn stepOf(f: *const ir.Function, user: ir.Inst, source: ir.Ref) ?u12 {
    if (f.resolve(user.a) != source) return null;
    return switch (user.op) {
        .record_get => std.math.cast(u12, user.data),
        .union_tag => 0,
        .union_payload => if (std.math.cast(u12, user.data + 1)) |step| step else null,
        else => null,
    };
}

fn extend(base: ir.FieldPath, step: u12) ?ir.FieldPath {
    var steps: [ir.FieldPath.max_steps + 1]u32 = undefined;
    for (base.slice(), 0..) |s, i| steps[i] = s;
    steps[base.len] = step;
    return ir.FieldPath.init(steps[0 .. base.len + 1]);
}

/// Whether `a` comes before `b` in program order (same block by position, else by block order).
fn before(f: *const ir.Function, a: ir.Ref, b: ir.Ref) bool {
    const pa = locate(f, a) orelse return false;
    const pb = locate(f, b) orelse return false;
    if (pa.block != pb.block) return pa.block < pb.block;
    return pa.at < pb.at;
}

const Located = struct { block: u32, at: usize };

fn locate(f: *const ir.Function, ref: ir.Ref) ?Located {
    for (f.blocks.items, 0..) |block, b| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, ref)) |at| return .{ .block = @intCast(b), .at = at };
    }
    return null;
}

/// Whether control passes from the read at `site` to `user` through inert instructions only:
/// within the read's block, or down a chain of single-predecessor blocks that hold nothing else.
fn reachedInertly(f: *const ir.Function, site: Site, user: ir.Ref) bool {
    const where = locate(f, user) orelse return false;
    if (where.block == site.block) {
        if (where.at <= site.at) return false;
        return allInert(f, site, site.block, site.at + 1, where.at);
    }
    // Everything after the read in its own block, then whole blocks, then the user's block up to the user.
    var block: usize = where.block;
    if (!allInert(f, site, where.block, 0, where.at)) return false;
    var steps: usize = 0;
    while (steps <= f.blocks.items.len) : (steps += 1) {
        const preds = f.blocks.items[block].preds.items;
        if (preds.len != 1) return false;
        const pred = preds[0].index();
        if (pred == site.block) {
            const all = f.blocks.items[pred].insts.items.len;
            return allInert(f, site, pred, site.at + 1, all);
        }
        if (!allInert(f, site, pred, 0, f.blocks.items[pred].insts.items.len)) return false;
        block = pred;
    }
    return false;
}

fn allInert(f: *const ir.Function, site: Site, block: usize, from: usize, to: usize) bool {
    for (f.blocks.items[block].insts.items[from..to]) |ref| {
        if (!inert(f.inst(ref), site.strict)) return false;
    }
    return true;
}
