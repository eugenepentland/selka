//! Ownership and one-count RC (docs/design/new-core-s1.md §5-§6, §13 R-2).
//!
//! Runs per function after the facts (release) or right after construction
//! (debug), and turns the value-semantic Core IR into counted code in two phases.
//!
//! **Values.** Every managed value (a block pointer, or a record or union holding
//! one) is *owned* (+1: constructors, updates, calls, phis, `list_copy`), *borrowed*
//! (parameters; reads of a managed part of another value: `list_get`,
//! `list_get_field`, `record_get`, `union_payload`, `box_get`, valid while that
//! parent is) or *immortal* (string constants, `undef`). A consuming use (an update's
//! list, a stored value, a returned value, a phi operand on its edge) takes one owner;
//! every other use borrows. Calls borrow their arguments.
//!
//! **Phase A, copy on write** (§5). Each in-place update (`list_push`, `list_set`,
//! `list_pop`) of list `a` takes one form:
//! 1. `a` owned, the update its last use, and statically unique (fresh from
//!    `list_new`, `list_copy` or another update, or a phi of such values, and never
//!    shared by a call or a retained use): in place, no test (verify builds assert
//!    `count == 1` and trap `R_CORE_FACT`);
//! 2. `a` owned and this its last use, but maybe shared: `if is_unique(a)` in place,
//!    else `c = list_copy(a); release(a)` and update `c`;
//! 3. `a` borrowed, or used after the update: update `list_copy(a)`.
//! A `record_set` of a managed field extracts the field it drops (released after),
//! and the `list_get` that reads a popped element owns it (§2.1).
//!
//! **Phase B, counting** (§6). Per owned value, liveness over the blocks:
//! - the last use moves the value when it consumes it; any other consuming use gets
//!   a `retain` first;
//! - a value that dies without a consuming last use is released right after it,
//!   or on the CFG edge where it dies (in the successor when that has one
//!   predecessor, else at the end of the predecessor when that has one successor,
//!   else in a block split into the edge). Early returns and `?` paths are edges like
//!   any other; paths into a block ending in `unreachable` (a trap) release nothing;
//! - a borrowed or immortal value that a consuming use takes is retained first
//!   (immortals need no count);
//! - a borrowed part stays valid because its parent's liveness covers the part's
//!   uses; when the parent is consumed while the part is still used, the part is
//!   *promoted* instead: retained right after it is read and owned from there on.
//! A final peephole drops `retain x … release x` pairs in one block with nothing
//! but pure reads between them (R-2: LLVM cannot fold such a pair itself).
const std = @import("std");
const ir = @import("ir.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// How the pass runs.
pub const Options = struct {
    /// Verify builds assert every statically unique update (form 1) at run time.
    verify: bool = false,
};

/// What the pass did, summed over functions.
pub const Stats = struct {
    in_place: u32 = 0,
    tested: u32 = 0,
    copied: u32 = 0,
    retains: u32 = 0,
    releases: u32 = 0,
    /// `retain x … release x` pairs the peephole removed.
    elided: u32 = 0,
    /// Blocks the pass added (copy-on-write arms, asserts, split edges).
    blocks: u32 = 0,

    /// Add `other`'s counts to these.
    pub fn add(self: *Stats, other: Stats) void {
        self.in_place += other.in_place;
        self.tested += other.tested;
        self.copied += other.copied;
        self.retains += other.retains;
        self.releases += other.releases;
        self.elided += other.elided;
        self.blocks += other.blocks;
    }
};

/// The `data` of an `unreachable` that asserts a statically unique update: verify
/// builds emit it as an `R_CORE_FACT` trap (`emit_llvm.zig`).
pub const unique_assert: u64 = 1;

/// Run the pass over every internal function of `module`.
pub fn run(arena: std.mem.Allocator, module: *ir.Module, options: Options) Error!Stats {
    var total: Stats = .{};
    for (module.functions.items) |*f| {
        if (f.signature.linkage != .internal) continue;
        total.add(try function(arena, module, f, options));
    }
    return total;
}

/// Run the pass over one function of `module`.
pub fn function(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, options: Options) Error!Stats {
    var stats: Stats = .{};
    const blocks_before = f.blocks.items.len;
    var marks: Marks = .{};
    // Popped elements are found (or read) before anything moves.
    try markPops(.{ .arena = arena, .f = f }, module, &marks);
    var phase_a = try Analysis.of(arena, module, f, &marks);
    try phase_a.analyze();
    try copyOnWrite(&phase_a, options, &stats);
    var phase_b = try Analysis.of(arena, module, f, &marks);
    try phase_b.analyze();
    try count(&phase_b, &stats);
    stats.elided = try elidePairs(arena, f);
    stats.retains -= stats.elided;
    stats.releases -= stats.elided;
    stats.blocks = @intCast(f.blocks.items.len - blocks_before);
    return stats;
}

// ---- analysis -------------------------------------------------------------------

/// How a managed value holds its blocks.
const Class = enum(u8) { none, owned, borrowed, immortal };

/// One use of a value: at instruction `pos` of `block`, or (for a phi operand) on the
/// edge from `block` to `succ`, with how many operand slots consume and borrow it.
const Use = struct {
    block: u32,
    pos: u32,
    /// The successor of a phi-operand use; `no_block` for an ordinary use.
    succ: u32 = no_block,
    consume: u16 = 0,
    borrow: u16 = 0,

    fn onEdge(self: Use) bool {
        return self.succ != no_block;
    }
};

const no_block = std.math.maxInt(u32);

/// What phase A hands to phase B: the reads that own what they read (popped
/// elements, the field a `record_set` drops).
const Marks = struct {
    owned_get: std.AutoHashMapUnmanaged(u32, void) = .empty,
};

/// Where a value is live, by block.
const Live = struct {
    in: std.DynamicBitSetUnmanaged,
    out: std.DynamicBitSetUnmanaged,
    /// The uses this liveness was computed from (its own and its borrowed parts').
    uses: []const Use,
    def: u32,
};

const Analysis = struct {
    arena: std.mem.Allocator,
    module: *const ir.Module,
    f: *ir.Function,
    marks: *Marks,
    /// Per instruction: its block (`no_block` outside every block) and position.
    where: []Where,
    class: []Class,
    /// The value a borrowed part was read from (`none` for roots).
    parent: []ir.Ref,
    /// Per value: the borrowed parts read from it.
    children: []std.ArrayList(ir.Ref),
    promoted: []bool,
    /// Per value: its direct uses.
    uses: []std.ArrayList(Use),
    /// Per value: the liveness used for ownership decisions (null: not computed).
    live: []?Live,
    /// Per block: whether it ends in `unreachable` (a trap path, which releases nothing).
    dead_end: []bool,

    const Where = struct { block: u32 = no_block, pos: u32 = 0 };

    fn of(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, marks: *Marks) Error!Analysis {
        const n = f.insts.items.len;
        const self: Analysis = .{
            .arena = arena,
            .module = module,
            .f = f,
            .marks = marks,
            .where = try arena.alloc(Where, n),
            .class = try arena.alloc(Class, n),
            .parent = try arena.alloc(ir.Ref, n),
            .children = try arena.alloc(std.ArrayList(ir.Ref), n),
            .promoted = try arena.alloc(bool, n),
            .uses = try arena.alloc(std.ArrayList(Use), n),
            .live = try arena.alloc(?Live, n),
            .dead_end = try arena.alloc(bool, f.blocks.items.len),
        };
        @memset(self.where, .{});
        @memset(self.class, .none);
        @memset(self.parent, .none);
        @memset(self.children, .empty);
        @memset(self.promoted, false);
        @memset(self.uses, .empty);
        @memset(self.live, null);
        for (f.blocks.items, 0..) |block, b| {
            for (block.insts.items, 0..) |ref, pos| self.where[ref.index()] = .{ .block = @intCast(b), .pos = @intCast(pos) };
            const insts = block.insts.items;
            self.dead_end[b] = insts.len != 0 and f.inst(insts[insts.len - 1]).op == .@"unreachable";
        }
        return self;
    }

    fn inst(self: *const Analysis, ref: ir.Ref) ir.Inst {
        return self.f.inst(ref);
    }

    fn managed(self: *const Analysis, ref: ir.Ref) bool {
        return self.module.managed(self.inst(ref).ty);
    }

    /// Whether a block takes part: the entry, or a block with predecessors (the emitter skips the rest).
    fn present(self: *const Analysis, b: usize) bool {
        return b == 0 or self.f.blocks.items[b].preds.items.len != 0;
    }

    /// Owned or promoted: the value holds its own count.
    fn counted(self: *const Analysis, ref: ir.Ref) bool {
        return self.class[ref.index()] == .owned or self.promoted[ref.index()];
    }

    fn analyze(self: *Analysis) Error!void {
        try self.classify();
        try self.collectUses();
        // Promote borrowed parts whose parent is consumed while they are in use, to a fixed point.
        while (true) {
            try self.computeLiveness();
            if (!try self.promote()) break;
        }
    }

    fn classify(self: *Analysis) Error!void {
        const f = self.f;
        for (f.insts.items, 0..) |instruction, i| {
            if (!self.module.managed(instruction.ty)) continue;
            self.class[i] = switch (instruction.op) {
                .param => .borrowed,
                .str_const, .undef => .immortal,
                .copy => .none,
                .list_get, .list_get_field, .record_get, .union_payload, .box_get => blk: {
                    if (self.marks.owned_get.contains(@intCast(i))) break :blk .owned;
                    self.parent[i] = f.resolve(instruction.a);
                    break :blk .borrowed;
                },
                else => .owned,
            };
        }
        // A phi no live instruction reads is ignored (its operands are not consumed).
        const live_phi = try self.livePhis();
        for (f.insts.items, 0..) |instruction, i| {
            if (instruction.op == .phi and !live_phi[i]) self.class[i] = .none;
        }
        for (self.parent, 0..) |p, child| {
            if (p != .none and self.class[child] == .borrowed) try self.children[p.index()].append(self.arena, @fromBackingInt(@intCast(child)));
        }
    }

    /// Phis read by a non-phi instruction, directly or through other live phis.
    fn livePhis(self: *Analysis) Error![]bool {
        const f = self.f;
        const live = try self.arena.alloc(bool, f.insts.items.len);
        @memset(live, false);
        var stack: std.ArrayList(ir.Ref) = .empty;
        for (f.blocks.items, 0..) |block, b| {
            if (!self.present(b)) continue;
            for (block.insts.items) |ref| {
                const instruction = f.inst(ref);
                if (instruction.op == .phi or instruction.op == .copy) continue;
                const operands = f.valueOperands(instruction);
                for (0..operands.len()) |k| try self.markPhi(f.resolve(operands.get(k)), live, &stack);
            }
        }
        while (stack.pop()) |phi| {
            for (f.operands(f.inst(phi).data)) |operand| try self.markPhi(f.resolve(operand), live, &stack);
        }
        return live;
    }

    fn markPhi(self: *Analysis, used: ir.Ref, live: []bool, stack: *std.ArrayList(ir.Ref)) Error!void {
        if (used == .none or self.f.inst(used).op != .phi or live[used.index()]) return;
        live[used.index()] = true;
        try stack.append(self.arena, used);
    }

    fn collectUses(self: *Analysis) Error!void {
        const f = self.f;
        for (f.blocks.items, 0..) |block, b| {
            if (!self.present(b)) continue;
            for (block.insts.items, 0..) |ref, pos| {
                const instruction = f.inst(ref);
                if (instruction.op == .copy) continue;
                if (instruction.op == .phi) {
                    if (self.class[ref.index()] == .none) continue;
                    for (f.operands(instruction.data), block.preds.items) |operand, pred| {
                        try self.addUse(f.resolve(operand), .{ .block = @backingInt(pred), .pos = 0, .succ = @intCast(b), .consume = 1 });
                    }
                    continue;
                }
                const operands = f.valueOperands(instruction);
                for (0..operands.len()) |k| {
                    const consumes = consuming(instruction, k);
                    try self.addUse(f.resolve(operands.get(k)), .{ .block = @intCast(b), .pos = @intCast(pos), .consume = @intFromBool(consumes), .borrow = @intFromBool(!consumes) });
                }
            }
        }
    }

    /// Record a use, merging it with an existing use at the same place.
    fn addUse(self: *Analysis, value: ir.Ref, use: Use) Error!void {
        if (value == .none or self.class[value.index()] == .none) return;
        const list = &self.uses[value.index()];
        for (list.items) |*existing| {
            if (existing.block == use.block and existing.pos == use.pos and existing.succ == use.succ) {
                existing.consume += use.consume;
                existing.borrow += use.borrow;
                return;
            }
        }
        try list.append(self.arena, use);
    }

    /// The nearest counted value `ref` was read from, or `none` (a parameter or constant root).
    fn owner(self: *const Analysis, ref: ir.Ref) ir.Ref {
        var current = self.parent[ref.index()];
        while (current != .none) {
            if (self.counted(current)) return current;
            if (self.class[current.index()] != .borrowed) return .none;
            current = self.parent[current.index()];
        }
        return .none;
    }

    /// Every use that keeps `ref` live: its own and, as borrows, those of the borrowed
    /// parts read from it (transitively) that are not counted themselves.
    fn liveUses(self: *Analysis, ref: ir.Ref, out: *std.ArrayList(Use)) Error!void {
        try out.appendSlice(self.arena, self.uses[ref.index()].items);
        for (self.children[ref.index()].items) |child_ref| {
            if (self.counted(child_ref)) continue;
            var nested: std.ArrayList(Use) = .empty;
            try self.liveUses(child_ref, &nested);
            for (nested.items) |use| try out.append(self.arena, .{ .block = use.block, .pos = use.pos, .succ = use.succ, .borrow = use.consume + use.borrow });
        }
    }

    fn computeLiveness(self: *Analysis) Error!void {
        const nblocks = self.f.blocks.items.len;
        for (self.class, 0..) |class, i| {
            self.live[i] = null;
            if (class != .owned and class != .borrowed) continue;
            if (self.where[i].block == no_block) continue;
            const ref: ir.Ref = @fromBackingInt(@intCast(i));
            var uses: std.ArrayList(Use) = .empty;
            try self.liveUses(ref, &uses);
            var live: Live = .{
                .in = try std.DynamicBitSetUnmanaged.initEmpty(self.arena, nblocks),
                .out = try std.DynamicBitSetUnmanaged.initEmpty(self.arena, nblocks),
                .uses = uses.items,
                .def = self.where[i].block,
            };
            var stack: std.ArrayList(u32) = .empty;
            for (uses.items) |use| {
                if (use.onEdge()) live.out.set(use.block);
                if (use.block != live.def and !live.in.isSet(use.block)) {
                    live.in.set(use.block);
                    try stack.append(self.arena, use.block);
                }
            }
            while (stack.pop()) |b| {
                for (self.f.blocks.items[b].preds.items) |pred_id| {
                    const pred = @backingInt(pred_id);
                    live.out.set(pred);
                    if (pred != live.def and !live.in.isSet(pred)) {
                        live.in.set(pred);
                        try stack.append(self.arena, pred);
                    }
                }
            }
            self.live[i] = live;
        }
    }

    /// Whether `ref` is still needed after instruction `pos` of `block`.
    fn liveAfter(self: *const Analysis, ref: ir.Ref, block: u32, pos: u32) bool {
        const live = self.live[ref.index()] orelse return false;
        if (live.out.isSet(block)) return true;
        for (live.uses) |use| {
            if (!use.onEdge() and use.block == block and use.pos > pos) return true;
        }
        return false;
    }

    /// Whether `ref` is needed in `succ` itself or beyond (its phis aside).
    fn liveInto(self: *const Analysis, ref: ir.Ref, succ: u32) bool {
        const live = self.live[ref.index()] orelse return false;
        return succ != live.def and live.in.isSet(succ);
    }

    /// Promote every borrowed part whose counted owner is consumed while it is in use;
    /// returns whether any was promoted.
    fn promote(self: *Analysis) Error!bool {
        var changed = false;
        for (self.class, 0..) |class, i| {
            if (class != .borrowed or self.promoted[i] or self.parent[i] == .none) continue;
            const ref: ir.Ref = @fromBackingInt(@intCast(i));
            const holder = self.owner(ref);
            if (holder == .none) continue;
            for (self.uses[holder.index()].items) |use| {
                if (use.consume == 0) continue;
                const still = if (use.onEdge()) self.liveInto(ref, use.succ) else self.liveAfter(ref, use.block, use.pos);
                if (still) {
                    self.promoted[i] = true;
                    changed = true;
                    break;
                }
            }
        }
        return changed;
    }
};

/// Whether operand `k` (in `valueOperands` order) of `instruction` is consumed.
fn consuming(instruction: ir.Inst, k: usize) bool {
    return switch (instruction.op) {
        // a (the list) and b (the value); a (the record) and b (the field value).
        .list_push, .record_set => true,
        // a (the list), b (the index), then extra[0] (the value).
        .list_set => k != 1,
        .list_pop, .union_make, .box_make, .ret, .release, .record_make => true,
        else => false,
    };
}

/// Whether `op` updates its list operand in place.
fn isUpdate(op: ir.Op) bool {
    return op == .list_push or op == .list_set or op == .list_pop;
}

// ---- phase A: copy on write -------------------------------------------------------

/// Whether updating `value` at `site` may skip the uniqueness test: it comes fresh
/// from an allocation, a copy or another update (or phis of those), and no use
/// before shares it.
fn staticallyUnique(a: *const Analysis, value: ir.Ref, site: ir.Ref) Error!bool {
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    var stack: std.ArrayList(ir.Ref) = .empty;
    try stack.append(a.arena, value);
    try seen.put(a.arena, @backingInt(value), {});
    while (stack.pop()) |current| {
        if (a.class[current.index()] != .owned) return false;
        const instruction = a.inst(current);
        switch (instruction.op) {
            .list_new, .list_copy, .list_push, .list_set, .list_pop => {},
            .phi => for (a.f.operands(instruction.data)) |operand| {
                const source = a.f.resolve(operand);
                if (seen.contains(@backingInt(source))) continue;
                try seen.put(a.arena, @backingInt(source), {});
                try stack.append(a.arena, source);
            },
            else => return false,
        }
        if (shared(a, current, site)) return false;
    }
    return true;
}

/// Whether some use of `value` other than `site` may give its block a second owner:
/// a call argument, or a consuming use the value outlives (it gets a retain).
fn shared(a: *const Analysis, value: ir.Ref, site: ir.Ref) bool {
    for (a.uses[value.index()].items) |use| {
        if (use.onEdge()) {
            if (use.consume > 1 or a.liveInto(value, use.succ)) return true;
            continue;
        }
        const at = a.f.blocks.items[use.block].insts.items[use.pos];
        if (at == site) continue;
        if (a.inst(at).op == .call) return true;
        if (use.consume > 1 or (use.consume == 1 and a.liveAfter(value, use.block, use.pos))) return true;
    }
    return false;
}

/// Phase A: give every in-place update its form, extract the fields `record_set`
/// drops, and mark the elements popped lists hand over.
fn copyOnWrite(a: *Analysis, options: Options, stats: *Stats) Error!void {
    const f = a.f;
    const Form = enum { in_place, tested, copied };
    const Site = struct { update: ir.Ref, form: Form };
    // Decide every form on the unchanged IR, then rewrite.
    var sites: std.ArrayList(Site) = .empty;
    for (f.blocks.items, 0..) |block, b| {
        if (!a.present(b)) continue;
        for (block.insts.items, 0..) |ref, pos| {
            const instruction = f.inst(ref);
            if (!isUpdate(instruction.op)) continue;
            const list = f.resolve(instruction.a);
            const form: Form = if (!a.counted(list) or a.liveAfter(list, @intCast(b), @intCast(pos)))
                .copied
            else if (try staticallyUnique(a, list, ref)) .in_place else .tested;
            try sites.append(a.arena, .{ .update = ref, .form = form });
        }
    }
    const e: Editor = .{ .arena = a.arena, .f = f };
    for (sites.items) |site| switch (site.form) {
        .copied => {
            stats.copied += 1;
            const update = f.inst(site.update);
            const copy = try e.insertBefore(site.update, .{ .op = .list_copy, .ty = update.ty, .a = update.a, .span = update.span });
            f.insts.items[site.update.index()].a = copy;
        },
        .tested => {
            stats.tested += 1;
            try testUnique(e, site.update);
        },
        .in_place => {
            stats.in_place += 1;
            if (options.verify) try assertUnique(e, site.update);
        },
    };
    try extractDroppedFields(a);
}

/// Split the block of `update` before it: `if is_unique(a)` the update runs on `a`,
/// else on `c = list_copy(a)` after `release(a)`; both reach it through a phi.
fn testUnique(e: Editor, update: ir.Ref) Error!void {
    const f = e.f;
    const instruction = f.inst(update);
    const list = instruction.a;
    const ty = f.inst(f.resolve(list)).ty;
    const at = try e.split(update);
    const unique = try e.append(at.head, .{ .op = .is_unique, .ty = .bool, .a = list, .span = instruction.span });
    const copy_block = try e.newBlock();
    try e.terminate(at.head, .{ .op = .branch, .ty = .void, .a = unique, .data = ir.packTargets(at.tail, copy_block), .span = instruction.span }, &.{ at.tail, copy_block });
    const copy = try e.append(copy_block, .{ .op = .list_copy, .ty = ty, .a = list, .span = instruction.span });
    _ = try e.append(copy_block, .{ .op = .release, .ty = .void, .a = list, .span = instruction.span });
    try e.terminate(copy_block, .{ .op = .jump, .ty = .void, .data = @backingInt(at.tail), .span = instruction.span }, &.{at.tail});
    // The tail's predecessors are [head, copy_block], in that order.
    const phi = try e.newInst(.{ .op = .phi, .ty = ty, .data = try e.extraOf(&.{ list, copy }), .span = instruction.span });
    try f.blocks.items[at.tail.index()].insts.insert(e.arena, 0, phi);
    f.insts.items[update.index()].a = phi;
}

/// Verify builds: trap `R_CORE_FACT` before a form-1 update unless its list's count is 1.
fn assertUnique(e: Editor, update: ir.Ref) Error!void {
    const instruction = e.f.inst(update);
    const at = try e.split(update);
    const unique = try e.append(at.head, .{ .op = .is_unique, .ty = .bool, .a = instruction.a, .span = instruction.span });
    const fail = try e.newBlock();
    try e.terminate(at.head, .{ .op = .branch, .ty = .void, .a = unique, .data = ir.packTargets(at.tail, fail), .span = instruction.span }, &.{ at.tail, fail });
    _ = try e.append(fail, .{ .op = .@"unreachable", .ty = .void, .data = unique_assert, .span = instruction.span });
}

/// Mark the `list_get` that reads the element a `list_pop` drops: it owns that element.
/// A pop with no such read gets one after it, released at once.
fn markPops(e: Editor, module: *const ir.Module, marks: *Marks) Error!void {
    const f = e.f;
    var b: usize = 0;
    while (b < f.blocks.items.len) : (b += 1) {
        var pos: usize = 0;
        while (pos < f.blocks.items[b].insts.items.len) : (pos += 1) {
            const ref = f.blocks.items[b].insts.items[pos];
            const pop = f.inst(ref);
            if (pop.op != .list_pop) continue;
            const element = module.compound(pop.ty).list;
            if (!module.managed(element)) continue;
            if (poppedRead(f, f.blocks.items[b].insts.items[0..pos], f.resolve(pop.a))) |read| {
                try marks.owned_get.put(e.arena, @backingInt(read), {});
                continue;
            }
            // The popped slot still holds the element: a pop only shortens the list.
            const len = try e.insertAfter(ref, .{ .op = .list_len, .ty = .u64, .a = ref, .span = pop.span });
            const got = try e.insertAfter(len, .{ .op = .list_get, .ty = element, .a = ref, .b = len, .span = pop.span });
            try marks.owned_get.put(e.arena, @backingInt(got), {});
            _ = try e.insertAfter(got, .{ .op = .release, .ty = .void, .a = got, .span = pop.span });
            pos += 3;
        }
    }
}

/// The last `list_get` of `list` among `earlier` (the instructions before its pop).
fn poppedRead(f: *const ir.Function, earlier: []const ir.Ref, list: ir.Ref) ?ir.Ref {
    var back = earlier.len;
    while (back > 0) {
        back -= 1;
        const candidate = f.inst(earlier[back]);
        if (candidate.op == .list_get and f.resolve(candidate.a) == list) return earlier[back];
    }
    return null;
}

/// Before each `record_set` of a managed field, read the field it drops (an owned
/// value: the record's reference to it goes with the consumed record) and release it after.
fn extractDroppedFields(a: *Analysis) Error!void {
    const f = a.f;
    const e: Editor = .{ .arena = a.arena, .f = f };
    var b: usize = 0;
    while (b < f.blocks.items.len) : (b += 1) {
        var pos: usize = 0;
        while (pos < f.blocks.items[b].insts.items.len) : (pos += 1) {
            const ref = f.blocks.items[b].insts.items[pos];
            const set = f.inst(ref);
            if (set.op != .record_set) continue;
            const field = a.module.compound(set.ty).record[@intCast(set.data)];
            if (!a.module.managed(field)) continue;
            const old = try e.insertBefore(ref, .{ .op = .record_get, .ty = field, .a = set.a, .data = set.data, .span = set.span });
            try a.marks.owned_get.put(a.arena, @backingInt(old), {});
            _ = try e.insertAfter(ref, .{ .op = .release, .ty = .void, .a = old, .span = set.span });
            pos += 2;
        }
    }
}

// ---- phase B: counting ----------------------------------------------------------

/// Where a counting instruction goes.
const Place = union(enum) {
    before: ir.Ref,
    after: ir.Ref,
    /// The top of a block, after its phis.
    top: u32,
    edge: struct { from: u32, to: u32 },
};

const Action = struct { place: Place, op: ir.Op, value: ir.Ref };

fn count(a: *Analysis, stats: *Stats) Error!void {
    var actions: std.ArrayList(Action) = .empty;
    for (a.class, 0..) |class, i| {
        if (class == .none) continue;
        const ref: ir.Ref = @fromBackingInt(@intCast(i));
        if (a.counted(ref)) {
            if (a.live[i] != null) try countOwned(a, ref, &actions);
        } else try countBorrowed(a, ref, &actions);
    }
    try apply(a, actions.items, stats);
}

/// Retains for the consuming uses of an owned (or promoted) value, and its releases.
fn countOwned(a: *Analysis, ref: ir.Ref, actions: *std.ArrayList(Action)) Error!void {
    const f = a.f;
    const live = a.live[ref.index()].?;
    if (a.promoted[ref.index()]) try actions.append(a.arena, .{ .place = placeAfterDef(a, ref), .op = .retain, .value = ref });
    // Consuming uses: the last one moves, the others take a retained owner.
    for (a.uses[ref.index()].items) |use| {
        if (use.consume == 0) continue;
        if (use.onEdge()) {
            const extra = use.consume - @intFromBool(!a.liveInto(ref, use.succ));
            for (0..extra) |_| try actions.append(a.arena, .{ .place = .{ .edge = .{ .from = use.block, .to = use.succ } }, .op = .retain, .value = ref });
        } else {
            const extra = use.consume - @intFromBool(!a.liveAfter(ref, use.block, use.pos));
            const at = f.blocks.items[use.block].insts.items[use.pos];
            for (0..extra) |_| try actions.append(a.arena, .{ .place = .{ .before = at }, .op = .retain, .value = ref });
        }
    }
    // Deaths inside blocks: after the last use, when nothing later needs the value.
    for (f.blocks.items, 0..) |block, b| {
        if (!a.present(b) or live.out.isSet(b)) continue;
        var last: ?u32 = null;
        for (live.uses) |use| {
            if (use.onEdge() or use.block != b) continue;
            if (last == null or use.pos > last.?) last = use.pos;
        }
        if (last) |pos| {
            const consumed = for (a.uses[ref.index()].items) |use| {
                const here = !use.onEdge() and use.block == b and use.pos == pos;
                if (here and use.consume > 0) break true;
            } else false;
            if (consumed) continue;
            const at = block.insts.items[pos];
            const place: Place = if (f.inst(at).op.terminates()) .{ .before = at } else .{ .after = at };
            try actions.append(a.arena, .{ .place = place, .op = .release, .value = ref });
        } else if (b == live.def) {
            // Defined and never used.
            try actions.append(a.arena, .{ .place = placeAfterDef(a, ref), .op = .release, .value = ref });
        }
    }
    // Deaths on edges: live at the end of `b`, but neither needed in a successor nor taken by its phi.
    for (f.blocks.items, 0..) |_, b| {
        if (!a.present(b) or !live.out.isSet(b)) continue;
        const succs = successors(f, @intCast(b));
        for (succs.slice()) |succ| {
            if (a.dead_end[succ] or a.liveInto(ref, succ)) continue;
            const taken = for (a.uses[ref.index()].items) |use| {
                if (use.onEdge() and use.block == b and use.succ == succ) break true;
            } else false;
            if (!taken) try actions.append(a.arena, .{ .place = .{ .edge = .{ .from = @intCast(b), .to = succ } }, .op = .release, .value = ref });
        }
    }
}

/// A borrowed value that a consuming use takes is retained first; an immortal one
/// needs no count.
fn countBorrowed(a: *Analysis, ref: ir.Ref, actions: *std.ArrayList(Action)) Error!void {
    if (a.class[ref.index()] == .immortal) return;
    for (a.uses[ref.index()].items) |use| {
        for (0..use.consume) |_| {
            const place: Place = if (use.onEdge())
                .{ .edge = .{ .from = use.block, .to = use.succ } }
            else
                .{ .before = a.f.blocks.items[use.block].insts.items[use.pos] };
            try actions.append(a.arena, .{ .place = place, .op = .retain, .value = ref });
        }
    }
}

/// Right after `ref` is defined: after its block's phi group for a phi.
fn placeAfterDef(a: *const Analysis, ref: ir.Ref) Place {
    if (a.inst(ref).op == .phi) return .{ .top = a.where[ref.index()].block };
    return .{ .after = ref };
}

const Lists = std.AutoHashMapUnmanaged(u32, std.ArrayList(ir.Ref));

/// Insert the counting instructions. Retains go before releases at the same place,
/// so a value that a use both retains (to consume) and lets die is never freed first.
fn apply(a: *Analysis, actions: []const Action, stats: *Stats) Error!void {
    const f = a.f;
    const arena = a.arena;
    const e: Editor = .{ .arena = arena, .f = f };
    var before: Lists = .empty;
    var after: Lists = .empty;
    var top: Lists = .empty;
    var edges: std.array_hash_map.Auto(u64, std.ArrayList(ir.Ref)) = .empty;
    for ([_]ir.Op{ .retain, .release }) |op| {
        for (actions) |action| {
            if (action.op != op) continue;
            const counted = try e.newInst(.{ .op = op, .ty = .void, .a = action.value, .span = f.inst(action.value).span });
            if (op == .retain) stats.retains += 1 else stats.releases += 1;
            const list = switch (action.place) {
                .before => |at| try listFor(arena, &before, @backingInt(at)),
                .after => |at| try listFor(arena, &after, @backingInt(at)),
                .top => |b| try listFor(arena, &top, b),
                .edge => |edge| blk: {
                    const entry = try edges.getOrPut(arena, (@as(u64, edge.from) << 32) | edge.to);
                    if (!entry.found_existing) entry.value_ptr.* = .empty;
                    break :blk entry.value_ptr;
                },
            };
            try list.append(arena, counted);
        }
    }
    // An edge's instructions go into a single-predecessor successor, at the end of a
    // single-successor predecessor, or into a new block split into the edge.
    var edge_iterator = edges.iterator();
    while (edge_iterator.next()) |entry| {
        const from: u32 = @intCast(entry.key_ptr.* >> 32);
        const to: u32 = @truncate(entry.key_ptr.*);
        if (f.blocks.items[to].preds.items.len == 1) {
            const list = try listFor(arena, &top, to);
            try list.insertSlice(arena, 0, entry.value_ptr.items);
        } else if (successors(f, from).len == 1) {
            const insts = f.blocks.items[from].insts.items;
            const list = try listFor(arena, &before, @backingInt(insts[insts.len - 1]));
            try list.appendSlice(arena, entry.value_ptr.items);
        } else try e.splitEdge(from, to, entry.value_ptr.items);
    }
    for (f.blocks.items, 0..) |*block, b| {
        var rebuilt: std.ArrayList(ir.Ref) = .empty;
        var phis_done = false;
        for (block.insts.items) |ref| {
            const op = f.inst(ref).op;
            if (!phis_done and op != .phi) {
                phis_done = true;
                if (top.get(@intCast(b))) |list| try rebuilt.appendSlice(arena, list.items);
            }
            if (before.get(@backingInt(ref))) |list| try rebuilt.appendSlice(arena, list.items);
            try rebuilt.append(arena, ref);
            if (after.get(@backingInt(ref))) |list| try rebuilt.appendSlice(arena, list.items);
        }
        block.insts = rebuilt;
    }
}

fn listFor(arena: std.mem.Allocator, map: *Lists, key: u32) Error!*std.ArrayList(ir.Ref) {
    const entry = try map.getOrPut(arena, key);
    if (!entry.found_existing) entry.value_ptr.* = .empty;
    return entry.value_ptr;
}

// ---- R-2 peephole ---------------------------------------------------------------

/// Drop `retain x … release x` in one block when only pure operations lie between
/// them (nothing that consumes, frees or calls); returns how many pairs it dropped.
pub fn elidePairs(arena: std.mem.Allocator, f: *ir.Function) Error!u32 {
    var dropped: u32 = 0;
    for (f.blocks.items) |*block| {
        const keep = try arena.alloc(bool, block.insts.items.len);
        @memset(keep, true);
        for (block.insts.items, 0..) |ref, i| {
            const retain = f.inst(ref);
            if (retain.op != .retain) continue;
            const value = f.resolve(retain.a);
            for (block.insts.items[i + 1 ..], i + 1..) |later_ref, j| {
                const later = f.inst(later_ref);
                if (later.op == .release and keep[j] and f.resolve(later.a) == value) {
                    keep[i] = false;
                    keep[j] = false;
                    dropped += 1;
                    break;
                }
                if (!pure(later.op)) break;
            }
        }
        var rebuilt: std.ArrayList(ir.Ref) = .empty;
        for (block.insts.items, keep) |ref, kept| if (kept) try rebuilt.append(arena, ref);
        block.insts = rebuilt;
    }
    return dropped;
}

/// Operations that neither consume nor free a value nor call out.
fn pure(op: ir.Op) bool {
    return switch (op) {
        .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem, .neg, .bit_and, .bit_or, .bit_xor, .not, .cmp => true,
        .fadd, .fsub, .fmul, .fdiv, .fneg, .fcmp, .int_to_float, .float_to_int, .convert => true,
        .list_len, .list_get, .list_get_field, .str_len, .record_get, .union_tag, .union_payload, .box_get, .is_unique, .retain => true,
        else => false,
    };
}

// ---- IR editing -----------------------------------------------------------------

/// Small edits of one function's blocks and instructions, allocating in `arena`.
const Editor = struct {
    arena: std.mem.Allocator,
    f: *ir.Function,

    fn newInst(e: Editor, instruction: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@intCast(e.f.insts.items.len));
        try e.f.insts.append(e.arena, instruction);
        return ref;
    }

    fn newBlock(e: Editor) Error!ir.BlockId {
        try e.f.blocks.append(e.arena, .{});
        return @fromBackingInt(@intCast(e.f.blocks.items.len - 1));
    }

    fn extraOf(e: Editor, refs: []const ir.Ref) Error!u64 {
        const start: u32 = @intCast(e.f.extra.items.len);
        try e.f.extra.appendSlice(e.arena, refs);
        return (ir.ExtraSlice{ .start = start, .len = @intCast(refs.len) }).pack();
    }

    fn append(e: Editor, block: ir.BlockId, instruction: ir.Inst) Error!ir.Ref {
        const ref = try e.newInst(instruction);
        try e.f.blocks.items[block.index()].insts.append(e.arena, ref);
        return ref;
    }

    /// End `block` with `terminator`, recording `block` as a predecessor of each target.
    fn terminate(e: Editor, block: ir.BlockId, terminator: ir.Inst, targets: []const ir.BlockId) Error!void {
        _ = try e.append(block, terminator);
        for (targets) |target| try e.f.blocks.items[target.index()].preds.append(e.arena, block);
    }

    /// The block and position of `ref`, by search (phase A moves instructions).
    fn locate(e: Editor, ref: ir.Ref) struct { block: usize, pos: usize } {
        for (e.f.blocks.items, 0..) |block, b| {
            if (std.mem.indexOfScalar(ir.Ref, block.insts.items, ref)) |pos| return .{ .block = b, .pos = pos };
        }
        unreachable;
    }

    fn insertBefore(e: Editor, at: ir.Ref, instruction: ir.Inst) Error!ir.Ref {
        const where = e.locate(at);
        const ref = try e.newInst(instruction);
        try e.f.blocks.items[where.block].insts.insert(e.arena, where.pos, ref);
        return ref;
    }

    fn insertAfter(e: Editor, at: ir.Ref, instruction: ir.Inst) Error!ir.Ref {
        const where = e.locate(at);
        const ref = try e.newInst(instruction);
        try e.f.blocks.items[where.block].insts.insert(e.arena, where.pos + 1, ref);
        return ref;
    }

    /// Split the block holding `at` before it: `head` keeps the instructions before `at`
    /// (and no terminator yet), `tail` holds `at` and the rest. The old terminator's
    /// targets name `tail` as their predecessor now, and a loop latch moves with it.
    fn split(e: Editor, at: ir.Ref) Error!struct { head: ir.BlockId, tail: ir.BlockId } {
        const f = e.f;
        const where = e.locate(at);
        const head: ir.BlockId = @fromBackingInt(@intCast(where.block));
        const tail = try e.newBlock();
        try f.blocks.items[tail.index()].insts.appendSlice(e.arena, f.blocks.items[where.block].insts.items[where.pos..]);
        f.blocks.items[where.block].insts.shrinkRetainingCapacity(where.pos);
        for (successors(f, @backingInt(tail)).slice()) |succ| {
            for (f.blocks.items[succ].preds.items) |*pred| {
                if (pred.* == head) pred.* = tail;
            }
        }
        for (f.loops.items) |*loop| {
            if (loop.latch == head) loop.latch = tail;
        }
        return .{ .head = head, .tail = tail };
    }

    /// Put `insts` on the edge `from → to`, in a new block between them.
    fn splitEdge(e: Editor, from: u32, to: u32, insts: []const ir.Ref) Error!void {
        const f = e.f;
        const middle = try e.newBlock();
        const source: ir.BlockId = @fromBackingInt(from);
        const target: ir.BlockId = @fromBackingInt(to);
        try f.blocks.items[middle.index()].insts.appendSlice(e.arena, insts);
        _ = try e.append(middle, .{ .op = .jump, .ty = .void, .data = to });
        try f.blocks.items[middle.index()].preds.append(e.arena, source);
        for (f.blocks.items[to].preds.items) |*pred| {
            if (pred.* == source) {
                pred.* = middle;
                break;
            }
        }
        const insts_from = f.blocks.items[from].insts.items;
        const term = &f.insts.items[insts_from[insts_from.len - 1].index()];
        const targets = ir.unpackTargets(term.data);
        term.data = if (targets.then == target) ir.packTargets(middle, targets.otherwise) else ir.packTargets(targets.then, middle);
        for (f.loops.items) |*loop| {
            if (loop.latch == source and loop.header == target) loop.latch = middle;
        }
    }
};

/// Up to two successor blocks of `block`, from its terminator (one when both targets are equal).
const Successors = struct {
    buffer: [2]u32 = undefined,
    len: usize = 0,

    fn slice(self: *const Successors) []const u32 {
        return self.buffer[0..self.len];
    }
};

// twin-drift-ok: facts.successorsOf keeps both targets of a branch as block ids;
// this one works on u32 indices and lists a branch's single target once.
fn successors(f: *const ir.Function, block: u32) Successors {
    var out: Successors = .{};
    const insts = f.blocks.items[block].insts.items;
    if (insts.len == 0) return out;
    const last = f.inst(insts[insts.len - 1]);
    switch (last.op) {
        .jump => {
            out.buffer[0] = @truncate(last.data);
            out.len = 1;
        },
        .branch => {
            const targets = ir.unpackTargets(last.data);
            out.buffer[0] = @backingInt(targets.then);
            out.len = 1;
            if (targets.otherwise != targets.then) {
                out.buffer[1] = @backingInt(targets.otherwise);
                out.len = 2;
            }
        },
        else => {},
    }
    return out;
}
