//! Typed owner-count uniqueness checks for the experimental RC emitter.
const ownership = @import("ownership.zig");
const cow = @import("cow_plan.zig");
const frame = @import("qbe_rc_frame.zig");
const runtime = @import("runtime_mode.zig");
/// Native emitter failures.
pub const Error = frame.Error;

/// Keep checks at their original instructions until physical publication has
/// its own loop proof; semantic COW hoisting does not count temporary owners.
pub fn analysis(comptime E: type, self: *E) Error!ownership.Analysis {
    var result = self.ownership orelse return error.InternalError;
    if (!runtime.enabled()) return result;
    const checks = try self.allocator.dupe(ownership.Cow, result.cows);
    for (checks) |*check| check.hoisted = cow.none;
    result.cows = checks;
    return result;
}

/// Make one guarded local unique, preserving a borrowed caller's owning edge.
/// The helper sets the guard only when a borrowed input acquired a fresh clone.
pub fn local(comptime E: type, self: *E, unique: cow.Unique) Error!void {
    if (unique.alias != cow.none and receiverFilled(E, self, unique.alias)) {
        return local(E, self, .{ .local = unique.alias });
    }
    const address = self.temp();
    const guard = try frame.guard(E, self, unique.local);
    try self.print(" %v{d} =l copy %l{d}\n", .{ address, unique.local });
    try localCall(E, self, unique.local, address, guard);
    if (unique.alias != cow.none) {
        const value = try self.load("l", unique.local);
        try frame.drop(E, self, unique.alias);
        try self.print(" storel %v{d}, %l{d}\n", .{ value, unique.alias });
    }
}

fn localCall(comptime E: type, self: *E, index: usize, address: usize, guard: usize) Error!void {
    if (stableMutParameter(E, self, index) or @import("qbe_rc_hoist.zig").covers(E, self, index)) return;
    const ty = self.function.scope.locals[index].ty;
    const holds = @import("qbe_rc_holds.zig");
    const label = self.temp();
    const maybe_held = self.function.scope.locals[index].usage.temporary and holds.mayHold(E, self, ty);
    if (maybe_held) {
        const held = try holds.held(E, self, index);
        try self.print(" jnz %v{d}, @rcuniqueheld{d}, @rcuniqueowner{d}\n@rcuniqueheld{d}\n", .{ held, label, label, label });
        try field(E, self, .{ .ty = ty, .address = address, .held = true });
        try self.print(" jmp @rcuniquelocal{d}\n@rcuniqueowner{d}\n", .{ label, label });
    }
    const done = self.temp();
    try self.print(" %v{d} =w call $myl_qbe_rc_unique_local(l %ctx, l extern ${s}, l %v{d}, l %v{d})\n", .{ done, try self.descriptor(ty), address, guard });
    try success(E, self, done);
    if (maybe_held) try self.print("@rcuniquelocal{d}\n", .{label});
}

// The caller already detached and pinned this exact payload for the complete
// activation. Pin-aware publications cannot introduce a second snapshot owner.
// A source-level rebind instead installs an ordinary value in the parameter
// slot, so any instruction that can replace that slot declines this shortcut.
fn stableMutParameter(comptime E: type, self: *E, index: usize) bool {
    const state = frame.get(E, self) orelse return false;
    if (index >= state.contract.parameters.len or state.contract.parameters[index] != .mutable_payload) return false;
    const ty = self.function.scope.locals[index].ty;
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.kind != .list or record.collection.box) return false;
    const shape = state.catalog.get(record.shape.buffer orelse return false) catch return false;
    if (shape.counted or shape.unique_drop) return false;
    return ownership.uniqueParameter(self.function, index);
}

/// One ordinary or held pointer edge in an already-owned containing value.
pub const Field = struct { ty: @import("typed.zig").Type, address: usize, container: ?usize = null, held: bool = false };

/// Detach an ordinary or held field without changing its ownership role.
pub fn field(comptime E: type, self: *E, target: Field) Error!void {
    const container = self.temp();
    if (target.container) |value| {
        try self.print(" %v{d} =l copy %v{d}\n", .{ container, value });
    } else try self.print(" %v{d} =l copy 0\n", .{container});
    const done = self.temp();
    const helper: []const u8 = if (target.held) "myl_qbe_rc_unique_held" else "myl_qbe_rc_unique_field";
    try self.print(" %v{d} =w call ${s}(l %ctx, l extern ${s}, l %v{d}, l %v{d})\n", .{ done, helper, try self.descriptor(target.ty), target.address, container });
    try success(E, self, done);
}

/// A compiler-only receiver temporary aliases its prepared owning parent.
/// User bindings and read-only compiler temporaries still establish snapshots.
pub fn receiverParent(comptime E: type, self: *E, index: usize) ?u32 {
    const plan = self.cow.?.plan;
    if (index >= plan.aliases.len or plan.aliases[index] == cow.none) return null;
    for (self.function.scope.instructions) |instruction| {
        const operation = switch (instruction.op) {
            .buffer_operation => |operation| operation,
            else => continue,
        };
        if (!operation.kind.writesReceiver() and operation.kind != .set_add and operation.kind != .set_discard) continue;
        var at: usize = @backingInt(operation.owner);
        var remaining = plan.aliases.len;
        while (remaining != 0) : (remaining -= 1) {
            if (at == index) return plan.aliases[index];
            if (plan.place(at)) |place| {
                at = place.parent;
            } else if (at < plan.aliases.len and plan.aliases[at] != cow.none) {
                at = plan.aliases[at];
            } else break;
        }
    }
    return null;
}

/// Runtime bridges already map their exact failure status to the active frame.
pub fn success(comptime E: type, self: *E, done: usize) Error!void {
    const label = self.temp();
    try self.print(" jnz %v{d}, @rcunique{d}, @failure\n@rcunique{d}\n", .{ done, label, label });
}

fn receiverFilled(comptime E: type, self: *E, index: usize) bool {
    if (receiverParent(E, self, index) == null) return false;
    for (self.function.scope.instructions[0..self.pc]) |instruction| {
        if (instruction.op == .store_local and @backingInt(instruction.op.store_local) == index) return true;
    }
    return false;
}
