//! Stack promotion of lists that never escape (docs/design/new-core-s1.md §6.3).
//!
//! A list built in the function whose every use is a read (`list_len`, `list_get`,
//! `list_get_field`), whose only updates are the pushes that fill it, and whose
//! capacity the facts bound by a constant lives in an entry-block `alloca` instead of
//! a heap block: its count is never touched, nothing releases it and it never grows.
//! Two fill shapes qualify:
//! - a straight chain `list_new → push → push …` (capacity: the number of pushes);
//! - a counted fill loop the fact pass recognized (`list_new` entering a header phi
//!   whose back edge is one push of it per iteration): capacity `hi(bound)`.
//! Anything else that touches a value of the web (a call, a return, a store into a
//! container, record, union or box, a phi of another shape, another update) makes it
//! escape. Element types that hold blocks are left alone (a stack list releases no
//! children). The `alloca` is reused across iterations of enclosing loops safely: no
//! web value reaches a phi, so every use of an instance comes before its `list_new`
//! runs again.
//!
//! Marks (frozen IR, `data` fields the verifier does not read): the `list_new` gets
//! `data = capacity + 1`; each filling push gets `data = stack_push` and is emitted
//! without the growth call. Verify builds put `len < capacity` before each such push
//! (an `unreachable` with `data = capacity_assert`, an `R_CORE_FACT` trap).
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// The `data` of a push into a promoted list: no growth, the room is proven.
pub const stack_push: u64 = 1;

/// The `data` of an `unreachable` asserting a promoted list's room (verify builds).
pub const capacity_assert: u64 = 2;

/// The most bytes of elements a promoted list may take on the stack.
pub const max_stack_bytes: u64 = 4096;

/// Promote every qualifying list of `f`; returns the promoted values (every value of
/// each web: the `list_new`, its pushes and the loop phi) and how many lists.
pub fn promote(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, known: *const facts.Facts, verify: bool) Error!Promoted {
    var out: Promoted = .{};
    const users = try usersOf(arena, f);
    const count = f.insts.items.len;
    for (0..count) |i| {
        const inst = f.insts.items[i];
        if (inst.op != .list_new or inst.data != 0) continue;
        const element = module.compound(inst.ty).list;
        if (module.managed(element)) continue;
        const ref: ir.Ref = @fromBackingInt(@intCast(i));
        const web = try webOf(arena, f, users, known, ref) orelse continue;
        if (web.capacity * @max(1, module.size(element)) > max_stack_bytes) continue;
        f.insts.items[i].data = web.capacity + 1;
        for (web.pushes) |push| f.insts.items[push.index()].data = stack_push;
        for (web.values) |value| try out.values.put(arena, @backingInt(value), {});
        out.lists += 1;
        if (verify) for (web.pushes) |push| try assertRoom(arena, f, push, web.capacity);
    }
    return out;
}

/// What `promote` changed.
pub const Promoted = struct {
    values: std.AutoHashMapUnmanaged(u32, void) = .empty,
    lists: u32 = 0,
};

/// One list's values, filling pushes and proven capacity.
const Web = struct { values: []const ir.Ref, pushes: []const ir.Ref, capacity: u64 };

/// Who reads each value: (instruction, operand position); a phi use names the phi.
const Users = []std.ArrayList(ir.Ref);

fn usersOf(arena: std.mem.Allocator, f: *const ir.Function) Error!Users {
    const users = try arena.alloc(std.ArrayList(ir.Ref), f.insts.items.len);
    @memset(users, .empty);
    for (f.blocks.items, 0..) |block, b| {
        if (b != 0 and block.preds.items.len == 0) continue;
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op == .copy) continue;
            const operands = if (inst.op == .phi) f.operands(inst.data) else blk: {
                var direct = f.valueOperands(inst);
                var list: std.ArrayList(ir.Ref) = .empty;
                for (0..direct.len()) |k| try list.append(arena, direct.get(k));
                break :blk list.items;
            };
            for (operands) |operand| {
                const used = f.resolve(operand);
                if (used != .none) try users[used.index()].append(arena, ref);
            }
        }
    }
    return users;
}

