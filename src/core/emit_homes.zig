//! Memory homes: the stack slot each record or union over four words lives in (CE-A,
//! docs/audits/values-keys-trap-search-plan-2026-10-07.md §4.5).
//!
//! A value over four words lives in memory, and its SSA value is the address of its
//! bytes (docs/design/new-core-s1.md §3). Values that are never live at the same time
//! share one slot here, a *home*, so the copy that would move the bytes from one to the
//! other disappears:
//! - a phi and an incoming value that dies on the edge (P1): the phi's fill is skipped;
//! - a `record_set` and the record it updates, when that record has no later reader (P2);
//! - a call's in-out argument and the parameter's final value, and a returned value and
//!   the caller's destination (P7).
//!
//! - a value a `ret` stores inside the returned value and the place in `%ret` it is stored at
//!   (CE2-B): the store is skipped (`Planner.buildInRet`).
//!
//! A *view* is a field or payload of a value in memory read where it lies (P8): it has no
//! home, and every use of it is a use of the value it lies in, which therefore stays
//! intact until the view's last use.
//!
//! Two values interfere when one is live just after the other is defined, when the other's
//! defining instruction reads it after writing its home (every operand except the updated
//! record of a `record_set` and the in-out argument of a call), or when both are written at
//! one point (two phis of one block, or the values one call defines). A home holds no two
//! values that interfere. Phi operands are read at the end of their predecessor, and a
//! construction stored straight into its consumer reads its operands at the consumer.
const std = @import("std");
const ir = @import("ir.zig");
const effects = @import("effects.zig");

/// The coalescings that run, in the order CE-A landed them: shared homes for phis and records
/// updated in place, views, write-backs built in their field, and in-out `mut` records. A
/// measurement build may switch later ones off to count what each removes
/// (experiments/ce-records-20261008/tools/stepbuild.sh).
/// Sharing uses one noalias destination pointer as the parameter and result storage;
/// the candidate parameter is omitted from the private, direct-call ABI (R3).
pub const steps: struct { homes: bool, views: bool, write_backs: bool, in_out: bool, share_sret: bool } = .{ .homes = true, .views = true, .write_backs = true, .in_out = true, .share_sret = true };

/// No class: a value that is not homed (a register value, a view, or one with a private slot).
pub const none: u32 = std.math.maxInt(u32);

/// Where the values of one class live.
pub const Home = union(enum) {
    /// An entry-block `alloca` of this many bytes.
    slot: u32,
    /// The caller's memory behind parameter `%pN` (written only when the parameter is in-out).
    param: u32,
    /// The caller's `sret` destination `%ret`.
    ret,
    /// Inside the home of class `class`, at `offset`: the field a write-back stores this
    /// value into, where it is built and updated (`Planner.embed`).
    field: struct { class: u32, offset: u32 },
    /// The caller's `sret` destination `%ret` at this byte offset: a value a `ret` stores
    /// inside the returned value is built where the return puts it (CE2-B, `Planner.place`).
    ret_at: u32,
};

/// Where a value's bytes are: in the home of a class not inside another, at an offset.
pub const Place = struct { class: u32, offset: u32 };

/// One function's homes.
pub const Plan = struct {
    /// Per instruction: the class of a homed value, or `none`.
    class: []u32,
    /// Per instruction: for a view, the value whose bytes it names part of; `.none` otherwise.
    view: []ir.Ref,
    /// Per class: where its values live.
    homes: []Home,
    /// Per instruction: for a view, its offset inside the value it reads.
    view_offset: []u32,
    /// Per instruction: a `ret` that builds its value in a temporary first (`staged`); empty when none does.
    stage: []const bool = &.{},
    /// Whether parameter `Results.share` may lie in the caller's destination `%ret` itself
    /// (`Planner.shareable`): a caller may pass one memory as both.
    shared: bool = false,

    /// The value whose home holds the bytes `ref` names: `ref` itself, or the root of a view.
    pub fn root(self: *const Plan, ref: ir.Ref) ir.Ref {
        var current = ref;
        while (current != .none and self.view[current.index()] != .none) current = self.view[current.index()];
        return current;
    }

    /// The class whose home holds the bytes `ref` names (through views), or `none`.
    pub fn rootClass(self: *const Plan, ref: ir.Ref) u32 {
        const at = self.root(ref);
        return if (at == .none) none else self.class[at.index()];
    }

    /// Whether `a` and `b` are homed values in one home: they are the same bytes.
    pub fn same(self: *const Plan, a: ir.Ref, b: ir.Ref) bool {
        const class = self.class[a.index()];
        return class != none and class == self.class[b.index()];
    }

    /// The class whose own storage (not inside another's) holds class `class`'s home.
    pub fn storage(self: *const Plan, class: u32) u32 {
        if (class == none) return none;
        return switch (self.homes[class]) {
            .field => |inside| inside.class,
            else => class,
        };
    }

    /// Where the bytes `ref` names lie, or null when they are in no home (a register value, a
    /// private slot, a constant).
    pub fn place(self: *const Plan, ref: ir.Ref) ?Place {
        var offset: u32 = 0;
        var current = ref;
        while (self.view[current.index()] != .none) {
            offset += self.view_offset[current.index()];
            current = self.view[current.index()];
        }
        const class = self.class[current.index()];
        if (class == none) return null;
        return switch (self.homes[class]) {
            .field => |inside| .{ .class = inside.class, .offset = inside.offset + offset },
            else => .{ .class = class, .offset = offset },
        };
    }

    /// Whether `inner` already lies `offset` bytes into `outer`'s bytes: storing one there copies nothing.
    pub fn holds(self: *const Plan, outer: ir.Ref, offset: u32, inner: ir.Ref) bool {
        const at = self.place(outer) orelse return false;
        const there = self.place(inner) orelse return false;
        return at.class == there.class and at.offset + offset == there.offset;
    }

    /// The byte offset inside the caller's `sret` destination `%ret` at which the bytes `ref`
    /// names lie, or null when they lie anywhere else.
    pub fn retOffset(self: *const Plan, ref: ir.Ref) ?u32 {
        const at = self.place(ref) orelse return null;
        return switch (self.homes[at.class]) {
            .ret => at.offset,
            .ret_at => |base| base + at.offset,
            else => null,
        };
    }

    /// Whether the `ret` instruction `ref` builds its value in a temporary first and then copies
    /// it to `%ret`, because a value it reads lies in `%ret` where an earlier store would overwrite it.
    pub fn staged(self: *const Plan, ref: ir.Ref) bool {
        return ref.index() < self.stage.len and self.stage[ref.index()];
    }
};

