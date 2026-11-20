//! One-use ownership transfer pairing through control flow.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const absent = std.math.maxInt(u32);
const empty = absent - 1;
const ambiguous = absent - 2;
const Key = struct { owner: ir.Ref, index: ir.Ref, constant: ?u64, field: ?u64, dictionary: bool };

/// Each read supplies one token. An overlapping write consumes it, including
/// writes which cannot themselves receive it. Merges require the same token
/// on every incoming path; a loop cannot reuse a token from an earlier turn.
pub fn slots(arena: std.mem.Allocator, function: *const ir.Function) std.mem.Allocator.Error![]bool {
    const taken = try arena.alloc(bool, function.insts.items.len);
    @memset(taken, false);
    var keys: std.AutoHashMapUnmanaged(Key, void) = .empty;
    for (function.blocks.items) |block| for (block.insts.items) |ref| {
        if (readKey(function, function.inst(ref))) |key| try keys.put(arena, key, {});
    };
    if (keys.count() == 0) return taken;
    // Resolve forwarding chains once per event, outside the per-key CFG walk.
    const reads = try arena.alloc(?Key, function.insts.items.len);
    const stores = try arena.alloc(?Key, function.insts.items.len);
    for (function.insts.items, 0..) |inst, position| {
        reads[position] = readKey(function, inst);
        stores[position] = storeKey(function, inst);
    }
    var scratch = std.heap.ArenaAllocator.init(arena);
    defer scratch.deinit();
    var iterator = keys.keyIterator();
    while (iterator.next()) |key| {
        _ = scratch.reset(.retain_capacity);
        try pair(scratch.allocator(), function, key.*, taken, reads, stores);
    }
    return taken;
}

fn readKey(function: *const ir.Function, inst: ir.Inst) ?Key {
    if (!flags.transferredRead(inst) or inst.op == .dict_entry_key) return null;
    return slotKey(function, inst, if (inst.op == .list_get_field) inst.data & ~flags.place_read else null, inst.op == .dict_entry_value);
}

fn storeKey(function: *const ir.Function, inst: ir.Inst) ?Key {
    const field: ?u64 = switch (inst.op) {
        .list_set, .dict_set_value => null,
        .list_set_field => storedPath(function, inst) orelse return null,
        else => return null,
    };
    return slotKey(function, inst, field, inst.op == .dict_set_value);
}

/// In-place slot writes keep every disjoint slot's transfer token. Pair against
/// their original container, while process() consumes tokens on overlapping writes.
fn slotKey(function: *const ir.Function, inst: ir.Inst, field: ?u64, dictionary: bool) Key {
    var owner = function.resolve(inst.a);
    while (true) {
        const parent = function.inst(owner);
        if (parent.op != .list_set and parent.op != .list_set_field and parent.op != .dict_set_value) break;
        owner = function.resolve(parent.a);
    }
    const index = function.resolve(inst.b);
    const at = function.inst(index);
    return .{ .owner = owner, .index = if (at.op == .iconst) .none else index, .constant = if (at.op == .iconst) at.data else null, .field = field, .dictionary = dictionary };
}

fn overlap(a: Key, b: Key) bool {
    if (a.owner != b.owner or a.dictionary != b.dictionary) return false;
    if (a.constant != null and b.constant != null and a.constant.? != b.constant.?) return false;
    if (a.field == null or b.field == null) return true;
    const left = ir.FieldPath.unpack(a.field.?);
    const right = ir.FieldPath.unpack(b.field.?);
    const count = @min(left.len, right.len);
    return std.mem.eql(u12, left.steps[0..count], right.steps[0..count]);
}

fn pair(arena: std.mem.Allocator, function: *const ir.Function, key: Key, taken: []bool, reads: []const ?Key, stores: []const ?Key) !void {
    if (function.blocks.items.len == 0) return;
    const incoming = try arena.alloc(u32, function.blocks.items.len);
    @memset(incoming, absent);
    incoming[0] = empty;
    var queue: std.ArrayList(ir.BlockId) = .empty;
    try queue.append(arena, @fromBackingInt(0));
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        const id = queue.items[cursor];
        const block = function.blocks.items[id.index()];
        const state = process(block, key, incoming[id.index()], taken, reads, stores);
        if (block.insts.items.len == 0) continue;
        const last = function.inst(block.insts.items[block.insts.items.len - 1]);
        switch (last.op) {
            .jump => try propagate(arena, incoming, &queue, @fromBackingInt(@intCast(last.data)), state),
            .branch => {
                const targets = ir.unpackTargets(last.data);
                try propagate(arena, incoming, &queue, targets.then, state);
                try propagate(arena, incoming, &queue, targets.otherwise, state);
            },
            else => {},
        }
    }
}

fn process(block: ir.Block, key: Key, initial: u32, taken: []bool, reads: []const ?Key, stores: []const ?Key) u32 {
    var state = initial;
    for (block.insts.items) |ref| {
        if (reads[ref.index()]) |read| {
            if (std.meta.eql(read, key)) state = @intCast(ref.index());
        }
        if (stores[ref.index()]) |store| {
            if (!overlap(key, store)) continue;
            if (std.meta.eql(store, key)) taken[ref.index()] = state < ambiguous;
            state = empty;
        }
    }
    return state;
}

fn propagate(arena: std.mem.Allocator, incoming: []u32, queue: *std.ArrayList(ir.BlockId), target: ir.BlockId, state: u32) !void {
    const prior = incoming[target.index()];
    const merged = if (prior == absent) state else if (prior == state) prior else ambiguous;
    if (prior == merged) return;
    incoming[target.index()] = merged;
    try queue.append(arena, target);
}

fn storedPath(function: *const ir.Function, inst: ir.Inst) ?u64 {
    const operands = function.operands(inst.data);
    if (operands.len != 2) return null;
    const constant = function.inst(function.resolve(operands[1]));
    return if (constant.op == .iconst and constant.ty == .u64) constant.data else null;
}
