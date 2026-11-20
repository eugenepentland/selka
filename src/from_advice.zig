//! What the function alone allows of a result declared `from` one of its parameters, as the ownership check and the
//! declaration authority judge it: which other returns may stand beside a borrowed one (`constant`), and whether the
//! parameter can lend the result (`lends`). The `W_COPY_MOVE` "every return" hint (`needless_copy.zig`) names the `from`
//! form only where both hold, and `W_COPY_RETURNED` (`copy_from_repair.zig`) repairs with it; a single module answers both.
const std = @import("std");
const return_borrow = @import("return_borrow.zig");
const typed = @import("typed.zig");

/// Whether a returned value is a constant the ownership check lets stand beside a borrowed return (its `staticValue`
/// classification of a return): a number, a bool, a unit, a byte blob, a text or bytes literal, a case with no payload
/// (`None`) or the empty list literal `[]`. Any other new value beside a borrow is `E_BORROW_MIXED`.
pub fn constant(program: typed.Program, id: typed.NodeId) bool {
    if (emptyListLiteral(program, id)) return true;
    const node = program.nodes[@backingInt(id)];
    return switch (node.data) {
        .integer, .boolean, .unit, .blob => true,
        .array => constantText(program, node.ty),
        .variant => |variant| variant.value == null,
        else => false,
    };
}

/// Whether a checked value is the empty list literal `[]`: the block that initializes a list temporary with no capacity and
/// reads it back (Core's `single_owner.emptyListLiteral`, which the front end cannot import).
fn emptyListLiteral(program: typed.Program, id: typed.NodeId) bool {
    const node = program.nodes[@backingInt(id)];
    if (node.data != .block_value) return false;
    const read = program.nodes[@backingInt(node.data.block_value.value)];
    const body = program.statements[@backingInt(node.data.block_value.body)];
    if (read.data != .local or body.data != .block or body.data.block.len != 1) return false;
    const init = program.statements[@backingInt(body.data.block[0])];
    if (init.data != .initialize or init.data.initialize.slot != read.data.local) return false;
    const value = program.nodes[@backingInt(init.data.initialize.value)];
    if (value.data != .acquire_buffer) return false;
    const capacity = program.nodes[@backingInt(value.data.acquire_buffer.capacity)];
    return capacity.data == .integer and capacity.data.integer == 0;
}

/// Whether `ty` is text or bytes, whose array node is a literal.
fn constantText(program: typed.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const kind = program.records[ty.recordIndex()].collection.kind;
    return kind == .string or kind == .bytes;
}

/// Whether parameter `parameter` can be the result's `from` source, as the declaration authority judges a written clause
/// (`core/borrow_contract.zig`): it lends the result's leaf (a plain text or bytes parameter lends only text or bytes of its
/// own kind, `E_BORROW_SOURCE`), and it is not a `mut` parameter of a function that fails with a managed error, which Core
/// cannot declare yet (`E_CORE_UNSUPPORTED`, rule Z3). Where it is not, the `from` hint is false whatever the callers do.
pub fn lends(program: typed.Program, function: typed.Function, parameter: usize) bool {
    if (parameter >= function.signature.parameter_count or parameter >= function.scope.locals.len) return false;
    const at: u16 = std.math.cast(u16, parameter) orelse return false;
    const mutable = function.scope.locals[parameter].mutable;
    if (mutable) if (typed.resultShape(function.signature.return_type, program.records)) |result| {
        if (return_borrow.managed(program.records, result.error_type)) return false;
    };
    var declared = function.signature;
    declared.return_origin = .{ .params = &.{at} };
    const leaf = return_borrow.shape(program.records, declared);
    if (leaf.kind == .none) return false;
    return return_borrow.sourceLends(program.records, mutable, function.scope.locals[parameter].ty, leaf);
}