/// What a `ret` writes into `%ret` and what lowers in place around calls (CE2-B,
/// docs/audits/values-keys-trap-search-plan-2026-10-07.md §4.5 "CE2").
pub const Results = struct {
    /// The function returns through `sret`: a value a `ret` stores inside the returned value may
    /// be built at its place in `%ret` (`Planner.place`).
    sret: bool = false,
    /// Bit `k`: field `k` of a returned record is an in-out final value, which a `ret` moves to its
    /// caller's memory and never stores in `%ret`.
    finals: u64 = 0,
    /// Per instruction: an element read out of a list that is passed where it lies, with no home
    /// (an element lent to calls, `emit_llvm.zig`); empty when there is none.
    borrowed: []const bool = &.{},
    /// A read-only memory parameter of the result's type that a caller may pass in its `sret`
    /// destination (checked by `Planner.shareable`), or `none`.
    share: u32 = none,
    /// Whether a returned value travels through `sret` and may be built whole in the caller's
    /// destination (CE-A's `%ret` home).
    home: bool = false,
};

/// One store a `ret` makes into `%ret`, in the order the emitter makes them: `size` bytes at
/// `offset`, of `leaf` (a value stored whole), or of a union's tag word when `leaf` is `.none`.
pub const RetStore = struct { offset: u32, size: u32, leaf: ir.Ref };

/// The stores the `ret` of `raw` makes into `%ret`, in order: a construction stored straight
/// into `%ret` stores its fields (or a union its tag word, then its payload) one by one; any
/// other value is stored whole. Fields in `finals` of the outermost record are not stored.
pub fn retStores(arena: std.mem.Allocator, m: *const ir.Module, f: *const ir.Function, fused: []const bool, raw: ir.Ref, finals: u64) std.mem.Allocator.Error![]const RetStore {
    var out: std.ArrayList(RetStore) = .empty;
    try storesOf(arena, .{ .module = m, .function = f, .fused = fused }, raw, 0, finals, &out);
    return out.items;
}

const Walk = struct { module: *const ir.Module, function: *const ir.Function, fused: []const bool };

fn storesOf(arena: std.mem.Allocator, w: Walk, raw: ir.Ref, offset: u32, finals: u64, out: *std.ArrayList(RetStore)) std.mem.Allocator.Error!void {
    const m = w.module;
    const f = w.function;
    const ref = f.resolve(raw);
    const inst = f.inst(ref);
    if (!w.fused[ref.index()]) return out.append(arena, .{ .offset = offset, .size = m.size(inst.ty), .leaf = ref });
    if (m.kind(inst.ty) == .array) {
        const elem = m.compound(inst.ty).array.elem;
        for (f.operands(inst.data), 0..) |operand, i| try storesOf(arena, w, operand, offset + @as(u32, @intCast(i)) * m.size(elem), 0, out);
        return;
    }
    switch (inst.op) {
        .record_make => for (f.operands(inst.data), 0..) |operand, k| {
            if (k < 64 and finals & (@as(u64, 1) << @intCast(k)) != 0) continue;
            try storesOf(arena, w, operand, offset + m.fieldOffset(inst.ty, k), 0, out);
        },
        .union_make => {
            try out.append(arena, .{ .offset = offset, .size = 8, .leaf = .none });
            if (inst.a != .none) try storesOf(arena, w, inst.a, offset + 8, 0, out);
        },
        else => unreachable,
    }
}

/// One in-out argument of a call, and where the parameter's final value appears.
pub const InOut = struct {
    /// The argument's position in the call's argument list.
    argument: u32,
    /// The value holding the parameter's final value after the call: the call itself, the
    /// one `record_get` of its field of the call's result, or `.none` when there is no such one.
    final: ir.Ref,
};

/// What a home plan needs: the function, its constructions stored straight into their
/// consumer, and its in-out ABI.
pub const Input = struct {
    module: *const ir.Module,
    function: *const ir.Function,
    /// Per instruction: a construction stored straight into its consumer (no storage of its own).
    fused: []const bool,
    /// Bit `i`: memory parameter `i` is in-out (its caller's memory, written in place).
    in_out: u64 = 0,
    /// Per instruction: for a call, its in-out arguments (empty everywhere else, or no slice at all).
    calls: []const []const InOut = &.{},
    /// The module's effect summaries (`effects.zig`): an in-out call writes only the fields its
    /// callee's summary names. Null: every in-out call writes its whole argument.
    effects: ?*const effects.Summaries = null,
    /// What the function's `ret`s store into `%ret` (CE2-B).
    results: Results = .{},
};

/// The definition point of a tracked value: block and position, or the function entry.
const Def = struct { block: u32, pos: u32, entry: bool = false };

/// Liveness of one value from a set of its uses: the blocks it is live into and out of, and
/// per block one past the position of its last use there.
const Live = struct {
    in: std.DynamicBitSetUnmanaged,
    out: std.DynamicBitSetUnmanaged,
    last: std.AutoHashMapUnmanaged(u32, u32) = .empty,
};

/// One use of a tracked value: where (`end`: on the edge out of `block`, read by a phi), the
/// instruction, the operand it reads (the value or a view of it) and the operand's index.
const UseSite = struct { block: u32, pos: u32, end: bool, user: ir.Ref, operand: ir.Ref, index: u32 };

/// A byte range inside a value: a field a write-back stores.
const Region = struct { offset: u32, size: u32 };

/// One operand an instruction reads, and its index in the instruction's own operand list
/// (`none` for an operand of a construction fused into it).
const Operand = struct { ref: ir.Ref, index: u32 };

/// Per tracked value (dense index): its instruction, definition point, liveness, the tracked
/// values its defining instruction reads after writing its home, and every use.
const Tracked = struct {
    refs: std.ArrayList(ir.Ref) = .empty,
    defs: std.ArrayList(Def) = .empty,
    live: std.ArrayList(Live) = .empty,
    reads: std.ArrayList([]const u32) = .empty,
    sites: std.ArrayList(std.ArrayList(UseSite)) = .empty,
};

/// Union-find over the tracked values (and one node for `%ret`): parent, members, fixed
/// home and whether that fixed home may be written.
const Classes = struct {
    parent: std.ArrayList(u32) = .empty,
    members: std.ArrayList(std.ArrayList(u32)) = .empty,
    fixed: std.ArrayList(?Home) = .empty,
    writable: std.ArrayList(bool) = .empty,
};

/// Where each instruction sits: its block and position in reachable blocks, `none` elsewhere;
/// for an in-out call's final value, the argument position it is the final value of; and its
/// dense index among tracked values, or `none`.
const Places = struct { block: []u32, pos: []u32, final: []u32, dense: []u32 };

/// Per-field interference (CE2-A): the pair of classes a merge is weighing (a value's definition
/// writes only part of its home when it shares the home with the value it updates), and per
/// pair of tracked values the liveness of the first restricted to the bytes the second's
/// definition writes.
const Partial = struct {
    pending: ?[2]u32 = null,
    live: std.AutoHashMapUnmanaged(u64, Live) = .empty,
};

