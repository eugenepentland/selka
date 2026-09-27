//! Exact plain-field storeback without copying an owning record's siblings.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const shapes = @import("rc_shape.zig");
const plans = @import("rc_plan.zig");
const cow_plan = @import("cow_plan.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// The complete inert tail; update and commit are start + 6 and start + 7.
pub const Certificate = struct { root: usize, capture: usize, value: usize, field: usize, start: usize, home: enum { caller, local } = .caller };
/// Optional refusal preserves general lowering; allocation failures propagate.
pub const Error = error{ InternalError, OutOfMemory };

/// Certify initialized caller slots whose whole capture lifetime never owns.
pub fn build(comptime E: type, self: *E, catalog: *shapes.Catalog, plan: plans.Plan) Error![]const Certificate {
    const code = self.function.scope.instructions;
    if (code.len > 4096 or self.function.policy.c_abi or self.function.policy.host != null) return &.{};
    var found: std.ArrayList(Certificate) = .empty;
    var remaining: usize = 262144;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .update_record or pc < 7 or pc + 1 >= code.len) continue;
        const proof = try tail(E, self, pc - 6, catalog, false) orelse continue;
        if (code.len > remaining) break;
        remaining -= code.len;
        if (!captureUses(E, self, proof) or !try quiet(E, self, proof, catalog, plan)) continue;
        try found.append(self.allocator, proof);
    }
    return found.toOwnedSlice(self.allocator);
}

/// Extend only canonical emission after loop, storage and alternate facts settle.
pub fn named(comptime E: type, self: *E) Error!void {
    const state = self.cow.?.rc orelse return;
    if (!state.active or state.readonly or state.contract.result == .borrowed) return;
    const code = self.function.scope.instructions;
    if (code.len > 4096 or self.function.policy.c_abi or self.function.policy.host != null) return;
    const homes = @import("rc_record_home.zig");
    var budget: homes.Budget = .{};
    const Cached = struct { root: usize, facts: ?[]const u8 };
    var cache: std.ArrayList(Cached) = .empty;
    var found: std.ArrayList(Certificate) = .empty;
    try found.appendSlice(self.allocator, state.plan.records.writes);
    var remaining: usize = 262144;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .update_record or pc < 7 or pc + 1 >= code.len) continue;
        const proof = try tail(E, self, pc - 6, &state.catalog, true) orelse continue;
        if (code.len > remaining) break;
        remaining -= code.len;
        if (!captureUses(E, self, proof) or !try quiet(E, self, proof, &state.catalog, state.plan.locals)) continue;
        const facts = cached: {
            for (cache.items) |entry| if (entry.root == proof.root) break :cached entry.facts;
            const facts = try homes.analyze(E, self, proof.root, &budget);
            try cache.append(self.allocator, .{ .root = proof.root, .facts = facts });
            break :cached facts;
        };
        if (facts) |rows| if (rows[proof.start] == homes.owned) try found.append(self.allocator, proof);
    }
    state.plan.records.writes = try found.toOwnedSlice(self.allocator);
}

fn tail(comptime E: type, self: *E, start: usize, catalog: *shapes.Catalog, named_home: bool) Error!?Certificate {
    const code = self.function.scope.instructions;
    const ops = code[start..][0..8];
    if (ops[0].op != .load_local or ops[1].op != .store_local or ops[5].op != .load_local) return null;
    const root = @backingInt(ops[0].op.load_local);
    const capture = @backingInt(ops[1].op.store_local);
    const value = @backingInt(ops[5].op.load_local);
    if (root == capture or root == value or capture == value) return null;
    if (!localIs(ops[2].op, .load_local, root) or !localIs(ops[3].op, .store_local, capture)) return null;
    if (!localIs(ops[4].op, .load_local, capture) or !localIs(ops[7].op, .store_local, root)) return null;
    if (!localIs(code[start - 1].op, .store_local, value)) return null;
    const update = ops[6].op.update_record;
    if (update.indices.len != 1 or self.callerStorage(root) == named_home or self.moves.resolve(root) != root) return null;
    const locals = self.function.scope.locals;
    const ty = locals[root].ty;
    if (ty != update.ty or locals[capture].ty != ty or !ty.isAggregate()) return null;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isRecord() or record.managed or record.isCollection()) return null;
    if ((try shape(catalog, ty)).unique_drop or @import("value_semantics.zig").containsLiveView(self.program.records, ty)) return null;
    if (capture < self.function.signature.parameter_count or !locals[capture].usage.temporary) return null;
    if (self.byReference(capture) or self.callerStorage(capture) or self.moves.resolve(capture) != capture) return null;
    if (self.byReference(value) or self.callerStorage(value) or self.moves.resolve(value) != value) return null;
    const layout = catalog.native.layout(ty) catch return error.InternalError;
    if (update.indices[0] >= layout.fields.len) return null;
    const member = layout.fields[update.indices[0]];
    if (member.ty != locals[value].ty or !try scalar(catalog, member.ty)) return null;
    const heights = [_]usize{ 0, 1, 0, 1, 0, 1, 2, 1 };
    for (ops, heights, start..) |instruction, height, pc| {
        const stack = self.states[pc] orelse return null;
        if (stack.len != height or instruction.inline_origin != null) return null;
        if (pc != start and self.isBranchTarget(pc)) return null;
    }
    if (self.live.?.after(start + 7, capture)) return null;
    return .{ .root = root, .capture = capture, .value = value, .field = update.indices[0], .start = start, .home = if (named_home) .local else .caller };
}

