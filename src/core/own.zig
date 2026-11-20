//! Checked ownership lowers unique owners to direct destruction at their final use.
//! Borrowed children extend their owner lifetime; consuming uses transfer storage.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const transfers = @import("transfers.zig");
const flags = @import("flags.zig");
const promotion = @import("promote.zig");
const elements = @import("elements.zig");
const buffers = @import("buffers.zig");
const stores = @import("stores.zig");
const effects = @import("effects.zig");
const origins = @import("inline_origins.zig");
const selections = @import("borrow_selection.zig");
const certificate = @import("ownership_certificate.zig");
const Rule = @import("selka").ownership_rules.Rule;

/// Invalid ownership transfers fail closed; analysis may allocate.
pub const Error = std.mem.Allocator.Error || error{Unsupported};

/// Where the ownership pass stopped when it has no safe schedule: the function,
/// the instruction that could not be placed, and its source span. It is also the pass's report
/// channel: with `certificates` set, the pass writes down the table of owners it scheduled from.
pub const Refusal = struct {
    /// Where to keep each function's ownership table for the certificates (design §2), when asked.
    certificates: ?*certificate.Sink = null,
    /// The function whose body could not be scheduled.
    function: []const u8 = "",
    /// The IR operation that could not be placed (`call`, `phi`, …).
    operation: []const u8 = "",
    /// Its source span (0 when the pass failed before naming one).
    span: u32 = 0,
    /// The ownership rule when a valid operation has no supported safe schedule.
    rule: ?Rule = null,
    /// The other place the operation conflicts with, when the pass can name it.
    conflict: Conflict = .{},

    fn recorded(self: Refusal) bool {
        return self.function.len != 0 or self.operation.len != 0 or self.span != 0 or self.rule != null;
    }
};

/// The second place of an ownership refusal and how the refused operation conflicts with it, so the
/// diagnostic names the statement and both places instead of the function header alone.
pub const Conflict = struct {
    kind: Kind = .none,
    /// Where the other place is read in the source (0 when the pass has none).
    place: u32 = 0,
    /// How many field or element steps the other place is below its owner (0 for the owner itself).
    depth: u32 = 0,
    /// The function the code was inlined into, when the refusal is reported in an inlined callee.
    caller: []const u8 = "",

    /// What the refused operation does to the other place.
    pub const Kind = enum {
        none,
        /// It takes ownership of a part of an owner that the function only borrows at that point.
        takes_borrowed,
        /// It takes ownership of a value that is still read afterwards.
        takes_live,
        /// It takes ownership of a value that the same operation also borrows.
        takes_and_borrows,
        /// It takes ownership of one value twice.
        takes_twice,
        /// A branch hands a value on while the code it branches to still reads it.
        edge_live,
        /// A value lent to a task is read after every join of its group, or its group has no join.
        lent_unjoined,
        /// It returns a borrow that no source in the function's `from` clause owns.
        return_undeclared,
    };
};

/// How the pass runs.
pub const Options = struct {
    /// Preserve verify-build checks when promoting bounded storage to the stack.
    verify: bool = false,
    /// The function's facts (release builds): lists they bound may live on the stack.
    facts: ?*const facts.Facts = null,
    /// Optional source ancestry of instructions cloned before ownership.
    provenance: ?*origins.Table = null,
    function_index: u32 = 0,
    /// The module's effect summaries (`effects.zig`): with them, element stores nothing reads
    /// are removed or sunk and the rest narrowed to the fields that changed (`stores.zig`).
    effects: ?*const effects.Summaries = null,
    /// Filled when the pass returns `error.Unsupported`, so the caller can report
    /// a located diagnostic instead of a silent failure (REGRESSION-R2).
    refusal: ?*Refusal = null,
};

/// What the pass did, summed over functions.
pub const Stats = struct {
    in_place: u32 = 0,
    drops: u32 = 0,
    /// Lists promoted to the stack (`promote.zig`).
    promoted: u32 = 0,

    /// Add `other`'s counts to these.
    pub fn add(self: *Stats, other: Stats) void {
        self.in_place += other.in_place;
        self.drops += other.drops;
        self.promoted += other.promoted;
    }
};

/// Run the pass over every internal function of `module`.
pub fn run(arena: std.mem.Allocator, module: *ir.Module, options: Options) Error!Stats {
    return runWithScratch(arena, arena, module, options);
}

/// Run ownership with independently reclaimable analysis backing.
pub fn runWithScratch(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *ir.Module, options: Options) Error!Stats {
    @import("marker_validation.zig").validateModule(backing, module) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnsupportedInstruction => return error.Unsupported,
    };
    var total: Stats = .{};
    const summaries = options.effects orelse &try effects.analyze(arena, module);
    for (module.functions.items, 0..) |*f, index| {
        if (f.signature.linkage != .internal) continue;
        var local = options;
        local.function_index = @intCast(index);
        local.effects = summaries;
        total.add(try functionWithScratch(arena, backing, module, f, local));
    }
    return total;
}

/// Run the pass over one function of `module`.
pub fn function(arena: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, options: Options) Error!Stats {
    return functionWithScratch(arena, arena, module, f, options);
}

/// IR edits live on `arena`; analysis storage is freed through `backing`.
pub fn functionWithScratch(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, options: Options) Error!Stats {
    const previous = if (options.refusal) |refusal| refusal.recorded() else false;
    return functionInternal(arena, backing, module, f, options) catch |err| {
        if (err == error.Unsupported and !previous) if (options.refusal) |refusal| {
            if (refusal.function.len == 0) refusal.function = f.name;
            if (refusal.operation.len == 0) refusal.operation = "ownership";
        };
        return err;
    };
}

fn functionInternal(arena: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, options: Options) Error!Stats {
    // Analysis graphs and liveness die with this function; the IR edits below
    // still use the caller's allocator. A build arena cannot reclaim scratch.
    var work = std.heap.ArenaAllocator.init(backing);
    defer work.deinit();
    const scratch = work.allocator();
    @import("marker_validation.zig").validate(backing, module, f) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnsupportedInstruction => return error.Unsupported,
    };
    for (f.insts.items) |*inst| {
        if ((inst.op == .list_copy or inst.op == .dict_copy) and inst.data == flags.place_copy) inst.op = .copy;
    }
    _ = try @import("phi_cleanup.zig").run(backing, f);
    var stats: Stats = .{};
    var marks: Marks = .{ .origin = if (options.provenance) |table| table.context(options.function_index) else null, .refusal = options.refusal };
    if (options.facts) |known| {
        const promoted = try promotion.promote(arena, module, f, known, .{ .verify = options.verify, .provenance = marks.origin, .effects = options.effects });
        marks.stack = promoted.values;
        stats.promoted = promoted.lists;
        reserveFills(arena, f, known);
    }
    // Resolve duplicate record roots before matching an exact element-field round trip.
    // Keep the later merge too: borrow forwarding can introduce fresh field reads.
    try mergeFieldReads(scratch, f);
    // Normalize in-place element-field stores before scheduling owner deaths.
    _ = try elements.fieldStores(arena, module, f);
    // Byte-buffer appends become updates the emitter does inline.
    _ = try buffers.appends(arena, module, f);
    // Element stores nothing reads go, and the rest store only the fields that changed.
    if (options.effects) |summaries| _ = try stores.run(arena, module, f, summaries);
    elideUnchangedRecordStores(f);
    // Popped elements are found (or read) before anything moves.
    try markPops(.{ .arena = arena, .f = f, .origin = marks.origin }, scratch, module, &marks);
    const transferred = try transfers.slots(scratch, f);
    for (f.insts.items, 0..) |inst, index| {
        if (flags.transferredRead(inst) and module.managed(inst.ty)) try marks.owned_get.put(scratch, @intCast(index), {});
        if (transferred[index]) try marks.taken.put(scratch, @intCast(index), {});
    }
    if (options.effects) |summaries| try @import("borrow_fields.zig").run(arena, module, f, summaries, marks.origin);
    try mergeFieldReads(scratch, f);
    for (f.insts.items, 0..) |instruction, index| {
        const selection = (selections.call(module, f, instruction) catch return error.Unsupported) orelse continue;
        try marks.borrowed_selection.put(scratch, @intCast(index), {});
        if (selection.phi) |phi| try marks.borrowed_selection.put(scratch, @intCast(phi.index()), {});
    }
    try sinkDictionaryKeyCopies(.{ .arena = arena, .f = f, .origin = marks.origin }, scratch, module);
    try exposeDeadRecordFields(.{ .arena = arena, .f = f, .origin = marks.origin }, scratch, module, &marks);
    try takeFields(scratch, module, f, &marks);
    var phase_a = try Analysis.of(scratch, arena, module, f, &marks);
    try phase_a.analyze();
    if (try elideDeadCopies(&phase_a)) {
        // A copy of a list element that became a take at the copy site leaves the view it was read through unread.
        _ = try @import("take_first.zig").run(scratch, f);
        // Forwarded copies change the source's lifetime; all subsequent ownership
        // decisions use a fresh analysis, including borrowed child liveness.
        phase_a = try Analysis.of(scratch, arena, module, f, &marks);
        try phase_a.analyze();
    }
    try prepareDrops(&phase_a, &stats);
    var phase_b = try Analysis.of(scratch, arena, module, f, &marks);
    try phase_b.analyze();
    try scheduleDrops(&phase_b, &stats);
    if (options.facts) |known| markFillPushes(f, known);
    if (options.refusal) |report| if (report.certificates) |sink| try keepCertificate(&phase_b, sink, options.function_index);
    return stats;
}

/// Write the ownership table the drops were just scheduled from to `sink`, by instruction index: the
/// state of every value and the values each borrowed one lives in. The instructions `apply` added after
/// the analysis (drops, cleanup phis and their `undef`s) are beyond the table.
fn keepCertificate(a: *const Analysis, sink: *certificate.Sink, function_index: u32) Error!void {
    const scratch = a.storage.scratch;
    const states = try scratch.alloc(certificate.State, a.class.len);
    const parent_lists = try scratch.alloc([]const ir.Ref, a.class.len);
    for (states, parent_lists, 0..) |*state, *parent_list, i| {
        state.* = certifiedState(a, i);
        var found: std.ArrayList(ir.Ref) = .empty;
        if (state.* == .owned or state.* == .borrowed) {
            var iterator = a.parents(i);
            while (iterator.next()) |parent| if (parent != .none) try found.append(scratch, parent);
        }
        parent_list.* = found.items;
    }
    var table = try certificate.capture(a.storage.results, states, parent_lists);
    table.abandons = try a.storage.results.dupe(certificate.Abandon, a.abandoned.items);
    try sink.put(a.storage.results, function_index, table);
}

/// The certificate state of instruction `index` as the analysis classified it.
fn certifiedState(a: *const Analysis, index: usize) certificate.State {
    const instruction = a.f.insts.items[index];
    if (instruction.op == .copy or instruction.ty == .void) return .none;
    if (a.marks.stack.contains(@intCast(index))) return .stack;
    if (a.marks.emptied.contains(@intCast(index))) return .emptied;
    return switch (a.class[index]) {
        .owned => .owned,
        .borrowed => .borrowed,
        // A lent empty case (`classifyLentEmptyCases`) is a construction that owns nothing: the certificate states it scalar.
        .immortal => if (instruction.op == .union_make) .scalar else .immortal,
        .none => if (a.module.managed(instruction.ty) or a.module.containsBorrow(instruction.ty)) .none else .scalar,
    };
}

/// A by-value record set that writes back its exact field leaves the record
/// unchanged. Dead collection stores can expose this shape before ownership.
fn elideUnchangedRecordStores(f: *ir.Function) void {
    for (f.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op != .record_set) continue;
        const root = f.resolve(inst.a);
        const child = f.inst(f.resolve(inst.b));
        if (child.op != .record_get or f.resolve(child.a) != root or child.data != inst.data) continue;
        f.insts.items[ref.index()] = .{ .op = .copy, .ty = inst.ty, .a = root, .span = inst.span };
    };
}

/// A checked owner whose final use is an independent copy can move into the
/// result. Borrowed children can move only when their owning container dies too.
fn elideDeadCopies(a: *Analysis) Error!bool {
    const f = a.f;
    const Site = struct { ref: ir.Ref, source: ir.Ref, donor: ?ChildDonor };
    var sites: std.ArrayList(Site) = .empty;
    for (f.blocks.items, 0..) |block, b| {
        if (!a.present(b)) continue;
        for (block.insts.items, 0..) |ref, pos| {
            const source = @import("inline_snapshot.zig").source(a.module, f, f.inst(ref)) orelse continue;
            const where: Analysis.Where = .{ .block = @intCast(b), .pos = @intCast(pos) };
            if (deadCopyOwner(a, source, where)) {
                try sites.append(a.storage.scratch, .{ .ref = ref, .source = source, .donor = null });
            } else if (childCopyDonor(a, source, where)) |donor| {
                try sites.append(a.storage.scratch, .{ .ref = ref, .source = source, .donor = donor });
            }
        }
    }
    for (sites.items) |site| {
        if (site.donor) |donor| {
            try moveCopiedChild(a, site.ref, site.source, donor);
        } else {
            const old = f.inst(site.ref);
            // The copy the source spelled survives as the source itself: a written copy (`copy(value)`) that is
            // elided into its dead source hands its written mark to that source (C9 bytes), so the census still
            // sees the copy the program wrote.
            if (old.data & flags.written_copy != 0 and @import("copy_sites.zig").isSite(a.module, f.inst(site.source)))
                f.insts.items[site.source.index()].data |= flags.written_copy;
            f.insts.items[site.ref.index()] = .{ .op = .copy, .ty = old.ty, .a = site.source, .data = old.data & flags.written_copy, .span = old.span };
        }
    }
    return sites.items.len != 0;
}