const Planner = struct {
    arena: std.mem.Allocator,
    input: Input,
    plan: Plan,
    places: Places,
    tracked: Tracked = .{},
    classes: Classes = .{},
    partial: Partial = .{},

    fn fun(self: *const Planner) *const ir.Function {
        return self.input.function;
    }

    fn mod(self: *const Planner) *const ir.Module {
        return self.input.module;
    }

    fn emptyLive(self: *Planner, blocks: usize) !Live {
        return .{ .in = try std.DynamicBitSetUnmanaged.initEmpty(self.arena, blocks), .out = try std.DynamicBitSetUnmanaged.initEmpty(self.arena, blocks) };
    }

    fn node(self: *Planner, home: ?Home, writable: bool) !u32 {
        const index: u32 = @intCast(self.classes.parent.items.len);
        try self.classes.parent.append(self.arena, index);
        try self.classes.members.append(self.arena, .empty);
        try self.classes.fixed.append(self.arena, home);
        try self.classes.writable.append(self.arena, writable);
        return index;
    }

    fn track(self: *Planner, ref: ir.Ref, def: Def, home: ?Home, writable: bool) !void {
        const index: u32 = @intCast(self.tracked.refs.items.len);
        self.places.dense[ref.index()] = index;
        const blocks = self.fun().blocks.items.len;
        try self.tracked.refs.append(self.arena, ref);
        try self.tracked.defs.append(self.arena, def);
        try self.tracked.live.append(self.arena, try self.emptyLive(blocks));
        try self.tracked.reads.append(self.arena, &.{});
        try self.tracked.sites.append(self.arena, .empty);
        const class = try self.node(home, writable);
        std.debug.assert(class == index);
        try self.classes.members.items[class].append(self.arena, index);
    }

    /// Find the views, and track every homed value and memory parameter.
    fn classify(self: *Planner) !void {
        const f = self.fun();
        const m = self.mod();
        for (self.input.calls, 0..) |in_outs, call| for (in_outs) |in_out| {
            if (in_out.final != .none) self.places.final[in_out.final.index()] = in_out.argument;
            _ = call;
        };
        for (f.insts.items, 0..) |inst, index| {
            const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(index)));
            if (inst.op == .param and m.passedInMemory(inst.ty)) {
                const param: u32 = @intCast(inst.data);
                const writable = param < 64 and self.input.in_out & (@as(u64, 1) << @intCast(param)) != 0;
                try self.track(ref, .{ .block = 0, .pos = 0, .entry = true }, .{ .param = param }, writable);
                continue;
            }
            if (self.places.block[index] == none) continue;
            if (index < self.input.results.borrowed.len and self.input.results.borrowed[index]) continue;
            if (steps.views and self.places.final[index] == none and isView(m, f, inst)) {
                self.plan.view[index] = f.resolve(inst.a);
                self.plan.view_offset[index] = if (inst.op == .union_payload) 8 else m.fieldOffset(f.inst(f.resolve(inst.a)).ty, @intCast(inst.data));
                continue;
            }
            if ((inst.op == .record_make or inst.op == .union_make) and self.input.fused[index]) continue;
            if (!homable(m, f, inst)) continue;
            try self.track(ref, .{ .block = self.places.block[index], .pos = self.places.pos[index] }, null, true);
        }
        // An in-out call's final value is written by the call: it is defined where the call is.
        for (self.input.calls, 0..) |in_outs, call| for (in_outs) |in_out| {
            if (in_out.final == .none) continue;
            const dense = self.places.dense[in_out.final.index()];
            if (dense == none or self.places.block[call] == none) continue;
            self.tracked.defs.items[dense] = .{ .block = self.places.block[call], .pos = self.places.pos[call] };
        };
    }

    /// The tracked value whose bytes `raw` reads (through views), or `none`.
    fn rootDense(self: *const Planner, raw: ir.Ref) u32 {
        const at = self.plan.root(self.fun().resolve(raw));
        return if (at == .none) none else self.places.dense[at.index()];
    }

    /// Every operand `inst` reads, a fused construction's operands included (they are read
    /// where the construction is stored).
    fn operandsOf(self: *const Planner, inst: ir.Inst, out: *std.ArrayList(Operand)) !void {
        const f = self.fun();
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |i| {
            const ref = f.resolve(operands.get(i));
            const producer = f.inst(ref);
            if ((producer.op == .record_make or producer.op == .union_make) and self.input.fused[ref.index()]) {
                const before = out.items.len;
                try self.operandsOf(producer, out);
                for (out.items[before..]) |*nested| nested.index = none;
                continue;
            }
            try out.append(self.arena, .{ .ref = ref, .index = @intCast(i) });
        }
    }

    /// Record every use of a tracked value and propagate its liveness.
    fn liveness(self: *Planner) !void {
        const f = self.fun();
        var operands: std.ArrayList(Operand) = .empty;
        for (f.blocks.items, 0..) |block, b| {
            if (!reachable(f, b)) continue;
            for (block.insts.items, 0..) |ref, i| {
                const inst = f.inst(ref);
                if (inst.op == .copy) continue;
                if (inst.op == .phi) {
                    for (f.operands(inst.data), block.preds.items, 0..) |raw, pred, k| {
                        const d = self.rootDense(raw);
                        if (d == none) continue;
                        const site: UseSite = .{ .block = @intCast(pred.index()), .pos = 0, .end = true, .user = ref, .operand = f.resolve(raw), .index = @intCast(k) };
                        try self.tracked.sites.items[d].append(self.arena, site);
                        try self.record(&self.tracked.live.items[d], self.tracked.defs.items[d], site);
                    }
                    continue;
                }
                if ((inst.op == .record_make or inst.op == .union_make) and self.input.fused[ref.index()]) continue;
                operands.clearRetainingCapacity();
                try self.operandsOf(inst, &operands);
                for (operands.items) |operand| {
                    const d = self.rootDense(operand.ref);
                    if (d == none) continue;
                    const site: UseSite = .{ .block = @intCast(b), .pos = @intCast(i), .end = false, .user = ref, .operand = operand.ref, .index = operand.index };
                    try self.tracked.sites.items[d].append(self.arena, site);
                    try self.record(&self.tracked.live.items[d], self.tracked.defs.items[d], site);
                }
            }
        }
        // The values each defining instruction reads after writing its home.
        for (self.tracked.refs.items, self.tracked.reads.items, self.tracked.defs.items) |ref, *reads, def| {
            if (def.entry) continue;
            const defining = f.insts.items[f.blocks.items[def.block].insts.items[def.pos].index()];
            if (defining.op == .phi) continue;
            operands.clearRetainingCapacity();
            try self.operandsOf(defining, &operands);
            var list: std.ArrayList(u32) = .empty;
            const skipped = self.exempt(ref, defining);
            for (operands.items) |operand| {
                if (operand.index != none and operand.index == skipped and self.places.dense[operand.ref.index()] != none) continue;
                const d = self.rootDense(operand.ref);
                if (d != none and std.mem.indexOfScalar(u32, list.items, d) == null) try list.append(self.arena, d);
            }
            reads.* = list.items;
        }
    }

    /// The operand index `defining` may read from `ref`'s own home after writing it: the record
    /// a `record_set` updates, or an in-out call's argument for its final value.
    fn exempt(self: *const Planner, ref: ir.Ref, defining: ir.Inst) u32 {
        if (defining.op == .record_set or defining.op == .array_set) return 0;
        const argument = self.places.final[ref.index()];
        if (argument == none) return none;
        // A call's arguments follow its direct operands (`call_indirect` reads its callee first).
        return argument + @as(u32, if (defining.op == .call_indirect) 1 else 0);
    }

    /// Add one use to `live`, the liveness of a value defined at `def`.
    fn record(self: *Planner, live: *Live, def: Def, site: UseSite) !void {
        var work: std.ArrayList(u32) = .empty;
        if (site.end) {
            try self.liveOut(live, def, site.block, &work);
        } else {
            const entry = try live.last.getOrPut(self.arena, site.block);
            if (!entry.found_existing or entry.value_ptr.* < site.pos + 1) entry.value_ptr.* = site.pos + 1;
            if (!def.entry and def.block == site.block) return;
            if (live.in.isSet(site.block)) return;
            live.in.set(site.block);
            try work.append(self.arena, site.block);
        }
        // Live into a block: live out of every predecessor, back to the definition.
        while (work.pop()) |block| {
            for (self.fun().blocks.items[block].preds.items) |pred| try self.liveOut(live, def, @intCast(pred.index()), &work);
        }
    }

    fn liveOut(self: *Planner, live: *Live, def: Def, b: u32, work: *std.ArrayList(u32)) !void {
        if (live.out.isSet(b)) return;
        live.out.set(b);
        if (!def.entry and def.block == b) return;
        if (live.in.isSet(b)) return;
        live.in.set(b);
        try work.append(self.arena, b);
    }

    /// Whether a value defined at `def` with liveness `live` is live just after position `i` of block `b`.
    fn liveAfterIn(live: *const Live, def: Def, b: u32, i: u32) bool {
        const started = live.in.isSet(b) or (!def.entry and def.block == b and def.pos <= i);
        if (!started) return false;
        if (live.out.isSet(b)) return true;
        return (live.last.get(b) orelse 0) > i + 1;
    }

    /// Whether `d` is live just after position `i` of block `b`.
    fn liveAfter(self: *const Planner, d: u32, b: u32, i: u32) bool {
        return liveAfterIn(&self.tracked.live.items[d], self.tracked.defs.items[d], b, i);
    }

    /// Whether `u` holds bytes some read still needs when `v`'s home is written: `u` is live
    /// just after `v`'s definition (only its reads of the bytes that definition writes count,
    /// when it writes part of the home), or that definition reads `u` after writing.
    fn liveAtDef(self: *Planner, u: u32, v: u32) !bool {
        const def = self.tracked.defs.items[v];
        if (def.entry) return self.tracked.defs.items[u].entry;
        if (try self.writtenRegions(v)) |regions| {
            if (liveAfterIn(try self.regionLive(u, v, regions), self.tracked.defs.items[u], def.block, def.pos)) return true;
        } else if (self.liveAfter(u, def.block, def.pos)) return true;
        return std.mem.indexOfScalar(u32, self.tracked.reads.items[v], u) != null;
    }

    /// Whether tracked values `x` and `y` share a home, or will once the merge being weighed is made.
    fn sameHome(self: *Planner, x: u32, y: u32) bool {
        const rx = self.find(x);
        const ry = self.find(y);
        if (rx == ry) return true;
        const pair = self.partial.pending orelse return false;
        return (rx == pair[0] and ry == pair[1]) or (rx == pair[1] and ry == pair[0]);
    }

    /// The bytes `v`'s definition writes in its home when that is not the whole value (null):
    /// a `record_set` that shares the home of the record it updates writes its field; an in-out
    /// call's final value that shares its argument's home is written where the callee's summary
    /// says it writes (`effects.zig`), and nowhere when it writes nothing.
    fn writtenRegions(self: *Planner, v: u32) !?[]const Region {
        const f = self.fun();
        const m = self.mod();
        const ref = self.tracked.refs.items[v];
        const def = self.tracked.defs.items[v];
        if (def.entry) return null;
        const inst = f.inst(ref);
        if (inst.op == .record_set) {
            const old = self.places.dense[f.resolve(inst.a).index()];
            if (old == none or !self.sameHome(old, v)) return null;
            const field_type = m.compound(inst.ty).record[@intCast(inst.data)];
            const region = try self.arena.alloc(Region, 1);
            region[0] = .{ .offset = m.fieldOffset(inst.ty, @intCast(inst.data)), .size = m.size(field_type) };
            return region;
        }
        const argument = self.places.final[ref.index()];
        if (argument == none) return null;
        const summaries = self.input.effects orelse return null;
        const call = f.inst(f.blocks.items[def.block].insts.items[def.pos]);
        if (call.op != .call) return null;
        // Only a `mut` parameter's summary says what the call writes in its argument's home: a
        // by-value argument sharing the call's `sret` result (CE2-B) is overwritten whole.
        const owned = m.functions.items[call.a.index()].signature.owned;
        if (argument >= 64 or owned & (@as(u64, 1) << @intCast(argument)) == 0) return null;
        const passed = f.resolve(f.operands(call.data)[argument]);
        const holder = self.places.dense[passed.index()];
        if (holder == none or !self.sameHome(holder, v)) return null;
        const paths = summaries.writes(call.a.index(), argument, null);
        if (paths.whole) return null;
        const regions = try self.arena.alloc(Region, paths.items.items.len);
        for (paths.items.items, regions) |path, *region| {
            const target = m.pathTarget(f.inst(passed).ty, path) orelse return null;
            if (target.tag_of != .void) return null;
            region.* = .{ .offset = target.offset, .size = m.size(target.ty) };
        }
        return regions;
    }

    /// The liveness of `u` from only its uses that read some of `regions` (the bytes `v`'s
    /// definition writes), computed once per pair.
    fn regionLive(self: *Planner, u: u32, v: u32, regions: []const Region) !*const Live {
        const key = (@as(u64, u) << 32) | v;
        if (self.partial.live.getPtr(key)) |known| return known;
        var live = try self.emptyLive(self.fun().blocks.items.len);
        for (self.tracked.sites.items[u].items) |site| {
            const reads = for (regions) |region| {
                if (self.readsRegion(u, site, region)) break true;
            } else false;
            if (reads) try self.record(&live, self.tracked.defs.items[u], site);
        }
        try self.partial.live.put(self.arena, key, live);
        return self.partial.live.getPtr(key).?;
    }

    /// Whether `u` and `v` are written at one point: the values one instruction defines, or two
    /// phis' fills on one edge.
    fn writtenTogether(self: *const Planner, u: u32, v: u32) bool {
        const du = self.tracked.defs.items[u];
        const dv = self.tracked.defs.items[v];
        if (du.entry or dv.entry or du.block != dv.block) return false;
        if (du.pos == dv.pos) return true;
        const f = self.fun();
        return f.inst(self.tracked.refs.items[u]).op == .phi and f.inst(self.tracked.refs.items[v]).op == .phi;
    }

    fn interferes(self: *Planner, u: u32, v: u32) !bool {
        if (self.writtenTogether(u, v)) return true;
        const forward = try self.liveAtDef(u, v);
        const backward = forward or try self.liveAtDef(v, u);
        return backward;
    }

    /// Whether `u` and `v` interfere as whole values, never per field: the form `clash` needs, since
    /// two classes in `%ret` lie at different offsets, where the fields one value's definition writes
    /// (offsets within its own home, `writtenRegions`) say nothing about the other's bytes.
    fn interferesWhole(self: *const Planner, u: u32, v: u32) bool {
        if (self.writtenTogether(u, v)) return true;
        return self.liveAtDefWhole(u, v) or self.liveAtDefWhole(v, u);
    }

    /// `liveAtDef` over whole values: `u` is live just after `v`'s definition, or that definition reads it.
    fn liveAtDefWhole(self: *const Planner, u: u32, v: u32) bool {
        const def = self.tracked.defs.items[v];
        if (def.entry) return self.tracked.defs.items[u].entry;
        if (self.liveAfter(u, def.block, def.pos)) return true;
        return std.mem.indexOfScalar(u32, self.tracked.reads.items[v], u) != null;
    }

    fn find(self: *Planner, x: u32) u32 {
        var at = x;
        while (self.classes.parent.items[at] != at) at = self.classes.parent.items[at];
        var walk = x;
        while (self.classes.parent.items[walk] != at) {
            const next = self.classes.parent.items[walk];
            self.classes.parent.items[walk] = at;
            walk = next;
        }
        return at;
    }

    /// Put the classes of `a` and `b` in one home if no two of their values interfere, at most
    /// one of them has a fixed home and that home may be written. Returns whether they share.
    fn merge(self: *Planner, a: u32, b: u32) !bool {
        const ra = self.find(a);
        const rb = self.find(b);
        if (ra == rb) return true;
        const fa = self.classes.fixed.items[ra];
        const fb = self.classes.fixed.items[rb];
        if (fa != null and fb != null) return false;
        if (fa != null and !self.classes.writable.items[ra]) return false;
        if (fb != null and !self.classes.writable.items[rb]) return false;
        self.partial.pending = .{ ra, rb };
        defer self.partial.pending = null;
        for (self.classes.members.items[ra].items) |x| for (self.classes.members.items[rb].items) |y| {
            if (try self.interferes(x, y)) return false;
        };
        const keep, const gone = if (fb != null) .{ rb, ra } else .{ ra, rb };
        self.classes.parent.items[gone] = keep;
        try self.classes.members.items[keep].appendSlice(self.arena, self.classes.members.items[gone].items);
        self.classes.members.items[gone] = .empty;
        return true;
    }

    /// The merges, in order: records updated in place, in-out arguments and their final
    /// values, phis and their incoming values, and the returned value and `%ret`.
    fn coalesce(self: *Planner) !void {
        const f = self.fun();
        for (self.tracked.refs.items, 0..) |ref, d| {
            const inst = f.inst(ref);
            if (!steps.homes or (inst.op != .record_set and inst.op != .array_set)) continue;
            const old = self.places.dense[f.resolve(inst.a).index()];
            if (old != none) _ = try self.merge(@intCast(d), old);
        }
        for (self.input.calls, 0..) |in_outs, call| for (in_outs) |in_out| {
            if (in_out.final == .none) continue;
            const final = self.places.dense[in_out.final.index()];
            const argument = self.places.dense[f.resolve(f.operands(f.insts.items[call].data)[in_out.argument]).index()];
            if (final != none and argument != none) _ = try self.merge(final, argument);
        };
        for (self.tracked.refs.items, 0..) |ref, d| {
            const inst = f.inst(ref);
            if (!steps.homes or inst.op != .phi) continue;
            for (f.operands(inst.data)) |raw| {
                const incoming = self.places.dense[f.resolve(raw).index()];
                if (incoming != none) _ = try self.merge(@intCast(d), incoming);
            }
        }
        if (!self.input.results.home) return;
        const ret = try self.node(.ret, true);
        for (f.blocks.items, 0..) |block, b| {
            if (!reachable(f, b)) continue;
            const last = f.inst(block.insts.items[block.insts.items.len - 1]);
            if (last.op != .ret or last.a == .none) continue;
            const value = self.places.dense[f.resolve(last.a).index()];
            if (value != none) _ = try self.merge(ret, value);
        }
    }

    /// Number the classes and give each its home (a class built inside another names that
    /// other's number).
    fn assign(self: *Planner) !void {
        const f = self.fun();
        const m = self.mod();
        var numbers = try self.arena.alloc(u32, self.classes.parent.items.len);
        @memset(numbers, none);
        var homes: std.ArrayList(Home) = .empty;
        for (self.tracked.refs.items, 0..) |ref, d| {
            const root = self.find(@intCast(d));
            if (numbers[root] == none) {
                numbers[root] = @intCast(homes.items.len);
                try homes.append(self.arena, self.classes.fixed.items[root] orelse .{ .slot = m.size(f.inst(ref).ty) });
            }
            self.plan.class[ref.index()] = numbers[root];
        }
        for (homes.items) |*home| switch (home.*) {
            .field => |inside| home.* = .{ .field = .{ .class = numbers[inside.class], .offset = inside.offset } },
            else => {},
        };
        self.plan.homes = homes.items;
    }

    /// Write-backs: for `p.f = y` with `p` updated in place, build `y`'s class inside `p`'s home
    /// at the field, so neither the read of the old field nor the store of the new one copies.
    /// It holds when no read of the field's old bytes and no write of `p`'s whole home falls
    /// inside the life of a value of `y`'s class (one level: a home holding such a field is
    /// never itself inside another).
    fn embed(self: *Planner) !void {
        const f = self.fun();
        const m = self.mod();
        for (self.tracked.refs.items, 0..) |ref, d| {
            const inst = f.inst(ref);
            if (inst.op != .record_set) continue;
            const field_type = m.compound(inst.ty).record[@intCast(inst.data)];
            if (!m.passedInMemory(field_type)) continue;
            const old = self.places.dense[f.resolve(inst.a).index()];
            const stored = self.places.dense[f.resolve(inst.b).index()];
            if (old == none or stored == none) continue;
            const outer = self.find(@intCast(d));
            const inner = self.find(stored);
            if (self.find(old) != outer or inner == outer or self.classes.fixed.items[inner] != null) continue;
            if (self.isInside(outer) or self.holdsAny(inner)) continue;
            const region: Region = .{ .offset = m.fieldOffset(inst.ty, @intCast(inst.data)), .size = m.size(field_type) };
            if (!try self.embeddable(inner, outer, region)) continue;
            self.classes.fixed.items[inner] = .{ .field = .{ .class = outer, .offset = region.offset } };
        }
    }

    fn isInside(self: *const Planner, class: u32) bool {
        const home = self.classes.fixed.items[class] orelse return false;
        return home == .field;
    }

    fn holdsAny(self: *const Planner, class: u32) bool {
        for (self.classes.fixed.items) |home| {
            const known = home orelse continue;
            if (known == .field and known.field.class == class) return true;
        }
        return false;
    }

    /// Whether class `inner` may live at `region` of class `outer`'s home.
    fn embeddable(self: *Planner, inner: u32, outer: u32, region: Region) !bool {
        const f = self.fun();
        const blocks = f.blocks.items.len;
        for (self.classes.members.items[outer].items) |w| {
            // The liveness of `w`'s old field bytes: only the uses that read them.
            var old_bytes = try self.emptyLive(blocks);
            for (self.tracked.sites.items[w].items) |site| {
                if (self.readsRegion(w, site, region)) try self.record(&old_bytes, self.tracked.defs.items[w], site);
            }
            const writes = self.writesRegion(w, region, inner);
            for (self.classes.members.items[inner].items) |e| {
                const de = self.tracked.defs.items[e];
                if (liveAfterIn(&old_bytes, self.tracked.defs.items[w], de.block, de.pos)) return false;
                if (try self.readsAtDef(e, w, region)) return false;
                if (!writes) continue;
                const dw = self.tracked.defs.items[w];
                if (dw.entry) continue;
                if (self.liveAfter(e, dw.block, dw.pos)) return false;
                if (std.mem.indexOfScalar(u32, self.tracked.reads.items[w], e) != null) return false;
                const both_phis = f.inst(self.tracked.refs.items[w]).op == .phi and f.inst(self.tracked.refs.items[e]).op == .phi;
                if (both_phis and dw.block == de.block) return false;
            }
        }
        // Another class already built at this field of the same home must never be live with this one.
        for (self.classes.fixed.items, 0..) |home, other| {
            const known = home orelse continue;
            if (known != .field or known.field.class != outer or known.field.offset != region.offset) continue;
            for (self.classes.members.items[other].items) |x| for (self.classes.members.items[inner].items) |y| {
                if (try self.interferes(x, y)) return false;
            };
        }
        return true;
    }

    /// The byte range a view names inside the tracked value it lies in.
    fn viewRegion(self: *const Planner, view: ir.Ref) Region {
        var offset: u32 = 0;
        var current = view;
        while (self.plan.view[current.index()] != .none) {
            offset += self.plan.view_offset[current.index()];
            current = self.plan.view[current.index()];
        }
        return .{ .offset = offset, .size = self.mod().size(self.fun().inst(view).ty) };
    }

    fn overlaps(a: Region, b: Region) bool {
        return a.offset < b.offset + b.size and b.offset < a.offset + a.size;
    }

    /// Whether the use `site` of tracked value `w` reads the bytes at `region`.
    fn readsRegion(self: *const Planner, w: u32, site: UseSite, region: Region) bool {
        const f = self.fun();
        if (site.operand != self.tracked.refs.items[w]) return overlaps(self.viewRegion(site.operand), region);
        const user_class = self.places.dense[site.user.index()];
        const shared = user_class != none and self.classes.parent.items.len != 0 and self.findConst(user_class) == self.findConst(w);
        // A phi that shares the home is filled by no copy; any other reads the whole value.
        if (site.end) return !shared;
        const user = f.inst(site.user);
        if (user.op == .record_get and site.index == 0) {
            const field = f.inst(self.tracked.refs.items[w]).ty;
            const field_region: Region = .{ .offset = self.mod().fieldOffset(field, @intCast(user.data)), .size = self.mod().size(user.ty) };
            return overlaps(field_region, region);
        }
        // A `record_set` that updates the value in place writes, and reads nothing of it.
        if (user.op == .record_set and site.index == 0) return !shared;
        return true;
    }

    /// Whether the definition of `w` writes the bytes at `region` with something other than the
    /// value of class `inner` that lives there: anything but a `record_set` in place of another field
    /// or of that field with that class's value.
    fn writesRegion(self: *const Planner, w: u32, region: Region, inner: u32) bool {
        const f = self.fun();
        const m = self.mod();
        const ref = self.tracked.refs.items[w];
        const inst = f.inst(ref);
        if (self.tracked.defs.items[w].entry) return false;
        if (inst.op != .record_set) return true;
        const old = self.places.dense[f.resolve(inst.a).index()];
        if (old == none or self.findConst(old) != self.findConst(w)) return true;
        const field_type = m.compound(inst.ty).record[@intCast(inst.data)];
        const written: Region = .{ .offset = m.fieldOffset(inst.ty, @intCast(inst.data)), .size = m.size(field_type) };
        if (!overlaps(written, region)) return false;
        const stored = self.places.dense[f.resolve(inst.b).index()];
        return !(written.offset == region.offset and stored != none and self.findConst(stored) == inner);
    }

    /// Whether the instruction defining `e` reads `region` of `w`, other than as the record it
    /// updates in place there (the `record_set`'s old value or the in-out argument, naming exactly it).
    fn readsAtDef(self: *Planner, e: u32, w: u32, region: Region) !bool {
        const def = self.tracked.defs.items[e];
        const f = self.fun();
        const defining = f.insts.items[f.blocks.items[def.block].insts.items[def.pos].index()];
        if (defining.op == .phi) return false;
        var operands: std.ArrayList(Operand) = .empty;
        try self.operandsOf(defining, &operands);
        const skipped = self.exempt(self.tracked.refs.items[e], defining);
        for (operands.items) |operand| {
            if (self.rootDense(operand.ref) != w) continue;
            const whole = operand.ref == self.tracked.refs.items[w];
            const read: Region = if (whole) .{ .offset = 0, .size = self.mod().size(f.inst(operand.ref).ty) } else self.viewRegion(operand.ref);
            if (!overlaps(read, region)) continue;
            const exact = read.offset == region.offset and read.size == region.size;
            const updated = operand.index != none and operand.index == skipped;
            if (updated and exact and !whole) continue;
            return true;
        }
        return false;
    }

    fn findConst(self: *const Planner, x: u32) u32 {
        var at = x;
        while (self.classes.parent.items[at] != at) at = self.classes.parent.items[at];
        return at;
    }

    // ---- CE2-B: values a `ret` stores inside the returned value, built at their place in `%ret` ----

    /// The `%ret` offset of class `class`'s storage, or null when it lies anywhere else.
    fn retBase(self: *const Planner, class: u32) ?u32 {
        const home = self.classes.fixed.items[self.findConst(class)] orelse return null;
        return switch (home) {
            .ret => 0,
            .ret_at => |at| at,
            .field => |inside| switch (self.classes.fixed.items[self.findConst(inside.class)] orelse return null) {
                .ret => inside.offset,
                .ret_at => |at| at + inside.offset,
                else => null,
            },
            else => null,
        };
    }

    /// Where in `%ret` the bytes `raw` names lie (through views), or null when they lie elsewhere.
    fn retOffsetOf(self: *const Planner, raw: ir.Ref) ?u32 {
        const ref = self.fun().resolve(raw);
        const d = self.rootDense(ref);
        if (d == none) return null;
        const base = self.retBase(d) orelse return null;
        return base + (if (self.plan.view[ref.index()] != .none) self.viewRegion(ref).offset else 0);
    }

    /// The bytes of `%ret` tracked value `d` occupies, or null when it lies elsewhere.
    fn retRegion(self: *const Planner, d: u32) ?Region {
        const at = self.retBase(d) orelse return null;
        return .{ .offset = at, .size = self.mod().size(self.fun().inst(self.tracked.refs.items[d]).ty) };
    }

    /// Whether `inner`'s class is built inside `outer`'s class (one level, `embed`).
    fn within(self: *const Planner, inner: u32, outer: u32) bool {
        const home = self.classes.fixed.items[self.findConst(inner)] orelse return false;
        return home == .field and self.findConst(home.field.class) == self.findConst(outer);
    }

    /// Whether the instruction defining tracked value `x` reads `y` (through views), any operand
    /// counted, the one it may update in place included; a phi reads its operands.
    fn defReads(self: *Planner, x: u32, y: u32) !bool {
        const def = self.tracked.defs.items[x];
        if (def.entry) return false;
        const f = self.fun();
        const defining = f.insts.items[f.blocks.items[def.block].insts.items[def.pos].index()];
        if (defining.op == .phi) {
            for (f.operands(defining.data)) |raw| if (self.rootDense(raw) == y) return true;
            return false;
        }
        var operands: std.ArrayList(Operand) = .empty;
        try self.operandsOf(defining, &operands);
        for (operands.items) |operand| if (self.rootDense(operand.ref) == y) return true;
        return false;
    }

    /// Whether `x` is a phi and `y` is read by a phi of the same block: both are filled or read on
    /// one edge, where the parallel copy orders moves by class, not by bytes.
    fn edgeShared(self: *const Planner, x: u32, y: u32) bool {
        const f = self.fun();
        const ref = self.tracked.refs.items[x];
        if (f.inst(ref).op != .phi) return false;
        const def = self.tracked.defs.items[x];
        for (f.blocks.items[def.block].insts.items) |other| {
            const inst = f.inst(other);
            if (inst.op != .phi) continue;
            for (f.operands(inst.data)) |raw| if (self.rootDense(raw) == y) return true;
        }
        return false;
    }

    /// Whether two values in different homes may not share bytes: one is live when the other is
    /// written, one's defining instruction reads the other, or both meet on a phi's edge.
    fn clash(self: *Planner, u: u32, v: u32) !bool {
        if (self.interferesWhole(u, v)) return true;
        if (try self.defReads(u, v) or try self.defReads(v, u)) return true;
        return self.edgeShared(u, v) or self.edgeShared(v, u);
    }

    /// Whether class `class`, just given a `%ret` home, shares no byte with a value in `%ret` it clashes with.
    fn disjointInRet(self: *Planner, class: u32) !bool {
        const root = self.findConst(class);
        for (self.tracked.refs.items, 0..) |_, u| {
            const ur = self.findConst(@intCast(u));
            if (ur != root and !self.within(@intCast(u), root)) continue;
            const mine = self.retRegion(@intCast(u)) orelse continue;
            for (self.tracked.refs.items, 0..) |_, v| {
                const vr = self.findConst(@intCast(v));
                if (vr == root or self.within(@intCast(v), root)) continue;
                const theirs = self.retRegion(@intCast(v)) orelse continue;
                if (!overlaps(mine, theirs)) continue;
                if (self.within(@intCast(v), @intCast(u)) or self.within(@intCast(u), @intCast(v))) continue;
                if (try self.clash(@intCast(u), @intCast(v))) return false;
            }
        }
        return true;
    }

    /// The classes a `ret` would read from `%ret` after an earlier store of the same `ret` (or the
    /// same store) overwrote them: the stores run in order and copy nothing for a value already at
    /// its place; the in-out final values are read after every store.
    fn overwritten(self: *Planner, site: RetSite, out: *std.ArrayList(u32)) !void {
        const m = self.mod();
        const f = self.fun();
        var written: std.ArrayList(Region) = .empty;
        for (site.stores) |store| {
            const region: Region = .{ .offset = store.offset, .size = store.size };
            if (store.leaf != .none and m.passedInMemory(f.inst(store.leaf).ty)) {
                if (self.retOffsetOf(store.leaf)) |from| {
                    if (from == store.offset) continue;
                    const read: Region = .{ .offset = from, .size = store.size };
                    var hit = overlaps(read, region);
                    for (written.items) |earlier| hit = hit or overlaps(read, earlier);
                    if (hit) try out.append(self.arena, self.findConst(self.rootDense(store.leaf)));
                }
            }
            try written.append(self.arena, region);
        }
        for (site.reads) |leaf| {
            const from = self.retOffsetOf(leaf) orelse continue;
            const read: Region = .{ .offset = from, .size = m.size(f.inst(f.resolve(leaf)).ty) };
            for (written.items) |earlier| if (overlaps(read, earlier)) {
                try out.append(self.arena, self.findConst(self.rootDense(leaf)));
                break;
            };
        }
    }

    /// Whether some `ret` reads class `class` from `%ret` after overwriting it.
    fn overwrittenAnywhere(self: *Planner, sites: []const RetSite, class: u32) !bool {
        var hits: std.ArrayList(u32) = .empty;
        for (sites) |site| try self.overwritten(site, &hits);
        return std.mem.indexOfScalar(u32, hits.items, self.findConst(class)) != null;
    }

    /// The largest value of class `class`.
    fn classSize(self: *const Planner, class: u32) u32 {
        var most: u32 = 0;
        for (self.classes.members.items[self.findConst(class)].items) |d| most = @max(most, self.mod().size(self.fun().inst(self.tracked.refs.items[d]).ty));
        return most;
    }

    /// Every `ret` of a value: its stores into `%ret`, and the values its in-out final moves read.
    fn retSites(self: *Planner) ![]const RetSite {
        const f = self.fun();
        const m = self.mod();
        var sites: std.ArrayList(RetSite) = .empty;
        for (f.blocks.items, 0..) |block, b| {
            if (!reachable(f, b)) continue;
            const ref = block.insts.items[block.insts.items.len - 1];
            const last = f.inst(ref);
            if (last.op != .ret or last.a == .none) continue;
            const finals = self.input.results.finals;
            const stores = try retStores(self.arena, m, f, self.input.fused, last.a, finals);
            var reads: std.ArrayList(ir.Ref) = .empty;
            const value = f.resolve(last.a);
            if (finals != 0 and self.input.fused[value.index()]) {
                for (f.operands(f.inst(value).data), 0..) |operand, k| {
                    if (k >= 64 or finals & (@as(u64, 1) << @intCast(k)) == 0) continue;
                    for (try retStores(self.arena, m, f, self.input.fused, operand, 0)) |store| if (store.leaf != .none) try reads.append(self.arena, store.leaf);
                }
            }
            try sites.append(self.arena, .{ .ret = ref, .stores = stores, .reads = reads.items });
        }
        return sites.items;
    }

    /// Results built in `%ret`: each value a `ret` stores inside the returned value (or the value
    /// it lies in, when it is a view) is given the home at that place in `%ret`, when that home
    /// fits, shares no byte with a value in `%ret` it clashes with, and no `ret` overwrites it
    /// before reading it. A `ret` that would overwrite a value of the caller's-destination class
    /// (`coalesce`) before reading it builds its value in a temporary (`Plan.staged`).
    fn buildInRet(self: *Planner) !void {
        if (!self.input.results.sret) return;
        const f = self.fun();
        const m = self.mod();
        const limit = m.size(f.signature.ret);
        const sites = try self.retSites();
        for (sites) |site| for (site.stores) |store| {
            if (store.leaf == .none or !m.passedInMemory(f.inst(store.leaf).ty)) continue;
            const d = self.rootDense(store.leaf);
            if (d == none) continue;
            const class = self.findConst(d);
            if (self.classes.fixed.items[class] != null) continue;
            const inside = if (self.plan.view[store.leaf.index()] != .none) self.viewRegion(store.leaf).offset else 0;
            if (store.offset < inside or store.offset - inside + self.classSize(class) > limit) continue;
            self.classes.fixed.items[class] = .{ .ret_at = store.offset - inside };
            if (try self.disjointInRet(class) and !try self.overwrittenAnywhere(sites, class)) continue;
            self.classes.fixed.items[class] = null;
        };
        var stage: ?[]bool = null;
        for (sites) |site| {
            var hits: std.ArrayList(u32) = .empty;
            try self.overwritten(site, &hits);
            if (hits.items.len == 0) continue;
            if (stage == null) {
                stage = try self.arena.alloc(bool, f.insts.items.len);
                @memset(stage.?, false);
            }
            stage.?[site.ret.index()] = true;
        }
        if (stage) |marks| self.plan.stage = marks;
    }

    /// Whether parameter `results.share` may lie in `%ret` itself, so a caller may pass one memory
    /// as both (`s = advance(s, x)`): nothing lives in `%ret` before a `ret` (every write to it is a
    /// `ret`'s store), and no `ret` reads a byte of the parameter after one of its stores wrote that
    /// byte — a store of the parameter's bytes to their own place copies them onto themselves.
    fn shareable(self: *Planner) !bool {
        const param = self.input.results.share;
        if (param == none or !self.input.results.sret) return false;
        for (self.tracked.refs.items, 0..) |_, d| if (self.retBase(@intCast(d)) != null) return false;
        const f = self.fun();
        const m = self.mod();
        const holder = for (f.insts.items, 0..) |inst, index| {
            if (inst.op == .param and inst.data == param) break self.places.dense[index];
        } else none;
        if (holder == none) return false;
        for (try self.retSites()) |site| {
            var written: std.ArrayList(Region) = .empty;
            for (site.stores) |store| {
                const region: Region = .{ .offset = store.offset, .size = store.size };
                const from_param = store.leaf != .none and m.passedInMemory(f.inst(store.leaf).ty) and self.rootDense(store.leaf) == holder;
                if (from_param) {
                    const from = if (self.plan.view[store.leaf.index()] != .none) self.viewRegion(store.leaf).offset else 0;
                    const read: Region = .{ .offset = from, .size = store.size };
                    for (written.items) |earlier| if (overlaps(read, earlier)) return false;
                    if (from == store.offset) continue;
                    if (overlaps(read, region)) return false;
                }
                try written.append(self.arena, region);
            }
        }
        return true;
    }
};

