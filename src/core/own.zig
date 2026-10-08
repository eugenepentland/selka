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
const facts = @import("facts.zig");
const flags = @import("flags.zig");
const promotion = @import("promote.zig");
const elements = @import("elements.zig");
const buffers = @import("buffers.zig");
const origins = @import("inline_origins.zig");

/// The pass only allocates.
pub const Error = std.mem.Allocator.Error;

/// How the pass runs.
pub const Options = struct {
    /// Verify builds assert every statically unique update (form 1) at run time.
    verify: bool = false,
    /// The function's facts (release builds): lists they bound may live on the stack.
    facts: ?*const facts.Facts = null,
    /// Optional source ancestry of instructions cloned before ownership.
    provenance: ?*origins.Table = null,
    function_index: u32 = 0,
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
    /// Lists promoted to the stack (`promote.zig`).
    promoted: u32 = 0,

    /// Add `other`'s counts to these.
    pub fn add(self: *Stats, other: Stats) void {
        self.in_place += other.in_place;
        self.tested += other.tested;
        self.copied += other.copied;
        self.retains += other.retains;
        self.releases += other.releases;
        self.elided += other.elided;
        self.promoted += other.promoted;
    }
};

/// The `data` of a `release` whose value may be `undef` (a phi fed by one, on a path
/// the checker rules out): the emitter skips every null block pointer in it.
pub const empty_release: u64 = 2;

/// The `data` of a `release` whose value is statically unique (fresh, never shared):
/// the emitter frees the block without testing its count (verify builds assert
/// `count == 1` first).
pub const unique_release: u64 = 1;

/// The `data` of an `unreachable` that asserts a statically unique update: verify
/// builds emit it as an `R_CORE_FACT` trap (`emit_llvm.zig`).
pub const unique_assert: u64 = 1;

/// Run the pass over every internal function of `module`.
pub fn run(arena: std.mem.Allocator, module: *ir.Module, options: Options) Error!Stats {
    var total: Stats = .{};
    for (module.functions.items, 0..) |*f, index| {
        if (f.signature.linkage != .internal) continue;
        var local = options;
        local.function_index = @intCast(index);
        total.add(try function(arena, module, f, local));
    }
    return total;
}

/// Run the pass over one function of `module`.
pub fn function(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, options: Options) Error!Stats {
    var stats: Stats = .{};
    var marks: Marks = .{ .origin = if (options.provenance) |table| table.context(options.function_index) else null };
    if (options.facts) |known| {
        const promoted = try promotion.promote(arena, module, f, known, options.verify, marks.origin);
        marks.stack = promoted.values;
        stats.promoted = promoted.lists;
        reserveFills(f, known);
    }
    // Element-field stores in place, before any update gets its copy-on-write form.
    _ = try elements.fieldStores(arena, module, f);
    // Byte-buffer appends become updates the emitter does inline.
    _ = try buffers.appends(arena, module, f);
    // Popped elements are found (or read) before anything moves.
    try markPops(.{ .arena = arena, .f = f, .origin = marks.origin }, module, &marks);
    for (f.insts.items, 0..) |inst, index| {
        if (flags.transferredRead(inst) and module.managed(inst.ty)) try marks.owned_get.put(arena, @intCast(index), {});
        if (flags.transferredSlot(f, inst)) try marks.taken.put(arena, @intCast(index), {});
    }
    try mergeFieldReads(arena, f);
    try takeFields(arena, module, f, &marks);
    var phase_a = try Analysis.of(arena, module, f, &marks);
    try phase_a.analyze();
    try copyOnWrite(&phase_a, options, &stats);
    var phase_b = try Analysis.of(arena, module, f, &marks);
    try phase_b.analyze();
    try count(&phase_b, &stats);
    if (options.facts) |known| markFillPushes(f, known);
    stats.elided = try elidePairs(arena, f);
    stats.retains -= stats.elided;
    stats.releases -= stats.elided;
    return stats;
}

/// Reserve known counted fills after stack promotion. Only detached i64/u64
/// parameters qualify, so the bound always dominates the empty constructor.
fn reserveFills(f: *ir.Function, known: *const facts.Facts) void {
    for (known.counted) |counted| {
        const bound = f.resolve(counted.bound);
        const source = f.inst(bound);
        if (source.op != .param or (source.ty != .i64 and source.ty != .u64)) continue;
        for (f.blocks.items[counted.loop.header.index()].insts.items) |ref| {
            const phi = f.inst(ref);
            if (phi.op != .phi or !known.aggregates.lists[ref.index()].pattern) continue;
            if (f.resolve(known.aggregates.lists[ref.index()].length) != bound) continue;
            for (f.operands(phi.data)) |operand| {
                const entry = f.resolve(operand);
                const inst = f.inst(entry);
                if (inst.op != .list_new or inst.data != 0) continue;
                f.insts.items[entry.index()].a = bound;
                f.insts.items[entry.index()].data = flags.fill_capacity;
            }
        }
    }
}

/// COW may replace the receiver with a copy whose capacity is unknown. Only
/// the counted body's backedge push, still consuming the original unique loop
/// phi, uses its reserved room. Later appends must check capacity normally.
fn markFillPushes(f: *ir.Function, known: *const facts.Facts) void {
    for (known.counted) |counted| {
        for (f.blocks.items[counted.loop.header.index()].insts.items) |ref| {
            const phi = f.inst(ref);
            if (phi.op != .phi or !known.aggregates.lists[ref.index()].pattern) continue;
            var reserved = false;
            for (f.operands(phi.data)) |operand| {
                const entry = f.inst(f.resolve(operand));
                reserved = reserved or (entry.op == .list_new and entry.data == flags.fill_capacity);
            }
            if (!reserved) continue;
            const push_ref = fillBackedgePush(f, counted.loop.header, ref) orelse continue;
            f.insts.items[push_ref.index()].data = flags.fill_push;
        }
    }
}