/// Whether `user` only reads list `value` (and does not keep it).
fn reads(f: *const ir.Function, user: ir.Ref, value: ir.Ref) bool {
    const inst = f.inst(user);
    return switch (inst.op) {
        .list_len, .list_get, .list_get_field => f.resolve(inst.a) == value and (inst.b == .none or f.resolve(inst.b) != value),
        else => false,
    };
}

/// The web of `list` when it qualifies, else null.
fn webOf(arena: std.mem.Allocator, f: *const ir.Function, users: Users, known: *const facts.Facts, list: ir.Ref) Error!?Web {
    var values: std.ArrayList(ir.Ref) = .empty;
    var pushes: std.ArrayList(ir.Ref) = .empty;
    try values.append(arena, list);
    var current = list;
    var capacity: u64 = 0;
    var looped = false;
    var filling: ir.Ref = .none;
    while (true) {
        var next: ?ir.Ref = null;
        for (users[current.index()].items) |user| {
            if (reads(f, user, current) or user == filling) continue;
            if (next != null) return null;
            next = user;
        }
        const consumer = next orelse break;
        // In place, a read after the update would see the new length: every read of
        // this version must be over before its update can run.
        for (users[current.index()].items) |user| {
            if (user != filling and user != consumer and try readsAfter(arena, f, current, consumer, user)) return null;
        }
        const inst = f.inst(consumer);
        const extends = inst.op == .list_push and f.resolve(inst.a) == current and f.resolve(inst.b) != current;
        if (extends and !looped) {
            capacity += 1;
            try pushes.append(arena, consumer);
            try values.append(arena, consumer);
            current = consumer;
            continue;
        }
        // A counted fill loop entered straight from the `list_new`.
        if (inst.op != .phi or current != list or looped) return null;
        const fill = fillLoop(f, users, known, consumer, list) orelse return null;
        for (users[consumer.index()].items) |user| {
            if (user != fill.push and try readsAfter(arena, f, consumer, fill.push, user)) return null;
        }
        capacity = fill.capacity;
        try pushes.append(arena, fill.push);
        try values.appendSlice(arena, &.{ consumer, fill.push });
        current = consumer;
        filling = fill.push;
        looped = true;
    }
    return .{ .values = values.items, .pushes = pushes.items, .capacity = capacity };
}

/// Whether `read` can run after `update` while `value` (its operand) keeps the same
/// instance: later in `update`'s block, or in a block reachable from it without
/// passing `value`'s definition again.
fn readsAfter(arena: std.mem.Allocator, f: *const ir.Function, value: ir.Ref, update: ir.Ref, read: ir.Ref) Error!bool {
    const from = locate(f, update);
    const target = locate(f, read);
    if (target.block == from.block and target.pos > from.pos) return true;
    const def = if (f.inst(value).op == .phi) locate(f, value).block else std.math.maxInt(usize);
    const seen = try arena.alloc(bool, f.blocks.items.len);
    @memset(seen, false);
    var stack: std.ArrayList(usize) = .empty;
    try stack.append(arena, from.block);
    while (stack.pop()) |b| {
        const insts = f.blocks.items[b].insts.items;
        if (insts.len == 0) continue;
        for (successorsOf(f.inst(insts[insts.len - 1]))) |succ| {
            const next = (succ orelse continue).index();
            if (next == def or seen[next]) continue;
            if (next == target.block) return true;
            seen[next] = true;
            try stack.append(arena, next);
        }
    }
    return false;
}

