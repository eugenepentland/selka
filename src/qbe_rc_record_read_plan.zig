//! Closed scalar list reads anchored by an initialized private record home.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const homes = @import("rc_record_home.zig");
const cow = @import("cow_plan.zig");
const sources = @import("ownership_sources.zig");
const Op = @FieldType(bytecode.Instruction, "op");
const Certificate = @import("rc_record_read.zig").Certificate;
/// Proof refusal preserves complete ordinary publication.
pub const Error = @import("qbe_rc_frame.zig").Error;
const Budget = struct {
    remaining: usize = 262144,
    homes: homes.Budget = .{},

    fn take(self: *Budget, amount: usize) bool {
        if (amount > self.remaining) return false;
        self.remaining -= amount;
        return true;
    }
};

/// Run only after physical storage, COW entries and other certificates settle.
pub fn finalize(comptime E: type, self: *E) Error!void {
    const state = self.cow.?.rc orelse return;
    if (!state.active or state.readonly or state.contract.result == .borrowed) return;
    const code = self.function.scope.instructions;
    if (code.len > 4096 or self.function.scope.locals.len > 256) return;
    if (self.function.policy.c_abi or self.function.policy.host != null) return;
    var budget: Budget = .{};
    var found: std.ArrayList(Certificate) = .empty;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .get_field or pc == 0 or pc + 1 >= code.len) continue;
        const proof = try candidate(E, self, pc, &budget) orelse continue;
        const facts = try homes.analyze(E, self, proof.root, &budget.homes) orelse continue;
        if (!try interval(E, self, proof, facts, &budget)) continue;
        try found.append(self.allocator, proof);
    }
    state.plan.records.reads = try found.toOwnedSlice(self.allocator);
}

fn candidate(comptime E: type, self: *E, pc: usize, budget: *Budget) Error!?Certificate {
    const code = self.function.scope.instructions;
    if (code[pc - 1].op != .load_local or code[pc + 1].op != .store_local) return null;
    const root = @backingInt(code[pc - 1].op.load_local);
    const capture = @backingInt(code[pc + 1].op.store_local);
    if (!private(E, self, root, false) or !private(E, self, capture, true)) return null;
    if (root == capture or !try list(E, self, capture)) return null;
    const stack = self.states[pc] orelse return null;
    if (stack.len != 1 or stack[0] != self.function.scope.locals[root].ty) return null;
    const member = self.field(stack[0], code[pc].op.get_field) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    if (member.ty != self.function.scope.locals[capture].ty) return null;
    const end = uses(E, self, capture, pc + 1, budget) orelse return null;
    if (end < pc + 2 or end - (pc - 1) > 64 or end + 1 >= code.len) return null;
    if (code[end + 1].op != .store_local) return null;
    const target = @backingInt(code[end + 1].op.store_local);
    if (!try scalar(E, self, self.function.scope.locals[target].ty)) return null;
    return .{ .start = pc - 1, .end = end + 1, .root = root, .capture = capture };
}

fn private(comptime E: type, self: *E, local: usize, temporary: bool) bool {
    if (local < self.function.signature.parameter_count) return false;
    if (self.function.scope.locals[local].usage.temporary != temporary) return false;
    if (self.byReference(local) or self.callerStorage(local) or self.moves.resolve(local) != local) return false;
    const plan = self.cow.?.plan;
    if (plan.place(local) != null or (local < plan.aliases.len and plan.aliases[local] != cow.none)) return false;
    const entry = self.cow.?.rc.?.plan.locals.entry[local];
    return @backingInt(entry.storage) == local and entry.ownership == .empty;
}

fn list(comptime E: type, self: *E, local: usize) Error!bool {
    const ty = self.function.scope.locals[local].ty;
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.box or record.collection.kind != .list) return false;
    if (!try scalar(E, self, record.shape.buffer orelse return false)) return false;
    return !self.cow.?.rc.?.plan.journal.emptyLocal(local);
}

// Examine every static writer, including currently unreachable blocks.
fn uses(comptime E: type, self: *E, local: usize, store: usize, budget: *Budget) ?usize {
    var end: ?usize = null;
    for (self.function.scope.instructions, 0..) |instruction, pc| {
        if (!budget.take(1)) return null;
        switch (instruction.op) {
            .store_local => |id| if (@backingInt(id) == local and pc != store) return null,
            .load_local, .move_local, .ref_local => |id| if (@backingInt(id) == local) return null,
            .switch_variant => |dispatch| for (dispatch.arms) |arm| {
                if (!budget.take(1)) return null;
                if (arm.slot) |id| if (@backingInt(id) == local) return null;
            },
            .buffer_operation => |operation| if (@backingInt(operation.owner) == local) {
                if (pc <= store or (operation.kind != .read and operation.kind != .length)) return null;
                end = pc;
            },
            else => {},
        }
    }
    if (!budget.take(self.function.scope.instructions.len * 4 + self.function.scope.locals.len * 4)) return null;
    if (!@import("qbe_rc_dictionary_effects.zig").unwritten(E, self, local)) return null;
    if (cow.iterationOwner(self.function, local)) return null;
    return end;
}

