//! Exact ordinary-source input proof, independent of empty-token lifetimes.
const bytecode = @import("bytecode.zig");
const cow = @import("cow_plan.zig");
const Op = @FieldType(bytecode.Instruction, "op");

/// Prove only that this immediate capture cannot receive a terminal H token.
/// The caller must separately prove the target's complete empty-token lifetime.
pub fn proven(comptime E: type, self: *E, target: usize, at: usize) bool {
    const state = self.cow.?.rc orelse return false;
    if (!canonical(state)) return false;
    const code = self.function.scope.instructions;
    if (code.len > 4096 or at == 0 or at >= code.len) return false;
    const source = pair(E, self, target, at) orelse return false;
    const locals = self.function.scope.locals;
    if (target < self.function.signature.parameter_count or !locals[target].usage.temporary) return false;
    if (source < self.function.signature.parameter_count or locals[source].usage.temporary) return false;
    if (locals[source].origin != .local) return false;
    if (referenced(E, self, target) or referenced(E, self, source)) return false;
    if (!scalarList(E, self, target) or locals[source].ty != locals[target].ty) return false;
    const plan = self.cow.?.plan;
    if (plan.place(source) != null or plan.place(target) != null) return false;
    if (source < plan.aliases.len and plan.aliases[source] != cow.none) return false;
    if (state.plan.locals.entry[source].ownership != .empty) return false;
    if (@backingInt(state.plan.locals.entry[source].storage) != source) return false;
    if (@backingInt(state.plan.locals.entry[target].storage) != target) return false;
    if (cow.iterationOwner(self.function, target)) return false;
    for (at - 1..at + 1) |pc| {
        const site = plan.at(pc);
        if (site.read_captures.len != 0 or site.shares.len != 0) return false;
        for (state.plan.field_transfers) |transfer| if (transfer.projection == pc or transfer.commit == pc) return false;
    }
    const definition = sourceStore(E, self, source, target, at) orelse return false;
    for (code, 0..) |instruction, pc| if (encloses(instruction.op, pc, definition)) return false;
    return true;
}

fn pair(comptime E: type, self: *E, target: usize, at: usize) ?usize {
    const code = self.function.scope.instructions;
    if (self.isBranchTarget(at) or code[at].op != .store_local) return null;
    if (@backingInt(code[at].op.store_local) != target or code[at - 1].op != .load_local) return null;
    const before = self.states[at - 1] orelse return null;
    const after = self.states[at] orelse return null;
    if (before.len != 0 or after.len != 1 or after[0] != self.function.scope.locals[target].ty) return null;
    return @backingInt(code[at - 1].op.load_local);
}

fn referenced(comptime E: type, self: *E, local: usize) bool {
    return self.byReference(local) or self.callerStorage(local);
}

/// Shared scalar-list admission; role and lifetime proofs remain with callers.
pub fn scalarList(comptime E: type, self: *E, local: usize) bool {
    const ty = self.function.scope.locals[local].ty;
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.box or record.collection.kind != .list) return false;
    const element = record.shape.buffer orelse return false;
    if (!self.isScalar(element)) return false;
    const shape = self.cow.?.rc.?.catalog.get(element) catch return false;
    if (shape.counted or shape.unique_drop) return false;
    const width = (self.layout(element) catch return false).size;
    return width == 1 or width == 2 or width == 4 or width == 8;
}

// A canonical named store normalizes O/H/LOAN/raw inputs into O. Exclude every
// other local publisher and any repeated definition, rather than inferring a
// role from the source name or the logical ownership explanation.
fn sourceStore(comptime E: type, self: *E, source: usize, target: usize, at: usize) ?usize {
    var result: ?usize = null;
    for (self.function.scope.instructions, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |id| {
            const local = @backingInt(id);
            if (local == target and pc != at) return null;
            if (local != source) continue;
            if (result != null or pc >= at - 1) return null;
            result = pc;
        },
        .move_local, .ref_local => |id| if (@backingInt(id) == source or @backingInt(id) == target) return null,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == source or @backingInt(id) == target) return null;
        },
        else => {},
    };
    return result;
}

// The PC comparison is supplied by the caller: only a backwards edge can
// repeat a source's canonical publication. Forward branches do not create H.
fn encloses(op: Op, pc: usize, definition: usize) bool {
    return switch (op) {
        .jump, .jump_if_false => |target| target <= definition and definition <= pc,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.target <= definition and definition <= pc) break true;
        } else false,
        .try_result => |propagate| propagate.error_target <= definition and definition <= pc,
        else => false,
    };
}

fn canonical(state: anytype) bool {
    return state.active and !state.readonly and state.contract.result != .borrowed;
}

const Probe = struct { function: bytecode.Function };
const t = @import("std").testing;

// spec-case: RC-NONHELD-CAPTURE-1
test "RC nonheld source writers reject reference pattern move and repeated stores" {
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    var code = [_]bytecode.Instruction{
        .{ .span = span, .op = .push_unit },
        .{ .span = span, .op = .{ .store_local = @fromBackingInt(0) } },
        .{ .span = span, .op = .{ .load_local = @fromBackingInt(0) } },
        .{ .span = span, .op = .{ .store_local = @fromBackingInt(1) } },
        .{ .span = span, .op = .push_unit },
    };
    var probe: Probe = .{ .function = .{ .id = @fromBackingInt(0), .name = "probe", .scope = .{ .instructions = &code } } };
    try t.expectEqual(@as(?usize, 1), sourceStore(Probe, &probe, 0, 1, 3));
    code[4].op = .{ .ref_local = @fromBackingInt(0) };
    try t.expectEqual(@as(?usize, null), sourceStore(Probe, &probe, 0, 1, 3));
    code[4].op = .{ .move_local = @fromBackingInt(1) };
    try t.expectEqual(@as(?usize, null), sourceStore(Probe, &probe, 0, 1, 3));
    code[4].op = .{ .store_local = @fromBackingInt(0) };
    try t.expectEqual(@as(?usize, null), sourceStore(Probe, &probe, 0, 1, 3));
    code[4].op = .{ .switch_variant = .{ .ty = .unit, .arms = &.{.{ .target = 0, .slot = @fromBackingInt(0) }} } };
    try t.expectEqual(@as(?usize, null), sourceStore(Probe, &probe, 0, 1, 3));
}

// spec-case: RC-NONHELD-CAPTURE-1
test "RC nonheld admission refuses borrowed entries and repeated source backedges" {
    const State = struct { active: bool, readonly: bool, contract: struct { result: @import("rc_model.zig").Result } };
    var state: State = .{ .active = true, .readonly = false, .contract = .{ .result = .owned } };
    try t.expect(canonical(state));
    state.readonly = true;
    try t.expect(!canonical(state));
    state.readonly = false;
    state.contract.result = .{ .borrowed = .{ .parameter = 0, .shape_identity = @splat(0), .dependency_identity = @splat(0) } };
    try t.expect(!canonical(state));
    try t.expect(encloses(.{ .jump = 1 }, 8, 2));
    try t.expect(encloses(.{ .jump_if_false = 2 }, 8, 2));
    try t.expect(!encloses(.{ .jump = 3 }, 8, 2));
    try t.expect(!encloses(.{ .jump = 1 }, 8, 9));
    try t.expect(encloses(.{ .switch_variant = .{ .ty = .unit, .arms = &.{.{ .target = 1, .slot = null }} } }, 8, 2));
    try t.expect(encloses(.{ .try_result = .{ .input = .unit, .output = .unit, .error_target = 1 } }, 8, 2));
}
