//! Recognize only a generated, fully staged update of the same optional payload.
const std = @import("std");
const language = @import("mylang");
const typed = language.typed;

/// The payload receiver is refreshed after the source RHS and before rebuilding Some.
pub const Shape = struct { receiver: typed.LocalId, payload: typed.NodeId, tag: usize };

fn node(program: typed.Program, id: typed.NodeId) ?typed.Node {
    const index = @backingInt(id);
    return if (index < program.nodes.len) program.nodes[index] else null;
}

fn hidden(function: typed.Function, slot: typed.LocalId, ty: typed.Type) bool {
    const index = @backingInt(slot);
    if (index < function.signature.parameter_count or index >= function.scope.locals.len) return false;
    const local = function.scope.locals[index];
    return local.ty == ty and local.mutable and local.usage.temporary and std.mem.startsWith(u8, local.name, "<");
}

/// Require the exact field path and a previously evaluated RHS, in bounded work.
fn staged(program: typed.Program, function: typed.Function, id: typed.NodeId) bool {
    var current = id;
    for (0..64) |_| {
        const value = node(program, current) orelse return false;
        if (value.data != .update or value.data.update.fields.len != 1) return false;
        const update = value.data.update;
        const field = update.fields[0];
        const parent = node(program, update.base) orelse return false;
        if (parent.ty != value.ty or !value.ty.isAggregate() or value.ty.recordIndex() >= program.records.len) return false;
        const fields = program.records[value.ty.recordIndex()].fields;
        if (field.index >= fields.len) return false;
        const rhs = node(program, field.value) orelse return false;
        if (rhs.ty != fields[field.index].ty) return false;
        if (rhs.data == .local) return hidden(function, rhs.data.local, rhs.ty);
        if (rhs.data != .update) return false;
        const base = node(program, rhs.data.update.base) orelse return false;
        if (base.data != .field or base.data.field.base != update.base or base.data.field.index != field.index) return false;
        current = field.value;
    }
    return false;
}

/// Ordinary variants, arbitrary payload moves and un-staged effects do not match.
pub fn shape(program: typed.Program, function: typed.Function, store: typed.Store) ?Shape {
    if (store.element or store.unpack != null or @backingInt(store.slot) >= function.scope.locals.len) return null;
    const destination = function.scope.locals[@backingInt(store.slot)];
    if (!destination.mutable) return null;
    if (!destination.ty.isAggregate() or destination.ty.recordIndex() >= program.records.len) return null;
    const option = language.reference_tables.prelude.optionShape(destination.ty, program.records) orelse return null;
    const value = node(program, store.value) orelse return null;
    if (value.ty != destination.ty or value.data != .variant or value.data.variant.tag != option.some) return null;
    const payload = value.data.variant.value orelse return null;
    const updated = node(program, payload) orelse return null;
    if (updated.ty != option.element or updated.data != .update or !staged(program, function, payload)) return null;
    const base = node(program, updated.data.update.base) orelse return null;
    if (base.ty != option.element or base.data != .local or !hidden(function, base.data.local, option.element)) return null;
    return .{ .receiver = base.data.local, .payload = payload, .tag = option.some };
}

fn statement(program: typed.Program, id: typed.StatementId) ?typed.Statement {
    const index = @backingInt(id);
    return if (index < program.statements.len) program.statements[index] else null;
}

fn empty(program: typed.Program, id: typed.StatementId) bool {
    const body = statement(program, id) orelse return false;
    return body.data == .block and body.data.block.len == 0;
}

fn trapped(program: typed.Program, id: typed.StatementId) bool {
    const body = statement(program, id) orelse return false;
    if (body.data != .assertion) return false;
    const condition = node(program, body.data.assertion.condition) orelse return false;
    return condition.data == .boolean and !condition.data.boolean;
}

/// Validate the exact defensive narrowing block recorded for the hidden receiver.
pub fn projection(program: typed.Program, function: typed.Function, store: typed.Store, found: Shape, definition: typed.NodeId) bool {
    const value = node(program, definition) orelse return false;
    if (value.data != .block_value or value.ty != function.scope.locals[@backingInt(found.receiver)].ty) return false;
    const block = value.data.block_value;
    const result = node(program, block.value) orelse return false;
    if (result.ty != value.ty or result.data != .local or !hidden(function, result.data.local, value.ty)) return false;
    const body = statement(program, block.body) orelse return false;
    if (body.data != .block or body.data.block.len != 1) return false;
    const dispatch = statement(program, body.data.block[0]) orelse return false;
    if (dispatch.data != .match or dispatch.data.match.arms.len != 2) return false;
    const match = dispatch.data.match;
    const root = node(program, match.value) orelse return false;
    if (match.borrowed or root.data != .local or root.data.local != store.slot or root.ty != function.scope.locals[@backingInt(store.slot)].ty) return false;
    const option = language.reference_tables.prelude.optionShape(root.ty, program.records) orelse return false;
    if (option.element != value.ty or option.some != found.tag) return false;
    var seen: u2 = 0;
    for (match.arms) |arm| {
        if (arm.unpack != null) return false;
        if (arm.tag == option.some and arm.slot == result.data.local and empty(program, arm.body)) {
            seen |= 1;
        } else if (arm.tag == option.none and arm.slot == null and trapped(program, arm.body)) {
            seen |= 2;
        } else return false;
    }
    return seen == 3;
}
