//! A retained list can anchor an adjacent ordinary variant dispatch.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
const cow = @import("cow_plan.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// Errors shared by physical operand publication.
pub const Error = values.Error;

/// Keep the checked interior address only while its concrete list token lives.
/// The ordinary switch still retains the selected payload before old-arm cleanup.
pub fn after(comptime E: type, self: *E, op: Op, stack: []const typed.Type) Error!bool {
    const owner = try admitted(E, self, op, stack) orelse return false;
    const label = self.temp();
    const live = self.temp();
    const flags = self.temp();
    const ordinary = self.temp();
    const loan = self.temp();
    const empty = self.temp();
    const ready = self.temp();
    try self.print(" # RC-ADJACENT-VARIANT-READ-1 owner {d} switch {d}\n", .{ owner, self.pc + 1 });
    try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w loaduw %v{d}\n", .{
        live, try frame.guard(E, self, owner), flags, try frame.entryField(E, self, owner, 24),
    });
    // O and private LOAN16 both keep the list header and its logical edges live.
    // Terminal H/unique/construction roles and a dirty operand use old lowering.
    try self.print(" %v{d} =w ceqw %v{d}, 2\n %v{d} =w ceqw %v{d}, 16\n %v{d} =w or %v{d}, %v{d}\n", .{ ordinary, flags, loan, flags, ordinary, ordinary, loan });
    try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w ceqw %v{d}, 0\n", .{
        empty, try frame.guard(E, self, values.journalIndex(E, self, 0)), empty, empty,
    });
    try self.print(" %v{d} =w and %v{d}, %v{d}\n %v{d} =w and %v{d}, %v{d}\n jnz %v{d}, @rcvariantdone{d}, @rcvariantslow{d}\n@rcvariantslow{d}\n", .{
        ready, live, ordinary, ready, ready, empty, ready, label, label, label,
    });
    try values.finish(E, self, .{ .ty = op.buffer_operation.output, .base = 0, .consumed = 1, .origin = .borrowed });
    try self.print("@rcvariantdone{d}\n", .{label});
    return true;
}

fn admitted(comptime E: type, self: *E, op: Op, stack: []const typed.Type) Error!?usize {
    if (op != .buffer_operation or op.buffer_operation.kind != .read) return null;
    const code = self.function.scope.instructions;
    if (code.len > 4096 or self.pc + 1 >= code.len) return null;
    if (stack.len != 1 or !stack[0].isInteger()) return null;
    if (!immediate(code, self.pc, self.isBranchTarget(self.pc + 1))) return null;
    const next = code[self.pc + 1];
    const dispatch = next.op.switch_variant;
    const ty = op.buffer_operation.output;
    if (ty != dispatch.ty or !ty.isAggregate() or self.isScalar(ty)) return null;
    const after_read = self.states[self.pc + 1] orelse return null;
    if (after_read.len != 1 or after_read[0] != ty) return null;
    const record = self.program.records[ty.recordIndex()];
    if (record.managed or record.shape.variants == null) return null;
    const state = frame.get(E, self) orelse return null;
    // This also excludes old arm-local finalizers: every arm local has its
    // exact payload type, and no reachable resource/opaque/callable is admitted.
    if (!try @import("rc_field_authority.zig").safe(&state.catalog, ty)) return null;
    for (dispatch.arms) |arm| if (arm.slot) |id| {
        const local = @backingInt(id);
        if (self.byReference(local) or self.callerStorage(local) or state.plan.journal.emptyLocal(local)) return null;
    };
    const owner = @backingInt(op.buffer_operation.owner);
    if (!concrete(E, self, owner) or !inertIndex(self.function.scope.instructions, owner, self.pc)) return null;
    for (self.pc..self.pc + 2) |pc| if (!quiet(E, self, pc)) return null;
    return owner;
}

fn immediate(code: []const bytecode.Instruction, read: usize, entered: bool) bool {
    if (entered or read >= code.len or read + 1 >= code.len) return false;
    if (code[read].op != .buffer_operation or code[read].op.buffer_operation.kind != .read) return false;
    const next = code[read + 1].op;
    return next == .switch_variant and !next.switch_variant.borrowed;
}