fn interval(comptime E: type, self: *E, proof: Certificate, facts: []const u8, budget: *Budget) Error!bool {
    const code = self.function.scope.instructions;
    if ((self.states[proof.start] orelse return false).len != 0) return false;
    const projected = self.states[proof.start + 2] orelse return false;
    if (projected.len != 1 or projected[0] != self.function.scope.locals[proof.capture].ty) return false;
    if ((self.states[proof.start + 3] orelse return false).len != 0) return false;
    if ((self.states[proof.end + 1] orelse return false).len != 0) return false;
    if (self.live.?.after(proof.end, proof.capture)) return false;
    for (code, 0..) |instruction, pc| {
        if (!budget.take(1)) return false;
        if (instruction.op == .switch_variant and !budget.take(instruction.op.switch_variant.arms.len)) return false;
        if (!sources.targetsSatisfy(instruction.op, pc, proof, edge)) return false;
        if (pc < proof.start or pc > proof.end) continue;
        if (self.states[pc] == null or instruction.inline_origin != null or facts[pc] != homes.owned) return false;
        if (!try allowed(E, self, proof, pc, budget) or !try quiet(E, self, proof, pc, budget)) return false;
    }
    for (self.loop_plan.loops) |loop| {
        if (!budget.take(1)) return false;
        if (loop.head <= proof.end and loop.back >= proof.start) return false;
    }
    return true;
}

fn edge(pc: usize, target: usize, proof: Certificate) bool {
    if (pc < proof.start or pc > proof.end) return target <= proof.start or target > proof.end;
    return target > pc and target <= proof.end;
}

fn allowed(comptime E: type, self: *E, proof: Certificate, pc: usize, budget: *Budget) Error!bool {
    const code = self.function.scope.instructions;
    const op = code[pc].op;
    if (pc <= proof.start + 2) return true;
    if (op == .load_local and @backingInt(op.load_local) == proof.root) {
        return pc < proof.end and code[pc + 1].op == .get_field;
    }
    if (op == .get_field) {
        if (code[pc - 1].op != .load_local or @backingInt(code[pc - 1].op.load_local) != proof.root) return false;
        const member = self.field(self.function.scope.locals[proof.root].ty, op.get_field) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
        return scalar(E, self, member.ty);
    }
    if (op == .buffer_operation) {
        const access = op.buffer_operation;
        if (@backingInt(access.owner) != proof.capture or (access.kind != .read and access.kind != .length)) return false;
        return scalar(E, self, access.output);
    }
    if (!try @import("qbe_rc_read_loans.zig").scalar(E, self, op, &self.cow.?.rc.?.catalog)) return false;
    return plainStack(E, self, self.states[pc].?, budget);
}

fn plainStack(comptime E: type, self: *E, stack: []const typed.Type, budget: *Budget) Error!bool {
    if (!budget.take(stack.len)) return false;
    for (stack) |ty| if (!try scalar(E, self, ty)) return false;
    return true;
}