fn deadCopyOwner(a: *const Analysis, source: ir.Ref, where: Analysis.Where) bool {
    return a.class[source.index()] == .owned and
        !a.marks.stack.contains(@intCast(source.index())) and a.live[source.index()] != null and
        !a.liveAfter(source, where.block, where.pos);
}

const ChildDonor = struct { root: ir.Ref, op: ir.Op, data: u64 = 0 };

/// Nulling a pointer slot is sufficient to detach one list element. A union or
/// box instead has an existing take operation, which also reclaims its shell.
/// Other inline aggregates and borrowed parents retain their explicit copies.
fn childCopyDonor(a: *const Analysis, source: ir.Ref, where: Analysis.Where) ?ChildDonor {
    if (a.class[source.index()] != .borrowed) return null;
    if (!a.module.isBlock(a.inst(source).ty) or a.liveAfter(source, where.block, where.pos)) return null;
    const f = a.f;
    var read = f.inst(source);
    // Only projections store their owning SSA value in a; calls store a callee.
    if (read.op != .list_get and read.op != .union_payload and read.op != .box_get) return null;
    var root = f.resolve(read.a);
    if (root == .none) return null;
    if (read.op == .box_get and f.inst(root).op == .union_payload) {
        read = f.inst(root);
        root = f.resolve(read.a);
    }
    const op: ir.Op = switch (read.op) {
        .list_get => if (read.data == 0) .list_get else return null,
        .union_payload => .union_take,
        .box_get => .box_take,
        else => return null,
    };
    if (!deadCopyOwner(a, root, where)) return null;
    if (op == .union_take) {
        const stored = a.module.compound(f.inst(root).ty).@"union"[@intCast(read.data)];
        const taken = if (a.module.kind(stored) == .box) a.module.compound(stored).box else stored;
        if (taken != f.inst(source).ty) return null;
    }
    if (op == .list_get and a.module.kind(f.inst(root).ty) != .list) return null;
    return .{ .root = root, .op = op, .data = read.data };
}

/// Re-read at the copy site, after previous borrowers have finished, and pair
/// the transferred list read with one clearing store. The remaining list owns
/// every unselected element and follows the ordinary destruction path.
fn moveCopiedChild(a: *Analysis, ref: ir.Ref, source: ir.Ref, donor: ChildDonor) Error!void {
    const f = a.f;
    const old = f.inst(ref);
    if (donor.op != .list_get) {
        f.insts.items[ref.index()] = .{ .op = donor.op, .ty = old.ty, .a = donor.root, .data = donor.data, .span = old.span };
        return;
    }
    const read = f.inst(source);
    const editor: Editor = .{ .arena = a.storage.results, .f = f, .origin = a.marks.origin };
    const got = try editor.insertBefore(ref, .{ .op = .list_get, .ty = old.ty, .a = donor.root, .b = read.b, .data = flags.place_read, .check = read.check, .span = old.span });
    const empty = try editor.insertBefore(ref, .{ .op = .undef, .ty = old.ty, .span = old.span });
    const detached = try editor.insertBefore(ref, .{ .op = .list_set, .ty = f.inst(donor.root).ty, .a = donor.root, .b = read.b, .data = try editor.extraOf(&.{empty}), .check = read.check, .span = old.span });
    try a.marks.owned_get.put(a.storage.scratch, @backingInt(got), {});
    try a.marks.taken.put(a.storage.scratch, @backingInt(detached), {});
    f.insts.items[ref.index()] = .{ .op = .copy, .ty = old.ty, .a = got, .span = old.span };
}

/// Repeated updates borrow their probe key and copy only a new stored key.
/// Delay only immutable octets whose complete copy-to-insert window is readonly.
fn sinkDictionaryKeyCopies(editor: Editor, scratch: std.mem.Allocator, module: *const ir.Module) Error!void {
    const f = editor.f;
    const graph = try UseGraph.of(scratch, f);
    const original_count = f.insts.items.len;
    for (0..original_count) |index| {
        const copied: ir.Ref = @fromBackingInt(@as(u32, @intCast(index)));
        const old = f.inst(copied);
        if (old.ty != .str and old.ty != .bytes) continue;
        const source = @import("inline_snapshot.zig").source(module, f, old) orelse continue;
        if (graph.block_of[index] == no_block) continue;
        var insertion: ?ir.Ref = null;
        var eligible = true;
        for (graph.uses[index].items) |user| {
            const used = f.inst(user);
            if (used.op == .dict_find and f.resolve(used.b) == copied) continue;
            if (used.op == .dict_insert and insertion == null) {
                const operands = f.operands(used.data);
                if (operands.len == 2 and f.resolve(operands[0]) == copied and f.resolve(operands[1]) != copied) {
                    insertion = user;
                    continue;
                }
            }
            eligible = false;
            break;
        }
        const insert = insertion orelse continue;
        if (!eligible) continue;
        const states = try scratch.alloc(u8, f.blocks.items.len);
        @memset(states, 0);
        const window: DictionaryCopyWindow = .{ .f = f, .module = module, .source = copied, .states = states };
        const at = editor.locate(insert);
        if (!window.clear(@intCast(at.block), at.pos)) continue;
        const insertion_inst = f.inst(insert);
        const owned_key = try editor.insertBefore(insert, old);
        const probe = try editor.insertBefore(insert, .{ .op = .dict_find, .ty = .i64, .a = insertion_inst.a, .b = owned_key, .span = insertion_inst.span });
        const values = f.operands(insertion_inst.data);
        const stored_value = values[1];
        f.insts.items[insert.index()].data = try editor.extraOf(&.{ owned_key, stored_value });
        f.insts.items[insert.index()].b = probe;
        f.insts.items[index] = .{ .op = .copy, .ty = old.ty, .a = source, .span = old.span };
    }
}

const DictionaryCopyWindow = struct {
    f: *const ir.Function,
    module: *const ir.Module,
    source: ir.Ref,
    states: []u8,

    /// Every incoming path reaches the original copy without a mutation or call.
    /// Cycles are refused rather than speculating across a loop iteration.
    fn clear(self: DictionaryCopyWindow, block: u32, end: usize) bool {
        if (self.states[block] != 0) return self.states[block] == 2;
        self.states[block] = 1;
        const instructions = self.f.blocks.items[block].insts.items;
        var position = end;
        while (position != 0) {
            position -= 1;
            const ref = instructions[position];
            if (ref == self.source) {
                self.states[block] = 2;
                return true;
            }
            const inst = self.f.inst(ref);
            if (!self.readonly(inst)) return false;
        }
        const predecessors = self.f.blocks.items[block].preds.items;
        if (predecessors.len == 0) return false;
        for (predecessors) |predecessor| {
            if (!self.clear(@intCast(predecessor.index()), self.f.blocks.items[predecessor.index()].insts.items.len)) return false;
        }
        self.states[block] = 2;
        return true;
    }

    fn readonly(self: DictionaryCopyWindow, inst: ir.Inst) bool {
        return switch (inst.op) {
            .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem, .neg, .bit_and, .bit_or, .bit_xor, .not, .cmp => true,
            .fadd, .fsub, .fmul, .fdiv, .fneg, .fcmp, .int_to_float, .float_to_int, .convert => true,
            .list_len, .list_get, .list_get_field, .str_len, .record_get, .union_tag, .union_payload, .box_get, .list_view_of, .list_slice_view => true,
            .copy, .iconst, .fconst, .str_const, .undef, .branch, .jump => true,
            .phi => !self.module.managed(inst.ty),
            .dict_find, .dict_entry_key, .dict_entry_value, .dict_len, .dict_entries, .dict_entry_live, .array_get => true,
            else => false,
        };
    }
};

/// Make unused siblings explicit before splitting an otherwise dead owned
/// record. The ordinary field-transfer and drop passes then move the selected
/// child and destroy every unused sibling exactly once.
fn exposeDeadRecordFields(editor: Editor, scratch: std.mem.Allocator, module: *const ir.Module, marks: *const Marks) Error!void {
    const f = editor.f;
    const graph = try UseGraph.of(scratch, f);
    const original_count = f.insts.items.len;
    for (0..original_count) |index| {
        const record: ir.Ref = @fromBackingInt(@as(u32, @intCast(index)));
        const instruction = f.inst(record);
        if (module.kind(instruction.ty) != .record or !module.managed(instruction.ty)) continue;
        // Updated records may inherit a sibling borrowed from an older version.
        // A fresh constructor has only the independent owners it consumes.
        if (instruction.op != .record_make or !ownedRecord(module, f, instruction)) continue;
        if (marks.borrowed_selection.contains(@backingInt(record))) continue;
        const home = graph.block_of[index];
        if (home == no_block or graph.uses[index].items.len == 0) continue;
        const fields = module.compound(instruction.ty).record;
        const counts = try scratch.alloc(u32, fields.len);
        @memset(counts, 0);
        var eligible = true;
        for (graph.uses[index].items) |user| {
            const read = f.inst(user);
            if (read.op != .record_get or graph.block_of[user.index()] != home) {
                eligible = false;
                break;
            }
            counts[@intCast(read.data)] += 1;
            if (module.managed(read.ty) and counts[@intCast(read.data)] > 1) eligible = false;
        }
        if (!eligible) continue;
        const first = for (f.blocks.items[home].insts.items) |ref| {
            if (std.mem.indexOfScalar(ir.Ref, graph.uses[index].items, ref) != null) break ref;
        } else continue;
        for (fields, counts, 0..) |field, reads, offset| {
            if (!module.managed(field) or reads != 0) continue;
            _ = try editor.insertBefore(first, .{ .op = .record_get, .ty = field, .a = record, .data = offset, .span = instruction.span });
        }
    }
}

/// Reserve known counted fills after stack promotion. Only detached i64/u64
/// parameters qualify, so the bound always dominates the empty constructor. A fill
/// whose body cannot trap reserves its whole count (`flags.fill_exact`); any other
/// reserves the speculative prefix, so an early trap is not preceded by an allocation
/// of the whole count (see `flags.fill_capacity_limit`).
fn reserveFills(arena: std.mem.Allocator, f: *ir.Function, known: *const facts.Facts) void {
    for (known.counted) |counted| {
        const bound = f.resolve(counted.bound);
        const source = f.inst(bound);
        if (source.op != .param or (source.ty != .i64 and source.ty != .u64)) continue;
        const exact: u64 = if (bodyCannotTrap(arena, f, counted.loop)) flags.fill_exact else 0;
        for (f.blocks.items[counted.loop.header.index()].insts.items) |ref| {
            const phi = f.inst(ref);
            if (phi.op != .phi or ref.index() >= known.aggregates.lists.len or !known.aggregates.lists[ref.index()].pattern) continue;
            if (f.resolve(known.aggregates.lists[ref.index()].length) != bound) continue;
            for (f.operands(phi.data)) |operand| {
                const entry = f.resolve(operand);
                const inst = f.inst(entry);
                if (inst.op != .list_new or inst.data != 0) continue;
                f.insts.items[entry.index()].a = bound;
                f.insts.items[entry.index()].data = flags.fill_capacity | exact;
            }
        }
    }
}

/// Whether a counted loop's body can trap or call out. The blocks reached from the
/// body, without entering the header or the exit, hold no checked instruction, no
/// trap terminator and no call. Allocation failure is not counted here: it fails
/// the same way growth would. Out of scratch memory answers false (the speculative path).
fn bodyCannotTrap(arena: std.mem.Allocator, f: *const ir.Function, loop: ir.Loop) bool {
    const seen = arena.alloc(bool, f.blocks.items.len) catch return false;
    @memset(seen, false);
    var stack: std.ArrayList(u32) = .empty;
    const header: u32 = @intCast(loop.header.index());
    const exit: u32 = @intCast(loop.exit.index());
    stack.append(arena, @intCast(loop.body.index())) catch return false;
    while (stack.pop()) |block| {
        if (seen[block]) continue;
        seen[block] = true;
        for (f.blocks.items[block].insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.check == .exact or inst.op == .@"unreachable" or inst.op == .call or inst.op == .call_indirect) return false;
        }
        for (successors(f, block).slice()) |next| {
            if (next == header or next == exit) continue;
            stack.append(arena, next) catch return false;
        }
    }
    return true;
}

