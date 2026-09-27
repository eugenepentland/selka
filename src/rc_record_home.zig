//! Converged ownership of private inline record homes across typed mut calls.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const sources = @import("ownership_sources.zig");
const cow = @import("cow_plan.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// One initialized owning value, including valid values with zero child edges.
pub const owned: u8 = 2;
/// Shared work bounds charge the root scans and every propagated CFG edge.
pub const Budget = struct {
    remaining: usize = 262144,
    roots: usize = 16,

    fn visit(self: *Budget) bool {
        if (self.remaining == 0) return false;
        self.remaining -= 1;
        return true;
    }
};
/// Optional proof refusal preserves ordinary publication.
pub const Error = error{ InternalError, OutOfMemory };

/// Return converged empty/O sets only after all root writers are accounted for.
pub fn analyze(comptime E: type, self: *E, root: usize, budget: *Budget) Error!?[]const u8 {
    const code = self.function.scope.instructions;
    if (code.len == 0 or code.len > 4096 or budget.roots == 0) return null;
    budget.roots -= 1;
    if (!try ordinary(E, self, root) or !writers(E, self, root, budget)) return null;
    for (code, 0..) |instruction, pc| {
        if (!budget.visit()) return null;
        switch (instruction.op) {
            .move_local => |id| if (@backingInt(id) == root) return null,
            .ref_local => |id| if (@backingInt(id) == root and !reference(E, self, root, pc, budget)) return null,
            .switch_variant => |dispatch| for (dispatch.arms) |arm| {
                if (!budget.visit()) return null;
                if (arm.slot) |id| if (@backingInt(id) == root) return null;
            },
            .buffer_operation => |operation| if (@backingInt(operation.owner) == root) return null,
            .store_local => |id| if (@backingInt(id) == root and intercepted(E, self, pc, budget)) return null,
            else => {},
        }
    }
    return converge(E, self, root, budget);
}

fn ordinary(comptime E: type, self: *E, root: usize) Error!bool {
    const local = self.function.scope.locals[root];
    const state = self.cow.?.rc orelse return false;
    if (!state.active or state.readonly or state.contract.result == .borrowed) return false;
    if (root < self.function.signature.parameter_count or local.usage.temporary or local.origin != .local) return false;
    if (self.byReference(root) or self.callerStorage(root) or self.moves.resolve(root) != root) return false;
    if (self.ownership.?.roles[root] != .owned or !local.ty.isAggregate()) return false;
    const record = self.program.records[local.ty.recordIndex()];
    if (!record.isRecord() or record.managed or record.isCollection()) return false;
    const entry = state.plan.locals.entry[root];
    if (@backingInt(entry.storage) != root or entry.ownership != .empty) return false;
    if (!entry.shape.counted or entry.shape.unique_drop or state.plan.journal.emptyLocal(root)) return false;
    if (!try @import("rc_field_authority.zig").safe(&state.catalog, local.ty)) return false;
    return !@import("value_semantics.zig").containsLiveView(self.program.records, local.ty);
}

fn writers(comptime E: type, self: *E, root: usize, budget: *Budget) bool {
    const plan = self.cow.?.plan;
    if (plan.place(root) != null or (root < plan.aliases.len and plan.aliases[root] != cow.none)) return false;
    for (plan.sites) |site| {
        if (!budget.visit()) return false;
        for (site.unique) |unique| {
            if (!budget.visit() or unique.local == root or unique.alias == root) return false;
        }
        if (site.unique_field) |place| if (place.parent == root) return false;
    }
    for (plan.loops.entries) |entries| {
        if (!budget.visit()) return false;
        for (entries) |entry| if (!budget.visit() or entry.local == root) return false;
    }
    for (plan.aliases) |parent| if (!budget.visit() or parent == root) return false;
    for (plan.places) |maybe| {
        if (!budget.visit()) return false;
        if (maybe) |place| {
            if (place.parent == root) return false;
            if (place.box) |box| if (box.owner == root) return false;
        }
    }
    return true;
}

fn intercepted(comptime E: type, self: *E, pc: usize, budget: *Budget) bool {
    for (self.cow.?.rc.?.plan.records.transfers) |proof| if (!budget.visit() or proof.projection == pc or proof.commit == pc) return true;
    return self.function.scope.instructions[pc].inline_origin != null;
}

// A reference stays at the same stack position until one canonical call consumes
// it. Even a semantically identity copy is refused: it is another physical use.
fn reference(comptime E: type, self: *E, root: usize, at: usize, budget: *Budget) bool {
    const code = self.function.scope.instructions;
    const before = self.states[at] orelse return false;
    const position = before.len;
    const limit = @min(code.len, at + 65);
    for (at + 1..limit) |pc| {
        if (!budget.visit() or self.isBranchTarget(pc) or code[pc].inline_origin != null) return false;
        if (!retained(E, self, root, pc - 1, budget)) return false;
        const inputs = self.states[pc] orelse return false;
        const op = code[pc].op;
        if (!sources.fallsThrough(op) or op == .try_result or op == .jump_if_false) return false;
        const pops = sources.popsOf(self.program, op);
        if (pops > inputs.len or position >= inputs.len) return false;
        if (inputs.len - pops <= position) return call(E, self, .{ .root = root, .read = at, .pc = pc, .position = position }, budget);
        switch (op) {
            .store_local, .drop_local, .move_local, .ref_local => |id| if (@backingInt(id) == root) return false,
            .begin_arena, .end_arena => return false,
            else => {},
        }
    }
    return false;
}

fn retained(comptime E: type, self: *E, root: usize, pc: usize, budget: *Budget) bool {
    for (self.cow.?.rc.?.plan.locals.edges) |edge| {
        if (!budget.visit()) return false;
        if (edge.from != pc or edge.to != pc + 1) continue;
        for (edge.releases) |release| {
            if (!budget.visit() or @backingInt(release.storage) == root) return false;
        }
    }
    return true;
}

const Reference = struct { root: usize, read: usize, pc: usize, position: usize };
fn call(comptime E: type, self: *E, ref: Reference, budget: *Budget) bool {
    const op = self.function.scope.instructions[ref.pc].op;
    if (op != .call) return false;
    const callee = self.program.functions[@backingInt(op.call)];
    if (callee.policy.c_abi or callee.policy.host != null or callee.scope.instructions.len == 0) return false;
    const inputs = self.states[ref.pc].?;
    const count = callee.signature.parameter_count;
    if (count > inputs.len or ref.position < inputs.len - count) return false;
    const parameter = ref.position - (inputs.len - count);
    const ty = self.function.scope.locals[ref.root].ty;
    if (callee.scope.locals[parameter].ty != ty or !typed.referenceMut(self.program.records, ty)) return false;
    const declared = for (callee.signature.declared_mutates) |position| {
        if (!budget.visit()) return false;
        if (position == parameter) break true;
    } else false;
    if (!declared) return false;
    const operands = self.ownership.?.operands[ref.pc] orelse return false;
    if (operands.len != inputs.len) return false;
    for (operands[inputs.len - count ..], inputs.len - count..) |source, index| {
        if (!budget.visit()) return false;
        if (source.origin != .local or source.local != ref.root) continue;
        if (index != ref.position or source.part != .whole or source.read != ref.read) return false;
    }
    const source = operands[ref.position];
    return source.origin == .local and source.local == ref.root and source.part == .whole and source.read == ref.read;
}

const Flow = struct {
    facts: []u8,
    queued: []bool,
    queue: []usize,
    cleared: std.AutoHashMapUnmanaged(EdgeKey, void),
    head: usize = 0,
    length: usize = 0,

    fn add(self: *Flow, pc: usize, fact: u8) void {
        if (self.facts[pc] | fact == self.facts[pc]) return;
        self.facts[pc] |= fact;
        if (self.queued[pc]) return;
        self.queue[(self.head + self.length) % self.queue.len] = pc;
        self.length += 1;
        self.queued[pc] = true;
    }
};

fn converge(comptime E: type, self: *E, root: usize, budget: *Budget) Error!?[]const u8 {
    const code = self.function.scope.instructions;
    var flow: Flow = .{
        .facts = try self.allocator.alloc(u8, code.len),
        .queued = try self.allocator.alloc(bool, code.len),
        .queue = try self.allocator.alloc(usize, code.len),
        .cleared = .{},
    };
    for (self.cow.?.rc.?.plan.locals.edges) |edge| {
        if (!budget.visit()) return null;
        for (edge.releases) |release| {
            if (!budget.visit()) return null;
            if (@backingInt(release.storage) == root) try flow.cleared.put(self.allocator, .{ .from = edge.from, .to = edge.to }, {});
        }
    }
    @memset(flow.facts, 0);
    @memset(flow.queued, false);
    flow.add(0, 1);
    while (flow.length != 0) {
        if (!budget.visit()) return null;
        const pc = flow.queue[flow.head];
        flow.head = (flow.head + 1) % code.len;
        flow.length -= 1;
        flow.queued[pc] = false;
        if (self.states[pc] == null) continue;
        const op = code[pc].op;
        const fact = next(op, root, flow.facts[pc]);
        var buffer: [2]usize = undefined;
        for (sources.branchTargets(op, &buffer)) |target| if (!propagate(.{ .from = pc, .to = target }, fact, &flow, budget)) return null;
        if (op == .switch_variant) for (op.switch_variant.arms) |arm| {
            if (!propagate(.{ .from = pc, .to = arm.target }, fact, &flow, budget)) return null;
        };
        if (sources.fallsThrough(op) and pc + 1 < code.len) {
            if (!propagate(.{ .from = pc, .to = pc + 1 }, fact, &flow, budget)) return null;
        }
    }
    return flow.facts;
}

fn next(op: Op, root: usize, fact: u8) u8 {
    return switch (op) {
        .store_local => |id| if (@backingInt(id) == root) owned else fact,
        .drop_local => |id| if (@backingInt(id) == root) 1 else fact,
        .end_arena => |id| if (root >= @backingInt(id)) 1 else fact,
        else => fact,
    };
}
const EdgeKey = struct { from: usize, to: usize };
fn propagate(edge: EdgeKey, fact: u8, flow: *Flow, budget: *Budget) bool {
    if (!budget.visit() or edge.to >= flow.facts.len) return false;
    flow.add(edge.to, if (flow.cleared.contains(edge)) 1 else fact);
    return true;
}

const t = std.testing;
const Probe = struct {
    allocator: std.mem.Allocator,
    function: bytecode.Function,
    states: []const ?[]const typed.Type,
    cow: ?struct { rc: ?struct { plan: struct { locals: struct { edges: []const @import("rc_plan.zig").Edge } } } },
};

fn converged(all_initialized: bool, allowance: usize) !?u8 {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const ops = [_]Op{
        .{ .jump_if_false = 4 },                                                     .{ .store_local = @fromBackingInt(0) }, .{ .jump = 5 },                         .push_unit,
        if (all_initialized) .{ .store_local = @fromBackingInt(0) } else .push_unit, .{ .jump_if_false = 8 },                .{ .store_local = @fromBackingInt(0) }, .{ .jump = 5 },
        .ret,
    };
    var code: [ops.len]bytecode.Instruction = undefined;
    for (&code, ops) |*instruction, op| instruction.* = .{ .span = .{ .start = 0, .end = 0 }, .op = op };
    const states: [ops.len]?[]const typed.Type = @splat(&.{});
    var probe: Probe = .{
        .allocator = arena.allocator(),
        .function = .{ .id = @fromBackingInt(0), .name = "probe", .scope = .{ .instructions = &code } },
        .states = &states,
        .cow = .{ .rc = .{ .plan = .{ .locals = .{ .edges = &.{} } } } },
    };
    var budget: Budget = .{ .remaining = allowance };
    const result = try converge(Probe, &probe, 0, &budget) orelse return null;
    return result[5];
}

// spec-case: RC-NAMED-RECORD-WRITE-1
test "RC named record convergence never hides an empty predecessor behind a backedge" {
    try t.expectEqual(@as(?u8, 3), try converged(false, 100));
    try t.expectEqual(@as(?u8, owned), try converged(true, 100));
    try t.expectEqual(@as(?u8, null), try converged(true, 2));
    try t.expectEqual(@as(u8, 1), next(.{ .drop_local = @fromBackingInt(0) }, 0, owned));
    try t.expectEqual(@as(u8, 1), next(.{ .end_arena = @fromBackingInt(0) }, 0, owned));
    try t.expectEqual(owned, next(.{ .end_arena = @fromBackingInt(1) }, 0, owned));
}

const ReferenceProbe = struct {
    function: bytecode.Function,
    program: bytecode.Program,
    states: []const ?[]const typed.Type,
    ownership: ?struct { operands: []const ?[]const sources.Source },
    cow: @FieldType(Probe, "cow"),

    fn isBranchTarget(_: *ReferenceProbe, _: usize) bool {
        return false;
    }
};
const ReferenceCase = enum { ordinary, drop, rebind, duplicate, spill, readonly, planned_release, projection };
fn referenceCase(which: ReferenceCase) bool {
    const ty: typed.Type = @fromBackingInt(@intCast(typed.Type.record_base));
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    const locals = [_]typed.Local{.{ .name = "root", .declaration = span, .ty = ty, .mutable = true }};
    const records = [_]typed.Record{.{ .id = ty, .name = "Record", .declaration = span, .fields = &.{} }};
    var code = [_]bytecode.Instruction{
        .{ .span = span, .op = .{ .ref_local = @fromBackingInt(0) } },
        .{ .span = span, .op = .push_unit },
        .{ .span = span, .op = .pop },
        .{ .span = span, .op = .{ .call = @fromBackingInt(1) } },
        .{ .span = span, .op = .ret },
    };
    switch (which) {
        .drop => code[1].op = .{ .drop_local = @fromBackingInt(0) },
        .rebind => code[2].op = .{ .store_local = @fromBackingInt(0) },
        .duplicate => code[1].op = .{ .ref_local = @fromBackingInt(0) },
        .spill => code[1].op = .{ .store_local = @fromBackingInt(1) },
        .projection => code[1].op = .{ .get_field = 0 },
        else => {},
    }
    const functions = [_]bytecode.Function{
        .{ .id = @fromBackingInt(0), .name = "caller", .scope = .{ .locals = &locals, .instructions = &code } },
        .{ .id = @fromBackingInt(1), .name = "callee", .signature = .{ .parameter_count = 1, .declared_mutates = if (which == .readonly) &.{} else &.{0} }, .scope = .{ .locals = &locals, .instructions = code[4..] } },
    };
    const states = [_]?[]const typed.Type{ &.{}, &.{ty}, &.{ ty, .unit }, &.{ty}, &.{} };
    const operands = [_]?[]const sources.Source{ null, null, null, &.{.{ .origin = .local, .local = 0, .read = 0 }}, null };
    const release = [_]@import("rc_plan.zig").Edge{.{ .from = 0, .to = 1, .releases = &.{.{ .storage = @fromBackingInt(0), .guard = @fromBackingInt(0) }} }};
    var probe: ReferenceProbe = .{
        .function = functions[0],
        .program = .{ .functions = &functions, .records = &records },
        .states = &states,
        .ownership = .{ .operands = &operands },
        .cow = .{ .rc = .{ .plan = .{ .locals = .{ .edges = if (which == .planned_release) &release else &.{} } } } },
    };
    var budget: Budget = .{};
    return reference(ReferenceProbe, &probe, 0, 0, &budget);
}

// spec-case: RC-NAMED-RECORD-WRITE-1
test "RC named record pending references reject release rebind duplicates and escape" {
    try t.expect(referenceCase(.ordinary));
    try t.expect(!referenceCase(.drop));
    try t.expect(!referenceCase(.rebind));
    try t.expect(!referenceCase(.duplicate));
    try t.expect(!referenceCase(.spill));
    try t.expect(!referenceCase(.readonly));
    try t.expect(!referenceCase(.planned_release));
    try t.expect(!referenceCase(.projection));
}
