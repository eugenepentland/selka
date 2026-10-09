//! A list's or byte buffer's length and capacity kept out of its header while a loop
//! appends to it (lane U1, NEW-CORE-U1-STATE-2).
//!
//! An in-place `list_push` or `buffer_append` reads the length and capacity from the
//! block's header and writes the length back, so each append in a loop waits on the
//! store of the one before: the block pointer changes when the block grows, so LLVM
//! cannot keep the header fields in registers itself. Here a *web* is a set of list (or
//! buffer) values, all inside loops, that are one value through time: the phis that join
//! them and the in-place updates that make each from the one before. Its *region* is the
//! loops (strongly connected blocks) they lie in. When nothing in the region but those
//! updates and phis uses a web value, the web's length and capacity live in two
//! entry-block slots (`alloca`s LLVM keeps in registers) inside the region:
//! - each edge that enters the web (a phi operand from outside the region, on an edge that
//!   jumps straight to the phi's block) loads the entering block's header into the slots;
//! - an update appends at the slots' length and advances it; when the block must grow,
//!   the header gets the length back first, and the grown block's capacity is loaded;
//! - each edge that leaves the region stores the slots' length into the header of the
//!   web value current there, on the edge itself.
//! So outside the region, where anything else may read, free or hand on a web value, its
//! header is current.
const std = @import("std");
const ir = @import("ir.zig");
const own = @import("own.zig");

/// The planning only allocates.
pub const Error = std.mem.Allocator.Error;

/// What emitting the slots' loads and stores may fail with: the emitter's own errors.
pub const EmitError = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// No web.
pub const none: u32 = std.math.maxInt(u32);

/// The two slots of one web: the names of its length and capacity `alloca`s.
pub const Slots = struct { len: []const u8, cap: []const u8 };

/// A store of a web's length on an edge leaving its region: into `value`'s header.
pub const Exit = struct { value: ir.Ref, slots: Slots };

/// One function's webs: per instruction the web it belongs to, each web's slots, and the
/// stores on the edges (`pred << 32 | succ`) that leave a region.
pub const Plan = struct {
    web: []const u32 = &.{},
    slots: []const Slots = &.{},
    exits: std.AutoHashMapUnmanaged(u64, std.ArrayList(Exit)) = .empty,

    /// The stores on the edge `pred → succ`, one per web whose region it leaves.
    pub fn exit(self: *const Plan, pred: u32, succ: u32) []const Exit {
        const list = self.exits.get(edgeKey(pred, succ)) orelse return &.{};
        return list.items;
    }

    /// The slots of the web `ref` belongs to, or null.
    pub fn of(self: *const Plan, ref: ir.Ref) ?Slots {
        if (ref == .none or ref.index() >= self.web.len) return null;
        const w = self.web[ref.index()];
        return if (w == none) null else self.slots[w];
    }
};

/// No one web value: paths disagree (`Check.exits`).
const conflict: ir.Ref = @fromBackingInt(std.math.maxInt(u32) - 1);

/// The join of two blocks' current web values: unknown yields to the other, two
/// different values to `conflict`.
fn meet(a: ir.Ref, b: ir.Ref) ir.Ref {
    if (a == .none) return b;
    if (b == .none or a == b) return a;
    return conflict;
}

fn edgeKey(pred: u32, succ: u32) u64 {
    return (@as(u64, pred) << 32) | succ;
}

/// Whether `inst` may join a web: a list push that is neither a counted fill nor a push
/// into a stack list, a buffer append, or a phi of lists or buffers.
fn candidate(module: *const ir.Module, inst: ir.Inst) bool {
    return switch (inst.op) {
        .list_push => inst.data == 0,
        .buffer_append => true,
        .phi => inst.ty == .byte_buffer or module.kind(inst.ty) == .list,
        else => false,
    };
}

fn isUpdate(op: ir.Op) bool {
    return op == .list_push or op == .buffer_append;
}