/// COW may replace the receiver with a copy whose capacity is unknown. Only
/// the counted body's backedge push, still consuming the original unique loop
/// phi, uses its reserved room. Later appends must check capacity normally.
fn markFillPushes(f: *ir.Function, known: *const facts.Facts) void {
    for (known.counted) |counted| {
        for (f.blocks.items[counted.loop.header.index()].insts.items) |ref| {
            // Cleanup can append nullable owner phis after this facts snapshot.
            // Only analyzed instructions can carry a proved fill pattern.
            const phi = f.inst(ref);
            if (phi.op != .phi or ref.index() >= known.aggregates.lists.len or !known.aggregates.lists[ref.index()].pattern) continue;
            var reserved = false;
            for (f.operands(phi.data)) |operand| {
                const entry = f.inst(f.resolve(operand));
                reserved = reserved or (entry.op == .list_new and flags.isFillCapacity(entry.data));
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

/// Storage ownership and transfer marks attached while normalizing field reads.
const Marks = struct {
    origin: ?origins.Context = null,
    owned_get: std.AutoHashMapUnmanaged(u32, void) = .empty,
    borrowed_selection: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Values of lists promoted to the stack: require no destruction.
    stack: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// `record_set`s whose old field a read took over (`takeFields`): nothing to drop.
    taken: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Records whose block-holding fields were all read out (`takeFields`): require no destruction.
    emptied: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Where the pass stopped, when it reports `error.Unsupported`.
    refusal: ?*Refusal = null,
};

/// Where a value is live, by block.
const Live = struct {
    in: std.DynamicBitSetUnmanaged,
    out: std.DynamicBitSetUnmanaged,
    /// The uses this liveness was computed from (its own and its borrowed parts').
    uses: []const Use,
    def: u32,
};

fn addUnique(arena: std.mem.Allocator, values: *std.ArrayList(ir.Ref), ref: ir.Ref) Error!void {
    if (std.mem.indexOfScalar(ir.Ref, values.items, ref) == null) try values.append(arena, ref);
}

const Analysis = struct {
    storage: struct {
        /// Analysis-only work storage.
        scratch: std.mem.Allocator,
        /// Persistent IR and provenance allocations.
        results: std.mem.Allocator,
    },
    module: *const ir.Module,
    f: *ir.Function,
    marks: *Marks,
    /// Per instruction: its block (`no_block` outside every block) and position.
    where: []Where,
    class: []Class,
    /// The value a borrowed part was read from (`none` for roots).
    parent: []ir.Ref,
    /// Additional possible owners of a borrowed value; allocated only for shared ancestry.
    extra_parents: []std.ArrayList(ir.Ref) = &.{},
    /// Per value: the borrowed parts read from it.
    children: []std.ArrayList(ir.Ref),
    /// Per value: its direct uses.
    uses: []std.ArrayList(Use),
    /// Per value: the liveness used for ownership decisions (null: not computed).
    live: []?Live,
    /// Per block: whether it ends in `unreachable` (a trap path, which releases nothing).
    dead_end: []bool,
    /// The deaths a trap path skips, for the certificate: an owner live on the edge `from -> to` that nothing from `to` on needs.
    abandoned: std.ArrayList(certificate.Abandon) = .empty,

    const Where = struct { block: u32 = no_block, pos: u32 = 0 };

    fn of(arena: std.mem.Allocator, results: std.mem.Allocator, module: *const ir.Module, f: *ir.Function, marks: *Marks) Error!Analysis {
        const n = f.insts.items.len;
        const self: Analysis = .{
            .storage = .{ .scratch = arena, .results = results },
            .module = module,
            .f = f,
            .marks = marks,
            .where = try arena.alloc(Where, n),
            .class = try arena.alloc(Class, n),
            .parent = try arena.alloc(ir.Ref, n),
            .children = try arena.alloc(std.ArrayList(ir.Ref), n),
            .uses = try arena.alloc(std.ArrayList(Use), n),
            .live = try arena.alloc(?Live, n),
            .dead_end = try arena.alloc(bool, f.blocks.items.len),
        };
        @memset(self.where, .{});
        @memset(self.class, .none);
        @memset(self.parent, .none);
        @memset(self.children, .empty);
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
        // A block whose every successor is a trap-only block is one too: the process exits at the trap and runs
        // no destruction (RC-TRAP-TEARDOWN-1), so no owner is released on the way. Only a path that reaches the trap
        // counts: a cycle is not trap-only, and a loop that never exits keeps releasing what it builds.
        var changed = true;
        while (changed) {
            changed = false;
            for (f.blocks.items, 0..) |_, b| {
                if (self.dead_end[b] or !self.present(b)) continue;
                const next = successors(f, @intCast(b));
                if (next.len == 0) continue;
                var trapping = true;
                for (next.slice()) |succ| trapping = trapping and self.dead_end[succ];
                if (trapping) {
                    self.dead_end[b] = true;
                    changed = true;
                }
            }
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

    /// This SSA value owns its managed storage.
    fn owns(self: *const Analysis, ref: ir.Ref) bool {
        return self.class[ref.index()] == .owned;
    }

    fn analyze(self: *Analysis) Error!void {
        try self.classify();
        try self.collectUses();
        try self.addLentJoinUses();
        try self.computeLiveness();
    }

    /// Rule A (E1b, join before drops): a value a lent box holds is read by its tasks until their group joins. The owner the
    /// value is read from (its root, through fields, elements and borrowed bindings) gets a borrowed use at each join of the
    /// lent box's own group that the root's definition dominates, so the root's drop follows the join on every exit edge. The
    /// group is the lent box's second operand. Sound: a join the root's definition dominates sees the root defined, a move of
    /// the root after its group has joined is not seen by another group's join, and a lent box whose group has no join, or
    /// whose root owner no join of its group dominates, is refused (fail closed) rather than left to drop early.
    fn addLentJoinUses(self: *Analysis) Error!void {
        const f = self.f;
        var joins: std.ArrayList(LentJoin) = .empty;
        for (f.blocks.items, 0..) |block, b| {
            if (!self.present(b)) continue;
            for (block.insts.items, 0..) |ref, pos| {
                const group = joinedGroup(self.module, f, f.inst(ref)) orelse continue;
                try joins.append(self.storage.scratch, .{ .at = .{ .block = @intCast(b), .pos = @intCast(pos) }, .group = group });
            }
        }
        for (f.blocks.items, 0..) |block, b| {
            if (!self.present(b)) continue;
            for (block.insts.items) |ref| {
                const lent = f.inst(ref);
                if (lent.op != .box_make or lent.data & flags.lent_box == 0) continue;
                try self.lentJoinUses(ref, lent, joins.items);
            }
        }
    }

    /// A group join with the group it joins (E1b), for `addLentJoinUses`.
    const LentJoin = struct { at: Where, group: ir.Ref };

    /// The uses one lent box adds: its root owner is read at each join of the box's own group that the root's definition
    /// dominates. Refuses (fail closed) when the box names no group, its group has no join, or no such join is dominated.
    fn lentJoinUses(self: *Analysis, box: ir.Ref, lent: ir.Inst, joins: []const LentJoin) Error!void {
        const group = self.f.resolve(lent.b);
        var matched: usize = 0;
        for (joins) |join| {
            if (join.group == group) matched += 1;
        }
        if (group == .none or matched == 0) {
            refuseConflict(self, box, null, .{ .kind = .lent_unjoined, .place = self.f.resolve(lent.a) });
            return error.Unsupported;
        }
        // Every root the value may borrow from (a merge of two borrowed sources has two) gets its own join uses.
        for (try self.lentRoots(self.f.resolve(lent.a))) |root| {
            // A parameter or constant is not defined in a block: it outlives every join of the function.
            if (self.where[root.index()].block == no_block or self.class[root.index()] == .none) continue;
            var dominated: usize = 0;
            for (joins) |join| {
                if (join.group != group) continue;
                if (!try self.definedBefore(root, join.at)) continue;
                dominated += 1;
                try self.addUse(root, .{ .block = join.at.block, .pos = join.at.pos, .borrow = 1 });
            }
            if (dominated == 0) {
                refuseConflict(self, box, .Z3, .{ .kind = .lent_unjoined, .place = root });
                return error.Unsupported;
            }
        }
    }

    /// The owners a lent value is read from: the roots of its chains of borrowed parts (a field, an element, a borrowed
    /// binding, or a selection or view merge with two sources), each listed once. A root is a value with neither parent.
    fn lentRoots(self: *Analysis, value: ir.Ref) Error![]const ir.Ref {
        var roots: std.ArrayList(ir.Ref) = .empty;
        var pending: std.ArrayList(ir.Ref) = .empty;
        const seen = try self.storage.scratch.alloc(bool, self.f.insts.items.len);
        @memset(seen, false);
        try pending.append(self.storage.scratch, value);
        while (pending.pop()) |item| {
            const ref = self.f.resolve(item);
            if (ref == .none or seen[ref.index()]) continue;
            seen[ref.index()] = true;
            var expanded = false;
            var ancestors = self.parents(ref.index());
            while (ancestors.next()) |up| {
                if (up == .none) continue;
                expanded = true;
                try pending.append(self.storage.scratch, up);
            }
            if (!expanded) try roots.append(self.storage.scratch, ref);
        }
        return roots.items;
    }

    /// Whether the definition of `value` dominates the point `at`: earlier in its block, or in a block every path to `at` passes.
    fn definedBefore(self: *const Analysis, value: ir.Ref, at: Where) Error!bool {
        const def = self.where[value.index()];
        if (def.block == no_block) return false;
        if (def.block == at.block) return def.pos < at.pos;
        return dominatesBlock(self.storage.scratch, self.f, def.block, at.block);
    }

    fn classify(self: *Analysis) Error!void {
        const f = self.f;
        for (f.insts.items, 0..) |instruction, i| {
            if (!self.module.managed(instruction.ty) and !self.module.containsBorrow(instruction.ty)) continue;
            self.class[i] = switch (instruction.op) {
                // Source `mut` and inferred consuming parameters both receive one owner.
                .param => if (ownedParameter(f.signature, instruction.data)) .owned else .borrowed,
                // A static string and the cache owners of a borrowed text (C9 S1) own no heap block: never destroyed.
                .str_const, .undef, .text_sentinel, .text_frame => .immortal,
                .call => blk: {
                    if ((@import("borrowed_provider.zig").call(self.module, f, instruction) catch return error.Unsupported) != null)
                        break :blk .borrowed;
                    const contract = self.module.functions.items[instruction.a.index()].signature.borrow;
                    if (contract.sources.len != 0 and (contract.path.len == 0 or !self.module.managed(instruction.ty))) {
                        try self.callParents(i, @fromBackingInt(@as(u32, @intCast(i))), contract);
                        break :blk .borrowed;
                    }
                    break :blk .owned;
                },
                .union_make, .record_make => try self.aggregateClass(i, instruction),
                // A frame box (O4) lends its read-only parameter, as a borrow does; nothing drops it.
                // A frame block (RB1) lends its read-only parameter's storage the same way.
                .borrow, .box_frame, .block_frame => blk: {
                    self.parent[i] = f.resolve(instruction.a);
                    break :blk .borrowed;
                },
                .copy => .none,
                .list_get, .list_get_field, .record_get, .union_payload, .box_get, .dict_entry_key, .dict_entry_value, .array_get, .str_view_of, .str_slice_view, .str_slice_bytes_view, .list_view_of, .list_slice_view => blk: {
                    if (self.marks.owned_get.contains(@intCast(i))) break :blk .owned;
                    if (try self.projectedCall(@fromBackingInt(@as(u32, @intCast(i))))) |call| {
                        try self.callParents(i, call, self.module.functions.items[f.inst(call).a.index()].signature.borrow);
                    } else self.parent[i] = f.resolve(instruction.a);
                    break :blk .borrowed;
                },
                else => .owned,
            };
        }
        try self.classifyLentEmptyCases();
        try self.classifySelections();
        try self.classifyViewPhis();
        try self.classifyContainedLoans();
        try self.classifyExtractedLoans();
        // A phi no live instruction reads is ignored (its operands are not consumed).
        const live_phi = try self.livePhis();
        for (f.insts.items, 0..) |instruction, i| {
            if (instruction.op == .phi and !live_phi[i]) self.class[i] = .none;
            if (self.marks.stack.contains(@intCast(i)) or self.marks.emptied.contains(@intCast(i))) self.class[i] = .none;
        }
        for (self.parent, 0..) |p, child| {
            if (p != .none and (self.class[child] == .borrowed or self.module.containsBorrow(f.insts.items[child].ty))) try self.children[p.index()].append(self.storage.scratch, @fromBackingInt(@intCast(child)));
        }
        for (self.extra_parents, 0..) |parents_list, child| for (parents_list.items) |owner| {
            if (owner != self.parent[child] and (self.class[child] == .borrowed or self.module.containsBorrow(f.insts.items[child].ty)))
                try self.children[owner.index()].append(self.storage.scratch, @fromBackingInt(@intCast(child)));
        };
    }

    /// A case built with no managed payload (`None` of an option of a managed type) owns no heap block. When every use of
    /// it is a borrow (a defaulted field of a borrowed record, RB1), it is never destroyed, like a static string: as an
    /// owner it would die at the end of its iteration while a record kept in a longer-lived collection still borrowed it
    /// (J4). A case that is consumed, joined or returned stays an owner.
    fn classifyLentEmptyCases(self: *Analysis) Error!void {
        const f = self.f;
        var candidate = try self.storage.scratch.alloc(bool, f.insts.items.len);
        @memset(candidate, false);
        var any = false;
        for (f.insts.items, 0..) |instruction, i| {
            if (instruction.op != .union_make or self.class[i] != .owned or self.module.containsBorrow(instruction.ty)) continue;
            const operands = f.valueOperands(instruction);
            const empty = for (0..operands.len()) |position| {
                const ty = f.inst(f.resolve(operands.get(position))).ty;
                if (self.module.managed(ty) or self.module.containsBorrow(ty)) break false;
            } else true;
            candidate[i] = empty;
            any = any or empty;
        }
        if (!any) return;
        for (f.insts.items) |instruction| {
            const operands = f.valueOperands(instruction);
            for (0..operands.len()) |position| {
                const operand = f.resolve(operands.get(position));
                if (operand != .none and instruction.op != .borrow) candidate[operand.index()] = false;
            }
        }
        for (candidate, 0..) |lent, i| if (lent) {
            self.class[i] = .immortal;
        };
    }

    fn aggregateClass(self: *Analysis, index: usize, instruction: ir.Inst) Error!Class {
        // A record of dictionary-entry loans that is not provably one entry is refused, never built as an owner (FX6).
        if (unprovenItem(self.module, self.f, instruction)) {
            refuseConflict(self, @fromBackingInt(@as(u32, @intCast(index))), null, .{ .kind = .none, .place = .none });
            return error.Unsupported;
        }
        const parent = if (instruction.op == .record_make) borrowedItem(self.module, self.f, instruction) else self.borrowedPayload(instruction);
        if (self.module.containsBorrow(instruction.ty)) {
            // An empty Option[view] owns nothing, whereas Result[view, str]
            // still needs destruction of its owning error alternative.
            if (self.module.managed(instruction.ty)) return .owned;
        } else if (parent == null) return .owned;
        self.parent[index] = parent orelse .none;
        return .borrowed;
    }

    const ParentIterator = struct {
        primary: ir.Ref,
        extra: []const ir.Ref,
        index: usize = 0,

        fn next(iterator: *ParentIterator) ?ir.Ref {
            if (iterator.primary != .none) {
                const value = iterator.primary;
                iterator.primary = .none;
                return value;
            }
            if (iterator.index >= iterator.extra.len) return null;
            const value = iterator.extra[iterator.index];
            iterator.index += 1;
            return value;
        }
    };

    fn parents(self: *const Analysis, index: usize) ParentIterator {
        return .{ .primary = self.parent[index], .extra = if (self.extra_parents.len == 0) &.{} else self.extra_parents[index].items };
    }

    fn addParent(self: *Analysis, index: usize, source: ir.Ref) Error!void {
        if (source == .none or source.index() == index or self.parent[index] == source) return;
        if (self.parent[index] == .none) {
            self.parent[index] = source;
            return;
        }
        if (self.extra_parents.len == 0) {
            self.extra_parents = try self.storage.scratch.alloc(std.ArrayList(ir.Ref), self.parent.len);
            @memset(self.extra_parents, .empty);
        }
        try addUnique(self.storage.scratch, &self.extra_parents[index], source);
    }

    fn classifySelections(self: *Analysis) Error!void {
        for (self.f.insts.items, 0..) |instruction, index| {
            const selection = (selections.call(self.module, self.f, instruction) catch return error.Unsupported) orelse continue;
            self.class[index] = .borrowed;
            if (selection.phi) |phi| {
                self.parent[index] = phi;
                self.class[phi.index()] = .borrowed;
                try self.addParent(phi.index(), selection.dictionary);
                try self.addParent(phi.index(), selection.fallback);
            } else {
                try self.addParent(index, selection.dictionary);
                try self.addParent(index, selection.fallback);
            }
        }
    }

    /// Keep each incoming view as a parent. Cycles are traversed with visited sets,
    /// so a loop or arbitrarily large join needs no owner-count or round budget.
    fn classifyViewPhis(self: *Analysis) Error!void {
        for (self.f.insts.items, 0..) |instruction, index| {
            if (instruction.op != .phi or !self.module.containsBorrow(instruction.ty) or self.module.managed(instruction.ty)) continue;
            self.class[index] = .borrowed;
            for (self.f.operands(instruction.data)) |operand| try self.addParent(index, self.f.resolve(operand));
        }
    }

    // A transient result may own its error or writeback siblings while lending
    // one payload. Keep those loan edges even when the aggregate itself owns.
    fn classifyContainedLoans(self: *Analysis) Error!void {
        for (self.f.insts.items, 0..) |instruction, index| {
            if (!self.module.containsBorrow(instruction.ty)) continue;
            switch (instruction.op) {
                .call => {
                    const contract = self.module.functions.items[instruction.a.index()].signature.borrow;
                    const arguments = self.f.operands(instruction.data);
                    for (contract.sources) |source| if (source == .argument) {
                        if (source.argument >= arguments.len) return error.Unsupported;
                        try self.addParent(index, self.f.resolve(arguments[source.argument]));
                    };
                },
                .phi, .record_make, .union_make => {
                    // A borrowed record (1A) is a read-only overlay made of lent fields: each managed field is a loan of it.
                    const lent = instruction.op == .record_make and self.module.isBorrowed(instruction.ty);
                    const operands = self.f.valueOperands(instruction);
                    for (0..operands.len()) |position| {
                        const value = self.f.resolve(operands.get(position));
                        const field_loan = lent and self.module.managed(self.f.inst(value).ty) and self.class[value.index()] == .borrowed;
                        if (field_loan or self.module.containsBorrow(self.f.inst(value).ty)) try self.addParent(index, value);
                    }
                },
                // An element store into a collection of borrows (RB2) lends the stored element: the updated collection holds
                // it, and it inherits the loans of the collection it consumes (the pass names that one too, for lifetimes).
                .list_push, .list_set, .dict_set_value, .dict_insert => if (self.module.lentStore(instruction)) {
                    const operands = self.f.valueOperands(instruction);
                    for (0..operands.len()) |position| {
                        const value = self.f.resolve(operands.get(position));
                        if (value == .none) continue;
                        if (self.class[value.index()] == .borrowed or self.module.containsBorrow(self.f.inst(value).ty)) try self.addParent(index, value);
                    }
                },
                .record_get, .union_payload => {
                    // At the declared leaf callParents already names final
                    // returned owners. A wrapper prefix still lends its parent,
                    // unless the prefix is an owner: an owned read takes its slot
                    // out of the wrapper (a `mut` argument's writeback record),
                    // which that take empties, so the owner is no loan of it, and
                    // an owned projection lists no parents in the certificate.
                    if (self.class[index] != .owned and try self.projectedCall(@fromBackingInt(@as(u32, @intCast(index)))) == null) {
                        const operand = self.f.resolve(instruction.a);
                        try self.addParent(index, operand);
                        // Below a call whose borrow is kept by a returned owner (a `mut` parameter's final value), the
                        // prefix also lends what its operand lends: the declared leaf then names that owner as a later
                        // take of the call's result, at any depth (`Result[T?, E]` from `mut self`, F-RA-115).
                        if (self.class[operand.index()] == .borrowed and self.belowResultOwner(operand)) {
                            var lent = self.parents(operand.index());
                            while (lent.next()) |up| try self.addParent(index, up);
                        }
                    }
                },
                else => {},
            }
        }
    }

    /// Inlining exposes the return constructor instead of a call contract.
    /// When takeFields transfers its owners to sibling reads, move each loan's
    /// lifetime to the matching read, using the constructor's actual ancestry.
    fn classifyExtractedLoans(self: *Analysis) Error!void {
        for (self.f.insts.items, 0..) |instruction, index| {
            if (instruction.op != .record_get or !self.module.containsBorrow(instruction.ty)) continue;
            const record = self.f.resolve(instruction.a);
            const constructor = self.f.inst(record);
            if (constructor.op != .record_make) continue;
            const fields = self.f.operands(constructor.data);
            if (instruction.data >= fields.len) return error.Unsupported;
            const roots = try self.lentRoots(fields[@intCast(instruction.data)]);
            for (fields, 0..) |field, position| {
                const owner = self.f.resolve(field);
                if (std.mem.indexOfScalar(ir.Ref, roots, owner) == null) continue;
                const sibling = self.projection(record, &.{.{ .field = @intCast(position) }}) orelse continue;
                if (self.owns(sibling)) try self.addParent(index, sibling);
            }
        }
    }

    /// Whether `value` is projected, through field and payload reads, from a call whose borrowed result a returned owner
    /// keeps alive (a `.result` source of its contract).
    fn belowResultOwner(self: *const Analysis, value: ir.Ref) bool {
        var current = self.f.resolve(value);
        var remaining = self.f.insts.items.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const instruction = self.f.inst(current);
            switch (instruction.op) {
                .record_get, .union_payload => current = self.f.resolve(instruction.a),
                .call => {
                    for (self.module.functions.items[instruction.a.index()].signature.borrow.sources) |source| {
                        if (source == .result) return true;
                    }
                    return false;
                },
                else => return false,
            }
        }
        return false;
    }

    fn projectedCall(self: *Analysis, value: ir.Ref) Error!?ir.Ref {
        var reverse: std.ArrayList(ir.BorrowProjection) = .empty;
        var current = self.f.resolve(value);
        var remaining = self.f.insts.items.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const instruction = self.f.inst(current);
            switch (instruction.op) {
                .record_get => try reverse.append(self.storage.scratch, .{ .field = @intCast(instruction.data) }),
                .union_payload => try reverse.append(self.storage.scratch, .{ .payload = @intCast(instruction.data) }),
                .call => {
                    const contract = self.module.functions.items[instruction.a.index()].signature.borrow;
                    if (contract.sources.len == 0 or contract.path.len != reverse.items.len) return null;
                    for (contract.path, 0..) |step, index| if (!std.meta.eql(step, reverse.items[reverse.items.len - 1 - index])) return null;
                    return current;
                },
                else => return null,
            }
            current = self.f.resolve(instruction.a);
        }
        return null;
    }

    fn projection(self: *const Analysis, root: ir.Ref, path: []const ir.BorrowProjection) ?ir.Ref {
        var current = self.f.resolve(root);
        for (path) |step| {
            var found: ?ir.Ref = null;
            for (self.f.insts.items, 0..) |instruction, index| {
                const matches = switch (step) {
                    .field => |position| instruction.op == .record_get and instruction.data == position,
                    .payload => |tag| instruction.op == .union_payload and instruction.data == tag,
                };
                if (matches and self.f.resolve(instruction.a) == current) {
                    found = @fromBackingInt(@as(u32, @intCast(index)));
                    break;
                }
            }
            current = found orelse return null;
        }
        return current;
    }

    fn callParents(self: *Analysis, index: usize, call: ir.Ref, contract: ir.BorrowContract) Error!void {
        const instruction = self.f.inst(call);
        const operands = self.f.operands(instruction.data);
        for (contract.sources) |source| switch (source) {
            .argument => |position| {
                if (position >= operands.len) return error.Unsupported;
                try self.addParent(index, self.f.resolve(operands[position]));
            },
            .result => |path| try self.addParent(index, self.projection(call, path) orelse return error.Unsupported),
        };
    }

    /// Phis read by a non-phi instruction, directly or through other live phis.
    fn livePhis(self: *Analysis) Error![]bool {
        const f = self.f;
        const live = try self.storage.scratch.alloc(bool, f.insts.items.len);
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
        try stack.append(self.storage.scratch, used);
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
                        const borrowed = self.class[ref.index()] == .borrowed;
                        try self.addUse(f.resolve(operand), .{ .block = @backingInt(pred), .pos = 0, .succ = @intCast(b), .consume = @intFromBool(!borrowed), .borrow = @intFromBool(borrowed) });
                    }
                    continue;
                }
                const operands = f.valueOperands(instruction);
                const borrowed_item = borrowedItem(self.module, f, instruction) != null;
                for (0..operands.len()) |k| {
                    // A returned borrow must trace to a parameter named by the function's `from` clause (R4);
                    // without declared sources, a managed result supplies owned storage to its caller.
                    const returned = f.resolve(operands.get(k));
                    try self.validateReturned(instruction, returned, ref);
                    const consumes = (!borrowed_item and !self.borrowedOperand(instruction, returned) and consuming(instruction, k)) or self.handedOver(instruction, k);
                    try self.addUse(f.resolve(operands.get(k)), .{ .block = @intCast(b), .pos = @intCast(pos), .consume = @intFromBool(consumes), .borrow = @intFromBool(!consumes) });
                }
            }
        }
    }

    fn validateReturned(self: *Analysis, instruction: ir.Inst, operand: ir.Ref, at: ir.Ref) Error!void {
        if (instruction.op != .ret) return;
        const declared = self.f.signature.borrow.sources.len != 0;
        if (!declared and !self.borrowedOperand(instruction, operand)) return;
        if (try self.returnedBorrowDeclared(operand)) return;
        refuseConflict(self, at, null, .{ .kind = .return_undeclared, .place = operand });
        return error.Unsupported;
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
        try list.append(self.storage.scratch, use);
    }

    /// Whether operand `k` of a call is an argument the callee takes over.
    fn handedOver(self: *const Analysis, instruction: ir.Inst, k: usize) bool {
        if (instruction.op == .call_indirect) {
            if (k == 0) return false;
            return ownedParameter(self.module.compound(self.inst(self.f.resolve(instruction.a)).ty).@"fn", k - 1);
        }
        if (instruction.op != .call) return false;
        return ownedParameter(self.module.functions.items[instruction.a.index()].signature, k);
    }

    /// The borrowed payload a union is built around (R4): a union of a borrowed managed value borrows it, as a record of
    /// borrowed items does, so it is never dropped and its payload is never consumed.
    fn borrowedPayload(self: *const Analysis, instruction: ir.Inst) ?ir.Ref {
        const values = self.f.valueOperands(instruction);
        if (values.len() != 1) return null;
        const payload = self.f.resolve(values.get(0));
        if (payload == .none or self.class[payload.index()] != .borrowed) return null;
        return payload;
    }

    /// Validate projected payload roots against arguments and final writeback owners.
    fn returnedBorrowDeclared(self: *Analysis, operand: ir.Ref) Error!bool {
        return @import("borrow_result.zig").valid(self.storage.scratch, self.module, self.f, operand);
    }

    /// Whether operand `operand` of `instruction` is a borrowed managed value the instruction hands back or builds
    /// into a union: a borrow use, so its owner is not consumed (R4). Spans keep their own rules.
    fn borrowedOperand(self: *const Analysis, instruction: ir.Inst, operand: ir.Ref) bool {
        const lends = instruction.op == .ret or instruction.op == .union_make or instruction.op == .record_make or self.module.lentStore(instruction);
        if (!lends) return false;
        if (operand == .none or self.class[operand.index()] != .borrowed) return false;
        return true;
    }

    /// Keep the original owner while visiting each loan descendant once. This
    /// handles shared roots and loans packed alongside their transferred owner.
    fn liveUses(self: *Analysis, ref: ir.Ref, out: *std.ArrayList(Use)) Error!void {
        var visited = try std.DynamicBitSetUnmanaged.initEmpty(self.storage.scratch, self.class.len);
        defer visited.deinit(self.storage.scratch);
        var pending: std.ArrayList(ir.Ref) = .empty;
        defer pending.deinit(self.storage.scratch);
        try pending.append(self.storage.scratch, ref);
        while (pending.pop()) |value| {
            if (visited.isSet(value.index())) continue;
            visited.set(value.index());
            // A constructor or owning phi takes over its operand's storage.
            // Continue tracking external loan roots through it, but end the
            // transferred owner's lifetime at that move.
            if (value != ref and self.takesOwner(value, ref)) continue;
            // A loan is made where it is defined, so its root lives at least that long. A projection of a call's
            // borrowed result reads the call, not the root: when nothing reads the projection, the root's last use
            // would otherwise be the call, and the root would die before the loan is made (J4).
            if (value != ref and self.f.inst(value).op != .phi and self.where[value.index()].block != no_block) {
                const def = self.where[value.index()];
                try out.append(self.storage.scratch, .{ .block = def.block, .pos = def.pos, .borrow = 1 });
            }
            for (self.uses[value.index()].items) |use| {
                const actual = if (value == ref) use else Use{ .block = use.block, .pos = use.pos, .succ = use.succ, .borrow = use.consume + use.borrow };
                try out.append(self.storage.scratch, actual);
            }
            for (self.children[value.index()].items) |child| {
                if (!self.owns(child) or self.module.containsBorrow(self.f.inst(child).ty)) try pending.append(self.storage.scratch, child);
            }
        }
    }

    fn takesOwner(self: *const Analysis, container: ir.Ref, owner: ir.Ref) bool {
        if (!self.owns(owner)) return false;
        const instruction = self.f.inst(container);
        switch (instruction.op) {
            // takeFields may already have emptied a record into sibling reads;
            // its original construction still transferred these operands.
            .record_make, .union_make => if (!self.module.managed(instruction.ty)) return false,
            .phi => if (!self.owns(container)) return false,
            // An element store into a collection of borrows (RB2) takes over the collection it updates.
            .list_push, .list_set, .dict_set_value, .dict_insert => if (!self.module.lentStore(instruction)) return false,
            else => return false,
        }
        const operands = self.f.valueOperands(instruction);
        for (0..operands.len()) |position| {
            if (self.f.resolve(operands.get(position)) == owner) return true;
        }
        return false;
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
        // than a borrowed part is read cannot extend that part's earlier lifetime.
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

    /// Liveness of `ref` from `uses` alone.
    fn liveFrom(self: *Analysis, ref: ir.Ref, uses: []const Use) Error!Live {
        const nblocks = self.f.blocks.items.len;
        var live: Live = .{
            .in = try std.DynamicBitSetUnmanaged.initEmpty(self.storage.scratch, nblocks),
            .out = try std.DynamicBitSetUnmanaged.initEmpty(self.storage.scratch, nblocks),
            .uses = uses,
            .def = self.where[ref.index()].block,
        };
        var stack: std.ArrayList(u32) = .empty;
        for (uses) |use| {
            if (use.onEdge()) live.out.set(use.block);
            if (use.block != live.def and !live.in.isSet(use.block)) {
                live.in.set(use.block);
                try stack.append(self.storage.scratch, use.block);
            }
        }
        while (stack.pop()) |b| {
            for (self.f.blocks.items[b].preds.items) |pred_id| {
                const pred = @backingInt(pred_id);
                live.out.set(pred);
                if (pred != live.def and !live.in.isSet(pred)) {
                    live.in.set(pred);
                    try stack.append(self.storage.scratch, pred);
                }
            }
        }
        return live;
    }
};

/// Only the generated key/value pair of one dictionary entry is a borrowed
/// record. Every other record construction keeps its ordinary owning operands.
/// The two projections are compared by the dictionary they lend from
/// (`lentSource`): a dictionary of a borrowed type reaches each lookup through its
/// own `borrow` overlay, and those overlays are one dictionary (FX6).
fn borrowedItem(module: *const ir.Module, f: *const ir.Function, inst: ir.Inst) ?ir.Ref {
    if (inst.op != .record_make) return null;
    const fields = f.operands(inst.data);
    if (fields.len != 2) return null;
    const key = f.inst(f.resolve(fields[0]));
    const value = f.inst(f.resolve(fields[1]));
    if (flags.transferredRead(key) or flags.transferredRead(value)) return null;
    if (key.op != .dict_entry_key or value.op != .dict_entry_value) return unitItemParent(module, f, key, value);
    const owner = f.resolve(key.a);
    if (lentSource(f, owner) != lentSource(f, value.a) or !sameItemIndex(module, f, key.b, value.b)) return null;
    return owner;
}

/// Whether `inst` is built from a borrowed key and a borrowed value of dictionary entries that `borrowedItem` cannot
/// show to be one entry. Its fields are loans, so an owning record of them would destroy storage the dictionary still
/// holds (FX6): the analysis refuses it instead.
fn unprovenItem(module: *const ir.Module, f: *const ir.Function, inst: ir.Inst) bool {
    if (inst.op != .record_make or borrowedItem(module, f, inst) != null) return false;
    const fields = f.operands(inst.data);
    for (fields) |field| {
        const part = f.inst(f.resolve(field));
        const entry_read = part.op == .dict_entry_key or part.op == .dict_entry_value;
        if (entry_read and !flags.transferredRead(part) and module.managed(part.ty)) return true;
    }
    return false;
}

/// The value `ref` lends its storage from: through copies and `borrow` overlays, which share the layout and the
/// storage of the value they borrow.
fn lentSource(f: *const ir.Function, ref: ir.Ref) ir.Ref {
    var current = f.resolve(ref);
    while (current != .none and f.inst(current).op == .borrow) current = f.resolve(f.inst(current).a);
    return current;
}

/// Unit members have no dictionary payload, but record storage represents
/// them with a canonical false byte. The other member still borrows the table.
fn unitItemParent(module: *const ir.Module, f: *const ir.Function, key: ir.Inst, value: ir.Inst) ?ir.Ref {
    if (key.op == .dict_entry_key and unitItemField(value)) {
        const owner = f.resolve(key.a);
        const shape = module.dictShape(f.inst(owner).ty) orelse return null;
        if (shape.value == .void) return owner;
    }
    if (value.op == .dict_entry_value and unitItemField(key)) {
        const owner = f.resolve(value.a);
        const shape = module.dictShape(f.inst(owner).ty) orelse return null;
        if (shape.key == .bool) return owner;
    }
    return null;
}

fn unitItemField(inst: ir.Inst) bool {
    return inst.op == .iconst and inst.ty == .bool and inst.data == 0;
}

/// The two source projections can each lower the same ordinal lookup. This
/// helper only reads the same dictionary/ordinal; no general call equivalence
/// or index algebra is used to classify the generated borrowed pair.
fn sameItemIndex(module: *const ir.Module, f: *const ir.Function, left: ir.Ref, right: ir.Ref) bool {
    const a = f.resolve(left);
    const b = f.resolve(right);
    if (a == b) return true;
    const first = f.inst(a);
    const second = f.inst(b);
    if (first.op != .call or second.op != .call or first.a != second.a) return false;
    const callee = module.functions.items[first.a.index()];
    if (callee.signature.linkage == .internal or !std.mem.eql(u8, callee.name, "myl_core_dict_ordinal")) return false;
    const signature = callee.signature;
    if ((signature.passing.hasOwned() or signature.passing.hasConsumes() or signature.passing.hasViews()) or signature.ret != .i64) return false;
    if (signature.params.len != 2 or signature.params[1] != .i64) return false;
    if (module.kind(signature.params[0]) != .dict) return false;
    const x = f.operands(first.data);
    const y = f.operands(second.data);
    if (x.len != 2 or y.len != 2) return false;
    return lentSource(f, x[0]) == lentSource(f, y[0]) and f.resolve(x[1]) == f.resolve(y[1]);
}

/// Whether parameter `index` of a function with `signature` is passed owned.
fn ownedParameter(signature: ir.Signature, index: u64) bool {
    return signature.passing.takes(@intCast(index));
}

/// Whether operand `k` (in `valueOperands` order) of `instruction` is consumed by the operation itself, before
/// the dynamic exceptions (a borrowed operand of a `ret` or aggregate, a call argument): the ownership pass's
/// own table, which `ownership_ops.zig` states again and its test compares.
pub fn consuming(instruction: ir.Inst, k: usize) bool {
    if (k == 0 and instruction.op.consumesOperand0()) return true;
    return switch (instruction.op) {
        // a (the list) and b (the value); a (the record) and b (the field value).
        .list_push, .record_set => true,
        // a (the list), b (the index), then extra[0] (the value).
        .list_set, .list_set_field, .array_set, .dict_set_value, .dict_insert => k >= 2,
        .list_pop, .union_make, .union_take, .record_take, .box_take, .ret, .drop, .record_make => true,
        // Rule B (E1b, lent box): a box made with `flags.lent_box` borrows its operand, so the operand keeps its owner.
        // Sound: the box has no layout (emit_llvm), so dropping it frees its shell and releases nothing it holds; the
        // lender still drops the value, once, and rule A keeps that drop behind every group join.
        .box_make => instruction.data & flags.lent_box == 0,
        else => false,
    };
}

/// The group a call joins (E1b), resolved, when `inst` is a call of the runtime's group end; null for every other instruction.
fn joinedGroup(module: *const ir.Module, f: *const ir.Function, inst: ir.Inst) ?ir.Ref {
    if (inst.op != .call or inst.a == .none or inst.a.index() >= module.functions.items.len) return null;
    if (!std.mem.eql(u8, module.functions.items[inst.a.index()].name, "myl_core_owned_group_end")) return null;
    const operands = f.valueOperands(inst);
    if (operands.len() == 0) return null;
    return f.resolve(operands.get(0));
}

/// Whether `op` consumes and updates owned storage.
fn isUpdate(op: ir.Op) bool {
    return op.consumesOperand0() and op != .record_set and op != .array_set;
}

/// Every checked update transfers its unique owner; overwritten fields die here.
fn prepareDrops(a: *Analysis, stats: *Stats) Error!void {
    for (a.f.blocks.items, 0..) |block, b| {
        if (!a.present(b)) continue;
        for (block.insts.items) |ref| {
            if (isUpdate(a.f.inst(ref).op)) stats.in_place += 1;
        }
    }
    try extractDroppedFields(a);
}

/// A pop with no such read gets one after it, destroyed at once.
fn markPops(e: Editor, scratch: std.mem.Allocator, module: *const ir.Module, marks: *Marks) Error!void {
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
                try marks.owned_get.put(scratch, @backingInt(read), {});
                continue;
            }
            // The popped slot still holds the element: a pop only shortens the list.
            const len = try e.insertAfter(ref, .{ .op = .list_len, .ty = .u64, .a = ref, .span = pop.span });
            const got = try e.insertAfter(len, .{ .op = .list_get, .ty = element, .a = ref, .b = len, .span = pop.span });
            try marks.owned_get.put(scratch, @backingInt(got), {});
            _ = try e.insertAfter(got, .{ .op = .drop, .ty = .void, .a = got, .span = pop.span });
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
    const Key = struct { record: u32, field: u64, epoch: u32 = 0 };
    var first: std.AutoHashMapUnmanaged(Key, ir.Ref) = .empty;
    // A use of the record other than a field read (a call that borrows it whole, say) ends the reads before it: a read
    // after it stays its own value, so it can take the field for a write-back even though the earlier read's parts were
    // lent to that use (`derive(block, block.table.declared)` then `block.table.published = v`, F-RA-14).
    var epochs: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    for (f.blocks.items) |block| {
        first.clearRetainingCapacity();
        epochs.clearRetainingCapacity();
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op != .record_get) {
                if (inst.op == .copy or inst.op == .phi) continue;
                const operands = f.valueOperands(inst);
                for (0..operands.len()) |k| {
                    const used = f.resolve(operands.get(k));
                    if (used == .none) continue;
                    const epoch = try epochs.getOrPut(arena, @backingInt(used));
                    epoch.value_ptr.* = if (epoch.found_existing) epoch.value_ptr.* + 1 else 1;
                }
                continue;
            }
            const record = @backingInt(f.resolve(inst.a));
            const key: Key = .{ .record = record, .field = inst.data, .epoch = epochs.get(record) orelse 0 };
            const entry = try first.getOrPut(arena, key);
            if (!entry.found_existing) {
                entry.value_ptr.* = ref;
                continue;
            }
            f.insts.items[ref.index()] = .{ .op = .copy, .ty = inst.ty, .a = entry.value_ptr.*, .span = inst.span };
        }
    }
    const graph = try UseGraph.of(arena, f);
    // The merges below rewrite instructions only, so the blocks' dominance holds for every question they ask.
    const dominance = try Dominance.of(arena, f);
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
        const group: ReadGroup = .{ .graph = graph, .dominance = &dominance, .def = def, .reads = reads.items, .merged = merged, .record = record, .field = key.field };
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