/// The facts proved this backedge value is the body's single push. Ownership
/// can split that edge, so consult the current recorded latch and phi ordering.
fn fillBackedgePush(f: *const ir.Function, header: ir.BlockId, phi: ir.Ref) ?ir.Ref {
    for (f.loops.items) |loop| {
        if (loop.header != header) continue;
        const position = std.mem.indexOfScalar(ir.BlockId, f.blocks.items[header.index()].preds.items, loop.latch) orelse return null;
        const ref = f.resolve(f.operands(f.inst(phi).data)[position]);
        const push = f.inst(ref);
        return if (push.op == .list_push and push.data == 0 and f.resolve(push.a) == phi) ref else null;
    }
    return null;
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
    origin: ?origins.Context = null,
    owned_get: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Values of lists promoted to the stack: never counted.
    stack: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// `record_set`s whose old field a read took over (`takeFields`): nothing to drop.
    taken: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Records whose block-holding fields were all read out (`takeFields`): never counted.
    emptied: std.AutoHashMapUnmanaged(u32, void) = .empty,
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
        // An owned parameter is defined on entry: in the entry block, before its first instruction.
        for (f.insts.items, 0..) |instruction, i| {
            if (instruction.op == .param and ownedParameter(f.signature, instruction.data)) self.where[i] = .{ .block = 0, .pos = 0 };
        }
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
            if (!self.module.managed(instruction.ty) and instruction.ty != .str_view) continue;
            self.class[i] = switch (instruction.op) {
                // A `mut` parameter is handed over by value (`Signature.owned`).
                .param => if (ownedParameter(f.signature, instruction.data)) .owned else .borrowed,
                .str_const, .undef => .immortal,
                .call => if (self.encodedSource(instruction)) |source| blk: {
                    self.parent[i] = source;
                    break :blk .borrowed;
                } else .owned,
                .copy => .none,
                .list_get, .list_get_field, .record_get, .union_payload, .box_get, .dict_entry_key, .dict_entry_value, .array_get, .str_view_of => blk: {
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
            if (self.marks.stack.contains(@intCast(i)) or self.marks.emptied.contains(@intCast(i))) self.class[i] = .none;
        }
        for (self.parent, 0..) |p, child| {
            if (p != .none and self.class[child] == .borrowed) try self.children[p.index()].append(self.arena, @fromBackingInt(@intCast(child)));
        }
    }

    /// `encode()` changes only the source type. Its byte reads keep the text alive;
    /// an escaping byte value is retained by the ordinary borrowed-value rules.
    fn encodedSource(self: *const Analysis, instruction: ir.Inst) ?ir.Ref {
        const callee = self.module.functions.items[instruction.a.index()];
        if (callee.signature.linkage != .extern_c or callee.signature.ret != .bytes) return null;
        if (!std.mem.eql(u8, callee.name, @import("flags.zig").text_encode_symbol)) return null;
        const operands = self.f.operands(instruction.data);
        if (operands.len != 1 or callee.signature.params.len != 1) return null;
        if (callee.signature.params[0] != .str or callee.signature.owned != 0) return null;
        return self.f.resolve(operands[0]);
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
                    const consumes = consuming(instruction, k) or self.handedOver(instruction, k);
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

    /// Whether operand `k` of a call is an argument the callee takes over (a `mut` one).
    fn handedOver(self: *const Analysis, instruction: ir.Inst, k: usize) bool {
        if (instruction.op == .call_indirect) {
            if (k == 0) return false;
            return ownedParameter(self.module.compound(self.inst(self.f.resolve(instruction.a)).ty).@"fn", k - 1);
        }
        if (instruction.op != .call) return false;
        return ownedParameter(self.module.functions.items[instruction.a.index()].signature, k);
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
        for (self.class, 0..) |class, i| {
            self.live[i] = null;
            if (class != .owned and class != .borrowed) continue;
            if (self.where[i].block == no_block) continue;
            const ref: ir.Ref = @fromBackingInt(@intCast(i));
            var uses: std.ArrayList(Use) = .empty;
            try self.liveUses(ref, &uses);
            self.live[i] = try self.liveFrom(ref, uses.items);
        }
    }

    /// Whether `ref` is still needed after instruction `pos` of `block`.
    fn liveAfter(self: *const Analysis, ref: ir.Ref, block: u32, pos: u32) bool {
        const live = self.live[ref.index()] orelse return false;
        // Nothing is live before its definition: an owner consumed earlier in the block
        // than a part is read does not promote that part (NEW-CORE-RC-13).
        const def = self.where[ref.index()];
        if (def.block == block and def.pos > pos) return false;
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

    /// Whether `ref` is a phi that may hold `undef`: one of its operands is `undef` or
    /// such a phi (the undef value is never owned, so its release must test for it).
    fn maybeUndef(self: *const Analysis, ref: ir.Ref) bool {
        const f = self.f;
        if (f.inst(ref).op != .phi) return false;
        var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
        var stack: std.ArrayList(ir.Ref) = .empty;
        stack.append(self.arena, ref) catch return true;
        while (stack.pop()) |current| {
            for (f.operands(f.inst(current).data)) |operand| {
                const source = f.resolve(operand);
                const op = f.inst(source).op;
                if (op == .undef) return true;
                if (op != .phi) continue;
                const entry = seen.getOrPut(self.arena, @backingInt(source)) catch return true;
                if (entry.found_existing) continue;
                stack.append(self.arena, source) catch return true;
            }
        }
        return false;
    }

    /// Whether the instruction at `pos` of `block` reads `ref` without taking it: a call
    /// that is handed the owner (`mut`) and borrows the part runs with both.
    fn borrowedAt(self: *const Analysis, ref: ir.Ref, block: u32, pos: u32) bool {
        const live = self.live[ref.index()] orelse return false;
        for (live.uses) |use| {
            const here = !use.onEdge() and use.block == block and use.pos == pos;
            if (here and use.borrow > 0) return true;
        }
        return false;
    }

    /// Promote every borrowed part whose counted owner is consumed while it is in use;
    /// returns whether any was promoted. A part needed there only through parts read out
    /// of it (a list whose element read outlives a `mut` call on the record holding the
    /// list) is not promoted itself: those parts are, so the call does not find the list
    /// shared and copy all of it (NEW-CORE-CE-LISTS-4).
    fn promote(self: *Analysis) Error!bool {
        var changed = false;
        for (self.class, 0..) |class, i| {
            if (self.f.insts.items[i].ty == .str_view) continue;
            if (class != .borrowed or self.promoted[i] or self.parent[i] == .none) continue;
            const ref: ir.Ref = @fromBackingInt(@intCast(i));
            const holder = self.owner(ref);
            if (holder == .none) continue;
            for (self.uses[holder.index()].items) |use| {
                if (use.consume == 0) continue;
                const still = if (use.onEdge()) self.liveInto(ref, use.succ) else self.liveAfter(ref, use.block, use.pos) or self.borrowedAt(ref, use.block, use.pos);
                if (!still) continue;
                if (try self.onlyThroughParts(ref, use)) continue;
                self.promoted[i] = true;
                changed = true;
                break;
            }
        }
        return changed;
    }

    /// Whether `ref`, still needed when its owner is consumed at `use`, is needed there only
    /// through the borrowed parts read out of it, each of which can be promoted in its place
    /// (a borrowed text view cannot).
    fn onlyThroughParts(self: *Analysis, ref: ir.Ref, use: Use) Error!bool {
        const children = self.children[ref.index()].items;
        if (children.len == 0) return false;
        // Only a collection the consumer may update is worth splitting: one retain of it is
        // cheaper than its parts' unless the update would find it shared and copy it all.
        const kind = self.module.kind(self.inst(ref).ty);
        if (kind != .list and kind != .dict) return false;
        if (try self.viewBelow(ref)) return false;
        const direct = try self.liveFrom(ref, self.uses[ref.index()].items);
        const def = self.where[ref.index()];
        if (use.onEdge()) return !(use.succ != direct.def and direct.in.isSet(use.succ));
        if (def.block == use.block and def.pos > use.pos) return true;
        if (direct.out.isSet(use.block)) return false;
        for (direct.uses) |own_use| {
            if (!own_use.onEdge() and own_use.block == use.block and own_use.pos >= use.pos) return false;
        }
        return true;
    }

    /// Whether a borrowed text view hangs below `ref` (through uncounted parts).
    fn viewBelow(self: *Analysis, ref: ir.Ref) Error!bool {
        for (self.children[ref.index()].items) |child| {
            if (self.counted(child)) continue;
            if (self.f.inst(child).ty == .str_view) return true;
            if (try self.viewBelow(child)) return true;
        }
        return false;
    }

    /// Liveness of `ref` from `uses` alone.
    fn liveFrom(self: *Analysis, ref: ir.Ref, uses: []const Use) Error!Live {
        const nblocks = self.f.blocks.items.len;
        var live: Live = .{
            .in = try std.DynamicBitSetUnmanaged.initEmpty(self.arena, nblocks),
            .out = try std.DynamicBitSetUnmanaged.initEmpty(self.arena, nblocks),
            .uses = uses,
            .def = self.where[ref.index()].block,
        };
        var stack: std.ArrayList(u32) = .empty;
        for (uses) |use| {
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
        return live;
    }
};

/// Whether parameter `index` of a function with `signature` is passed owned.
fn ownedParameter(signature: ir.Signature, index: u64) bool {
    return index < 64 and signature.owned & (@as(u64, 1) << @intCast(index)) != 0;
}

/// Whether operand `k` (in `valueOperands` order) of `instruction` is consumed.
fn consuming(instruction: ir.Inst, k: usize) bool {
    if (k == 0 and instruction.op.consumesOperand0()) return true;
    return switch (instruction.op) {
        // a (the list) and b (the value); a (the record) and b (the field value).
        .list_push, .record_set => true,
        // a (the list), b (the index), then extra[0] (the value).
        .list_set, .list_set_field, .array_set, .dict_set_value, .dict_insert => k >= 2,
        .list_pop, .union_make, .box_make, .ret, .release, .record_make => true,
        else => false,
    };
}

/// Whether `op` consumes and updates a counted block.
fn isUpdate(op: ir.Op) bool {
    return op.consumesOperand0() and op != .record_set and op != .array_set;
}

// ---- phase A: copy on write -------------------------------------------------------

/// Whether updating `value` at `site` may skip the uniqueness test: it comes fresh
/// from an allocation, a copy or another update (or phis of those), and no use
/// before shares it.
fn staticallyUnique(a: *const Analysis, value: ir.Ref, site: ir.Ref) Error!bool {
    if (!a.module.isBlock(a.inst(value).ty)) return false;
    var web: std.ArrayList(ir.Ref) = .empty;
    var index: std.AutoHashMapUnmanaged(u32, u6) = .empty;
    try web.append(a.arena, value);
    var next: usize = 0;
    while (next < web.items.len) : (next += 1) {
        const current = web.items[next];
        if (a.class[current.index()] != .owned or web.items.len > 64) return false;
        const instruction = a.inst(current);
        switch (instruction.op) {
            .list_new, .list_copy, .dict_new, .dict_copy, .str_from_view, .buffer_new, .buffer_copy => {},
            .list_get => if (flags.transferredRead(instruction)) {
                if (!try exclusiveChildren(a, instruction.a)) return false;
            } else return false,
            .phi => for (a.f.operands(instruction.data)) |operand| {
                const source = a.f.resolve(operand);
                if (std.mem.indexOfScalar(ir.Ref, web.items, source) == null) try web.append(a.arena, source);
            },
            else => if (instruction.op.consumesOperand0()) {} else return false,
        }
    }
    for (web.items, 0..) |member, i| try index.put(a.arena, @backingInt(member), @intCast(i));
    for (web.items) |member| {
        if (try shared(a, .{ .members = web.items, .index = &index }, member, site)) return false;
    }
    return true;
}

/// A fresh collection owns unique child blocks when all stores moved unique
/// values and no ordinary child read was promoted, stored, returned or lent to a
/// call. A real collection copy does not establish this claim: its children share.
fn exclusiveChildren(a: *const Analysis, root: ir.Ref) Error!bool {
    var values: std.ArrayList(ir.Ref) = .empty;
    try values.append(a.arena, a.f.resolve(root));
    var next: usize = 0;
    while (next < values.items.len) : (next += 1) {
        const ref = values.items[next];
        const inst = a.inst(ref);
        switch (inst.op) {
            .list_new => {},
            .list_copy => {
                if (inst.data != flags.place_copy) return false;
                const source = a.f.resolve(inst.a);
                const at = location(a.f, ref);
                if (!a.counted(source) or a.liveAfter(source, at.block, at.pos)) return false;
                if (!try staticallyUnique(a, source, ref)) return false;
                try addUnique(a.arena, &values, source);
            },
            .phi => for (a.f.operands(inst.data)) |operand| {
                try addUnique(a.arena, &values, a.f.resolve(operand));
            },
            .list_push, .list_set => {
                const child = a.f.resolve(if (inst.op == .list_push) inst.b else a.f.operands(inst.data)[0]);
                const at = location(a.f, ref);
                if (a.liveAfter(child, at.block, at.pos) or !try staticallyUnique(a, child, ref)) return false;
                try addUnique(a.arena, &values, a.f.resolve(inst.a));
            },
            else => return false,
        }
    }
    for (a.f.insts.items, 0..) |inst, index| {
        if (inst.op != .list_get or !a.module.managed(inst.ty) or flags.transferredRead(inst)) continue;
        if (std.mem.indexOfScalar(ir.Ref, values.items, a.f.resolve(inst.a)) == null) continue;
        if (a.class[index] == .owned) return false;
        for (a.uses[index].items) |use| {
            if (use.consume != 0) return false;
            const user = a.f.inst(a.f.blocks.items[use.block].insts.items[use.pos]);
            if (user.op == .call or user.op == .call_indirect) return false;
        }
    }
    return true;
}

fn addUnique(arena: std.mem.Allocator, values: *std.ArrayList(ir.Ref), ref: ir.Ref) Error!void {
    if (std.mem.indexOfScalar(ir.Ref, values.items, ref) == null) try values.append(arena, ref);
}

fn location(f: *const ir.Function, ref: ir.Ref) struct { block: u32, pos: u32 } {
    for (f.blocks.items, 0..) |block, b| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, ref)) |pos| return .{ .block = @intCast(b), .pos = @intCast(pos) };
    }
    unreachable;
}