/// The webs of `f` whose slots are worth keeping, with their `alloca` names.
pub fn plan(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function) Error!Plan {
    const n = f.insts.items.len;
    var any = false;
    for (f.insts.items) |inst| any = any or isUpdate(inst.op);
    if (!any) return .{};
    const parent = try arena.alloc(u32, n);
    for (parent, 0..) |*p, i| p.* = @intCast(i);
    const present = try arena.alloc(bool, n);
    @memset(present, false);
    const block_of = try arena.alloc(u32, n);
    @memset(block_of, none);
    const scc = try cycles(arena, f);
    for (f.blocks.items, 0..) |block, b| {
        if (b != 0 and block.preds.items.len == 0) continue;
        for (block.insts.items) |ref| {
            block_of[ref.index()] = @intCast(b);
            // Only values inside loops join webs: one outside is an ordinary value.
            if (scc[b] != none and candidate(module, f.inst(ref))) present[ref.index()] = true;
        }
    }
    // A phi none of whose operands is a web value, or an update of a value that is not one
    // (a literal's pushes, the join of a hoisted uniqueness test), only makes a value that
    // enters a web; its header stays current.
    var pruned = true;
    while (pruned) {
        pruned = false;
        for (f.insts.items, 0..) |inst, i| {
            if (!present[i] or joins(f, present, inst)) continue;
            present[i] = false;
            pruned = true;
        }
    }
    // Join each update with the value it updates, and each phi with its operands.
    for (f.insts.items, 0..) |inst, i| {
        if (!present[i]) continue;
        if (isUpdate(inst.op)) {
            const operand = f.resolve(inst.a);
            if (present[operand.index()]) unite(parent, @intCast(i), @intCast(operand.index()));
        } else for (f.operands(inst.data)) |raw| {
            const operand = f.resolve(raw);
            if (operand != .none and present[operand.index()]) unite(parent, @intCast(i), @intCast(operand.index()));
        }
    }
    var check: Check = .{ .arena = arena, .f = f, .parent = parent, .present = present, .block_of = block_of, .scc = scc };
    const web = try arena.alloc(u32, n);
    @memset(web, none);
    var out: Plan = .{ .web = web };
    var slots: std.ArrayList(Slots) = .empty;
    for (0..n) |i| {
        if (!present[i] or find(parent, @intCast(i)) != i) continue;
        var region: Region = .empty;
        if (!try check.keep(@intCast(i), &region)) continue;
        const id: u32 = @intCast(slots.items.len);
        const pair: Slots = .{ .len = try std.fmt.allocPrint(arena, "%state{d}.len", .{id}), .cap = try std.fmt.allocPrint(arena, "%state{d}.cap", .{id}) };
        try slots.append(arena, pair);
        for (0..n) |j| {
            if (present[j] and find(parent, @intCast(j)) == i) web[j] = id;
        }
        try check.exits(@intCast(i), &region, pair, &out.exits);
    }
    if (slots.items.len == 0) return .{};
    out.slots = slots.items;
    return out;
}

/// The cycles (strongly connected components) a web's values lie in.
const Region = std.AutoHashMapUnmanaged(u32, void);

/// Whether `inst` takes a web value: an update's updated value, or a phi operand.
fn joins(f: *const ir.Function, present: []const bool, inst: ir.Inst) bool {
    if (isUpdate(inst.op)) return present[f.resolve(inst.a).index()];
    for (f.operands(inst.data)) |raw| {
        const operand = f.resolve(raw);
        if (operand != .none and present[operand.index()]) return true;
    }
    return false;
}

fn find(parent: []u32, x: u32) u32 {
    var at = x;
    while (parent[at] != at) {
        parent[at] = parent[parent[at]];
        at = parent[at];
    }
    return at;
}

fn unite(parent: []u32, x: u32, y: u32) void {
    const a = find(parent, x);
    const b = find(parent, y);
    if (a != b) parent[@max(a, b)] = @min(a, b);
}