// The capture starts empty at function entry, and only these two suppressed
// stores can define it. The one read never escapes. Backedges preserve emptiness.
fn captureUses(comptime E: type, self: *E, proof: Certificate) bool {
    const plan = self.cow.?.plan;
    if (plan.place(proof.capture) != null) return false;
    if (proof.capture < plan.aliases.len and plan.aliases[proof.capture] != cow_plan.none) return false;
    for (self.function.scope.instructions, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |id| if (@backingInt(id) == proof.capture and pc != proof.start + 1 and pc != proof.start + 3) return false,
        .load_local => |id| if (@backingInt(id) == proof.capture and pc != proof.start + 4) return false,
        .move_local, .ref_local => |id| if (@backingInt(id) == proof.capture) return false,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == proof.capture) return false;
        },
        .buffer_operation => |operation| if (@backingInt(operation.owner) == proof.capture) return false,
        else => {},
    };
    return writers(plan, proof.capture);
}

fn writers(plan: cow_plan.Plan, capture: usize) bool {
    for (plan.sites) |site| {
        for (site.unique) |unique| if (unique.local == capture or unique.alias == capture) return false;
        if (site.unique_field) |place| if (place.parent == capture) return false;
    }
    for (plan.loops.entries) |entries| for (entries) |entry| if (entry.local == capture) return false;
    for (plan.aliases) |parent| if (parent == capture) return false;
    for (plan.places) |maybe| if (maybe) |place| {
        if (place.parent == capture) return false;
        if (place.box) |box| if (box.owner == capture) return false;
    };
    return true;
}

fn quiet(comptime E: type, self: *E, proof: Certificate, catalog: *shapes.Catalog, plan: plans.Plan) Error!bool {
    const cow = self.cow.?;
    const none = cow_plan.none;
    for (proof.start..proof.start + 8) |pc| {
        const site = cow.plan.at(pc);
        if (site.unique.len != 0 or site.unique_field != null or site.fill or site.capture) return false;
        if (site.shares.len != 0 or site.read_captures.len != 0 or cow.plan.entry(pc).len != 0) return false;
        if (cow.captures[pc].begin != none or cow.captures[pc].active != none) return false;
        for (plan.edges) |edge| {
            if (edge.from != pc or edge.to != pc + 1) continue;
            for (edge.releases) |release| {
                const index = @backingInt(release.storage);
                const local = self.function.scope.locals[index];
                if (!local.usage.temporary or index < self.function.signature.parameter_count) continue;
                if (self.byReference(index) or self.callerStorage(index) or !self.isScalar(local.ty)) continue;
                if ((try shape(catalog, local.ty)).counted) return false;
            }
        }
    }
    const analysis = self.ownership orelse return false;
    for (self.function.scope.locals, 0..) |local, index| {
        if (index == proof.root or index == proof.capture or !self.live.?.before(proof.start, index)) continue;
        if (!(try shape(catalog, local.ty)).counted) continue;
        if (analysis.rootOf(@intCast(index)) == proof.root) return false;
    }
    return true;
}

fn localIs(op: Op, comptime tag: std.meta.Tag(Op), index: usize) bool {
    return op == tag and @backingInt(@field(op, @tagName(tag))) == index;
}
fn scalar(catalog: *shapes.Catalog, ty: typed.Type) Error!bool {
    if (!ty.isInteger() and ty != .bool) return false;
    const value = try shape(catalog, ty);
    return !value.counted and !value.unique_drop and (catalog.native.layout(ty) catch return error.InternalError).size != 0;
}
fn shape(catalog: *shapes.Catalog, ty: typed.Type) Error!shapes.Shape {
    return catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
