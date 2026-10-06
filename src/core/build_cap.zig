//! S3-C owns capability/resource admission and exact effect lowering.
const ir = @import("ir.zig");
const typed = @import("mylang").typed;

/// Preserve precise located refusals until the capability runtime is implemented.
pub fn expression(context: anytype, node: typed.Node, span: u32) error{ OutOfMemory, Unsupported }!ir.Ref {
    return context.mb.refuse(@tagName(node.data), span);
}
