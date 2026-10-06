//! Everyday list composition through existing value-functional updates.
const ir = @import("ir.zig");
const typed = @import("mylang").typed;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");

/// Allocation and precise feature refusals are the list builder's failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Extend evaluates its argument before refreshing the writable receiver place.
pub fn operation(comptime Context: type, b: Context, node: Operation, span: u32) Error!ir.Ref {
    if (node.kind == .extend) {
        const other = try b.expression(node.arguments[0]);
        if (b.current == null) return .none;
        const receiver = try b.writableReceiverOf(node.owner, span);
        try b.writeOwner(node.owner, try extend(Context, b, receiver, other, span), span);
    } else {
        const receiver = try b.writableReceiverOf(node.owner, span);
        const empty = try b.emit(.{ .op = .list_new, .ty = b.typeOfRef(receiver), .a = try b.emit(.{ .op = .list_len, .ty = .u64, .a = receiver, .span = span }), .span = span });
        try b.writeOwner(node.owner, try compose(Context, b, empty, receiver, true, span), span);
    }
    return .none;
}

/// Append each source element once, preserving shared/self-extension snapshots.
pub fn extend(comptime Context: type, b: Context, target: ir.Ref, source: ir.Ref, span: u32) Error!ir.Ref {
    return compose(Context, b, target, source, false, span);
}

fn compose(comptime Context: type, b: Context, target: ir.Ref, source: ir.Ref, reverse: bool, span: u32) Error!ir.Ref {
    const ty = b.typeOfRef(target);
    const element = b.module().compound(ty).list;
    const length = try b.emit(.{ .op = .list_len, .ty = .u64, .a = source, .span = span });
    const list_slot = try b.synthetic(ty);
    const index_slot = try b.synthetic(.u64);
    try b.write(list_slot, b.current.?, target);
    try b.write(index_slot, b.current.?, try b.constant(.u64, 0));
    const header = try b.newBlock();
    const body = try b.newBlock();
    const exit = try b.newBlock();
    try b.jump(header);
    b.enter(header);
    const index = try b.read(index_slot, header);
    const more = try b.emit(.{ .op = .cmp, .ty = .bool, .a = index, .b = length, .data = @backingInt(ir.Predicate.lt), .span = span });
    try b.branch(more, body, exit, span);
    try b.seal(body);
    b.enter(body);
    const selected = if (reverse) try b.emit(.{ .op = .sub, .ty = .u64, .a = try b.emit(.{ .op = .sub, .ty = .u64, .a = length, .b = try b.constant(.u64, 1), .span = span }), .b = index, .span = span }) else index;
    const value = if (element == .void) try b.emit(.{ .op = .undef, .ty = .void }) else try b.emit(.{ .op = .list_get, .ty = element, .a = source, .b = selected, .check = .exact, .span = span });
    const pushed = try b.emit(.{ .op = .list_push, .ty = ty, .a = try b.read(list_slot, body), .b = value, .span = span });
    try b.write(list_slot, body, pushed);
    try b.write(index_slot, body, try b.emit(.{ .op = .add, .ty = .u64, .a = index, .b = try b.constant(.u64, 1), .span = span }));
    try b.jump(header);
    try b.seal(header);
    try b.seal(exit);
    b.enter(exit);
    return b.read(list_slot, exit);
}