/// The reads of one record's field `mergeable` weighs: the function's uses and block dominance, the record's
/// scope (`def`), the reads and which were merged, and the record and field.
const ReadGroup = struct { graph: UseGraph, dominance: *const Dominance, def: u32, reads: []const ir.Ref, merged: []const bool, record: ir.Ref, field: u64 };

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
    if (!group.dominance.dominates(from, to)) return false;
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
        var pending: std.ArrayList(Lent) = .empty;
        try pending.append(arena, .{ .value = other });
        var visited: usize = 0;
        while (pending.pop()) |lent| {
            const value = lent.value;
            visited += 1;
            if (visited > 64) return false;
            if (block_of[value.index()] == no_block) return false;
            if (try runsAfter(arena, f, block_of, earlier, value, group.def)) return false;
            for (group.graph.uses[value.index()].items) |user| {
                if (block_of[user.index()] == no_block or try runsAfter(arena, f, block_of, earlier, user, group.def)) return false;
                const part = f.inst(user);
                if (!lendsFirst(part.op) or f.resolve(part.a) != value) continue;
                // Below a dictionary's entry or a view, a scalar part lends nothing: its uses do not hold the field (FR54).
                const below = lent.below or !readsPart(part.op);
                if (below and holdsNothing(part.ty)) continue;
                try pending.append(arena, .{ .value = user, .below = below });
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
///   field read once: the reads own the fields and the record requires no destruction. This is
///   the write-back of a call with a result and `mut` parameters (or of its inlined body).
fn takeFields(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function, marks: *Marks) Error!void {
    const graph = try UseGraph.of(arena, f);
    var pending: std.ArrayList(ir.Ref) = .empty;
    const queued = try arena.alloc(bool, f.insts.items.len);
    @memset(queued, false);
    const ctx: Taking = .{ .arena = arena, .module = module, .f = f, .graph = graph, .marks = marks, .pending = &pending, .queued = queued };
    // Inlining can append a producer after its users in instruction storage. Seed
    // owners once, then visit newly transferred aggregates as their reads gain ownership.
    for (0..f.insts.items.len) |i| try ctx.enqueue(@fromBackingInt(@intCast(i)));
    // A take through a chain of updates (`takeThrough`) needs the chain's earliest record owned, and that record may
    // become owned only after the chain was visited: a nested record is owned once its parent's update takes it, and the
    // parent can sit later in the worklist. So the worklist runs again, over the updates still untaken, until a round
    // takes nothing new (`ctx.a.b.c.x` and `ctx.a.b.c.y` passed `mut` to one call, F-RA-710).
    while (true) {
        const taken = marks.taken.count();
        try takeRound(ctx);
        if (marks.taken.count() == taken) break;
    }
}

/// One pass of `takeFields` over its worklist, which grows as reads gain ownership.
fn takeRound(ctx: Taking) Error!void {
    const f = ctx.f;
    const module = ctx.module;
    const graph = ctx.graph;
    const arena = ctx.arena;
    const pending = ctx.pending;
    var next: usize = 0;
    while (next < pending.items.len) : (next += 1) {
        const ref = pending.items[next];
        const i = ref.index();
        const record = f.inst(ref);
        const kind = module.kind(record.ty);
        if (kind == .array) {
            for (graph.uses[i].items) |user| {
                const inst = f.inst(user);
                if (inst.op == .array_set and f.resolve(inst.a) == ref) try ctx.takeArrayReplaced(ref, user);
            }
            continue;
        }
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
        // Each set replaces its own field: arms of a branch may each update another one.
        for (sets.items) |update| {
            if (!ctx.marks.taken.contains(@backingInt(update))) try ctx.takeReplaced(ref, update);
        }
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
    pending: *std.ArrayList(ir.Ref),
    queued: []bool,

    /// An aggregate enters the worklist at most once, only after the existing
    /// ownership and borrowed-selection checks admit it.
    fn enqueue(self: Taking, ref: ir.Ref) Error!void {
        if (self.queued[ref.index()]) return;
        const record = self.f.inst(ref);
        const kind = self.module.kind(record.ty);
        if ((kind != .record and kind != .array) or !self.module.managed(record.ty)) return;
        if (self.marks.borrowed_selection.contains(@backingInt(ref))) return;
        if (!ownedRecord(self.module, self.f, record) and !self.marks.owned_get.contains(@backingInt(ref))) return;
        try self.pending.append(self.arena, ref);
        self.queued[ref.index()] = true;
    }

    fn markOwned(self: Taking, ref: ir.Ref) Error!void {
        try self.marks.owned_get.put(self.arena, @backingInt(ref), {});
        try self.enqueue(ref);
    }

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
        } else return self.takeThrough(record, update);
        for (self.graph.uses[record.index()].items) |user| {
            const inst = f.inst(user);
            if (user == get or user == update) continue;
            if (inst.op == .record_get and inst.data != field) continue;
            if (inst.op == .phi) {
                if (try phiAfter(self, record, get, user, def_block)) return;
                continue;
            }
            if (!try runsAfter(self.arena, f, self.graph.block_of, get, user, def_block)) continue;
            if (self.borrowsFirst(record, get, user)) continue;
            return;
        }
        try self.markOwned(get);
        try self.marks.taken.put(self.arena, @backingInt(update), {});
    }

    /// An inline array lends its exact selected slot to a nested update, under
    /// the same path and borrow-window checks used for named record fields.
    fn takeArrayReplaced(self: Taking, array: ir.Ref, update: ir.Ref) Error!void {
        const f = self.f;
        if (!self.module.managed(self.module.compound(f.inst(array).ty).array.elem)) return;
        const index = f.inst(update).b;
        const def = if (f.inst(array).op == .param) 0 else self.graph.block_of[array.index()];
        var reads: std.ArrayList(ir.Ref) = .empty;
        for (self.graph.uses[array.index()].items) |user| {
            const inst = f.inst(user);
            if (inst.op == .array_get and f.resolve(inst.a) == array and arrayIndex(f, index, inst.b) != .different)
                try addUnique(self.arena, &reads, user);
        }
        for (reads.items) |get| {
            if (arrayIndex(f, index, f.inst(get).b) != .same) continue;
            if (!try self.takes(get, update, reads.items, def)) continue;
            if (!try self.arrayWindow(array, get, update, def)) continue;
            try self.markOwned(get);
            try self.marks.taken.put(self.arena, @backingInt(update), {});
            return;
        }
    }

    fn arrayWindow(self: Taking, array: ir.Ref, get: ir.Ref, update: ir.Ref, def: u32) Error!bool {
        const f = self.f;
        for (self.graph.uses[array.index()].items) |user| {
            if (user == get or user == update) continue;
            const inst = f.inst(user);
            if (inst.op == .array_get and arrayIndex(f, f.inst(get).b, inst.b) == .different) continue;
            if (inst.op == .phi) {
                if (try phiAfter(self, array, get, user, def)) return false;
                continue;
            }
            if (!try runsAfter(self.arena, f, self.graph.block_of, get, user, def)) continue;
            if (self.borrowsFirst(array, get, user)) continue;
            return false;
        }
        return true;
    }

    /// `update` replaces a field of `record`, which updates of other fields made from an earlier
    /// record: a read of the field from that earlier record takes it over the same way, when
    /// nothing but reads of other fields and those updates uses the records in between while
    /// it holds the field (`wb = it.rt; it.returned = pop(mut wb); it.rt = wb`,
    /// NEW-CORE-CE2-EFFECTS-5).
    fn takeThrough(self: Taking, record: ir.Ref, update: ir.Ref) Error!void {
        const f = self.f;
        const field = f.inst(update).data;
        var chain: [4]ir.Ref = undefined;
        var len: usize = 0;
        var current = record;
        while (len < chain.len) {
            const inst = f.inst(current);
            if (inst.op != .record_set or inst.data == field) return;
            chain[len] = current;
            len += 1;
            const earlier = f.resolve(inst.a);
            if (self.marks.borrowed_selection.contains(@intCast(earlier.index()))) return;
            if (!ownedRecord(self.module, f, f.inst(earlier)) and !self.marks.owned_get.contains(@backingInt(earlier))) return;
            const def_block = if (f.inst(earlier).op == .param) 0 else self.graph.block_of[earlier.index()];
            var reads: std.ArrayList(ir.Ref) = .empty;
            for (self.graph.uses[earlier.index()].items) |user| {
                const got = f.inst(user);
                if (got.op == .record_get and got.data == field and f.resolve(got.a) == earlier) try addUnique(self.arena, &reads, user);
            }
            for (reads.items) |get| {
                if (!try self.takes(get, update, reads.items, def_block)) continue;
                if (!try self.clearThrough(.{ .earlier = earlier, .get = get, .update = update, .chain = chain[0..len] })) continue;
                try self.markOwned(get);
                try self.marks.taken.put(self.arena, @backingInt(update), {});
                return;
            }
            current = earlier;
        }
    }

    /// A field taken from `earlier` by `get` and put back by `update`, through `chain`: the
    /// updates of other fields from the record `update` replaces it in back to `earlier`'s.
    const Through = struct { earlier: ir.Ref, get: ir.Ref, update: ir.Ref, chain: []const ir.Ref };

    /// Whether, while `get` holds the field, only reads of other fields and the chain's own
    /// updates use `earlier` and the records of the chain.
    fn clearThrough(self: Taking, through: Through) Error!bool {
        const f = self.f;
        const field = f.inst(through.update).data;
        const holders = through.chain.len + 1;
        // The taken field belongs to the original record. A later holder's
        // definition may lie between that read and its users; stopping there
        // would hide live borrows through the preserving update.
        const def = if (f.inst(through.earlier).op == .param) 0 else self.graph.block_of[through.earlier.index()];
        for (0..holders) |k| {
            const holder = if (k == through.chain.len) through.earlier else through.chain[k];
            // The one use that carries the hole on: the next update of the chain, or `update`.
            const next = if (k == 0) through.update else through.chain[k - 1];
            for (self.graph.uses[holder.index()].items) |user| {
                const inst = f.inst(user);
                if (user == through.get or user == next) continue;
                if (inst.op == .record_get and inst.data != field) continue;
                if (inst.op == .phi) {
                    if (try phiAfter(self, holder, through.get, user, def)) return false;
                    continue;
                }
                if (try runsAfter(self.arena, f, self.graph.block_of, through.get, user, def)) return false;
            }
        }
        return true;
    }

    /// Whether `user`, a use of `record` after `get` took its field, only lends the record to
    /// a call in `get`'s block that runs before anything uses the taken field (CE2-B): `__wb = rt.globals;
    /// table.set(mut __wb, name, string_hash(rt, name), item); rt.globals = __wb`. The call sees
    /// the field as it was, since nothing can have updated it in place yet.
    fn borrowsFirst(self: Taking, record: ir.Ref, get: ir.Ref, user: ir.Ref) bool {
        const f = self.f;
        const inst = f.inst(user);
        if (inst.op != .call and inst.op != .call_indirect) return false;
        const block = self.graph.block_of[get.index()];
        if (self.graph.block_of[user.index()] != block) return false;
        const signature = if (inst.op == .call_indirect) self.module.compound(f.inst(f.resolve(inst.a)).ty).@"fn" else self.module.functions.items[inst.a.index()].signature;
        if (inst.op == .call_indirect and f.resolve(inst.a) == record) return false;
        for (f.operands(inst.data), 0..) |argument, k| {
            if (f.resolve(argument) == record and ownedParameter(signature, k)) return false;
        }
        const insts = f.blocks.items[block].insts.items;
        const at = std.mem.indexOfScalar(ir.Ref, insts, user).?;
        if (std.mem.indexOfScalar(ir.Ref, insts, get).? > at) return false;
        // A use in another block, or a join on an edge, runs once this block (and `user`) has.
        for (self.graph.uses[get.index()].items) |taker| {
            if (self.graph.block_of[taker.index()] != block or f.inst(taker).op == .phi) continue;
            if (std.mem.indexOfScalar(ir.Ref, insts, taker).? <= at) return false;
        }
        return true;
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
            if (!try self.clearOfWindow(other, get, def)) return false;
        }
        return true;
    }

    /// Every earlier borrowed read and its descendants must finish before a
    /// transfer takes the field. No later mutation can preserve a hidden owner.
    fn clearOfWindow(self: Taking, read: ir.Ref, get: ir.Ref, def: u32) Error!bool {
        var pending: std.ArrayList(ir.Ref) = .empty;
        try pending.append(self.arena, read);
        if (try runsAfter(self.arena, self.f, self.graph.block_of, get, read, def)) return false;
        while (pending.pop()) |value| {
            for (self.graph.uses[value.index()].items) |user| {
                if (self.graph.block_of[user.index()] == no_block) return false;
                const later = try runsAfter(self.arena, self.f, self.graph.block_of, get, user, def);
                if (later) return false;
                const inst = self.f.inst(user);
                if (readsPart(inst.op) and self.module.managed(inst.ty)) try addUnique(self.arena, &pending, user);
            }
        }
        return true;
    }

    fn dominates(self: Taking, through: u32, target: u32) Error!bool {
        return dominatesBlock(self.arena, self.f, through, target);
    }

    fn reachesOrTraps(self: Taking, from: u32, target: u32) Error!bool {
        return reachesOrTrapsBlock(self.arena, self.f, from, target);
    }

    /// A record used only by reads in its own block, each block-holding field read once:
    /// the reads own the fields and the record requires no destruction.
    fn empty(self: Taking, record: ir.Ref) Error!void {
        const f = self.f;
        // A phi owns only what its operands hand it on their edges, and an emptied value
        // is not independently destroyed: its operands would be destroyed where they die on those edges
        // while the reads still use the fields (a release build's unswitched loop exits
        // joining the loop record). A phi stays an ordinary owned record.
        if (f.inst(record).op == .phi) return;
        // An `own` parameter stays an ordinary owned record dropped whole: its certificate states every parameter owned,
        // borrowed or scalar (design §5, J1), so an emptied parameter cannot be stated (D-G-1). Emptying would save no
        // work: the reads borrow the fields and the drop destroys the same parts.
        if (f.inst(record).op == .param) return;
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
            if (self.module.managed(f.inst(user).ty)) try self.markOwned(user);
        }
        try self.marks.emptied.put(self.arena, @backingInt(record), {});
    }
};

