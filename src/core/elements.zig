//! Element-field stores (NEW-CORE-CE-LISTS-1): `xs[i].f = v` written in place.
//!
//! The builder lowers a store into a field of a list element as a whole-element round
//! trip: `g = list_get(xs, i)`, `r = record_set(g, f, v)` (a chain of them, through
//! `record_get`s, for `xs[i].a.b = v`), `xs' = list_set(xs, i, r)`. For an element over
//! four words that copies the element out, copies it again for the field store and
//! copies it back. When nothing else reads the element or the intermediate records, the
//! chain becomes one `list_set_field(xs, i, v, path)`: the same value (the list with that
//! one field replaced), stored in place after the list's uniqueness test like any other
//! list update. The read's bounds check moves to the store, so only instructions that
//! cannot trap, write or have an effect may lie between them.
//!
//! An element read nothing uses whose bounds check an identical later access repeats is
//! dropped too (the later access takes its source position), and the read a place
//! detaches its list for (`list_copy` marked `place_copy`) is no longer needed once the
//! read is gone, so the store updates the list it came from.
//!
//! Runs in `own.function` before copy on write, after the release passes and stack
//! promotion (which index the fact tables by instruction).
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// The field path of a `list_set_field`: the `u64` constant in `extra[1]`.
pub fn setPath(f: *const ir.Function, inst: ir.Inst) ?ir.FieldPath {
    const operands = f.operands(inst.data);
    if (operands.len != 2) return null;
    const constant = f.inst(f.resolve(operands[1]));
    if (constant.op != .iconst or constant.ty != .u64) return null;
    return ir.FieldPath.unpack(constant.data);
}

/// Rewrite every element-field store of `f` and drop the dead element reads; returns
/// how many stores it rewrote.
pub fn fieldStores(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function) Error!u32 {
    var rewritten: u32 = 0;
    var uses = try countUses(arena, f);
    for (0..f.blocks.items.len) |b| {
        if (b != 0 and f.blocks.items[b].preds.items.len == 0) continue;
        var pos: usize = 0;
        while (pos < f.blocks.items[b].insts.items.len) : (pos += 1) {
            const ref = f.blocks.items[b].insts.items[pos];
            if (f.inst(ref).op != .list_set) continue;
            if (try rewriteStore(arena, module, f, .{ .uses = uses, .block = @intCast(b), .store = ref })) {
                rewritten += 1;
                uses = try countUses(arena, f);
                pos = 0;
            }
        }
    }
    try dropDeadReads(arena, f, uses);
    return rewritten;
}

/// Uses of each value by the instructions of reachable blocks (phi operands included).
fn countUses(arena: std.mem.Allocator, f: *const ir.Function) Error![]u32 {
    const uses = try arena.alloc(u32, f.insts.items.len);
    @memset(uses, 0);
    for (f.blocks.items, 0..) |block, b| {
        if (b != 0 and block.preds.items.len == 0) continue;
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op == .copy) continue;
            if (inst.op == .phi) {
                for (f.operands(inst.data)) |operand| uses[f.resolve(operand).index()] += 1;
                continue;
            }
            const operands = f.valueOperands(inst);
            for (0..operands.len()) |k| {
                const used = f.resolve(operands.get(k));
                if (used != .none) uses[used.index()] += 1;
            }
        }
    }
    return uses;
}

/// One store being matched: the use counts, its block and the `list_set`.
const Site = struct { uses: []const u32, block: u32, store: ir.Ref };

const inert = @import("fuse.zig").inert;