/// What `Check.keep` weighs a web against.
const Check = struct {
    arena: std.mem.Allocator,
    f: *const ir.Function,
    parent: []u32,
    present: []const bool,
    block_of: []const u32,
    /// Per block: its strongly connected component when that is a cycle, else `none`.
    scc: []const u32,

    fn member(self: *Check, ref: ir.Ref, root: u32) bool {
        return ref != .none and self.present[ref.index()] and find(self.parent, @intCast(ref.index())) == root;
    }

    /// Whether web `root` keeps its length in slots (its region in `region`): it has a phi
    /// and an update; every update updates a member; inside the region, members are used
    /// only by the web's updates (as the value updated) and phis; and every value entering
    /// a phi comes from outside the region on an edge that jumps straight there.
    fn keep(self: *Check, root: u32, region: *Region) Error!bool {
        const f = self.f;
        var updates = false;
        var phis = false;
        for (f.insts.items, 0..) |inst, i| {
            if (!self.member(@fromBackingInt(@intCast(i)), root)) continue;
            try region.put(self.arena, self.scc[self.block_of[i]], {});
            if (isUpdate(inst.op)) {
                updates = true;
                if (!self.member(f.resolve(inst.a), root)) return false;
            } else phis = true;
        }
        if (!updates or !phis) return false;
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op == .copy) continue;
                const fits = if (inst.op == .phi) self.phiFits(region, root, ref, @intCast(b)) else self.useFits(region, root, ref, @intCast(b));
                if (!fits) return false;
            }
        }
        return true;
    }

    /// A phi of the web takes each entering value from outside the region on an edge that
    /// jumps straight to it (where the slots are loaded).
    fn phiFits(self: *Check, region: *const Region, root: u32, ref: ir.Ref, b: u32) bool {
        const f = self.f;
        if (!self.member(ref, root)) return true;
        for (f.operands(f.inst(ref).data), f.blocks.items[b].preds.items) |raw, pred| {
            if (self.member(f.resolve(raw), root)) continue;
            const p = @backingInt(pred);
            if (self.inside(region, p) or !endsInJump(f, p)) return false;
        }
        return true;
    }

    /// Inside the region, an instruction reads a web value only as the value a web update
    /// updates.
    fn useFits(self: *Check, region: *const Region, root: u32, ref: ir.Ref, b: u32) bool {
        const f = self.f;
        if (!self.inside(region, b)) return true;
        const mine = self.member(ref, root);
        const operands = f.valueOperands(f.inst(ref));
        for (0..operands.len()) |k| {
            if (!self.member(f.resolve(operands.get(k)), root)) continue;
            if (!mine or k != 0) return false;
        }
        return true;
    }

    /// The stores on the edges leaving the region: each of the web value current at the
    /// end of the region block it leaves from (the block's last update or phi of the web,
    /// else the one every predecessor agrees on). Where paths disagree (or one comes from
    /// outside the region) no web value is live past the block, and nothing is stored.
    fn exits(self: *Check, root: u32, region: *const Region, slots: Slots, out: *std.AutoHashMapUnmanaged(u64, std.ArrayList(Exit))) Error!void {
        const f = self.f;
        const count = f.blocks.items.len;
        // `.none` is not known yet; `conflict` is no one value.
        const current = try self.arena.alloc(ir.Ref, count);
        @memset(current, .none);
        var changed = true;
        while (changed) {
            changed = false;
            for (f.blocks.items, 0..) |block, b| {
                if (!self.inside(region, @intCast(b))) continue;
                var value: ir.Ref = .none;
                for (block.preds.items) |pred| {
                    const from = if (self.inside(region, @intCast(pred.index()))) current[pred.index()] else conflict;
                    value = meet(value, from);
                }
                for (block.insts.items) |ref| {
                    if (self.member(ref, root)) value = ref;
                }
                if (current[b] != value) {
                    current[b] = value;
                    changed = true;
                }
            }
        }
        for (f.blocks.items, 0..) |_, b| {
            if (!self.inside(region, @intCast(b)) or current[b] == .none or current[b] == conflict) continue;
            for (own.successors(f, @intCast(b)).slice()) |s| {
                if (self.inside(region, s)) continue;
                const entry = try out.getOrPut(self.arena, edgeKey(@intCast(b), s));
                if (!entry.found_existing) entry.value_ptr.* = .empty;
                try entry.value_ptr.append(self.arena, .{ .value = current[b], .slots = slots });
            }
        }
    }

    fn inside(self: *const Check, region: *const Region, block: u32) bool {
        const component = self.scc[block];
        return component != none and region.contains(component);
    }
};

fn endsInJump(f: *const ir.Function, block: u32) bool {
    const insts = f.blocks.items[block].insts.items;
    return insts.len != 0 and f.inst(insts[insts.len - 1]).op == .jump;
}

