//! Number conversions share the accepted text layout and frozen parse operation.
const ir = @import("ir.zig");
const typed = @import("mylang").typed;
const Operation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");

/// Allocation and precise feature refusals are the number builder's failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Lower int(text) without introducing an operation or changing its Option result.
pub fn operation(comptime Context: type, context: Context, node: Operation, ty: ir.Type, span: u32) Error!ir.Ref {
    if (node.kind != .parse_int) return context.mb.refuse("number text operation", span);
    const receiver = try context.receiverOf(node.owner);
    if (context.typeOfRef(receiver) != .str) return context.mb.refuse("parse_int receiver", span);
    return context.emit(.{ .op = .str_parse_int, .ty = ty, .a = receiver, .span = span });
}