/// Match `list_set(xs, i, record_set(list_get(xs, i), f, …))` at `site.store` and rewrite it.
fn rewriteStore(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, site: Site) Error!bool {
    const store = f.inst(site.store);
    const list = f.resolve(store.a);
    const index = f.resolve(store.b);
    const top = f.resolve(f.operands(store.data)[0]);
    const outer = f.inst(top);
    if (outer.op != .record_set or site.uses[top.index()] != 1) return false;
    const read_ref = f.resolve(outer.a);
    const read = f.inst(read_ref);
    if (read.op != .list_get or (read.data != 0 and read.data != flags.place_read)) return false;
    if (f.resolve(read.a) != list or f.resolve(read.b) != index) return false;
    // Walk the chain of field updates down to the stored value.
    var steps: [ir.FieldPath.max_steps]u32 = undefined;
    var depth: usize = 0;
    var removed: [2 * ir.FieldPath.max_steps + 1]ir.Ref = undefined;
    var removed_len: usize = 0;
    removed[removed_len] = top;
    removed_len += 1;
    var level = read_ref;
    var update = top;
    var value: ir.Ref = .none;
    while (true) {
        const set = f.inst(update);
        if (module.kind(set.ty) != .record) return false;
        steps[depth] = @intCast(set.data);
        depth += 1;
        const next = f.resolve(set.b);
        const inner = f.inst(next);
        const nested = depth < ir.FieldPath.max_steps and inner.op == .record_set and site.uses[next.index()] == 1 and blk: {
            const part = f.resolve(inner.a);
            const got = f.inst(part);
            break :blk got.op == .record_get and f.resolve(got.a) == level and got.data == set.data and site.uses[part.index()] == 1;
        };
        if (!nested) {
            value = next;
            break;
        }
        const part = f.resolve(inner.a);
        removed[removed_len] = part;
        removed[removed_len + 1] = next;
        removed_len += 2;
        level = part;
        update = next;
    }
    // The read feeds the outer update and, when nested, the first field read.
    if (site.uses[read_ref.index()] != @as(u32, if (depth > 1) 2 else 1)) return false;
    const path = ir.FieldPath.init(steps[0..depth]) orelse return false;
    const element = module.compound(f.inst(list).ty).list;
    const target = module.pathTarget(element, path) orelse return false;
    if (target.tag_of != .void or target.ty != f.inst(value).ty) return false;
    // The read and every update sit in the store's block, ahead of it, with only inert
    // instructions between the read and the store.
    const insts = f.blocks.items[site.block].insts.items;
    const read_at = std.mem.indexOfScalar(ir.Ref, insts, read_ref) orelse return false;
    const store_at = std.mem.indexOfScalar(ir.Ref, insts, site.store) orelse return false;
    if (read_at >= store_at) return false;
    for (removed[0..removed_len]) |member| {
        const at = std.mem.indexOfScalar(ir.Ref, insts, member) orelse return false;
        if (at <= read_at or at >= store_at) return false;
    }
    const strict = read.check == .exact;
    for (insts[read_at + 1 .. store_at]) |between| {
        if (!inert(f.inst(between), strict)) return false;
    }
    // The rewrite: the store keeps its position and reference (its facts still hold).
    const constant: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    try f.insts.append(arena, .{ .op = .iconst, .ty = .u64, .data = path.pack() });
    const extra_start: u32 = @intCast(f.extra.items.len);
    try f.extra.appendSlice(arena, &.{ value, constant });
    const exact = read.check == .exact or store.check == .exact;
    var target_list = store.a;
    const detach = f.inst(list);
    // The detach existed only for the read to take the slot's owner: drop it.
    if (detach.op == .list_copy and detach.data == flags.place_copy and site.uses[list.index()] == 2) {
        target_list = detach.a;
        f.insts.items[list.index()] = .{ .op = .copy, .ty = detach.ty, .a = detach.a, .span = detach.span };
    }
    f.insts.items[site.store.index()] = .{
        .op = .list_set_field,
        .ty = store.ty,
        .a = target_list,
        .b = store.b,
        .data = (ir.ExtraSlice{ .start = extra_start, .len = 2 }).pack(),
        .check = if (exact) .exact else if (read.check == .proven or store.check == .proven) .proven else .none,
        .span = if (strict) read.span else store.span,
    };
    var kept: std.ArrayList(ir.Ref) = .empty;
    for (insts) |member| {
        if (member == read_ref or member == list and f.inst(list).op == .copy) continue;
        if (std.mem.indexOfScalar(ir.Ref, removed[0..removed_len], member) != null) continue;
        try kept.append(arena, member);
    }
    f.blocks.items[site.block].insts = kept;
    return true;
}

/// Drop each element read (`data` 0) no instruction uses: one that cannot trap at once,
/// and one whose bounds check the next access of the same element repeats, with only
/// inert instructions between, by giving that access its check and source position.
fn dropDeadReads(arena: std.mem.Allocator, f: *ir.Function, uses: []const u32) Error!void {
    for (f.blocks.items, 0..) |*block, b| {
        if (b != 0 and block.preds.items.len == 0) continue;
        var kept: std.ArrayList(ir.Ref) = .empty;
        for (block.insts.items, 0..) |ref, at| {
            const read = f.inst(ref);
            const dead = (read.op == .list_get or read.op == .list_get_field) and read.data == 0 and uses[ref.index()] == 0;
            if (!dead) {
                try kept.append(arena, ref);
                continue;
            }
            if (read.check != .exact) continue;
            const repeat = repeatedAccess(f, block.insts.items[at + 1 ..], read) orelse {
                try kept.append(arena, ref);
                continue;
            };
            f.insts.items[repeat.index()].check = .exact;
            f.insts.items[repeat.index()].span = read.span;
        }
        block.insts = kept;
    }
}

/// The first later access of the element `read` reads, reached through inert instructions only.
fn repeatedAccess(f: *const ir.Function, later: []const ir.Ref, read: ir.Inst) ?ir.Ref {
    for (later) |ref| {
        const inst = f.inst(ref);
        const access = switch (inst.op) {
            // A pop's read traps as an empty pop, not as an index: it is no repeat.
            .list_get => inst.data == 0 or inst.data == flags.place_read,
            .list_get_field, .list_set, .list_set_field => true,
            else => false,
        };
        if (access and f.resolve(inst.a) == f.resolve(read.a) and f.resolve(inst.b) == f.resolve(read.b)) return ref;
        if (!inert(inst, true)) return null;
    }
    return null;
}