/// Per block, the strongly connected component of the control-flow graph it belongs to
/// when that component is a cycle (several blocks, or one that jumps to itself), else
/// `none` (Tarjan's algorithm, iterative).
fn cycles(arena: std.mem.Allocator, f: *const ir.Function) Error![]u32 {
    const count = f.blocks.items.len;
    const index = try arena.alloc(u32, count);
    const low = try arena.alloc(u32, count);
    const on_stack = try arena.alloc(bool, count);
    const out = try arena.alloc(u32, count);
    @memset(index, none);
    @memset(on_stack, false);
    @memset(out, none);
    var stack: std.ArrayList(u32) = .empty;
    const Frame = struct { block: u32, next: u32 };
    var frames: std.ArrayList(Frame) = .empty;
    var next_index: u32 = 0;
    var next_component: u32 = 0;
    for (0..count) |start| {
        if (index[start] != none or (start != 0 and f.blocks.items[start].preds.items.len == 0)) continue;
        try frames.append(arena, .{ .block = @intCast(start), .next = 0 });
        index[start] = next_index;
        low[start] = next_index;
        next_index += 1;
        try stack.append(arena, @intCast(start));
        on_stack[start] = true;
        while (frames.items.len != 0) {
            const top = &frames.items[frames.items.len - 1];
            const succ = own.successors(f, top.block);
            if (top.next < succ.len) {
                const s = succ.slice()[top.next];
                top.next += 1;
                if (index[s] == none) {
                    index[s] = next_index;
                    low[s] = next_index;
                    next_index += 1;
                    try stack.append(arena, s);
                    on_stack[s] = true;
                    try frames.append(arena, .{ .block = s, .next = 0 });
                } else if (on_stack[s]) low[top.block] = @min(low[top.block], index[s]);
                continue;
            }
            const done = top.block;
            _ = frames.pop();
            if (frames.items.len != 0) {
                const caller = frames.items[frames.items.len - 1].block;
                low[caller] = @min(low[caller], low[done]);
            }
            if (low[done] != index[done]) continue;
            // `done` roots a component: everything above it on the stack.
            var members: usize = 0;
            var self_loop = false;
            for (own.successors(f, done).slice()) |s| self_loop = self_loop or s == done;
            const base = stack.items.len;
            var at = base;
            while (at > 0) {
                at -= 1;
                members += 1;
                if (stack.items[at] == done) break;
            }
            const component: u32 = if (members > 1 or self_loop) next_component else none;
            if (component != none) next_component += 1;
            for (stack.items[at..base]) |b| {
                on_stack[b] = false;
                out[b] = component;
            }
            stack.shrinkRetainingCapacity(at);
        }
    }
    return out;
}

/// The two slots' `alloca`s, for the entry block.
pub fn allocas(plan_of: *const Plan, out: *std.ArrayList(u8), arena: std.mem.Allocator) Error!void {
    for (plan_of.slots) |slots| try out.print(arena, "  {s} = alloca i64, align 8\n  {s} = alloca i64, align 8\n", .{ slots.len, slots.cap });
}

/// Load block `block`'s length and capacity (its header) into `slots`.
pub fn load(comptime Context: type, context: Context, out: *std.ArrayList(u8), block: []const u8, slots: Slots) EmitError!void {
    const a = context.a();
    const at = try context.fresh("%stl");
    const len = try context.fresh("%stl");
    const cap_at = try context.fresh("%stc");
    const cap = try context.fresh("%stc");
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  {s} = load i64, ptr {s}, align 8, !tbaa !5\n  store i64 {s}, ptr {s}, align 8\n", .{ at, block, len, at, len, slots.len });
    try out.print(a, "  {s} = getelementptr inbounds i8, ptr {s}, i64 16\n  {s} = load i64, ptr {s}, align 8, !tbaa !5\n  store i64 {s}, ptr {s}, align 8\n", .{ cap_at, block, cap, cap_at, cap, slots.cap });
}

/// Store the slots' length into block `block`'s header, which is current again.
pub fn store(comptime Context: type, context: Context, out: *std.ArrayList(u8), block: []const u8, slots: Slots) EmitError!void {
    const len = try context.fresh("%sts");
    const at = try context.fresh("%sts");
    try out.print(context.a(), "  {s} = load i64, ptr {s}, align 8\n  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  store i64 {s}, ptr {s}, align 8, !tbaa !5\n", .{ len, slots.len, at, block, len, at });
}

/// Before the jump that ends block `pred`, to `target`: the store of a web's length when
/// the edge leaves its region, and the loads of the slots for each web phi of `target`
/// that takes a value from outside its web.
pub fn jump(comptime Context: type, context: Context, out: *std.ArrayList(u8), pred: u32, target: u32) EmitError!void {
    const states = &context.memory.states;
    if (states.slots.len == 0) return;
    for (states.exit(pred, target)) |leaving| try store(Context, context, out, try context.value(leaving.value), leaving.slots);
    const f = context.function;
    const block = f.blocks.items[target];
    const position = for (block.preds.items, 0..) |p, i| {
        if (@backingInt(p) == pred) break i;
    } else return;
    for (block.insts.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op == .copy) continue;
        if (inst.op != .phi) break;
        const slots = states.of(ref) orelse continue;
        const operand = f.resolve(f.operands(inst.data)[position]);
        if (states.of(operand) == null) try load(Context, context, out, try context.value(operand), slots);
    }
}