/// Whether every path from the entry block to `target` passes block `through`.
pub fn dominatesBlock(arena: std.mem.Allocator, f: *const ir.Function, through: u32, target: u32) std.mem.Allocator.Error!bool {
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

/// The block dominance of one function, computed once for the many questions `mergeFieldReads` asks (Cooper, Harvey and
/// Kennedy's iteration over the reverse postorder, on the edges `successors` gives): the answers of `dominatesBlock`, each
/// in constant time instead of a walk of the whole function (lane P, `experiments/large-function-20261111`).
pub const Dominance = struct {
    /// Per block, its preorder number in the dominator tree, or `no_block` when the entry does not reach it.
    pre: []const u32,
    /// Per block, the largest preorder number in its subtree of the dominator tree.
    last: []const u32,

    /// The dominance of `f` as its blocks are now; an edit of its control flow makes it stale.
    pub fn of(arena: std.mem.Allocator, f: *const ir.Function) std.mem.Allocator.Error!Dominance {
        const n = f.blocks.items.len;
        const pre = try arena.alloc(u32, n);
        const last = try arena.alloc(u32, n);
        @memset(pre, no_block);
        @memset(last, no_block);
        if (n == 0) return .{ .pre = pre, .last = last };
        // Postorder from the entry over `successors`, the edges `dominatesBlock` walks.
        const post = try arena.alloc(u32, n);
        @memset(post, no_block);
        var order: std.ArrayList(u32) = .empty;
        const Frame = struct { block: u32, next: u32 };
        var stack: std.ArrayList(Frame) = .empty;
        const seen = try arena.alloc(bool, n);
        @memset(seen, false);
        seen[0] = true;
        try stack.append(arena, .{ .block = 0, .next = 0 });
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            const next = successors(f, top.block);
            if (top.next < next.len) {
                const succ = next.buffer[top.next];
                top.next += 1;
                if (!seen[succ]) {
                    seen[succ] = true;
                    try stack.append(arena, .{ .block = succ, .next = 0 });
                }
                continue;
            }
            post[top.block] = @intCast(order.items.len);
            try order.append(arena, top.block);
            _ = stack.pop();
        }
        // The predecessors among the reached blocks, from the same edges.
        const preds = try arena.alloc(std.ArrayList(u32), n);
        @memset(preds, .empty);
        for (order.items) |b| for (successors(f, b).slice()) |succ| try preds[succ].append(arena, b);
        const idom = try arena.alloc(u32, n);
        @memset(idom, no_block);
        idom[0] = 0;
        var changed = true;
        while (changed) {
            changed = false;
            var i = order.items.len;
            while (i > 0) {
                i -= 1;
                const b = order.items[i];
                if (b == 0) continue;
                var chosen: u32 = no_block;
                for (preds[b].items) |p| {
                    if (idom[p] == no_block) continue;
                    chosen = if (chosen == no_block) p else intersectDominators(idom, post, p, chosen);
                }
                if (chosen != idom[b]) {
                    idom[b] = chosen;
                    changed = true;
                }
            }
        }
        // Preorder numbers of the dominator tree: a block dominates exactly the blocks numbered within its subtree.
        const children = try arena.alloc(std.ArrayList(u32), n);
        @memset(children, .empty);
        for (order.items) |b| if (b != 0) try children[idom[b]].append(arena, b);
        var counter: u32 = 0;
        stack.clearRetainingCapacity();
        pre[0] = counter;
        counter += 1;
        try stack.append(arena, .{ .block = 0, .next = 0 });
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            if (top.next < children[top.block].items.len) {
                const child = children[top.block].items[top.next];
                top.next += 1;
                pre[child] = counter;
                counter += 1;
                try stack.append(arena, .{ .block = child, .next = 0 });
                continue;
            }
            last[top.block] = counter - 1;
            _ = stack.pop();
        }
        return .{ .pre = pre, .last = last };
    }

    /// `dominatesBlock`'s answer: whether every path from the entry to `target` passes `through` (always, for the entry
    /// as `through` and for a `target` the entry does not reach).
    pub fn dominates(self: *const Dominance, through: u32, target: u32) bool {
        if (through == 0 or self.pre[target] == no_block) return true;
        if (self.pre[through] == no_block) return false;
        return self.pre[through] <= self.pre[target] and self.pre[target] <= self.last[through];
    }
};

