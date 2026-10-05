//! Operand conventions the builder and the emitter share on top of `ir.zig`'s shapes.

/// `list_get.data` of the read a `pop` starts with: a failing index is reported as the pop
/// of an empty list (`R_LIST_BOUNDS`, operation `pop`), as the old core does.
pub const pop_read: u64 = 1;
