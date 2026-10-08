//! Element stores (CE2-A, docs/audits/values-keys-trap-search-plan-2026-10-07.md §4.5 "CE2").
//!
//! Two rewrites of `xs' = list_set(xs, k, v)`, the whole-element store, before ownership
//! gives it its copy-on-write form:
//!
//! **Dead and sunk stores** (NEW-CORE-CE2-EFFECTS-3). A store whose element nothing reads
//! before a later store of the same element overwrites it is removed: its list value is
//! followed forward (through the records that hold it, phis, and calls whose effect
//! summary neither reads nor replaces it) until a store of the same element ends it on
//! every path. A read of the list's elements, a return, a call that may read the list, or
//! anything else that lets the list escape is an observation and keeps the store. A trap
//! is not one: a trap ends the process (a test trial runs in a forked child), so nothing
//! can see a store a trap skips. When only some successors of the store's block observe
//! it, the store moves to those successors, and the others go without. The store's bounds
//! check stays where it was, as an element read nothing uses.
//!
//! **Narrowed stores** (NEW-CORE-CE2-EFFECTS-4). When `v` is a record that was read from
//! element `k` of the same list, or last stored there, and only some of its fields can
//! have changed since (record updates, and `mut` calls by their effect summaries), the
//! store writes only those fields with `list_set_field`: no whole-element copy and no
//! count updates for the parts that did not change. The proof walks `v` back to where it
//! was read or stored and the element back through the stores of the list, across phis
//! by their predecessors, keeping the branch conditions that lead to each edge: a
//! handler that changes the frame count only when it answers `False` (by its conditional
//! summary) does not count on the path that continues only on `True`.
//!
//! Element identity: an index is its integer before any normalization from the end,
//! taken from a field of a record (`rt.frame_count - 1`) or a value, plus a constant. A
//! normalized index names the same element only in lists of the same length, so a push or
//! pop, or a call that may write the list, ends that knowledge.
const std = @import("std");
const ir = @import("ir.zig");
const effects = @import("effects.zig");
const flags = @import("flags.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// What the pass did to one function.
pub const Stats = struct { removed: u32 = 0, sunk: u32 = 0, narrowed: u32 = 0 };

/// No block.
const none: u32 = std.math.maxInt(u32);

/// Run both rewrites over `f`, dead and sunk stores first.
pub fn run(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, summaries: *const effects.Summaries) Error!Stats {
    var stats: Stats = .{};
    if (!hasStores(f)) return stats;
    var scratch = std.heap.ArenaAllocator.init(arena);
    defer scratch.deinit();
    {
        var ctx = try Context.of(arena, scratch.allocator(), .{ .module = module, .f = f, .summaries = summaries });
        try ctx.deadStores(&stats);
    }
    _ = scratch.reset(.retain_capacity);
    {
        var ctx = try Context.of(arena, scratch.allocator(), .{ .module = module, .f = f, .summaries = summaries });
        try ctx.narrowStores(&stats);
    }
    return stats;
}

fn hasStores(f: *const ir.Function) bool {
    for (f.insts.items) |inst| if (inst.op == .list_set) return true;
    return false;
}

/// The function and what the rewrites read about the module.
const Input = struct { module: *const ir.Module, f: *ir.Function, summaries: *const effects.Summaries };

/// Blocks, dominators and users of one function's current IR.
const Graph = struct {
    users: []const []const ir.Ref,
    /// Per instruction: its block, or `none` (parameters, constants, unplaced).
    block_of: []u32,
    /// Per block: its immediate dominator (the entry its own), `none` when unreachable.
    idom: []u32,
    /// Per block: its depth in the dominator tree.
    depth: []u32,

    fn of(arena: std.mem.Allocator, f: *const ir.Function) Error!Graph {
        const n = f.blocks.items.len;
        const block_of = try arena.alloc(u32, f.insts.items.len);
        @memset(block_of, none);
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| block_of[ref.index()] = @intCast(b);
        }
        // Reverse postorder from the entry.
        const post = try arena.alloc(u32, n);
        @memset(post, none);
        var order: std.ArrayList(u32) = .empty;
        var stack: std.ArrayList(struct { block: u32, next: u32 }) = .empty;
        const seen = try arena.alloc(bool, n);
        @memset(seen, false);
        if (n != 0) {
            seen[0] = true;
            try stack.append(arena, .{ .block = 0, .next = 0 });
        }
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            const succ = successors(f, top.block);
            if (top.next < succ.len) {
                const s = succ.items[top.next];
                top.next += 1;
                if (!seen[s]) {
                    seen[s] = true;
                    try stack.append(arena, .{ .block = s, .next = 0 });
                }
                continue;
            }
            post[top.block] = @intCast(order.items.len);
            try order.append(arena, top.block);
            _ = stack.pop();
        }
        const idom = try arena.alloc(u32, n);
        @memset(idom, none);
        if (n != 0) idom[0] = 0;
        var changed = true;
        while (changed) {
            changed = false;
            var i = order.items.len;
            while (i > 0) {
                i -= 1;
                const b = order.items[i];
                if (b == 0) continue;
                var chosen: u32 = none;
                for (f.blocks.items[b].preds.items) |pred_id| {
                    const p: u32 = @intCast(pred_id.index());
                    if (idom[p] == none) continue;
                    chosen = if (chosen == none) p else intersect(idom, post, p, chosen);
                }
                if (chosen != none and idom[b] != chosen) {
                    idom[b] = chosen;
                    changed = true;
                }
            }
        }
        const depth = try arena.alloc(u32, n);
        @memset(depth, 0);
        var i = order.items.len;
        while (i > 0) {
            i -= 1;
            const b = order.items[i];
            if (b != 0 and idom[b] != none) depth[b] = depth[idom[b]] + 1;
        }
        return .{ .users = try effects.usersOf(arena, f), .block_of = block_of, .idom = idom, .depth = depth };
    }

    fn intersect(idom: []const u32, post: []const u32, a: u32, b: u32) u32 {
        var x = a;
        var y = b;
        while (x != y) {
            while (post[x] < post[y]) x = idom[x];
            while (post[y] < post[x]) y = idom[y];
        }
        return x;
    }

    /// Whether block `a` dominates block `b` (every block dominates itself).
    fn dominates(self: *const Graph, a: u32, b: u32) bool {
        if (self.idom[b] == none or self.idom[a] == none) return false;
        var at = b;
        while (self.depth[at] > self.depth[a]) at = self.idom[at];
        return at == a;
    }

    /// Whether the definition of `ref` strictly dominates block `b`: it has no block (a
    /// parameter or constant), or its block strictly dominates `b`.
    fn before(self: *const Graph, ref: ir.Ref, b: u32) bool {
        const home = self.block_of[ref.index()];
        if (home == none) return true;
        return home != b and self.dominates(home, b);
    }
};