/// The values one block may pass through on its way to an update: the updated value
/// and, through phis, everything that flows into it (`staticallyUnique`).
const Web = struct {
    members: []const ir.Ref,
    index: *const std.AutoHashMapUnmanaged(u32, u6),

    fn bit(self: Web, ref: ir.Ref) ?u64 {
        const i = self.index.get(@backingInt(ref)) orelse return null;
        return @as(u64, 1) << i;
    }
};

/// Whether some use of web member `value` other than `site` may give the block a
/// second owner that it still has at the update: a call argument (the callee may keep
/// it) or a consuming use the value outlives, or a use that consumes it twice. With
/// `site` none the question is about the value's death: then any call may have kept
/// it, even its last use, and any such use counts.
fn shared(a: *const Analysis, web: Web, value: ir.Ref, site: ir.Ref) Error!bool {
    for (a.uses[value.index()].items) |use| {
        if (use.onEdge()) {
            if (use.consume > 1) return true;
            if (!a.liveInto(value, use.succ)) continue;
            if (site == .none or try carries(a, web, value, .{ .block = use.block, .edge = use.succ }, site)) return true;
            continue;
        }
        const at = a.f.blocks.items[use.block].insts.items[use.pos];
        if (at == site) continue;
        const call = a.inst(at).op == .call or a.inst(at).op == .call_indirect;
        if (use.consume > 1 or (call and site == .none)) return true;
        const may_share = call or use.consume == 1;
        if (!may_share or !a.liveAfter(value, use.block, use.pos)) continue;
        if (site == .none or try carries(a, web, value, .{ .block = use.block, .pos = use.pos }, site)) return true;
    }
    return false;
}

