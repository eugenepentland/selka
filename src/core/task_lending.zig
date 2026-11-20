//! Shared classification of task arguments that lend an existing place.
const typed = @import("selka").typed;

/// A local or its projection is lent; freshly evaluated values belong to the
/// task environment. Checking and lowering must agree on this distinction.
pub fn isPlace(program: typed.Program, id: typed.NodeId) bool {
    return switch (program.nodes[@backingInt(id)].data) {
        .local => true,
        .field => |field| isPlace(program, field.base),
        .index => |index| isPlace(program, index.base),
        else => false,
    };
}