fn scalar(comptime E: type, self: *E, ty: typed.Type) Error!bool {
    if (!self.isScalar(ty)) return false;
    const state = self.cow.?.rc.?;
    const shape = state.catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    if (shape.counted or shape.unique_drop) return false;
    const size = (self.layout(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError).size;
    return size == 1 or size == 2 or size == 4 or size == 8;
}

fn quiet(comptime E: type, self: *E, proof: Certificate, pc: usize, budget: *Budget) Error!bool {
    const state = self.cow.?;
    const site = state.plan.at(pc);
    if (site.unique.len != 0 or site.unique_field != null or site.capture or site.fill) return false;
    if (site.shares.len != 0 or site.read_captures.len != 0 or state.plan.entry(pc).len != 0) return false;
    if (state.captures[pc].begin != cow.none or state.captures[pc].active != cow.none) return false;
    const plan = state.rc.?.plan;
    if (!budget.take(plan.records.transfers.len + plan.records.writes.len + plan.dictionary_tails.len)) return false;
    if (@import("qbe_rc_dictionary_effects.zig").intercepted(E, self, pc)) return false;
    for (plan.dictionary_tails) |tail| if (pc >= tail.start and pc <= tail.start + 4) return false;
    for (plan.locals.edges) |release_edge| {
        if (!budget.take(1)) return false;
        if (release_edge.from != pc) continue;
        for (release_edge.releases) |release| {
            if (!budget.take(1)) return false;
            const local = @backingInt(release.storage);
            if (local == proof.capture) continue;
            if (local == proof.root) return false;
            const locals = self.function.scope.locals.len;
            if (!budget.take(locals * locals + plan.locals.edges.len)) return false;
            if (try @import("qbe_rc_edges.zig").releasesAt(E, self, pc, local)) return false;
        }
    }
    return true;
}

const t = std.testing;
// spec-case: RC-RECORD-FIELD-READ-1
test "RC record field reads exclude middle entries exits and internal backedges" {
    const proof: Certificate = .{ .start = 4, .end = 12, .root = 0, .capture = 1 };
    try t.expect(edge(2, 4, proof));
    try t.expect(edge(15, 4, proof));
    try t.expect(edge(7, 10, proof));
    try t.expect(!edge(2, 5, proof));
    try t.expect(!edge(15, 12, proof));
    try t.expect(!edge(8, 7, proof));
    try t.expect(!edge(7, 13, proof));
}

const WriterProbe = struct { function: bytecode.Function, cow: ?struct { plan: cow.Plan } };
// spec-case: RC-RECORD-FIELD-READ-1
test "RC record field reads scan unreachable writers implicit aliases and exhausted budgets" {
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    var code = [_]bytecode.Instruction{
        .{ .span = span, .op = .{ .store_local = @fromBackingInt(1) } },
        .{ .span = span, .op = .{ .buffer_operation = .{ .owner = @fromBackingInt(1), .kind = .length, .output = .i64 } } },
        .{ .span = span, .op = .ret },
        .{ .span = span, .op = .{ .drop_local = @fromBackingInt(1) } },
    };
    var probe: WriterProbe = .{ .function = .{ .id = @fromBackingInt(0), .name = "capture", .scope = .{ .instructions = &code } }, .cow = .{ .plan = .{} } };
    var budget: Budget = .{};
    try t.expectEqual(@as(?usize, 1), uses(WriterProbe, &probe, 1, 0, &budget));
    for ([_]Op{ .{ .store_local = @fromBackingInt(1) }, .{ .load_local = @fromBackingInt(1) }, .{ .move_local = @fromBackingInt(1) }, .{ .ref_local = @fromBackingInt(1) } }) |writer| {
        code[3].op = writer;
        budget = .{};
        try t.expectEqual(@as(?usize, null), uses(WriterProbe, &probe, 1, 0, &budget));
    }
    code[3].op = .{ .drop_local = @fromBackingInt(1) };
    probe.cow.?.plan.aliases = &.{1};
    budget = .{};
    try t.expectEqual(@as(?usize, null), uses(WriterProbe, &probe, 1, 0, &budget));
    probe.cow.?.plan = .{ .sites = &.{.{ .unique = &.{.{ .local = 1 }} }} };
    budget = .{};
    try t.expectEqual(@as(?usize, null), uses(WriterProbe, &probe, 1, 0, &budget));
    probe.cow.?.plan = .{};
    budget = .{ .remaining = 1 };
    try t.expectEqual(@as(?usize, null), uses(WriterProbe, &probe, 1, 0, &budget));
}

const ScalarProbe = struct {
    cow: ?struct { rc: ?*State },
    fail_layout: bool = false,
    const State = struct { catalog: Catalog };
    const Catalog = struct {
        fail: bool = false,
        calls: usize = 0,
        fn get(self: *@This(), _: typed.Type) error{OutOfMemory}!struct { counted: bool = false, unique_drop: bool = false } {
            self.calls += 1;
            if (self.fail) return error.OutOfMemory;
            return .{};
        }
    };
    fn isScalar(_: *@This(), _: typed.Type) bool {
        return true;
    }
    fn layout(self: *@This(), _: typed.Type) error{OutOfMemory}!struct { size: u64 = 8 } {
        if (self.fail_layout) return error.OutOfMemory;
        return .{};
    }
};
// spec-case: RC-RECORD-FIELD-READ-1
test "RC record field reads charge every scalar stack entry and propagate allocation failures" {
    var state: ScalarProbe.State = .{ .catalog = .{} };
    var probe: ScalarProbe = .{ .cow = .{ .rc = &state } };
    var budget: Budget = .{ .remaining = 2 };
    try t.expect(!try plainStack(ScalarProbe, &probe, &.{ .i64, .i64, .i64 }, &budget));
    try t.expectEqual(@as(usize, 0), probe.cow.?.rc.?.catalog.calls);
    try t.expect(try plainStack(ScalarProbe, &probe, &.{ .i64, .i64 }, &budget));
    try t.expectEqual(@as(usize, 0), budget.remaining);
    try t.expectEqual(@as(usize, 2), probe.cow.?.rc.?.catalog.calls);
    probe.cow.?.rc.?.catalog.fail = true;
    budget = .{};
    try t.expectError(error.OutOfMemory, plainStack(ScalarProbe, &probe, &.{.i64}, &budget));
    probe.cow.?.rc.?.catalog.fail = false;
    probe.fail_layout = true;
    try t.expectError(error.OutOfMemory, plainStack(ScalarProbe, &probe, &.{.i64}, &budget));
}