/// Where a walk of `carries` starts: after instruction `pos` of `block`, or on the
/// edge from `block` into `edge`.
const Start = struct { block: u32, pos: u32 = 0, edge: u32 = no_block };

/// Whether the block `value` holds at `start` can still be held, by some web member,
/// when `site` updates it: a walk of the CFG that tracks which members hold the block
/// (a phi takes it on an edge whose operand holds it; a member defined again holds a
/// new block) and stops where none does.
fn carries(a: *const Analysis, web: Web, value: ir.Ref, start: Start, site: ir.Ref) Error!bool {
    const f = a.f;
    const State = struct { block: u32, holders: u64 };
    var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
    var stack: std.ArrayList(State) = .empty;
    const first = web.bit(value).?;
    var from: u32 = start.pos + 1;
    var block = start.block;
    var holders = first;
    if (start.edge != no_block) {
        holders = enter(f, web, start.block, start.edge, first);
        block = start.edge;
        from = 0;
    }
    while (true) {
        const insts = f.blocks.items[block].insts.items;
        var done = false;
        for (insts[@min(from, insts.len)..]) |ref| {
            const inst = f.inst(ref);
            if (inst.op == .phi) continue;
            if (ref == site) {
                if ((web.bit(f.resolve(inst.a)) orelse 0) & holders != 0) return true;
                // This path reaches the update with a block nothing shares; others may not.
                done = true;
                break;
            }
            if (web.bit(ref)) |b| holders &= ~b;
            if (holders == 0) {
                done = true;
                break;
            }
        }
        if (!done) {
            for (successors(f, block).slice()) |succ| {
                const next = enter(f, web, block, succ, holders);
                if (next == 0) continue;
                const key = (@as(u64, succ) << 32) ^ next ^ (next >> 32);
                if ((try seen.getOrPut(a.arena, key)).found_existing) continue;
                try stack.append(a.arena, .{ .block = succ, .holders = next });
            }
        }
        const state = stack.pop() orelse return false;
        block = state.block;
        holders = state.holders;
        from = 0;
    }
}

/// The holders after the edge `from → to`: each web phi of `to` holds the block when
/// its operand on this edge does, and no longer when it does not.
fn enter(f: *const ir.Function, web: Web, from: u32, to: u32, holders: u64) u64 {
    const target = f.blocks.items[to];
    const pred = for (target.preds.items, 0..) |p, i| {
        if (@backingInt(p) == from) break i;
    } else return holders;
    var out = holders;
    for (target.insts.items) |ref| {
        const inst = f.inst(ref);
        // Phis lead the block; a removed trivial phi (`copy`) may sit among them.
        if (inst.op == .copy) continue;
        if (inst.op != .phi) break;
        const b = web.bit(ref) orelse continue;
        const operand = f.resolve(f.operands(inst.data)[pred]);
        if ((web.bit(operand) orelse 0) & holders != 0) out |= b else out &= ~b;
    }
    return out;
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
            const detach = (instruction.op == .list_copy or instruction.op == .dict_copy) and instruction.data == flags.place_copy;
            if (!isUpdate(instruction.op) and !detach) continue;
            if (a.marks.taken.contains(@backingInt(ref))) continue;
            // A push into a promoted list: in place by construction (`promote.zig`).
            if (instruction.op == .list_push and instruction.data == promotion.stack_push) continue;
            const list = f.resolve(instruction.a);
            const form: Form = if (!a.counted(list) or a.liveAfter(list, @intCast(b), @intCast(pos)))
                .copied
            else if (try staticallyUnique(a, list, ref)) .in_place else .tested;
            try sites.append(a.arena, .{ .update = ref, .form = form });
        }
    }
    const e: Editor = .{ .arena = a.arena, .f = f, .origin = a.marks.origin };
    for (sites.items) |site| {
        const before = f.inst(site.update);
        const detach = (before.op == .list_copy or before.op == .dict_copy) and before.data == flags.place_copy;
        switch (site.form) {
            .copied => {
                stats.copied += 1;
                if (detach) {
                    f.insts.items[site.update.index()].data = 0;
                } else {
                    const copy = try copyBefore(e, a.module, site.update, before.a);
                    try useUpdatedOperand(e, site.update, copy);
                }
            },
            .tested => {
                stats.tested += 1;
                try testUnique(e, a.module, site.update);
                if (detach) f.insts.items[site.update.index()].op = .copy;
            },
            .in_place => {
                stats.in_place += 1;
                if (options.verify) try assertUnique(e, site.update);
                if (detach) f.insts.items[site.update.index()].op = .copy;
            },
        }
    }
    if (options.verify) {
        var reads: std.ArrayList(ir.Ref) = .empty;
        for (f.blocks.items) |block| for (block.insts.items) |ref| {
            if (flags.transferredRead(f.inst(ref))) try reads.append(a.arena, ref);
        };
        for (reads.items) |ref| try assertUnique(e, ref);
    }
    try extractDroppedFields(a);
}

/// Split the block of `update` before it: `if is_unique(a)` the update runs on `a`,
/// else on a copy of `a` after `release(a)`; both reach it through a phi.
fn testUnique(e: Editor, module: *const ir.Module, update: ir.Ref) Error!void {
    const f = e.f;
    const instruction = f.inst(update);
    const list = instruction.a;
    const ty = f.inst(f.resolve(list)).ty;
    const at = try e.split(update);
    const unique = try e.append(at.head, .{ .op = .is_unique, .ty = .bool, .a = list, .span = instruction.span });
    try e.inherit(unique, update);
    const copy_block = try e.newBlock();
    if (e.origin) |origin| try origin.setBlock(e.arena, @intCast(copy_block.index()), e.frameAt(update));
    try e.terminate(at.head, .{ .op = .branch, .ty = .void, .a = unique, .data = ir.packTargets(at.tail, copy_block), .span = instruction.span }, &.{ at.tail, copy_block });
    const marker = try e.append(copy_block, .{ .op = .copy, .ty = ty, .a = list });
    const copy = try copyBefore(e, module, marker, list);
    _ = try e.append(copy_block, .{ .op = .release, .ty = .void, .a = list, .span = instruction.span });
    try e.terminate(copy_block, .{ .op = .jump, .ty = .void, .data = @backingInt(at.tail), .span = instruction.span }, &.{at.tail});
    // The tail's predecessors are [head, copy_block], in that order.
    const phi = try e.newInst(.{ .op = .phi, .ty = ty, .data = try e.extraOf(&.{ list, copy }), .span = instruction.span });
    try e.inherit(phi, update);
    try f.blocks.items[at.tail.index()].insts.insert(e.arena, 0, phi);
    try useUpdatedOperand(e, update, phi);
}

/// Copy the block in its own representation before a consuming update.
fn copyBefore(e: Editor, module: *const ir.Module, before: ir.Ref, value: ir.Ref) Error!ir.Ref {
    const ty = e.f.inst(e.f.resolve(value)).ty;
    const span = e.f.inst(before).span;
    if (ty != .str) return e.insertBefore(before, .{ .op = if (ty == .byte_buffer) .buffer_copy else if (module.kind(ty) == .dict) .dict_copy else .list_copy, .ty = ty, .a = value, .span = span });
    const zero = try e.newInst(.{ .op = .iconst, .ty = .u64 });
    const len = try e.insertBefore(before, .{ .op = .str_len, .ty = .u64, .a = value, .span = span });
    const view = try e.insertBefore(before, .{ .op = .str_view_of, .ty = .str_view, .a = value, .b = zero, .data = try e.extraOf(&.{len}), .span = span });
    return e.insertBefore(before, .{ .op = .str_from_view, .ty = .str, .a = view, .span = span });
}