/// The nearest common dominator of `a` and `b`, walking up `idom` by postorder number.
fn intersectDominators(idom: []const u32, post: []const u32, a: u32, b: u32) u32 {
    var x = a;
    var y = b;
    while (x != y) {
        while (post[x] < post[y]) x = idom[x];
        while (post[y] < post[x]) y = idom[y];
    }
    return x;
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
        .list_get, .list_get_field, .record_get, .array_get, .union_payload, .box_get => true,
        else => false,
    };
}

/// A value `mergeable`'s walk visits: a read of the field or what it lends, and whether the path to it went through a
/// dictionary's entry or a view (`lendsFirst` beyond `readsPart`).
const Lent = struct { value: ir.Ref, below: bool = false };

/// Whether a value of type `ty` is a plain scalar, which borrows nothing.
fn holdsNothing(ty: ir.Type) bool {
    return switch (ty) {
        .void, .bool, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .f64, .f32, .cap => true,
        else => false,
    };
}

/// Whether the result of `op` still borrows its first operand, for `mergeable`'s walk of what a field read lends: a part
/// (`readsPart`), a dictionary's entry, or a span view of a list, text or bytes. Without the last two the walk stopped at
/// `r.d[k]` and missed a view of `r.d[k].f` still read after a later read of `r.d`, and merged that read's take ahead of it
/// (FR54).
fn lendsFirst(op: ir.Op) bool {
    return readsPart(op) or switch (op) {
        .dict_entry_key, .dict_entry_value, .list_view_of, .list_slice_view, .str_view_of, .str_slice_view, .str_slice_bytes_view => true,
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

/// An unresolved pair may alias: only exact SSA identity or two constants prove it.
fn arrayIndex(f: *const ir.Function, left: ir.Ref, right: ir.Ref) enum { same, different, unknown } {
    const a = f.resolve(left);
    const b = f.resolve(right);
    if (a == b) return .same;
    const x = f.inst(a);
    const y = f.inst(b);
    if (x.op != .iconst or y.op != .iconst or x.ty != y.ty) return .unknown;
    return if (x.data == y.data) .same else .different;
}

/// Whether a record value is owned where it is defined: built, updated, joined,
/// returned by a call, or a `mut` parameter.
fn ownedRecord(module: *const ir.Module, f: *const ir.Function, record: ir.Inst) bool {
    if (borrowedItem(module, f, record) != null) return false;
    if ((@import("borrowed_provider.zig").call(module, f, record) catch null) != null) return false;
    if ((selections.call(module, f, record) catch null) != null) return false;
    return switch (record.op) {
        // Indirect internal calls use the same owned result/writeback ABI as direct calls.
        .record_make, .record_set, .array_set, .phi, .call, .call_indirect, .union_take, .record_take, .box_take => true,
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
    const e: Editor = .{ .arena = a.storage.results, .f = f, .origin = a.marks.origin };
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
            try a.marks.owned_get.put(a.storage.scratch, @backingInt(old), {});
            _ = try e.insertAfter(ref, .{ .op = .drop, .ty = .void, .a = old, .span = set.span });
            pos += 2;
        }
    }
}

// ---- direct destruction ----------------------------------------------------------

/// Where a destruction instruction goes.
const Place = union(enum) {
    before: ir.Ref,
    after: ir.Ref,
    /// The top of a block, after its phis.
    top: u32,
    edge: struct { from: u32, to: u32 },
};

/// An owner to destroy at a location or control-flow edge.
const Action = struct { place: Place, value: ir.Ref };

fn scheduleDrops(a: *Analysis, stats: *Stats) Error!void {
    var actions: std.ArrayList(Action) = .empty;
    for (a.class, 0..) |class, i| {
        if (class == .none) continue;
        const ref: ir.Ref = @fromBackingInt(@intCast(i));
        if (a.owns(ref)) {
            if (a.live[i] != null) try dropOwned(a, ref, &actions);
        } else try validateBorrowedTransfer(a, ref, &actions);
    }
    try loansFirst(a, actions.items);
    try apply(a, actions.items, stats);
}

/// Two owners that die at one place are destroyed loan first: an owner that holds a loan on another (an owned result
/// that may carry a borrow of an argument, `-> T from self fails str` matched on its `Err` arm, F-RA-115) is dropped
/// before the owner it borrows from, so no loan outlives its root. Owners die in instruction order otherwise.
fn loansFirst(a: *const Analysis, actions: []Action) Error!void {
    // Group the actions by place; only a place with two or more deaths can need reordering.
    var groups: std.array_hash_map.Auto(PlaceKey, std.ArrayList(usize)) = .empty;
    for (actions, 0..) |action, index| {
        const entry = try groups.getOrPut(a.storage.scratch, placeKey(action.place));
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(a.storage.scratch, index);
    }
    for (groups.values()) |positions| {
        if (positions.items.len < 2) continue;
        var order = try a.storage.scratch.alloc(Action, positions.items.len);
        for (positions.items, 0..) |position, k| order[k] = actions[position];
        // Move each death ahead of the earliest death at its place whose value it holds a loan on.
        var k: usize = 1;
        while (k < order.len) : (k += 1) {
            var target = k;
            var j = k;
            while (j > 0) {
                j -= 1;
                if (try holdsLoanOn(a, order[k].value, order[j].value)) target = j;
            }
            if (target == k) continue;
            const moved = order[k];
            std.mem.copyBackwards(Action, order[target + 1 .. k + 1], order[target..k]);
            order[target] = moved;
        }
        for (positions.items, order) |position, action| actions[position] = action;
    }
}

/// A place as a hashable key: its kind and its instruction, block or edge.
const PlaceKey = struct { kind: u8, first: u32, second: u32 };

fn placeKey(place: Place) PlaceKey {
    return switch (place) {
        .before => |at| .{ .kind = 0, .first = @backingInt(at), .second = 0 },
        .after => |at| .{ .kind = 1, .first = @backingInt(at), .second = 0 },
        .top => |b| .{ .kind = 2, .first = b, .second = 0 },
        .edge => |edge| .{ .kind = 3, .first = edge.from, .second = edge.to },
    };
}

/// Whether `owner` reads, through its chain of borrowed parts, from `root`. The parents form a graph with cycles (a
/// collection of borrows carried around a loop is a phi whose parents include itself, RB2), so the walk visits each
/// value once instead of spending a step budget: a budget ran out inside such a cycle and missed the root (J4).
fn holdsLoanOn(a: *const Analysis, owner: ir.Ref, root: ir.Ref) Error!bool {
    if (owner == root) return false;
    var pending: std.ArrayList(ir.Ref) = .empty;
    var seen: std.AutoHashMapUnmanaged(ir.Ref, void) = .empty;
    try seen.put(a.storage.scratch, owner, {});
    var parents = a.parents(owner.index());
    while (parents.next()) |up| try pending.append(a.storage.scratch, up);
    while (pending.pop()) |value| {
        if (value == .none) continue;
        if (value == root) return true;
        if ((try seen.getOrPut(a.storage.scratch, value)).found_existing) continue;
        var above = a.parents(value.index());
        while (above.next()) |up| try pending.append(a.storage.scratch, up);
    }
    return false;
}

/// Validate owner transfers and destroy storage where its final borrowed use ends.
/// Name the operation that stopped the pass, if the caller asked for it. The
/// first refusal wins: it is the one the schedule broke on.
fn refuse(a: *const Analysis, ref: ?ir.Ref) void {
    refuseRule(a, ref, null);
}

/// Identify a valid ownership operation the scheduler cannot safely support.
fn refuseOwnership(a: *const Analysis, ref: ?ir.Ref) void {
    refuseRule(a, ref, .Z3);
}

fn refuseRule(a: *const Analysis, ref: ?ir.Ref, rule: ?Rule) void {
    refuseConflict(a, ref orelse .none, rule, .{ .kind = .none, .place = .none });
}

/// The other place of a refusal as the pass sees it: an IR value, and for `takes_live` the later use that still reads it.
const Other = struct { kind: Conflict.Kind, place: ir.Ref, later: ?Located = null };

/// A use position inside a block, for `Other.later`.
const Located = struct { block: u32, ref: ir.Ref };

/// Record the refused operation `ref`, the other place it conflicts with, and where to report both. An instruction that
/// inlining copied in from a callee is reported at the statement of the innermost function the two places share: the
/// operation itself when it is in that function, else the call there that leads to it.
fn refuseConflict(a: *const Analysis, ref: ir.Ref, rule: ?Rule, other: Other) void {
    const refusal = a.marks.refusal orelse return;
    if (refusal.recorded()) return;
    refusal.function = a.f.name;
    refusal.rule = rule;
    if (ref != .none) {
        const inst = a.f.inst(ref);
        refusal.operation = @tagName(inst.op);
        refusal.span = inst.span;
        if (other.kind != .none) {
            const place = if (other.later) |later| later.ref else other.place;
            const place_block = if (other.later) |later| later.block else a.where[place.index()].block;
            const site = statementOf(a, .{ .block = a.where[ref.index()].block, .ref = ref }, .{ .block = place_block, .ref = place });
            refusal.span = if (site.span != 0) site.span else inst.span;
            if (site.through_call) refusal.operation = "call";
            if (site.function) |index| {
                refusal.function = a.module.functions.items[index].name;
                refusal.conflict.caller = a.f.name;
            }
            refusal.conflict.kind = other.kind;
            refusal.conflict.place = placeSpan(a, place);
            refusal.conflict.depth = if (other.later == null) placeDepth(a, place) else 0;
        }
    }
    // A shape with no single offending operation still points at the function's
    // first located instruction, so the build reports a line rather than a
    // function name alone.
    if (refusal.span == 0) refusal.span = firstLocatedSpan(a.f);
}

/// Where a refusal is reported: the statement's span, the inlined callee it is in (null for the physical function), and
/// whether that statement is a call leading to the operation rather than the operation itself.
const RefusalSite = struct { span: u32, function: ?u32, through_call: bool };

/// The statement of `operation` in the innermost inline frame that also holds `place`.
fn statementOf(a: *const Analysis, operation: Located, place: Located) RefusalSite {
    const context = a.marks.origin orelse return .{ .span = 0, .function = null, .through_call = false };
    const own_frame = frameOf(context, operation);
    const place_frame = frameOf(context, place);
    // The innermost frame on the operation's chain that is also on the place's chain (null: the physical function).
    var common: ?u32 = own_frame;
    while (common) |frame| : (common = context.table.frames.items[frame].parent) {
        if (onChain(context, place_frame, frame)) break;
    }
    if (common == own_frame) return .{ .span = 0, .function = if (common) |frame| context.table.frames.items[frame].function else null, .through_call = false };
    // The call in the common frame that the operation's chain enters through.
    var current = own_frame;
    while (current) |frame| {
        const entry = context.table.frames.items[frame];
        if (entry.parent == common) return .{ .span = entry.call_span, .function = if (common) |outer| context.table.frames.items[outer].function else null, .through_call = true };
        current = entry.parent;
    }
    return .{ .span = 0, .function = null, .through_call = false };
}

fn frameOf(context: origins.Context, at: Located) ?u32 {
    if (at.ref == .none or at.block == no_block) return null;
    return context.at(at.block, at.ref);
}

fn onChain(context: origins.Context, start: ?u32, frame: u32) bool {
    var current = start;
    var steps: u32 = 0;
    while (current) |id| : (current = context.table.frames.items[id].parent) {
        if (id == frame) return true;
        steps += 1;
        if (steps > origins.max_depth) return false;
    }
    return false;
}

/// The instruction at a use: the operation itself, or the branch that ends the block for a use on an edge.
fn useInstruction(a: *const Analysis, use: Use) ir.Ref {
    const insts = a.f.blocks.items[use.block].insts.items;
    if (use.onEdge()) return if (insts.len == 0) .none else insts[insts.len - 1];
    return insts[use.pos];
}

/// A use of `ref` (or of a borrowed part of it) after `use`: later in the same block, else in another block.
fn laterUse(a: *const Analysis, live: Live, use: Use) ?Located {
    for (live.uses) |other| {
        if (other.onEdge() or other.block != use.block or other.pos <= use.pos) continue;
        const at = a.f.blocks.items[other.block].insts.items[other.pos];
        if (a.f.inst(at).span != 0) return .{ .block = other.block, .ref = at };
    }
    for (live.uses) |other| {
        if (other.onEdge() or other.block == use.block) continue;
        const at = a.f.blocks.items[other.block].insts.items[other.pos];
        if (a.f.inst(at).span != 0) return .{ .block = other.block, .ref = at };
    }
    return null;
}

/// The source span of a value, or of the nearest owner it was read from that has one.
fn placeSpan(a: *const Analysis, value: ir.Ref) u32 {
    var current = value;
    var steps: u32 = 0;
    while (current != .none and steps < 64) : (steps += 1) {
        const span = a.f.inst(current).span;
        if (span != 0) return span;
        current = a.parent[current.index()];
    }
    return 0;
}

/// How many borrowed-part steps a value is below its root owner.
fn placeDepth(a: *const Analysis, value: ir.Ref) u32 {
    var current = a.parent[value.index()];
    var depth: u32 = 0;
    while (current != .none and depth < 64) : (current = a.parent[current.index()]) depth += 1;
    return depth;
}

/// The source offset of the function's first instruction that carries one, so a
/// refusal the pass cannot tie to one operation still names a line.
fn firstLocatedSpan(f: *const ir.Function) u32 {
    for (f.insts.items) |instruction| {
        if (instruction.span != 0) return instruction.span;
    }
    return 0;
}

/// A consuming use must be the last use of `ref`: another owner cannot be manufactured. Refuses (rule Z3) at the first
/// use that takes the value while it is still read, borrowed by the same operation, taken twice, or live past a branch.
fn checkConsumes(a: *Analysis, ref: ir.Ref, live: Live) Error!void {
    for (a.uses[ref.index()].items) |use| {
        if (use.consume == 0) continue;
        if (use.onEdge()) {
            const extra = use.consume - @intFromBool(!a.liveInto(ref, use.succ));
            if (extra != 0) {
                refuseConflict(a, useInstruction(a, use), .Z3, .{ .kind = .edge_live, .place = ref });
                return error.Unsupported;
            }
        } else {
            // A call may not consume an owner while still borrowing it.
            const moves = !a.liveAfter(ref, use.block, use.pos) and use.borrow == 0;
            const extra = use.consume - @intFromBool(moves);
            if (extra != 0) {
                const kind: Conflict.Kind = if (use.consume > 1) .takes_twice else if (use.borrow != 0) .takes_and_borrows else .takes_live;
                const later = if (kind == .takes_live) laterUse(a, live, use) else null;
                refuseConflict(a, useInstruction(a, use), .Z3, .{ .kind = kind, .place = ref, .later = later });
                return error.Unsupported;
            }
        }
    }
}

fn dropOwned(a: *Analysis, ref: ir.Ref, actions: *std.ArrayList(Action)) Error!void {
    const f = a.f;
    const live = a.live[ref.index()].?;
    try checkConsumes(a, ref, live);
    // Deaths inside blocks: after the last use, when nothing later needs the value.
    for (f.blocks.items, 0..) |block, b| {
        if (!a.present(b) or live.out.isSet(b)) continue;
        if (a.dead_end[b]) {
            try abandonAfterLastUse(a, ref, live, @intCast(b));
            continue;
        }
        var last: ?u32 = null;
        for (live.uses) |use| {
            if (use.onEdge() or use.block != b) continue;
            if (last == null or use.pos > last.?) last = use.pos;
        }
        if (last) |pos| {
            const consumed = for (a.uses[ref.index()].items) |use| {
                const here = !use.onEdge() and use.block == b and use.pos == pos;
                // A use that also borrows the value does not move it.
                if (here and use.consume > 0 and use.borrow == 0) break true;
            } else false;
            if (consumed) continue;
            const at = block.insts.items[pos];
            const place: Place = if (f.inst(at).op.terminates()) .{ .before = at } else .{ .after = at };
            try actions.append(a.storage.scratch, .{ .place = place, .value = ref });
        } else if (b == live.def) {
            // Defined and never used.
            try actions.append(a.storage.scratch, .{ .place = placeAfterDef(a, ref), .value = ref });
        }
    }
    // Deaths on edges: live at the end of `b`, but neither needed in a successor nor taken by its phi.
    for (f.blocks.items, 0..) |_, b| {
        if (!a.present(b) or !live.out.isSet(b)) continue;
        const succs = successors(f, @intCast(b));
        for (succs.slice()) |succ| {
            if (a.liveInto(ref, succ)) continue;
            if (takenOnEdge(a, ref, @intCast(b), succ)) continue;
            // A path into a trap runs no destruction: the owner is abandoned there, and the certificate says so.
            if (a.dead_end[succ]) {
                try a.abandoned.append(a.storage.scratch, .{ .from = @intCast(b), .to = succ, .value = ref });
            } else try actions.append(a.storage.scratch, .{ .place = .{ .edge = .{ .from = @intCast(b), .to = succ } }, .value = ref });
        }
    }
}

/// An owner that was built on one arm only is read through the nullable phi `own_conditional_drop` made for the cleanups after the
/// join, not through its own value: the abandon of such an owner on an edge names that phi, which is what is live there. An owner
/// no phi was made for, and that its definition does not dominate, cannot be named and is not listed. No instruction is added.
fn nameAbandoned(a: *Analysis, nullable: *const @import("own_conditional_drop.zig").Builder) Error!void {
    var kept: usize = 0;
    for (a.abandoned.items) |gone| {
        const definition = a.where[gone.value.index()].block;
        var named = gone;
        if (definition != no_block and definition != gone.from and !try dominatesBlock(a.storage.scratch, a.f, definition, gone.from)) {
            named.value = nullable.peek(gone.value, gone.from) orelse continue;
        }
        a.abandoned.items[kept] = named;
        kept += 1;
    }
    a.abandoned.shrinkRetainingCapacity(kept);
}

/// Whether a phi of `succ` takes `ref` on the edge from block `b`.
fn takenOnEdge(a: *const Analysis, ref: ir.Ref, b: u32, succ: u32) bool {
    for (a.uses[ref.index()].items) |use| {
        if (use.onEdge() and use.block == b and use.succ == succ) return true;
    }
    return false;
}

/// The trap block `b` releases nothing, so an owner whose last use is in it (or that it defines and never uses) and that it does
/// not consume is still live at its end: it is abandoned on every edge out of `b` (the process ends at the trap).
fn abandonAfterLastUse(a: *Analysis, ref: ir.Ref, live: Live, b: u32) Error!void {
    var last: ?u32 = null;
    for (live.uses) |use| {
        if (use.onEdge() or use.block != b) continue;
        if (last == null or use.pos > last.?) last = use.pos;
    }
    if (last) |pos| {
        for (a.uses[ref.index()].items) |use| {
            const here = !use.onEdge() and use.block == b and use.pos == pos;
            if (here and use.consume > 0 and use.borrow == 0) return;
        }
    } else if (b != live.def) return;
    for (successors(a.f, b).slice()) |succ| {
        if (takenOnEdge(a, ref, b, succ)) continue;
        try a.abandoned.append(a.storage.scratch, .{ .from = b, .to = succ, .value = ref });
    }
}

/// Borrowed storage cannot escape through a consuming use; static storage is immutable.
fn validateBorrowedTransfer(a: *Analysis, ref: ir.Ref, _: *std.ArrayList(Action)) Error!void {
    if (a.module.containsBorrow(a.f.inst(ref).ty) or a.class[ref.index()] == .immortal) return;
    for (a.uses[ref.index()].items) |use| if (use.consume != 0) {
        refuseConflict(a, useInstruction(a, use), .Z3, .{ .kind = .takes_borrowed, .place = ref });
        return error.Unsupported;
    };
}

/// Right after `ref` is defined: after its block's phi group for a phi.
fn placeAfterDef(a: *const Analysis, ref: ir.Ref) Place {
    if (a.inst(ref).op == .phi or a.inst(ref).op == .param) return .{ .top = a.where[ref.index()].block };
    return .{ .after = ref };
}

const Lists = std.AutoHashMapUnmanaged(u32, std.ArrayList(ir.Ref));

/// Insert direct destruction without changing the order of existing instructions.
fn apply(a: *Analysis, actions: []const Action, stats: *Stats) Error!void {
    const f = a.f;
    const arena = a.storage.scratch;
    const e: Editor = .{ .arena = a.storage.results, .f = f, .origin = a.marks.origin };
    var before: Lists = .empty;
    var after: Lists = .empty;
    var top: Lists = .empty;
    var edges: std.array_hash_map.Auto(u64, std.ArrayList(ir.Ref)) = .empty;
    var nullable: @import("own_conditional_drop.zig").Builder = .{ .arena = a.storage.results, .scratch = arena, .function = f, .origin = a.marks.origin };
    try cleanupDeaths(a, &nullable, actions);
    {
        for (actions) |action| {
            const value = try cleanupValue(a, &nullable, action);
            const dropped = try e.newInst(.{ .op = .drop, .ty = .void, .a = value, .span = f.inst(action.value).span });
            if (e.origin) |origin| {
                const frame = switch (action.place) {
                    .before, .after => |at| e.frameAt(at),
                    .top => |b| origin.table.block(origin.function, b),
                    .edge => |edge| origin.table.block(origin.function, edge.from),
                };
                try origin.setInstruction(a.storage.results, dropped, frame);
            }
            stats.drops += 1;
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
            try list.append(arena, dropped);
        }
    }
    try nameAbandoned(a, &nullable);
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
                if (top.get(@intCast(b))) |list| try rebuilt.appendSlice(a.storage.results, list.items);
            }
            if (before.get(@backingInt(ref))) |list| try rebuilt.appendSlice(a.storage.results, list.items);
            try rebuilt.append(a.storage.results, ref);
            if (after.get(@backingInt(ref))) |list| try rebuilt.appendSlice(a.storage.results, list.items);
        }
        block.insts = rebuilt;
    }
}

