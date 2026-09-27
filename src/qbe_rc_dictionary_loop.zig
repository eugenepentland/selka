//! Late fresh dictionary uniqueness over an already certified key/write tail.
const cow = @import("cow_plan.zig");
const model = @import("rc_dictionary_tail.zig");
const effects = @import("qbe_rc_dictionary_effects.zig");
const flow = @import("rc_dictionary_key.zig");
const reads = @import("qbe_rc_read_loans.zig");
/// Optional proof refusal retains original sites and ownership publication.
pub const Error = @import("qbe_rc_frame.zig").Error;
const Entry = struct { head: usize, back: usize, definition: usize };
const Budget = model.Budget;

/// Runs after loop-version veto and tail finalization. Only entry lists change:
/// sites, checked flags, captures, aliases, places and fast-loop plans stay put.
pub fn finalize(comptime E: type, self: *E) Error!void {
    const state = self.cow.?.rc orelse return;
    if (!state.active or state.readonly or state.contract.result == .borrowed) return;
    if (self.function.scope.instructions.len > 4096) return;
    var budget: Budget = .{};
    for (state.plan.dictionary_tails, 0..) |proof, index| {
        const entry = try certify(E, self, proof, &budget) orelse continue;
        const empty = try @import("qbe_rc_dictionary_empty.zig").certify(E, self, proof, entry.definition, entry.back, &budget);
        const plan = &self.cow.?.plan;
        const previous = plan.loops.entries[entry.head];
        const entries = try self.allocator.alloc(cow.Hoisted, previous.len + 1);
        @memcpy(entries[0..previous.len], previous);
        entries[previous.len] = .{ .local = @intCast(proof.root), .elements = false };
        @constCast(plan.loops.entries)[entry.head] = entries;
        @constCast(state.plan.dictionary_tails)[index].empty_drops = empty;
    }
}

fn certify(comptime E: type, self: *E, proof: model.Certificate, budget: *Budget) Error!?Entry {
    if (proof.key_authority != .anchored) return null;
    const code = self.function.scope.instructions;
    if (!budget.take(code.len * 2)) return null;
    for (code) |instruction| if (instruction.op == .switch_variant and
        !budget.take(instruction.op.switch_variant.arms.len)) return null;
    const definition = flow.definition(code, proof.root) orelse return null;
    if (definition == 0 or self.isBranchTarget(definition)) return null;
    const producer = code[definition - 1].op;
    if (producer != .make_record or producer.make_record.fields != 0) return null;
    if (producer.make_record.ty != self.function.scope.locals[proof.root].ty) return null;
    const analysis = self.ownership orelse return null;
    var head: ?usize = null;
    for (analysis.cows) |site| {
        if (!budget.take(1)) return null;
        if (site.pc != proof.start or site.local != proof.root) continue;
        if (!site.needed or site.elements) return null;
        if (site.via != proof.root or site.hoisted == cow.none) return null;
        head = site.hoisted;
    }
    const at = head orelse return null;
    if (at >= self.cow.?.plan.loops.back.len or definition >= at) return null;
    const back = self.cow.?.plan.loops.back[at];
    if (back == cow.none or back < at or back - at > 1024 or proof.start + 4 > back) return null;
    if (proof.key_authority.anchored.capture - 1 < at or (self.states[at] orelse return null).len != 0) return null;
    const entry: Entry = .{ .head = at, .back = back, .definition = definition };
    if (!try lifetime(E, self, proof, entry, budget)) return null;
    return entry;
}

fn lifetime(comptime E: type, self: *E, proof: model.Certificate, entry: Entry, budget: *Budget) Error!bool {
    const state = self.cow.?.rc.?;
    const plan = self.cow.?.plan;
    const key = proof.key_authority.anchored;
    for (state.plan.dictionary_tails) |other| {
        if (!budget.take(1)) return false;
        if (other.root == proof.root and other.start != proof.start) return false;
    }
    for (plan.loops.entries) |entries| {
        if (!budget.take(1)) return false;
        for (entries) |check| if (!budget.take(1) or check.local == proof.root) return false;
    }
    const code = self.function.scope.instructions;
    for (code, 0..) |instruction, pc| {
        if (!budget.take(1)) return false;
        if (instruction.op == .switch_variant and !budget.take(instruction.op.switch_variant.arms.len)) return false;
        if (!edges(instruction.op, pc, entry)) return false;
        if (pc < entry.definition or pc > entry.back) continue;
        if (instruction.inline_origin != null or self.states[pc] == null) return false;
        if (!quiet(E, self, proof, pc, budget)) return false;
        if (pc == entry.definition) continue;
        if (pc >= key.capture - 1 and pc <= proof.start + 4) continue;
        // Outside the already proved key interval, no managed producer,
        // receiver, root read/publication or callback is admitted.
        if (instruction.op != .pop and !try reads.scalar(E, self, instruction.op, &state.catalog)) return false;
        for (self.states[pc].?) |ty| {
            if (!budget.take(1)) return false;
            const shape = state.catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
            if (shape.counted or shape.unique_drop) return false;
        }
    }
    return true;
}