/// The successors of block `b`: one for a jump, two for a branch.
const Successors = struct {
    items: [2]u32 = .{ 0, 0 },
    len: u32 = 0,
};

fn successors(f: *const ir.Function, b: u32) Successors {
    const insts = f.blocks.items[b].insts.items;
    if (insts.len == 0) return .{};
    const last = f.inst(insts[insts.len - 1]);
    return switch (last.op) {
        .jump => .{ .items = .{ @intCast(last.data), 0 }, .len = 1 },
        .branch => blk: {
            const targets = ir.unpackTargets(last.data);
            const then: u32 = @intCast(targets.then.index());
            const otherwise: u32 = @intCast(targets.otherwise.index());
            if (then == otherwise) break :blk .{ .items = .{ then, 0 }, .len = 1 };
            break :blk .{ .items = .{ then, otherwise }, .len = 2 };
        },
        else => .{},
    };
}

/// A place relative to an SSA value: `root`, then the record fields of `path`.
const Loc = struct { root: ir.Ref, path: effects.Path = .{} };

/// An element index: the integer at `at` plus `addend`, normalized from the end of its
/// list when `from_end` (then it names the same element only in lists of the same length).
const Key = struct { at: Loc, addend: i64 = 0, from_end: bool = false, known: bool = true };

/// Element `key` of the list at `list`.
const Place = struct { list: Loc, key: Key };

/// On the path being followed, `ref` (a `bool`) is `value`.
const Fact = struct { ref: ir.Ref, value: bool };

/// The values `v` is compared with: an element of a list, or one value.
const Target = union(enum) {
    element: Place,
    value: ir.Ref,
};

/// One question of the narrowing proof: in which fields may `v` differ from `target`,
/// given `facts`.
const Query = struct { v: ir.Ref, target: Target, facts: []const Fact };

/// One proof in progress, for the cycles a loop makes.
const Memo = struct { busy: bool, assumed: effects.Paths, hits: u32, result: ?effects.Paths };

/// A list value that may hold the element a store wrote: the value, the record fields
/// from it to the list, the element's index and whether the list's length is unchanged.
const Carrier = struct { ref: ir.Ref, path: effects.Path, key: Key, fixed: bool };

/// The most steps one proof or one forward walk may take before it gives up.
const budget: u32 = 20000;