/// Preserve a dictionary insert's probe provenance when COW changes its operand.
fn useUpdatedOperand(e: Editor, update: ir.Ref, value: ir.Ref) Error!void {
    const inst = e.f.inst(update);
    if (inst.op == .dict_insert) {
        const old_probe = e.f.inst(e.f.resolve(inst.b));
        const probe = try e.insertBefore(update, .{ .op = .dict_find, .ty = .i64, .a = value, .b = old_probe.b, .span = inst.span });
        e.f.insts.items[update.index()].b = probe;
    }
    e.f.insts.items[update.index()].a = value;
}

/// Verify builds: trap `R_CORE_FACT` before a form-1 update unless its list's count is 1.
fn assertUnique(e: Editor, update: ir.Ref) Error!void {
    const instruction = e.f.inst(update);
    const at = try e.split(update);
    const unique = try e.append(at.head, .{ .op = .is_unique, .ty = .bool, .a = instruction.a, .span = instruction.span });
    try e.inherit(unique, update);
    const fail = try e.newBlock();
    if (e.origin) |origin| try origin.setBlock(e.arena, @intCast(fail.index()), e.frameAt(update));
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

/// One read of a record's field per block: a record value never changes, so a later
/// identical `record_get` in the block becomes a `copy` of the first. A nested update
/// `r.marker.marks.append(x)` reads `r.marker` twice, once to reach the list and once to
/// write it back; merged, the read that takes `r.marker` over also holds the list it
/// updates (NEW-CORE-TAKE-READS-1).
///
/// Reads in different blocks merge too (NEW-CORE-CE-LISTS-3) when the earlier one runs
/// on every path to the later one and every path from it reaches the later one (or a
/// trap), and no other read of the field can run after the earlier one: an index's
/// negative branch splits `it.rt.stack[i] = v` into a read of `it.rt` that reaches the
/// list and one that writes it back, and merged, the write-back takes the list too.
fn mergeFieldReads(arena: std.mem.Allocator, f: *ir.Function) Error!void {
    const Key = struct { record: u32, field: u64 };
    var first: std.AutoHashMapUnmanaged(Key, ir.Ref) = .empty;
    for (f.blocks.items) |block| {
        first.clearRetainingCapacity();
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op != .record_get) continue;
            const key: Key = .{ .record = @backingInt(f.resolve(inst.a)), .field = inst.data };
            const entry = try first.getOrPut(arena, key);
            if (!entry.found_existing) {
                entry.value_ptr.* = ref;
                continue;
            }
            f.insts.items[ref.index()] = .{ .op = .copy, .ty = inst.ty, .a = entry.value_ptr.*, .span = inst.span };
        }
    }
    const graph = try UseGraph.of(arena, f);
    var groups: std.array_hash_map.Auto(Key, std.ArrayList(ir.Ref)) = .empty;
    for (f.blocks.items, 0..) |block, b| {
        if (b != 0 and block.preds.items.len == 0) continue;
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op != .record_get) continue;
            const entry = try groups.getOrPut(arena, .{ .record = @backingInt(f.resolve(inst.a)), .field = inst.data });
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            try entry.value_ptr.append(arena, ref);
        }
    }
    for (groups.keys(), groups.values()) |key, reads| {
        if (reads.items.len < 2) continue;
        const record: ir.Ref = @fromBackingInt(key.record);
        const def = if (f.inst(record).op.isConstant()) 0 else graph.block_of[record.index()];
        if (def == no_block) continue;
        const merged = try arena.alloc(bool, reads.items.len);
        @memset(merged, false);
        const group: ReadGroup = .{ .graph = graph, .def = def, .reads = reads.items, .merged = merged, .record = record, .field = key.field };
        var changed = true;
        while (changed) {
            changed = false;
            for (reads.items, 0..) |later, j| {
                if (merged[j]) continue;
                for (reads.items, 0..) |earlier, i| {
                    if (i == j or merged[i]) continue;
                    if (!try mergeable(arena, f, group, earlier, later)) continue;
                    f.insts.items[later.index()] = .{ .op = .copy, .ty = f.inst(later).ty, .a = earlier, .span = f.inst(later).span };
                    merged[j] = true;
                    changed = true;
                    break;
                }
            }
        }
    }
}

/// The reads of one record's field `mergeable` weighs: the function's uses, the record's
/// scope (`def`), the reads and which were merged, and the record and field.
const ReadGroup = struct { graph: UseGraph, def: u32, reads: []const ir.Ref, merged: []const bool, record: ir.Ref, field: u64 };

/// Whether read `later` may become a copy of read `earlier` in another block: `earlier`
/// runs on every path to it, every path from `earlier` reaches it or traps, and nothing
/// can run after `earlier` that would keep `earlier` from taking the field where `later`
/// could: no other read of the field nor a use of what it read, and no use of the record
/// but reads of its fields and the field's write-back.
fn mergeable(arena: std.mem.Allocator, f: *const ir.Function, group: ReadGroup, earlier: ir.Ref, later: ir.Ref) Error!bool {
    const block_of = group.graph.block_of;
    const from = block_of[earlier.index()];
    const to = block_of[later.index()];
    if (from == no_block or to == no_block or from == to) return false;
    if (!try dominatesBlock(arena, f, from, to)) return false;
    if (!try reachesOrTrapsBlock(arena, f, from, to)) return false;
    const edges: Edges = .{ .arena = arena, .f = f, .block_of = block_of };
    for (group.graph.uses[group.record.index()].items) |user| {
        const inst = f.inst(user);
        if (inst.op == .record_get) continue;
        if (inst.op == .record_set and inst.data == group.field and f.resolve(inst.a) == group.record) continue;
        // A join takes the record only on its incoming edges, as `takeReplaced` weighs it.
        if (inst.op == .phi) {
            if (try edges.phiAfter(group.record, earlier, user, group.def)) return false;
            continue;
        }
        if (try runsAfter(arena, f, block_of, earlier, user, group.def)) return false;
    }
    for (group.reads, group.merged) |other, gone| {
        if (gone or other == earlier or other == later) continue;
        var pending: std.ArrayList(ir.Ref) = .empty;
        try pending.append(arena, other);
        var visited: usize = 0;
        while (pending.pop()) |value| {
            visited += 1;
            if (visited > 64) return false;
            if (block_of[value.index()] == no_block) return false;
            if (try runsAfter(arena, f, block_of, earlier, value, group.def)) return false;
            for (group.graph.uses[value.index()].items) |user| {
                if (block_of[user.index()] == no_block or try runsAfter(arena, f, block_of, earlier, user, group.def)) return false;
                const part = f.inst(user);
                if (readsPart(part.op) and f.resolve(part.a) == value) try pending.append(arena, user);
            }
        }
    }
    return true;
}