/// One `ret` of a value: the instruction, its stores into `%ret` in order, and the values its
/// in-out final moves read after them.
const RetSite = struct { ret: ir.Ref, stores: []const RetStore, reads: []const ir.Ref };

/// Plan the homes of `input.function`'s memory values.
pub fn plan(arena: std.mem.Allocator, input: Input) std.mem.Allocator.Error!Plan {
    const f = input.function;
    const count = f.insts.items.len;
    var p: Planner = .{
        .arena = arena,
        .input = input,
        .plan = .{ .class = try arena.alloc(u32, count), .view = try arena.alloc(ir.Ref, count), .homes = &.{}, .view_offset = try arena.alloc(u32, count) },
        .places = .{ .block = try arena.alloc(u32, count), .pos = try arena.alloc(u32, count), .final = try arena.alloc(u32, count), .dense = try arena.alloc(u32, count) },
    };
    @memset(p.plan.class, none);
    @memset(p.plan.view, .none);
    @memset(p.plan.view_offset, 0);
    @memset(p.places.dense, none);
    @memset(p.places.block, none);
    @memset(p.places.pos, none);
    @memset(p.places.final, none);
    for (f.blocks.items, 0..) |block, b| {
        if (!reachable(f, b)) continue;
        for (block.insts.items, 0..) |ref, i| {
            p.places.block[ref.index()] = @intCast(b);
            p.places.pos[ref.index()] = @intCast(i);
        }
    }
    try p.classify();
    try p.liveness();
    try p.coalesce();
    if (steps.write_backs) try p.embed();
    try p.buildInRet();
    p.plan.shared = try p.shareable();
    try p.assign();
    return p.plan;
}