const Context = struct {
    arena: std.mem.Allocator,
    scratch: std.mem.Allocator,
    input: Input,
    graph: Graph,
    memo: std.AutoHashMapUnmanaged(u64, Memo) = .empty,
    steps: u32 = 0,
    /// How many times a proof has leaned on an assumption still being proved: a result
    /// computed while that happened is provisional and not kept.
    leans: u32 = 0,

    fn of(arena: std.mem.Allocator, scratch: std.mem.Allocator, input: Input) Error!Context {
        return .{ .arena = arena, .scratch = scratch, .input = input, .graph = try Graph.of(scratch, input.f) };
    }

    fn fun(self: *const Context) *ir.Function {
        return self.input.f;
    }

    fn mod(self: *const Context) *const ir.Module {
        return self.input.module;
    }

    // ---- places ------------------------------------------------------------------------

    /// The call and `mut` parameter whose final value `ref` is (the call itself for a
    /// result that is that value, or the one field of the result that holds it), or null.
    fn finalOf(self: *const Context, ref: ir.Ref) ?struct { call: ir.Ref, param: u32 } {
        const f = self.fun();
        const m = self.mod();
        const inst = f.inst(ref);
        const call, const component: ?u32 = switch (inst.op) {
            .call => .{ ref, null },
            .record_get => .{ f.resolve(inst.a), @intCast(inst.data) },
            else => return null,
        };
        const made = f.inst(call);
        if (made.op != .call) return null;
        const signature = m.functions.items[made.a.index()].signature;
        for (0..signature.params.len) |param| {
            const final = effects.finalOf(m, signature, param) orelse continue;
            const matches = switch (final) {
                .whole => component == null,
                .field => |field| component != null and component.? == field,
            };
            if (matches) return .{ .call = call, .param = @intCast(param) };
        }
        return null;
    }

    /// What `facts` say call `call` answered (its declared `bool`), or null.
    fn answer(self: *const Context, call: ir.Ref, facts: []const Fact) ?bool {
        const f = self.fun();
        const m = self.mod();
        const field = effects.declaredBool(m, m.functions.items[f.inst(call).a.index()].signature) orelse return null;
        for (facts) |fact| {
            const inst = f.inst(fact.ref);
            if (inst.op == .record_get and inst.data == field and f.resolve(inst.a) == call) return fact.value;
        }
        return null;
    }

    /// The paths call `call` (to an internal function) may write in its parameter `param`.
    fn callWrites(self: *const Context, call: ir.Ref, param: u32, facts: []const Fact) *const effects.Paths {
        const callee = self.fun().inst(call).a.index();
        return self.input.summaries.writes(callee, param, self.answer(call, facts));
    }

    /// `loc` moved back as far as it names the same bytes: through updates of other fields,
    /// field reads (the path grows at the front), calls that do not write it, and copies.
    fn normalize(self: *const Context, start: Loc, facts: []const Fact) Loc {
        const f = self.fun();
        var loc = start;
        var guard: u32 = 0;
        while (guard < 4096) : (guard += 1) {
            loc.root = f.resolve(loc.root);
            const inst = f.inst(loc.root);
            if (self.finalOf(loc.root)) |final| {
                if (self.callWrites(final.call, final.param, facts).overlaps(loc.path)) break;
                loc.root = f.resolve(f.operands(f.inst(final.call).data)[final.param]);
                continue;
            }
            switch (inst.op) {
                .record_get => {
                    if (loc.path.len >= effects.Path.max_steps) break;
                    loc = .{ .root = inst.a, .path = prepend(@intCast(inst.data), loc.path) };
                },
                .record_set => {
                    if (loc.path.len == 0) break;
                    if (inst.data != loc.path.steps[0]) {
                        loc.root = inst.a;
                    } else loc = .{ .root = inst.b, .path = tail(loc.path) };
                },
                .list_copy => {
                    if (loc.path.len != 0) break;
                    loc.root = inst.a;
                },
                else => break,
            }
        }
        return loc;
    }

    fn sameLoc(self: *const Context, a: Loc, b: Loc) bool {
        if (!std.meta.eql(a.path, b.path)) return false;
        const f = self.fun();
        const x = f.resolve(a.root);
        const y = f.resolve(b.root);
        if (x == y) return true;
        const ix = f.inst(x);
        const iy = f.inst(y);
        return ix.op == .iconst and iy.op == .iconst and ix.ty == iy.ty and ix.data == iy.data;
    }

    fn sameKey(self: *const Context, a: Key, b: Key) bool {
        if (!a.known or !b.known) return false;
        return a.addend == b.addend and a.from_end == b.from_end and self.sameLoc(a.at, b.at);
    }

    /// The index `index` of an access to `list`: its integer before normalization from the
    /// end (`i < 0 ? len(list) + i : i`), split into a base and a constant.
    fn keyOf(self: *const Context, index: ir.Ref, list: ir.Ref, facts: []const Fact) Key {
        const f = self.fun();
        var raw = f.resolve(index);
        var from_end = false;
        if (self.fromEnd(raw, f.resolve(list))) |original| {
            raw = original;
            from_end = true;
        }
        var addend: i64 = 0;
        const inst = f.inst(raw);
        if ((inst.op == .add or inst.op == .sub) and inst.ty == .i64) {
            const rhs = f.inst(f.resolve(inst.b));
            const lhs = f.inst(f.resolve(inst.a));
            if (rhs.op == .iconst) {
                const c: i64 = @bitCast(rhs.data);
                addend = if (inst.op == .sub) -%c else c;
                raw = f.resolve(inst.a);
            } else if (inst.op == .add and lhs.op == .iconst) {
                addend = @bitCast(lhs.data);
                raw = f.resolve(inst.b);
            }
        }
        return .{ .at = self.normalize(.{ .root = raw }, facts), .addend = addend, .from_end = from_end };
    }

    /// When `index` is the builder's normalization of an index into `list` from its end,
    /// `phi(i, len(list) + i)`, the original `i`.
    fn fromEnd(self: *const Context, index: ir.Ref, list: ir.Ref) ?ir.Ref {
        const f = self.fun();
        const inst = f.inst(index);
        if (inst.op != .phi) return null;
        const operands = f.operands(inst.data);
        if (operands.len != 2) return null;
        for ([_][2]usize{ .{ 0, 1 }, .{ 1, 0 } }) |pair| {
            const original = f.resolve(operands[pair[0]]);
            const sum = f.inst(f.resolve(operands[pair[1]]));
            if (sum.op != .add) continue;
            const x = f.resolve(sum.a);
            const y = f.resolve(sum.b);
            const length = if (y == original) x else if (x == original) y else continue;
            var len_inst = f.inst(length);
            if (len_inst.op == .convert) len_inst = f.inst(f.resolve(len_inst.a));
            if (len_inst.op != .list_len) continue;
            // The length of the list accessed, or of the same list read again.
            const measured = f.resolve(len_inst.a);
            if (measured == list or self.sameLoc(self.normalize(.{ .root = measured }, &.{}), self.normalize(.{ .root = list }, &.{}))) return original;
        }
        return null;
    }

    /// The element an access `(list, index)` names.
    fn placeOf(self: *const Context, list: ir.Ref, index: ir.Ref, facts: []const Fact) Place {
        return .{ .list = self.normalize(.{ .root = list }, facts), .key = self.keyOf(index, list, facts) };
    }

    // ---- branch facts --------------------------------------------------------------------

    /// Add `fact` to `list` (with what a `not` implies); false when it contradicts one there.
    fn addFact(self: *const Context, list: *std.ArrayList(Fact), fact: Fact) Error!bool {
        const f = self.fun();
        var current = fact;
        var guard: u32 = 0;
        while (guard < 8) : (guard += 1) {
            current.ref = f.resolve(current.ref);
            for (list.items) |known| {
                if (known.ref == current.ref) {
                    if (known.value != current.value) return false;
                    return true;
                }
            }
            const inst = f.inst(current.ref);
            if (inst.op == .iconst) return (inst.data != 0) == current.value;
            try list.append(self.scratch, current);
            if (inst.op != .not) return true;
            current = .{ .ref = inst.a, .value = !current.value };
        }
        return true;
    }

    /// The facts that hold on the edge into block `j` from its predecessor number `i`, given
    /// `facts` before it: facts on `j`'s phis become facts on their operands on that edge (a
    /// constant that contradicts makes the edge impossible: null), facts on values defined
    /// before `j` stay, the rest are dropped; then the branch conditions that lead to the edge.
    fn across(self: *const Context, facts: []const Fact, j: u32, i: usize) Error!?[]const Fact {
        const f = self.fun();
        var out: std.ArrayList(Fact) = .empty;
        for (facts) |fact| {
            const inst = f.inst(fact.ref);
            if (inst.op == .phi and self.graph.block_of[fact.ref.index()] == j) {
                if (!try self.addFact(&out, .{ .ref = f.operands(inst.data)[i], .value = fact.value })) return null;
            } else if (self.graph.before(fact.ref, j)) {
                if (!try self.addFact(&out, fact)) return null;
            }
        }
        // The edge itself, then the chain of single-predecessor blocks above it.
        var child = j;
        var parent: u32 = @intCast(f.blocks.items[j].preds.items[i].index());
        var guard: u32 = 0;
        while (guard < 16) : (guard += 1) {
            const insts = f.blocks.items[parent].insts.items;
            const last = f.inst(insts[insts.len - 1]);
            if (last.op == .branch) {
                const targets = ir.unpackTargets(last.data);
                const then: u32 = @intCast(targets.then.index());
                const otherwise: u32 = @intCast(targets.otherwise.index());
                if (then != otherwise) {
                    if (!try self.addFact(&out, .{ .ref = last.a, .value = then == child })) return null;
                }
            }
            const preds = f.blocks.items[parent].preds.items;
            if (preds.len != 1) break;
            child = parent;
            parent = @intCast(preds[0].index());
        }
        return out.items;
    }

    // ---- dead and sunk stores -----------------------------------------------------------

    fn deadStores(self: *Context, stats: *Stats) Error!void {
        const f = self.fun();
        var stores: std.ArrayList(ir.Ref) = .empty;
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                if (f.inst(ref).op != .list_set) continue;
                // A store paired with a read that took its slot's owner puts that owner back:
                // it is never removed, moved or narrowed.
                if (flags.transferredSlot(f, f.inst(ref))) continue;
                try stores.append(self.scratch, ref);
            }
        }
        // Later stores first: a store a later one overwrites goes once that one has settled.
        std.mem.reverse(ir.Ref, stores.items);
        for (stores.items) |store| try self.deadStore(store, stats);
    }

    /// The list a store writes, then the records it is put back into in its block, each the
    /// one use of the one before: `[store, record_set(…, store), record_set(…, that), …]`.
    fn chainOf(self: *Context, store: ir.Ref) Error![]const ir.Ref {
        const f = self.fun();
        var chain: std.ArrayList(ir.Ref) = .empty;
        try chain.append(self.scratch, store);
        const b = self.graph.block_of[store.index()];
        while (chain.items.len < effects.Path.max_steps) {
            const top = chain.items[chain.items.len - 1];
            const users = self.graph.users[top.index()];
            if (users.len != 1) break;
            const user = users[0];
            const inst = f.inst(user);
            if (inst.op != .record_set or f.resolve(inst.b) != top or f.resolve(inst.a) == top) break;
            if (self.graph.block_of[user.index()] != b) break;
            try chain.append(self.scratch, user);
        }
        return chain.items;
    }

    fn deadStore(self: *Context, store: ir.Ref, stats: *Stats) Error!void {
        const f = self.fun();
        const inst = f.inst(store);
        const start: Carrier = .{ .ref = store, .path = .{}, .key = self.keyOf(inst.b, inst.a, &.{}), .fixed = true };
        self.steps = 0;
        if (try self.unobserved(start, null)) {
            try self.removeStore(store);
            stats.removed += 1;
            self.graph = try Graph.of(self.scratch, f);
            return;
        }
        // Sinking: the chain ends its block's work, and each successor either observes the
        // store (it moves there) or does not (it goes without).
        const chain = try self.chainOf(store);
        const top = chain[chain.len - 1];
        const b = self.graph.block_of[store.index()];
        const succ = successors(f, b);
        if (succ.len < 2) return;
        for (succ.items[0..succ.len]) |s| if (f.blocks.items[s].preds.items.len != 1) return;
        // Every use of the chain's last value lies under one successor.
        for (self.graph.users[top.index()]) |user| {
            if (self.regionOfUse(top, user, succ) == null) return;
        }
        for (chain[0 .. chain.len - 1], 0..) |member, k| {
            if (self.graph.users[member.index()].len != 1 or self.graph.users[member.index()][0] != chain[k + 1]) return;
        }
        var dead_in: [2]bool = .{ false, false };
        var any = false;
        for (succ.items[0..succ.len], 0..) |s, k| {
            self.steps = 0;
            const carried: Carrier = .{ .ref = top, .path = try self.chainPath(chain), .key = start.key, .fixed = true };
            dead_in[k] = try self.unobserved(carried, s);
            any = any or dead_in[k];
        }
        if (!any) return;
        try self.sink(chain, succ, dead_in);
        stats.sunk += 1;
        self.graph = try Graph.of(self.scratch, f);
    }

    /// The record fields from the chain's last value down to the stored list.
    fn chainPath(self: *Context, chain: []const ir.Ref) Error!effects.Path {
        const f = self.fun();
        var path: effects.Path = .{};
        var k = chain.len;
        while (k > 1) {
            k -= 1;
            path = effects.child(path, @intCast(f.inst(chain[k]).data));
        }
        return path;
    }

    /// Which successor (index into `succ`) a use of `value` by `user` lies under, or null
    /// when it lies under none or under both.
    fn regionOfUse(self: *const Context, value: ir.Ref, user: ir.Ref, succ: Successors) ?usize {
        const f = self.fun();
        const inst = f.inst(user);
        var found: ?usize = null;
        if (inst.op == .phi) {
            const j = self.graph.block_of[user.index()];
            for (f.operands(inst.data), f.blocks.items[j].preds.items) |operand, pred| {
                if (f.resolve(operand) != value) continue;
                const k = self.under(@intCast(pred.index()), succ) orelse return null;
                if (found != null and found.? != k) return null;
                found = k;
            }
            return found;
        }
        return self.under(self.graph.block_of[user.index()], succ);
    }

    fn under(self: *const Context, block: u32, succ: Successors) ?usize {
        if (block == none) return null;
        var found: ?usize = null;
        for (succ.items[0..succ.len], 0..) |s, k| {
            if (!self.graph.dominates(s, block)) continue;
            if (found != null) return null;
            found = k;
        }
        return found;
    }

    /// Whether nothing can read the element `start` holds before a store of the same
    /// element overwrites it. With `region`, only uses of `start.ref` under that block count
    /// at first (the successor a sunk store would move to).
    fn unobserved(self: *Context, start: Carrier, region: ?u32) Error!bool {
        var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
        var work: std.ArrayList(Carrier) = .empty;
        try work.append(self.scratch, start);
        var first = true;
        while (work.pop()) |carrier| {
            const key = carrierHash(carrier);
            if ((try seen.getOrPut(self.scratch, key)).found_existing) continue;
            self.steps += 1;
            if (self.steps > budget) return false;
            const filter = if (first) region else null;
            first = false;
            if (!try self.follow(carrier, filter, &work)) return false;
        }
        return true;
    }

    /// Push what each use of `carrier` passes the element on to; false at an observation.
    fn follow(self: *Context, carrier: Carrier, region: ?u32, work: *std.ArrayList(Carrier)) Error!bool {
        const f = self.fun();
        for (self.graph.users[carrier.ref.index()]) |user| {
            const inst = f.inst(user);
            if (region) |s| {
                const at = if (inst.op == .phi) null else self.graph.block_of[user.index()];
                if (at) |block| {
                    if (!self.graph.dominates(s, block)) continue;
                }
            }
            const operands = f.valueOperands(inst);
            for (0..operands.len()) |k| {
                if (f.resolve(operands.get(k)) != carrier.ref) continue;
                if (!try self.useOf(carrier, user, k, region, work)) return false;
            }
        }
        return true;
    }

    fn useOf(self: *Context, carrier: Carrier, user: ir.Ref, k: usize, region: ?u32, work: *std.ArrayList(Carrier)) Error!bool {
        const f = self.fun();
        const m = self.mod();
        const inst = f.inst(user);
        const path = carrier.path;
        switch (inst.op) {
            .record_get => {
                if (path.len == 0 or inst.data != path.steps[0]) return true;
                try work.append(self.scratch, .{ .ref = user, .path = tail(path), .key = carrier.key, .fixed = carrier.fixed });
            },
            .record_set => {
                if (k == 1) {
                    if (path.len >= effects.Path.max_steps) return false;
                    try work.append(self.scratch, .{ .ref = user, .path = prepend(@intCast(inst.data), path), .key = carrier.key, .fixed = carrier.fixed });
                    return true;
                }
                if (path.len == 0) return false;
                // The field that holds the list is replaced: whatever replaces it carries on
                // through its own uses.
                if (inst.data == path.steps[0]) return true;
                try work.append(self.scratch, .{ .ref = user, .path = path, .key = carrier.key, .fixed = carrier.fixed });
            },
            .list_set => {
                if (k != 0 or path.len != 0) return false;
                const key = self.keyOf(inst.b, inst.a, &.{});
                const overwrites = self.sameKey(key, carrier.key) and (!key.from_end or carrier.fixed);
                if (!overwrites) try work.append(self.scratch, .{ .ref = user, .path = path, .key = carrier.key, .fixed = carrier.fixed });
            },
            .list_set_field => {
                if (k != 0 or path.len != 0) return false;
                try work.append(self.scratch, .{ .ref = user, .path = path, .key = carrier.key, .fixed = carrier.fixed });
            },
            .list_len => if (path.len != 0) return false,
            // An element read nothing uses is only its bounds check, and a trap observes nothing.
            .list_get, .list_get_field => if (inst.data != 0 or self.graph.users[user.index()].len != 0) return false,
            .list_push, .list_pop => {
                if (k != 0 or path.len != 0) return false;
                try work.append(self.scratch, .{ .ref = user, .path = path, .key = carrier.key, .fixed = false });
            },
            .list_copy => try work.append(self.scratch, .{ .ref = user, .path = path, .key = carrier.key, .fixed = carrier.fixed }),
            .phi => {
                const j = self.graph.block_of[user.index()];
                for (f.operands(inst.data), f.blocks.items[j].preds.items, 0..) |operand, pred, i| {
                    if (f.resolve(operand) != carrier.ref) continue;
                    if (region) |s| if (!self.graph.dominates(s, @intCast(pred.index()))) continue;
                    try work.append(self.scratch, .{ .ref = user, .path = path, .key = self.keyAcross(carrier, j, i), .fixed = carrier.fixed });
                }
            },
            .call => {
                const callee = inst.a.index();
                if (m.functions.items[callee].signature.linkage != .internal) return false;
                const effect = self.input.summaries.of(callee, k);
                if (effect.reads.overlaps(path)) return false;
                const final = effects.finalOf(m, m.functions.items[callee].signature, k) orelse return true;
                const fixed = carrier.fixed and !effect.writes.overlaps(path);
                switch (final) {
                    .whole => try work.append(self.scratch, .{ .ref = user, .path = path, .key = carrier.key, .fixed = fixed }),
                    .field => |field| for (self.graph.users[user.index()]) |reader| {
                        const got = f.inst(reader);
                        if (got.op != .record_get) return false;
                        if (got.data == field) try work.append(self.scratch, .{ .ref = reader, .path = path, .key = carrier.key, .fixed = fixed });
                    },
                }
            },
            .retain, .release, .is_unique => {},
            else => return false,
        }
        return true;
    }

    /// The element's index after the carrier crosses into block `j` from predecessor `i`:
    /// an index read from a record that crosses the edge in a phi of `j` is read from that
    /// phi; one defined before `j` stays; any other is no longer known.
    fn keyAcross(self: *const Context, carrier: Carrier, j: u32, i: usize) Key {
        var key = carrier.key;
        if (!key.known) return key;
        const f = self.fun();
        for (f.blocks.items[j].insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op != .phi) break;
            const operand = f.operands(inst.data)[i];
            const moved = self.normalize(.{ .root = operand, .path = key.at.path }, &.{});
            if (self.sameLoc(moved, key.at)) {
                key.at = .{ .root = ref, .path = key.at.path };
                return key;
            }
        }
        if (self.graph.before(key.at.root, j)) return key;
        key.known = false;
        return key;
    }

    /// The bounds check of `store` stays at its place, as an element read nothing uses.
    fn checkOnly(self: *Context, store: ir.Inst) Error!?ir.Ref {
        if (store.check != .exact) return null;
        const f = self.fun();
        const element = self.mod().compound(store.ty).list;
        const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
        try f.insts.append(self.arena, .{ .op = .list_get, .ty = element, .a = store.a, .b = store.b, .check = .exact, .span = store.span });
        return ref;
    }

    /// Replace `store` by its list, keeping its bounds check; the records it was put back into
    /// then put back the list unchanged.
    fn removeStore(self: *Context, store: ir.Ref) Error!void {
        const f = self.fun();
        const inst = f.inst(store);
        const b = self.graph.block_of[store.index()];
        const check = try self.checkOnly(inst);
        f.insts.items[store.index()] = .{ .op = .copy, .ty = inst.ty, .a = inst.a, .span = inst.span };
        if (check) |read| try self.insertBefore(b, store, read);
    }

    fn insertBefore(self: *Context, b: u32, at: ir.Ref, new: ir.Ref) Error!void {
        const list = &self.fun().blocks.items[b].insts;
        const pos = std.mem.indexOfScalar(ir.Ref, list.items, at).?;
        try list.insert(self.arena, pos, new);
        if (new.index() >= self.graph.block_of.len) return;
        self.graph.block_of[new.index()] = b;
    }

    /// Move the store chain out of its block: a copy of it starts each successor that observes
    /// it, the uses under each other successor take the values without the store, and the
    /// bounds check stays.
    fn sink(self: *Context, chain: []const ir.Ref, succ: Successors, dead_in: [2]bool) Error!void {
        const f = self.fun();
        const store = chain[0];
        const top = chain[chain.len - 1];
        const b = self.graph.block_of[store.index()];
        // The uses of the chain's value, by successor, before anything moves.
        var uses: [2]std.ArrayList(ir.Ref) = .{ .empty, .empty };
        for (self.graph.users[top.index()]) |user| {
            const k = self.regionOfUse(top, user, succ).?;
            try uses[k].append(self.scratch, user);
        }
        for (succ.items[0..succ.len], 0..) |s, k| {
            if (uses[k].items.len == 0) continue;
            const replacement = if (dead_in[k]) try self.unstored(chain, s) else try self.cloneChain(chain, s);
            for (uses[k].items) |user| self.replaceUse(user, top, replacement, s);
        }
        // Out of the block: the chain goes, the bounds check stays.
        const inst = f.inst(store);
        const check = try self.checkOnly(inst);
        var kept: std.ArrayList(ir.Ref) = .empty;
        for (f.blocks.items[b].insts.items) |ref| {
            if (ref == store) {
                if (check) |read| try kept.append(self.arena, read);
                continue;
            }
            if (std.mem.indexOfScalar(ir.Ref, chain, ref) != null) continue;
            try kept.append(self.arena, ref);
        }
        f.blocks.items[b].insts = kept;
    }

    /// Insert `inst` at the start of block `s` (after its phis); returns its value.
    fn emitAtStart(self: *Context, s: u32, inst: ir.Inst, after: *usize) Error!ir.Ref {
        const f = self.fun();
        const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
        try f.insts.append(self.arena, inst);
        try f.blocks.items[s].insts.insert(self.arena, after.*, ref);
        after.* += 1;
        return ref;
    }

    fn startOf(self: *const Context, s: u32) usize {
        const f = self.fun();
        var pos: usize = 0;
        for (f.blocks.items[s].insts.items) |ref| {
            if (f.inst(ref).op != .phi) break;
            pos += 1;
        }
        return pos;
    }

    /// A copy of the store chain at the start of `s`; returns its last value.
    fn cloneChain(self: *Context, chain: []const ir.Ref, s: u32) Error!ir.Ref {
        const f = self.fun();
        var at = self.startOf(s);
        // The records each level is put back into, read again here when the level below was
        // read from them: the read and its write-back then share a block, so the update takes
        // the field over (`own.zig` `takeFields`) instead of copying it.
        const records = try self.scratch.alloc(ir.Ref, chain.len);
        records[chain.len - 1] = f.inst(chain[chain.len - 1]).a;
        var level = chain.len - 1;
        while (level > 1) {
            level -= 1;
            records[level] = try self.reread(f.inst(chain[level]).a, f.inst(chain[level + 1]), records[level + 1], s, &at);
        }
        const store = f.inst(chain[0]);
        var copy = store;
        if (chain.len > 1) copy.a = try self.reread(store.a, f.inst(chain[1]), records[1], s, &at);
        const extra_start: u32 = @intCast(f.extra.items.len);
        try f.extra.appendSlice(self.arena, f.operands(store.data));
        copy.data = (ir.ExtraSlice{ .start = extra_start, .len = @intCast(f.operands(store.data).len) }).pack();
        var previous = try self.emitAtStart(s, copy, &at);
        for (chain[1..], 1..) |member, k| {
            var wrap = f.inst(member);
            wrap.a = records[k];
            wrap.b = previous;
            previous = try self.emitAtStart(s, wrap, &at);
        }
        return previous;
    }

    /// `value` read again from `fresh` at the start of `s` when it is the field `wrap` puts
    /// back, read from the record `wrap` updates; else `value` itself.
    fn reread(self: *Context, value: ir.Ref, wrap: ir.Inst, fresh: ir.Ref, s: u32, at: *usize) Error!ir.Ref {
        const f = self.fun();
        const read = f.inst(f.resolve(value));
        if (read.op != .record_get or read.data != wrap.data or f.resolve(read.a) != f.resolve(wrap.a)) return value;
        return self.emitAtStart(s, .{ .op = .record_get, .ty = read.ty, .a = fresh, .data = read.data, .span = read.span }, at);
    }

    /// The chain's last value without the store: each record the list was put back into is
    /// the record before, when the list put back is the one read from it, or else that
    /// record with the unchanged value put back.
    fn unstored(self: *Context, chain: []const ir.Ref, s: u32) Error!ir.Ref {
        const f = self.fun();
        var at = self.startOf(s);
        var previous = f.resolve(f.inst(chain[0]).a);
        for (chain[1..]) |member| {
            const wrap = f.inst(member);
            const read = f.inst(previous);
            const same = read.op == .record_get and f.resolve(read.a) == f.resolve(wrap.a) and read.data == wrap.data;
            if (same) {
                previous = f.resolve(wrap.a);
                continue;
            }
            var put = wrap;
            put.b = previous;
            previous = try self.emitAtStart(s, put, &at);
        }
        return previous;
    }

    /// Replace `old` by `new` in the operands of `user` (a phi only on edges from under `s`).
    fn replaceUse(self: *Context, user: ir.Ref, old: ir.Ref, new: ir.Ref, s: u32) void {
        const f = self.fun();
        const inst = &f.insts.items[user.index()];
        if (inst.op == .phi) {
            const j = self.graph.block_of[user.index()];
            const operands = ir.ExtraSlice.unpack(inst.data);
            for (f.extra.items[operands.start..][0..operands.len], f.blocks.items[j].preds.items) |*operand, pred| {
                if (f.resolve(operand.*) == old and self.graph.dominates(s, @intCast(pred.index()))) operand.* = new;
            }
            return;
        }
        if (inst.a != .none and f.resolve(inst.a) == old) inst.a = new;
        if (inst.b != .none and f.resolve(inst.b) == old) inst.b = new;
        if (inst.op.hasExtra()) {
            const operands = ir.ExtraSlice.unpack(inst.data);
            for (f.extra.items[operands.start..][0..operands.len]) |*operand| {
                if (f.resolve(operand.*) == old) operand.* = new;
            }
        }
    }

    // ---- narrowed stores ----------------------------------------------------------------

    fn narrowStores(self: *Context, stats: *Stats) Error!void {
        const f = self.fun();
        const m = self.mod();
        var stores: std.ArrayList(ir.Ref) = .empty;
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op != .list_set) continue;
                if (m.kind(m.compound(inst.ty).list) != .record) continue;
                if (flags.transferredSlot(f, inst)) continue;
                try stores.append(self.scratch, ref);
            }
        }
        // Every proof is made against the stores as written; a narrowed store writes the same
        // list value, so the proofs still hold once the stores are rewritten.
        var plans: std.ArrayList(struct { store: ir.Ref, changed: effects.Paths }) = .empty;
        for (stores.items) |store| {
            const inst = f.inst(store);
            self.steps = 0;
            self.memo = .empty;
            const query: Query = .{ .v = f.operands(inst.data)[0], .target = .{ .element = self.placeOf(inst.a, inst.b, &.{}) }, .facts = &.{} };
            const changed = (try self.diff(query)) orelse continue;
            if (!self.narrowable(inst, &changed)) continue;
            try plans.append(self.scratch, .{ .store = store, .changed = changed });
        }
        for (plans.items) |plan| {
            try self.narrow(plan.store, &plan.changed);
            stats.narrowed += 1;
        }
    }

    /// Whether storing only `changed` beats storing the whole element: not every field, and
    /// each path reaches through records only.
    fn narrowable(self: *const Context, store: ir.Inst, changed: *const effects.Paths) bool {
        const m = self.mod();
        if (changed.whole) return false;
        const element = m.compound(store.ty).list;
        const fields = m.compound(element).record;
        var top_level: u64 = 0;
        for (changed.items.items) |path| {
            var current = element;
            for (path.slice()) |step| {
                if (m.kind(current) != .record) return false;
                const record = m.compound(current).record;
                if (step >= record.len) return false;
                current = record[step];
            }
            if (path.len == 1 and path.steps[0] < 64) top_level |= @as(u64, 1) << @intCast(path.steps[0]);
        }
        return fields.len > 64 or @popCount(top_level) < fields.len;
    }

    /// Rewrite `store` into one `list_set_field` per changed path (or none: the list itself,
    /// with the bounds check kept).
    fn narrow(self: *Context, store: ir.Ref, changed: *const effects.Paths) Error!void {
        const f = self.fun();
        const m = self.mod();
        const inst = f.inst(store);
        const b = self.graph.block_of[store.index()];
        const value = f.operands(inst.data)[0];
        if (changed.items.items.len == 0) {
            try self.removeStore(store);
            return;
        }
        const element = m.compound(inst.ty).list;
        var list = inst.a;
        for (changed.items.items, 0..) |path, n| {
            // The changed field, read out of the stored value.
            var part = value;
            var current = element;
            for (path.slice()) |step| {
                const field_type = m.compound(current).record[step];
                const read: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
                try f.insts.append(self.arena, .{ .op = .record_get, .ty = field_type, .a = part, .data = step, .span = inst.span });
                try self.insertBefore(b, store, read);
                part = read;
                current = field_type;
            }
            const constant: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
            try f.insts.append(self.arena, .{ .op = .iconst, .ty = .u64, .data = path.pack() });
            const extra_start: u32 = @intCast(f.extra.items.len);
            try f.extra.appendSlice(self.arena, &.{ part, constant });
            const field_store: ir.Inst = .{ .op = .list_set_field, .ty = inst.ty, .a = list, .b = inst.b, .data = (ir.ExtraSlice{ .start = extra_start, .len = 2 }).pack(), .check = inst.check, .span = inst.span };
            if (n + 1 == changed.items.items.len) {
                f.insts.items[store.index()] = field_store;
            } else {
                const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
                try f.insts.append(self.arena, field_store);
                try self.insertBefore(b, store, ref);
                list = ref;
            }
        }
    }

    /// The fields in which `query.v` may differ from its target, or null when that cannot be shown.
    fn diff(self: *Context, given: Query) Error!?effects.Paths {
        self.steps += 1;
        if (self.steps > budget) return null;
        const f = self.fun();
        var query = given;
        query.v = f.resolve(query.v);
        switch (query.target) {
            .value => |w| query.target = .{ .value = f.resolve(w) },
            .element => |place| {
                var normalized = place;
                normalized.list = self.normalize(place.list, query.facts);
                normalized.key.at = self.normalize(place.key.at, query.facts);
                query.target = .{ .element = normalized };
                // The element a store wrote is the value it stored. Any other element of a
                // store's list is named only by an access to that very list.
                if (normalized.list.path.len == 0) {
                    const source = f.inst(normalized.list.root);
                    if (source.op == .list_set and self.sameKey(self.keyOf(source.b, source.a, query.facts), normalized.key)) {
                        query.target = .{ .value = f.resolve(f.operands(source.data)[0]) };
                    }
                }
            },
        }
        const key = self.queryHash(query);
        if (self.memo.getPtr(key)) |memo| {
            if (memo.busy) {
                memo.hits += 1;
                self.leans += 1;
                const assumed = try memo.assumed.clone(self.scratch);
                return assumed;
            }
            return if (memo.result) |known| try known.clone(self.scratch) else null;
        }
        try self.memo.put(self.scratch, key, .{ .busy = true, .assumed = .{}, .hits = 0, .result = null });
        var rounds: u32 = 0;
        while (true) : (rounds += 1) {
            const leaned = self.leans;
            const result = try self.walkBack(query);
            const memo = self.memo.getPtr(key).?;
            const settled = result == null or memo.hits == 0 or covered(&memo.assumed, &result.?);
            if (settled or rounds >= 4) {
                const outcome: ?effects.Paths = if (settled) result else null;
                // Only an answer that leaned on no assumption but its own is kept.
                if (self.leans - leaned > memo.hits) {
                    _ = self.memo.remove(key);
                } else {
                    memo.busy = false;
                    memo.result = outcome;
                }
                return outcome;
            }
            memo.assumed = result.?;
            memo.hits = 0;
        }
    }

    /// One step of `diff`: walk `v` back by its definition, or split at a phi block.
    fn walkBack(self: *Context, query: Query) Error!?effects.Paths {
        const f = self.fun();
        const v = query.v;
        if (query.target == .value and query.target.value == v) return effects.Paths{};
        // The latest block that defines a phi the query names: the query is split there.
        if (self.splitBlock(query)) |j| return self.split(query, j);
        const inst = f.inst(v);
        if (self.finalOf(v)) |final| {
            const written = self.callWrites(final.call, final.param, query.facts);
            if (written.whole) return null;
            const argument = f.operands(f.inst(final.call).data)[final.param];
            var rest = (try self.diff(.{ .v = argument, .target = query.target, .facts = query.facts })) orelse return null;
            _ = try rest.addUnder(self.scratch, effects.whole_path, written);
            return rest;
        }
        switch (inst.op) {
            .record_set => {
                var rest = (try self.diff(.{ .v = inst.a, .target = query.target, .facts = query.facts })) orelse return null;
                // `v.f.g = x` changes only `f.g`: the new `f` is the old one, updated.
                var nested: effects.Paths = .{};
                const field = effects.child(.{}, @intCast(inst.data));
                if (try self.nestedChanges(.{ .record = inst.a, .field = @intCast(inst.data), .value = inst.b, .prefix = field }, &nested)) {
                    _ = try rest.addUnder(self.scratch, effects.whole_path, &nested);
                } else _ = try rest.add(self.scratch, field);
                return rest;
            },
            .list_get => {
                if (query.target != .element or inst.data != 0) return null;
                const place = self.placeOf(inst.a, inst.b, query.facts);
                if (!self.sameLoc(place.list, query.target.element.list)) return null;
                if (!self.sameKey(place.key, query.target.element.key)) return null;
                return effects.Paths{};
            },
            else => return null,
        }
    }

    /// A field `value` stored as field `field` of `record`, at `prefix` inside the element.
    const Nested = struct { record: ir.Ref, field: u32, value: ir.Ref, prefix: effects.Path };

    /// Add to `out` the paths under `nested.prefix` where `nested.value` may differ from
    /// `record`'s old field: none when it is that field, its updates' fields when it is that
    /// field updated; false when it is anything else.
    fn nestedChanges(self: *Context, nested: Nested, out: *effects.Paths) Error!bool {
        const f = self.fun();
        const value = f.resolve(nested.value);
        const inst = f.inst(value);
        if (inst.op == .record_get and inst.data == nested.field and f.resolve(inst.a) == f.resolve(nested.record)) return true;
        if (inst.op != .record_set or nested.prefix.len >= effects.Path.max_steps) return false;
        if (!try self.nestedChanges(.{ .record = nested.record, .field = nested.field, .value = inst.a, .prefix = nested.prefix }, out)) return false;
        const deeper = effects.child(nested.prefix, @intCast(inst.data));
        if (!try self.nestedChanges(.{ .record = inst.a, .field = @intCast(inst.data), .value = inst.b, .prefix = deeper }, out)) _ = try out.add(self.scratch, deeper);
        return true;
    }

    /// The block to split `query` at: the phi among the values it names (`v`, the list's and
    /// the index's roots) whose block every other's definition dominates; null when `v` is
    /// not a phi and no such phi is defined after `v`.
    fn splitBlock(self: *const Context, query: Query) ?u32 {
        const f = self.fun();
        var candidate: ?u32 = null;
        var refs: [3]ir.Ref = .{ query.v, .none, .none };
        switch (query.target) {
            .value => |w| refs[1] = w,
            .element => |place| {
                refs[1] = place.list.root;
                refs[2] = place.key.at.root;
            },
        }
        for (refs) |ref| {
            if (ref == .none) continue;
            if (f.inst(ref).op != .phi) continue;
            const j = self.graph.block_of[ref.index()];
            if (j == none) continue;
            if (candidate) |c| {
                if (c != j and self.graph.dominates(c, j)) candidate = j;
            } else candidate = j;
        }
        const j = candidate orelse return null;
        if (f.inst(query.v).op == .phi and self.graph.block_of[query.v.index()] == j) return j;
        // `v` is not one of `j`'s phis: split there only when `v` is defined before `j`.
        return if (self.graph.before(query.v, j)) j else null;
    }

    fn split(self: *Context, query: Query, j: u32) Error!?effects.Paths {
        const f = self.fun();
        // Every value the query names is one of `j`'s phis or defined before `j`.
        var refs: [3]ir.Ref = .{ query.v, .none, .none };
        switch (query.target) {
            .value => |w| refs[1] = w,
            .element => |place| {
                refs[1] = place.list.root;
                refs[2] = place.key.at.root;
            },
        }
        for (refs) |ref| {
            if (ref == .none) continue;
            const is_phi = f.inst(ref).op == .phi and self.graph.block_of[ref.index()] == j;
            if (!is_phi and !self.graph.before(ref, j)) return null;
        }
        var total: effects.Paths = .{};
        for (f.blocks.items[j].preds.items, 0..) |_, i| {
            const facts = (try self.across(query.facts, j, i)) orelse continue;
            var next = query;
            next.facts = facts;
            next.v = self.operandOn(query.v, j, i);
            switch (query.target) {
                .value => |w| next.target = .{ .value = self.operandOn(w, j, i) },
                .element => |place| {
                    var moved = place;
                    moved.list.root = self.operandOn(place.list.root, j, i);
                    moved.key.at.root = self.operandOn(place.key.at.root, j, i);
                    next.target = .{ .element = moved };
                },
            }
            const part = (try self.diff(next)) orelse return null;
            _ = try total.addUnder(self.scratch, effects.whole_path, &part);
        }
        return total;
    }

    /// `ref`'s value on the edge into block `j` from predecessor `i`: its operand there when it
    /// is one of `j`'s phis, else itself.
    fn operandOn(self: *const Context, ref: ir.Ref, j: u32, i: usize) ir.Ref {
        const f = self.fun();
        if (ref == .none) return ref;
        const inst = f.inst(ref);
        if (inst.op != .phi or self.graph.block_of[ref.index()] != j) return ref;
        return f.resolve(f.operands(inst.data)[i]);
    }

    fn queryHash(self: *const Context, query: Query) u64 {
        _ = self;
        var h = std.hash.Wyhash.init(0);
        h.update(std.mem.asBytes(&query.v));
        switch (query.target) {
            .value => |w| {
                h.update("v");
                h.update(std.mem.asBytes(&w));
            },
            .element => |place| {
                h.update("e");
                h.update(std.mem.asBytes(&place.list.root));
                h.update(std.mem.asBytes(&place.list.path.pack()));
                h.update(std.mem.asBytes(&place.key.at.root));
                h.update(std.mem.asBytes(&place.key.at.path.pack()));
                h.update(std.mem.asBytes(&place.key.addend));
                h.update(&.{ @intFromBool(place.key.from_end), @intFromBool(place.key.known) });
            },
        }
        for (query.facts) |fact| {
            h.update(std.mem.asBytes(&fact.ref));
            h.update(&.{@intFromBool(fact.value)});
        }
        return h.final();
    }
};

