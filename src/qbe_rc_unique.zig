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
    const ty = self.function.scope.locals[unique.local].ty;
    const address = self.temp();
    const guard = try frame.guard(E, self, unique.local);
    const done = self.temp();
    try self.print(" %v{d} =l copy %l{d}\n", .{ address, unique.local });
    try self.print(" %v{d} =w call $myl_qbe_rc_unique_local(l %ctx, l extern ${s}, l %v{d}, l %v{d})\n", .{ done, try self.descriptor(ty), address, guard });
    try success(E, self, done);
    if (unique.alias != cow.none) {
        const value = try self.load("l", unique.local);
        try frame.drop(E, self, unique.alias);
        try self.print(" storel %v{d}, %l{d}\n", .{ value, unique.alias });
    }
}

/// One pointer edge in an already-owned containing value.
pub const Field = struct { ty: @import("typed.zig").Type, address: usize, container: ?usize = null };

/// Detach an owned field transactionally before publishing the replacement edge.
pub fn field(comptime E: type, self: *E, target: Field) Error!void {
    const container = self.temp();
    if (target.container) |value| {
        try self.print(" %v{d} =l copy %v{d}\n", .{ container, value });
    } else try self.print(" %v{d} =l copy 0\n", .{container});
    const done = self.temp();
    try self.print(" %v{d} =w call $myl_qbe_rc_unique_field(l %ctx, l extern ${s}, l %v{d}, l %v{d})\n", .{ done, try self.descriptor(target.ty), target.address, container });
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