fn reachable(f: *const ir.Function, b: usize) bool {
    return b == 0 or f.blocks.items[b].preds.items.len != 0;
}

/// Whether `inst` defines a memory value the emitter writes into a home it is given (rather
/// than naming it some other way).
fn homable(m: *const ir.Module, f: *const ir.Function, inst: ir.Inst) bool {
    if (!m.passedInMemory(inst.ty)) return false;
    return switch (inst.op) {
        .phi, .record_make, .union_make, .record_set, .record_get, .union_payload => true,
        .list_get, .list_get_field, .box_get, .dict_entry_key, .dict_entry_value, .array_get, .array_set => true,
        .call => m.functions.items[inst.a.index()].signature.linkage == .internal,
        .call_indirect => m.compound(f.inst(f.resolve(inst.a)).ty).@"fn".linkage == .internal,
        else => false,
    };
}

/// Whether `inst` reads a field of a record, or the payload of a union, that lives in memory
/// and is itself over four words: it can name those bytes where they lie.
fn isView(m: *const ir.Module, f: *const ir.Function, inst: ir.Inst) bool {
    if (inst.op != .record_get and inst.op != .union_payload) return false;
    return m.passedInMemory(inst.ty) and m.passedInMemory(f.inst(f.resolve(inst.a)).ty);
}