/// Whether `outer` covers every path of `inner`.
fn covered(outer: *const effects.Paths, inner: *const effects.Paths) bool {
    if (outer.whole) return true;
    if (inner.whole) return false;
    for (inner.items.items) |path| if (!outer.covers(path)) return false;
    return true;
}

fn carrierHash(carrier: Carrier) u64 {
    var h = std.hash.Wyhash.init(0);
    h.update(std.mem.asBytes(&carrier.ref));
    h.update(std.mem.asBytes(&carrier.path.pack()));
    h.update(std.mem.asBytes(&carrier.key.at.root));
    h.update(std.mem.asBytes(&carrier.key.at.path.pack()));
    h.update(std.mem.asBytes(&carrier.key.addend));
    h.update(&.{ @intFromBool(carrier.key.from_end), @intFromBool(carrier.key.known), @intFromBool(carrier.fixed) });
    return h.final();
}

/// `step` followed by the steps of `path` (the last one dropped past `Path.max_steps`).
fn prepend(step: u12, path: effects.Path) effects.Path {
    var out: effects.Path = .{};
    out = effects.child(out, step);
    for (path.slice()) |s| out = effects.child(out, s);
    return out;
}

/// `path` without its first step.
fn tail(path: effects.Path) effects.Path {
    var out: effects.Path = .{};
    for (path.slice()[1..]) |s| out = effects.child(out, s);
    return out;
}