/// Reads that take a record's fields over instead of borrowing them, so an update of
/// the field does not copy it (§6.4). Every `record_set` that replaces a field of the
/// record is considered:
/// - `g = record_get(r, f)` and `record_set(r, f, v)` in one block, `g` first, where `r`
///   is owned and has no other use but reads of other fields: `g` owns the field (the
///   record's reference goes to it) and the set drops nothing. This is a `mut` record's
///   `r.items.append(x)`: the list is updated in place when unique.
/// - an owned record whose only uses are reads in its own block, each block-holding
///   field read once: the reads own the fields and the record is never counted. This is
///   the write-back of a call with a result and `mut` parameters (or of its inlined body).
fn takeFields(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function, marks: *Marks) Error!void {
    const graph = try UseGraph.of(arena, f);
    for (f.insts.items, 0..) |record, i| {
        if (module.kind(record.ty) != .record or !module.managed(record.ty)) continue;
        if (!ownedRecord(f, record) and !marks.owned_get.contains(@intCast(i))) continue;
        const ref: ir.Ref = @fromBackingInt(@intCast(i));
        var reads_only = true;
        var sets: std.ArrayList(ir.Ref) = .empty;
        for (graph.uses[i].items) |user| {
            const inst = f.inst(user);
            if (inst.op == .record_get and f.resolve(inst.a) == ref) continue;
            const replaces = inst.op == .record_set and f.resolve(inst.a) == ref and f.resolve(inst.b) != ref;
            if (replaces) {
                try sets.append(arena, user);
            } else reads_only = false;
        }
        const ctx: Taking = .{ .arena = arena, .module = module, .f = f, .graph = graph, .marks = marks };
        // Each set replaces its own field: arms of a branch may each update another one.
        for (sets.items) |update| try ctx.takeReplaced(ref, update);
        if (sets.items.len == 0 and reads_only) try ctx.empty(ref);
    }
}

/// Every instruction's users (copies resolved) and block, for `takeFields`.
const UseGraph = struct {
    uses: []std.ArrayList(ir.Ref),
    block_of: []u32,

    fn of(arena: std.mem.Allocator, f: *const ir.Function) Error!UseGraph {
        const graph: UseGraph = .{ .uses = try arena.alloc(std.ArrayList(ir.Ref), f.insts.items.len), .block_of = try arena.alloc(u32, f.insts.items.len) };
        @memset(graph.uses, .empty);
        @memset(graph.block_of, no_block);
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                graph.block_of[ref.index()] = @intCast(b);
                const inst = f.inst(ref);
                if (inst.op == .copy) continue;
                var list: std.ArrayList(ir.Ref) = .empty;
                if (inst.op == .phi) try list.appendSlice(arena, f.operands(inst.data)) else {
                    const direct = f.valueOperands(inst);
                    for (0..direct.len()) |k| try list.append(arena, direct.get(k));
                }
                for (list.items) |operand| {
                    const used = f.resolve(operand);
                    if (used != .none) try graph.uses[used.index()].append(arena, ref);
                }
            }
        }
        return graph;
    }
};

/// The two ways `takeFields` hands a record's fields to their reads.
const Taking = struct {
    arena: std.mem.Allocator,
    module: *const ir.Module,
    f: *const ir.Function,
    graph: UseGraph,
    marks: *Marks,

    /// `g = record_get(r, f)` then `update = record_set(r, f, v)`: `g` owns the field (the
    /// record's reference goes to it, and the set drops nothing) when it is the last read
    /// of the field ahead of the set on every path, every path from it reaches the set
    /// (or a trap), every earlier read of the field is finished before it, and nothing but
    /// reads of other fields can use `r` after it. The read and the set may sit in
    /// different blocks: an index's negative-index branch splits `r.items[i] = v`
    /// (NEW-CORE-TAKE-READS-1).
    fn takeReplaced(self: Taking, record: ir.Ref, update: ir.Ref) Error!void {
        const f = self.f;
        const field = f.inst(update).data;
        if (!self.module.managed(self.module.compound(f.inst(record).ty).record[@intCast(field)])) return;
        const def_block = if (f.inst(record).op == .param) 0 else self.graph.block_of[record.index()];
        var reads: std.ArrayList(ir.Ref) = .empty;
        for (self.graph.uses[record.index()].items) |user| {
            const inst = f.inst(user);
            if (inst.op == .record_get and inst.data == field and f.resolve(inst.a) == record) try addUnique(self.arena, &reads, user);
        }
        const get = for (reads.items) |candidate| {
            if (try self.takes(candidate, update, reads.items, def_block)) break candidate;
        } else return;
        for (self.graph.uses[record.index()].items) |user| {
            const inst = f.inst(user);
            if (user == get or user == update) continue;
            if (inst.op == .record_get and inst.data != field) continue;
            if (inst.op == .phi) {
                if (try phiAfter(self, record, get, user, def_block)) return;
                continue;
            }
            if (try runsAfter(self.arena, f, self.graph.block_of, get, user, def_block)) return;
        }
        try self.marks.owned_get.put(self.arena, @backingInt(get), {});
        try self.marks.taken.put(self.arena, @backingInt(update), {});
    }

    /// Whether read `get` of the field `update` replaces can take it over: it runs ahead of
    /// the set on every path, every path from it reaches the set or a trap, and every other
    /// read of the field (`reads`), with the parts read out of it, is finished before it.
    fn takes(self: Taking, get: ir.Ref, update: ir.Ref, reads: []const ir.Ref, def: u32) Error!bool {
        const get_block = self.graph.block_of[get.index()];
        const update_block = self.graph.block_of[update.index()];
        if (get_block == no_block or update_block == no_block) return false;
        if (get_block == update_block) {
            const insts = self.f.blocks.items[get_block].insts.items;
            if (std.mem.indexOfScalar(ir.Ref, insts, get).? > std.mem.indexOfScalar(ir.Ref, insts, update).?) return false;
        } else {
            if (!try self.dominates(get_block, update_block)) return false;
            if (!try self.reachesOrTraps(get_block, update_block)) return false;
        }
        // An earlier read still in use would lose the record's reference under it once `get`
        // takes the field; one whose uses all come before `get` (`len(r.items)` ahead of
        // `r.items.append(x)`) is over by then.
        for (reads) |other| {
            if (other == get) continue;
            if (!try self.clearOfWindow(other, get, update, def)) return false;
        }
        return true;
    }

    /// Whether `read`, and every managed part read out of it (which borrows from it in
    /// turn), is used only before `get` or only after `update`: never while `get` holds the
    /// field and the update may already have changed the list in place. A part still used
    /// after `update` is safe: `update` consumes the record, its counted owner, so
    /// phase B promotes the part to its own count when it is read.
    fn clearOfWindow(self: Taking, read: ir.Ref, get: ir.Ref, update: ir.Ref, def: u32) Error!bool {
        var pending: std.ArrayList(ir.Ref) = .empty;
        try pending.append(self.arena, read);
        if (try runsAfter(self.arena, self.f, self.graph.block_of, get, read, def)) return false;
        while (pending.pop()) |value| {
            for (self.graph.uses[value.index()].items) |user| {
                if (self.graph.block_of[user.index()] == no_block) return false;
                const later = try runsAfter(self.arena, self.f, self.graph.block_of, get, user, def);
                if (later and !try self.onlyAfter(user, get, update)) return false;
                const inst = self.f.inst(user);
                if (readsPart(inst.op) and self.module.managed(inst.ty)) try addUnique(self.arena, &pending, user);
            }
        }
        return true;
    }

    /// Whether `user`, which may run after `get`, runs only once `update` has: every path
    /// from `get` to it passes `update`.
    fn onlyAfter(self: Taking, user: ir.Ref, get: ir.Ref, update: ir.Ref) Error!bool {
        const block_of = self.graph.block_of;
        const at = block_of[user.index()];
        const get_block = block_of[get.index()];
        const update_block = block_of[update.index()];
        if (at == update_block) {
            const insts = self.f.blocks.items[at].insts.items;
            return std.mem.indexOfScalar(ir.Ref, insts, user).? > std.mem.indexOfScalar(ir.Ref, insts, update).?;
        }
        if (at == get_block) return false;
        // `get` runs ahead of `update` in their shared block, so leaving it passes `update`.
        if (get_block == update_block) return true;
        return !try blockReachable(self.arena, self.f, get_block, at, update_block);
    }

    fn dominates(self: Taking, through: u32, target: u32) Error!bool {
        return dominatesBlock(self.arena, self.f, through, target);
    }

    fn reachesOrTraps(self: Taking, from: u32, target: u32) Error!bool {
        return reachesOrTrapsBlock(self.arena, self.f, from, target);
    }

    /// A record used only by reads in its own block, each block-holding field read once:
    /// the reads own the fields and the record is never counted.
    fn empty(self: Taking, record: ir.Ref) Error!void {
        const f = self.f;
        // A phi owns only what its operands hand it on their edges, and an emptied value
        // is never counted: its operands would be released where they die on those edges
        // while the reads still use the fields (a release build's unswitched loop exits
        // joining the loop record). A phi stays an ordinary owned record.
        if (f.inst(record).op == .phi) return;
        const home = self.graph.block_of[record.index()];
        if (home == no_block) return;
        const fields = self.module.compound(f.inst(record).ty).record;
        const counts = try self.arena.alloc(u32, fields.len);
        @memset(counts, 0);
        for (self.graph.uses[record.index()].items) |user| {
            if (self.graph.block_of[user.index()] != home) return;
            counts[@intCast(f.inst(user).data)] += 1;
        }
        for (fields, counts) |field, n| {
            if (self.module.managed(field) and n != 1) return;
        }
        for (self.graph.uses[record.index()].items) |user| {
            if (self.module.managed(f.inst(user).ty)) try self.marks.owned_get.put(self.arena, @backingInt(user), {});
        }
        try self.marks.emptied.put(self.arena, @backingInt(record), {});
    }
};