/// Cleanup availability must not carry a released pointer around a backedge.
fn cleanupDeaths(a: *Analysis, nullable: *@import("own_conditional_drop.zig").Builder, actions: []const Action) Error!void {
    for (actions) |action| switch (action.place) {
        .edge => |edge| try nullable.clearEdge(action.value, edge.from, edge.to),
        .before, .after => |at| try nullable.clearAfter(action.value, a.where[at.index()].block),
        .top => |block| try nullable.clearAfter(action.value, block),
    };
}

/// A loan selected after a join may keep an owner defined on only one arm.
/// Its cleanup reads a nullable owner phi instead of a nondominating SSA value.
fn cleanupValue(a: *Analysis, nullable: *@import("own_conditional_drop.zig").Builder, action: Action) Error!ir.Ref {
    const definition = a.where[action.value.index()].block;
    if (definition == no_block) return action.value;
    const block: u32 = switch (action.place) {
        .before, .after => |at| a.where[at.index()].block,
        .top => |at| at,
        .edge => |edge| edge.from,
    };
    if (definition == block or try dominatesBlock(a.storage.scratch, a.f, definition, block)) return action.value;
    if (!a.module.managed(a.f.inst(action.value).ty)) return error.Unsupported;
    return nullable.read(action.value, definition, block);
}

fn listFor(arena: std.mem.Allocator, map: *Lists, key: u32) Error!*std.ArrayList(ir.Ref) {
    const entry = try map.getOrPut(arena, key);
    if (!entry.found_existing) entry.value_ptr.* = .empty;
    return entry.value_ptr;
}

// ---- R-2 peephole ---------------------------------------------------------------

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
