//! Incoming record lifetime is distinct from a private named home's O token.
const model = @import("rc_model.zig");
const cow = @import("cow_plan.zig");
/// Optional type refusal retains ordinary lowering; allocator failures propagate.
pub const Error = error{ InternalError, OutOfMemory };

/// A canonical inout slot remains anchored by its suspended caller. No count,
/// uniqueness, mutation or escaping-result authority follows from this query.
pub fn incoming(comptime E: type, self: *E, root: usize) Error!bool {
    const state = self.cow.?.rc orelse return false;
    if (root >= self.function.signature.parameter_count or root >= state.contract.parameters.len) return false;
    if (!self.callerStorage(root) or self.borrowsElement(root) or self.moves.resolve(root) != root) return false;
    const entry = state.plan.locals.entry[root];
    if (@backingInt(entry.storage) != root or !matches(root, state.contract.parameters[root], entry.ownership)) return false;
    const local = self.function.scope.locals[root];
    if (local.usage.temporary or !local.ty.isAggregate()) return false;
    const record = self.program.records[local.ty.recordIndex()];
    if (!record.isRecord() or record.managed or record.isCollection()) return false;
    if (!entry.shape.counted or entry.shape.unique_drop) return false;
    const plan = self.cow.?.plan;
    if (plan.place(root) != null or (root < plan.aliases.len and plan.aliases[root] != cow.none)) return false;
    // safe visits every native child and refuses all builtins, including live views.
    return @import("rc_field_authority.zig").safe(&state.catalog, local.ty);
}

fn matches(root: usize, parameter: model.Parameter, authority: model.Ownership) bool {
    if (parameter != .caller_storage or authority != .inout) return false;
    return authority.inout == .parameter and authority.inout.parameter == root;
}

// spec-case: RC-CALLER-FIELD-READ-1
test "RC incoming record anchor requires exact inout parameter not an owner or generic borrow" {
    const t = @import("std").testing;
    try t.expect(matches(2, .caller_storage, .{ .inout = .{ .parameter = 2 } }));
    try t.expect(!matches(2, .read, .{ .inout = .{ .parameter = 2 } }));
    try t.expect(!matches(2, .mutable_payload, .{ .inout = .{ .parameter = 2 } }));
    try t.expect(!matches(2, .caller_storage, .{ .inout = .{ .parameter = 1 } }));
    try t.expect(!matches(2, .caller_storage, .{ .inout = .{ .storage = @fromBackingInt(2) } }));
    try t.expect(!matches(2, .caller_storage, .{ .borrowed = .{ .parameter = 2 } }));
    try t.expect(!matches(2, .caller_storage, .{ .owned = .{ .token = @fromBackingInt(2) } }));
}