/// Whether every path from the entry block to `target` passes block `through`.
pub fn dominatesBlock(arena: std.mem.Allocator, f: *const ir.Function, through: u32, target: u32) Error!bool {
    if (through == 0) return true;
    const seen = try arena.alloc(bool, f.blocks.items.len);
    @memset(seen, false);
    var stack: std.ArrayList(u32) = .empty;
    try stack.append(arena, 0);
    seen[0] = true;
    while (stack.pop()) |b| {
        if (b == target) return false;
        for (successors(f, b).slice()) |succ| {
            if (succ == through or seen[succ]) continue;
            seen[succ] = true;
            try stack.append(arena, succ);
        }
    }
    return true;
}

/// Whether every path leaving block `from` reaches block `target` or ends in a trap,
/// without coming back to `from` first.
fn reachesOrTrapsBlock(arena: std.mem.Allocator, f: *const ir.Function, from: u32, target: u32) Error!bool {
    const seen = try arena.alloc(bool, f.blocks.items.len);
    @memset(seen, false);
    var stack: std.ArrayList(u32) = .empty;
    try stack.append(arena, from);
    while (stack.pop()) |b| {
        const next = successors(f, b);
        if (next.len == 0 and !endsInTrap(f, b)) return false;
        for (next.slice()) |succ| {
            if (succ == from) return false;
            if (succ == target or seen[succ]) continue;
            seen[succ] = true;
            try stack.append(arena, succ);
        }
    }
    return true;
}

/// Whether `op` reads a part of its first operand that borrows from it (§5).
fn readsPart(op: ir.Op) bool {
    return switch (op) {
        .list_get, .list_get_field, .record_get, .union_payload, .box_get => true,
        else => false,
    };
}

/// Whether join `phi` can receive `record` on an edge taken after `get`: a phi reads each
/// operand at the end of its predecessor, so only the edges carrying `record` from `get`'s
/// block or a block reachable from it see the record once its field was taken. The record
/// that an `if` leaves alone on its other edge (a `mut` record whose field one arm updates)
/// keeps its field there.
fn phiAfter(self: Taking, record: ir.Ref, get: ir.Ref, phi: ir.Ref, def: u32) Error!bool {
    const edges: Edges = .{ .arena = self.arena, .f = self.f, .block_of = self.graph.block_of };
    return edges.phiAfter(record, get, phi, def);
}

/// The control flow `phiAfter` walks: the function and each instruction's block.
const Edges = struct {
    arena: std.mem.Allocator,
    f: *const ir.Function,
    block_of: []const u32,

    fn phiAfter(self: Edges, record: ir.Ref, get: ir.Ref, phi: ir.Ref, def: u32) Error!bool {
        const f = self.f;
        const from = self.block_of[get.index()];
        const home = self.block_of[phi.index()];
        if (home == no_block) return true;
        const operands = f.operands(f.inst(phi).data);
        const preds = f.blocks.items[home].preds.items;
        if (operands.len != preds.len) return true;
        for (operands, preds) |operand, pred| {
            if (f.resolve(operand) != record) continue;
            const source = @backingInt(pred);
            if (source == from or try blockReachable(self.arena, f, from, source, def)) return true;
        }
        return false;
    }
};

/// Whether block `target` can run after block `from` without passing block `def`.
fn blockReachable(arena: std.mem.Allocator, f: *const ir.Function, from: u32, target: u32, def: u32) Error!bool {
    const seen = try arena.alloc(bool, f.blocks.items.len);
    @memset(seen, false);
    var stack: std.ArrayList(u32) = .empty;
    try stack.append(arena, from);
    while (stack.pop()) |b| {
        for (successors(f, b).slice()) |succ| {
            if (succ == def or seen[succ]) continue;
            if (succ == target) return true;
            seen[succ] = true;
            try stack.append(arena, succ);
        }
    }
    return false;
}

/// Whether a record value is owned where it is defined: built, updated, joined,
/// returned by a call, or a `mut` parameter.
fn ownedRecord(f: *const ir.Function, record: ir.Inst) bool {
    return switch (record.op) {
        .record_make, .record_set, .phi, .call => true,
        .param => ownedParameter(f.signature, record.data),
        else => false,
    };
}

/// Whether `second` can run after `first` without passing block `def` (where the
/// value both read is defined again).
fn runsAfter(arena: std.mem.Allocator, f: *const ir.Function, block_of: []const u32, first: ir.Ref, second: ir.Ref, def: u32) Error!bool {
    const from = block_of[first.index()];
    const target = block_of[second.index()];
    if (from == target) {
        const insts = f.blocks.items[from].insts.items;
        if (std.mem.indexOfScalar(ir.Ref, insts, second).? > std.mem.indexOfScalar(ir.Ref, insts, first).?) return true;
    }
    const seen = try arena.alloc(bool, f.blocks.items.len);
    @memset(seen, false);
    var stack: std.ArrayList(u32) = .empty;
    try stack.append(arena, from);
    while (stack.pop()) |b| {
        for (successors(f, b).slice()) |succ| {
            if (succ == def or seen[succ]) continue;
            if (succ == target) return true;
            seen[succ] = true;
            try stack.append(arena, succ);
        }
    }
    return false;
}