/// A header phi the fact pass gave a length (`listFacts`): its other operand is one
/// push of the phi, used by nothing else; the capacity is the bound's upper end.
fn fillLoop(f: *const ir.Function, users: Users, known: *const facts.Facts, phi: ir.Ref, list: ir.Ref) ?struct { push: ir.Ref, capacity: u64 } {
    const fact = known.lists[phi.index()];
    if (fact.length == .none) return null;
    const operands = f.operands(f.inst(phi).data);
    if (operands.len != 2) return null;
    const entry = f.resolve(operands[0]);
    const back = f.resolve(operands[1]);
    const push = if (entry == list) back else if (back == list) entry else return null;
    const pushed = f.inst(push);
    if (pushed.op != .list_push or f.resolve(pushed.a) != phi or f.resolve(pushed.b) == phi) return null;
    if (users[push.index()].items.len != 1 or users[push.index()].items[0] != phi) return null;
    const bound = f.inst(f.resolve(fact.length));
    const hi: i128 = if (bound.op == .iconst) @as(i64, @bitCast(bound.data)) else (known.ranges[f.resolve(fact.length).index()] orelse return null).hi;
    if (hi > std.math.maxInt(u32)) return null;
    return .{ .push = push, .capacity = @intCast(@max(hi, 0)) };
}

/// Verify builds: before `push`, trap unless its list's length is below `capacity`.
fn assertRoom(arena: std.mem.Allocator, f: *ir.Function, push: ir.Ref, capacity: u64) Error!void {
    const inst = f.inst(push);
    const where = locate(f, push);
    const head: ir.BlockId = @fromBackingInt(@intCast(where.block));
    // Split before the push; the head ends in the room test.
    try f.blocks.append(arena, .{});
    const tail: ir.BlockId = @fromBackingInt(@intCast(f.blocks.items.len - 1));
    try f.blocks.items[tail.index()].insts.appendSlice(arena, f.blocks.items[where.block].insts.items[where.pos..]);
    f.blocks.items[where.block].insts.shrinkRetainingCapacity(where.pos);
    const term = f.inst(f.blocks.items[tail.index()].insts.items[f.blocks.items[tail.index()].insts.items.len - 1]);
    for (successorsOf(term)) |succ| {
        if (succ == null) continue;
        for (f.blocks.items[succ.?.index()].preds.items) |*pred| {
            if (pred.* == head) pred.* = tail;
        }
    }
    for (f.loops.items) |*loop| {
        if (loop.latch == head) loop.latch = tail;
    }
    const len = try add(arena, f, head, .{ .op = .list_len, .ty = .u64, .a = inst.a, .span = inst.span });
    const limit = try loose(arena, f, .{ .op = .iconst, .ty = .u64, .data = capacity });
    const room = try add(arena, f, head, .{ .op = .cmp, .ty = .bool, .a = len, .b = limit, .data = @backingInt(ir.Predicate.lt), .span = inst.span });
    try f.blocks.append(arena, .{});
    const fail: ir.BlockId = @fromBackingInt(@intCast(f.blocks.items.len - 1));
    _ = try add(arena, f, head, .{ .op = .branch, .ty = .void, .a = room, .data = ir.packTargets(tail, fail), .span = inst.span });
    try f.blocks.items[tail.index()].preds.append(arena, head);
    try f.blocks.items[fail.index()].preds.append(arena, head);
    _ = try add(arena, f, fail, .{ .op = .@"unreachable", .ty = .void, .data = capacity_assert, .span = inst.span });
}

fn successorsOf(term: ir.Inst) [2]?ir.BlockId {
    return switch (term.op) {
        .jump => .{ @fromBackingInt(@as(u32, @truncate(term.data))), null },
        .branch => blk: {
            const targets = ir.unpackTargets(term.data);
            break :blk .{ targets.then, if (targets.otherwise == targets.then) null else targets.otherwise };
        },
        else => .{ null, null },
    };
}

fn locate(f: *const ir.Function, ref: ir.Ref) struct { block: usize, pos: usize } {
    for (f.blocks.items, 0..) |block, b| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, ref)) |pos| return .{ .block = b, .pos = pos };
    }
    unreachable;
}

fn loose(arena: std.mem.Allocator, f: *ir.Function, inst: ir.Inst) Error!ir.Ref {
    try f.insts.append(arena, inst);
    return @fromBackingInt(@intCast(f.insts.items.len - 1));
}

fn add(arena: std.mem.Allocator, f: *ir.Function, block: ir.BlockId, inst: ir.Inst) Error!ir.Ref {
    const ref = try loose(arena, f, inst);
    try f.blocks.items[block.index()].insts.append(arena, ref);
    return ref;
}