// Keep index callbacks/scopes outside this first certificate. The last exact
// capture store must precede at most 64 scalar/read normalization operations.
fn inertIndex(code: []const bytecode.Instruction, owner: usize, read: usize) bool {
    var pc = read;
    var remaining: usize = 64;
    while (pc != 0 and remaining != 0) {
        pc -= 1;
        remaining -= 1;
        switch (code[pc].op) {
            .store_local => |id| if (@backingInt(id) == owner) return true,
            .load_local,
            .get_field,
            .push_i64,
            .push_integer,
            .push_bool,
            .cast_integer,
            .cmp_i64,
            .cmp_bool,
            .add_i64_checked,
            .sub_i64_checked,
            .mul_i64_checked,
            .jump,
            .jump_if_false,
            .buffer_operation,
            => if (code[pc].op == .buffer_operation and code[pc].op.buffer_operation.kind != .length) return false,
            else => return false,
        }
    }
    return false;
}

fn concrete(comptime E: type, self: *E, owner: usize) bool {
    const state = frame.get(E, self).?;
    if (owner < self.function.signature.parameter_count or self.byReference(owner) or self.callerStorage(owner)) return false;
    if (self.moves.resolve(owner) != owner or frame.emptyLocal(E, self, owner)) return false;
    const ty = self.function.scope.locals[owner].ty;
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.kind != .list or record.collection.box) return false;
    if (self.cow.?.plan.place(owner) != null or @import("qbe_rc_receivers.zig").receiverParent(E, self, owner) != null) return false;
    const role = state.plan.locals.entry[owner].ownership;
    return role != .borrowed and !cow.iterationOwner(self.function, owner);
}

fn quiet(comptime E: type, self: *E, pc: usize) bool {
    const state = self.cow.?;
    const site = state.plan.at(pc);
    if (site.capture or site.fill or site.unique_field != null or site.unique.len != 0) return false;
    if (site.shares.len != 0 or site.read_captures.len != 0 or state.plan.entry(pc).len != 0) return false;
    if (state.captures[pc].begin != cow.none or state.captures[pc].active != cow.none) return false;
    if (self.function.scope.instructions[pc].inline_origin != null) return false;
    return @import("qbe_rc_edges.zig").boundaryQuiet(self.function.scope.instructions[pc].op);
}

const t = @import("std").testing;
// spec-case: RC-ADJACENT-VARIANT-READ-1
test "RC adjacent variant boundary rejects external entry borrowed arms and gaps" {
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    var code = [_]bytecode.Instruction{
        .{ .span = span, .op = .{ .buffer_operation = .{ .kind = .read, .owner = @fromBackingInt(0), .output = .unit } } },
        .{ .span = span, .op = .{ .switch_variant = .{ .ty = .unit, .arms = &.{} } } },
    };
    try t.expect(immediate(&code, 0, false));
    try t.expect(!immediate(&code, 0, true));
    code[1].op.switch_variant.borrowed = true;
    try t.expect(!immediate(&code, 0, false));
    code[1].op = .push_unit;
    try t.expect(!immediate(&code, 0, false));
    try t.expect(!immediate(&code, 1, false));
    try t.expect(!immediate(&code, code.len, false));
}

// spec-case: RC-ADJACENT-VARIANT-READ-1
test "RC adjacent variant index scan is bounded and refuses callback effects" {
    const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    var code: [65]bytecode.Instruction = @splat(.{ .span = span, .op = .{ .push_i64 = 0 } });
    code[0].op = .{ .store_local = @fromBackingInt(3) };
    try t.expect(inertIndex(&code, 3, 64));
    try t.expect(!inertIndex(&code, 3, 65));
    code[1].op = .{ .call = @fromBackingInt(0) };
    try t.expect(!inertIndex(&code, 3, 64));
    try t.expect(@import("qbe_rc_edges.zig").boundaryQuiet(.push_unit));
    try t.expect(!@import("qbe_rc_edges.zig").boundaryQuiet(.{ .store_local = @fromBackingInt(3) }));
}