/// Before each `record_set` of a managed field, read the field it drops (an owned
/// value: the record's reference to it goes with the consumed record) and release it after.
fn extractDroppedFields(a: *Analysis) Error!void {
    const f = a.f;
    const e: Editor = .{ .arena = a.arena, .f = f, .origin = a.marks.origin };
    var b: usize = 0;
    while (b < f.blocks.items.len) : (b += 1) {
        var pos: usize = 0;
        while (pos < f.blocks.items[b].insts.items.len) : (pos += 1) {
            const ref = f.blocks.items[b].insts.items[pos];
            const set = f.inst(ref);
            if ((set.op != .record_set and set.op != .array_set) or a.marks.taken.contains(@backingInt(ref))) continue;
            const field = if (set.op == .array_set) a.module.compound(set.ty).array.elem else a.module.compound(set.ty).record[@intCast(set.data)];
            if (!a.module.managed(field)) continue;
            const old = try e.insertBefore(ref, .{
                .op = if (set.op == .array_set) .array_get else .record_get,
                .ty = field,
                .a = set.a,
                .b = if (set.op == .array_set) set.b else .none,
                .data = if (set.op == .array_set) 0 else set.data,
                .check = set.check,
                .span = set.span,
            });
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

/// A counting instruction to insert; `data` is `unique_release` for a release of a
/// value no other owner can share.
const Action = struct { place: Place, op: ir.Op, value: ir.Ref, data: u64 = 0 };

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
    // A list nothing shares (form 1's rule) has count 1 wherever it dies.
    const release_data = try releaseKind(a, ref);
    if (a.promoted[ref.index()]) try actions.append(a.arena, .{ .place = placeAfterDef(a, ref), .op = .retain, .value = ref });
    // Consuming uses: the last one moves, the others take a retained owner.
    for (a.uses[ref.index()].items) |use| {
        if (use.consume == 0) continue;
        if (use.onEdge()) {
            const extra = use.consume - @intFromBool(!a.liveInto(ref, use.succ));
            for (0..extra) |_| try actions.append(a.arena, .{ .place = .{ .edge = .{ .from = use.block, .to = use.succ } }, .op = .retain, .value = ref });
        } else {
            // A call that both takes the value (`mut`) and borrows it gets a second owner.
            const moves = !a.liveAfter(ref, use.block, use.pos) and use.borrow == 0;
            const extra = use.consume - @intFromBool(moves);
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
                // A use that also borrows the value (a `mut` call reading it too) does not move it.
                if (here and use.consume > 0 and use.borrow == 0) break true;
            } else false;
            if (consumed) continue;
            const at = block.insts.items[pos];
            const place: Place = if (f.inst(at).op.terminates()) .{ .before = at } else .{ .after = at };
            try actions.append(a.arena, .{ .place = place, .op = .release, .value = ref, .data = release_data });
        } else if (b == live.def) {
            // Defined and never used.
            try actions.append(a.arena, .{ .place = placeAfterDef(a, ref), .op = .release, .value = ref, .data = release_data });
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
            if (!taken) try actions.append(a.arena, .{ .place = .{ .edge = .{ .from = @intCast(b), .to = succ } }, .op = .release, .value = ref, .data = release_data });
        }
    }
}

/// The `data` an owned value's releases carry: may be `undef`, unique, or plain.
fn releaseKind(a: *Analysis, ref: ir.Ref) Error!u64 {
    if (a.maybeUndef(ref)) return empty_release;
    return if (try staticallyUnique(a, ref, .none)) unique_release else 0;
}

/// A borrowed value that a consuming use takes is retained first; an immortal one
/// needs no count.
fn countBorrowed(a: *Analysis, ref: ir.Ref, actions: *std.ArrayList(Action)) Error!void {
    if (a.f.inst(ref).ty == .str_view) return;
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
    if (a.inst(ref).op == .phi or a.inst(ref).op == .param) return .{ .top = a.where[ref.index()].block };
    return .{ .after = ref };
}

const Lists = std.AutoHashMapUnmanaged(u32, std.ArrayList(ir.Ref));

/// Insert the counting instructions. Retains go before releases at the same place,
/// so a value that a use both retains (to consume) and lets die is never freed first.
fn apply(a: *Analysis, actions: []const Action, stats: *Stats) Error!void {
    const f = a.f;
    const arena = a.arena;
    const e: Editor = .{ .arena = arena, .f = f, .origin = a.marks.origin };
    var before: Lists = .empty;
    var after: Lists = .empty;
    var top: Lists = .empty;
    var edges: std.array_hash_map.Auto(u64, std.ArrayList(ir.Ref)) = .empty;
    for ([_]ir.Op{ .retain, .release }) |op| {
        for (actions) |action| {
            if (action.op != op) continue;
            const counted = try e.newInst(.{ .op = op, .ty = .void, .a = action.value, .data = action.data, .span = f.inst(action.value).span });
            if (e.origin) |origin| {
                const frame = switch (action.place) {
                    .before, .after => |at| e.frameAt(at),
                    .top => |b| origin.table.block(origin.function, b),
                    .edge => |edge| origin.table.block(origin.function, edge.from),
                };
                try origin.setInstruction(arena, counted, frame);
            }
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
    origin: ?origins.Context = null,

    fn frameAt(e: Editor, ref: ir.Ref) ?u32 {
        const origin = e.origin orelse return null;
        const where = e.locate(ref);
        return origin.at(@intCast(where.block), ref);
    }

    fn inherit(e: Editor, ref: ir.Ref, anchor: ir.Ref) Error!void {
        if (e.origin) |origin| try origin.setInstruction(e.arena, ref, e.frameAt(anchor));
    }

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
        try e.inherit(ref, at);
        try e.f.blocks.items[where.block].insts.insert(e.arena, where.pos, ref);
        return ref;
    }

    fn insertAfter(e: Editor, at: ir.Ref, instruction: ir.Inst) Error!ir.Ref {
        const where = e.locate(at);
        const ref = try e.newInst(instruction);
        try e.inherit(ref, at);
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
        if (e.origin) |origin| try origin.copyBlock(e.arena, @intCast(head.index()), @intCast(tail.index()));
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
        if (e.origin) |origin| try origin.copyBlock(e.arena, from, @intCast(middle.index()));
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
pub const Successors = struct {
    buffer: [2]u32 = undefined,
    len: usize = 0,

    /// The successors, in terminator order.
    pub fn slice(self: *const Successors) []const u32 {
        return self.buffer[0..self.len];
    }
};

/// Whether `block` ends in `unreachable` (a trap: the process ends there).
fn endsInTrap(f: *const ir.Function, block: u32) bool {
    const insts = f.blocks.items[block].insts.items;
    return insts.len != 0 and f.inst(insts[insts.len - 1]).op == .@"unreachable";
}

// twin-drift-ok: facts.successorsOf keeps both targets of a branch as block ids;
// this one works on u32 indices and lists a branch's single target once.
/// The successor blocks of `block`, from its terminator.
pub fn successors(f: *const ir.Function, block: u32) Successors {
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