fn quiet(comptime E: type, self: *E, proof: model.Certificate, pc: usize, budget: *Budget) bool {
    const plan = self.cow.?.rc.?.plan;
    // Charge every metadata row inspected by the shared veto and this scan.
    if (!budget.take(plan.records.transfers.len + plan.records.writes.len + 1)) return false;
    if (!effects.quiet(E, self, proof, pc)) return false;
    return releasesQuiet(plan.locals.edges, proof, pc, budget);
}
fn releasesQuiet(rows: []const @import("rc_plan.zig").Edge, proof: model.Certificate, pc: usize, budget: *Budget) bool {
    for (rows) |release_edge| {
        if (!budget.take(1)) return false;
        if (release_edge.from != pc) continue;
        for (release_edge.releases) |release| {
            if (!budget.take(1)) return false;
            const local = @backingInt(release.storage);
            if (emptyRelease(proof, local)) continue;
            // Conservatively refuse even a scheduled release which current
            // emission might suppress. Only certified empty locals are exempt.
            return false;
        }
    }
    return true;
}

fn emptyRelease(proof: model.Certificate, local: usize) bool {
    return local == proof.receiver or local == proof.key or local == proof.key_authority.anchored.receiver;
}

fn edges(op: @FieldType(@import("bytecode.zig").Instruction, "op"), pc: usize, entry: Entry) bool {
    return @import("ownership_sources.zig").targetsSatisfy(op, pc, entry, edge);
}
fn edge(pc: usize, target: usize, entry: Entry) bool {
    const producer = entry.definition - 1;
    if (pc < producer and target > producer and target <= entry.back) return false;
    if (pc > entry.back and target > producer and target <= entry.back) return false;
    if (pc >= entry.head and pc <= entry.back) return target >= entry.head;
    return target <= entry.head or target > entry.back;
}

const t = @import("std").testing;
// spec-case: RC-DICTIONARY-LOOP-1
test "RC dictionary loop rejects middle entry and stale enclosing iteration" {
    const entry: Entry = .{ .definition = 4, .head = 8, .back = 20 };
    const arms = [_]@import("bytecode.zig").SwitchArm{ .{ .target = 3, .slot = null }, .{ .target = 8, .slot = null } };
    try t.expect(edge(20, 8, entry));
    try t.expect(edge(7, 8, entry));
    try t.expect(edge(25, 3, entry)); // An outer iteration recreates the root.
    try t.expect(!edge(25, 8, entry)); // Published old root would be reused.
    try t.expect(!edge(2, 4, entry)); // Skip the fresh producer.
    try t.expect(!edge(7, 12, entry)); // Skip the entry check.
    try t.expect(!edge(18, 5, entry)); // Inner backedge before the header.
    try t.expect(edges(.{ .switch_variant = .{ .ty = .unit, .arms = arms[0..1] } }, 25, entry));
    try t.expect(!edges(.{ .switch_variant = .{ .ty = .unit, .arms = &arms } }, 25, entry));
    try t.expect(!edges(.{ .try_result = .{ .input = .unit, .output = .unit, .error_target = 4 } }, 2, entry));
}
// spec-case: RC-DICTIONARY-LOOP-1
test "RC dictionary loop scan exhaustion never accepts a partial candidate" {
    var budget: Budget = .{ .left = 3 };
    try t.expect(budget.take(2));
    try t.expect(!budget.take(2));
    try t.expect(budget.take(1));
    try t.expect(!budget.take(1));
}

// spec-case: RC-DICTIONARY-LOOP-1
test "RC dictionary loop branch cleanup only exempts independently empty guards" {
    const proof: model.Certificate = .{
        .start = 18,
        .root = 0,
        .receiver = 1,
        .key = 2,
        .value = 3,
        .key_authority = .{ .anchored = .{
            .anchor = .{ .storage = @fromBackingInt(4) },
            .receiver = 5,
            .capture = 10,
            .projection = 15,
        } },
    };
    var releases = [_]@import("rc_plan.zig").Release{.{ .storage = @fromBackingInt(0), .guard = @fromBackingInt(0) }};
    var rows = [_]@import("rc_plan.zig").Edge{.{ .from = 7, .to = 18, .releases = &releases }};
    var budget: Budget = .{};
    try t.expect(!releasesQuiet(&rows, proof, 7, &budget));
    rows[0].to = 3;
    try t.expect(!releasesQuiet(&rows, proof, 7, &budget));
    releases[0].storage = @fromBackingInt(4); // The real key-list anchor.
    try t.expect(!releasesQuiet(&rows, proof, 7, &budget));
    releases[0].storage = @fromBackingInt(2); // Whole-local empty key guard.
    try t.expect(releasesQuiet(&rows, proof, 7, &budget));
}
